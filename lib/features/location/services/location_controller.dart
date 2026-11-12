import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/weather_model.dart';
import 'location_service.dart';

enum AddressStatus { idle, loading, resolved, notFound, offline, noConsent, failed }

class LocationState {
  const LocationState({
    this.permission = LocationPermissionState.unknown,
    this.tracking = false,
    this.live,
    this.lastKnown,
    this.manual,
    this.addressStatus = AddressStatus.idle,
    this.addressMessage,
    this.weather,
    this.error,
  });

  final LocationPermissionState permission;

  /// Whether the GPS stream is active.
  final bool tracking;

  /// Most recent live GPS fix (with address once resolved).
  final LocationModel? live;

  /// Cached/OS last-known position, shown with its age; never treated as live.
  final LocationModel? lastKnown;

  /// User-selected location override for new photos.
  final LocationModel? manual;
  final AddressStatus addressStatus;
  final String? addressMessage;
  final WeatherModel? weather;
  final String? error;

  bool get acquiring => tracking && live == null;
  bool get weakSignal => (live?.accuracy ?? 0) > 50;

  /// What the UI should display: manual override, else live fix, else last known.
  LocationModel? get display => manual ?? live ?? lastKnown;

  LocationState copyWith({
    LocationPermissionState? permission,
    bool? tracking,
    LocationModel? live,
    LocationModel? lastKnown,
    LocationModel? manual,
    bool clearManual = false,
    AddressStatus? addressStatus,
    String? addressMessage,
    WeatherModel? weather,
    String? error,
    bool clearError = false,
  }) {
    return LocationState(
      permission: permission ?? this.permission,
      tracking: tracking ?? this.tracking,
      live: live ?? this.live,
      lastKnown: lastKnown ?? this.lastKnown,
      manual: clearManual ? null : manual ?? this.manual,
      addressStatus: addressStatus ?? this.addressStatus,
      addressMessage: addressMessage,
      weather: weather ?? this.weather,
      error: clearError ? null : error ?? this.error,
    );
  }
}

/// App-wide foreground location tracking with reverse geocoding and weather.
class LocationController extends Notifier<LocationState> {
  StreamSubscription<LocationModel>? _sub;
  StreamSubscription<bool>? _serviceSub;
  LocationModel? _geocodedAt;
  bool _geocoding = false;
  Timer? _debounce;

  LocationService get _service => ref.read(locationServiceProvider);

  @override
  LocationState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _serviceSub?.cancel();
      _debounce?.cancel();
    });
    // Re-resolve a pending address when connectivity returns.
    ref.listen<bool>(isOnlineProvider, (prev, online) {
      if (online && prev == false) _maybeGeocode(force: true);
    });
    final repo = ref.read(settingsRepositoryProvider);
    return LocationState(lastKnown: repo.lastLocation?.copyWith(source: LocationSource.lastKnown), manual: repo.manualLocation);
  }

  /// Checks permission without prompting and starts tracking if allowed.
  Future<void> start() async {
    final settings = ref.read(settingsProvider);
    final perm = await _service.checkPermission();
    if (!ref.mounted) return;
    state = state.copyWith(permission: perm);
    _serviceSub ??= _service.serviceStatus().listen((enabled) async {
      final p = await _service.checkPermission();
      if (!ref.mounted) return;
      state = state.copyWith(permission: p);
      if (enabled && p == LocationPermissionState.granted) {
        _startStream();
      } else {
        _stopStream();
      }
    });
    if (perm == LocationPermissionState.granted && settings.autoLocation) {
      final last = await _service.lastKnown();
      if (!ref.mounted) return;
      if (last != null && state.lastKnown == null) state = state.copyWith(lastKnown: last);
      _startStream();
    }
  }

  /// Prompts for permission (the UI shows a rationale first).
  Future<LocationPermissionState> requestPermission() async {
    final perm = await _service.requestPermission();
    if (!ref.mounted) return perm;
    state = state.copyWith(permission: perm, clearError: true);
    if (perm == LocationPermissionState.granted) _startStream();
    return perm;
  }

  void _startStream() {
    if (_sub != null) return;
    final pref = ref.read(settingsProvider).gpsAccuracy;
    state = state.copyWith(tracking: true, clearError: true);
    _sub = _service.positions(pref).listen(
      _onFix,
      onError: (Object e) {
        if (!ref.mounted) return;
        final msg = AppException.from(e, fallback: AppErrorKind.gpsDisabled, context: 'Location error').message;
        state = state.copyWith(error: msg);
        _stopStream();
      },
    );
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;
    if (ref.mounted) state = state.copyWith(tracking: false);
  }

  /// Pauses GPS (app backgrounded). Call [start] to resume.
  void pause() => _stopStream();

  /// Restarts tracking with new accuracy settings.
  Future<void> restart() async {
    _stopStream();
    await start();
  }

  void _onFix(LocationModel fix) {
    if (!ref.mounted) return;
    final prev = state.live;
    // Keep the previous address while the position hasn't moved meaningfully.
    var merged = fix;
    if (prev != null && prev.addressResolved && _distance(prev, fix) < 30) {
      merged = fix.withAddress(_addressOf(prev));
    }
    state = state.copyWith(live: merged, clearError: true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _maybeGeocode());
  }

  static AddressModel _addressOf(LocationModel l) => AddressModel(
        street: l.street,
        buildingNumber: l.buildingNumber,
        area: l.area,
        locality: l.locality,
        subLocality: l.subLocality,
        city: l.city,
        district: l.district,
        state: l.state,
        postalCode: l.postalCode,
        country: l.country,
        countryCode: l.countryCode,
        fullAddress: l.fullAddress,
        provider: l.addressProvider,
      );

  static double _distance(LocationModel a, LocationModel b) {
    const r = 6371000.0;
    final dLat = (b.latitude! - a.latitude!) * math.pi / 180;
    final dLon = (b.longitude! - a.longitude!) * math.pi / 180;
    final la1 = a.latitude! * math.pi / 180;
    final la2 = b.latitude! * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  Future<void> _maybeGeocode({bool force = false}) async {
    final live = state.live;
    if (live == null || !live.hasCoordinates || _geocoding) return;
    if (!force && live.addressResolved && _geocodedAt != null && _distance(_geocodedAt!, live) < 30) return;
    _geocoding = true;
    final settings = ref.read(settingsProvider);
    final online = ref.read(isOnlineProvider);
    state = state.copyWith(addressStatus: AddressStatus.loading);
    try {
      final addr = await ref
          .read(geocodingRepositoryProvider)
          .reverse(live.latitude!, live.longitude!, settings, online: online);
      if (!ref.mounted) return;
      _geocodedAt = live;
      if (addr == null) {
        state = state.copyWith(addressStatus: AddressStatus.notFound, addressMessage: 'No address found for this position.');
      } else {
        final current = state.live ?? live;
        final withAddr = current.withAddress(addr);
        state = state.copyWith(live: withAddr, addressStatus: AddressStatus.resolved);
        await ref.read(settingsRepositoryProvider).setLastLocation(withAddr);
        unawaited(_fetchWeather(withAddr));
      }
    } on AppException catch (e) {
      if (!ref.mounted) return;
      final status = switch (e.kind) {
        AppErrorKind.noConsent => AddressStatus.noConsent,
        AppErrorKind.offline => AddressStatus.offline,
        _ => AddressStatus.failed,
      };
      state = state.copyWith(addressStatus: status, addressMessage: e.message);
      // Still remember the coordinates so offline sessions have something to show.
      await ref.read(settingsRepositoryProvider).setLastLocation(live);
    } catch (e) {
      if (ref.mounted) state = state.copyWith(addressStatus: AddressStatus.failed, addressMessage: '$e');
    } finally {
      _geocoding = false;
    }
  }

  Future<void> retryAddress() => _maybeGeocode(force: true);

  Future<void> _fetchWeather(LocationModel l) async {
    final s = ref.read(settingsProvider);
    if (!s.fetchWeather || !s.onlineAllowed || !ref.read(isOnlineProvider)) return;
    try {
      final w = await ref.read(weatherServiceProvider).current(l.latitude!, l.longitude!);
      if (ref.mounted) state = state.copyWith(weather: w);
    } catch (_) {
      // Weather is optional; the stamp simply leaves it empty.
    }
  }

  Future<void> setManual(LocationModel? l) async {
    await ref.read(settingsRepositoryProvider).setManualLocation(l);
    if (l != null) await ref.read(geocodingRepositoryProvider).addRecent(l);
    state = l == null ? state.copyWith(clearManual: true) : state.copyWith(manual: l);
  }

  /// The location to attach to a photo captured now.
  ///
  /// Manual override first; then the live fix; then the OS last-known position
  /// only if it is recent (≤ 5 min), clearly labelled as such. Otherwise null —
  /// no location is invented.
  LocationModel? forCapture() {
    if (state.manual != null) return state.manual;
    final live = state.live;
    if (live != null && state.tracking) return live;
    final last = state.lastKnown;
    if (last != null &&
        last.detectedAt != null &&
        DateTime.now().difference(last.detectedAt!) <= const Duration(minutes: 5)) {
      return last.copyWith(source: LocationSource.lastKnown);
    }
    if (live != null &&
        live.detectedAt != null &&
        DateTime.now().difference(live.detectedAt!) <= const Duration(minutes: 2)) {
      return live;
    }
    return null;
  }

  void clearCachedData() {
    state = LocationState(
      permission: state.permission,
      tracking: state.tracking,
      live: state.live,
      manual: state.manual,
      addressStatus: state.addressStatus,
      weather: state.weather,
    );
  }
}

final locationControllerProvider = NotifierProvider<LocationController, LocationState>(LocationController.new);
