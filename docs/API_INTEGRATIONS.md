# API integrations

GPS Camera works offline by default. Every network integration below is optional, needs the user's **online-services consent** (asked on first launch; stored as `AppSettings.onlineConsent`), and is configured at build time through `env.json` (see [env.example.json](../env.example.json)). No photo is ever uploaded.

| Integration | Sends | Used for | Code |
|---|---|---|---|
| Device geocoder (Google / Apple) | Coordinates, search text | Reverse geocoding, search | [platform_geocoding_provider.dart](../lib/data/remote/platform_geocoding_provider.dart) |
| Nominatim-compatible API | Coordinates, search text | Reverse geocoding, search | [nominatim_geocoding_provider.dart](../lib/data/remote/nominatim_geocoding_provider.dart) |
| Raster tile server | Tile x/y/z (reveals the viewed area) | Map screen, map snapshots | [map_snapshot_service.dart](../lib/features/stamp_editor/services/map_snapshot_service.dart), [map_location_screen.dart](../lib/features/map_location/screens/map_location_screen.dart) |
| Open-Meteo compatible API | Coordinates (4 decimals) | Current weather & temperature | [weather_service.dart](../lib/data/remote/weather_service.dart) |

All HTTP calls go through a single `Dio` instance (`dioProvider`) with a 10 s connect / 15 s receive timeout and the `Env.userAgent` header.

## Reverse geocoding provider abstraction

```dart
abstract interface class GeocodingProvider {
  String get name;
  Future<AddressModel?> reverse(double latitude, double longitude, {String? languageCode});
  Future<List<PlaceResult>> search(String query, {String? languageCode});
}
```

`GeocodingRepository` selects the provider from `AppSettings.geocoderProvider` (default: device geocoder), adds a local SQLite cache keyed on coordinates rounded to 4 decimals (about 11 m), enforces consent and offline checks, and falls back from the device geocoder to Nominatim if the device has none.

### Adding a provider

1. Implement `GeocodingProvider` in `lib/data/remote/`. Map the response to `AddressModel`: street, buildingNumber, area, locality, subLocality, city, district, state, postalCode, country, countryCode, fullAddress.
2. Throw `AppException(AppErrorKind.offline, …)` for connectivity errors and `AppErrorKind.geocoding` for service errors. Return `null` or `[]` for "nothing found".
3. Add a value to `GeocoderProvider` in [app_settings.dart](../lib/data/models/app_settings.dart) and wire it up in `GeocodingRepository.providerFor`.
4. Read any credentials from `Env` via `String.fromEnvironment`. Never hard-code them.

### Nominatim details

- `GET {GEOCODER_BASE_URL}/reverse?format=jsonv2&addressdetails=1&lat=…&lon=…&zoom=18[&accept-language][&key][&email]`
- `GET {GEOCODER_BASE_URL}/search?format=jsonv2&addressdetails=1&q=…&limit=8`
- Requests are throttled to one per 1.1 s, as the public OSM usage policy requires.
- HTTP 429 is reported as "rate limited".
- Compatible commercial services (e.g. LocationIQ) work by setting `GEOCODER_BASE_URL` and `GEOCODER_API_KEY`.

## Map tiles

- `TILE_URL_TEMPLATE` accepts `{z}`, `{x}`, `{y}` (and `{s}`, replaced with `a`).
- The interactive map uses flutter_map's built-in tile cache.
- Map snapshots for stamps composite tiles into a 640×640 image and keep tiles in `ApplicationSupport/tiles/z/x/y.png`, so previously viewed areas also work offline.
- The `TILE_ATTRIBUTION` text is drawn on every snapshot and shown on the map.

## Weather

- `GET {WEATHER_BASE_URL}?latitude=…&longitude=…&current=temperature_2m,weather_code`
- Results are cached in memory for 20 minutes per ~2 km area.
- Weather is fetched only when `AppSettings.fetchWeather` is on (default), consent is given, and the device is online.
- Weather codes are mapped to text using the WMO interpretation table.
- Weather is never attached to manually selected locations.

## Device photo library

`gal` saves exports to an album named "GPS Camera". The `exportToDevice` method in `PhotoService` handles add-only permission requests and reports permission or storage errors. After a capture is saved, the stamped photo is copied there automatically (`AppSettings.saveEditedToDevice`, default on; `saveOriginalToDevice`, default off). Any photo can also be saved from the editor menu with *Save to phone gallery*.
