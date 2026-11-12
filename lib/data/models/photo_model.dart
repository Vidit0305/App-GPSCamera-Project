import 'dart:convert';

import 'location_model.dart';
import 'photo_metadata_model.dart';
import 'stamp_template_model.dart';
import 'stamp_values.dart';
import 'weather_model.dart';

enum PhotoSource {
  camera('Camera'),
  imported('Imported'),
  copy('Copy');

  const PhotoSource(this.label);
  final String label;
}

/// Outcome of the last EXIF write, shown in the UI.
enum ExifStatus {
  /// Not written by this app yet (metadata as captured / imported).
  untouched,

  /// Written and verified by re-reading the saved file.
  verified,

  /// Some fields could not be written or verified.
  partial,

  /// The write failed.
  failed,

  /// The image format does not support EXIF writing on this platform.
  unsupported;

  static ExifStatus parse(String? v) =>
      ExifStatus.values.firstWhere((e) => e.name == v, orElse: () => ExifStatus.untouched);
}

/// A photo managed by the app.
///
/// Three independent sets of values are kept:
///  * [detectedLocation] / [detectedWeather] / [capturedAt]: what the device
///    detected (never overwritten by user edits),
///  * [stampValues] + [stampStyle]: the visible stamp text and design,
///  * [exifEdits] + [exifOverrides]: user-requested EXIF changes, re-applied
///    whenever the edited image is regenerated.
class PhotoModel {
  const PhotoModel({
    required this.id,
    required this.originalFilePath,
    this.editedFilePath,
    this.thumbnailPath,
    required this.createdAt,
    required this.updatedAt,
    required this.capturedAt,
    this.latitude,
    this.longitude,
    this.altitude,
    this.gpsAccuracy,
    this.address,
    this.city,
    this.area,
    this.state,
    this.country,
    this.stampTemplateId,
    this.hasVisibleStamp = false,
    this.hasExifMetadata = false,
    this.isOriginalPreserved = true,
    this.imageWidth,
    this.imageHeight,
    this.fileSize,
    this.source = PhotoSource.camera,
    this.detectedLocation,
    this.detectedWeather,
    this.stampValues,
    this.stampStyle,
    this.exifEdits,
    this.exifOverrides = const {},
    this.originalExif,
    this.exifStatus = ExifStatus.untouched,
    this.exifStatusMessage,
    this.addressPending = false,
    this.addressResolvedLater = false,
    this.originalFileName,
  });

  final String id;

  /// The preserved, unstamped original (as captured or imported).
  final String originalFilePath;

  /// Stamped and/or metadata-edited export. Null when no edits exist.
  final String? editedFilePath;
  final String? thumbnailPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime capturedAt;

  // Denormalised "effective" values used for listing, search and filters.
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? gpsAccuracy;
  final String? address;
  final String? city;
  final String? area;
  final String? state;
  final String? country;

  final String? stampTemplateId;
  final bool hasVisibleStamp;

  /// Whether the current display file carries GPS EXIF metadata.
  final bool hasExifMetadata;
  final bool isOriginalPreserved;
  final int? imageWidth;
  final int? imageHeight;
  final int? fileSize;

  final PhotoSource source;
  final LocationModel? detectedLocation;
  final WeatherModel? detectedWeather;
  final StampValues? stampValues;
  final StampTemplateModel? stampStyle;
  final PhotoMetadataModel? exifEdits;
  final Set<ExifField> exifOverrides;

  /// EXIF as first read from the original file (preserves original timestamps).
  final PhotoMetadataModel? originalExif;
  final ExifStatus exifStatus;
  final String? exifStatusMessage;

  /// Coordinates were saved but the address could not be resolved yet.
  final bool addressPending;

  /// The detected address was resolved after capture and has not been applied
  /// to the stamp (the user decides).
  final bool addressResolvedLater;
  final String? originalFileName;

  String get displayPath => editedFilePath ?? originalFilePath;
  bool get isEdited => editedFilePath != null;
  bool get hasGps => latitude != null && longitude != null;

  PhotoModel copyWith({
    String? id,
    String? originalFilePath,
    String? editedFilePath,
    bool clearEdited = false,
    String? thumbnailPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? capturedAt,
    double? latitude,
    double? longitude,
    double? altitude,
    double? gpsAccuracy,
    bool clearCoordinates = false,
    bool clearAltitude = false,
    String? address,
    String? city,
    String? area,
    String? state,
    String? country,
    String? stampTemplateId,
    bool? hasVisibleStamp,
    bool? hasExifMetadata,
    bool? isOriginalPreserved,
    int? imageWidth,
    int? imageHeight,
    int? fileSize,
    PhotoSource? source,
    LocationModel? detectedLocation,
    WeatherModel? detectedWeather,
    StampValues? stampValues,
    StampTemplateModel? stampStyle,
    PhotoMetadataModel? exifEdits,
    Set<ExifField>? exifOverrides,
    PhotoMetadataModel? originalExif,
    ExifStatus? exifStatus,
    String? exifStatusMessage,
    bool? addressPending,
    bool? addressResolvedLater,
  }) {
    return PhotoModel(
      id: id ?? this.id,
      originalFilePath: originalFilePath ?? this.originalFilePath,
      editedFilePath: clearEdited ? null : editedFilePath ?? this.editedFilePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      capturedAt: capturedAt ?? this.capturedAt,
      latitude: clearCoordinates ? null : latitude ?? this.latitude,
      longitude: clearCoordinates ? null : longitude ?? this.longitude,
      altitude: clearAltitude ? null : altitude ?? this.altitude,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      address: address ?? this.address,
      city: city ?? this.city,
      area: area ?? this.area,
      state: state ?? this.state,
      country: country ?? this.country,
      stampTemplateId: stampTemplateId ?? this.stampTemplateId,
      hasVisibleStamp: hasVisibleStamp ?? this.hasVisibleStamp,
      hasExifMetadata: hasExifMetadata ?? this.hasExifMetadata,
      isOriginalPreserved: isOriginalPreserved ?? this.isOriginalPreserved,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      fileSize: fileSize ?? this.fileSize,
      source: source ?? this.source,
      detectedLocation: detectedLocation ?? this.detectedLocation,
      detectedWeather: detectedWeather ?? this.detectedWeather,
      stampValues: stampValues ?? this.stampValues,
      stampStyle: stampStyle ?? this.stampStyle,
      exifEdits: exifEdits ?? this.exifEdits,
      exifOverrides: exifOverrides ?? this.exifOverrides,
      originalExif: originalExif ?? this.originalExif,
      exifStatus: exifStatus ?? this.exifStatus,
      exifStatusMessage: exifStatusMessage ?? this.exifStatusMessage,
      addressPending: addressPending ?? this.addressPending,
      addressResolvedLater: addressResolvedLater ?? this.addressResolvedLater,
      originalFileName: originalFileName,
    );
  }

  static String? _enc(Map<String, dynamic>? m) => m == null ? null : jsonEncode(m);
  static Map<String, dynamic>? _dec(Object? s) =>
      s is String && s.isNotEmpty ? jsonDecode(s) as Map<String, dynamic> : null;

  Map<String, Object?> toRow() => {
        'id': id,
        'original_file_path': originalFilePath,
        'edited_file_path': editedFilePath,
        'thumbnail_path': thumbnailPath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'captured_at': capturedAt.millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'gps_accuracy': gpsAccuracy,
        'address': address,
        'city': city,
        'area': area,
        'state': state,
        'country': country,
        'stamp_template_id': stampTemplateId,
        'has_visible_stamp': hasVisibleStamp ? 1 : 0,
        'has_exif_metadata': hasExifMetadata ? 1 : 0,
        'is_original_preserved': isOriginalPreserved ? 1 : 0,
        'image_width': imageWidth,
        'image_height': imageHeight,
        'file_size': fileSize,
        'source': source.name,
        'detected_location': _enc(detectedLocation?.toJson()),
        'detected_weather': _enc(detectedWeather?.toJson()),
        'stamp_values': _enc(stampValues?.toJson()),
        'stamp_style': _enc(stampStyle?.toJson()),
        'exif_edits': _enc(exifEdits?.toJson()),
        'exif_overrides': exifOverrides.map((e) => e.name).join(','),
        'original_exif': _enc(originalExif?.toJson()),
        'exif_status': exifStatus.name,
        'exif_status_message': exifStatusMessage,
        'address_pending': addressPending ? 1 : 0,
        'address_resolved_later': addressResolvedLater ? 1 : 0,
        'original_file_name': originalFileName,
        'search_text': [address, city, area, state, country, originalFileName, stampValues?[StampField.note]]
            .whereType<String>()
            .join(' ')
            .toLowerCase(),
      };

  factory PhotoModel.fromRow(Map<String, Object?> r) {
    DateTime t(String k) => DateTime.fromMillisecondsSinceEpoch(r[k] as int);
    double? d(String k) => (r[k] as num?)?.toDouble();
    final loc = _dec(r['detected_location']);
    final weather = _dec(r['detected_weather']);
    final stamp = _dec(r['stamp_values']);
    final style = _dec(r['stamp_style']);
    final exif = _dec(r['exif_edits']);
    final origExif = _dec(r['original_exif']);
    return PhotoModel(
      id: r['id'] as String,
      originalFilePath: r['original_file_path'] as String,
      editedFilePath: r['edited_file_path'] as String?,
      thumbnailPath: r['thumbnail_path'] as String?,
      createdAt: t('created_at'),
      updatedAt: t('updated_at'),
      capturedAt: t('captured_at'),
      latitude: d('latitude'),
      longitude: d('longitude'),
      altitude: d('altitude'),
      gpsAccuracy: d('gps_accuracy'),
      address: r['address'] as String?,
      city: r['city'] as String?,
      area: r['area'] as String?,
      state: r['state'] as String?,
      country: r['country'] as String?,
      stampTemplateId: r['stamp_template_id'] as String?,
      hasVisibleStamp: r['has_visible_stamp'] == 1,
      hasExifMetadata: r['has_exif_metadata'] == 1,
      isOriginalPreserved: r['is_original_preserved'] == 1,
      imageWidth: r['image_width'] as int?,
      imageHeight: r['image_height'] as int?,
      fileSize: r['file_size'] as int?,
      source: PhotoSource.values.firstWhere((e) => e.name == r['source'], orElse: () => PhotoSource.camera),
      detectedLocation: loc == null ? null : LocationModel.fromJson(loc),
      detectedWeather: weather == null ? null : WeatherModel.fromJson(weather),
      stampValues: stamp == null ? null : StampValues.fromJson(stamp),
      stampStyle: style == null ? null : StampTemplateModel.fromJson(style),
      exifEdits: exif == null ? null : PhotoMetadataModel.fromJson(exif),
      exifOverrides: {
        for (final n in ((r['exif_overrides'] as String?) ?? '').split(','))
          if (ExifField.tryParse(n) != null) ExifField.tryParse(n)!,
      },
      originalExif: origExif == null ? null : PhotoMetadataModel.fromJson(origExif),
      exifStatus: ExifStatus.parse(r['exif_status'] as String?),
      exifStatusMessage: r['exif_status_message'] as String?,
      addressPending: r['address_pending'] == 1,
      addressResolvedLater: r['address_resolved_later'] == 1,
      originalFileName: r['original_file_name'] as String?,
    );
  }
}
