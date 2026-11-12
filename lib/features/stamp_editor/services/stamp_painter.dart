import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';

class _Line {
  _Line(this.icon, this.text, {this.title = false});
  final IconData icon;
  final String text;
  final bool title;
  late TextPainter painter;
  TextPainter? iconPainter;
}

/// Lays out and paints a visible stamp in *image pixel coordinates*.
///
/// The same code renders the live preview (scaled down by the canvas) and the
/// full-resolution export, so the preview is exactly what gets exported.
class StampLayout {
  StampLayout._(this.rect, this._t, this._lines, this._scale, this._pad, this._mapRect, this._textArea,
      this._map, this._mapPlaceholder, this._iconW, this._lineGap);

  /// Stamp bounding box in image coordinates. [Rect.zero] if nothing to draw.
  final Rect rect;
  final StampTemplateModel _t;
  final List<_Line> _lines;
  final double _scale;
  final double _pad; // ignore: unused_field
  final Rect? _mapRect;
  final Rect _textArea;
  final ui.Image? _map;
  final bool _mapPlaceholder;
  final double _iconW;
  final double _lineGap;

  bool get isEmpty => rect.isEmpty;

  static bool _looksNumeric(String s) => RegExp(r'^[-+±]?\s?\d').hasMatch(s.trim());

  static List<_Line> _buildLines(StampTemplateModel t, StampValues v) {
    String val(StampField f) => t.shows(f) ? v[f].trim() : '';
    String join(List<StampField> fs, String sep) {
      final out = <String>[];
      for (final f in fs) {
        final s = val(f);
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
      return out.join(sep);
    }

    String labelled(StampField f, String label) {
      final s = val(f);
      if (s.isEmpty) return '';
      return _looksNumeric(s) ? '$label $s' : s;
    }

    final lines = <_Line>[];
    void add(IconData icon, String text, {bool title = false}) {
      if (text.trim().isNotEmpty) lines.add(_Line(icon, text, title: title));
    }

    add(Icons.location_on, join([StampField.city, StampField.state, StampField.country], ', '), title: true);
    add(Icons.signpost_outlined,
        join([StampField.street, StampField.area, StampField.locality, StampField.district, StampField.postalCode], ', '));
    add(Icons.home_work_outlined, val(StampField.fullAddress));
    add(Icons.my_location,
        [labelled(StampField.latitude, 'Lat'), labelled(StampField.longitude, 'Long')]
            .where((e) => e.isNotEmpty)
            .join('   '));
    add(Icons.terrain_outlined,
        [labelled(StampField.altitude, 'Alt'), labelled(StampField.accuracy, 'Accuracy')]
            .where((e) => e.isNotEmpty)
            .join('  ·  '));
    add(Icons.schedule, join([StampField.date, StampField.time], '   '));
    add(Icons.wb_cloudy_outlined, join([StampField.weather, StampField.temperature], '  ·  '));
    add(Icons.notes, val(StampField.note));
    return lines;
  }

  /// Computes the layout for an image of [imageSize].
  ///
  /// [map] is the snapshot to draw; when the template wants a map but [map]
  /// is null, a placeholder is reserved only if [showMapPlaceholder] is true
  /// (editor preview) – exports simply omit the map.
  static StampLayout compute({
    required Size imageSize,
    required StampTemplateModel template,
    required StampValues values,
    ui.Image? map,
    bool showMapPlaceholder = false,
  }) {
    final t = template;
    final w = imageSize.width;
    final h = imageSize.height;
    final s = math.min(w, h) / 1080.0;
    final pad = t.padding * s;
    final margin = t.margin * s;
    final gap = 12 * s;
    final fontSize = t.fontSize * s;

    final wantMap = t.includesMap;
    final hasMap = wantMap && (map != null || showMapPlaceholder);
    final mapSide = hasMap ? t.mapSize.fraction * math.min(w, h) : 0.0;
    final mapSpace = hasMap ? mapSide + gap * 1.5 : 0.0;

    final boxMaxW = t.fullWidth ? w - 2 * margin : math.min(w * t.maxWidthFraction, w - 2 * margin);
    final iconW = t.showIcons ? fontSize * 1.05 + gap * 0.7 : 0.0;
    final textMaxW = math.max(40 * s, boxMaxW - 2 * pad - mapSpace - iconW);

    final lines = _buildLines(t, values);
    final shadows = t.shadow
        ? [Shadow(color: Colors.black.withValues(alpha: 0.75), blurRadius: 6 * s, offset: Offset(0, 1.5 * s))]
        : null;
    final textAlign = switch (t.alignment) {
      StampAlign.left => TextAlign.left,
      StampAlign.center => TextAlign.center,
      StampAlign.right => TextAlign.right,
    };

    var blockW = 0.0;
    var blockH = 0.0;
    final lineGap = fontSize * math.max(0, t.lineSpacing - 1) * 0.8 + 3 * s;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final size = l.title ? fontSize * 1.18 : fontSize;
      final style = TextStyle(
        fontFamily: t.fontFamily,
        fontSize: size,
        fontWeight: (l.title || t.bold) ? FontWeight.w700 : FontWeight.w400,
        fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
        color: Color(t.textColor),
        height: t.lineSpacing.clamp(1.0, 2.2),
        shadows: shadows,
      );
      l.painter = TextPainter(
        text: TextSpan(text: l.text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: textAlign,
        maxLines: l.title ? 2 : 3,
        ellipsis: '…',
      )..layout(maxWidth: textMaxW);
      if (t.showIcons) {
        l.iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(l.icon.codePoint),
            style: TextStyle(
              fontFamily: l.icon.fontFamily,
              package: l.icon.fontPackage,
              fontSize: size * 0.98,
              color: Color(t.accentColor),
              shadows: shadows,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      }
      blockW = math.max(blockW, l.painter.width + iconW);
      blockH += l.painter.height + (i == lines.length - 1 ? 0 : lineGap);
    }

    if (lines.isEmpty && !hasMap) {
      return StampLayout._(Rect.zero, t, lines, s, pad, null, Rect.zero, null, false, iconW, lineGap);
    }

    final contentH = math.max(blockH, mapSide);
    final boxW = t.fullWidth ? boxMaxW : blockW + mapSpace + 2 * pad;
    final boxH = contentH + 2 * pad;

    double x, y;
    switch (t.position) {
      case StampPosition.topLeft:
        x = margin;
        y = margin;
      case StampPosition.topRight:
        x = w - margin - boxW;
        y = margin;
      case StampPosition.bottomLeft:
        x = margin;
        y = h - margin - boxH;
      case StampPosition.bottomRight:
        x = w - margin - boxW;
        y = h - margin - boxH;
      case StampPosition.center:
        x = (w - boxW) / 2;
        y = (h - boxH) / 2;
      case StampPosition.custom:
        x = t.customX.clamp(0.0, 1.0) * math.max(0, w - boxW);
        y = t.customY.clamp(0.0, 1.0) * math.max(0, h - boxH);
    }
    if (t.fullWidth && t.position != StampPosition.custom) x = margin;
    final rect = Rect.fromLTWH(x, y, boxW, boxH);

    Rect? mapRect;
    var textLeft = x + pad;
    final textWidth = boxW - 2 * pad - mapSpace;
    if (hasMap) {
      final my = y + pad + (contentH - mapSide) / 2;
      if (t.mapPlacement == MapPlacement.left) {
        mapRect = Rect.fromLTWH(x + pad, my, mapSide, mapSide);
        textLeft += mapSpace;
      } else {
        mapRect = Rect.fromLTWH(x + boxW - pad - mapSide, my, mapSide, mapSide);
      }
    }
    final textArea = Rect.fromLTWH(textLeft, y + pad + (contentH - blockH) / 2, textWidth, blockH);
    return StampLayout._(rect, t, lines, s, pad, mapRect, textArea, map, hasMap && map == null, iconW, lineGap);
  }

  void paint(Canvas canvas) {
    if (isEmpty) return;
    final t = _t;
    final s = _scale;
    final radius = math.min(t.borderRadius * s, rect.height / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    if (t.backgroundOpacity > 0) {
      if (t.shadow) {
        canvas.drawRRect(
          rrect.shift(Offset(0, 4 * s)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * s),
        );
      }
      canvas.drawRRect(rrect, Paint()..color = Color(t.backgroundColor).withValues(alpha: t.backgroundOpacity));
    }
    if (t.borderWidth > 0) {
      canvas.drawRRect(
        rrect.deflate(t.borderWidth * s / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = t.borderWidth * s
          ..color = Color(t.borderColor),
      );
    }

    if (_mapRect != null) _paintMap(canvas, _mapRect);

    var y = _textArea.top;
    for (final l in _lines) {
      final lineW = l.painter.width + _iconW;
      final dx = switch (t.alignment) {
        StampAlign.left => 0.0,
        StampAlign.center => (_textArea.width - lineW) / 2,
        StampAlign.right => _textArea.width - lineW,
      };
      final left = _textArea.left + math.max(0, dx);
      final ip = l.iconPainter;
      if (ip != null) {
        final firstLine = l.painter.computeLineMetrics().firstOrNull;
        final lh = firstLine?.height ?? l.painter.preferredLineHeight;
        ip.paint(canvas, Offset(left, y + (lh - ip.height) / 2));
      }
      l.painter.paint(canvas, Offset(left + _iconW, y));
      y += l.painter.height + _lineGap;
    }
  }

  void _paintMap(Canvas canvas, Rect r) {
    final t = _t;
    final s = _scale;
    final rr = RRect.fromRectAndRadius(r, Radius.circular(t.mapRounded ? 14 * s : 0));
    canvas.save();
    canvas.clipRRect(rr);
    final img = _map;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        r,
        Paint()..filterQuality = FilterQuality.high,
      );
      if (t.mapShowMarker) _paintMarker(canvas, r.center, s);
      // Attribution required by the tile provider.
      final attr = TextPainter(
        text: TextSpan(
          text: Env.tileAttribution,
          style: TextStyle(fontFamily: 'Inter', fontSize: math.max(7, 9.5 * s), color: const Color(0xFF333333)),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: r.width - 6 * s);
      final ar = Rect.fromLTWH(r.right - attr.width - 6 * s, r.bottom - attr.height - 2 * s, attr.width + 6 * s,
          attr.height + 2 * s);
      canvas.drawRect(ar, Paint()..color = Colors.white.withValues(alpha: 0.75));
      attr.paint(canvas, Offset(ar.left + 3 * s, ar.top + 1 * s));
    } else if (_mapPlaceholder) {
      canvas.drawRect(r, Paint()..color = const Color(0xFF3A4252));
      final icon = Icons.map_outlined;
      final tp = TextPainter(
        text: TextSpan(
          text: '${String.fromCharCode(icon.codePoint)}\n',
          style: TextStyle(fontFamily: icon.fontFamily, fontSize: r.width * 0.28, color: Colors.white70),
          children: [
            TextSpan(
              text: 'Map unavailable',
              style: TextStyle(fontFamily: 'Inter', fontSize: r.width * 0.08, color: Colors.white70),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width);
      tp.paint(canvas, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2));
    }
    canvas.restore();
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  static void _paintMarker(Canvas canvas, Offset c, double s) {
    final r = 11 * s;
    final tip = Offset(c.dx, c.dy);
    final head = Offset(c.dx, c.dy - r * 1.9);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(head.dx - r * 1.25, head.dy + r * 0.6, head.dx - r, head.dy)
      ..arcTo(Rect.fromCircle(center: head, radius: r), math.pi, math.pi, false)
      ..quadraticBezierTo(head.dx + r * 1.25, head.dy + r * 0.6, tip.dx, tip.dy)
      ..close();
    canvas.drawPath(
      path.shift(Offset(0, 1.5 * s)),
      Paint()
        ..color = Colors.black38
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * s),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFE53935));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s
        ..color = Colors.white,
    );
    canvas.drawCircle(head, r * 0.4, Paint()..color = Colors.white);
  }
}

/// CustomPainter that draws a stamp over an image displayed at any size.
class StampOverlayPainter extends CustomPainter {
  StampOverlayPainter({
    required this.imageSize,
    required this.template,
    required this.values,
    this.map,
    this.showMapPlaceholder = true,
    this.highlight = false,
  });

  final Size imageSize;
  final StampTemplateModel template;
  final StampValues values;
  final ui.Image? map;
  final bool showMapPlaceholder;
  final bool highlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty) return;
    final scale = size.width / imageSize.width;
    canvas.save();
    canvas.scale(scale);
    final layout = StampLayout.compute(
      imageSize: imageSize,
      template: template,
      values: values,
      map: map,
      showMapPlaceholder: showMapPlaceholder,
    );
    layout.paint(canvas);
    if (highlight && !layout.isEmpty) {
      canvas.drawRect(
        layout.rect.inflate(4 / scale),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / scale
          ..color = const Color(0xFF6F8FF5),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StampOverlayPainter old) =>
      old.imageSize != imageSize ||
      old.template != template ||
      old.values != values ||
      old.map != map ||
      old.highlight != highlight ||
      old.showMapPlaceholder != showMapPlaceholder;
}
