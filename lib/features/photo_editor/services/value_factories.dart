import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../../data/models/weather_model.dart';

/// Builds visible-stamp text from detected data.
abstract final class StampValueFactory {
  static Map<StampField, String> locationFields(LocationModel? l, AppSettings s) {
    if (l == null) return {for (final f in _locationFields) f: ''};
    final street = [l.buildingNumber, l.street].whereType<String>().where((e) => e.isNotEmpty).join(' ');
    return {
      StampField.city: l.city ?? l.locality ?? '',
      StampField.area: l.area ?? l.subLocality ?? '',
      StampField.locality: l.locality ?? '',
      StampField.street: street,
      StampField.district: l.district ?? '',
      StampField.state: l.state ?? '',
      StampField.country: l.country ?? '',
      StampField.postalCode: l.postalCode ?? '',
      StampField.fullAddress: l.fullAddress ?? '',
      StampField.latitude: l.latitude == null ? '' : Fmt.latitude(l.latitude!, s.coordinateFormat),
      StampField.longitude: l.longitude == null ? '' : Fmt.longitude(l.longitude!, s.coordinateFormat),
      // Only say "unavailable" when there is a position but no altitude.
      StampField.altitude: l.hasCoordinates ? Fmt.altitude(l.altitude, s.altitudeUnit) : '',
      StampField.accuracy: l.accuracy == null ? '' : Fmt.accuracy(l.accuracy, s.distanceUnit),
    };
  }

  static const _locationFields = [
    StampField.city,
    StampField.area,
    StampField.locality,
    StampField.street,
    StampField.district,
    StampField.state,
    StampField.country,
    StampField.postalCode,
    StampField.fullAddress,
    StampField.latitude,
    StampField.longitude,
    StampField.altitude,
    StampField.accuracy,
  ];

  static Map<StampField, String> timeFields(DateTime t, AppSettings s) => {
        StampField.date: Fmt.date(t, s),
        StampField.time: Fmt.time(t, s),
      };

  static Map<StampField, String> weatherFields(WeatherModel? w, AppSettings s) => {
        StampField.weather: w?.description ?? '',
        StampField.temperature: w == null ? '' : Fmt.temperature(w.temperatureC, s.temperatureUnit),
      };

  static StampValues build({
    required LocationModel? location,
    required WeatherModel? weather,
    required DateTime time,
    required AppSettings settings,
    String note = '',
  }) {
    return StampValues(
      values: {
        ...timeFields(time, settings),
        ...locationFields(location, settings),
        ...weatherFields(weather, settings),
        StampField.note: note,
      },
      mapLatitude: location?.latitude,
      mapLongitude: location?.longitude,
    );
  }

  /// Formats EXIF values into stamp text (EXIF → stamp sync).
  static Map<StampField, String> fromExif(PhotoMetadataModel m, AppSettings s) => {
        if (m.latitude != null) StampField.latitude: Fmt.latitude(m.latitude!, s.coordinateFormat),
        if (m.longitude != null) StampField.longitude: Fmt.longitude(m.longitude!, s.coordinateFormat),
        if (m.hasGps) StampField.altitude: Fmt.altitude(m.altitude, s.altitudeUnit),
        if (m.dateTimeOriginal != null) ...timeFields(m.dateTimeOriginal!, s),
      };
}

/// Builds EXIF values from detected data.
abstract final class ExifValueFactory {
  /// GPS + time metadata for a location (the location's fix time is used for
  /// the UTC GPS date/time stamps when known).
  static (PhotoMetadataModel, Set<ExifField>) gpsFrom(LocationModel l, {DateTime? fallbackTime}) {
    final fixTime = (l.detectedAt ?? fallbackTime ?? DateTime.now()).toUtc();
    final m = PhotoMetadataModel(
      latitude: l.latitude,
      longitude: l.longitude,
      altitude: l.altitude,
      gpsDateStamp: _gpsDate(fixTime),
      gpsTimeStamp: _gpsTime(fixTime),
    );
    return (
      m,
      {
        ExifField.gpsCoordinates,
        if (l.altitude != null) ExifField.gpsAltitude,
        ExifField.gpsDateStamp,
        ExifField.gpsTimeStamp,
      }
    );
  }

  static String _gpsDate(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}:${utc.month.toString().padLeft(2, '0')}:${utc.day.toString().padLeft(2, '0')}';
  static String _gpsTime(DateTime utc) =>
      '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}:${utc.second.toString().padLeft(2, '0')}';

  static String gpsDate(DateTime t) => _gpsDate(t.toUtc());
  static String gpsTime(DateTime t) => _gpsTime(t.toUtc());

  /// Metadata written into a freshly captured original.
  static (PhotoMetadataModel, Set<ExifField>) forCapture({
    required PhotoMetadataModel existing,
    required LocationModel? location,
    required DateTime capturedAt,
    required AppSettings settings,
  }) {
    var m = PhotoMetadataModel(
      dateTimeOriginal: existing.dateTimeOriginal ?? capturedAt,
      dateTimeDigitized: existing.dateTimeDigitized ?? capturedAt,
      offsetTime: existing.offsetTime ?? PhotoMetadataModel.formatOffset(capturedAt.timeZoneOffset),
      artist: settings.defaultArtist.isEmpty ? null : settings.defaultArtist,
      copyright: settings.defaultCopyright.isEmpty ? null : settings.defaultCopyright,
    );
    final fields = <ExifField>{
      if (existing.dateTimeOriginal == null) ExifField.dateTimeOriginal,
      if (existing.dateTimeDigitized == null) ExifField.dateTimeDigitized,
      if (existing.offsetTime == null) ExifField.offsetTime,
      if (settings.defaultArtist.isNotEmpty) ExifField.artist,
      if (settings.defaultCopyright.isNotEmpty) ExifField.copyright,
    };
    if (settings.saveLocationInExif && location != null && location.hasCoordinates) {
      final (gps, gpsFields) = gpsFrom(location, fallbackTime: capturedAt);
      m = PhotoMetadataModel(
        dateTimeOriginal: m.dateTimeOriginal,
        dateTimeDigitized: m.dateTimeDigitized,
        offsetTime: m.offsetTime,
        artist: m.artist,
        copyright: m.copyright,
        latitude: gps.latitude,
        longitude: gps.longitude,
        altitude: gps.altitude,
        gpsDateStamp: gps.gpsDateStamp,
        gpsTimeStamp: gps.gpsTimeStamp,
      );
      fields.addAll(gpsFields);
    }
    return (m, fields);
  }
}
