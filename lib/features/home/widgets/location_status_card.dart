import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/colors.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/location_model.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';
import '../../location/services/location_service.dart';

/// Live location with clear labels for where the data comes from.
class LocationStatusCard extends ConsumerWidget {
  const LocationStatusCard({super.key});

  Future<void> _pickOnMap(BuildContext context, WidgetRef ref, LocationModel? initial) async {
    final picked = await context.push<LocationModel>(Routes.mapLocation, extra: initial);
    if (picked != null) {
      await ref.read(locationControllerProvider.notifier).setManual(picked);
      if (context.mounted) showSnack(context, 'New photos will use the location you picked.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(locationControllerProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ctrl = ref.read(locationControllerProvider.notifier);

    final manual = st.manual;
    final live = st.live;
    final shown = manual ?? live ?? st.lastKnown;
    final granted = st.permission == LocationPermissionState.granted;

    final (label, tone) = manual != null
        ? ('Picked on map', ChipTone.info)
        : !granted
            ? ('Off', ChipTone.neutral)
            : live == null
                ? (st.tracking ? 'Searching…' : 'Paused', ChipTone.neutral)
                : st.weakSignal
                    ? ('Weak signal', ChipTone.warning)
                    : ('Live GPS', ChipTone.success);

    final children = <Widget>[
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.location_on_rounded, color: scheme.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Your location', style: theme.textTheme.titleMedium)),
          StatusChip(label: label, tone: tone),
        ],
      ),
      const SizedBox(height: 16),
    ];

    // ---- No permission and nothing picked manually
    if (manual == null && !granted) {
      final msg = switch (st.permission) {
        LocationPermissionState.serviceDisabled => 'Location is turned off on this phone.',
        LocationPermissionState.deniedForever => 'Location access is blocked. You can allow it in system settings.',
        _ => 'Allow location so your photos show where they were taken.',
      };
      children.addAll([
        Text(msg, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: hx(() => ensureLocationPermission(context, ref)),
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(st.permission == LocationPermissionState.serviceDisabled ? 'Turn on' : 'Allow'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hx(() => _pickOnMap(context, ref, null)),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Pick on map'),
            ),
          ),
        ]),
      ]);
      return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
    }

    // ---- Waiting for the first fix
    if (shown == null) {
      children.add(Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            st.error ?? 'Finding your position… this can take a little longer indoors.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ]));
      return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
    }

    // ---- Location available
    final title = shown.shortAddress;
    children.add(Text(
      title.isNotEmpty ? title : 'Address not available',
      style: theme.textTheme.titleLarge?.copyWith(color: title.isEmpty ? scheme.onSurfaceVariant : null),
    ));
    final sub = [shown.area, shown.street].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    if (sub.isNotEmpty) {
      children.add(Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: theme.textTheme.bodySmall)));
    }
    if (manual == null) children.add(_AddressStatusLine(st: st));
    children.add(const SizedBox(height: 14));

    children.add(_TileGrid(tiles: [
      (Icons.north_rounded, 'Latitude', shown.latitude == null ? '—' : Fmt.latitude(shown.latitude!, settings.coordinateFormat)),
      (Icons.east_rounded, 'Longitude', shown.longitude == null ? '—' : Fmt.longitude(shown.longitude!, settings.coordinateFormat)),
      (Icons.terrain_rounded, 'Altitude', shown.altitude == null ? 'Unavailable' : Fmt.altitude(shown.altitude, settings.altitudeUnit)),
      (Icons.gps_fixed_rounded, 'Accuracy', manual != null ? '—' : Fmt.accuracy(shown.accuracy, settings.distanceUnit)),
    ]));

    // Warnings, only when they matter.
    String? warning;
    if (manual != null) {
      warning = null;
    } else if (shown.isMocked) {
      warning = 'This phone reports a simulated (mock) location.';
    } else if (live == null) {
      warning = 'Last known position${shown.detectedAt != null ? ' (${Fmt.relative(shown.detectedAt!)})' : ''} — waiting for live GPS.';
    } else if (st.weakSignal) {
      warning = 'Low accuracy. Move to an open area for a better fix — you can still take photos.';
    }
    if (warning != null) {
      children.addAll([const SizedBox(height: 12), InfoBanner(message: warning, tone: ChipTone.warning)]);
    }

    children.add(const SizedBox(height: 6));
    children.add(Row(
      children: [
        if (manual != null)
          TextButton.icon(
            onPressed: hx(() => ctrl.setManual(null)),
            icon: const Icon(Icons.gps_fixed, size: 18),
            label: const Text('Use GPS'),
          )
        else
          Expanded(
            child: Text(
              shown.detectedAt == null ? shown.source.label : '${shown.source.label} · ${Fmt.timeShort(shown.detectedAt!, settings)}',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (manual != null) const Spacer(),
        TextButton.icon(
          onPressed: hx(() => _pickOnMap(context, ref, shown)),
          icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
          label: const Text('Change'),
        ),
      ],
    ));

    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<(IconData, String, String)> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (icon, label, value) in tiles)
            Container(
              width: w,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: dark ? AppColors.darkCardHigh : const Color(0xFFF4F7FD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: theme.textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _AddressStatusLine extends ConsumerWidget {
  const _AddressStatusLine({required this.st});
  final LocationState st;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.read(locationControllerProvider.notifier);
    Widget line(IconData icon, String text, {Widget? action}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ?action,
          ]),
        );
    return switch (st.addressStatus) {
      AddressStatus.loading => line(Icons.sync, 'Looking up address…'),
      AddressStatus.offline => line(Icons.cloud_off, 'Offline — the address will be added later.'),
      AddressStatus.noConsent => line(Icons.public_off, 'Address lookup is off.',
          action: TextButton(onPressed: hx(() => requestOnlineConsent(context, ref)), child: const Text('Turn on'))),
      AddressStatus.failed => line(Icons.error_outline, 'Couldn\'t get the address.',
          action: TextButton(onPressed: hx(ctrl.retryAddress), child: const Text('Retry'))),
      AddressStatus.notFound => line(Icons.help_outline, 'No address found here.'),
      AddressStatus.resolved || AddressStatus.idle => const SizedBox.shrink(),
    };
  }
}
