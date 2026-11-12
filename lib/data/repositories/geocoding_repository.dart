import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../local/app_database.dart';
import '../models/app_settings.dart';
import '../models/location_model.dart';
import '../remote/geocoding_provider.dart';
import '../remote/nominatim_geocoding_provider.dart';
import '../remote/platform_geocoding_provider.dart';

/// Reverse geocoding with a local cache (~11 m grid) so previously visited
/// places resolve offline. Respects the user's online-services consent.
class GeocodingRepository {
  GeocodingRepository(this._db, this._platform, this._nominatim);

  final AppDatabase _db;
  final PlatformGeocodingProvider _platform;
  final NominatimGeocodingProvider _nominatim;

  GeocodingProvider providerFor(AppSettings s) =>
      s.geocoderProvider == GeocoderProvider.nominatim ? _nominatim : _platform;

  static String _key(double lat, double lon) => '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

  Future<AddressModel?> cached(double lat, double lon) async {
    final rows = await _db.db.query('geocode_cache', where: 'key = ?', whereArgs: [_key(lat, lon)], limit: 1);
    if (rows.isEmpty) return null;
    try {
      return AddressModel.fromJson(jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Returns a cached address or queries the configured provider.
  /// Throws [AppException] (noConsent / offline / geocoding) on failure.
  Future<AddressModel?> reverse(double lat, double lon, AppSettings settings, {bool online = true}) async {
    final hit = await cached(lat, lon);
    if (hit != null) return hit;
    if (!settings.onlineAllowed) {
      throw const AppException(AppErrorKind.noConsent,
          'Address lookup needs online services. Enable them in Settings › Privacy.');
    }
    if (!online) {
      throw const AppException(AppErrorKind.offline, 'Offline – the address will be looked up later.');
    }
    final provider = providerFor(settings);
    AddressModel? result;
    try {
      result = await provider.reverse(lat, lon, languageCode: settings.locale?.languageCode);
    } on AppException catch (e) {
      // Fall back to Nominatim if the device geocoder is missing/failing.
      if (provider == _platform && e.kind == AppErrorKind.geocoding) {
        result = await _nominatim.reverse(lat, lon, languageCode: settings.locale?.languageCode);
      } else {
        rethrow;
      }
    }
    if (result != null && !result.isEmpty) {
      await _db.db.insert(
        'geocode_cache',
        {
          'key': _key(lat, lon),
          'latitude': lat,
          'longitude': lon,
          'data': jsonEncode(result.toJson()),
          'provider': result.provider,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return result;
  }

  Future<List<PlaceResult>> search(String query, AppSettings settings) async {
    if (!settings.onlineAllowed) {
      throw const AppException(AppErrorKind.noConsent, 'Search needs online services. Enable them in Settings › Privacy.');
    }
    final provider = providerFor(settings);
    try {
      return await provider.search(query, languageCode: settings.locale?.languageCode);
    } on AppException catch (e) {
      if (provider == _platform && e.kind == AppErrorKind.geocoding) {
        return _nominatim.search(query, languageCode: settings.locale?.languageCode);
      }
      rethrow;
    }
  }

  Future<int> clearCache() => _db.db.delete('geocode_cache');

  // ------------------------------------------------------- recent locations

  Future<void> addRecent(LocationModel l) async {
    if (!l.hasCoordinates) return;
    await _db.db.insert('recent_locations', {
      'data': jsonEncode(l.toJson()),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    // keep the 20 most recent
    await _db.db.execute(
        'DELETE FROM recent_locations WHERE id NOT IN (SELECT id FROM recent_locations ORDER BY created_at DESC LIMIT 20)');
  }

  Future<List<LocationModel>> recents() async {
    final rows = await _db.db.query('recent_locations', orderBy: 'created_at DESC', limit: 20);
    return rows
        .map((r) => LocationModel.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearRecents() => _db.db.delete('recent_locations');
}
