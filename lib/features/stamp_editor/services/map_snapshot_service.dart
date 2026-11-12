import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/env.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/file_storage_service.dart';

/// Renders a small map image around a coordinate by compositing raster tiles.
/// Tiles are cached on disk so snapshots of previously visited areas work offline.
class MapSnapshotService {
  MapSnapshotService(this._dio, this._storage);

  final Dio _dio;
  final FileStorageService _storage;
  final _memory = <String, ui.Image>{};

  static const _tile = 256;

  String _key(double lat, double lon, int z, int size) =>
      '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)},$z,$size';

  /// Returns a [size]x[size] map image centred on [lat],[lon].
  ///
  /// Throws [AppException] with kind `noConsent`, `offline` or `map` when the
  /// snapshot cannot be produced.
  Future<ui.Image> snapshot(
    double lat,
    double lon, {
    int zoom = 16,
    int size = 640,
    required bool onlineAllowed,
    required bool online,
  }) async {
    final key = _key(lat, lon, zoom, size);
    final cached = _memory[key];
    if (cached != null) return cached.clone();

    final n = 1 << zoom;
    final latRad = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
    final px = (lon + 180) / 360 * n * _tile;
    final py = (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n * _tile;
    final left = px - size / 2;
    final top = py - size / 2;
    final tx0 = (left / _tile).floor();
    final ty0 = (top / _tile).floor();
    final tx1 = ((left + size) / _tile).floor();
    final ty1 = ((top + size) / _tile).floor();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), Paint()..color = const Color(0xFFE8E4DC));

    for (var ty = ty0; ty <= ty1; ty++) {
      if (ty < 0 || ty >= n) continue;
      for (var tx = tx0; tx <= tx1; tx++) {
        final wrappedX = ((tx % n) + n) % n;
        final img = await _tileImage(zoom, wrappedX, ty, onlineAllowed: onlineAllowed, online: online);
        canvas.drawImage(img, Offset(tx * _tile - left, ty * _tile - top), Paint()..filterQuality = FilterQuality.medium);
        img.dispose();
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    _memory[key] = image;
    if (_memory.length > 12) {
      final first = _memory.keys.first;
      _memory.remove(first)?.dispose();
    }
    return image.clone();
  }

  Future<ui.Image> _tileImage(int z, int x, int y, {required bool onlineAllowed, required bool online}) async {
    final file = File(p.join(_storage.tilesDir.path, '$z', '$x', '$y.png'));
    List<int>? bytes;
    if (await file.exists()) {
      bytes = await file.readAsBytes();
    } else {
      if (!onlineAllowed) {
        throw const AppException(AppErrorKind.noConsent,
            'Map snapshots need online map tiles. Enable online services in Settings › Privacy.');
      }
      if (!online) {
        throw const AppException(AppErrorKind.offline,
            'Offline: this area\'s map is not cached, so the map snapshot is unavailable.');
      }
      final url = Env.tileUrlTemplate
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y')
          .replaceAll('{s}', 'a');
      try {
        final res = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes, headers: {'User-Agent': Env.userAgent}),
        );
        bytes = res.data;
        if (bytes == null || bytes.isEmpty) throw const AppException(AppErrorKind.map, 'Empty map tile.');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: false);
      } on DioException catch (e) {
        throw AppException(AppErrorKind.map, 'Map tiles could not be downloaded (${e.response?.statusCode ?? e.type.name}).',
            cause: e);
      }
    }
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
