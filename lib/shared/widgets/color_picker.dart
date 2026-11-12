import 'package:flutter/material.dart';

const _palette = <int>[
  0xFFFFFFFF, 0xFFF2F4F8, 0xFFB0B8C8, 0xFF6B7280, 0xFF1D2330, 0xFF000000,
  0xFF0B1F3A, 0xFF2F5BEA, 0xFF6F8FF5, 0xFF8FB0FF, 0xFF00A3C4, 0xFF1E9E5A,
  0xFF4CE08A, 0xFFFFC94D, 0xFFFF9A2E, 0xFFE8890C, 0xFFE53935, 0xFFD81B60,
  0xFF8E24AA, 0xFF795548,
];

/// Compact colour field: swatch + hex, opens a palette / hex dialog.
class ColorField extends StatelessWidget {
  const ColorField({super.key, required this.label, required this.color, required this.onChanged});

  final String label;
  final int color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showColorPicker(context, color, title: label);
        if (picked != null) onChanged(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            _Swatch(color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: t.textTheme.bodyMedium)),
            Text(_hex(color), style: t.textTheme.labelMedium),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

String _hex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.size = 32, this.selected = false});
  final int color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(color),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.secondary : scheme.outline,
          width: selected ? 3 : 1,
        ),
      ),
    );
  }
}

Future<int?> showColorPicker(BuildContext context, int initial, {String title = 'Colour'}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _ColorDialog(initial: initial, title: title),
  );
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial, required this.title});
  final int initial;
  final String title;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late int _color = widget.initial | 0xFF000000;
  late final _hexCtrl = TextEditingController(text: _hex(widget.initial).substring(1));
  String? _error;

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _setHex(String v) {
    final clean = v.replaceAll('#', '').trim();
    final parsed = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
    setState(() {
      if (parsed == null) {
        _error = 'Enter 6 hex digits';
      } else {
        _error = null;
        _color = 0xFF000000 | parsed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => setState(() {
                      _color = c;
                      _hexCtrl.text = _hex(c).substring(1);
                      _error = null;
                    }),
                    child: _Swatch(color: c, size: 36, selected: (c & 0xFFFFFF) == (_color & 0xFFFFFF)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(children: [
              _Swatch(color: _color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  decoration: InputDecoration(prefixText: '#', labelText: 'Hex', errorText: _error),
                  maxLength: 7,
                  onChanged: _setHex,
                ),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _error == null ? () => Navigator.pop(context, _color) : null,
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}
