import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../shared/widgets/common.dart';
import '../../stamp_editor/widgets/stamp_preview.dart';
import '../../stamp_editor/widgets/stamp_style_editor.dart';
import 'templates_screen.dart';

/// Creates or edits a user stamp template. Built-in templates are never
/// modified: opening one starts a new copy.
class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({super.key, this.templateId, this.baseTemplateId});

  final String? templateId;
  final String? baseTemplateId;

  @override
  ConsumerState<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  StampTemplateModel? _template;
  bool _isNew = false;
  bool _dirty = false;
  bool _saving = false;
  Object? _error;
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = ref.read(templateRepositoryProvider);
      final id = widget.templateId ?? widget.baseTemplateId;
      StampTemplateModel t;
      if (id == null) {
        t = await repo.getById(ref.read(settingsProvider).defaultTemplateId);
        _isNew = true;
      } else {
        t = await repo.getById(id);
        _isNew = widget.templateId == null || t.isBuiltIn;
      }
      if (_isNew) {
        final now = DateTime.now();
        t = t.copyWith(
          id: const Uuid().v4(),
          name: '${t.name} (custom)',
          isBuiltIn: false,
          createdAt: now,
          updatedAt: now,
        );
      }
      if (!mounted) return;
      _name.text = t.name;
      _description.text = t.description;
      setState(() => _template = t);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _update(StampTemplateModel t) => setState(() {
        _template = t;
        _dirty = true;
      });

  Future<void> _save({bool setDefault = false}) async {
    final t = _template;
    if (t == null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Please give the template a name.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(templateRepositoryProvider)
          .save(t.copyWith(name: name, description: _description.text.trim()));
      if (setDefault) {
        await ref.read(settingsProvider.notifier).update((s) => s.copyWith(defaultTemplateId: saved.id));
      }
      if (!mounted) return;
      _dirty = false;
      showSnack(context, setDefault ? 'Template saved and set as default.' : 'Template saved.');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onPopAttempt() async {
    final discard = await confirm(
      context,
      title: 'Discard changes?',
      message: 'Your changes to this template have not been saved.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (discard && mounted) {
      setState(() => _dirty = false);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _template;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopAttempt();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New template' : 'Edit template'),
          actions: [
            TextButton(
              onPressed: t == null || _saving ? null : () => _save(),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
            PopupMenuButton<String>(
              enabled: t != null && !_saving,
              onSelected: (v) {
                if (v == 'default') _save(setDefault: true);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'default',
                  child: ListTile(leading: Icon(Icons.star_border), title: Text('Save & set as default')),
                ),
              ],
            ),
          ],
        ),
        body: _error != null
            ? ErrorView(message: '$_error', onRetry: _load)
            : t == null
                ? const LoadingView()
                : Column(
                    children: [
                      Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        padding: const EdgeInsets.all(12),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: StampPreview(
                            imagePath: null,
                            imageSize: const Size(1600, 1200),
                            background: const PreviewBackdrop(),
                            template: t,
                            values: ref.watch(templatePreviewValuesProvider),
                            onPositionChanged: (x, y) =>
                                _update(t.copyWith(position: StampPosition.custom, customX: x, customY: y)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _name,
                                    textCapitalization: TextCapitalization.sentences,
                                    decoration: const InputDecoration(labelText: 'Template name'),
                                    onChanged: (_) => setState(() => _dirty = true),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _description,
                                    textCapitalization: TextCapitalization.sentences,
                                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                                    onChanged: (_) => setState(() => _dirty = true),
                                  ),
                                ],
                              ),
                            ),
                            StampStyleEditor(template: t, onChanged: _update, showFieldToggles: true),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
