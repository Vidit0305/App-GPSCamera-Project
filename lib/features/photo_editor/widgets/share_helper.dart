import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../../photo_editor/services/photo_service.dart';

/// Shares photos honouring the privacy settings:
///  * "Remove location metadata when sharing" strips GPS EXIF from the copies;
///  * "Ask before sharing location" asks when any photo carries GPS metadata.
Future<void> sharePhotosWithPrivacy(BuildContext context, WidgetRef ref, List<PhotoModel> photos) async {
  if (photos.isEmpty) return;
  final s = ref.read(settingsProvider);
  var strip = s.removeLocationOnShare;
  final anyGps = photos.any((p) => p.hasGps);
  if (!strip && s.askBeforeShareLocation && anyGps) {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.share_location_outlined, size: 32),
        title: const Text('Share location metadata?'),
        content: Text(
          '${photos.length == 1 ? 'This photo contains' : 'Some of these photos contain'} GPS coordinates in '
          'their EXIF metadata. You can share copies with the location metadata removed.\n\n'
          'Note: a visible stamp drawn on the photo is part of the image and is not removed.',
        ),
        actions: [
          TextButton(onPressed: hx(() => Navigator.pop(ctx)), child: const Text('Cancel')),
          OutlinedButton(onPressed: hx(() => Navigator.pop(ctx, false)), child: const Text('Include location')),
          FilledButton(onPressed: hx(() => Navigator.pop(ctx, true)), child: const Text('Remove location')),
        ],
      ),
    );
    if (choice == null) return;
    strip = choice;
  }
  try {
    await ref.read(photoServiceProvider).share(photos, stripLocation: strip);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
