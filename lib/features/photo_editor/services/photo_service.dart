import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/file_storage_service.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../../data/models/weather_model.dart';
import '../../exif_editor/services/exif_service.dart';
import '../../stamp_editor/services/image_render_service.dart';
import 'value_factories.dart';

class PhotoOpResult {
  const PhotoOpResult(this.photo, {this.exif, this.warnings = const []});
  final PhotoModel photo;
  final ExifWriteResult? exif;
  final List<String> warnings;
}

/// Everything needed to (re)generate a photo's edited file.
class EditRequest {
  const EditRequest({
    required this.stampValues,
    required this.style,
    required this.applyStamp,
    required this.exifDesired,
    required this.exifOverrides,
    this.rerender = true,
    this.asNew = false,
    this.detectedLocation,
  });

  final StampValues stampValues;
  final StampTemplateModel style;
  final bool applyStamp;

  /// Desired EXIF values; only [exifOverrides] fields are written.
  final PhotoMetadataModel exifDesired;

  /// Complete set of user-overridden EXIF fields for this photo.
  final Set<ExifField> exifOverrides;

  /// Re-render the stamp from the original (false = reuse the current edited
  /// pixels and only rewrite metadata).
  final bool rerender;
  final bool asNew;
  final LocationModel? detectedLocation;
}

/// Orchestrates capture, import, editing, sharing and exporting of photos.
/// All processing is local; nothing is uploaded.
class PhotoService {
  PhotoService(this.ref);

  final Ref ref;
  static const _uuid = Uuid();
  static const deviceAlbum = 'GPS Camera';

  FileStorageService get _storage => ref.read(storageProvider);
  ExifService get _exif => ref.read(exifServiceProvider);
  ImageRenderService get _render => ref.read(renderServiceProvider);
  AppSettings get _settings => ref.read(settingsProvider);

  // ----------------------------------------------------------------- helpers

  /// Loads the map snapshot for a stamp, or returns a warning explaining why not.
  Future<(ui.Image?, String?)> loadMap(StampTemplateModel style, StampValues values) async {
    if (!style.includesMap) return (null, null);
    if (!values.hasMapLocation) return (null, 'Map snapshot skipped: the photo has no coordinates.');
    try {
      final img = await ref.read(mapSnapshotServiceProvider).snapshot(
            values.mapLatitude!,
            values.mapLongitude!,
            zoom: style.mapZoom,
            onlineAllowed: _settings.onlineAllowed,
            online: ref.read(isOnlineProvider),
          );
      return (img, null);
    } on AppException catch (e) {
      return (null, '${e.message} The photo was saved without the map.');
    }
  }

  Future<void> _thumb(String source, String target) async {
    try {
      await _render.thumbnail(source, target);
    } catch (_) {
      // Thumbnails are optional; the gallery falls back to the full image.
    }
  }

  static String _ext(String path) {
    final e = p.extension(path).toLowerCase();
    return e.isEmpty ? '.jpg' : e;
  }

  Future<PhotoMetadataModel?> _tryRead(String path) async {
    try {
      return await _exif.read(path);
    } catch (_) {
      return null;
    }
  }

  /// "Effective" denormalised values for listing/search.
  PhotoModel _denormalise(PhotoModel m, PhotoMetadataModel? displayExif) {
    final v = m.stampValues;
    String? pick(StampField f, String? fallback) {
      final s = v?[f].trim();
      return (s != null && s.isNotEmpty) ? s : fallback;
    }

    final d = m.detectedLocation;
    final hasGps = displayExif?.hasGps ?? false;
    return PhotoModel(
      id: m.id,
      originalFilePath: m.originalFilePath,
      editedFilePath: m.editedFilePath,
      thumbnailPath: m.thumbnailPath,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
      capturedAt: m.capturedAt,
      latitude: hasGps ? displayExif!.latitude : null,
      longitude: hasGps ? displayExif!.longitude : null,
      altitude: hasGps ? displayExif!.altitude : null,
      gpsAccuracy: d?.accuracy,
      address: pick(StampField.fullAddress, d?.fullAddress),
      city: pick(StampField.city, d?.city),
      area: pick(StampField.area, d?.area),
      state: pick(StampField.state, d?.state),
      country: pick(StampField.country, d?.country),
      stampTemplateId: m.stampTemplateId,
      hasVisibleStamp: m.hasVisibleStamp,
      hasExifMetadata: hasGps,
      isOriginalPreserved: m.isOriginalPreserved,
      imageWidth: m.imageWidth,
      imageHeight: m.imageHeight,
      fileSize: m.fileSize,
      source: m.source,
      detectedLocation: m.detectedLocation,
      detectedWeather: m.detectedWeather,
      stampValues: m.stampValues,
      stampStyle: m.stampStyle,
      exifEdits: m.exifEdits,
      exifOverrides: m.exifOverrides,
      originalExif: m.originalExif,
      exifStatus: m.exifStatus,
      exifStatusMessage: m.exifStatusMessage,
      addressPending: m.addressPending,
      addressResolvedLater: m.addressResolvedLater,
      originalFileName: m.originalFileName,
    );
  }

  // ----------------------------------------------------------------- capture

  /// Stores a camera capture: preserves the original, writes capture EXIF,
  /// optionally renders the stamp, and creates the record.
  Future<PhotoOpResult> processCapture({
    required XFile shot,
    required LocationModel? location,
    required WeatherModel? weather,
    required StampTemplateModel template,
    required DateTime capturedAt,
  }) async {
    final s = _settings;
    final warnings = <String>[];
    final id = _uuid.v4();
    final originalPath = _storage.originalPath(id, _ext(shot.path));
    try {
      await shot.saveTo(originalPath);
    } catch (e) {
      throw AppException.from(e, fallback: AppErrorKind.storage, context: 'Could not save the photo');
    }
    await FileStorageService.deleteQuietly(shot.path);

    // Capture metadata on the original (date/time, GPS if enabled).
    final before = await _tryRead(originalPath) ?? const PhotoMetadataModel();
    var status = ExifStatus.untouched;
    String? statusMsg;
    if (before.writeSupported) {
      final (desired, fields) =
          ExifValueFactory.forCapture(existing: before, location: location, capturedAt: capturedAt, settings: s);
      final res = await _exif.write(originalPath, desired, fields);
      if (fields.isNotEmpty) {
        status = res.success ? ExifStatus.verified : (res.partial ? ExifStatus.partial : ExifStatus.failed);
        statusMsg = res.success ? 'Capture metadata written and verified.' : res.summary;
        if (!res.success) warnings.add(res.summary);
      }
    } else {
      status = ExifStatus.unsupported;
      statusMsg = 'This capture format does not support EXIF writing on this device.';
      warnings.add(statusMsg);
    }
    final originalExif = await _tryRead(originalPath);
    final dims = await ImageRenderService.imageSize(originalPath);

    final stampValues = StampValueFactory.build(location: location, weather: weather, time: capturedAt, settings: s);
    var record = PhotoModel(
      id: id,
      originalFilePath: originalPath,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      capturedAt: capturedAt,
      stampTemplateId: template.id,
      source: PhotoSource.camera,
      detectedLocation: location,
      detectedWeather: weather,
      stampValues: stampValues,
      stampStyle: template,
      originalExif: originalExif,
      exifStatus: status,
      exifStatusMessage: statusMsg,
      imageWidth: dims.width.round(),
      imageHeight: dims.height.round(),
      fileSize: await File(originalPath).length(),
      addressPending: location != null && location.hasCoordinates && !location.addressResolved,
      isOriginalPreserved: true,
    );

    if (s.autoStamp) {
      final (map, mapWarning) = await loadMap(template, stampValues);
      if (mapWarning != null) warnings.add(mapWarning);
      final out = _storage.editedPath(id);
      try {
        final r = await _render.renderStamped(
          sourcePath: originalPath,
          outputPath: out,
          template: template,
          values: stampValues,
          map: map,
          quality: s.exportQuality,
          sourceOrientation: originalExif?.orientation,
          rawWidth: originalExif?.imageWidth,
          rawHeight: originalExif?.imageHeight,
        );
        record = record.copyWith(
          editedFilePath: out,
          hasVisibleStamp: true,
          imageWidth: r.width,
          imageHeight: r.height,
          fileSize: r.fileSize,
        );
        if (r.downscaled) warnings.add('The stamped copy was limited to ${ImageRenderService.maxDimension}px.');
      } on AppException catch (e) {
        warnings.add('${e.message} The unstamped photo was kept.');
      } finally {
        map?.dispose();
      }
    }

    final thumb = _storage.thumbnailPath(id);
    await _thumb(record.displayPath, thumb);
    record = _denormalise(record.copyWith(thumbnailPath: thumb), await _tryRead(record.displayPath));
    await ref.read(photoRepositoryProvider).upsert(record);
    return PhotoOpResult(record, warnings: warnings);
  }

  // ----------------------------------------------------------------- import

  /// Imports an existing image file (copied, never moved) for viewing/editing.
  Future<PhotoModel> importFile(String sourcePath, {String? originalName}) async {
    final s = _settings;
    final id = _uuid.v4();
    final originalPath = _storage.originalPath(id, _ext(originalName ?? sourcePath));
    await File(sourcePath).copy(originalPath);
    final exif = await _tryRead(originalPath);
    final dims = await ImageRenderService.imageSize(originalPath);
    final captured = exif?.dateTimeOriginal ?? exif?.dateTime ?? (await File(originalPath).lastModified());

    LocationModel? location;
    if (exif != null && exif.hasGps) {
      location = LocationModel(
        latitude: exif.latitude,
        longitude: exif.longitude,
        altitude: exif.altitude,
        detectedAt: captured,
        source: LocationSource.exif,
      );
      final cached = await ref.read(geocodingRepositoryProvider).cached(exif.latitude!, exif.longitude!);
      if (cached != null) location = location.withAddress(cached);
    }
    final thumb = _storage.thumbnailPath(id);
    await _thumb(originalPath, thumb);
    final record = PhotoModel(
      id: id,
      originalFilePath: originalPath,
      thumbnailPath: thumb,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      capturedAt: captured,
      source: PhotoSource.imported,
      detectedLocation: location,
      stampValues: StampValueFactory.build(location: location, weather: null, time: captured, settings: s),
      stampStyle: ref.read(defaultTemplateProvider),
      stampTemplateId: s.defaultTemplateId,
      originalExif: exif,
      exifStatus: exif == null
          ? ExifStatus.unsupported
          : (exif.writeSupported ? ExifStatus.untouched : ExifStatus.unsupported),
      exifStatusMessage: exif == null ? 'Metadata could not be read from this file.' : null,
      imageWidth: dims.width.round(),
      imageHeight: dims.height.round(),
      fileSize: await File(originalPath).length(),
      addressPending: location != null && !location.addressResolved,
      originalFileName: originalName ?? p.basename(sourcePath),
    );
    final out = _denormalise(record, exif);
    await ref.read(photoRepositoryProvider).upsert(out);
    return out;
  }

  // ----------------------------------------------------------------- edit

  /// Regenerates the edited file from the preserved original according to
  /// [req], applies EXIF overrides and verifies them.
  Future<PhotoOpResult> saveEdits(PhotoModel photo, EditRequest req) async {
    final s = _settings;
    final warnings = <String>[];
    final now = DateTime.now();
    final id = req.asNew ? _uuid.v4() : photo.id;

    // Base pixels: the preserved original, or the current file when the
    // original was not kept.
    final base = photo.isOriginalPreserved ? photo.originalFilePath : photo.displayPath;
    var originalPath = photo.originalFilePath;
    if (req.asNew) {
      originalPath = _storage.originalPath(id, _ext(base));
      await File(base).copy(originalPath);
    }
    final baseForRender = req.asNew ? originalPath : base;

    String? out;
    var hasStamp = photo.hasVisibleStamp;
    int? width = photo.imageWidth, height = photo.imageHeight;

    if (req.applyStamp && (req.rerender || photo.editedFilePath == null) && photo.isOriginalPreserved) {
      out = _storage.editedPath(id);
      final (map, mapWarning) = await loadMap(req.style, req.stampValues);
      if (mapWarning != null) warnings.add(mapWarning);
      final srcExif = await _tryRead(baseForRender);
      try {
        final r = await _render.renderStamped(
          sourcePath: baseForRender,
          outputPath: out,
          template: req.style,
          values: req.stampValues,
          map: map,
          quality: s.exportQuality,
          sourceOrientation: srcExif?.orientation,
          rawWidth: srcExif?.imageWidth,
          rawHeight: srcExif?.imageHeight,
        );
        width = r.width;
        height = r.height;
        hasStamp = true;
      } finally {
        map?.dispose();
      }
    } else if (req.applyStamp && photo.editedFilePath != null) {
      // Keep the existing stamped pixels, rewrite metadata on a fresh copy.
      out = _storage.editedPath(id);
      await File(photo.editedFilePath!).copy(out);
      if (!photo.isOriginalPreserved && req.rerender) {
        warnings.add('The original was not preserved, so the stamp could not be re-rendered.');
      }
    } else if (!req.applyStamp && req.exifOverrides.isNotEmpty) {
      out = _storage.editedPath(id);
      await File(baseForRender).copy(out);
      hasStamp = !photo.isOriginalPreserved && photo.hasVisibleStamp;
    } else {
      hasStamp = !photo.isOriginalPreserved && photo.hasVisibleStamp;
    }

    // Apply EXIF overrides to the new file and verify.
    ExifWriteResult? exifResult;
    var status = photo.exifStatus;
    String? statusMsg = photo.exifStatusMessage;
    if (out != null && req.exifOverrides.isNotEmpty) {
      exifResult = await _exif.write(out, req.exifDesired, req.exifOverrides);
      status = exifResult.success
          ? ExifStatus.verified
          : exifResult.unsupported
              ? ExifStatus.unsupported
              : (exifResult.partial ? ExifStatus.partial : ExifStatus.failed);
      statusMsg = exifResult.summary;
    } else if (req.exifOverrides.isEmpty && out == null) {
      status = photo.source == PhotoSource.camera ? photo.exifStatus : ExifStatus.untouched;
    }

    final display = out ?? (req.asNew ? originalPath : photo.originalFilePath);
    final displayExif = await _tryRead(display);
    final thumb = _storage.thumbnailPath(id);
    await _thumb(display, thumb);

    var record = PhotoModel(
      id: id,
      originalFilePath: originalPath,
      editedFilePath: out,
      thumbnailPath: thumb,
      createdAt: req.asNew ? now : photo.createdAt,
      updatedAt: now,
      capturedAt: photo.capturedAt,
      stampTemplateId: req.style.id,
      hasVisibleStamp: hasStamp,
      isOriginalPreserved: photo.isOriginalPreserved,
      imageWidth: width,
      imageHeight: height,
      fileSize: await File(display).length(),
      source: req.asNew ? PhotoSource.copy : photo.source,
      detectedLocation: req.detectedLocation ?? photo.detectedLocation,
      detectedWeather: photo.detectedWeather,
      stampValues: req.stampValues,
      stampStyle: req.style,
      exifEdits: req.exifDesired,
      exifOverrides: req.exifOverrides,
      originalExif: photo.originalExif,
      exifStatus: status,
      exifStatusMessage: statusMsg,
      addressPending: photo.addressPending,
      addressResolvedLater: photo.addressResolvedLater,
      originalFileName: photo.originalFileName,
    );

    // Honour "Original image preservation = off".
    if (!s.preserveOriginals && out != null && record.isOriginalPreserved) {
      await FileStorageService.deleteQuietly(originalPath);
      record = record.copyWith(originalFilePath: out, isOriginalPreserved: false);
    }

    record = _denormalise(record, displayExif);
    await ref.read(photoRepositoryProvider).upsert(record);

    // Clean up files replaced by this save (never the preserved original).
    if (!req.asNew) {
      if (photo.editedFilePath != null && photo.editedFilePath != out && photo.editedFilePath != record.originalFilePath) {
        await FileStorageService.deleteQuietly(photo.editedFilePath);
      }
      if (photo.thumbnailPath != thumb) await FileStorageService.deleteQuietly(photo.thumbnailPath);
    }
    return PhotoOpResult(record, exif: exifResult, warnings: warnings);
  }

  /// Saves record-only changes (no file regeneration).
  Future<void> updateRecord(PhotoModel photo) =>
      ref.read(photoRepositoryProvider).upsert(photo.copyWith(updatedAt: DateTime.now()));

  // ----------------------------------------------------------------- copy / delete

  Future<PhotoModel> duplicate(PhotoModel photo) async {
    final id = _uuid.v4();
    final orig = _storage.originalPath(id, _ext(photo.originalFilePath));
    await File(photo.originalFilePath).copy(orig);
    String? edited;
    if (photo.editedFilePath != null && photo.editedFilePath != photo.originalFilePath) {
      edited = _storage.editedPath(id);
      await File(photo.editedFilePath!).copy(edited);
    } else if (photo.editedFilePath != null) {
      edited = orig;
    }
    final thumb = _storage.thumbnailPath(id);
    await _thumb(edited ?? orig, thumb);
    final now = DateTime.now();
    final copy = PhotoModel.fromRow({
      ...photo.toRow(),
      'id': id,
      'original_file_path': orig,
      'edited_file_path': edited,
      'thumbnail_path': thumb,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
      'source': PhotoSource.copy.name,
    });
    await ref.read(photoRepositoryProvider).upsert(copy);
    return copy;
  }

  Future<void> delete(PhotoModel photo) => ref.read(photoRepositoryProvider).delete(photo);

  // ----------------------------------------------------------------- share / export

  String _niceName(PhotoModel photo, {String suffix = ''}) =>
      'GPSCamera_${DateFormat('yyyyMMdd_HHmmss').format(photo.capturedAt)}$suffix${_ext(photo.displayPath)}';

  /// Shares the display files. When [stripLocation] is true, shared copies
  /// have their GPS metadata removed (the visible stamp is unaffected).
  Future<void> share(List<PhotoModel> photos, {required bool stripLocation}) async {
    await _storage.clearShareCache();
    final files = <XFile>[];
    var i = 0;
    for (final photo in photos) {
      final name = _niceName(photo, suffix: photos.length > 1 ? '_${++i}' : '');
      final target = _storage.sharePath(name);
      if (stripLocation) {
        final meta = await _tryRead(photo.displayPath);
        if (meta != null && meta.hasGps && !meta.writeSupported) {
          throw AppException(AppErrorKind.unsupportedFormat,
              'Location metadata cannot be removed from ${meta.format?.toUpperCase()} files on this device.');
        }
        await _exif.stripGpsCopy(photo.displayPath, target);
      } else {
        await File(photo.displayPath).copy(target);
      }
      files.add(XFile(target, mimeType: 'image/jpeg', name: name));
    }
    await SharePlus.instance.share(ShareParams(files: files));
  }

  /// Saves a photo to the device photo library (album "GPS Camera").
  Future<void> exportToDevice(PhotoModel photo, {bool original = false}) async {
    try {
      if (!await Gal.hasPermission(toAlbum: true)) {
        final ok = await Gal.requestPermission(toAlbum: true);
        if (!ok) {
          throw const AppException(AppErrorKind.galleryPermission,
              'Photo library access was denied. Allow it in system settings to save photos to your gallery.');
        }
      }
      await Gal.putImage(original ? photo.originalFilePath : photo.displayPath, album: deviceAlbum);
    } on GalException catch (e) {
      throw AppException(
        e.type == GalExceptionType.permissionDenied ? AppErrorKind.galleryPermission : AppErrorKind.storage,
        e.type == GalExceptionType.notEnoughSpace
            ? 'Not enough storage space to save to the gallery.'
            : 'Could not save to the device gallery (${e.type.message}).',
        cause: e,
      );
    }
  }

  /// Saves new captures to the device gallery according to settings.
  Future<List<String>> autoExport(PhotoModel photo) async {
    final s = _settings;
    final warnings = <String>[];
    try {
      // The displayed version (stamped/edited, or the original if unedited).
      if (s.saveEditedToDevice) await exportToDevice(photo);
      // The unstamped original, unless it was already exported above.
      final originalAlreadySaved = s.saveEditedToDevice && !photo.isEdited;
      if (s.saveOriginalToDevice && photo.isOriginalPreserved && !originalAlreadySaved) {
        await exportToDevice(photo, original: true);
      }
    } on AppException catch (e) {
      warnings.add(e.message);
    }
    return warnings;
  }

  // ----------------------------------------------------------------- addresses

  /// Resolves addresses for photos captured offline. Only the *detected*
  /// location is updated; stamp text is never changed without the user.
  Future<int> resolvePendingAddresses() async {
    final s = _settings;
    if (!s.onlineAllowed || !ref.read(isOnlineProvider)) return 0;
    final repo = ref.read(photoRepositoryProvider);
    var count = 0;
    for (final photo in await repo.pendingAddress()) {
      final d = photo.detectedLocation;
      if (d == null || !d.hasCoordinates) continue;
      try {
        final addr = await ref.read(geocodingRepositoryProvider).reverse(d.latitude!, d.longitude!, s);
        final updated = photo.copyWith(
          detectedLocation: addr == null ? d : d.withAddress(addr),
          addressPending: false,
          addressResolvedLater: addr != null && !addr.isEmpty,
        );
        await repo.upsert(updated);
        count++;
      } on AppException catch (e) {
        if (e.kind == AppErrorKind.offline || e.kind == AppErrorKind.noConsent) break;
      }
    }
    return count;
  }
}

final photoServiceProvider = Provider<PhotoService>((ref) => PhotoService(ref));
