import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns the app's private photo directories.
///
/// documents/photos/originals  – preserved originals (never modified after capture/import)
/// documents/photos/edited     – stamped / metadata-edited exports
/// support/thumbnails          – generated thumbnails (re-creatable)
/// support/tiles               – cached map tiles for offline snapshots
/// temp/share                  – temporary copies for sharing
class FileStorageService {
  FileStorageService._(this.documents, this.support, this.temp);

  final Directory documents;
  final Directory support;
  final Directory temp;

  static Future<FileStorageService> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final temp = await getTemporaryDirectory();
    final s = FileStorageService._(docs, support, temp);
    for (final d in [s.originalsDir, s.editedDir, s.thumbnailsDir, s.tilesDir, s.shareDir, s.workDir]) {
      await d.create(recursive: true);
    }
    return s;
  }

  Directory get originalsDir => Directory(p.join(documents.path, 'photos', 'originals'));
  Directory get editedDir => Directory(p.join(documents.path, 'photos', 'edited'));
  Directory get thumbnailsDir => Directory(p.join(support.path, 'thumbnails'));
  Directory get tilesDir => Directory(p.join(support.path, 'tiles'));
  Directory get shareDir => Directory(p.join(temp.path, 'share'));
  Directory get workDir => Directory(p.join(temp.path, 'work'));

  String originalPath(String id, String ext) => p.join(originalsDir.path, '$id$ext');

  /// Edited exports get a version suffix so image caches never show stale pixels.
  String editedPath(String id) =>
      p.join(editedDir.path, '${id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
  String thumbnailPath(String id) =>
      p.join(thumbnailsDir.path, '${id}_${DateTime.now().millisecondsSinceEpoch}.png');
  String workPath(String name) => p.join(workDir.path, name);
  String sharePath(String name) => p.join(shareDir.path, name);

  /// Converts an absolute path into a container-independent stored form.
  /// (iOS changes the app container path across updates, so absolute paths
  /// must never be persisted.)
  String? toStored(String? absolute) {
    if (absolute == null) return null;
    if (p.isWithin(documents.path, absolute)) return 'docs:${p.relative(absolute, from: documents.path)}';
    if (p.isWithin(support.path, absolute)) return 'support:${p.relative(absolute, from: support.path)}';
    return absolute;
  }

  String? resolve(String? stored) {
    if (stored == null) return null;
    if (stored.startsWith('docs:')) return p.join(documents.path, stored.substring(5));
    if (stored.startsWith('support:')) return p.join(support.path, stored.substring(8));
    return stored;
  }

  /// Deletes a file if present; never throws.
  static Future<void> deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Atomically replaces [target] with [source] (rename within the same volume).
  static Future<void> replace(String source, String target) async {
    final t = File(target);
    if (await t.exists()) await t.delete();
    try {
      await File(source).rename(target);
    } on FileSystemException {
      await File(source).copy(target);
      await File(source).delete();
    }
  }

  Future<void> clearShareCache() async {
    try {
      if (await shareDir.exists()) {
        await shareDir.delete(recursive: true);
      }
      await shareDir.create(recursive: true);
    } catch (_) {}
  }

  Future<void> clearTileCache() async {
    try {
      if (await tilesDir.exists()) await tilesDir.delete(recursive: true);
      await tilesDir.create(recursive: true);
    } catch (_) {}
  }
}
