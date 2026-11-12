import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';
import '../../photo_editor/services/value_factories.dart';
import '../../stamp_editor/widgets/stamp_preview.dart';
import '../services/default_templates.dart';

/// Values used for template previews: the real current location when one has
/// been resolved, otherwise descriptive placeholders (never a fake location).
final templatePreviewValuesProvider = Provider<StampValues>((ref) {
  final loc = ref.watch(locationControllerProvider);
  final settings = ref.watch(settingsProvider);
  final display = loc.display;
  if (display == null || !display.hasCoordinates) return placeholderStampValues();
  final built = StampValueFactory.build(
    location: display,
    weather: loc.weather,
    time: DateTime.now(),
    settings: settings,
  );
  // Fill gaps (e.g. unresolved address) with placeholders so every enabled
  // field remains visible in the preview.
  final placeholders = placeholderStampValues();
  return StampValues(
    values: {
      for (final f in StampField.values)
        if (f.isText) f: built[f].isNotEmpty ? built[f] : placeholders[f],
    },
    mapLatitude: built.mapLatitude,
    mapLongitude: built.mapLongitude,
  );
});

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    final defaultId = ref.watch(settingsProvider.select((s) => s.defaultTemplateId));
    return Scaffold(
      appBar: AppBar(title: const Text('Stamp Templates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.editTemplate(base: defaultId)),
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
      body: templates.when(
        loading: () => const LoadingView(message: 'Loading templates…'),
        error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(templatesProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(icon: Icons.dashboard_customize_outlined, title: 'No templates');
          }
          final builtIn = list.where((t) => t.isBuiltIn).toList();
          final user = list.where((t) => !t.isBuiltIn).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              SectionHeader('My templates (${user.length})', padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
              if (user.isEmpty)
                const InfoBanner(
                  tone: ChipTone.info,
                  icon: Icons.lightbulb_outline,
                  message: 'Create your own design with “New template”, or customise a copy of a built-in template.',
                )
              else
                for (final t in user) _TemplateCard(template: t, isDefault: t.id == defaultId),
              const SectionHeader('Built-in templates'),
              for (final t in builtIn) _TemplateCard(template: t, isDefault: t.id == defaultId),
            ],
          );
        },
      ),
    );
  }
}

enum _Action { setDefault, edit, customise, duplicate, delete }

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({required this.template, required this.isDefault});

  final StampTemplateModel template;
  final bool isDefault;

  Future<void> _onAction(BuildContext context, WidgetRef ref, _Action a) async {
    final repo = ref.read(templateRepositoryProvider);
    final t = template;
    try {
      switch (a) {
        case _Action.setDefault:
          await ref.read(settingsProvider.notifier).update((s) => s.copyWith(defaultTemplateId: t.id));
          if (context.mounted) showSnack(context, '“${t.name}” is now the default stamp.');
        case _Action.edit:
          await context.push(Routes.editTemplate(id: t.id));
        case _Action.customise:
          await context.push(Routes.editTemplate(base: t.id));
        case _Action.duplicate:
          final copy = await repo.duplicate(t);
          if (context.mounted) showSnack(context, 'Created “${copy.name}”.');
        case _Action.delete:
          final ok = await confirm(
            context,
            title: 'Delete template?',
            message: '“${t.name}” will be removed. Photos already stamped with it are not affected.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (!ok) return;
          await repo.delete(t.id);
          if (isDefault) {
            await ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(defaultTemplateId: DefaultTemplates.classicId));
          }
          if (context.mounted) showSnack(context, 'Template deleted.');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final values = ref.watch(templatePreviewValuesProvider);
    final t = template;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () => _onAction(context, ref, t.isBuiltIn ? _Action.customise : _Action.edit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: IgnorePointer(
                child: StampPreview(
                  imagePath: null,
                  imageSize: const Size(1600, 1200),
                  background: const PreviewBackdrop(),
                  template: t,
                  values: values,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, style: theme.textTheme.titleMedium),
                        if (t.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(t.description, style: theme.textTheme.bodySmall),
                        ],
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          if (isDefault)
                            const StatusChip(label: 'Default', icon: Icons.star, tone: ChipTone.success, dense: true),
                          if (t.isBuiltIn)
                            const StatusChip(label: 'Built-in', icon: Icons.lock_outline, dense: true)
                          else
                            const StatusChip(label: 'Custom', icon: Icons.edit_outlined, tone: ChipTone.info, dense: true),
                          if (t.includesMap) const StatusChip(label: 'Map', icon: Icons.map_outlined, dense: true),
                        ]),
                      ],
                    ),
                  ),
                  if (!isDefault)
                    IconButton(
                      tooltip: 'Set as default',
                      icon: const Icon(Icons.star_border),
                      onPressed: () => _onAction(context, ref, _Action.setDefault),
                    ),
                  PopupMenuButton<_Action>(
                    onSelected: (a) => _onAction(context, ref, a),
                    itemBuilder: (_) => [
                      if (!isDefault)
                        const PopupMenuItem(
                            value: _Action.setDefault,
                            child: ListTile(leading: Icon(Icons.star_border), title: Text('Set as default'))),
                      if (t.isBuiltIn)
                        const PopupMenuItem(
                            value: _Action.customise,
                            child: ListTile(leading: Icon(Icons.tune), title: Text('Customise a copy')))
                      else
                        const PopupMenuItem(
                            value: _Action.edit, child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                      const PopupMenuItem(
                          value: _Action.duplicate,
                          child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Duplicate'))),
                      if (!t.isBuiltIn)
                        const PopupMenuItem(
                            value: _Action.delete,
                            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
