import 'package:intl/intl.dart';

/// EXIF fields this app can write. Latitude and longitude are written as one
/// unit ([gpsCoordinates]) because their reference tags must stay consistent.
enum ExifField {
  dateTimeOriginal('Date taken (DateTimeOriginal)'),
  dateTimeDigitized('DateTimeDigitized'),
  dateTime('DateTime (modified)'),
  offsetTime('Timezone offset (OffsetTime*)'),
  gpsCoordinates('GPS latitude / longitude'),
  gpsAltitude('GPS altitude'),
  gpsDateStamp('GPS date (UTC)'),
  gpsTimeStamp('GPS time (UTC)'),
  imageDescription('Image description'),
  artist('Artist / Author'),
  copyright('Copyright'),
  userComment('User comment');

  const ExifField(this.label);
  final String label;

  /// Fields stored as 7-bit ASCII in EXIF; other characters cannot be stored.
  bool get isAscii => this == imageDescription || this == artist || this == copyright;

  static ExifField? tryParse(String v) {
    for (final f in values) {
      if (f.name == v) return f;
    }
    return null;
  }
}

/// EXIF metadata of an image (the actual metadata stored inside the file),
/// kept separate from the visible stamp values.
class PhotoMetadataModel {
  const PhotoMetadataModel({
    this.dateTimeOriginal,
    this.dateTimeDigitized,
    this.dateTime,
    this.offsetTime,
    this.latitude,
    this.longitude,
    this.altitude,
    this.gpsDateStamp,
    this.gpsTimeStamp,
    this.imageDescription,
    this.artist,
    this.copyright,
    this.userComment,
    this.make,
    this.model,
    this.software,
    this.orientation,
    this.imageWidth,
    this.imageHeight,
    this.format,
    this.writeSupported = false,
    this.rawTags = const {},
  });

  /// Wall-clock capture time as stored in EXIF (no timezone; see [offsetTime]).
  final DateTime? dateTimeOriginal;
  final DateTime? dateTimeDigitized;
  final DateTime? dateTime;

  /// e.g. "+05:30" (EXIF 2.31 OffsetTimeOriginal).
  final String? offsetTime;

  /// Signed decimal degrees (negative = S / W).
  final double? latitude;
  final double? longitude;

  /// Signed metres (negative = below sea level).
  final double? altitude;

  /// "yyyy:MM:dd" in UTC.
  final String? gpsDateStamp;

  /// "HH:mm:ss" in UTC.
  final String? gpsTimeStamp;
  final String? imageDescription;
  final String? artist;
  final String? copyright;
  final String? userComment;

  // Read-only information
  final String? make;
  final String? model;
  final String? software;
  final int? orientation;
  final int? imageWidth;
  final int? imageHeight;

  /// Detected container format: jpeg, png, webp, heic, ...
  final String? format;

  /// Whether the platform can write EXIF into this file format.
  final bool writeSupported;

  /// All tags the native reader returned (for the "all tags" view).
  final Map<String, String> rawTags;

  String? get latitudeReference => latitude == null ? null : (latitude! >= 0 ? 'N' : 'S');
  String? get longitudeReference => longitude == null ? null : (longitude! >= 0 ? 'E' : 'W');

  /// 0 = above sea level, 1 = below sea level.
  int? get altitudeReference => altitude == null ? null : (altitude! >= 0 ? 0 : 1);
  bool get hasGps => latitude != null && longitude != null;

  static final _exifDate = DateFormat('yyyy:MM:dd HH:mm:ss');

  static String formatExifDate(DateTime d) => _exifDate.format(d);

  static DateTime? parseExifDate(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty || t.startsWith('0000')) return null;
    try {
      return _exifDate.parseStrict(t.length > 19 ? t.substring(0, 19) : t);
    } catch (_) {
      return DateTime.tryParse(t);
    }
  }

  /// Formats a [Duration] offset as "+HH:mm".
  static String formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final m = offset.inMinutes.abs();
    return '$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  static bool isValidOffset(String s) => RegExp(r'^[+-](0\d|1[0-4]):[0-5]\d$').hasMatch(s);

  /// Builds a metadata model from the map returned by the native channel.
  factory PhotoMetadataModel.fromNative(Map<dynamic, dynamic> m) {
    String? str(String k) {
      final v = m[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    double? dbl(String k) {
      final v = m[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int? integer(String k) {
      final v = m[k];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final raw = <String, String>{};
    final rawMap = m['rawTags'];
    if (rawMap is Map) {
      rawMap.forEach((k, v) {
        if (v != null) raw['$k'] = '$v';
      });
    }

    return PhotoMetadataModel(
      dateTimeOriginal: parseExifDate(str('dateTimeOriginal')),
      dateTimeDigitized: parseExifDate(str('dateTimeDigitized')),
      dateTime: parseExifDate(str('dateTime')),
      offsetTime: str('offsetTimeOriginal') ?? str('offsetTime'),
      latitude: dbl('gpsLatitude'),
      longitude: dbl('gpsLongitude'),
      altitude: dbl('gpsAltitude'),
      gpsDateStamp: str('gpsDateStamp'),
      gpsTimeStamp: _normalizeGpsTime(str('gpsTimeStamp')),
      imageDescription: str('imageDescription'),
      artist: str('artist'),
      copyright: str('copyright'),
      userComment: _cleanUserComment(str('userComment')),
      make: str('make'),
      model: str('model'),
      software: str('software'),
      orientation: integer('orientation'),
      imageWidth: integer('imageWidth'),
      imageHeight: integer('imageHeight'),
      format: str('format'),
      writeSupported: m['writeSupported'] == true,
      rawTags: raw,
    );
  }

  /// Strips the 8-byte character-code prefix some writers leave in UserComment.
  static String? _cleanUserComment(String? s) {
    if (s == null) return null;
    var t = s;
    for (final prefix in ['ASCII', 'UNICODE', 'JIS', 'UTF-8']) {
      if (t.startsWith(prefix)) {
        t = t.substring(prefix.length);
        break;
      }
    }
    t = t.replaceAll('\u0000', '').trim();
    return t.isEmpty ? null : t;
  }

  static String? _normalizeGpsTime(String? s) {
    if (s == null) return null;
    // Accept "HH:mm:ss", "HH:mm:ss.SS" or rational "h/1,m/1,s/1".
    if (s.contains('/')) {
      final parts = s.split(',');
      if (parts.length == 3) {
        final nums = parts.map((p) {
          final r = p.split('/');
          final n = double.tryParse(r[0]) ?? 0;
          final d = r.length > 1 ? (double.tryParse(r[1]) ?? 1) : 1;
          return d == 0 ? 0 : n / d;
        }).toList();
        return '${nums[0].floor().toString().padLeft(2, '0')}:'
            '${nums[1].floor().toString().padLeft(2, '0')}:'
            '${nums[2].floor().toString().padLeft(2, '0')}';
      }
    }
    return s.length >= 8 ? s.substring(0, 8) : s;
  }

  PhotoMetadataModel copyWith({
    DateTime? dateTimeOriginal,
    DateTime? dateTimeDigitized,
    DateTime? dateTime,
    String? offsetTime,
    double? latitude,
    double? longitude,
    double? altitude,
    String? gpsDateStamp,
    String? gpsTimeStamp,
    String? imageDescription,
    String? artist,
    String? copyright,
    String? userComment,
    Set<ExifField> clear = const {},
  }) {
    return PhotoMetadataModel(
      dateTimeOriginal: clear.contains(ExifField.dateTimeOriginal) ? null : dateTimeOriginal ?? this.dateTimeOriginal,
      dateTimeDigitized:
          clear.contains(ExifField.dateTimeDigitized) ? null : dateTimeDigitized ?? this.dateTimeDigitized,
      dateTime: clear.contains(ExifField.dateTime) ? null : dateTime ?? this.dateTime,
      offsetTime: clear.contains(ExifField.offsetTime) ? null : offsetTime ?? this.offsetTime,
      latitude: clear.contains(ExifField.gpsCoordinates) ? null : latitude ?? this.latitude,
      longitude: clear.contains(ExifField.gpsCoordinates) ? null : longitude ?? this.longitude,
      altitude: clear.contains(ExifField.gpsAltitude) ? null : altitude ?? this.altitude,
      gpsDateStamp: clear.contains(ExifField.gpsDateStamp) ? null : gpsDateStamp ?? this.gpsDateStamp,
      gpsTimeStamp: clear.contains(ExifField.gpsTimeStamp) ? null : gpsTimeStamp ?? this.gpsTimeStamp,
      imageDescription:
          clear.contains(ExifField.imageDescription) ? null : imageDescription ?? this.imageDescription,
      artist: clear.contains(ExifField.artist) ? null : artist ?? this.artist,
      copyright: clear.contains(ExifField.copyright) ? null : copyright ?? this.copyright,
      userComment: clear.contains(ExifField.userComment) ? null : userComment ?? this.userComment,
      make: make,
      model: model,
      software: software,
      orientation: orientation,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      format: format,
      writeSupported: writeSupported,
      rawTags: rawTags,
    );
  }

  /// Returns the value of an editable field in its wire form (as sent to the
  /// native writer), used for diffing and verification.
  Object? wireValue(ExifField f) => switch (f) {
        ExifField.dateTimeOriginal => dateTimeOriginal == null ? null : formatExifDate(dateTimeOriginal!),
        ExifField.dateTimeDigitized => dateTimeDigitized == null ? null : formatExifDate(dateTimeDigitized!),
        ExifField.dateTime => dateTime == null ? null : formatExifDate(dateTime!),
        ExifField.offsetTime => offsetTime,
        ExifField.gpsCoordinates => hasGps ? [latitude, longitude] : null,
        ExifField.gpsAltitude => altitude,
        ExifField.gpsDateStamp => gpsDateStamp,
        ExifField.gpsTimeStamp => gpsTimeStamp,
        ExifField.imageDescription => imageDescription,
        ExifField.artist => artist,
        ExifField.copyright => copyright,
        ExifField.userComment => userComment,
      };

  /// Whether [f] holds the same value in both models (with numeric tolerance).
  bool sameField(ExifField f, PhotoMetadataModel other) {
    switch (f) {
      case ExifField.gpsCoordinates:
        if (hasGps != other.hasGps) return false;
        if (!hasGps) return true;
        return (latitude! - other.latitude!).abs() < 1e-6 && (longitude! - other.longitude!).abs() < 1e-6;
      case ExifField.gpsAltitude:
        if ((altitude == null) != (other.altitude == null)) return false;
        if (altitude == null) return true;
        return (altitude! - other.altitude!).abs() < 0.05;
      default:
        final a = wireValue(f);
        final b = other.wireValue(f);
        return (a?.toString().trim() ?? '') == (b?.toString().trim() ?? '');
    }
  }

  /// Serialises only the editable fields (used to persist user EXIF edits).
  Map<String, dynamic> toJson() => {
        'dateTimeOriginal': dateTimeOriginal?.toIso8601String(),
        'dateTimeDigitized': dateTimeDigitized?.toIso8601String(),
        'dateTime': dateTime?.toIso8601String(),
        'offsetTime': offsetTime,
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'gpsDateStamp': gpsDateStamp,
        'gpsTimeStamp': gpsTimeStamp,
        'imageDescription': imageDescription,
        'artist': artist,
        'copyright': copyright,
        'userComment': userComment,
        'make': make,
        'model': model,
        'orientation': orientation,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'format': format,
        'writeSupported': writeSupported,
      };

  factory PhotoMetadataModel.fromJson(Map<String, dynamic> j) => PhotoMetadataModel(
        dateTimeOriginal: DateTime.tryParse(j['dateTimeOriginal'] as String? ?? ''),
        dateTimeDigitized: DateTime.tryParse(j['dateTimeDigitized'] as String? ?? ''),
        dateTime: DateTime.tryParse(j['dateTime'] as String? ?? ''),
        offsetTime: j['offsetTime'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        altitude: (j['altitude'] as num?)?.toDouble(),
        gpsDateStamp: j['gpsDateStamp'] as String?,
        gpsTimeStamp: j['gpsTimeStamp'] as String?,
        imageDescription: j['imageDescription'] as String?,
        artist: j['artist'] as String?,
        copyright: j['copyright'] as String?,
        userComment: j['userComment'] as String?,
        make: j['make'] as String?,
        model: j['model'] as String?,
        orientation: (j['orientation'] as num?)?.toInt(),
        imageWidth: (j['imageWidth'] as num?)?.toInt(),
        imageHeight: (j['imageHeight'] as num?)?.toInt(),
        format: j['format'] as String?,
        writeSupported: j['writeSupported'] as bool? ?? false,
      );
}
