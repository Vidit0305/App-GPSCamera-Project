import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/stamp_values.dart';
import '../../../shared/widgets/common.dart';
import '../../batch_editor/services/batch_service.dart';
import '../../photo_editor/services/photo_service.dart';
import '../widgets/import_helper.dart';
import '../widgets/photo_grid_tile.dart';
import '../widgets/share_helper.dart';

enum GalleryCategory {
  all('All photos'),
  originals('Originals'),
  edited('Edited'),
  gps('GPS tagged'),
  noGps('Without GPS'),
  recent('Recently edited');

  const GalleryCategory(this.label);
  final String label;
}

/// Filters, searches and sorts photos for the gallery views.
List<PhotoModel> filterPhotos(List<PhotoModel> all, GalleryCategory cat, String query, GallerySort sort) {
  final q = query.trim().toLowerCase();
  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  var list = all.where((p) {
    final inCategory = switch (cat) {
      GalleryCategory.all => true,
      GalleryCategory.originals => !p.isEdited,
      GalleryCategory.edited => p.isEdited,
      GalleryCategory.gps => p.hasGps,
      GalleryCategory.noGps => !p.hasGps,
      GalleryCategory.recent =>
        p.updatedAt.isAfter(weekAgo) && p.updatedAt.difference(p.createdAt) > const Duration(seconds: 2),
    };
    if (!inCategory) return false;
    if (q.isEmpty) return true;
    final haystack = [
      p.city,
      p.area,
      p.state,
      p.country,
      p.address,
      p.originalFileName,
      p.stampValues?[StampField.note],
      p.stampValues?[StampField.city],
      p.stampValues?[StampField.fullAddress],
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(q);
  }).toList();

  final effectiveSort = cat == GalleryCategory.recent ? GallerySort.recentlyEdited : sort;
  switch (effectiveSort) {
    case GallerySort.newest:
      list.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    case GallerySort.oldest:
      list.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    case GallerySort.recentlyEdited:
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case GallerySort.largest:
      list.sort((a, b) => (b.fileSize ?? 0).compareTo(a.fileSize ?? 0));
  }
  return list;
}

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _large = false;
  GalleryCategory _category = GalleryCategory.all;
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  List<PhotoModel> _selectedPhotos(List<PhotoModel> all) => all.where((p) => _selected.contains(p.id)).toList();

  Future<void> _deleteSelected(List<PhotoModel> all) async {
    final photos = _selectedPhotos(all);
    final ok = await confirm(
      context,
      title: 'Delete ${photos.length} photo${photos.length == 1 ? '' : 's'}?',
      message: 'The photos, their preserved originals and edits will be permanently removed from GPS Camera. '
          'Copies already saved to your device gallery are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final service = ref.read(photoServiceProvider);
    var failed = 0;
    await runWithProgress(context, 'Deleting…', () async {
      for (final p in photos) {
        try {
          await service.delete(p);
        } catch (_) {
          failed++;
        }
      }
    });
    if (!mounted) return;
    setState(_selected.clear);
    showSnack(context, failed == 0 ? 'Deleted ${photos.length} photo(s).' : '$failed photo(s) could not be deleted.',
        error: failed > 0);
  }

  void _batchSelected() {
    ref.read(batchPreselectionProvider.notifier).set(_selected);
    setState(_selected.clear);
    context.push(Routes.batch);
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);
    final settings = ref.watch(settingsProvider);
    final all = photosAsync.value ?? const <PhotoModel>[];

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting ? _selectionBar(all) : _normalBar(settings),
        body: Column(
          children: [
            if (_searching && !_selecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search city, address, file name, note…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_searchCtrl.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: GalleryCategory.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = GalleryCategory.values[i];
                  return Center(
                    child: ChoiceChip(
                      label: Text(c.label),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: photosAsync.when(
                loading: () => const LoadingView(message: 'Loading photos…'),
                error: (e, _) => ErrorView(
                  message: '$e',
                  onRetry: () => ref.invalidate(photosProvider),
                ),
                data: (photos) => _content(photos, settings),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _normalBar(AppSettings settings) {
    return AppBar(
      title: const Text('Gallery'),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: Icon(_searching ? Icons.search_off : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _searchCtrl.clear();
          }),
        ),
        PopupMenuButton<GallerySort>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: settings.gallerySort,
          onSelected: (s) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(gallerySort: s)),
          itemBuilder: (_) => [
            for (final s in GallerySort.values) CheckedPopupMenuItem(value: s, checked: s == settings.gallerySort, child: Text(s.label)),
          ],
        ),
        IconButton(
          tooltip: _large ? 'Smaller previews' : 'Larger previews',
          icon: Icon(_large ? Icons.grid_view : Icons.view_agenda_outlined),
          onPressed: () => setState(() => _large = !_large),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'import') importPhotosFromDevice(context, ref);
            if (v == 'batch') context.push(Routes.batch);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'import',
              child: ListTile(leading: Icon(Icons.add_photo_alternate_outlined), title: Text('Import from device')),
            ),
            PopupMenuItem(
              value: 'batch',
              child: ListTile(leading: Icon(Icons.edit_note), title: Text('Batch edit')),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(List<PhotoModel> all) {
    final visible = filterPhotos(all, _category, _searchCtrl.text, ref.read(settingsProvider).gallerySort);
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
      title: Text('${_selected.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all),
          onPressed: () => setState(() => _selected.addAll(visible.map((p) => p.id))),
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share_outlined),
          onPressed: () => sharePhotosWithPrivacy(context, ref, _selectedPhotos(all)),
        ),
        IconButton(tooltip: 'Batch edit', icon: const Icon(Icons.edit_note), onPressed: _batchSelected),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteSelected(all),
        ),
      ],
    );
  }

  Widget _content(List<PhotoModel> photos, AppSettings settings) {
    if (photos.isEmpty) {
      return EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No photos yet',
        message: 'Photos you take with GPS Camera or import from your device appear here.',
        action: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => context.push(Routes.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Take photo'),
            ),
            OutlinedButton.icon(
              onPressed: () => importPhotosFromDevice(context, ref),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Import'),
            ),
          ],
        ),
      );
    }
    final list = filterPhotos(photos, _category, _searchCtrl.text, settings.gallerySort);
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No matching photos',
        message: 'Try another category or search term.',
        action: TextButton(
          onPressed: () => setState(() {
            _category = GalleryCategory.all;
            _searchCtrl.clear();
          }),
          child: const Text('Show all photos'),
        ),
      );
    }

    final dateGrouped = _category != GalleryCategory.recent &&
        (settings.gallerySort == GallerySort.newest || settings.gallerySort == GallerySort.oldest);
    final groups = <String, List<PhotoModel>>{};
    if (dateGrouped) {
      for (final p in list) {
        groups.putIfAbsent(Fmt.dayHeader(p.capturedAt, settings), () => []).add(p);
      }
    } else {
      groups['${list.length} photo${list.length == 1 ? '' : 's'}'] = list;
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = _large ? (width > 700 ? 3 : 2) : (width > 700 ? 5 : 3);
    return CustomScrollView(
      slivers: [
        for (final e in groups.entries) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(child: Text(e.key, style: Theme.of(context).textTheme.titleSmall)),
                  Text('${e.value.length}', style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final p = e.value[i];
                  return PhotoGridTile(
                    photo: p,
                    size: (width / columns).round(),
                    selected: _selected.contains(p.id),
                    selecting: _selecting,
                    onTap: () => _selecting ? _toggle(p.id) : context.push(Routes.photo(p.id)),
                    onLongPress: () => _toggle(p.id),
                  );
                },
                childCount: e.value.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
