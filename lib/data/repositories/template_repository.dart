import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/templates/services/default_templates.dart';
import '../local/app_database.dart';
import '../models/stamp_template_model.dart';

/// Built-in templates come from code; user templates are stored in SQLite.
class TemplateRepository {
  TemplateRepository(this._db);

  final AppDatabase _db;
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  Future<List<StampTemplateModel>> getAll() async {
    final rows = await _db.db.query('templates', orderBy: 'sort_order ASC, updated_at DESC');
    final user = rows
        .map((r) {
          try {
            return StampTemplateModel.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<StampTemplateModel>()
        .toList();
    return [...DefaultTemplates.all, ...user];
  }

  Future<StampTemplateModel> getById(String id) async {
    final builtIn = DefaultTemplates.all.where((t) => t.id == id);
    if (builtIn.isNotEmpty) return builtIn.first;
    final rows = await _db.db.query('templates', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return DefaultTemplates.all.first;
    return StampTemplateModel.fromJson(jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
  }

  /// Saves a user template. Built-in templates cannot be overwritten.
  Future<StampTemplateModel> save(StampTemplateModel t) async {
    if (t.isBuiltIn || DefaultTemplates.all.any((b) => b.id == t.id)) {
      throw StateError('Built-in templates are read-only. Duplicate it to make changes.');
    }
    final now = DateTime.now();
    final saved = t.copyWith(updatedAt: now, createdAt: t.createdAt ?? now, isBuiltIn: false);
    await _db.db.insert(
      'templates',
      {
        'id': saved.id,
        'name': saved.name,
        'is_builtin': 0,
        'sort_order': 0,
        'data': jsonEncode(saved.toJson()),
        'updated_at': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(null);
    return saved;
  }

  Future<StampTemplateModel> duplicate(StampTemplateModel t, {String? name}) {
    return save(t.copyWith(
      id: const Uuid().v4(),
      name: name ?? '${t.name} (copy)',
      isBuiltIn: false,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> delete(String id) async {
    if (DefaultTemplates.all.any((b) => b.id == id)) {
      throw StateError('Built-in templates cannot be deleted.');
    }
    await _db.db.delete('templates', where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }
}
