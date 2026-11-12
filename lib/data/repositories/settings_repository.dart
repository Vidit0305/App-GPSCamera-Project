import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/location_model.dart';

/// Preferences plus small cached values (last location, manual override).
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kSettings = 'settings_v1';
  static const _kLastLocation = 'last_location_v1';
  static const _kManualLocation = 'manual_location_v1';

  AppSettings load() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) => _prefs.setString(_kSettings, jsonEncode(s.toJson()));

  LocationModel? _loc(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return LocationModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Last GPS fix with its address, used to show something useful offline
  /// (always labelled with its age; never presented as a live fix).
  LocationModel? get lastLocation => _loc(_kLastLocation);
  Future<void> setLastLocation(LocationModel l) => _prefs.setString(_kLastLocation, jsonEncode(l.toJson()));

  LocationModel? get manualLocation => _loc(_kManualLocation);
  Future<void> setManualLocation(LocationModel? l) => l == null
      ? _prefs.remove(_kManualLocation)
      : _prefs.setString(_kManualLocation, jsonEncode(l.toJson()));

  Future<void> clearCachedLocations() async {
    await _prefs.remove(_kLastLocation);
  }
}
