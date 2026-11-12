/// Environment-based configuration. Values are injected at build time with
/// `--dart-define` or `--dart-define-from-file=env.json` (see env.example.json).
/// No API keys are stored in source code.
abstract final class Env {
  /// Base URL of a Nominatim-compatible geocoding API (OSM Nominatim,
  /// a self-hosted instance, or a compatible commercial service).
  static const geocoderBaseUrl = String.fromEnvironment(
    'GEOCODER_BASE_URL',
    defaultValue: 'https://nominatim.openstreetmap.org',
  );

  /// Optional API key, sent as the `key` query parameter (e.g. LocationIQ).
  static const geocoderApiKey = String.fromEnvironment('GEOCODER_API_KEY');

  /// Optional contact e-mail sent to Nominatim (`email` parameter) as required
  /// by its usage policy for heavy users.
  static const geocoderContactEmail = String.fromEnvironment('GEOCODER_CONTACT_EMAIL');

  /// Raster tile URL template used by the map screen and map snapshots.
  static const tileUrlTemplate = String.fromEnvironment(
    'TILE_URL_TEMPLATE',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Attribution displayed for the configured tile source.
  static const tileAttribution = String.fromEnvironment(
    'TILE_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// Open-Meteo compatible weather endpoint (no key required for the public API).
  static const weatherBaseUrl = String.fromEnvironment(
    'WEATHER_BASE_URL',
    defaultValue: 'https://api.open-meteo.com/v1/forecast',
  );

  /// Identifies the app to public OSM services, as their usage policies require.
  static const userAgent = 'GPSCamera/1.0 (Flutter app; com.gpscamera.gps_camera)';
  static const packageName = 'com.gpscamera.gps_camera';
}
