import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/config/env.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';
import '../../location/services/location_service.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _set(WidgetRef ref, AppSettings Function(AppSettings) change) =>
      ref.read(settingsProvider.notifier).update(change);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final loc = ref.watch(locationControllerProvider);
    final templates = ref.watch(templatesProvider).value ?? const [];
    final defaultTemplate = templates.where((t) => t.id == s.defaultTemplateId).firstOrNull;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // ------------------------------------------------------- General
          const SectionHeader('General'),
          _Group(children: [
            _ChoiceTile<ThemeMode>(
              icon: Icons.brightness_6_outlined,
              title: 'Theme',
              value: s.themeMode,
              options: const {ThemeMode.system: 'System', ThemeMode.light: 'Light', ThemeMode.dark: 'Dark'},
              onChanged: (v) => _set(ref, (x) => x.copyWith(themeMode: v)),
            ),
            _ChoiceTile<String>(
              icon: Icons.language,
              title: 'Language & formats',
              subtitle: '${supportedLocaleCodes[s.localeCode]} · app text is English; this sets date/number '
                  'formats and system dialogs',
              value: s.localeCode,
              options: supportedLocaleCodes,
              onChanged: (v) => _set(ref, (x) => x.copyWith(localeCode: v)),
            ),
            _ChoiceTile<String>(
              icon: Icons.calendar_today_outlined,
              title: 'Date format',
              value: s.dateFormat,
              options: {for (final f in dateFormatOptions) f: '$f  ·  ${Fmt.date(now, s.copyWith(dateFormat: f))}'},
              valueLabel: Fmt.date(now, s),
              onChanged: (v) => _set(ref, (x) => x.copyWith(dateFormat: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.schedule),
              title: const Text('24-hour time'),
              subtitle: Text(Fmt.time(now, s)),
              value: s.use24Hour,
              onChanged: (v) => _set(ref, (x) => x.copyWith(use24Hour: v)),
            ),
            _ChoiceTile<DistanceUnit>(
              icon: Icons.straighten,
              title: 'Distance units',
              value: s.distanceUnit,
              options: const {DistanceUnit.metric: 'Metric (m, km/h)', DistanceUnit.imperial: 'Imperial (ft, mph)'},
              onChanged: (v) => _set(ref, (x) => x.copyWith(distanceUnit: v)),
            ),
            _ChoiceTile<AltitudeUnit>(
              icon: Icons.terrain_outlined,
              title: 'Altitude units',
              value: s.altitudeUnit,
              options: {for (final u in AltitudeUnit.values) u: u.label},
              onChanged: (v) => _set(ref, (x) => x.copyWith(altitudeUnit: v)),
            ),
            _ChoiceTile<TemperatureUnit>(
              icon: Icons.thermostat_outlined,
              title: 'Temperature',
              value: s.temperatureUnit,
              options: const {TemperatureUnit.celsius: 'Celsius (°C)', TemperatureUnit.fahrenheit: 'Fahrenheit (°F)'},
              onChanged: (v) => _set(ref, (x) => x.copyWith(temperatureUnit: v)),
            ),
          ]),

          // ------------------------------------------------------- Camera
          const SectionHeader('Camera'),
          _Group(children: [
            _ChoiceTile<LensSetting>(
              icon: Icons.cameraswitch_outlined,
              title: 'Default camera',
              value: s.defaultLens,
              options: const {LensSetting.back: 'Rear camera', LensSetting.front: 'Front camera'},
              onChanged: (v) => _set(ref, (x) => x.copyWith(defaultLens: v)),
            ),
            _ChoiceTile<FlashSetting>(
              icon: Icons.flash_auto,
              title: 'Default flash',
              value: s.defaultFlash,
              options: const {FlashSetting.off: 'Off', FlashSetting.auto: 'Auto', FlashSetting.on: 'On'},
              onChanged: (v) => _set(ref, (x) => x.copyWith(defaultFlash: v)),
            ),
            _ChoiceTile<CaptureResolution>(
              icon: Icons.high_quality_outlined,
              title: 'Capture resolution',
              value: s.resolution,
              options: {for (final r in CaptureResolution.values) r: r.label},
              onChanged: (v) => _set(ref, (x) => x.copyWith(resolution: v)),
            ),
            _SliderTile(
              icon: Icons.photo_size_select_large_outlined,
              title: 'Image quality (JPEG)',
              value: s.jpegQuality.toDouble(),
              min: 50,
              max: 100,
              onChanged: (v) => _set(ref, (x) => x.copyWith(jpegQuality: v.round())),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('Default stamp template'),
              subtitle: Text(defaultTemplate?.name ?? 'Loading…'),
              trailing: const Icon(Icons.chevron_right),
              onTap: templates.isEmpty
                  ? null
                  : () async {
                      final picked = await _pick<String>(
                        context,
                        'Default stamp template',
                        {for (final t in templates) t.id: t.name},
                        s.defaultTemplateId,
                      );
                      if (picked != null) await _set(ref, (x) => x.copyWith(defaultTemplateId: picked));
                    },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.approval_outlined),
              title: const Text('Automatic stamp'),
              subtitle: const Text('Render the default stamp onto each new photo'),
              value: s.autoStamp,
              onChanged: (v) => _set(ref, (x) => x.copyWith(autoStamp: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.save_alt),
              title: const Text('Save edited photos to device gallery'),
              subtitle: const Text('Stamped version, album “GPS Camera”'),
              value: s.saveEditedToDevice,
              onChanged: (v) => _set(ref, (x) => x.copyWith(saveEditedToDevice: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.photo_outlined),
              title: const Text('Save original photos to device gallery'),
              subtitle: const Text('Unstamped original, album “GPS Camera”'),
              value: s.saveOriginalToDevice,
              onChanged: (v) => _set(ref, (x) => x.copyWith(saveOriginalToDevice: v)),
            ),
          ]),

          // ------------------------------------------------------- Location
          const SectionHeader('Location'),
          _Group(children: [
            _ChoiceTile<GpsAccuracyPreference>(
              icon: Icons.gps_fixed,
              title: 'GPS accuracy',
              value: s.gpsAccuracy,
              options: {for (final g in GpsAccuracyPreference.values) g: g.label},
              onChanged: (v) async {
                await _set(ref, (x) => x.copyWith(gpsAccuracy: v));
                await ref.read(locationControllerProvider.notifier).restart();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Location permission'),
              subtitle: Text(loc.permission.label),
              trailing: loc.permission == LocationPermissionState.granted
                  ? const StatusChip(label: 'Allowed', tone: ChipTone.success, dense: true)
                  : TextButton(
                      onPressed: () async {
                        if (loc.permission == LocationPermissionState.deniedForever) {
                          await openAppSettings();
                        } else {
                          await ensureLocationPermission(context, ref);
                        }
                      },
                      child: Text(loc.permission == LocationPermissionState.deniedForever ? 'Open settings' : 'Allow'),
                    ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.autorenew),
              title: const Text('Automatic location detection'),
              subtitle: const Text('Track GPS while the app is open'),
              value: s.autoLocation,
              onChanged: (v) async {
                await _set(ref, (x) => x.copyWith(autoLocation: v));
                final c = ref.read(locationControllerProvider.notifier);
                v ? await c.start() : c.pause();
              },
            ),
            _ChoiceTile<CoordinateFormat>(
              icon: Icons.pin_drop_outlined,
              title: 'Coordinate format',
              value: s.coordinateFormat,
              options: {for (final f in CoordinateFormat.values) f: '${f.label}  ·  ${f.example}'},
              valueLabel: s.coordinateFormat.label,
              onChanged: (v) => _set(ref, (x) => x.copyWith(coordinateFormat: v)),
            ),
            _ChoiceTile<GeocoderProvider>(
              icon: Icons.travel_explore,
              title: 'Reverse geocoding provider',
              subtitle: s.geocoderProvider == GeocoderProvider.nominatim
                  ? '${s.geocoderProvider.label}\n${Env.geocoderBaseUrl}'
                  : s.geocoderProvider.label,
              value: s.geocoderProvider,
              options: {for (final g in GeocoderProvider.values) g: g.label},
              onChanged: (v) async {
                await _set(ref, (x) => x.copyWith(geocoderProvider: v));
                await ref.read(locationControllerProvider.notifier).retryAddress();
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wb_cloudy_outlined),
              title: const Text('Fetch weather'),
              subtitle: const Text('Current weather from Open-Meteo (online services required)'),
              value: s.fetchWeather,
              onChanged: (v) => _set(ref, (x) => x.copyWith(fetchWeather: v)),
            ),
          ]),

          // ------------------------------------------------------- Gallery
          const SectionHeader('Gallery & metadata'),
          _Group(children: [
            _ChoiceTile<GallerySort>(
              icon: Icons.sort,
              title: 'Default sorting',
              value: s.gallerySort,
              options: {for (final g in GallerySort.values) g: g.label},
              onChanged: (v) => _set(ref, (x) => x.copyWith(gallerySort: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.share_location),
              title: const Text('Save location in photo metadata'),
              subtitle: const Text('Write GPS coordinates into the EXIF of new photos'),
              value: s.saveLocationInExif,
              onChanged: (v) => _set(ref, (x) => x.copyWith(saveLocationInExif: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.history_toggle_off),
              title: const Text('Preserve original images'),
              subtitle: const Text('Keep the unstamped original so stamps can be re-edited'),
              value: s.preserveOriginals,
              onChanged: (v) async {
                if (!v) {
                  final ok = await confirm(
                    context,
                    title: 'Stop preserving originals?',
                    message: 'When you save edits, the unstamped original will be deleted. The visible stamp of '
                        'those photos can no longer be changed, only their metadata. Existing photos are not affected '
                        'until you save them again.',
                    confirmLabel: 'Turn off',
                    destructive: true,
                  );
                  if (!ok) return;
                }
                await _set(ref, (x) => x.copyWith(preserveOriginals: v));
              },
            ),
            _SliderTile(
              icon: Icons.tune,
              title: 'Export quality (stamped JPEG)',
              value: s.exportQuality.toDouble(),
              min: 60,
              max: 100,
              onChanged: (v) => _set(ref, (x) => x.copyWith(exportQuality: v.round())),
            ),
            _TextSettingTile(
              icon: Icons.person_outline,
              title: 'Default author (EXIF Artist)',
              value: s.defaultArtist,
              onSaved: (v) => _set(ref, (x) => x.copyWith(defaultArtist: v)),
            ),
            _TextSettingTile(
              icon: Icons.copyright,
              title: 'Default copyright (EXIF)',
              value: s.defaultCopyright,
              onSaved: (v) => _set(ref, (x) => x.copyWith(defaultCopyright: v)),
            ),
          ]),

          // ------------------------------------------------------- Privacy
          const SectionHeader('Privacy'),
          _Group(children: [
            SwitchListTile(
              secondary: const Icon(Icons.public),
              title: const Text('Online location services'),
              subtitle: const Text('Address lookup, place search, map tiles and weather. Photos are never uploaded.'),
              value: s.onlineAllowed,
              onChanged: (v) async {
                if (v) {
                  await requestOnlineConsent(context, ref);
                } else {
                  await _set(ref, (x) => x.copyWith(onlineConsent: false));
                }
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.location_off_outlined),
              title: const Text('Remove location metadata when sharing'),
              subtitle: const Text('Shared copies have GPS EXIF removed (the visible stamp is unchanged)'),
              value: s.removeLocationOnShare,
              onChanged: (v) => _set(ref, (x) => x.copyWith(removeLocationOnShare: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.help_outline),
              title: const Text('Ask before sharing location'),
              subtitle: const Text('Confirm whether to include GPS metadata each time you share'),
              value: s.askBeforeShareLocation,
              onChanged: (v) => _set(ref, (x) => x.copyWith(askBeforeShareLocation: v)),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Clear cached location data'),
              subtitle: const Text('Saved addresses, recent locations, last position and map tiles'),
              onTap: () => _clearCache(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Manage permissions'),
              subtitle: const Text('Camera, location and photo library access in system settings'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: openAppSettings,
            ),
          ]),

          // ------------------------------------------------------- About
          const SectionHeader('About'),
          _Group(children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('GPS Camera'),
              subtitle: Text(ref.watch(_packageInfoProvider).when(
                    data: (i) => 'Version ${i.version} (${i.buildNumber})',
                    loading: () => 'Version …',
                    error: (_, _) => 'Version unavailable',
                  )),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDoc(context, Env.privacyPolicyUrl, 'privacy'),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Terms and Conditions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDoc(context, Env.termsUrl, 'terms'),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('Contact & support'),
              subtitle: Text(Env.supportEmail.isNotEmpty
                  ? Env.supportEmail
                  : (Env.supportUrl.isNotEmpty ? Env.supportUrl : 'Not configured')),
              onTap: () => _contact(context),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context, applicationName: 'GPS Camera'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Clear cached location data?',
      message: 'Cached addresses, recent locations, the last known position and downloaded map tiles will be '
          'deleted. Your photos and their metadata are not changed.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok) return;
    try {
      final geo = ref.read(geocodingRepositoryProvider);
      await geo.clearCache();
      await geo.clearRecents();
      await ref.read(settingsRepositoryProvider).clearCachedLocations();
      await ref.read(storageProvider).clearTileCache();
      ref.read(locationControllerProvider.notifier).clearCachedData();
      if (context.mounted) showSnack(context, 'Cached location data cleared.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _openDoc(BuildContext context, String url, String doc) async {
    if (url.isNotEmpty) {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (ok) return;
    }
    if (context.mounted) await context.push(Routes.legal(doc));
  }

  Future<void> _contact(BuildContext context) async {
    Uri? uri;
    if (Env.supportEmail.isNotEmpty) {
      uri = Uri(scheme: 'mailto', path: Env.supportEmail, queryParameters: {'subject': 'GPS Camera support'});
    } else if (Env.supportUrl.isNotEmpty) {
      uri = Uri.parse(Env.supportUrl);
    }
    if (uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Support contact'),
        content: Text(uri == null
            ? 'No support contact has been configured for this build. The publisher sets SUPPORT_EMAIL or '
                'SUPPORT_URL at build time (see env.example.json).'
            : 'No app is available to open $uri.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
}

// ------------------------------------------------------------------ widgets

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

Future<T?> _pick<T>(BuildContext context, String title, Map<T, String> options, T current) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Flexible(
              child: RadioGroup<T>(
                groupValue: current,
                onChanged: (v) => Navigator.pop(ctx, v),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in options.entries)
                      RadioListTile<T>(value: e.key, title: Text(e.value)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.valueLabel,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final String? valueLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle ?? valueLabel ?? options[value] ?? '$value'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await _pick<T>(context, title, options, value);
        if (picked != null && picked != value) onChanged(picked);
      },
    );
  }
}

class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = _drag ?? widget.value;
    return ListTile(
      leading: Icon(widget.icon),
      title: Row(children: [
        Expanded(child: Text(widget.title)),
        Text('${v.round()}', style: Theme.of(context).textTheme.labelMedium),
      ]),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Slider(
          value: v.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: (widget.max - widget.min).round(),
          onChanged: (x) => setState(() => _drag = x),
          onChangeEnd: (x) {
            setState(() => _drag = null);
            widget.onChanged(x);
          },
        ),
      ),
    );
  }
}

class _TextSettingTile extends StatelessWidget {
  const _TextSettingTile({required this.icon, required this.title, required this.value, required this.onSaved});

  final IconData icon;
  final String title;
  final String value;
  final ValueChanged<String> onSaved;

  static bool _ascii(String s) => s.codeUnits.every((c) => c >= 0x20 && c < 0x7F);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value.isEmpty ? 'Not set' : value),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () async {
        final ctrl = TextEditingController(text: value);
        String? error;
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setState) => AlertDialog(
              title: Text(title),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Leave empty to not write this field',
                  errorText: error,
                  helperText: 'Plain ASCII text only (EXIF limitation)',
                ),
                onChanged: (v) => setState(() => error = _ascii(v) ? null : 'Use plain ASCII characters only'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(
                  onPressed: error != null ? null : () => Navigator.pop(ctx, ctrl.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
        // The controller is not disposed here: the dialog's exit animation may
        // still reference it; it is garbage-collected afterwards.
        if (result != null) onSaved(result);
      },
    );
  }
}
