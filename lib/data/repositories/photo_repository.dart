import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../core/services/file_storage_service.dart';
import '../local/app_database.dart';
import '../models/photo_model.dart';

/// Persistence for photo records. File paths are stored relative to the app
/// containers and resolved on load.
class PhotoRepository {
  PhotoRepository(this._db, this._storage);

  final AppDatabase _db;
  final FileStorageService _storage;
  final _changes = StreamController<void>.broadcast();

  /// Emits whenever photo records change.
  Stream<void> get changes => _changes.stream;

  Map<String, Object?> _toRow(PhotoModel m) {
    final row = m.toRow();
    row['original_file_path'] = _storage.toStored(m.originalFilePath);
    row['edited_file_path'] = _storage.toStored(m.editedFilePath);
    row['thumbnail_path'] = _storage.toStored(m.thumbnailPath);
    return row;
  }

  PhotoModel _fromRow(Map<String, Object?> r) {
    final row = Map<String, Object?>.from(r);
    row['original_file_path'] = _storage.resolve(r['original_file_path'] as String?);
    row['edited_file_path'] = _storage.resolve(r['edited_file_path'] as String?);
    row['thumbnail_path'] = _storage.resolve(r['thumbnail_path'] as String?);
    return PhotoModel.fromRow(row);
  }

  Future<List<PhotoModel>> getAll() async {
    final rows = await _db.db.query('photos', orderBy: 'captured_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<List<PhotoModel>> recent({int limit = 12}) async {
    final rows = await _db.db.query('photos', orderBy: 'created_at DESC', limit: limit);
    return rows.map(_fromRow).toList();
  }

  Future<PhotoModel?> getById(String id) async {
    final rows = await _db.db.query('photos', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<PhotoModel>> pendingAddress() async {
    final rows = await _db.db.query('photos', where: 'address_pending = 1 AND latitude IS NOT NULL');
    return rows.map(_fromRow).toList();
  }

  Future<void> upsert(PhotoModel m) async {
    await _db.db.insert('photos', _toRow(m), conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(null);
  }

  /// Deletes the record and every file it owns.
  Future<void> delete(PhotoModel m) async {
    await _db.db.delete('photos', where: 'id = ?', whereArgs: [m.id]);
    await FileStorageService.deleteQuietly(m.originalFilePath);
    await FileStorageService.deleteQuietly(m.editedFilePath);
    await FileStorageService.deleteQuietly(m.thumbnailPath);
    _changes.add(null);
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.db.rawQuery('SELECT COUNT(*) FROM photos')) ?? 0;
}
