import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/native_image_channel.dart';
import '../../../data/models/photo_metadata_model.dart';

/// Result of an EXIF write, after re-opening the file and verifying it.
class ExifWriteResult {
  const ExifWriteResult({
    required this.requested,
    required this.verified,
    required this.failures,
    required this.after,
    this.unsupported = false,
    this.message,
  });

  final Set<ExifField> requested;
  final Set<ExifField> verified;
  final Map<ExifField, String> failures;

  /// Metadata as re-read from disk after the write.
  final PhotoMetadataModel? after;
  final bool unsupported;
  final String? message;

  bool get success => !unsupported && failures.isEmpty && verified.length == requested.length;
  bool get partial => !unsupported && verified.isNotEmpty && failures.isNotEmpty;

  String get summary {
    if (requested.isEmpty) return 'No metadata changes.';
    if (unsupported) return message ?? 'This image format does not support EXIF writing on this device.';
    if (success) return 'Metadata written and verified (${verified.length} field${verified.length == 1 ? '' : 's'}).';
    final failed = failures.entries.map((e) => '${e.key.label}: ${e.value}').join('\n');
    return verified.isEmpty ? 'Metadata was not written.\n$failed' : 'Some fields could not be written:\n$failed';
  }
}

/// EXIF read/write abstraction. Writing is delegated to native code
/// (ExifInterface on Android, ImageIO on iOS) and always verified by reading
/// the saved file back.
class ExifService {
  ExifService(this._native);

  final NativeImageChannel _native;

  Future<PhotoMetadataModel> read(String path) async {
    if (!await File(path).exists()) {
      throw AppException(AppErrorKind.exifRead, 'File not found: $path');
    }
    try {
      return PhotoMetadataModel.fromNative(await _native.readMetadata(path));
    } on PlatformException catch (e) {
      throw AppException.from(e, fallback: AppErrorKind.exifRead, context: 'Could not read metadata');
    } on MissingPluginException catch (e) {
      throw AppException(AppErrorKind.exifRead, 'Metadata reading is not available on this platform.', cause: e);
    }
  }

  static bool _isAscii(String s) => s.codeUnits.every((c) => c >= 0x20 && c < 0x7F);

  static Map<String, Object?> _wire(ExifField f, PhotoMetadataModel m) {
    switch (f) {
      case ExifField.gpsCoordinates:
        return m.hasGps
            ? {'gpsLatitude': m.latitude, 'gpsLongitude': m.longitude}
            : {'gpsLatitude': null, 'gpsLongitude': null};
      case ExifField.gpsAltitude:
        return {'gpsAltitude': m.altitude};
      case ExifField.offsetTime:
        return {
          'offsetTimeOriginal': m.offsetTime,
          'offsetTimeDigitized': m.offsetTime,
          'offsetTime': m.offsetTime,
        };
      case ExifField.dateTimeOriginal:
        return {'dateTimeOriginal': m.wireValue(f)};
      case ExifField.dateTimeDigitized:
        return {'dateTimeDigitized': m.wireValue(f)};
      case ExifField.dateTime:
        return {'dateTime': m.wireValue(f)};
      case ExifField.gpsDateStamp:
        return {'gpsDateStamp': m.gpsDateStamp};
      case ExifField.gpsTimeStamp:
        return {'gpsTimeStamp': m.gpsTimeStamp};
      case ExifField.imageDescription:
        return {'imageDescription': m.imageDescription};
      case ExifField.artist:
        return {'artist': m.artist};
      case ExifField.copyright:
        return {'copyright': m.copyright};
      case ExifField.userComment:
        return {'userComment': m.userComment};
    }
  }

  /// Validates a value before writing. Returns an error message or null.
  static String? validate(ExifField f, PhotoMetadataModel m) {
    switch (f) {
      case ExifField.gpsCoordinates:
        if ((m.latitude == null) != (m.longitude == null)) return 'Latitude and longitude must both be set.';
        if (m.latitude != null && m.latitude!.abs() > 90) return 'Latitude must be between -90 and 90.';
        if (m.longitude != null && m.longitude!.abs() > 180) return 'Longitude must be between -180 and 180.';
      case ExifField.offsetTime:
        if (m.offsetTime != null && !PhotoMetadataModel.isValidOffset(m.offsetTime!)) {
          return 'Use the form +HH:MM, e.g. +05:30.';
        }
      case ExifField.gpsDateStamp:
        if (m.gpsDateStamp != null && !RegExp(r'^\d{4}:\d{2}:\d{2}$').hasMatch(m.gpsDateStamp!)) {
          return 'Use the form YYYY:MM:DD.';
        }
      case ExifField.gpsTimeStamp:
        if (m.gpsTimeStamp != null && !RegExp(r'^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$').hasMatch(m.gpsTimeStamp!)) {
          return 'Use the form HH:MM:SS (24 h, UTC).';
        }
      case ExifField.imageDescription || ExifField.artist || ExifField.copyright || ExifField.userComment:
        final v = switch (f) {
          ExifField.imageDescription => m.imageDescription,
          ExifField.artist => m.artist,
          ExifField.copyright => m.copyright,
          _ => m.userComment,
        };
        if (v != null && !_isAscii(v)) {
          return 'EXIF stores this field as plain ASCII text; remove accented or non-Latin characters.';
        }
      default:
        break;
    }
    return null;
  }

  /// Writes [fields] of [desired] into the file at [path] and verifies them.
  Future<ExifWriteResult> write(String path, PhotoMetadataModel desired, Set<ExifField> fields) async {
    if (fields.isEmpty) {
      return ExifWriteResult(requested: const {}, verified: const {}, failures: const {}, after: null);
    }
    final before = await read(path);
    if (!before.writeSupported) {
      return ExifWriteResult(
        requested: fields,
        verified: const {},
        failures: {for (final f in fields) f: 'unsupported format'},
        after: before,
        unsupported: true,
        message: 'EXIF metadata cannot be written to ${before.format?.toUpperCase() ?? 'this'} files on this device. '
            'Stamp the photo (which exports a JPEG) or convert it to JPEG first.',
      );
    }

    final failures = <ExifField, String>{};
    final values = <String, Object?>{};
    for (final f in fields) {
      final err = validate(f, desired);
      if (err != null) {
        failures[f] = err;
      } else {
        values.addAll(_wire(f, desired));
      }
    }

    if (values.isNotEmpty) {
      try {
        await _native.writeMetadata(path, values);
      } on PlatformException catch (e) {
        final unsupported = e.code == 'UNSUPPORTED_FORMAT';
        return ExifWriteResult(
          requested: fields,
          verified: const {},
          failures: {for (final f in fields) f: failures[f] ?? (e.message ?? e.code)},
          after: before,
          unsupported: unsupported,
          message: unsupported ? e.message : null,
        );
      }
    }

    // Re-open the saved file and verify each requested field.
    final after = await read(path);
    final verified = <ExifField>{};
    for (final f in fields) {
      if (failures.containsKey(f)) continue;
      if (after.sameField(f, desired)) {
        verified.add(f);
      } else {
        failures[f] = 'value read back from the file does not match (got "${after.wireValue(f) ?? 'nothing'}")';
      }
    }
    return ExifWriteResult(requested: fields, verified: verified, failures: failures, after: after);
  }

  /// Creates a copy of [source] at [output] with all GPS metadata removed,
  /// then verifies that no coordinates remain.
  Future<void> stripGpsCopy(String source, String output) async {
    await _native.stripGpsCopy(source, output);
    final check = await read(output);
    if (check.hasGps) {
      throw const AppException(AppErrorKind.exifWrite, 'Location metadata could not be removed from the shared copy.');
    }
  }
}
