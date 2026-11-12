import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/file_storage_service.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../../photo_editor/services/photo_service.dart';

/// Lets the user pick images from the device and imports copies of them into
/// the app (the device originals are never modified). Returns the imported
/// records; reports per-file failures.
Future<List<PhotoModel>> importPhotosFromDevice(BuildContext context, WidgetRef ref) async {
  List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(
      type: FileType.image,
      darwinOptions: const DarwinOptions(assetRepresentationMode: DarwinAssetRepresentationMode.current),
    );
  } catch (e) {
    if (context.mounted) {
      showError(context, AppException.from(e, fallback: AppErrorKind.galleryPermission, context: 'Could not open the photo picker'));
    }
    return const [];
  }
  if (files.isEmpty || !context.mounted) return const [];

  final storage = ref.read(storageProvider);
  final service = ref.read(photoServiceProvider);
  final imported = <PhotoModel>[];
  final errors = <String>[];

  await runWithProgress(context, 'Importing ${files.length} photo${files.length == 1 ? '' : 's'}…', () async {
    for (final f in files) {
      String? temp;
      try {
        var path = f.path;
        if (path == null) {
          temp = storage.workPath('import_${DateTime.now().microsecondsSinceEpoch}_${f.name}');
          await f.xFile.saveTo(temp);
          path = temp;
        }
        imported.add(await service.importFile(path, originalName: f.name));
      } catch (e) {
        errors.add('${f.name}: ${AppException.from(e, context: 'Import failed').message}');
      } finally {
        await FileStorageService.deleteQuietly(temp);
      }
    }
  });

  if (!context.mounted) return imported;
  if (errors.isEmpty) {
    showSnack(context, 'Imported ${imported.length} photo${imported.length == 1 ? '' : 's'}.');
  } else {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Imported ${imported.length} of ${files.length}'),
        content: SingleChildScrollView(child: Text(errors.join('\n\n'))),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
  return imported;
}
