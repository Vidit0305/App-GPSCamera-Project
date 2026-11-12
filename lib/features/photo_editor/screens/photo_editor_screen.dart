import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../../shared/widgets/common.dart';
import '../../stamp_editor/services/image_render_service.dart';
import '../../stamp_editor/widgets/stamp_preview.dart';
import '../services/photo_service.dart';
import '../services/value_factories.dart';
import '../widgets/share_helper.dart';

/// Warnings produced while processing a capture, shown in the editor.
class CaptureWarnings extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() => const {};

  void add(String photoId, String message) {
    state = {
      ...state,
      photoId: [...?state[photoId], message],
    };
  }

  List<String> take(String photoId) {
    final w = state[photoId] ?? const [];
    state = {...state}..remove(photoId);
    return w;
  }
}

final captureWarningsProvider = NotifierProvider<CaptureWarnings, Map<String, List<String>>>(CaptureWarnings.new);

/// Editable stamp text fields, in display order.
const _textFields = [
  StampField.date,
  StampField.time,
  StampField.city,
  StampField.area,
  StampField.locality,
  StampField.street,
  StampField.district,
  StampField.state,
  StampField.country,
  StampField.postalCode,
  StampField.fullAddress,
  StampField.latitude,
  StampField.longitude,
  StampField.altitude,
  StampField.accuracy,
  StampField.weather,
  StampField.temperature,
  StampField.note,
];

/// Simple photo editor: preview + the text shown on the stamp.
class PhotoEditorScreen extends ConsumerStatefulWidget {
  const PhotoEditorScreen({super.key, required this.photoId, this.initialTab, this.isNewCapture = false});

  final String photoId;

  /// Kept for route compatibility; the editor has a single view.
  final String? initialTab;
  final bool isNewCapture;

  @override
  ConsumerState<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends ConsumerState<PhotoEditorScreen> {
  PhotoModel? _photo;
  String? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _saved = false;

  Size _imageSize = Size.zero;
  late StampValues _values;
  late StampTemplateModel _style;
  bool _applyStamp = false;
  PhotoMetadataModel _exif = const PhotoMetadataModel();
  Set<ExifField> _overrides = {};

  ui.Image? _map;
  String _mapKey = '';
  List<String> _warnings = [];

  final _controllers = {for (final f in _textFields) f: TextEditingController()};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _map?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ load

  Future<void> _load() async {
    try {
      final photo = await ref.read(photoRepositoryProvider).getById(widget.photoId);
      if (photo == null) {
        setState(() {
          _loading = false;
          _loadError = 'This photo no longer exists.';
        });
        return;
      }
      final settings = ref.read(settingsProvider);
      final base = photo.isOriginalPreserved ? photo.originalFilePath : photo.displayPath;
      final size = await ImageRenderService.imageSize(base);
      final style = photo.stampStyle ??
          ref.read(defaultTemplateProvider) ??
          await ref.read(templateRepositoryProvider).getById(settings.defaultTemplateId);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _imageSize = size;
        _style = style;
        _values = photo.stampValues ??
            StampValueFactory.build(
              location: photo.detectedLocation,
              weather: photo.detectedWeather,
              time: photo.capturedAt,
              settings: settings,
            );
        _applyStamp = photo.hasVisibleStamp;
        _exif = photo.exifEdits ?? const PhotoMetadataModel();
        _overrides = {...photo.exifOverrides};
        _warnings = ref.read(captureWarningsProvider.notifier).take(photo.id);
        _loading = false;
        _syncControllers();
      });
      unawaited(_refreshMap());
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = AppException.from(e).message;
        });
      }
    }
  }

  void _syncControllers() {
    for (final f in _textFields) {
      final c = _controllers[f]!;
      if (c.text != _values[f]) c.text = _values[f];
    }
  }

  Future<void> _refreshMap() async {
    final key = '${_style.includesMap}|${_values.mapLatitude}|${_values.mapLongitude}|${_style.mapZoom}';
    if (key == _mapKey) return;
    _mapKey = key;
    if (!_style.includesMap) return;
    final (img, _) = await ref.read(photoServiceProvider).loadMap(_style, _values);
    if (!mounted) {
      img?.dispose();
      return;
    }
    setState(() {
      _map?.dispose();
      _map = img;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  // ------------------------------------------------------------------ edits

  void _setValue(StampField f, String v) {
    setState(() => _values = _values.set(f, v));
    _markDirty();
  }

  void _setStyle(StampTemplateModel t) {
    setState(() => _style = t);
    _markDirty();
    unawaited(_refreshMap());
  }

  void _toggleField(StampField f, bool show) {
    Haptics.select();
    _setStyle(_style.toggleField(f, show));
  }

  void _applyValues(Map<StampField, String> changes, {double? mapLat, double? mapLon}) {
    setState(() {
      _values = StampValues(values: {..._values.values, ...changes}, mapLatitude: mapLat, mapLongitude: mapLon);
      _syncControllers();
    });
    _markDirty();
    unawaited(_refreshMap());
  }

  void _resetToDetected() {
    final p = _photo!;
    final fresh = StampValueFactory.build(
      location: p.detectedLocation,
      weather: p.detectedWeather,
      time: p.capturedAt,
      settings: ref.read(settingsProvider),
      note: _values[StampField.note],
    );
    _applyValues(fresh.values, mapLat: fresh.mapLatitude, mapLon: fresh.mapLongitude);
    showSnack(context, 'Restored the details detected when the photo was taken.');
  }

  /// Picks a new location on the map and applies it to the stamp text and
  /// to the photo's GPS metadata, so both stay consistent.
  Future<void> _changeLocation() async {
    final p = _photo!;
    final initial = _values.hasMapLocation
        ? LocationModel(latitude: _values.mapLatitude, longitude: _values.mapLongitude, source: LocationSource.manual)
        : p.detectedLocation;
    final picked = await context.push<LocationModel>(Routes.mapLocation, extra: initial);
    if (picked == null || !mounted) return;
    _applyValues(
      StampValueFactory.locationFields(picked, ref.read(settingsProvider)),
      mapLat: picked.latitude,
      mapLon: picked.longitude,
    );
    final (gps, fields) = ExifValueFactory.gpsFrom(picked.copyWith(detectedAt: p.capturedAt), fallbackTime: p.capturedAt);
    final j = _exif.toJson()
      ..['latitude'] = gps.latitude
      ..['longitude'] = gps.longitude
      ..['altitude'] = gps.altitude
      ..['gpsDateStamp'] = gps.gpsDateStamp
      ..['gpsTimeStamp'] = gps.gpsTimeStamp;
    setState(() {
      _exif = PhotoMetadataModel.fromJson(j);
      _overrides = {..._overrides, ...fields, ExifField.gpsAltitude};
    });
    showSnack(context, 'Location updated. Tap Save to apply it to the photo.');
  }

  Future<void> _lookUpAddress() async {
    final p = _photo!;
    final d = p.detectedLocation;
    if (d == null || !d.hasCoordinates) return;
    try {
      final addr = await ref
          .read(geocodingRepositoryProvider)
          .reverse(d.latitude!, d.longitude!, ref.read(settingsProvider), online: ref.read(isOnlineProvider));
      if (addr == null) {
        if (mounted) showSnack(context, 'No address was found for this place.');
        return;
      }
      final updated = p.copyWith(detectedLocation: d.withAddress(addr), addressPending: false, addressResolvedLater: true);
      await ref.read(photoServiceProvider).updateRecord(updated);
      setState(() => _photo = updated);
      await _fillEmptyFromDetected();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Fills empty stamp fields from the address resolved after capture.
  Future<void> _fillEmptyFromDetected() async {
    final p = _photo!;
    final fields = StampValueFactory.locationFields(p.detectedLocation, ref.read(settingsProvider));
    final changes = <StampField, String>{
      for (final e in fields.entries)
        if (_values[e.key].trim().isEmpty && e.value.isNotEmpty) e.key: e.value,
    };
    _applyValues(changes, mapLat: _values.mapLatitude, mapLon: _values.mapLongitude);
    final updated = p.copyWith(addressResolvedLater: false);
    await ref.read(photoServiceProvider).updateRecord(updated);
    setState(() => _photo = updated);
    if (mounted) showSnack(context, 'Address added. Tap Save to apply it.');
  }

  // ------------------------------------------------------------------ save / share / delete

  Future<bool> _save({required bool asNew}) async {
    final p = _photo;
    if (p == null || _saving) return false;
    setState(() => _saving = true);
    try {
      final service = ref.read(photoServiceProvider);
      final result = await service.saveEdits(
        p,
        EditRequest(
          stampValues: _values,
          style: _style,
          applyStamp: _applyStamp,
          exifDesired: _exif,
          exifOverrides: _overrides,
          asNew: asNew,
        ),
      );
      final warnings = [...result.warnings];
      if (widget.isNewCapture && !_saved) warnings.addAll(await service.autoExport(result.photo));
      _saved = true;
      if (!mounted) return true;
      final exif = result.exif;
      final exifFailed = exif != null && !exif.success;
      showSnack(
        context,
        [
          asNew ? 'Saved as a new photo.' : 'Photo saved.',
          if (exifFailed) 'The location could not be fully written into the photo file.',
          ...warnings,
        ].join(' '),
        error: exifFailed,
      );
      if (asNew) {
        context.pushReplacement(Routes.editor(result.photo.id));
      } else if (widget.isNewCapture) {
        context.pop();
      } else {
        setState(() {
          _dirty = false;
          _photo = result.photo;
        });
      }
      return true;
    } catch (e) {
      if (mounted) showError(context, AppException.from(e, fallback: AppErrorKind.imageProcessing));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    final p = _photo;
    if (p == null) return;
    if (_dirty) {
      final ok = await confirm(
        context,
        title: 'Save changes first?',
        message: 'Your latest changes need to be saved before sharing.',
        confirmLabel: 'Save & share',
      );
      if (!ok || !await _save(asNew: false)) return;
    }
    if (!mounted) return;
    await sharePhotosWithPrivacy(context, ref, [ref.read(photoByIdProvider(p.id)) ?? p]);
  }

  Future<void> _exportToDevice() async {
    final p = _photo;
    if (p == null) return;
    try {
      await ref.read(photoServiceProvider).exportToDevice(p);
      if (mounted) showSnack(context, 'Saved to your phone gallery.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete() async {
    final p = _photo;
    if (p == null) return;
    final ok = await confirm(
      context,
      title: 'Delete this photo?',
      message: 'The photo will be permanently removed from GPS Camera.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(photoServiceProvider).delete(p);
    _saved = true;
    if (mounted) context.pop();
  }

  Future<void> _retake() async {
    final p = _photo;
    if (p == null) return;
    await ref.read(photoServiceProvider).delete(p);
    _saved = true;
    if (mounted) context.pop();
  }

  /// Back navigation: new captures must be kept or discarded explicitly.
  Future<void> _onPopRequested() async {
    if (widget.isNewCapture && !_saved) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keep this photo?'),
          actions: [
            TextButton(onPressed: hx(() => Navigator.pop(ctx, 'discard')), child: const Text('Discard')),
            FilledButton(onPressed: hx(() => Navigator.pop(ctx, 'keep')), child: const Text('Keep')),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'keep') {
        if (_dirty) {
          await _save(asNew: false);
          return;
        }
        final warnings = await ref.read(photoServiceProvider).autoExport(_photo!);
        if (warnings.isNotEmpty && mounted) showSnack(context, warnings.join(' '), error: true);
      } else {
        await ref.read(photoServiceProvider).delete(_photo!);
      }
      _saved = true;
      if (mounted) context.pop();
      return;
    }
    if (_dirty) {
      final ok = await confirm(
        context,
        title: 'Discard changes?',
        message: 'Your unsaved changes will be lost.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    _saved = true;
    if (mounted) context.pop();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    final p = _photo;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorView(message: _loadError ?? 'Photo not found.', title: 'Cannot open photo'),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canStamp = p.isOriginalPreserved;
    final shown = _textFields.where(_style.shows).toList();
    final hidden = _textFields.where((f) => !_style.shows(f)).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopRequested();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNewCapture ? 'New photo' : 'Edit photo'),
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: hx(_onPopRequested)),
          actions: [
            IconButton(tooltip: 'Share', onPressed: _saving ? null : hx(_share), icon: const Icon(Icons.ios_share_rounded)),
            PopupMenuButton<String>(
              onOpened: Haptics.tap,
              onSelected: (v) async {
                Haptics.tap();
                switch (v) {
                  case 'export':
                    await _exportToDevice();
                  case 'retake':
                    await _retake();
                  case 'delete':
                    await _delete();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'export', child: ListTile(leading: Icon(Icons.save_alt_rounded), title: Text('Save to phone gallery'))),
                if (widget.isNewCapture)
                  const PopupMenuItem(value: 'retake', child: ListTile(leading: Icon(Icons.replay_rounded), title: Text('Retake'))),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                    title: Text('Delete', style: TextStyle(color: scheme.error)),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            // ---------------- preview
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: MediaQuery.sizeOf(context).height * 0.42,
                color: Colors.black,
                child: Stack(children: [
                  Positioned.fill(
                    child: StampPreview(
                      imagePath: canStamp ? p.originalFilePath : p.displayPath,
                      imageSize: _imageSize,
                      template: _style,
                      values: _values,
                      map: _map,
                      showStamp: _applyStamp && canStamp,
                      onPositionChanged: (x, y) =>
                          _setStyle(_style.copyWith(position: StampPosition.custom, customX: x, customY: y)),
                    ),
                  ),
                  if (_saving) const Positioned.fill(child: ColoredBox(color: Colors.black45, child: LoadingView())),
                ]),
              ),
            ),
            if (_applyStamp && canStamp)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Tip: drag the stamp to move it.',
                    textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 14),

            for (final w in _warnings) ...[
              InfoBanner(
                message: w,
                action: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: hx(() => setState(() => _warnings.remove(w))),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (p.addressPending) ...[
              InfoBanner(
                message: 'The address hasn\'t been looked up yet.',
                tone: ChipTone.info,
                icon: Icons.cloud_off_rounded,
                action: TextButton(onPressed: hx(_lookUpAddress), child: const Text('Look up')),
              ),
              const SizedBox(height: 10),
            ],
            if (p.addressResolvedLater) ...[
              InfoBanner(
                message: 'Address found: ${p.detectedLocation?.shortAddress ?? ''}',
                tone: ChipTone.info,
                icon: Icons.place_outlined,
                action: TextButton(onPressed: hx(_fillEmptyFromDetected), child: const Text('Add')),
              ),
              const SizedBox(height: 10),
            ],

            // ---------------- stamp on/off + location actions
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show stamp on photo'),
                subtitle: canStamp ? null : const Text('Not available for this photo'),
                value: _applyStamp && canStamp,
                onChanged: canStamp
                    ? hxv((v) {
                        setState(() => _applyStamp = v);
                        _markDirty();
                      })
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hx(_changeLocation),
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                  label: const Text('Change location'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hx(_resetToDetected),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset'),
                ),
              ),
            ]),

            // ---------------- fields
            const SizedBox(height: 22),
            Text('Shown on the photo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            if (shown.isEmpty)
              Text('Nothing is shown. Add details below.', style: theme.textTheme.bodySmall)
            else
              for (final f in shown) _field(f, visible: true),
            if (hidden.isNotEmpty) ...[
              const SizedBox(height: 6),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  onExpansionChanged: (_) => Haptics.select(),
                  title: Text('More details', style: theme.textTheme.titleSmall),
                  subtitle: Text('${hidden.length} hidden — tap + to show one', style: theme.textTheme.bodySmall),
                  children: [for (final f in hidden) _field(f, visible: false)],
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : hx(() => _save(asNew: true)),
                  child: const Text('Save as new'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _saving ? null : hx(() => _save(asNew: false)),
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded, size: 20),
                  label: const Text('Save'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(StampField f, {required bool visible}) {
    final c = _controllers[f]!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        readOnly: !visible,
        maxLines: f == StampField.fullAddress || f == StampField.note ? 3 : 1,
        minLines: 1,
        style: visible ? null : TextStyle(color: scheme.onSurfaceVariant),
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f == StampField.note ? 'Optional note' : null,
          suffixIcon: IconButton(
            tooltip: visible ? 'Hide from photo' : 'Show on photo',
            onPressed: () => _toggleField(f, !visible),
            icon: Icon(
              visible ? Icons.visibility_rounded : Icons.add_circle_outline_rounded,
              color: visible ? scheme.secondary : scheme.onSurfaceVariant,
            ),
          ),
        ),
        onChanged: (v) => _setValue(f, v),
      ),
    );
  }
}
