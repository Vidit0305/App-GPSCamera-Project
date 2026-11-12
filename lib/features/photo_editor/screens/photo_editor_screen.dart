import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../../shared/widgets/common.dart';
import '../../exif_editor/widgets/exif_editor_panel.dart';
import '../widgets/share_helper.dart';
import '../../stamp_editor/services/image_render_service.dart';
import '../../stamp_editor/widgets/stamp_preview.dart';
import '../../stamp_editor/widgets/stamp_style_editor.dart';
import '../services/photo_service.dart';
import '../services/value_factories.dart';

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

class PhotoEditorScreen extends ConsumerStatefulWidget {
  const PhotoEditorScreen({super.key, required this.photoId, this.initialTab, this.isNewCapture = false});

  final String photoId;
  final String? initialTab;
  final bool isNewCapture;

  @override
  ConsumerState<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

/// Text fields shown in the stamp tab, in display order.
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

class _PhotoEditorScreenState extends ConsumerState<PhotoEditorScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: switch (widget.initialTab) { 'style' => 1, 'exif' => 2, _ => 0 },
  );

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
  String? _stampLocationLabel;

  PhotoMetadataModel? _currentExif;
  String? _exifLoadError;
  PhotoMetadataModel _exif = const PhotoMetadataModel();
  Set<ExifField> _overrides = {};

  ui.Image? _map;
  String? _mapMessage;
  String _mapKey = '';
  List<String> _warnings = [];

  final _controllers = <StampField, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final f in _textFields) {
      _controllers[f] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _map?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

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
      PhotoMetadataModel? exif;
      String? exifErr;
      try {
        exif = await ref.read(exifServiceProvider).read(photo.displayPath);
      } on AppException catch (e) {
        exifErr = e.message;
      }
      final style = photo.stampStyle ??
          ref.read(defaultTemplateProvider) ??
          await ref.read(templateRepositoryProvider).getById(settings.defaultTemplateId);
      if (!mounted) return;
      final values = photo.stampValues ??
          StampValueFactory.build(
            location: photo.detectedLocation,
            weather: photo.detectedWeather,
            time: photo.capturedAt,
            settings: settings,
          );
      setState(() {
        _photo = photo;
        _imageSize = size;
        _style = style;
        _values = values;
        _applyStamp = photo.hasVisibleStamp;
        _currentExif = exif;
        _exifLoadError = exifErr;
        _exif = exif ?? photo.exifEdits ?? const PhotoMetadataModel();
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
      final v = _values[f];
      if (c.text != v) c.text = v;
    }
  }

  Future<void> _refreshMap() async {
    final key = '${_style.includesMap}|${_values.mapLatitude}|${_values.mapLongitude}|${_style.mapZoom}';
    if (key == _mapKey) return;
    _mapKey = key;
    if (!_style.includesMap) {
      setState(() => _mapMessage = null);
      return;
    }
    final (img, msg) = await ref.read(photoServiceProvider).loadMap(_style, _values);
    if (!mounted) {
      img?.dispose();
      return;
    }
    setState(() {
      _map?.dispose();
      _map = img;
      _mapMessage = msg;
    });
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  // ------------------------------------------------------------------ stamp edits

  void _setValue(StampField f, String v) {
    setState(() => _values = _values.set(f, v));
    _markDirty();
  }

  void _setStyle(StampTemplateModel t) {
    setState(() => _style = t);
    _markDirty();
    unawaited(_refreshMap());
  }

  void _applyValues(Map<StampField, String> changes, {double? mapLat, double? mapLon, bool setMap = false}) {
    setState(() {
      _values = setMap
          ? StampValues(values: {..._values.values, ...changes}, mapLatitude: mapLat, mapLongitude: mapLon)
          : _values.merge(changes);
      _syncControllers();
    });
    _markDirty();
    unawaited(_refreshMap());
  }

  void _resetStampToDetected() {
    final p = _photo!;
    final s = ref.read(settingsProvider);
    final fresh = StampValueFactory.build(
      location: p.detectedLocation,
      weather: p.detectedWeather,
      time: p.capturedAt,
      settings: s,
      note: _values[StampField.note],
    );
    _applyValues(fresh.values, mapLat: fresh.mapLatitude, mapLon: fresh.mapLongitude, setMap: true);
    setState(() => _stampLocationLabel = null);
    showSnack(context, 'Stamp text reset to the detected values.');
  }

  // ------------------------------------------------------------------ EXIF edits

  void _setExif(PhotoMetadataModel d, Set<ExifField> overrides) {
    setState(() {
      _exif = d;
      _overrides = overrides;
    });
    _markDirty();
  }

  /// Visible stamp → EXIF (parses what it can, reports what it can't).
  void _copyStampToExif() {
    final s = ref.read(settingsProvider);
    final problems = <String>[];
    final j = _exif.toJson();
    final fields = <ExifField>{};
    final lat = Fmt.parseCoordinate(_values[StampField.latitude], isLatitude: true);
    final lon = Fmt.parseCoordinate(_values[StampField.longitude], isLatitude: false);
    if (lat != null && lon != null) {
      j['latitude'] = lat;
      j['longitude'] = lon;
      fields.add(ExifField.gpsCoordinates);
    } else if (_values[StampField.latitude].isNotEmpty || _values[StampField.longitude].isNotEmpty) {
      problems.add('coordinates');
    }
    final altText = _values[StampField.altitude];
    final alt = Fmt.parseAltitude(altText, s.altitudeUnit);
    if (alt != null) {
      j['altitude'] = alt;
      fields.add(ExifField.gpsAltitude);
    } else if (altText.isNotEmpty && !altText.toLowerCase().contains('unavailable')) {
      problems.add('altitude');
    }
    final date = Fmt.parseDate(_values[StampField.date], s);
    final time = Fmt.parseTime(_values[StampField.time]);
    if (date != null) {
      final base = _exif.dateTimeOriginal ?? _photo!.capturedAt;
      final dt = DateTime(date.year, date.month, date.day, time?.h ?? base.hour, time?.m ?? base.minute, time?.s ?? base.second);
      j['dateTimeOriginal'] = dt.toIso8601String();
      j['dateTime'] = dt.toIso8601String();
      fields.addAll({ExifField.dateTimeOriginal, ExifField.dateTime});
    } else if (_values[StampField.date].isNotEmpty) {
      problems.add('date');
    }
    if (fields.isEmpty) {
      showSnack(context, 'Nothing in the stamp could be converted to EXIF values.', error: true);
      return;
    }
    _setExif(PhotoMetadataModel.fromJson(j), {..._overrides, ...fields});
    showSnack(
      context,
      problems.isEmpty
          ? 'Copied ${fields.length} value(s) from the stamp to EXIF. Save to write them.'
          : 'Copied what could be parsed. Could not convert: ${problems.join(', ')}.',
    );
  }

  /// EXIF → visible stamp.
  void _copyExifToStamp() {
    final changes = StampValueFactory.fromExif(_exif, ref.read(settingsProvider));
    if (changes.isEmpty) {
      showSnack(context, 'The EXIF data has no coordinates or date to copy.');
      return;
    }
    _applyValues(changes, mapLat: _exif.latitude, mapLon: _exif.longitude, setMap: _exif.hasGps);
    showSnack(context, 'Stamp updated from EXIF values.');
  }

  void _exifUseDetected() {
    final d = _photo!.detectedLocation;
    if (d == null || !d.hasCoordinates) {
      showSnack(context, 'No GPS location was detected for this photo.', error: true);
      return;
    }
    _applyLocationToExif(d);
    showSnack(context, 'EXIF GPS reset to the detected location. Save to write it.');
  }

  void _applyLocationToExif(LocationModel l) {
    final (gps, fields) = ExifValueFactory.gpsFrom(l, fallbackTime: _photo!.capturedAt);
    final j = _exif.toJson()
      ..['latitude'] = gps.latitude
      ..['longitude'] = gps.longitude
      ..['altitude'] = gps.altitude
      ..['gpsDateStamp'] = gps.gpsDateStamp
      ..['gpsTimeStamp'] = gps.gpsTimeStamp;
    _setExif(PhotoMetadataModel.fromJson(j), {..._overrides, ...fields, ExifField.gpsAltitude});
  }

  // ------------------------------------------------------------------ manual location

  Future<void> _pickOnMap() async {
    final p = _photo!;
    final initial = _values.hasMapLocation
        ? LocationModel(latitude: _values.mapLatitude, longitude: _values.mapLongitude, source: LocationSource.manual)
        : p.detectedLocation;
    final picked = await context.push<LocationModel>(Routes.mapLocation, extra: initial);
    if (picked == null || !mounted) return;
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Apply selected location to…', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('The detected GPS record of this photo is not changed.'),
          ),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Visible stamp only'),
            onTap: () => Navigator.pop(ctx, 'stamp'),
          ),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: const Text('EXIF metadata only'),
            onTap: () => Navigator.pop(ctx, 'exif'),
          ),
          ListTile(
            leading: const Icon(Icons.done_all),
            title: const Text('Both stamp and EXIF'),
            onTap: () => Navigator.pop(ctx, 'both'),
          ),
        ]),
      ),
    );
    if (target == null || !mounted) return;
    final s = ref.read(settingsProvider);
    if (target == 'stamp' || target == 'both') {
      final fields = StampValueFactory.locationFields(picked, s);
      _applyValues(fields, mapLat: picked.latitude, mapLon: picked.longitude, setMap: true);
      setState(() => _stampLocationLabel = 'Manually selected location');
    }
    if (target == 'exif' || target == 'both') {
      _applyLocationToExif(picked.copyWith(detectedAt: p.capturedAt));
    }
  }

  Future<void> _lookUpAddressNow() async {
    final p = _photo!;
    final d = p.detectedLocation;
    if (d == null || !d.hasCoordinates) return;
    try {
      final addr = await ref
          .read(geocodingRepositoryProvider)
          .reverse(d.latitude!, d.longitude!, ref.read(settingsProvider), online: ref.read(isOnlineProvider));
      if (addr == null) {
        if (mounted) showSnack(context, 'No address was found for these coordinates.');
        return;
      }
      final updated = p.copyWith(detectedLocation: d.withAddress(addr), addressPending: false, addressResolvedLater: true);
      await ref.read(photoServiceProvider).updateRecord(updated);
      setState(() => _photo = updated);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Fills empty address fields of the stamp from the (later) resolved address.
  Future<void> _applyResolvedAddress() async {
    final p = _photo!;
    final fields = StampValueFactory.locationFields(p.detectedLocation, ref.read(settingsProvider));
    final changes = <StampField, String>{};
    for (final e in fields.entries) {
      if (_values[e.key].trim().isEmpty && e.value.isNotEmpty) changes[e.key] = e.value;
    }
    _applyValues(changes);
    final updated = p.copyWith(addressResolvedLater: false);
    await ref.read(photoServiceProvider).updateRecord(updated);
    setState(() => _photo = updated);
    if (mounted) showSnack(context, 'Filled ${changes.length} empty field(s). Save to update the photo.');
  }

  // ------------------------------------------------------------------ save / share / discard

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
      if (exif != null && !exif.success) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded),
            title: const Text('Saved, but metadata needs attention'),
            content: SingleChildScrollView(child: Text([exif.summary, ...warnings].join('\n\n'))),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      } else {
        final msg = [
          asNew ? 'Saved as a new photo.' : 'Photo saved.',
          if (exif != null) exif.summary,
          ...warnings,
        ].join(' ');
        showSnack(context, msg);
      }
      if (!mounted) return true;
      if (asNew) {
        context.pushReplacement(Routes.editor(result.photo.id));
      } else if (widget.isNewCapture) {
        context.pop();
      } else {
        setState(() {
          _dirty = false;
          _photo = result.photo;
        });
        // Re-read the actual file metadata after the save.
        try {
          final fresh = await ref.read(exifServiceProvider).read(result.photo.displayPath);
          if (mounted) {
            setState(() {
              _currentExif = fresh;
              _exif = fresh;
            });
          }
        } catch (_) {}
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
        title: 'Unsaved changes',
        message: 'Sharing uses the last saved version. Save your changes first?',
        confirmLabel: 'Save & share',
      );
      if (!ok || !await _save(asNew: false)) return;
    }
    if (!mounted) return;
    final latest = ref.read(photoByIdProvider(p.id)) ?? p;
    await sharePhotosWithPrivacy(context, ref, [latest]);
  }

  Future<void> _discard() async {
    final p = _photo;
    if (p == null) return;
    final ok = await confirm(
      context,
      title: 'Discard photo?',
      message: 'The photo and its preserved original will be deleted from GPS Camera.',
      confirmLabel: 'Discard',
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

  Future<void> _revert() async {
    setState(() {
      _loading = true;
      _dirty = false;
      _mapKey = '';
    });
    await _load();
  }

  /// Back navigation guard: new captures must be kept or discarded explicitly.
  Future<void> _onPopRequested() async {
    if (widget.isNewCapture && !_saved) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keep this photo?'),
          content: Text(_dirty
              ? 'You have unsaved edits. Save them, keep the photo as captured, or discard it.'
              : 'Keep the photo as captured, or discard it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
            if (_dirty) TextButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: const Text('Keep as captured')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _dirty ? 'save' : 'keep'),
              child: Text(_dirty ? 'Save' : 'Keep'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      switch (choice) {
        case 'save':
          await _save(asNew: false);
        case 'keep':
          final warnings = await ref.read(photoServiceProvider).autoExport(_photo!);
          _saved = true;
          if (warnings.isNotEmpty && mounted) showSnack(context, warnings.join(' '), error: true);
          if (mounted) context.pop();
        case 'discard':
          await ref.read(photoServiceProvider).delete(_photo!);
          _saved = true;
          if (mounted) context.pop();
      }
      return;
    }
    if (_dirty) {
      final ok = await confirm(
        context,
        title: 'Discard changes?',
        message: 'Your unsaved edits will be lost.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    _saved = true;
    if (mounted) context.pop();
  }

  Future<void> _exportToDevice() async {
    final p = _photo;
    if (p == null) return;
    try {
      await ref.read(photoServiceProvider).exportToDevice(p);
      if (mounted) showSnack(context, 'Saved to your phone gallery (album "${PhotoService.deviceAlbum}").');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _saveAsTemplate() async {
    final ctrl = TextEditingController(text: '${_style.name} (custom)');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as template'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Template name'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final saved = await ref.read(templateRepositoryProvider).save(_style.copyWith(
            id: const Uuid().v4(),
            name: name,
            isBuiltIn: false,
            description: 'Created from the photo editor',
            createdAt: DateTime.now(),
          ));
      setState(() => _style = saved);
      if (mounted) showSnack(context, 'Template "$name" saved.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView(message: 'Opening photo…'));
    final p = _photo;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorView(message: _loadError ?? 'Photo not found.', title: 'Cannot open photo'),
      );
    }
    final theme = Theme.of(context);
    final canStamp = p.isOriginalPreserved;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopRequested();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNewCapture ? 'New photo' : 'Edit photo'),
          actions: [
            IconButton(tooltip: 'Share', onPressed: _saving ? null : _share, icon: const Icon(Icons.ios_share)),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'retake':
                    await _retake();
                  case 'discard':
                    await _discard();
                  case 'revert':
                    await _revert();
                  case 'export':
                    await _exportToDevice();
                  case 'template':
                    await _saveAsTemplate();
                }
              },
              itemBuilder: (_) => [
                if (widget.isNewCapture)
                  const PopupMenuItem(value: 'retake', child: ListTile(leading: Icon(Icons.replay), title: Text('Retake'))),
                if (_dirty && !widget.isNewCapture)
                  const PopupMenuItem(value: 'revert', child: ListTile(leading: Icon(Icons.undo), title: Text('Revert changes'))),
                const PopupMenuItem(
                    value: 'template', child: ListTile(leading: Icon(Icons.bookmark_add_outlined), title: Text('Save style as template'))),
                if (!widget.isNewCapture)
                  const PopupMenuItem(
                      value: 'export',
                      child: ListTile(leading: Icon(Icons.save_alt), title: Text('Save to phone gallery'))),
                PopupMenuItem(
                  value: 'discard',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    title: Text(widget.isNewCapture ? 'Discard' : 'Delete photo'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // ---------------- preview
            Container(
              height: MediaQuery.sizeOf(context).height * 0.36,
              color: Colors.black,
              padding: const EdgeInsets.all(8),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: StampPreview(
                      imagePath: canStamp ? p.originalFilePath : p.displayPath,
                      imageSize: _imageSize,
                      template: _style,
                      values: _values,
                      map: _map,
                      showStamp: _applyStamp && canStamp,
                      onPositionChanged: (x, y) => _setStyle(
                        _style.copyWith(position: StampPosition.custom, customX: x, customY: y),
                      ),
                    ),
                  ),
                  if (_saving)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black45,
                        child: LoadingView(),
                      ),
                    ),
                ],
              ),
            ),
            Material(
              color: theme.colorScheme.surface,
              child: TabBar(
                controller: _tabs,
                labelColor: theme.colorScheme.secondary,
                indicatorColor: theme.colorScheme.secondary,
                tabs: const [
                  Tab(icon: Icon(Icons.text_fields, size: 20), text: 'Stamp text'),
                  Tab(icon: Icon(Icons.palette_outlined, size: 20), text: 'Stamp style'),
                  Tab(icon: Icon(Icons.data_object, size: 20), text: 'EXIF'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildStampText(p),
                  _buildStyle(p),
                  SingleChildScrollView(
                    child: ExifEditorPanel(
                      current: _currentExif,
                      desired: _exif,
                      overrides: _overrides,
                      settings: ref.watch(settingsProvider),
                      onChanged: _setExif,
                      status: p.exifStatus,
                      statusMessage: p.exifStatusMessage,
                      originalExif: p.originalExif,
                      loadError: _exifLoadError,
                      onCopyFromStamp: _copyStampToExif,
                      onCopyToStamp: _copyExifToStamp,
                      onUseDetected: _exifUseDetected,
                      onPickOnMap: _pickOnMap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(asNew: true),
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Save as new'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _save(asNew: false),
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(_dirty || widget.isNewCapture ? 'Save' : 'Saved'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStampText(PhotoModel p) {
    final theme = Theme.of(context);
    final detected = p.detectedLocation;
    final sourceLabel = _stampLocationLabel ?? (detected?.source.label ?? LocationSource.none.label);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final w in _warnings) ...[
          InfoBanner(
            message: w,
            tone: ChipTone.warning,
            action: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _warnings.remove(w)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (!p.isOriginalPreserved) ...[
          const InfoBanner(
            message: 'The unstamped original of this photo was not preserved, so the visible stamp cannot be re-rendered. '
                'EXIF metadata can still be edited.',
            tone: ChipTone.warning,
          ),
          const SizedBox(height: 8),
        ],
        if (p.addressPending) ...[
          InfoBanner(
            message: 'Coordinates were saved, but the address has not been looked up yet.',
            tone: ChipTone.info,
            icon: Icons.cloud_off,
            action: TextButton(onPressed: _lookUpAddressNow, child: const Text('Look up')),
          ),
          const SizedBox(height: 8),
        ],
        if (p.addressResolvedLater) ...[
          InfoBanner(
            message: 'The address was resolved after capture: ${p.detectedLocation?.shortAddress ?? ''}. '
                'Your stamp text was not changed.',
            tone: ChipTone.info,
            icon: Icons.place_outlined,
            action: TextButton(onPressed: _applyResolvedAddress, child: const Text('Fill empty')),
          ),
          const SizedBox(height: 8),
        ],
        if (_mapMessage != null && _style.includesMap) ...[
          InfoBanner(message: _mapMessage!, tone: ChipTone.warning, icon: Icons.map_outlined),
          const SizedBox(height: 8),
        ],
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visible stamp on photo'),
            subtitle: Text(p.isOriginalPreserved
                ? 'Rendered into the exported image at full resolution'
                : 'Unavailable – original not preserved'),
            value: _applyStamp && p.isOriginalPreserved,
            onChanged: p.isOriginalPreserved
                ? (v) {
                    setState(() => _applyStamp = v);
                    _markDirty();
                  }
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          StatusChip(
            label: 'Stamp location: $sourceLabel',
            icon: _stampLocationLabel != null ? Icons.edit_location_alt_outlined : Icons.gps_fixed,
            tone: _stampLocationLabel != null ? ChipTone.info : ChipTone.neutral,
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.map_outlined, size: 16), label: const Text('Pick on map'), onPressed: _pickOnMap),
          ActionChip(
            avatar: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Reset to detected'),
            onPressed: _resetStampToDetected,
          ),
          ActionChip(avatar: const Icon(Icons.south, size: 16), label: const Text('Copy to EXIF'), onPressed: _copyStampToExif),
          ActionChip(avatar: const Icon(Icons.north, size: 16), label: const Text('Copy from EXIF'), onPressed: _copyExifToStamp),
        ]),
        const SectionHeader('Stamp fields'),
        Text(
          'Edit any text freely. The eye icon controls whether a field is shown on the photo.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final f in _textFields) _fieldRow(f),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
              'Show map snapshot',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Switch(value: _style.includesMap, onChanged: (v) => _setStyle(_style.toggleField(StampField.map, v))),
        ]),
      ],
    );
  }

  Widget _fieldRow(StampField f) {
    final visible = _style.shows(f);
    final c = _controllers[f]!;
    final hint = switch (f) {
      StampField.weather || StampField.temperature => 'When available',
      StampField.note => 'Optional note shown on the stamp',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          IconButton(
            tooltip: visible ? 'Hide on stamp' : 'Show on stamp',
            onPressed: () => _setStyle(_style.toggleField(f, !visible)),
            icon: Icon(
              visible ? Icons.visibility : Icons.visibility_off_outlined,
              color: visible ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: TextField(
              controller: c,
              maxLines: f == StampField.fullAddress || f == StampField.note ? 3 : 1,
              minLines: 1,
              decoration: InputDecoration(
                labelText: f.label,
                hintText: hint,
                suffixIcon: ValueListenableBuilder(
                  valueListenable: c,
                  builder: (_, v, _) => v.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            c.clear();
                            _setValue(f, '');
                          },
                        ),
                ),
              ),
              onChanged: (v) => _setValue(f, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyle(PhotoModel p) {
    final templates = ref.watch(templatesProvider).value ?? const <StampTemplateModel>[];
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        if (!p.isOriginalPreserved)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: InfoBanner(message: 'Stamp style changes cannot be applied because the original was not preserved.'),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SectionHeader('Template', padding: EdgeInsets.fromLTRB(4, 8, 4, 8)),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: templates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final t = templates[i];
              return ChoiceChip(
                label: Text(t.name),
                selected: _style.id == t.id,
                onSelected: (_) {
                  _setStyle(t);
                  if (!_applyStamp && p.isOriginalPreserved) setState(() => _applyStamp = true);
                },
              );
            },
          ),
        ),
        StampStyleEditor(template: _style, onChanged: _setStyle),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: OutlinedButton.icon(
            onPressed: _saveAsTemplate,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Save this style as a template'),
          ),
        ),
      ],
    );
  }
}
