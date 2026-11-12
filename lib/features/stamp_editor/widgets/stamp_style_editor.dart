import 'package:flutter/material.dart';

import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../../shared/widgets/color_picker.dart';
import '../../../shared/widgets/common.dart';

/// Full set of visual stamp controls. Every change is reported immediately so
/// previews update live.
class StampStyleEditor extends StatelessWidget {
  const StampStyleEditor({
    super.key,
    required this.template,
    required this.onChanged,
    this.showFieldToggles = false,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
  });

  final StampTemplateModel template;
  final ValueChanged<StampTemplateModel> onChanged;
  final bool showFieldToggles;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showFieldToggles) ...[
            const SectionHeader('Information shown'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in StampField.values)
                  FilterChip(
                    label: Text(f.label),
                    selected: t.shows(f),
                    onSelected: (on) => onChanged(t.toggleField(f, on)),
                  ),
              ],
            ),
          ],
          const SectionHeader('Typography'),
          DropdownButtonFormField<String>(
            initialValue: t.fontFamily,
            decoration: const InputDecoration(labelText: 'Font family'),
            items: [
              for (final e in stampFontFamilies.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value, style: TextStyle(fontFamily: e.key))),
            ],
            onChanged: (v) => v == null ? null : onChanged(t.copyWith(fontFamily: v)),
          ),
          _SliderRow(
            label: 'Font size',
            value: t.fontSize,
            min: 14,
            max: 72,
            display: t.fontSize.toStringAsFixed(0),
            onChanged: (v) => onChanged(t.copyWith(fontSize: v)),
          ),
          Row(
            children: [
              FilterChip(
                avatar: const Icon(Icons.format_bold, size: 18),
                label: const Text('Bold'),
                selected: t.bold,
                onSelected: (v) => onChanged(t.copyWith(bold: v)),
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.format_italic, size: 18),
                label: const Text('Italic'),
                selected: t.italic,
                onSelected: (v) => onChanged(t.copyWith(italic: v)),
              ),
              const Spacer(),
              SegmentedButton<StampAlign>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: StampAlign.left, icon: Icon(Icons.format_align_left, size: 18)),
                  ButtonSegment(value: StampAlign.center, icon: Icon(Icons.format_align_center, size: 18)),
                  ButtonSegment(value: StampAlign.right, icon: Icon(Icons.format_align_right, size: 18)),
                ],
                selected: {t.alignment},
                onSelectionChanged: (s) => onChanged(t.copyWith(alignment: s.first)),
              ),
            ],
          ),
          _SliderRow(
            label: 'Line spacing',
            value: t.lineSpacing,
            min: 1.0,
            max: 2.0,
            display: t.lineSpacing.toStringAsFixed(2),
            onChanged: (v) => onChanged(t.copyWith(lineSpacing: v)),
          ),
          const SectionHeader('Colours'),
          ColorField(label: 'Text colour', color: t.textColor, onChanged: (c) => onChanged(t.copyWith(textColor: c))),
          ColorField(
              label: 'Icon / accent colour', color: t.accentColor, onChanged: (c) => onChanged(t.copyWith(accentColor: c))),
          ColorField(
              label: 'Background colour',
              color: t.backgroundColor,
              onChanged: (c) => onChanged(t.copyWith(backgroundColor: c))),
          _SliderRow(
            label: 'Background opacity',
            value: t.backgroundOpacity,
            min: 0,
            max: 1,
            display: '${(t.backgroundOpacity * 100).round()}%',
            onChanged: (v) => onChanged(t.copyWith(backgroundOpacity: v)),
          ),
          ColorField(
              label: 'Border colour', color: t.borderColor, onChanged: (c) => onChanged(t.copyWith(borderColor: c))),
          _SliderRow(
            label: 'Border width',
            value: t.borderWidth,
            min: 0,
            max: 8,
            display: t.borderWidth.toStringAsFixed(1),
            onChanged: (v) => onChanged(t.copyWith(borderWidth: v)),
          ),
          const SectionHeader('Position'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in StampPosition.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: t.position == p,
                  onSelected: (_) => onChanged(t.copyWith(position: p)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tip: drag the stamp on the preview to place it anywhere.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Full-width banner'),
            value: t.fullWidth,
            onChanged: (v) => onChanged(t.copyWith(fullWidth: v)),
          ),
          if (!t.fullWidth)
            _SliderRow(
              label: 'Maximum width',
              value: t.maxWidthFraction,
              min: 0.3,
              max: 1.0,
              display: '${(t.maxWidthFraction * 100).round()}%',
              onChanged: (v) => onChanged(t.copyWith(maxWidthFraction: v)),
            ),
          _SliderRow(
            label: 'Edge margin',
            value: t.margin,
            min: 0,
            max: 80,
            display: t.margin.toStringAsFixed(0),
            onChanged: (v) => onChanged(t.copyWith(margin: v)),
          ),
          const SectionHeader('Appearance'),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Rounded'), icon: Icon(Icons.rounded_corner, size: 18)),
                    ButtonSegment(value: false, label: Text('Square'), icon: Icon(Icons.crop_square, size: 18)),
                  ],
                  selected: {t.borderRadius > 0},
                  onSelectionChanged: (s) => onChanged(t.copyWith(borderRadius: s.first ? 18 : 0)),
                ),
              ),
            ],
          ),
          if (t.borderRadius > 0)
            _SliderRow(
              label: 'Corner radius',
              value: t.borderRadius,
              min: 2,
              max: 60,
              display: t.borderRadius.toStringAsFixed(0),
              onChanged: (v) => onChanged(t.copyWith(borderRadius: v)),
            ),
          _SliderRow(
            label: 'Padding',
            value: t.padding,
            min: 0,
            max: 60,
            display: t.padding.toStringAsFixed(0),
            onChanged: (v) => onChanged(t.copyWith(padding: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Shadow'),
            subtitle: const Text('Drop shadow behind the card and text'),
            value: t.shadow,
            onChanged: (v) => onChanged(t.copyWith(shadow: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show icons'),
            value: t.showIcons,
            onChanged: (v) => onChanged(t.copyWith(showIcons: v)),
          ),
          const SectionHeader('Map snapshot'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include map snapshot'),
            subtitle: const Text('Small map of the photo location (needs online map tiles or a cached area)'),
            value: t.includesMap,
            onChanged: (v) => onChanged(t.toggleField(StampField.map, v)),
          ),
          if (t.includesMap) ...[
            const SizedBox(height: 4),
            SegmentedButton<MapSnapshotSize>(
              showSelectedIcon: false,
              segments: [for (final s in MapSnapshotSize.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {t.mapSize},
              onSelectionChanged: (s) => onChanged(t.copyWith(mapSize: s.first)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<MapPlacement>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: MapPlacement.left, label: Text('Map left')),
                ButtonSegment(value: MapPlacement.right, label: Text('Map right')),
              ],
              selected: {t.mapPlacement},
              onSelectionChanged: (s) => onChanged(t.copyWith(mapPlacement: s.first)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rounded map corners'),
              value: t.mapRounded,
              onChanged: (v) => onChanged(t.copyWith(mapRounded: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show location marker'),
              value: t.mapShowMarker,
              onChanged: (v) => onChanged(t.copyWith(mapShowMarker: v)),
            ),
            _SliderRow(
              label: 'Map zoom',
              value: t.mapZoom.toDouble(),
              min: 10,
              max: 18,
              divisions: 8,
              display: '${t.mapZoom}',
              onChanged: (v) => onChanged(t.copyWith(mapZoom: v.round())),
            ),
          ],
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: t.bodyMedium)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 44, child: Text(display, textAlign: TextAlign.end, style: t.labelMedium)),
        ],
      ),
    );
  }
}
