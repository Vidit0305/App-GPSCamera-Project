import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../photo_editor/services/photo_service.dart';
import '../../photo_editor/services/value_factories.dart';
import '../../templates/services/default_templates.dart';

/// Photo ids handed to the batch editor (e.g. from gallery multi-select).
class BatchPreselection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(Set<String> ids) => state = {...ids};
  void clear() => state = const {};
}

final batchPreselectionProvider = NotifierProvider<BatchPreselection, Set<String>>(BatchPreselection.new);

/// Changes to apply to every selected photo. Null = field not selected.
class BatchChanges {
  const BatchChanges({
    this.city,
    this.area,
    this.address,
    this.state,
    this.country,
    this.latitude,
    this.longitude,
    this.altitude,
    this.date,
    this.time,
    this.artist,
    this.copyright,
  });

  final String? city;
  final String? area;
  final String? address;
  final String? state;
  final String? country;
  final double? latitude;
  final double? longitude;

  /// Metres.
  final double? altitude;

  /// Only the date part is used.
  final DateTime? date;
  final ({int h, int m, int s})? time;
  final String? artist;
  final String? copyright;

  bool get hasLocationText => [city, area, address, state, country].any((e) => e != null);
  bool get hasCoordinates => latitude != null || longitude != null;
  bool get hasDateTime => date != null || time != null;
  bool get hasExif => hasCoordinates || altitude != null || hasDateTime || artist != null || copyright != null;
  bool get isEmpty => !hasLocationText && !hasExif;

  /// New capture date/time combined with [base] for the unchanged part.
  DateTime combineDateTime(DateTime base) {
    final d = date ?? base;
    return DateTime(
      d.year,
      d.month,
      d.day,
      time?.h ?? base.hour,
      time?.m ?? base.minute,
      time?.s ?? base.second,
    );
  }
}

class BatchItemResult {
  const BatchItemResult({required this.photo, required this.success, required this.message, this.result});

  final PhotoModel photo;
  final bool success;
  final String message;
  final PhotoModel? result;
}

/// Applies [BatchChanges] to one photo at a time (memory-safe for large batches).
class BatchService {
  BatchService(this.ref);

  final Ref ref;

  Future<BatchItemResult> applyTo(
    PhotoModel photo,
    BatchChanges c, {
    required bool saveAsNew,
    required bool updateStamp,
  }) async {
    try {
      final settings = ref.read(settingsProvider);
      final service = ref.read(photoServiceProvider);

      // Actual metadata of the current display file.
      PhotoMetadataModel current;
      try {
        current = await ref.read(exifServiceProvider).read(photo.displayPath);
      } catch (e) {
        if (c.hasExif) rethrow;
        current = const PhotoMetadataModel();
      }
      if (c.hasExif && !current.writeSupported && !photo.hasVisibleStamp) {
        return BatchItemResult(
          photo: photo,
          success: false,
          message: 'EXIF cannot be written to ${current.format?.toUpperCase() ?? 'this'} files on this device.',
        );
      }

      // ---------------------------------------------------------- EXIF
      final changed = <ExifField>{};
      double? lat, lon;
      if (c.hasCoordinates) {
        lat = c.latitude ?? current.latitude;
        lon = c.longitude ?? current.longitude;
        if (lat == null || lon == null) {
          return BatchItemResult(
            photo: photo,
            success: false,
            message: c.latitude == null
                ? 'Photo has no existing latitude to combine with the new longitude.'
                : 'Photo has no existing longitude to combine with the new latitude.',
          );
        }
        changed.add(ExifField.gpsCoordinates);
      }
      if (c.altitude != null) changed.add(ExifField.gpsAltitude);
      DateTime? newDateTime;
      if (c.hasDateTime) {
        newDateTime = c.combineDateTime(current.dateTimeOriginal ?? photo.capturedAt);
        changed.addAll({ExifField.dateTimeOriginal, ExifField.dateTimeDigitized});
      }
      if (c.artist != null) changed.add(ExifField.artist);
      if (c.copyright != null) changed.add(ExifField.copyright);

      // Start from what is actually in the file; fall back to the last saved
      // edits only when the file's metadata cannot be read/written.
      final base = current.writeSupported ? current : (photo.exifEdits ?? current);
      final desired = base.copyWith(
        latitude: lat,
        longitude: lon,
        altitude: c.altitude,
        dateTimeOriginal: newDateTime,
        dateTimeDigitized: newDateTime,
        artist: c.artist,
        copyright: c.copyright,
      );
      final overrides = {...photo.exifOverrides, ...changed};

      // ---------------------------------------------------------- stamp text
      final oldValues = photo.stampValues ??
          StampValueFactory.build(
            location: photo.detectedLocation,
            weather: photo.detectedWeather,
            time: photo.capturedAt,
            settings: settings,
          );
      var newValues = oldValues;
      if (updateStamp) {
        final m = <StampField, String>{
          if (c.city != null) StampField.city: c.city!,
          if (c.area != null) StampField.area: c.area!,
          if (c.address != null) StampField.fullAddress: c.address!,
          if (c.state != null) StampField.state: c.state!,
          if (c.country != null) StampField.country: c.country!,
          if (lat != null) StampField.latitude: Fmt.latitude(lat, settings.coordinateFormat),
          if (lon != null) StampField.longitude: Fmt.longitude(lon, settings.coordinateFormat),
          if (c.altitude != null) StampField.altitude: Fmt.altitude(c.altitude, settings.altitudeUnit),
          if (newDateTime != null) ...StampValueFactory.timeFields(newDateTime, settings),
        };
        newValues = oldValues.merge(m);
        if (lat != null && lon != null) newValues = newValues.withMapLocation(lat, lon);
      }

      final rerender = updateStamp && photo.hasVisibleStamp && photo.isOriginalPreserved;
      final needsFiles = c.hasExif || rerender;

      PhotoModel result;
      final notes = <String>[];
      if (needsFiles) {
        final style = photo.stampStyle ??
            ref.read(defaultTemplateProvider) ??
            DefaultTemplates.byId(settings.defaultTemplateId);
        final op = await service.saveEdits(
          photo,
          EditRequest(
            stampValues: newValues,
            style: style,
            applyStamp: photo.hasVisibleStamp,
            rerender: rerender,
            exifDesired: desired,
            exifOverrides: overrides,
            asNew: saveAsNew,
          ),
        );
        result = op.photo;
        notes.addAll(op.warnings);
        if (op.exif != null) {
          notes.insert(0, op.exif!.summary);
          if (!op.exif!.success) {
            return BatchItemResult(photo: photo, success: false, message: notes.join('\n'), result: result);
          }
        }
        if (updateStamp && photo.hasVisibleStamp && !photo.isOriginalPreserved && c.hasLocationText) {
          notes.add('Original not preserved: stamp text could not be re-rendered.');
        }
      } else {
        result = saveAsNew ? await service.duplicate(photo) : photo;
      }

      // Record-level location text (search / listing) and stamp values.
      if (c.hasLocationText || (!needsFiles && updateStamp)) {
        final updated = result.copyWith(
          stampValues: newValues,
          city: c.city,
          area: c.area,
          address: c.address,
          state: c.state,
          country: c.country,
        );
        await service.updateRecord(updated);
        result = updated;
      }

      if (notes.isEmpty) notes.add(saveAsNew ? 'Saved as a new copy.' : 'Updated.');
      return BatchItemResult(photo: photo, success: true, message: notes.join('\n'), result: result);
    } catch (e) {
      return BatchItemResult(
        photo: photo,
        success: false,
        message: AppException.from(e, fallback: AppErrorKind.exifWrite, context: 'Failed').message,
      );
    }
  }
}

final batchServiceProvider = Provider<BatchService>((ref) => BatchService(ref));
