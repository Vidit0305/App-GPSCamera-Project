import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/providers.dart';
import '../../../core/config/env.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/location_model.dart';
import '../../../data/remote/geocoding_provider.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';

enum _AddrStatus { idle, loading, ok, notFound, offline, noConsent, failed }

enum _F { city, area, address, state, country }

/// Lets the user choose a location on a map, by search, or by typing
/// coordinates. The result is always labelled as manually selected and never
/// changes the device's GPS position.
class MapLocationScreen extends ConsumerStatefulWidget {
  const MapLocationScreen({super.key, this.initial});

  final LocationModel? initial;

  @override
  ConsumerState<MapLocationScreen> createState() => _MapLocationScreenState();
}

class _MapLocationScreenState extends ConsumerState<MapLocationScreen> {
  final _map = MapController();
  late LatLng _center;
  late double _initialZoom;

  /// Whether a point has actually been chosen (false while showing the world).
  bool _selected = false;

  AddressModel? _address;
  _AddrStatus _status = _AddrStatus.idle;
  String? _statusMsg;
  Timer? _geoDebounce;
  int _geoSeq = 0;

  // Search
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  bool _searching = false;
  List<PlaceResult> _results = const [];
  String? _searchError;
  Future<List<LocationModel>>? _recents;

  // Manual detail fields
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _latFocus = FocusNode();
  final _lonFocus = FocusNode();
  final _alt = TextEditingController();
  final _fields = {for (final f in _F.values) f: TextEditingController()};
  final _edited = <_F>{};
  String? _coordError;
  String? _altError;

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? ref.read(locationControllerProvider).display;
    if (init != null && init.hasCoordinates) {
      _center = LatLng(init.latitude!, init.longitude!);
      _initialZoom = 16;
      _selected = true;
      if (widget.initial != null) {
        final i = widget.initial!;
        void seed(_F f, String? v) {
          if (v != null && v.trim().isNotEmpty) {
            _fields[f]!.text = v;
            _edited.add(f);
          }
        }

        seed(_F.city, i.city);
        seed(_F.area, i.area);
        seed(_F.address, i.fullAddress);
        seed(_F.state, i.state);
        seed(_F.country, i.country);
      }
      if (init.altitude != null) {
        final unit = ref.read(settingsProvider).altitudeUnit;
        _alt.text = unit == AltitudeUnit.metres
            ? init.altitude!.toStringAsFixed(1)
            : (init.altitude! * 3.28084).toStringAsFixed(0);
      }
    } else {
      _center = const LatLng(20, 0);
      _initialZoom = 2;
    }
    _syncCoordFields();
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) _recents ??= ref.read(geocodingRepositoryProvider).recents();
      setState(() {});
    });
    if (_selected) WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleGeocode(immediate: true));
  }

  @override
  void dispose() {
    _geoDebounce?.cancel();
    _searchDebounce?.cancel();
    _map.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _lat.dispose();
    _lon.dispose();
    _latFocus.dispose();
    _lonFocus.dispose();
    _alt.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  AppSettings get _settings => ref.read(settingsProvider);

  void _syncCoordFields() {
    if (!_latFocus.hasFocus) _lat.text = _center.latitude.toStringAsFixed(6);
    if (!_lonFocus.hasFocus) _lon.text = _center.longitude.toStringAsFixed(6);
    _coordError = null;
  }

  // ------------------------------------------------------------------ map

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (hasGesture) _selected = true;
    setState(_syncCoordFields);
    if (_selected) _scheduleGeocode();
  }

  void _moveTo(LatLng p, {double? zoom}) {
    _selected = true;
    _center = p;
    _map.move(p, zoom ?? (_map.camera.zoom < 14 ? 16 : _map.camera.zoom));
    setState(_syncCoordFields);
    _scheduleGeocode();
  }

  void _scheduleGeocode({bool immediate = false}) {
    _geoDebounce?.cancel();
    _geoDebounce = Timer(Duration(milliseconds: immediate ? 0 : 700), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    final seq = ++_geoSeq;
    final p = _center;
    setState(() {
      _status = _AddrStatus.loading;
      _statusMsg = null;
    });
    try {
      final addr = await ref
          .read(geocodingRepositoryProvider)
          .reverse(p.latitude, p.longitude, _settings, online: ref.read(isOnlineProvider));
      if (!mounted || seq != _geoSeq) return;
      setState(() {
        _address = addr;
        _status = addr == null ? _AddrStatus.notFound : _AddrStatus.ok;
        if (addr != null) _applyAddress(addr);
      });
    } on AppException catch (e) {
      if (!mounted || seq != _geoSeq) return;
      setState(() {
        _address = null;
        _status = switch (e.kind) {
          AppErrorKind.noConsent => _AddrStatus.noConsent,
          AppErrorKind.offline => _AddrStatus.offline,
          _ => _AddrStatus.failed,
        };
        _statusMsg = e.message;
        _clearUneditedAddress();
      });
    } catch (e) {
      if (!mounted || seq != _geoSeq) return;
      setState(() {
        _status = _AddrStatus.failed;
        _statusMsg = '$e';
        _clearUneditedAddress();
      });
    }
  }

  void _clearUneditedAddress() {
    for (final f in _F.values) {
      if (!_edited.contains(f)) _fields[f]!.text = '';
    }
  }

  /// Fills fields the user hasn't typed into from the looked-up address.
  void _applyAddress(AddressModel a) {
    final values = {
      _F.city: a.city ?? a.locality ?? '',
      _F.area: a.area ?? a.subLocality ?? '',
      _F.address: a.fullAddress ?? '',
      _F.state: a.state ?? '',
      _F.country: a.country ?? '',
    };
    for (final e in values.entries) {
      if (!_edited.contains(e.key)) _fields[e.key]!.text = e.value;
    }
  }

  void _resetEdits() {
    setState(() {
      _edited.clear();
      if (_address != null) {
        _applyAddress(_address!);
      } else {
        _clearUneditedAddress();
      }
    });
  }

  void _onCoordEdited() {
    final lat = Fmt.parseCoordinate(_lat.text, isLatitude: true);
    final lon = Fmt.parseCoordinate(_lon.text, isLatitude: false);
    if (lat == null || lon == null) {
      setState(() => _coordError = 'Enter valid coordinates (latitude −90…90, longitude −180…180).');
      return;
    }
    _latFocus.unfocus();
    _lonFocus.unfocus();
    _moveTo(LatLng(lat, lon));
  }

  // ------------------------------------------------------------------ search

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 3) {
      setState(() {
        _results = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 650), () => _runSearch(q.trim()));
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      if (!ref.read(isOnlineProvider)) {
        throw const AppException(AppErrorKind.offline, 'Search needs an internet connection.');
      }
      final r = await ref.read(geocodingRepositoryProvider).search(q, _settings);
      if (!mounted || _search.text.trim() != q) return;
      setState(() {
        _results = r;
        _searchError = r.isEmpty ? 'No places found for “$q”.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searchError = e is AppException ? e.message : 'Search failed: $e';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pickResult(PlaceResult r) {
    _searchFocus.unfocus();
    _search.text = r.title;
    _results = const [];
    _moveTo(LatLng(r.latitude, r.longitude), zoom: 16);
    if (r.address != null) {
      _geoDebounce?.cancel();
      _geoSeq++;
      setState(() {
        _address = r.address;
        _status = _AddrStatus.ok;
        _applyAddress(r.address!);
      });
    }
  }

  void _pickRecent(LocationModel l) {
    _searchFocus.unfocus();
    _moveTo(LatLng(l.latitude!, l.longitude!), zoom: 16);
  }

  // ------------------------------------------------------------------ actions

  Future<void> _useMyLocation() async {
    final ok = await ensureLocationPermission(context, ref);
    if (!ok || !mounted) return;
    var live = ref.read(locationControllerProvider).live;
    if (live == null) {
      try {
        live = await runWithProgress(
          context,
          'Getting GPS position…',
          () => ref.read(locationServiceProvider).current(_settings.gpsAccuracy),
        );
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
    }
    final fix = live;
    if (!mounted || fix == null || !fix.hasCoordinates) return;
    if (fix.altitude != null) {
      _alt.text = _settings.altitudeUnit == AltitudeUnit.metres
          ? fix.altitude!.toStringAsFixed(1)
          : (fix.altitude! * 3.28084).toStringAsFixed(0);
    }
    _moveTo(LatLng(fix.latitude!, fix.longitude!), zoom: 17);
  }

  void _zoom(double delta) {
    final z = (_map.camera.zoom + delta).clamp(2.0, 19.0);
    _map.move(_map.camera.center, z);
  }

  void _confirm() {
    final lat = Fmt.parseCoordinate(_lat.text, isLatitude: true) ?? _center.latitude;
    final lon = Fmt.parseCoordinate(_lon.text, isLatitude: false) ?? _center.longitude;
    double? altitude;
    if (_alt.text.trim().isNotEmpty) {
      altitude = Fmt.parseAltitude(_alt.text, _settings.altitudeUnit);
      if (altitude == null) {
        setState(() => _altError = 'Enter a number or leave empty');
        return;
      }
    }
    String? v(_F f) {
      final s = _fields[f]!.text.trim();
      return s.isEmpty ? null : s;
    }

    final a = _address;
    final anyAddress = _F.values.any((f) => v(f) != null);
    final result = LocationModel(
      latitude: lat,
      longitude: lon,
      altitude: altitude,
      street: a?.street,
      buildingNumber: a?.buildingNumber,
      area: v(_F.area),
      locality: a?.locality,
      subLocality: a?.subLocality,
      city: v(_F.city),
      district: a?.district,
      state: v(_F.state),
      postalCode: a?.postalCode,
      country: v(_F.country),
      countryCode: a?.countryCode,
      fullAddress: v(_F.address),
      detectedAt: DateTime.now(),
      source: LocationSource.manual,
      addressResolved: anyAddress,
      addressProvider: _edited.isEmpty ? a?.provider : 'Manual entry',
    );
    context.pop(result);
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final online = ref.watch(isOnlineProvider);
    final scheme = Theme.of(context).colorScheme;
    final showOverlay = _searchFocus.hasFocus;

    return Scaffold(
      appBar: AppBar(title: const Text('Select Location')),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _initialZoom,
                minZoom: 2,
                maxZoom: 19,
                backgroundColor: scheme.surfaceContainerHigh,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onTap: (_, p) => _moveTo(p, zoom: _map.camera.zoom),
                onPositionChanged: _onPositionChanged,
              ),
              children: [
                if (settings.onlineAllowed)
                  TileLayer(
                    urlTemplate: Env.tileUrlTemplate,
                    userAgentPackageName: Env.packageName,
                    maxNativeZoom: 19,
                  ),
                if (settings.onlineAllowed)
                  SimpleAttributionWidget(
                    source: Text(Env.tileAttribution, style: const TextStyle(fontSize: 11)),
                    alignment: Alignment.topRight,
                  ),
              ],
            ),
          ),
          // Fixed centre pin: the map moves underneath it.
          if (_selected)
            IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -22),
                  child: Icon(Icons.location_on, size: 46, color: Colors.red.shade600, shadows: const [
                    Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                  ]),
                ),
              ),
            )
          else
            const IgnorePointer(
              child: Center(child: Icon(Icons.add, size: 32, color: Colors.black54)),
            ),
          // Search bar + notices
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  color: scheme.surface,
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: (q) {
                      if (q.trim().isNotEmpty) _runSearch(q.trim());
                    },
                    decoration: InputDecoration(
                      hintText: 'Search for a place or address',
                      prefixIcon: const Icon(Icons.search),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : (_search.text.isNotEmpty || showOverlay)
                              ? IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _search.clear();
                                    _searchFocus.unfocus();
                                    setState(() {
                                      _results = const [];
                                      _searchError = null;
                                    });
                                  },
                                )
                              : null,
                    ),
                  ),
                ),
                if (showOverlay) _buildSearchOverlay(),
                if (!showOverlay && !settings.onlineAllowed) ...[
                  const SizedBox(height: 8),
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    color: scheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Map tiles, search and address lookup need online services.'),
                          const SizedBox(height: 4),
                          Text(
                            'You can still enter coordinates and address details manually below.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () async {
                              final ok = await requestOnlineConsent(context, ref);
                              if (ok && _selected) _scheduleGeocode(immediate: true);
                            },
                            icon: const Icon(Icons.public),
                            label: const Text('Enable online services'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (!showOverlay && settings.onlineAllowed && !online) ...[
                  const SizedBox(height: 8),
                  const InfoBanner(
                    icon: Icons.cloud_off,
                    message: 'You are offline. Only previously viewed (cached) map areas are shown.',
                  ),
                ],
              ],
            ),
          ),
          // Map controls
          Positioned(
            right: 12,
            bottom: MediaQuery.sizeOf(context).height * 0.36 + 8,
            child: Column(
              children: [
                _MapButton(icon: Icons.my_location, tooltip: 'My location', onPressed: _useMyLocation),
                const SizedBox(height: 10),
                _MapButton(icon: Icons.add, tooltip: 'Zoom in', onPressed: () => _zoom(1)),
                const SizedBox(height: 6),
                _MapButton(icon: Icons.remove, tooltip: 'Zoom out', onPressed: () => _zoom(-1)),
              ],
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.34,
            minChildSize: 0.2,
            maxChildSize: 0.9,
            builder: (context, controller) => Material(
              elevation: 8,
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: _buildPanel(controller, settings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchOverlay() {
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim();
    Widget content;
    if (query.length < 3) {
      content = FutureBuilder<List<LocationModel>>(
        future: _recents,
        builder: (context, snap) {
          final list = (snap.data ?? const []).where((l) => l.hasCoordinates).toList();
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
          }
          if (list.isEmpty) {
            return const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Type at least 3 characters to search'),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(dense: true, title: Text('Recent locations')),
              for (final l in list.take(6))
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(l.shortAddress.isNotEmpty ? l.shortAddress : 'Unnamed location'),
                  subtitle: Text(Fmt.latLng(l.latitude!, l.longitude!, _settings.coordinateFormat)),
                  onTap: () => _pickRecent(l),
                ),
            ],
          );
        },
      );
    } else if (_searchError != null) {
      content = ListTile(leading: const Icon(Icons.error_outline), title: Text(_searchError!));
    } else if (_results.isEmpty) {
      content = ListTile(
        leading: const Icon(Icons.search),
        title: Text(_searching ? 'Searching…' : 'Press search to look up “$query”'),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in _results)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: r.subtitle == null ? null : Text(r.subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => _pickResult(r),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(14),
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
          child: SingleChildScrollView(child: content),
        ),
      ),
    );
  }

  Widget _buildPanel(ScrollController controller, AppSettings settings) {
    final t = Theme.of(context);
    final (statusText, tone) = switch (_status) {
      _AddrStatus.idle => ('Move the map or tap to choose a point', ChipTone.neutral),
      _AddrStatus.loading => ('Looking up address…', ChipTone.info),
      _AddrStatus.ok => ('Address found${_address?.provider == null ? '' : ' · ${_address!.provider}'}', ChipTone.success),
      _AddrStatus.notFound => ('No address found here', ChipTone.warning),
      _AddrStatus.offline => (_statusMsg ?? 'Offline – address unavailable', ChipTone.warning),
      _AddrStatus.noConsent => ('Address lookup is off (online services disabled)', ChipTone.warning),
      _AddrStatus.failed => (_statusMsg ?? 'Address lookup failed', ChipTone.error),
    };
    final shortAddr = [_fields[_F.city]!.text, _fields[_F.state]!.text, _fields[_F.country]!.text]
        .where((e) => e.trim().isNotEmpty)
        .join(', ');

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: t.colorScheme.outline, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(
            label: 'Manually selected location — not from device GPS',
            icon: Icons.edit_location_alt_outlined,
            tone: ChipTone.info,
          ),
        ),
        const SizedBox(height: 12),
        if (!_selected)
          Text('No point selected yet', style: t.textTheme.titleMedium)
        else ...[
          Text(shortAddr.isNotEmpty ? shortAddr : 'Selected point', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(Fmt.latLng(_center.latitude, _center.longitude, settings.coordinateFormat),
              style: t.textTheme.bodyMedium),
          if (_fields[_F.address]!.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_fields[_F.address]!.text, style: t.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(child: StatusChip(label: statusText, tone: tone)),
            if (_status == _AddrStatus.failed || _status == _AddrStatus.offline)
              TextButton(onPressed: () => _scheduleGeocode(immediate: true), child: const Text('Retry')),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _selected ? _confirm : null,
          icon: const Icon(Icons.check),
          label: const Text('Confirm Location'),
        ),
        const SizedBox(height: 8),
        Theme(
          data: t.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Edit details'),
            subtitle: Text('Type coordinates or override the address', style: t.textTheme.bodySmall),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      focusNode: _latFocus,
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      onSubmitted: (_) => _onCoordEdited(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lon,
                      focusNode: _lonFocus,
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      onSubmitted: (_) => _onCoordEdited(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Go to coordinates',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _onCoordEdited,
                  ),
                ],
              ),
              if (_coordError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_coordError!, style: TextStyle(color: t.colorScheme.error, fontSize: 12)),
                ),
              const SizedBox(height: 10),
              for (final f in _F.values) ...[
                TextField(
                  controller: _fields[f],
                  textCapitalization: TextCapitalization.words,
                  maxLines: f == _F.address ? 3 : 1,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: switch (f) {
                      _F.city => 'City',
                      _F.area => 'Area',
                      _F.address => 'Address',
                      _F.state => 'State',
                      _F.country => 'Country',
                    },
                    suffixIcon: _edited.contains(f) ? const Icon(Icons.edit, size: 16) : null,
                  ),
                  onChanged: (_) => setState(() => _edited.add(f)),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _alt,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(
                  labelText: 'Altitude (${settings.altitudeUnit == AltitudeUnit.metres ? 'm' : 'ft'}) — optional',
                  helperText: 'Leave empty if unknown',
                  errorText: _altError,
                ),
                onChanged: (_) {
                  if (_altError != null) setState(() => _altError = null);
                },
              ),
              const SizedBox(height: 6),
              if (_edited.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _resetEdits,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset to looked-up address'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      shape: const CircleBorder(),
      child: IconButton(tooltip: tooltip, icon: Icon(icon), color: scheme.onSurface, onPressed: onPressed),
    );
  }
}
