import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../widgets/import_helper.dart';
import '../widgets/photo_grid_tile.dart';

/// Picks a photo (from the app or by importing one) and opens it in the editor.
class PhotoPickerScreen extends ConsumerWidget {
  const PhotoPickerScreen({super.key, required this.purpose});

  /// 'exif' opens the EXIF tab; anything else opens the stamp editor.
  final String purpose;

  void _open(BuildContext context, PhotoModel p) =>
      context.pushReplacement(Routes.editor(p.id, tab: purpose == 'exif' ? 'exif' : null));

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final imported = await importPhotosFromDevice(context, ref);
    if (imported.length == 1 && context.mounted) _open(context, imported.first);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(photosProvider);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 700 ? 5 : 3;
    return Scaffold(
      appBar: AppBar(
        title: Text(purpose == 'exif' ? 'Choose a photo to edit metadata' : 'Choose a photo'),
        actions: [
          IconButton(
            tooltip: 'Import from device',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: () => _import(context, ref),
          ),
        ],
      ),
      body: photos.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(photosProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'No photos in GPS Camera yet',
              message: 'Import a photo from your device to view and edit its metadata.',
              action: FilledButton.icon(
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Import from device'),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: InfoBanner(
                  tone: ChipTone.info,
                  message: 'Pick a photo below, or import one from your device. Imported photos are copied; '
                      'the file on your device is never modified.',
                  action: TextButton(onPressed: () => _import(context, ref), child: const Text('Import')),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => PhotoGridTile(
                    photo: list[i],
                    size: (width / columns).round(),
                    onTap: () => _open(context, list[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
