# GPS Camera

A Flutter app (Android & iOS) for taking photos stamped with location, coordinates, altitude and time, with **real EXIF metadata editing** and manual map-based location selection. Core features work fully offline.

The app is deliberately simple: **one home screen** (Capture, current location, your photos, light/dark toggle). The camera, the photo editor and the map picker open on top of it. A larger version with separate Gallery, Templates, Settings and Batch-edit screens exists in the first commit of this repository's history.

- [Features](#features)
- [Requirements](#requirements)
- [Setup](#setup)
- [Configuration (environment)](#configuration-environment)
- [Running](#running)
- [Building for release](#building-for-release)
- [Architecture](#architecture)
- [Data storage](#data-storage)
- [Native EXIF integration](#native-exif-integration)
- [Known limitations](#known-limitations)
- Further docs: [API integrations](docs/API_INTEGRATIONS.md) · [Testing guide](docs/TESTING.md)

---

## Features

| Area | What it does |
|---|---|
| Camera | Live preview, flash off/auto/on, front/rear switch, pinch & preset zoom, tap to focus/expose, exposure slider, resolution selection, live stamp preview, GPS status, ticking date/time, correct lifecycle handling (camera released when backgrounded). |
| GPS | Foreground-only Geolocator stream: latitude, longitude, altitude (MSL on Android), accuracy, speed, heading, fix time, mock-location detection. Weak-signal warning; accuracy keeps improving while open. Last-known position is shown only with its age and never presented as a live fix. |
| Reverse geocoding | Provider abstraction (`GeocodingProvider`) with two implementations: the OS geocoder and Nominatim (OSM or any compatible service). Results are cached locally (~11 m grid) for offline reuse. Photos captured offline keep their coordinates and get their address resolved later — without touching user-edited stamp text. |
| Visible stamp | Renderer that draws at the photo's **real export resolution** (not a screenshot). The same code paints the live preview, so preview = export. Fields, fonts (4 bundled families), size, bold/italic, alignment, colours, opacity, border, radius, padding, line spacing, shadow, icons, banner mode, 5 anchor positions plus drag-anywhere, optional map snapshot (size, corners, placement, marker, zoom). |
| Templates | 8 built-in designs, selectable in the camera and the editor; any edited style can be saved as a template. Stored in SQLite. |
| EXIF editor | Reads and writes real metadata: DateTimeOriginal / Digitized / DateTime, OffsetTime, GPS lat/lon + refs, altitude + ref, GPS date/time, description, artist, copyright, user comment. Every write is **verified by re-opening the saved file**; any field that doesn't match is reported as failed. Unsupported formats are reported, never faked. |
| Independent values | Each photo keeps three separate sets: detected GPS data, visible-stamp text, and EXIF overrides. Sync is explicit (Copy to/from EXIF, Reset to detected). |
| Manual location | Map screen (flutter_map + OSM tiles) with search, centre-pin selection, my-location, zoom, reverse geocoding, and manual fields. Manual locations are always labelled as such and never alter the device GPS. |
| Home | Single screen: Capture card, live location card (with *Change* to pick on a map), grid of your photos (tap to edit, share, save to the phone gallery or delete), light/dark theme toggle at top right. |
| Privacy | Online services (geocoding, search, tiles, weather) require explicit consent, asked on first launch. Photos are never uploaded. No background location. |
| Offline | Capture, GPS, stamping, EXIF editing, viewing and sharing photos all work without internet. |

Preferences (units, date format, default template, image quality, …) use sensible defaults; they live in `AppSettings` and can be changed in code.

## Requirements

| Tool | Version used |
|---|---|
| Flutter | 3.47.x (stable), Dart 3.13 |
| Android | minSdk 24, compileSdk 37 (required by permission_handler), targetSdk per Flutter; AGP 9.5.1, Gradle 9.6.0, JDK 17 |
| iOS | iOS 15.0+, Xcode 16+ (CocoaPods or Swift Package Manager) |

## Setup

```bash
git clone <repo> && cd App-GPSCamera-Project
flutter pub get
cp env.example.json env.json      # edit values if needed (see below)
```

**Change the application identifiers before publishing:**
- Android: `applicationId` and `namespace` in [android/app/build.gradle.kts](android/app/build.gradle.kts) (currently `com.gpscamera.gps_camera`; also move `MainActivity.kt` / `ImageNativePlugin.kt` to the matching package directory).
- iOS: `PRODUCT_BUNDLE_IDENTIFIER` in Xcode (Runner target › Signing & Capabilities).
- Update `Env.userAgent` / `Env.packageName` in [lib/core/config/env.dart](lib/core/config/env.dart). OSM services require an identifying User-Agent.

## Configuration (environment)

No API keys are stored in the source. All external services are configured at build time via `--dart-define-from-file=env.json`. `env.json` is git-ignored; [env.example.json](env.example.json) documents every key:

| Key | Purpose | Default |
|---|---|---|
| `GEOCODER_BASE_URL` | Nominatim-compatible API for reverse geocoding & search | `https://nominatim.openstreetmap.org` |
| `GEOCODER_API_KEY` | Optional key sent as `key=` (e.g. LocationIQ) | empty |
| `GEOCODER_CONTACT_EMAIL` | Optional `email=` parameter for Nominatim's usage policy | empty |
| `TILE_URL_TEMPLATE` | Raster tiles for the map and map snapshots | OSM standard tiles |
| `TILE_ATTRIBUTION` | Attribution drawn on maps and snapshots | `© OpenStreetMap contributors` |
| `WEATHER_BASE_URL` | Open-Meteo compatible endpoint | public Open-Meteo |

> **Production note:** the public OSM tile server and Nominatim are volunteer-run, with strict usage policies (no heavy use, valid User-Agent, max 1 request/s for Nominatim, which the app enforces). For a published app, use your own instance or a commercial provider and point the keys above to it.

## Running

```bash
flutter run --dart-define-from-file=env.json
```

Use a **real device**: emulators have no real GPS, altitude or camera sensors, and the camera plugin has limited emulator support.

Tests:

```bash
flutter analyze
flutter test
```

## Building for release

### Android APK

```bash
flutter build apk --release --dart-define-from-file=env.json
# or per-ABI (smaller files):
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
```
Output: `build/app/outputs/flutter-apk/`.

### Android App Bundle (Play Store)

1. Create an upload keystore (once):
   ```bash
   keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `android/key.properties` (git-ignored):
   ```properties
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=/absolute/path/to/upload-keystore.jks
   ```
   Without this file, release builds fall back to the debug key (fine for testing, not for the store).
3. Build:
   ```bash
   flutter build appbundle --release --dart-define-from-file=env.json
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab`.

### iOS

Requires macOS with Xcode.

```bash
flutter pub get
cd ios && pod install && cd ..            # if using CocoaPods
open ios/Runner.xcworkspace               # set Team & bundle id under Signing & Capabilities
flutter build ipa --release --dart-define-from-file=env.json
```
Upload `build/ios/ipa/*.ipa` with Xcode Organizer or Transporter. Usage descriptions (camera, location when in use, photo library, add-to-photos) are already in [ios/Runner/Info.plist](ios/Runner/Info.plist); review the wording for your publisher. The [Podfile](ios/Podfile) enables only the permission_handler permissions the app uses (camera, location-when-in-use, photos).

> The Swift EXIF bridge in [ios/Runner/AppDelegate.swift](ios/Runner/AppDelegate.swift) could not be compiled during development (built on Windows). Build it on a Mac first and run the EXIF checks in [docs/TESTING.md](docs/TESTING.md#exif) before release.

## Architecture

```
lib/
  main.dart                    bootstraps DB, storage, prefs → ProviderScope
  app/                         app widget, go_router routes, theme, providers
  core/
    config/env.dart            build-time configuration (dart-define)
    errors/                    AppException with categories (permission, gps, exif, storage…)
    permissions/               rationale → request → settings flows; online-services consent
    services/                  file storage (path-independent), native image channel
    utils/formatters.dart      coordinates (decimal/DMS/DDM), units, dates – format & parse
  data/
    models/                    PhotoModel, LocationModel, StampTemplateModel, PhotoMetadataModel,
                               StampValues, WeatherModel, AppSettings
    local/app_database.dart    sqflite schema
    remote/                    GeocodingProvider + platform/Nominatim impls, weather
    repositories/              photos, templates, settings, geocoding (+cache, recents)
  features/
    home/          the single main screen
    camera/        full-screen camera
    photo_editor/  stamp text, stamp style and EXIF tabs; capture/save pipeline
    location/ stamp_editor/ exif_editor/ map_location/ templates/(built-in designs)
  shared/widgets/              cards, chips, banners, thumbnails, colour picker
```

- **State:** Riverpod 3 (`Notifier`/`StreamProvider`). Repositories expose change streams; `photosProvider` and `templatesProvider` rebuild automatically.
- **Navigation:** go_router with four routes: `/` (Home), `/camera`, `/editor/:id` and `/map-location`. There is no bottom bar.
- **Rendering:** `StampLayout` ([stamp_painter.dart](lib/features/stamp_editor/services/stamp_painter.dart)) lays out and paints in image-pixel coordinates, scaled by the image's shorter side / 1080. The preview paints the same layout through a scaled canvas. Export decodes the original at full resolution, paints it plus the stamp into a `PictureRecorder`, reads raw RGBA and encodes it to JPEG **natively**, copying the source metadata and resetting orientation.
- **Photo pipeline** ([photo_service.dart](lib/features/photo_editor/services/photo_service.dart)): capture → move into app storage as the preserved original → write capture EXIF (time, offset, GPS if enabled) and verify → optionally render the stamped export → thumbnail → DB record. Re-editing always regenerates from the preserved original and re-applies the photo's EXIF overrides, so metadata is never silently dropped.

## Data storage

| What | Where |
|---|---|
| Photo records, user templates, geocoding cache, recent locations | SQLite `gps_camera.db` |
| Settings, last known location, manual override | SharedPreferences |
| Originals / edited exports | `Documents/photos/originals`, `Documents/photos/edited` |
| Thumbnails, map tiles | Application Support (re-creatable caches) |
| Share copies | Temp directory (cleared before each share) |

Paths are stored relative to the app container (`docs:` / `support:` prefixes) because iOS changes the container path between app updates.

## Native EXIF integration

Channel `com.gpscamera/image_native` (Dart side: [native_image_channel.dart](lib/core/services/native_image_channel.dart)):

| Method | Android ([ImageNativePlugin.kt](android/app/src/main/kotlin/com/gpscamera/gps_camera/ImageNativePlugin.kt)) | iOS ([AppDelegate.swift](ios/Runner/AppDelegate.swift)) |
|---|---|---|
| `readMetadata` | androidx `ExifInterface` (JPEG, PNG, WebP, HEIF read) | ImageIO `CGImageSourceCopyPropertiesAtIndex` |
| `writeMetadata` | `ExifInterface.saveAttributes()` – lossless; JPEG/PNG/WebP | `CGImageDestinationCopyImageSource` + merged `CGImageMetadata` – lossless; JPEG/PNG/HEIC/TIFF attempted |
| `encodeJpeg` | `Bitmap.compress` + copy all EXIF tags | `CGImageDestinationAddImage` with source properties |
| `stripGpsCopy` | remove all `TAG_GPS_*` | `kCGImageMetadataShouldExcludeGPS` |

`ExifService` (Dart) validates values, sends only the changed fields, re-reads the file and compares field by field (coordinates within 1e-6°, altitude within 5 cm). The UI shows Verified / Partially written / Failed / Not supported.

## Known limitations

- **EXIF text encoding:** ImageDescription, Artist and Copyright are ASCII in the EXIF standard; the editor rejects other characters instead of corrupting them.
- **Address fields in EXIF:** EXIF has no standard city/state/country tags. Address edits go to the visible stamp and the app's record; batch address changes re-render stamps when requested.
- **HEIC:** Android cannot write EXIF to HEIC. iOS writing is attempted and verified; if verification fails the app says so. Stamping always exports JPEG, which supports full editing.
- **Very large images:** stamped exports are limited to 8192 px on the long side (GPU texture limit); the app warns if a photo was downscaled.
- **Map snapshots** need online tiles (with consent) or an area already cached on the device; otherwise the photo is saved without the map and a message explains why.
- **Language:** UI text is English. The Language setting changes date/number formats and system dialogs.
- **Device gallery copies** are snapshots: later edits in the app don't change copies already exported (use *Save to phone gallery* in the editor menu again).

## Licences

Bundled fonts: Inter, Lora, Oswald (SIL OFL 1.1), Roboto Mono (Apache 2.0). Map data © OpenStreetMap contributors (ODbL). The app registers these in the Flutter licence registry.

## App icon

The icon is drawn in code by [tool/icon/generate_icon_test.dart](tool/icon/generate_icon_test.dart) (camera with a location pin in its lens, using the app's navy/royal palette). To change it, edit that file and run:

```bash
flutter test tool/icon/generate_icon_test.dart   # writes assets/icon/*.png
dart run flutter_launcher_icons                  # Android (incl. adaptive + themed) and iOS icons
```
