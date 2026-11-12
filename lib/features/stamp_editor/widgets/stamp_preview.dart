import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';
import '../services/stamp_painter.dart';

/// Shows an image with the stamp painted on top using the exact export
/// renderer, scaled to the display size. Supports dragging the stamp to a
/// custom position.
class StampPreview extends StatefulWidget {
  const StampPreview({
    super.key,
    required this.imagePath,
    required this.imageSize,
    required this.template,
    required this.values,
    this.showStamp = true,
    this.map,
    this.onPositionChanged,
    this.background,
  });

  /// Image to show; null shows [background] (used for template previews).
  final String? imagePath;
  final Size imageSize;
  final StampTemplateModel template;
  final StampValues values;
  final bool showStamp;
  final ui.Image? map;

  /// Called with normalised custom coordinates while dragging.
  final void Function(double x, double y)? onPositionChanged;
  final Widget? background;

  @override
  State<StampPreview> createState() => _StampPreviewState();
}

class _StampPreviewState extends State<StampPreview> {
  bool _dragging = false;
  Rect? _startRect;
  Offset _dragAccum = Offset.zero;

  Rect _stampRect() => StampLayout.compute(
        imageSize: widget.imageSize,
        template: widget.template,
        values: widget.values,
        map: widget.map,
        showMapPlaceholder: true,
      ).rect;

  @override
  Widget build(BuildContext context) {
    final size = widget.imageSize;
    if (size.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final scale = math.min(c.maxWidth / size.width, c.maxHeight / size.height);
      final dw = size.width * scale;
      final dh = size.height * scale;
      return Center(
        child: SizedBox(
          width: dw,
          height: dh,
          child: GestureDetector(
            onPanStart: widget.onPositionChanged == null || !widget.showStamp
                ? null
                : (d) {
                    final r = _stampRect();
                    final local = d.localPosition / scale;
                    if (r.inflate(20 / scale).contains(local)) {
                      setState(() {
                        _dragging = true;
                        _startRect = r;
                        _dragAccum = Offset.zero;
                      });
                    }
                  },
            onPanUpdate: (d) {
              if (!_dragging || _startRect == null) return;
              _dragAccum += d.delta / scale;
              final r = _startRect!.shift(_dragAccum);
              final freeW = math.max(1.0, size.width - r.width);
              final freeH = math.max(1.0, size.height - r.height);
              widget.onPositionChanged?.call(
                (r.left / freeW).clamp(0.0, 1.0),
                (r.top / freeH).clamp(0.0, 1.0),
              );
            },
            onPanEnd: (_) => setState(() => _dragging = false),
            onPanCancel: () => setState(() => _dragging = false),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.imagePath != null)
                  Image.file(
                    File(widget.imagePath!),
                    fit: BoxFit.fill,
                    cacheWidth: (dw * MediaQuery.devicePixelRatioOf(context)).round(),
                    gaplessPlayback: true,
                  )
                else
                  widget.background ?? const ColoredBox(color: Colors.black),
                if (widget.showStamp)
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: StampOverlayPainter(
                        imageSize: size,
                        template: widget.template,
                        values: widget.values,
                        map: widget.map,
                        highlight: _dragging,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Neutral gradient used behind template previews (no real photo).
class PreviewBackdrop extends StatelessWidget {
  const PreviewBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B7DA8), Color(0xFF9DB4C9), Color(0xFF6E8B6A), Color(0xFF3F5A3A)],
          stops: [0, 0.45, 0.62, 1],
        ),
      ),
    );
  }
}

/// Field placeholders for previews where no real data exists. They are
/// descriptive labels, never presented as an actual location.
StampValues placeholderStampValues() => const StampValues(values: {
      StampField.date: 'DD/MM/YYYY',
      StampField.time: 'HH:MM:SS',
      StampField.city: 'City',
      StampField.state: 'State',
      StampField.country: 'Country',
      StampField.area: 'Area',
      StampField.locality: 'Locality',
      StampField.street: 'Street',
      StampField.district: 'District',
      StampField.postalCode: 'Postal code',
      StampField.fullAddress: 'Full address appears here',
      StampField.latitude: 'Latitude',
      StampField.longitude: 'Longitude',
      StampField.altitude: 'Altitude',
      StampField.accuracy: 'GPS accuracy',
      StampField.weather: 'Weather',
      StampField.temperature: 'Temperature',
      StampField.note: 'Custom note',
    });
