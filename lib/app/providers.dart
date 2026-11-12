import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../core/services/file_storage_service.dart';
import '../core/services/native_image_channel.dart';
import '../data/local/app_database.dart';
import '../data/models/app_settings.dart';
import '../data/models/photo_model.dart';
import '../data/models/stamp_template_model.dart';
import '../data/remote/nominatim_geocoding_provider.dart';
import '../data/remote/platform_geocoding_provider.dart';
import '../data/remote/weather_service.dart';
import '../data/repositories/geocoding_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/template_repository.dart';
import '../features/exif_editor/services/exif_service.dart';
import '../features/location/services/location_service.dart';
import '../features/stamp_editor/services/image_render_service.dart';
import '../features/stamp_editor/services/map_snapshot_service.dart';

// ----------------------------------------------------------- core singletons
// These are created in main() and injected with overrides.

final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('overridden in main'));
final storageProvider = Provider<FileStorageService>((ref) => throw UnimplementedError('overridden in main'));
final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => throw UnimplementedError('overridden in main'));

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': Env.userAgent},
  ));
  ref.onDispose(dio.close);
  return dio;
});

final nativeImageProvider = Provider((ref) => NativeImageChannel());
final exifServiceProvider = Provider((ref) => ExifService(ref.watch(nativeImageProvider)));
final renderServiceProvider = Provider((ref) => ImageRenderService(ref.watch(nativeImageProvider)));
final locationServiceProvider = Provider((ref) => LocationService());
final weatherServiceProvider = Provider((ref) => WeatherService(ref.watch(dioProvider)));
final mapSnapshotServiceProvider =
    Provider((ref) => MapSnapshotService(ref.watch(dioProvider), ref.watch(storageProvider)));

final photoRepositoryProvider =
    Provider((ref) => PhotoRepository(ref.watch(databaseProvider), ref.watch(storageProvider)));
final templateRepositoryProvider = Provider((ref) => TemplateRepository(ref.watch(databaseProvider)));
final geocodingRepositoryProvider = Provider((ref) => GeocodingRepository(
      ref.watch(databaseProvider),
      PlatformGeocodingProvider(),
      NominatimGeocodingProvider(ref.watch(dioProvider)),
    ));

// ----------------------------------------------------------- settings

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(settingsProvider.select((s) => s.themeMode)));

// ----------------------------------------------------------- connectivity

/// True when the device reports any network connection. (A connection does
/// not guarantee internet reachability; network calls still handle failures.)
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);
  yield online(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(online);
});

final isOnlineProvider = Provider<bool>((ref) => ref.watch(connectivityProvider).value ?? true);

// ----------------------------------------------------------- data streams

final photosProvider = StreamProvider<List<PhotoModel>>((ref) async* {
  final repo = ref.watch(photoRepositoryProvider);
  yield await repo.getAll();
  await for (final _ in repo.changes) {
    yield await repo.getAll();
  }
});

final photoByIdProvider = Provider.family<PhotoModel?, String>((ref, id) {
  final list = ref.watch(photosProvider).value;
  if (list == null) return null;
  for (final p in list) {
    if (p.id == id) return p;
  }
  return null;
});

final templatesProvider = StreamProvider<List<StampTemplateModel>>((ref) async* {
  final repo = ref.watch(templateRepositoryProvider);
  yield await repo.getAll();
  await for (final _ in repo.changes) {
    yield await repo.getAll();
  }
});

/// The default template (falls back to the first built-in).
final defaultTemplateProvider = Provider<StampTemplateModel?>((ref) {
  final id = ref.watch(settingsProvider.select((s) => s.defaultTemplateId));
  final list = ref.watch(templatesProvider).value;
  if (list == null || list.isEmpty) return null;
  return list.firstWhere((t) => t.id == id, orElse: () => list.first);
});
