import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera/data/models/stamp_template_model.dart';
import 'package:gps_camera/data/models/stamp_values.dart';
import 'package:gps_camera/features/stamp_editor/services/stamp_painter.dart';
import 'package:gps_camera/features/templates/services/default_templates.dart';

const _values = StampValues(values: {
  StampField.city: 'City',
  StampField.state: 'State',
  StampField.country: 'Country',
  StampField.latitude: '12.971599° N',
  StampField.longitude: '77.594566° E',
  StampField.date: '12/11/2026',
  StampField.time: '09:30:15 AM',
});

void main() {
  test('stamp scales with the export resolution (same relative layout)', () {
    final t = DefaultTemplates.byId(DefaultTemplates.classicId);
    final small = StampLayout.compute(imageSize: const Size(1080, 1440), template: t, values: _values).rect;
    final big = StampLayout.compute(imageSize: const Size(3024, 4032), template: t, values: _values).rect;
    const ratio = 3024 / 1080;
    expect(big.width / small.width, closeTo(ratio, ratio * 0.05));
    expect(big.height / small.height, closeTo(ratio, ratio * 0.05));
    expect(big.left / small.left, closeTo(ratio, ratio * 0.05));
  });

  test('stamp always stays inside the image', () {
    for (final t in DefaultTemplates.all) {
      for (final pos in StampPosition.values) {
        const size = Size(1200, 900);
        final r = StampLayout.compute(
          imageSize: size,
          template: t.copyWith(position: pos, customX: 1, customY: 1),
          values: _values,
          showMapPlaceholder: true,
        ).rect;
        if (r.isEmpty) continue;
        expect(r.left, greaterThanOrEqualTo(-0.5), reason: '${t.name} $pos');
        expect(r.top, greaterThanOrEqualTo(-0.5), reason: '${t.name} $pos');
        expect(r.right, lessThanOrEqualTo(size.width + 0.5), reason: '${t.name} $pos');
        expect(r.bottom, lessThanOrEqualTo(size.height + 0.5), reason: '${t.name} $pos');
      }
    }
  });

  test('positions anchor to the expected corners', () {
    final t = DefaultTemplates.byId(DefaultTemplates.classicId);
    const size = Size(2000, 1500);
    Rect at(StampPosition p) =>
        StampLayout.compute(imageSize: size, template: t.copyWith(position: p), values: _values).rect;
    expect(at(StampPosition.topLeft).top, lessThan(size.height / 2));
    expect(at(StampPosition.bottomRight).right, greaterThan(size.width / 2));
    expect(at(StampPosition.bottomLeft).bottom, greaterThan(size.height / 2));
    final c = at(StampPosition.center).center;
    expect(c.dx, closeTo(size.width / 2, 1));
    expect(c.dy, closeTo(size.height / 2, 1));
  });

  test('no enabled data → nothing is drawn', () {
    final t = DefaultTemplates.byId(DefaultTemplates.classicId);
    final r = StampLayout.compute(imageSize: const Size(1000, 1000), template: t, values: const StampValues()).rect;
    expect(r, Rect.zero);
  });

  test('map is omitted from exports when no snapshot is available', () {
    final t = DefaultTemplates.byId('builtin_map');
    final withPlaceholder = StampLayout.compute(
      imageSize: const Size(2000, 1500),
      template: t,
      values: _values,
      showMapPlaceholder: true,
    ).rect;
    final export = StampLayout.compute(imageSize: const Size(2000, 1500), template: t, values: _values).rect;
    expect(export.width, lessThan(withPlaceholder.width));
  });
}
