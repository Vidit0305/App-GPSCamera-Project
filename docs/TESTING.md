# Testing guide

## Automated tests

```bash
flutter analyze      # static analysis
flutter test         # unit tests
```

| Suite | Covers |
|---|---|
| `test/formatters_test.dart` | Coordinate formatting (decimal, DMS, DDM) and parsing (signed, hemisphere letters, DMS round trip, labels, out-of-range values); altitude units; time and date parsing |
| `test/models_test.dart` | EXIF map parsing (refs, rational GPS time, UserComment prefixes, zeroed dates); numeric tolerances used for verification; ASCII, coordinate and GPS date/time validation; template JSON round trip; photo DB row round trip keeping detected, stamp and EXIF values separate |
| `test/stamp_layout_test.dart` | Stamp scales with resolution; stays inside the image for every template and position; anchor positions; empty stamp; map omitted from exports when there is no snapshot |

Camera, GPS, native EXIF and gallery access need real hardware. Use the device checklist below.

## Device test checklist

Run on at least one recent Android phone and one iPhone, with a release build (`flutter run --release --dart-define-from-file=env.json`). Record the device model and OS version.

### Camera
- [ ] Rear and front camera preview start; switching works repeatedly.
- [ ] Flash off / auto / on behaves correctly; the icon matches.
- [ ] Pinch zoom and the 1×/2×/5× presets work; tap to focus shows the ring and refocuses.
- [ ] Exposure slider changes brightness, where supported.
- [ ] Each resolution captures at the expected size (check Photo details › dimensions).
- [ ] Lifecycle: background the app, lock and unlock the screen, open another camera app, then return. The preview resumes without a crash.
- [ ] Deny camera permission: an explanatory screen appears and *Open settings* works. Grant it, then return: the preview starts.

### GPS
- [ ] Outdoors: accuracy is about ±3–10 m; lat/lon match a reference app within accuracy.
- [ ] Altitude appears in metres and in feet (switch in Settings). On a device without altitude it shows "Altitude unavailable".
- [ ] Indoors / weak signal: the "Weak GPS signal" warning shows and capture still works.
- [ ] Location permission denied: Home shows the warning with *Allow location* / *Select on map*; captures have no GPS, with a notice in the editor.
- [ ] Location services off: the "Location off" state shows and *Turn on* opens system settings.
- [ ] Airplane mode with GPS on: coordinates still work and the address shows "Offline – will be filled in later".
- [ ] After reconnecting, the photo's detected address resolves. The editor offers *Fill empty* without changing typed text.
- [ ] Mock location app (Android developer options): the mock warning appears.

### Stamp
- [ ] Each of the 8 built-in templates renders as in the preview, in portrait and landscape photos.
- [ ] Every field toggles on and off; edited text appears in the export exactly as typed.
- [ ] Each font, bold, italic and alignment option; text, accent, background and border colours; opacity 0–100 %.
- [ ] Each anchor position, plus dragging to a custom position.
- [ ] Export at maximum resolution: zoom into the saved file; text is sharp, not upscaled.
- [ ] Map snapshot online; then offline in a cached area (map shown) and an uncached area (photo saved without a map, with a message).
- [ ] Templates: create, edit, duplicate, delete and set default persist after an app restart; the camera opens with the default.

### EXIF
For each check, verify independently: copy the file to a computer (*Share* or *Export to gallery*) and run `exiftool -a -G1 -s file.jpg`.
- [ ] New capture: DateTimeOriginal, OffsetTimeOriginal, GPSLatitude/Ref, GPSLongitude/Ref, GPSAltitude/Ref, GPSDateStamp/TimeStamp are present and correct; Make/Model are preserved.
- [ ] Edit coordinates (including southern and western hemispheres) and save: the editor shows "Verified" and exiftool matches.
- [ ] Edit altitude above and below sea level (Ref 0/1).
- [ ] Edit the date taken, with "Also change DateTimeDigitized" off: Digitized keeps the original value.
- [ ] Artist, Copyright, Description, UserComment are written. Non-ASCII text in ASCII fields is rejected with a message.
- [ ] *Remove all GPS metadata*: exiftool shows no GPS tags.
- [ ] Unrelated tags are preserved (compare `exiftool` output before and after; MakerNote may be dropped in stamped exports).
- [ ] Orientation: portrait captures stay upright in the app, in the device gallery and on a computer (stamped exports have Orientation = 1).
- [ ] Import a PNG and a WebP on Android (writable), and a HEIC (Android: reported "not supported"; iOS: verified or reported).
- [ ] Share with *Remove location* on: the shared file has no GPS tags.
- [ ] The preserved original (Photo details › Original) is byte-identical before and after edits.

### Gallery & batch
- [ ] Grid scrolls smoothly with 200+ photos; date headers, search, sort and each category filter work.
- [ ] Details, Edit, Share, Export to gallery (original and edited), Save a copy, Delete.
- [ ] Batch: select 20+ photos, change lat/lon + date + author with "Save as new". Progress shows, each copy verifies, and the originals are unchanged.
- [ ] Batch overwrite mode updates the edited files in place; preserved originals stay untouched.
- [ ] Batch with a failing item (e.g. an imported HEIC on Android): the other items still succeed and the failure is listed.

### Offline (airplane mode, Wi-Fi off)
- [ ] App opens; camera captures; GPS coordinates are recorded.
- [ ] Stamps apply with saved templates; EXIF edits save and verify.
- [ ] Gallery opens; batch editing and sharing to a local app work.
- [ ] Map screen shows the offline notice; manual coordinate entry still confirms.

### Permissions & privacy
- [ ] First launch: location rationale, then the system prompt, then online-services consent. With consent declined, no network requests are made (check with a proxy, e.g. mitmproxy).
- [ ] *Clear cached location data* empties the address cache, recent locations and map tiles.
- [ ] No background-location permission is requested on either platform.
