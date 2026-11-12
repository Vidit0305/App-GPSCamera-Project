// Generates the app icon PNGs in assets/icon/.
//
// Run with:  flutter test tool/icon/generate_icon_test.dart
// Then:      dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 1024.0;
const _navy = Color(0xFF0B1F3A);
const _navyMid = Color(0xFF173A7A);
const _royal = Color(0xFF2F5BEA);
const _royalLight = Color(0xFF8FB0FF);
const _amber = Color(0xFFFFC94D);

enum _Mode { full, foreground, background, monochrome }

void _paintBackground(Canvas c) {
  final rect = const Rect.fromLTWH(0, 0, _size, _size);
  c.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_navy, _navyMid, _royal],
        stops: [0, 0.55, 1],
      ).createShader(rect),
  );
  // Soft highlight for depth.
  c.drawCircle(
    const Offset(_size * 0.22, _size * 0.18),
    _size * 0.55,
    Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: const Offset(_size * 0.22, _size * 0.18), radius: _size * 0.55)),
  );
}

Path _pin(Offset head, double r) {
  final tip = Offset(head.dx, head.dy + r * 1.95);
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..quadraticBezierTo(head.dx - r * 1.28, head.dy + r * 0.62, head.dx - r, head.dy)
    ..arcTo(Rect.fromCircle(center: head, radius: r), math.pi, math.pi, false)
    ..quadraticBezierTo(head.dx + r * 1.28, head.dy + r * 0.62, tip.dx, tip.dy)
    ..close();
}

/// Camera body with a lens that contains a location pin.
void _paintGlyph(Canvas c, {required bool mono}) {
  final white = Paint()..color = Colors.white;
  final cut = Paint()..blendMode = BlendMode.clear;

  if (!mono) {
    // Subtle drop shadow under the camera body.
    c.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTRB(212, 352, 812, 782), const Radius.circular(96)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
  }

  c.saveLayer(const Rect.fromLTWH(0, 0, _size, _size), Paint());
  // Body + viewfinder hump.
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(212, 330, 812, 760), const Radius.circular(96)), white);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(372, 262, 572, 372), const Radius.circular(40)), white);

  const lens = Offset(512, 552);
  if (mono) {
    // Themed (monochrome) icon: lens is a cut-out ring with the pin inside.
    c.drawCircle(lens, 172, cut);
    c.drawCircle(lens, 150, white..style = PaintingStyle.stroke..strokeWidth = 18);
    white.style = PaintingStyle.fill;
    c.drawPath(_pin(const Offset(512, 520), 60), white);
    c.drawCircle(const Offset(512, 520), 23, cut);
    c.drawCircle(const Offset(708, 410), 22, cut);
  } else {
    c.drawCircle(
      lens,
      172,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navyMid],
        ).createShader(Rect.fromCircle(center: lens, radius: 172)),
    );
    c.drawCircle(
      lens,
      150,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = _royalLight,
    );
    // Lens glint.
    c.drawArc(
      Rect.fromCircle(center: lens, radius: 118),
      math.pi * 1.08,
      math.pi * 0.42,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    // Location pin.
    final pin = _pin(const Offset(512, 520), 60);
    c.drawPath(
      pin.shift(const Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    c.drawPath(pin, Paint()..color = _amber);
    c.drawCircle(const Offset(512, 520), 23, Paint()..color = _navy);
    // Flash indicator.
    c.drawCircle(const Offset(708, 410), 22, Paint()..color = _royal);
  }
  c.restore();
}

Future<void> _render(_Mode mode, String path) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder, const Rect.fromLTWH(0, 0, _size, _size));
  switch (mode) {
    case _Mode.full:
      _paintBackground(c);
      _paintGlyph(c, mono: false);
    case _Mode.background:
      _paintBackground(c);
    case _Mode.foreground:
    case _Mode.monochrome:
      // Adaptive icons are masked to the centre ~61 %: shrink the glyph.
      c.translate(_size / 2, _size / 2);
      c.scale(0.74);
      c.translate(-_size / 2, -_size / 2 + 6);
      _paintGlyph(c, mono: mode == _Mode.monochrome);
  }
  final image = await recorder.endRecording().toImage(_size.toInt(), _size.toInt());
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
    for (final n in ['app_icon', 'app_icon_background', 'app_icon_foreground', 'app_icon_monochrome']) {
      expect(File('assets/icon/$n.png').existsSync(), isTrue);
    }
  });
}
