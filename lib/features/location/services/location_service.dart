import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../../../core/errors/app_exception.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/location_model.dart';

enum LocationPermissionState {
  unknown,
  granted,
  denied,
  deniedForever,
  serviceDisabled;

  String get label => switch (this) {
        unknown => 'Not requested',
        granted => 'Allowed while using the app',
        denied => 'Denied',
        deniedForever => 'Denied – change in system settings',
        serviceDisabled => 'Location services are off',
      };
}

/// Thin wrapper over Geolocator: foreground-only, never requests background access.
class LocationService {
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<LocationPermissionState> checkPermission() async {
    if (!await serviceEnabled()) return LocationPermissionState.serviceDisabled;
    return _map(await Geolocator.checkPermission());
  }

  Future<LocationPermissionState> requestPermission() async {
    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.deniedForever) return LocationPermissionState.deniedForever;
    final result = await Geolocator.requestPermission();
    final mapped = _map(result);
    if (mapped == LocationPermissionState.granted && !await serviceEnabled()) {
      return LocationPermissionState.serviceDisabled;
    }
    return mapped;
  }

  static LocationPermissionState _map(LocationPermission p) => switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => LocationPermissionState.granted,
        LocationPermission.denied => LocationPermissionState.denied,
        LocationPermission.deniedForever => LocationPermissionState.deniedForever,
        LocationPermission.unableToDetermine => LocationPermissionState.unknown,
      };

  LocationSettings _settings(GpsAccuracyPreference pref) {
    final accuracy = switch (pref) {
      GpsAccuracyPreference.high => LocationAccuracy.best,
      GpsAccuracyPreference.balanced => LocationAccuracy.high,
      GpsAccuracyPreference.low => LocationAccuracy.medium,
    };
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
        useMSLAltitude: true,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: true,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return LocationSettings(accuracy: accuracy);
  }

  Stream<LocationModel> positions(GpsAccuracyPreference pref) =>
      Geolocator.getPositionStream(locationSettings: _settings(pref)).map((p) => toModel(p, LocationSource.gps));

  Stream<bool> serviceStatus() {
    if (!Platform.isAndroid) return const Stream.empty();
    return Geolocator.getServiceStatusStream().map((s) => s == ServiceStatus.enabled);
  }

  Future<LocationModel?> lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : toModel(p, LocationSource.lastKnown);
    } catch (_) {
      return null;
    }
  }

  Future<LocationModel> current(GpsAccuracyPreference pref, {Duration timeout = const Duration(seconds: 20)}) async {
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: _settings(pref)).timeout(timeout);
      return toModel(p, LocationSource.gps);
    } on TimeoutException {
      throw const AppException(AppErrorKind.gpsTimeout,
          'GPS timed out. Move to an open area with a clear view of the sky and try again.');
    } on LocationServiceDisabledException {
      throw const AppException(AppErrorKind.gpsDisabled, 'Location services are turned off.');
    } on PermissionDeniedException {
      throw const AppException(AppErrorKind.locationPermission, 'Location permission was denied.');
    }
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Converts a platform position, dropping values the platform did not provide.
  static LocationModel toModel(Position p, LocationSource source) {
    return LocationModel(
      latitude: p.latitude,
      longitude: p.longitude,
      altitude: p.hasAltitude ? p.altitude : null,
      altitudeAccuracy: p.hasAltitudeAccuracy ? p.altitudeAccuracy : null,
      accuracy: p.hasAccuracy ? p.accuracy : null,
      speed: p.hasSpeed && p.speed >= 0 ? p.speed : null,
      heading: p.hasHeading && p.heading >= 0 ? p.heading : null,
      detectedAt: p.timestamp.toLocal(),
      source: source,
      isMocked: p.isMocked,
    );
  }
}
