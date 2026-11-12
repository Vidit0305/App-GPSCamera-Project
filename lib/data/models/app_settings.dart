import 'package:flutter/material.dart';

enum CoordinateFormat {
  decimal('Decimal degrees', '12.971599° N'),
  dms('Degrees minutes seconds', '12°58\'17.8" N'),
  ddm('Degrees decimal minutes', '12°58.296\' N');

  const CoordinateFormat(this.label, this.example);
  final String label;
  final String example;
}

enum DistanceUnit { metric, imperial }

enum AltitudeUnit {
  metres('Metres (m)'),
  feet('Feet (ft)');

  const AltitudeUnit(this.label);
  final String label;
}

enum TemperatureUnit { celsius, fahrenheit }

enum GpsAccuracyPreference {
  high('High (GPS, more battery)'),
  balanced('Balanced'),
  low('Low power');

  const GpsAccuracyPreference(this.label);
  final String label;
}

enum GeocoderProvider {
  platform('Device geocoder (Google / Apple)'),
  nominatim('OpenStreetMap Nominatim');

  const GeocoderProvider(this.label);
  final String label;
}

enum CaptureResolution {
  medium('Medium (~480p)'),
  high('High (~720p)'),
  veryHigh('Very high (~1080p)'),
  ultraHigh('Ultra high (~2160p)'),
  max('Maximum available');

  const CaptureResolution(this.label);
  final String label;
}

enum FlashSetting { off, auto, on }

enum LensSetting { back, front }

enum GallerySort {
  newest('Newest first'),
  oldest('Oldest first'),
  recentlyEdited('Recently edited'),
  largest('Largest files');

  const GallerySort(this.label);
  final String label;
}

/// Date formats the user can choose for stamps and the UI.
const dateFormatOptions = <String>['dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd', 'dd MMM yyyy', 'EEE, dd MMM yyyy'];

/// Locales used for date/number formatting and system UI text.
const supportedLocaleCodes = <String, String>{
  'system': 'System default',
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'pt': 'Português',
  'hi': 'हिन्दी',
  'ar': 'العربية',
  'zh': '中文',
  'ja': '日本語',
};

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.localeCode = 'system',
    this.dateFormat = 'dd/MM/yyyy',
    this.use24Hour = false,
    this.distanceUnit = DistanceUnit.metric,
    this.altitudeUnit = AltitudeUnit.metres,
    this.temperatureUnit = TemperatureUnit.celsius,
    this.coordinateFormat = CoordinateFormat.decimal,
    this.defaultLens = LensSetting.back,
    this.defaultFlash = FlashSetting.auto,
    this.resolution = CaptureResolution.max,
    this.jpegQuality = 92,
    this.exportQuality = 95,
    this.defaultTemplateId = 'builtin_classic',
    this.autoStamp = true,
    this.saveOriginalToDevice = false,
    this.saveEditedToDevice = true,
    this.gpsAccuracy = GpsAccuracyPreference.high,
    this.autoLocation = true,
    this.geocoderProvider = GeocoderProvider.platform,
    this.onlineConsent,
    this.fetchWeather = true,
    this.gallerySort = GallerySort.newest,
    this.saveLocationInExif = true,
    this.preserveOriginals = true,
    this.removeLocationOnShare = false,
    this.askBeforeShareLocation = true,
    this.defaultArtist = '',
    this.defaultCopyright = '',
    this.onboardingDone = false,
  });

  final ThemeMode themeMode;
  final String localeCode;
  final String dateFormat;
  final bool use24Hour;
  final DistanceUnit distanceUnit;
  final AltitudeUnit altitudeUnit;
  final TemperatureUnit temperatureUnit;
  final CoordinateFormat coordinateFormat;

  final LensSetting defaultLens;
  final FlashSetting defaultFlash;
  final CaptureResolution resolution;

  /// JPEG quality the camera captures with.
  final int jpegQuality;

  /// JPEG quality used when rendering stamped exports.
  final int exportQuality;
  final String defaultTemplateId;
  final bool autoStamp;
  final bool saveOriginalToDevice;
  final bool saveEditedToDevice;

  final GpsAccuracyPreference gpsAccuracy;
  final bool autoLocation;
  final GeocoderProvider geocoderProvider;

  /// Consent to send coordinates/search text to online services (reverse
  /// geocoding, search, map tiles, weather). Null = not asked yet.
  final bool? onlineConsent;
  final bool fetchWeather;

  final GallerySort gallerySort;

  /// Write GPS coordinates into the EXIF metadata of captured photos.
  final bool saveLocationInExif;

  /// Keep the unstamped original of every photo in app storage.
  final bool preserveOriginals;

  final bool removeLocationOnShare;
  final bool askBeforeShareLocation;
  final String defaultArtist;
  final String defaultCopyright;
  final bool onboardingDone;

  bool get onlineAllowed => onlineConsent == true;
  Locale? get locale => localeCode == 'system' ? null : Locale(localeCode);
  String get timeFormat => use24Hour ? 'HH:mm:ss' : 'hh:mm:ss a';

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? localeCode,
    String? dateFormat,
    bool? use24Hour,
    DistanceUnit? distanceUnit,
    AltitudeUnit? altitudeUnit,
    TemperatureUnit? temperatureUnit,
    CoordinateFormat? coordinateFormat,
    LensSetting? defaultLens,
    FlashSetting? defaultFlash,
    CaptureResolution? resolution,
    int? jpegQuality,
    int? exportQuality,
    String? defaultTemplateId,
    bool? autoStamp,
    bool? saveOriginalToDevice,
    bool? saveEditedToDevice,
    GpsAccuracyPreference? gpsAccuracy,
    bool? autoLocation,
    GeocoderProvider? geocoderProvider,
    bool? onlineConsent,
    bool? fetchWeather,
    GallerySort? gallerySort,
    bool? saveLocationInExif,
    bool? preserveOriginals,
    bool? removeLocationOnShare,
    bool? askBeforeShareLocation,
    String? defaultArtist,
    String? defaultCopyright,
    bool? onboardingDone,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode ?? this.localeCode,
      dateFormat: dateFormat ?? this.dateFormat,
      use24Hour: use24Hour ?? this.use24Hour,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      altitudeUnit: altitudeUnit ?? this.altitudeUnit,
      temperatureUnit: temperatureUnit ?? this.temperatureUnit,
      coordinateFormat: coordinateFormat ?? this.coordinateFormat,
      defaultLens: defaultLens ?? this.defaultLens,
      defaultFlash: defaultFlash ?? this.defaultFlash,
      resolution: resolution ?? this.resolution,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      exportQuality: exportQuality ?? this.exportQuality,
      defaultTemplateId: defaultTemplateId ?? this.defaultTemplateId,
      autoStamp: autoStamp ?? this.autoStamp,
      saveOriginalToDevice: saveOriginalToDevice ?? this.saveOriginalToDevice,
      saveEditedToDevice: saveEditedToDevice ?? this.saveEditedToDevice,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      autoLocation: autoLocation ?? this.autoLocation,
      geocoderProvider: geocoderProvider ?? this.geocoderProvider,
      onlineConsent: onlineConsent ?? this.onlineConsent,
      fetchWeather: fetchWeather ?? this.fetchWeather,
      gallerySort: gallerySort ?? this.gallerySort,
      saveLocationInExif: saveLocationInExif ?? this.saveLocationInExif,
      preserveOriginals: preserveOriginals ?? this.preserveOriginals,
      removeLocationOnShare: removeLocationOnShare ?? this.removeLocationOnShare,
      askBeforeShareLocation: askBeforeShareLocation ?? this.askBeforeShareLocation,
      defaultArtist: defaultArtist ?? this.defaultArtist,
      defaultCopyright: defaultCopyright ?? this.defaultCopyright,
      onboardingDone: onboardingDone ?? this.onboardingDone,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'localeCode': localeCode,
        'dateFormat': dateFormat,
        'use24Hour': use24Hour,
        'distanceUnit': distanceUnit.name,
        'altitudeUnit': altitudeUnit.name,
        'temperatureUnit': temperatureUnit.name,
        'coordinateFormat': coordinateFormat.name,
        'defaultLens': defaultLens.name,
        'defaultFlash': defaultFlash.name,
        'resolution': resolution.name,
        'jpegQuality': jpegQuality,
        'exportQuality': exportQuality,
        'defaultTemplateId': defaultTemplateId,
        'autoStamp': autoStamp,
        'saveOriginalToDevice': saveOriginalToDevice,
        'saveEditedToDevice': saveEditedToDevice,
        'gpsAccuracy': gpsAccuracy.name,
        'autoLocation': autoLocation,
        'geocoderProvider': geocoderProvider.name,
        'onlineConsent': onlineConsent,
        'fetchWeather': fetchWeather,
        'gallerySort': gallerySort.name,
        'saveLocationInExif': saveLocationInExif,
        'preserveOriginals': preserveOriginals,
        'removeLocationOnShare': removeLocationOnShare,
        'askBeforeShareLocation': askBeforeShareLocation,
        'defaultArtist': defaultArtist,
        'defaultCopyright': defaultCopyright,
        'onboardingDone': onboardingDone,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      themeMode: _enum(ThemeMode.values, j['themeMode'], d.themeMode),
      localeCode: supportedLocaleCodes.containsKey(j['localeCode']) ? j['localeCode'] as String : d.localeCode,
      dateFormat: dateFormatOptions.contains(j['dateFormat']) ? j['dateFormat'] as String : d.dateFormat,
      use24Hour: j['use24Hour'] as bool? ?? d.use24Hour,
      distanceUnit: _enum(DistanceUnit.values, j['distanceUnit'], d.distanceUnit),
      altitudeUnit: _enum(AltitudeUnit.values, j['altitudeUnit'], d.altitudeUnit),
      temperatureUnit: _enum(TemperatureUnit.values, j['temperatureUnit'], d.temperatureUnit),
      coordinateFormat: _enum(CoordinateFormat.values, j['coordinateFormat'], d.coordinateFormat),
      defaultLens: _enum(LensSetting.values, j['defaultLens'], d.defaultLens),
      defaultFlash: _enum(FlashSetting.values, j['defaultFlash'], d.defaultFlash),
      resolution: _enum(CaptureResolution.values, j['resolution'], d.resolution),
      jpegQuality: (j['jpegQuality'] as num?)?.toInt() ?? d.jpegQuality,
      exportQuality: (j['exportQuality'] as num?)?.toInt() ?? d.exportQuality,
      defaultTemplateId: j['defaultTemplateId'] as String? ?? d.defaultTemplateId,
      autoStamp: j['autoStamp'] as bool? ?? d.autoStamp,
      saveOriginalToDevice: j['saveOriginalToDevice'] as bool? ?? d.saveOriginalToDevice,
      saveEditedToDevice: j['saveEditedToDevice'] as bool? ?? d.saveEditedToDevice,
      gpsAccuracy: _enum(GpsAccuracyPreference.values, j['gpsAccuracy'], d.gpsAccuracy),
      autoLocation: j['autoLocation'] as bool? ?? d.autoLocation,
      geocoderProvider: _enum(GeocoderProvider.values, j['geocoderProvider'], d.geocoderProvider),
      onlineConsent: j['onlineConsent'] as bool?,
      fetchWeather: j['fetchWeather'] as bool? ?? d.fetchWeather,
      gallerySort: _enum(GallerySort.values, j['gallerySort'], d.gallerySort),
      saveLocationInExif: j['saveLocationInExif'] as bool? ?? d.saveLocationInExif,
      preserveOriginals: j['preserveOriginals'] as bool? ?? d.preserveOriginals,
      removeLocationOnShare: j['removeLocationOnShare'] as bool? ?? d.removeLocationOnShare,
      askBeforeShareLocation: j['askBeforeShareLocation'] as bool? ?? d.askBeforeShareLocation,
      defaultArtist: j['defaultArtist'] as String? ?? '',
      defaultCopyright: j['defaultCopyright'] as String? ?? '',
      onboardingDone: j['onboardingDone'] as bool? ?? false,
    );
  }
}
