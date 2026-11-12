// Generates the app icon PNGs in assets/icon/.
//
// Design: a white map pin whose head is a camera lens with aperture blades,
// on a deep blue gradient with faint "map" contour rings.
//
// Run with:  flutter test tool/icon/generate_icon_test.dart
// Then:      dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _s = 1024.0;
const _bgTop = Color(0xFF0B1B3F);
const _bgMid = Color(0xFF14307A);
const _bgBottom = Color(0xFF2B63F0);
const _lensDark = Color(0xFF071029);
const _lensBlue = Color(0xFF3B82F6);
const _lensCyan = Color(0xFF5EEAD4);

/// Pin geometry (in 1024 space).
const _head = Offset(512, 430);
const _headR = 262.0;
const _tipY = 878.0;

enum _Mode { full, foreground, background, monochrome }

Path _pinPath() {
  const c = _head;
  const r = _headR;
  // Straight sides run from the tip to the points where they touch the circle.
  final a = math.acos(r / (_tipY - c.dy));
  final startAngle = math.pi / 2 + a; // left tangent point (canvas angles, y down)
  final left = c + Offset(math.cos(startAngle), math.sin(startAngle)) * r;
  return Path()
    ..moveTo(c.dx, _tipY)
    ..lineTo(left.dx, left.dy)
    ..arcTo(Rect.fromCircle(center: c, radius: r), startAngle, 2 * math.pi - 2 * a, false)
    ..close();
}

void _paintBackground(Canvas c) {
  const rect = Rect.fromLTWH(0, 0, _s, _s);
  c.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
        colors: [_bgTop, _bgMid, _bgBottom],
        stops: [0, 0.55, 1],
      ).createShader(rect),
  );
  // Glow behind the pin head.
  c.drawCircle(
    _head,
    480,
    Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF4F8BFF).withValues(alpha: 0.45),
        const Color(0xFF4F8BFF).withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: _head, radius: 480)),
  );
  // Map contour rings around the pin tip.
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..color = Colors.white.withValues(alpha: 0.07);
  for (var i = 1; i <= 6; i++) {
    c.drawOval(Rect.fromCenter(center: const Offset(512, _tipY), width: 150.0 * i, height: 52.0 * i), ring);
  }
}

void _paintAperture(Canvas c, Offset center, double r, {required bool mono}) {
  final lensRect = Rect.fromCircle(center: center, radius: r);
  if (!mono) {
    c.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.3),
          radius: 1.0,
          colors: [_lensCyan, _lensBlue, Color(0xFF1E3A8A), _lensDark],
          stops: [0, 0.35, 0.75, 1],
        ).createShader(lensRect),
    );
  }
  // Aperture blades: lines from each hexagon vertex, tangent-ish, to the rim.
  final rIn = r * 0.36;
  final verts = [
    for (var i = 0; i < 6; i++)
      center + Offset(math.cos(i * math.pi / 3 - math.pi / 2), math.sin(i * math.pi / 3 - math.pi / 2)) * rIn,
  ];
  final hex = Path()..addPolygon(verts, true);
  c.save();
  c.clipPath(Path()..addOval(lensRect));
  final blade = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = mono ? 14 : 9
    ..strokeCap = StrokeCap.round
    ..color = mono ? Colors.white : _lensDark.withValues(alpha: 0.85);
  for (var i = 0; i < 6; i++) {
    final v = verts[i];
    final dir = (verts[(i + 1) % 6] - v);
    final unit = dir / dir.distance;
    c.drawLine(v, v + unit * (r * 2), blade);
  }
  c.restore();
  if (mono) {
    c.drawPath(hex, Paint()..color = Colors.white);
  } else {
    c.drawPath(
      hex,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF0F1B3D), _lensDark]).createShader(
          Rect.fromCircle(center: center, radius: rIn),
        ),
    );
    // Glare: a soft highlight arc along the upper-left rim.
    c.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.78),
      math.pi * 1.06,
      math.pi * 0.36,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.5),
    );
    c.drawCircle(center + Offset(r * 0.42, r * 0.36), r * 0.06, Paint()..color = Colors.white.withValues(alpha: 0.35));
  }
}

void _paintGlyph(Canvas c, {required bool mono}) {
  final pin = _pinPath();
  if (!mono) {
    // Soft shadow.
    c.drawPath(
      pin.shift(const Offset(0, 22)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
    );
    c.drawPath(
      pin,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFDCE6F8)],
        ).createShader(Rect.fromLTRB(250, 168, 774, _tipY)),
    );
  }
  c.saveLayer(const Rect.fromLTWH(0, 0, _s, _s), Paint());
  if (mono) {
    c.drawPath(pin, Paint()..color = Colors.white);
    // Cut the lens out, then draw the aperture back in.
    c.drawCircle(_head, 196, Paint()..blendMode = BlendMode.clear);
    c.drawCircle(
      _head,
      196,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0,
    );
    _paintAperture(c, _head, 168, mono: true);
  } else {
    // Lens bezel.
    c.drawCircle(
      _head,
      200,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2A4E), _lensDark],
        ).createShader(Rect.fromCircle(center: _head, radius: 200)),
    );
    c.drawCircle(
      _head,
      186,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFF6E8FD8).withValues(alpha: 0.6),
    );
    _paintAperture(c, _head, 168, mono: false);
  }
  c.restore();
}

Future<void> _render(_Mode mode, String path) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder, const Rect.fromLTWH(0, 0, _s, _s));
  switch (mode) {
    case _Mode.full:
      _paintBackground(c);
      c.translate(0, 6);
      _paintGlyph(c, mono: false);
    case _Mode.background:
      _paintBackground(c);
    case _Mode.foreground:
    case _Mode.monochrome:
      // Adaptive icons show roughly the centre 61 %: shrink the glyph to fit.
      c.translate(_s / 2, _s / 2);
      c.scale(0.6);
      c.translate(-_s / 2, -_s / 2 + 10);
      _paintGlyph(c, mono: mode == _Mode.monochrome);
  }
  final image = await recorder.endRecording().toImage(_s.toInt(), _s.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('generate app icon PNGs', (tester) async {
    await tester.runAsync(() async {
      await _render(_Mode.full, 'assets/icon/app_icon.png');
      await _render(_Mode.background, 'assets/icon/app_icon_background.png');
      await _render(_Mode.foreground, 'assets/icon/app_icon_foreground.png');
      await _render(_Mode.monochrome, 'assets/icon/app_icon_monochrome.png');
    });
  });
}
