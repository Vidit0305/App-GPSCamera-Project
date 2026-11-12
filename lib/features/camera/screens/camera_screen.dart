import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/weather_model.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';
import '../../location/services/location_service.dart';
import '../../photo_editor/services/photo_service.dart';
import '../../photo_editor/services/value_factories.dart';
import '../../photo_editor/screens/photo_editor_screen.dart';
import '../../stamp_editor/services/stamp_painter.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

enum _CamStatus { initializing, ready, noPermission, noCamera, error }

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lens = CameraLensDirection.back;
  _CamStatus _status = _CamStatus.initializing;
  String? _error;
  FlashMode _flash = FlashMode.auto;
  double _minZoom = 1, _maxZoom = 1, _zoom = 1, _baseZoom = 1;
  double _minExposure = 0, _maxExposure = 0, _exposure = 0;
  bool _showExposure = false;
  bool _processing = false;
  String _processingLabel = '';
  Offset? _focusPoint;
  Timer? _clock;
  Timer? _focusTimer;
  StampTemplateModel? _template;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = ref.read(settingsProvider);
    _lens = s.defaultLens == LensSetting.front ? CameraLensDirection.front : CameraLensDirection.back;
    _flash = switch (s.defaultFlash) {
      FlashSetting.off => FlashMode.off,
      FlashSetting.auto => FlashMode.auto,
      FlashSetting.on => FlashMode.always,
    };
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!await ensureCameraPermission(context)) {
      if (mounted) setState(() => _status = _CamStatus.noPermission);
      return;
    }
    await _initCamera();
    if (!mounted) return;
    // Location: ask only when it has not been decided yet; never nag.
    final loc = ref.read(locationControllerProvider.notifier);
    await loc.start();
    final perm = ref.read(locationControllerProvider).permission;
    if (mounted && (perm == LocationPermissionState.unknown || perm == LocationPermissionState.denied)) {
      await ensureLocationPermission(context, ref);
    }
  }

  ResolutionPreset get _preset => switch (ref.read(settingsProvider).resolution) {
        CaptureResolution.medium => ResolutionPreset.medium,
        CaptureResolution.high => ResolutionPreset.high,
        CaptureResolution.veryHigh => ResolutionPreset.veryHigh,
        CaptureResolution.ultraHigh => ResolutionPreset.ultraHigh,
        CaptureResolution.max => ResolutionPreset.max,
      };

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    setState(() {
      _status = _CamStatus.initializing;
      _error = null;
    });
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _status = _CamStatus.noCamera);
        return;
      }
      final desc = _cameras.firstWhere((c) => c.lensDirection == _lens, orElse: () => _cameras.first);
      _lens = desc.lensDirection;
      final old = _controller;
      _controller = null;
      await old?.dispose();
      final c = CameraController(desc, _preset, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      try {
        await c.setJpegImageQuality(ref.read(settingsProvider).jpegQuality);
      } catch (_) {}
      try {
        await c.setFlashMode(_flash);
      } catch (_) {
        _flash = FlashMode.off;
      }
      try {
        _minZoom = await c.getMinZoomLevel();
        _maxZoom = await c.getMaxZoomLevel();
      } catch (_) {
        _minZoom = _maxZoom = 1;
      }
      try {
        _minExposure = await c.getMinExposureOffset();
        _maxExposure = await c.getMaxExposureOffset();
      } catch (_) {
        _minExposure = _maxExposure = 0;
      }
      _zoom = _minZoom;
      _exposure = 0;
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _status = _CamStatus.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.contains('Access') || e.code.contains('Permission');
      setState(() {
        _status = denied ? _CamStatus.noPermission : _CamStatus.error;
        _error = e.description ?? e.code;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _CamStatus.error;
          _error = '$e';
        });
      }
    } finally {
      _initializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (c != null) {
        _controller = null;
        c.dispose();
        if (mounted) setState(() => _status = _CamStatus.initializing);
      }
    } else if (state == AppLifecycleState.resumed && _controller == null && _status != _CamStatus.noPermission) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _focusTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- controls

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await _controller?.setFlashMode(next);
      setState(() => _flash = next);
    } on CameraException catch (e) {
      if (mounted) showSnack(context, 'Flash unavailable: ${e.description ?? e.code}', error: true);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _lens = _lens == CameraLensDirection.back ? CameraLensDirection.front : CameraLensDirection.back;
    await _initCamera();
  }

  Future<void> _setZoom(double z) async {
    final c = _controller;
    if (c == null) return;
    final v = z.clamp(_minZoom, _maxZoom);
    setState(() => _zoom = v);
    try {
      await c.setZoomLevel(v);
    } catch (_) {}
  }

  Future<void> _onTapPreview(TapDownDetails d, BoxConstraints box) async {
    final c = _controller;
    if (c == null) return;
    final p = Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight);
    setState(() => _focusPoint = d.localPosition);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    try {
      if (c.value.focusPointSupported) await c.setFocusPoint(p);
      if (c.value.exposurePointSupported) await c.setExposurePoint(p);
    } catch (_) {}
  }

  Future<void> _pickTemplate() async {
    final templates = ref.read(templatesProvider).value ?? const [];
    final current = _template ?? ref.read(defaultTemplateProvider);
    final picked = await showModalBottomSheet<StampTemplateModel>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Stamp template', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final t in templates)
              ListTile(
                leading: Icon(t.id == current?.id ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(t.name),
                subtitle: Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _template = picked);
  }

  Future<void> _pickResolution() async {
    final s = ref.read(settingsProvider);
    final picked = await showModalBottomSheet<CaptureResolution>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Resolution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final r in CaptureResolution.values)
              ListTile(
                leading: Icon(r == s.resolution ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(r.label),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != s.resolution) {
      await ref.read(settingsProvider.notifier).update((x) => x.copyWith(resolution: picked));
      await _initCamera();
    }
  }

  // --------------------------------------------------------------- capture

  WeatherModel? _freshWeather(LocationModel? loc) {
    final w = ref.read(locationControllerProvider).weather;
    if (w == null || loc == null || loc.source == LocationSource.manual) return null;
    if (DateTime.now().difference(w.observedAt) > const Duration(minutes: 30)) return null;
    return w;
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _processing || c.value.isTakingPicture) return;
    final template = _template ??
        ref.read(defaultTemplateProvider) ??
        await ref.read(templateRepositoryProvider).getById(ref.read(settingsProvider).defaultTemplateId);
    HapticFeedback.mediumImpact();
    final capturedAt = DateTime.now();
    final location = ref.read(locationControllerProvider.notifier).forCapture();
    final weather = _freshWeather(location);
    setState(() {
      _processing = true;
      _processingLabel = 'Capturing…';
    });
    try {
      final shot = await c.takePicture();
      if (mounted) setState(() => _processingLabel = 'Saving photo & metadata…');
      final result = await ref.read(photoServiceProvider).processCapture(
            shot: shot,
            location: location,
            weather: weather,
            template: template,
            capturedAt: capturedAt,
          );
      if (location == null) {
        ref.read(captureWarningsProvider.notifier).add(result.photo.id,
            'No location was available, so this photo has no GPS data. You can choose a location in the editor.');
      } else if (location.source == LocationSource.lastKnown) {
        ref.read(captureWarningsProvider.notifier).add(result.photo.id,
            'No live GPS fix – the last known position (${location.detectedAt != null ? Fmt.relative(location.detectedAt!) : 'earlier'}) was used.');
      }
      for (final w in result.warnings) {
        ref.read(captureWarningsProvider.notifier).add(result.photo.id, w);
      }
      if (!mounted) return;
      setState(() => _processing = false);
      await context.push(Routes.editor(result.photo.id, fresh: true));
    } on CameraException catch (e) {
      if (mounted) showSnack(context, 'Capture failed: ${e.description ?? e.code}', error: true);
    } catch (e) {
      if (mounted) showError(context, AppException.from(e, fallback: AppErrorKind.imageProcessing));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // --------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: switch (_status) {
            _CamStatus.noPermission => _Message(
                icon: Icons.no_photography_outlined,
                title: 'Camera access needed',
                message: 'Allow camera access to take photos.',
                primary: ('Grant access', _start),
                secondary: ('Open settings', () => showOpenSettingsDialog(context,
                    title: 'Camera access', message: 'Enable camera access for GPS Camera in system settings.')),
              ),
            _CamStatus.noCamera => _Message(
                icon: Icons.videocam_off_outlined,
                title: 'No camera found',
                message: 'This device does not report any camera.',
                primary: ('Close', () => context.pop()),
              ),
            _CamStatus.error => _Message(
                icon: Icons.error_outline,
                title: 'Camera could not start',
                message: _error ?? 'Unknown error',
                primary: ('Retry', _initCamera),
                secondary: ('Close', () => context.pop()),
              ),
            _ => _buildCamera(context),
          },
        ),
      ),
    );
  }

  Widget _buildCamera(BuildContext context) {
    final c = _controller;
    final ready = _status == _CamStatus.ready && c != null && c.value.isInitialized;
    return Stack(
      children: [
        Column(
          children: [
            _TopBar(
              flash: _flash,
              onClose: () => context.pop(),
              onFlash: ready ? _cycleFlash : null,
              onResolution: _pickResolution,
              onTemplate: _pickTemplate,
              onExposure: ready && _maxExposure > _minExposure ? () => setState(() => _showExposure = !_showExposure) : null,
            ),
            Expanded(
              child: Center(
                child: ready ? _buildPreview(c) : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
            if (ready && _maxZoom > _minZoom) _zoomBar(),
            _BottomBar(
              processing: _processing,
              onCapture: ready ? _capture : null,
              onSwitch: _cameras.length > 1 && !_processing ? _switchCamera : null,
            ),
          ],
        ),
        if (_processing)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 14),
                    Text(_processingLabel, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreview(CameraController c) {
    final settings = ref.watch(settingsProvider);
    final loc = ref.watch(locationControllerProvider);
    final template = _template ?? ref.watch(defaultTemplateProvider);
    final previewSize = c.value.previewSize;
    // Portrait: the sensor preview size is landscape; swap for display.
    final imageSize = previewSize == null ? const Size(3, 4) : Size(previewSize.height, previewSize.width);
    final location = loc.manual ?? loc.live;
    final values = StampValueFactory.build(
      location: location,
      weather: location?.source == LocationSource.manual ? null : loc.weather,
      time: DateTime.now(),
      settings: settings,
    );

    return AspectRatio(
      aspectRatio: imageSize.width / imageSize.height,
      child: LayoutBuilder(builder: (context, box) {
        return GestureDetector(
          onTapDown: (d) => _onTapPreview(d, box),
          onScaleStart: (_) => _baseZoom = _zoom,
          onScaleUpdate: (d) {
            if (d.pointerCount >= 2) _setZoom(_baseZoom * d.scale);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(child: CameraPreview(c)),
              if (template != null && settings.autoStamp)
                IgnorePointer(
                  child: Opacity(
                    opacity: 0.92,
                    child: CustomPaint(
                      painter: StampOverlayPainter(
                        imageSize: imageSize,
                        template: template,
                        values: values,
                        showMapPlaceholder: true,
                      ),
                    ),
                  ),
                ),
              Positioned(top: 10, left: 10, right: 10, child: _GpsChip(state: loc, settings: settings)),
              if (_focusPoint != null)
                Positioned(
                  left: _focusPoint!.dx - 32,
                  top: _focusPoint!.dy - 32,
                  child: IgnorePointer(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(border: Border.all(color: Colors.amber, width: 2), shape: BoxShape.circle),
                    ),
                  ),
                ),
              if (_showExposure)
                Positioned(
                  right: 4,
                  top: 60,
                  bottom: 60,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.amber,
                        thumbColor: Colors.amber,
                        inactiveTrackColor: Colors.white30,
                      ),
                      child: Slider(
                        value: _exposure.clamp(_minExposure, _maxExposure),
                        min: _minExposure,
                        max: _maxExposure,
                        onChanged: (v) async {
                          setState(() => _exposure = v);
                          try {
                            await c.setExposureOffset(v);
                          } catch (_) {}
                        },
                      ),
                    ),
                  ),
                ),
              if (!settings.autoStamp)
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: _Pill(text: 'Automatic stamp off', icon: Icons.layers_clear_outlined),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _zoomBar() {
    final presets = <double>{_minZoom, if (_maxZoom >= 2) 2, if (_maxZoom >= 5) 5}.toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final z in presets)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _setZoom(z),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_zoom - z).abs() < 0.05 ? Colors.white : Colors.white12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${z.toStringAsFixed(z == z.roundToDouble() ? 0 : 1)}×',
                    style: TextStyle(
                      color: (_zoom - z).abs() < 0.05 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Text('${_zoom.toStringAsFixed(1)}×', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _GpsChip extends StatelessWidget {
  const _GpsChip({required this.state, required this.settings});
  final LocationState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (IconData icon, Color color, String text) = () {
      if (state.manual != null) {
        return (Icons.edit_location_alt, Colors.lightBlueAccent, 'Manual: ${state.manual!.shortAddress.isEmpty ? 'selected point' : state.manual!.shortAddress}');
      }
      switch (state.permission) {
        case LocationPermissionState.granted:
          final live = state.live;
          if (live == null) return (Icons.gps_not_fixed, Colors.orangeAccent, 'Acquiring GPS…');
          final acc = Fmt.accuracy(live.accuracy, settings.distanceUnit);
          return state.weakSignal
              ? (Icons.gps_not_fixed, Colors.orangeAccent, 'Weak GPS $acc')
              : (Icons.gps_fixed, Colors.greenAccent, 'GPS $acc');
        case LocationPermissionState.serviceDisabled:
          return (Icons.location_off, Colors.redAccent, 'Location off – no GPS data');
        default:
          return (Icons.location_disabled, Colors.redAccent, 'No location permission');
      }
    }();
    return Row(
      children: [
        Flexible(child: _Pill(text: text, icon: icon, iconColor: color)),
        const SizedBox(width: 6),
        _Pill(text: '${Fmt.date(now, settings)}  ${Fmt.time(now, settings)}', icon: Icons.schedule),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon, this.iconColor = Colors.white});
  final String text;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.flash,
    required this.onClose,
    required this.onFlash,
    required this.onResolution,
    required this.onTemplate,
    required this.onExposure,
  });

  final FlashMode flash;
  final VoidCallback onClose;
  final VoidCallback? onFlash;
  final VoidCallback onResolution;
  final VoidCallback onTemplate;
  final VoidCallback? onExposure;

  @override
  Widget build(BuildContext context) {
    final flashIcon = switch (flash) {
      FlashMode.off => Icons.flash_off,
      FlashMode.auto => Icons.flash_auto,
      _ => Icons.flash_on,
    };
    final flashLabel = switch (flash) {
      FlashMode.off => 'Flash off',
      FlashMode.auto => 'Flash auto',
      _ => 'Flash on',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Colors.white), tooltip: 'Close'),
          const Spacer(),
          IconButton(onPressed: onFlash, icon: Icon(flashIcon, color: Colors.white), tooltip: flashLabel),
          IconButton(
            onPressed: onExposure,
            icon: Icon(Icons.exposure, color: onExposure == null ? Colors.white30 : Colors.white),
            tooltip: 'Exposure',
          ),
          IconButton(onPressed: onResolution, icon: const Icon(Icons.high_quality_outlined, color: Colors.white), tooltip: 'Resolution'),
          IconButton(onPressed: onTemplate, icon: const Icon(Icons.layers_outlined, color: Colors.white), tooltip: 'Stamp template'),
        ],
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.processing, required this.onCapture, required this.onSwitch});
  final bool processing;
  final VoidCallback? onCapture;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(photosProvider).value ?? const [];
    final last = photos.isEmpty ? null : (([...photos]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: last == null ? null : () => context.push(Routes.editor(last.id)),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white54, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: last == null
                  ? const Icon(Icons.photo_library_outlined, color: Colors.white54)
                  : PhotoThumb(path: last.displayPath, thumbnailPath: last.thumbnailPath, size: 60),
            ),
          ),
          GestureDetector(
            onTap: onCapture,
            child: Container(
              width: 78,
              height: 78,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: onCapture == null || processing ? Colors.white38 : Colors.white,
                ),
              ),
            ),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.white12, fixedSize: const Size(52, 52)),
            onPressed: onSwitch,
            icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
            tooltip: 'Switch camera',
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.message, required this.primary, this.secondary});
  final IconData icon;
  final String title;
  final String message;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            FilledButton(onPressed: primary.$2, child: Text(primary.$1)),
            if (secondary != null)
              TextButton(
                onPressed: secondary!.$2,
                child: Text(secondary!.$1, style: const TextStyle(color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }
}
