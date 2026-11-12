import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite database holding photo records, stamp templates and the
/// reverse-geocoding cache.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 1;

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'gps_camera.db'),
      version: _version,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        final batch = db.batch();
        batch.execute('''
          CREATE TABLE photos (
            id TEXT PRIMARY KEY,
            original_file_path TEXT NOT NULL,
            edited_file_path TEXT,
            thumbnail_path TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            captured_at INTEGER NOT NULL,
            latitude REAL,
            longitude REAL,
            altitude REAL,
            gps_accuracy REAL,
            address TEXT,
            city TEXT,
            area TEXT,
            state TEXT,
            country TEXT,
            stamp_template_id TEXT,
            has_visible_stamp INTEGER NOT NULL DEFAULT 0,
            has_exif_metadata INTEGER NOT NULL DEFAULT 0,
            is_original_preserved INTEGER NOT NULL DEFAULT 1,
            image_width INTEGER,
            image_height INTEGER,
            file_size INTEGER,
            source TEXT NOT NULL,
            detected_location TEXT,
            detected_weather TEXT,
            stamp_values TEXT,
            stamp_style TEXT,
            exif_edits TEXT,
            exif_overrides TEXT,
            original_exif TEXT,
            exif_status TEXT,
            exif_status_message TEXT,
            address_pending INTEGER NOT NULL DEFAULT 0,
            address_resolved_later INTEGER NOT NULL DEFAULT 0,
            original_file_name TEXT,
            search_text TEXT
          )
        ''');
        batch.execute('CREATE INDEX idx_photos_captured ON photos(captured_at DESC)');
        batch.execute('CREATE INDEX idx_photos_updated ON photos(updated_at DESC)');
        batch.execute('CREATE INDEX idx_photos_pending ON photos(address_pending)');
        batch.execute('''
          CREATE TABLE templates (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_builtin INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            data TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE geocode_cache (
            key TEXT PRIMARY KEY,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            data TEXT NOT NULL,
            provider TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE recent_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await batch.commit(noResult: true);
      },
    );
    return AppDatabase._(db);
  }
}
