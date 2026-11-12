import 'package:flutter/services.dart';

/// Bridge to the native image helpers implemented in
/// android/.../ImageNativePlugin.kt (androidx ExifInterface + Bitmap) and
/// ios/Runner/AppDelegate.swift (ImageIO).
///
/// Methods:
///  * readMetadata {path} -> Map (see PhotoMetadataModel.fromNative)
///  * writeMetadata {path, values} -> null. Only keys present in `values` are
///    changed; a null value removes the tag. Lossless (no recompression).
///  * encodeJpeg {rgba, width, height, quality, outputPath, metadataSourcePath?,
///    resetOrientation} -> {fileSize}. Encodes raw RGBA pixels and copies the
///    metadata of `metadataSourcePath` into the result.
///  * stripGpsCopy {sourcePath, outputPath} -> null. Copy without GPS tags.
class NativeImageChannel {
  static const _channel = MethodChannel('com.gpscamera/image_native');

  Future<Map<dynamic, dynamic>> readMetadata(String path) async {
    final r = await _channel.invokeMethod<Map<dynamic, dynamic>>('readMetadata', {'path': path});
    return r ?? const {};
  }

  Future<void> writeMetadata(String path, Map<String, Object?> values) =>
      _channel.invokeMethod<void>('writeMetadata', {'path': path, 'values': values});

  Future<int> encodeJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    required int quality,
    required String outputPath,
    String? metadataSourcePath,
    bool resetOrientation = true,
  }) async {
    final r = await _channel.invokeMethod<Map<dynamic, dynamic>>('encodeJpeg', {
      'rgba': rgba,
      'width': width,
      'height': height,
      'quality': quality.clamp(1, 100),
      'outputPath': outputPath,
      'metadataSourcePath': metadataSourcePath,
      'resetOrientation': resetOrientation,
    });
    return (r?['fileSize'] as num?)?.toInt() ?? 0;
  }

  Future<void> stripGpsCopy(String sourcePath, String outputPath) =>
      _channel.invokeMethod<void>('stripGpsCopy', {'sourcePath': sourcePath, 'outputPath': outputPath});
}
