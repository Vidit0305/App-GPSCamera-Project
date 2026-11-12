import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/common.dart';

/// Renders a bundled legal document (simple Markdown subset: headings,
/// bullets and paragraphs).
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.doc});

  /// `privacy` or `terms`.
  final String doc;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late Future<String> _text = _load();

  String get _asset => widget.doc == 'terms' ? 'assets/legal/terms.md' : 'assets/legal/privacy_policy.md';
  String get _title => widget.doc == 'terms' ? 'Terms and Conditions' : 'Privacy Policy';

  Future<String> _load() => rootBundle.loadString(_asset);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: FutureBuilder<String>(
        future: _text,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            return ErrorView(
              message: 'The document could not be loaded.',
              onRetry: () => setState(() => _text = _load()),
            );
          }
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: _render(context, snap.data!),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _render(BuildContext context, String text) {
    final t = Theme.of(context).textTheme;
    final out = <Widget>[];
    final paragraph = StringBuffer();

    void flush() {
      if (paragraph.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(paragraph.toString().trim(), style: t.bodyMedium),
      ));
      paragraph.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
      } else if (line.startsWith('## ')) {
        flush();
        out.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(line.substring(3), style: t.titleMedium),
        ));
      } else if (line.startsWith('# ')) {
        flush();
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(line.substring(2), style: t.headlineSmall),
        ));
      } else if (line.trimLeft().startsWith('- ')) {
        flush();
        out.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: t.bodyMedium),
              Expanded(child: Text(line.trimLeft().substring(2), style: t.bodyMedium)),
            ],
          ),
        ));
      } else {
        paragraph.write('${line.trim()} ');
      }
    }
    flush();
    return out;
  }
}
