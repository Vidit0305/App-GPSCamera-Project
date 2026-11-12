import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/colors.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/location_model.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';
import '../../location/services/location_service.dart';

/// Live GPS / address status with clear provenance labels.
class LocationStatusCard extends ConsumerWidget {
  const LocationStatusCard({super.key});

  Future<void> _selectManually(BuildContext context, WidgetRef ref, LocationModel? initial) async {
    final picked = await context.push<LocationModel>(Routes.mapLocation, extra: initial);
    if (picked != null) {
      await ref.read(locationControllerProvider.notifier).setManual(picked);
      if (context.mounted) showSnack(context, 'Manual location will be used for new photos.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(locationControllerProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final status = context.status;
    final ctrl = ref.read(locationControllerProvider.notifier);

    final manual = st.manual;
    final live = st.live;
    final shown = manual ?? live ?? st.lastKnown;

    Widget header() {
      final (label, tone, icon) = manual != null
          ? ('Manual location', ChipTone.info, Icons.edit_location_alt_outlined)
          : switch (st.permission) {
              LocationPermissionState.granted when live != null && st.weakSignal =>
                ('Weak GPS signal', ChipTone.warning, Icons.gps_not_fixed),
              LocationPermissionState.granted when live != null => ('GPS active', ChipTone.success, Icons.gps_fixed),
              LocationPermissionState.granted when st.tracking => ('Acquiring GPS…', ChipTone.info, Icons.gps_not_fixed),
              LocationPermissionState.granted => ('GPS paused', ChipTone.neutral, Icons.gps_off),
              LocationPermissionState.serviceDisabled => ('Location off', ChipTone.error, Icons.location_off),
              LocationPermissionState.denied ||
              LocationPermissionState.deniedForever =>
                ('Permission denied', ChipTone.error, Icons.location_disabled),
              LocationPermissionState.unknown => ('Not enabled', ChipTone.neutral, Icons.location_searching),
            };
      return Row(
        children: [
          Icon(Icons.place_outlined, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text('Current location', style: theme.textTheme.titleMedium)),
          StatusChip(label: label, tone: tone, icon: icon),
        ],
      );
    }

    final children = <Widget>[header(), const SizedBox(height: 14)];

    // ---- permission / service problems
    if (manual == null && st.permission != LocationPermissionState.granted) {
      final msg = switch (st.permission) {
        LocationPermissionState.serviceDisabled =>
          'Location services are turned off. Turn them on to add GPS data, or choose a location manually.',
        LocationPermissionState.deniedForever =>
          'Location permission was denied. Enable it in system settings, or choose a location manually.',
        _ => 'Allow location access to stamp photos with GPS coordinates, altitude and address.',
      };
      children.add(InfoBanner(message: msg, tone: ChipTone.warning, icon: Icons.location_disabled_outlined));
      children.add(const SizedBox(height: 12));
      children.add(Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => ensureLocationPermission(context, ref),
            icon: const Icon(Icons.my_location, size: 18),
            label: Text(st.permission == LocationPermissionState.serviceDisabled ? 'Turn on' : 'Allow location'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _selectManually(context, ref, null),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Select on map'),
          ),
        ),
      ]));
    }

    if (manual != null) {
      children.add(InfoBanner(
        message: 'New photos use this manually selected location, not the device GPS.',
        tone: ChipTone.info,
        icon: Icons.edit_location_alt_outlined,
        action: TextButton(onPressed: () => ctrl.setManual(null), child: const Text('Use GPS')),
      ));
      children.add(const SizedBox(height: 12));
    }

    if (shown == null && st.permission == LocationPermissionState.granted && manual == null) {
      children.add(Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            st.tracking
                ? 'Acquiring GPS fix… this can take longer indoors.'
                : (st.error ?? 'GPS is paused.'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ]));
    }

    if (shown != null) {
      final isStale = manual == null && live == null;
      if (isStale) {
        children.add(InfoBanner(
          message: 'Showing the last known position'
              '${shown.detectedAt != null ? ' (${Fmt.relative(shown.detectedAt!)})' : ''}. '
              'Waiting for a live GPS fix.',
          tone: ChipTone.warning,
          icon: Icons.history,
        ));
        children.add(const SizedBox(height: 12));
      }
      if (shown.isMocked) {
        children.add(const InfoBanner(
          message: 'The device reports a mock (simulated) location provider.',
          tone: ChipTone.error,
          icon: Icons.warning_amber_rounded,
        ));
        children.add(const SizedBox(height: 12));
      }

      // Address block
      final title = shown.shortAddress;
      children.add(Text(
        title.isNotEmpty ? title : 'Address not available',
        style: theme.textTheme.titleLarge?.copyWith(color: title.isEmpty ? theme.colorScheme.onSurfaceVariant : null),
      ));
      final area = [shown.area, shown.street].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
      if (area.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(area, style: theme.textTheme.bodySmall),
        ));
      }
      if (manual == null) children.add(_AddressStatusLine(st: st));
      children.add(const SizedBox(height: 14));

      final grid = <(String, String)>[
        ('Latitude', shown.latitude == null ? '—' : Fmt.latitude(shown.latitude!, settings.coordinateFormat)),
        ('Longitude', shown.longitude == null ? '—' : Fmt.longitude(shown.longitude!, settings.coordinateFormat)),
        ('Altitude', Fmt.altitude(shown.altitude, settings.altitudeUnit)),
        ('GPS accuracy', manual != null ? 'Not applicable' : Fmt.accuracy(shown.accuracy, settings.distanceUnit)),
        if (manual == null && shown.speed != null) ('Speed', Fmt.speed(shown.speed, settings.distanceUnit)),
        if (manual == null && shown.heading != null) ('Heading', Fmt.heading(shown.heading)),
        ('City', shown.city ?? shown.locality ?? '—'),
        ('Country', shown.country ?? '—'),
      ];
      children.add(LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final (k, v) in grid)
              SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k, style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      v,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: k == 'GPS accuracy' && (shown.accuracy ?? 0) > 50 ? status.warning : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      }));
      if (manual == null && st.weakSignal) {
        children.add(const SizedBox(height: 12));
        children.add(const InfoBanner(
          message: 'Low GPS accuracy. Keep the app open with a clear view of the sky – accuracy keeps improving. '
              'You can still take photos.',
          tone: ChipTone.warning,
          icon: Icons.gps_not_fixed,
        ));
      }
      children.add(const SizedBox(height: 12));
      children.add(Row(
        children: [
          Text('Source: ${shown.source.label}', style: theme.textTheme.bodySmall),
          if (shown.detectedAt != null) ...[
            const Text(' · '),
            Text(Fmt.timeShort(shown.detectedAt!, settings), style: theme.textTheme.bodySmall),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: () => _selectManually(context, ref, shown),
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            label: const Text('Change'),
          ),
        ],
      ));
    }

    children.add(const Divider(height: 20));
    children.add(Row(children: [
      Icon(Icons.verified_user_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Expanded(child: Text('Permission: ${st.permission.label}', style: theme.textTheme.bodySmall)),
    ]));

    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }
}

class _AddressStatusLine extends ConsumerWidget {
  const _AddressStatusLine({required this.st});
  final LocationState st;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.read(locationControllerProvider.notifier);
    Widget line(IconData icon, String text, {Widget? action, Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(icon, size: 15, color: color ?? theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ?action,
          ]),
        );
    switch (st.addressStatus) {
      case AddressStatus.loading:
        return line(Icons.sync, 'Looking up address…');
      case AddressStatus.offline:
        return line(Icons.cloud_off, 'Offline – coordinates are saved; the address will be filled in later.');
      case AddressStatus.noConsent:
        return line(Icons.public_off, 'Address lookup is off.',
            action: TextButton(onPressed: () => requestOnlineConsent(context, ref), child: const Text('Enable')));
      case AddressStatus.failed:
        return line(Icons.error_outline, st.addressMessage ?? 'Address lookup failed.',
            color: context.status.error,
            action: TextButton(onPressed: ctrl.retryAddress, child: const Text('Retry')));
      case AddressStatus.notFound:
        return line(Icons.help_outline, 'No address found for this position.');
      case AddressStatus.resolved:
      case AddressStatus.idle:
        return const SizedBox.shrink();
    }
  }
}
