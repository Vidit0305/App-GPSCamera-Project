import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers.dart';
import '../utils/haptics.dart';
import '../../features/location/services/location_controller.dart';
import '../../features/location/services/location_service.dart';

/// Explains why a permission is needed before the system prompt is shown.
Future<bool> showPermissionRationale(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String allowLabel = 'Continue',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon, size: 32),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: hx(() => Navigator.pop(ctx, false)), child: const Text('Not now')),
        FilledButton(onPressed: hx(() => Navigator.pop(ctx, true)), child: Text(allowLabel)),
      ],
    ),
  );
  return r ?? false;
}

Future<void> showOpenSettingsDialog(BuildContext context, {required String title, required String message}) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: hx(() => Navigator.pop(ctx, false)), child: const Text('Cancel')),
        FilledButton(onPressed: hx(() => Navigator.pop(ctx, true)), child: const Text('Open settings')),
      ],
    ),
  );
  if (open == true) await openAppSettings();
}

/// Full location-permission flow: rationale → system prompt → settings help.
/// Returns true when location is usable.
Future<bool> ensureLocationPermission(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(locationControllerProvider.notifier);
  final service = ref.read(locationServiceProvider);
  var state = await service.checkPermission();
  if (state == LocationPermissionState.granted) {
    await controller.start();
    return true;
  }
  if (!context.mounted) return false;
  if (state == LocationPermissionState.serviceDisabled) {
    final open = await showPermissionRationale(
      context,
      icon: Icons.location_off_outlined,
      title: 'Location services are off',
      message: 'Turn on location services so GPS Camera can add coordinates and an address to your photos. '
          'You can still take photos without a location.',
      allowLabel: 'Turn on',
    );
    if (open) await service.openLocationSettings();
    return false;
  }
  if (state == LocationPermissionState.deniedForever) {
    await showOpenSettingsDialog(
      context,
      title: 'Location permission needed',
      message: 'Location access was denied. To stamp photos with GPS data, allow location access '
          '"While using the app" in system settings. The camera still works without it.',
    );
    return false;
  }
  final ok = await showPermissionRationale(
    context,
    icon: Icons.my_location,
    title: 'Allow location access?',
    message: 'GPS Camera uses your location only while the app is open, to add coordinates, altitude and '
        'address to the photos you take. Location is never collected in the background, and nothing is uploaded '
        'without your consent.',
  );
  if (!ok) return false;
  state = await controller.requestPermission();
  if (state == LocationPermissionState.deniedForever && context.mounted) {
    await showOpenSettingsDialog(
      context,
      title: 'Location permission denied',
      message: 'You can enable location access for GPS Camera in system settings at any time.',
    );
  }
  return state == LocationPermissionState.granted;
}

/// Camera permission flow. Returns true when the camera may be used.
Future<bool> ensureCameraPermission(BuildContext context) async {
  var status = await Permission.camera.status;
  if (status.isGranted || status.isLimited) return true;
  if (!context.mounted) return false;
  if (status.isPermanentlyDenied || status.isRestricted) {
    await showOpenSettingsDialog(
      context,
      title: 'Camera access needed',
      message: 'GPS Camera needs the camera to take photos. Allow camera access in system settings.',
    );
    return false;
  }
  final ok = await showPermissionRationale(
    context,
    icon: Icons.photo_camera_outlined,
    title: 'Allow camera access?',
    message: 'The camera is used to take photos. Photos stay on your device unless you choose to share them.',
  );
  if (!ok) return false;
  status = await Permission.camera.request();
  if (status.isPermanentlyDenied && context.mounted) {
    await showOpenSettingsDialog(
      context,
      title: 'Camera permission denied',
      message: 'You can enable camera access for GPS Camera in system settings.',
    );
  }
  return status.isGranted;
}

/// Asks for consent to use online services (geocoding, search, map tiles,
/// weather). Stores the answer in settings and returns it.
Future<bool> requestOnlineConsent(BuildContext context, WidgetRef ref) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.public, size: 32),
      title: const Text('Use online location services?'),
      content: const Text(
        'To show addresses, search places, display maps and add weather, GPS Camera sends coordinates or '
        'search text to the configured providers (your device geocoder, OpenStreetMap and Open-Meteo by default).\n\n'
        'Photos are never uploaded. Without online services, the camera, GPS coordinates, stamps and EXIF editing '
        'still work fully offline. You can change this any time in Settings › Privacy.',
      ),
      actions: [
        TextButton(onPressed: hx(() => Navigator.pop(ctx, false)), child: const Text('Stay offline')),
        FilledButton(onPressed: hx(() => Navigator.pop(ctx, true)), child: const Text('Allow')),
      ],
    ),
  );
  final allowed = r ?? false;
  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(onlineConsent: allowed));
  if (allowed) await ref.read(locationControllerProvider.notifier).retryAddress();
  return allowed;
}
