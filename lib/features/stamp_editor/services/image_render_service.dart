import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/native_image_channel.dart';
import '../../../data/models/stamp_template_model.dart';
import '../../../data/models/stamp_values.dart';
import 'stamp_painter.dart';

class RenderOutput {
  const RenderOutput({required this.width, required this.height, required this.fileSize, this.downscaled = false});
  final int width;
  final int height;
  final int fileSize;
  final bool downscaled;
}

/// Renders stamps at the photo's real resolution and creates thumbnails.
class ImageRenderService {
  ImageRenderService(this._native);

  final NativeImageChannel _native;

  /// Largest dimension the GPU path can rasterise reliably.
  static const maxDimension = 8192;

  /// Decodes [path] honouring EXIF orientation (Flutter's decoder applies it).
  static Future<ui.Image> decode(String path, {int? maxDimension}) async {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
      if (maxDimension == null || math.max(w, h) <= maxDimension) return ui.TargetImageSize(width: w, height: h);
      final f = maxDimension / math.max(w, h);
      return ui.TargetImageSize(width: (w * f).round(), height: (h * f).round());
    });
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Reads the displayed (orientation-corrected) size of an image.
  ///
  /// The full dimensions come from the encoded header; whether they need to be
  /// swapped is decided by decoding a small preview, which is exactly what the
  /// UI and the renderer will see.
  static Future<Size> imageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    descriptor.dispose();
    buffer.dispose();
    final preview = await decode(path, maxDimension: 256);
    final portraitPreview = preview.height > preview.width;
    preview.dispose();
    final portraitRaw = h > w;
    if (w != h && portraitPreview != portraitRaw) return Size(h.toDouble(), w.toDouble());
    return Size(w.toDouble(), h.toDouble());
  }

  /// Draws [template]/[values] onto the image at [sourcePath] and writes a JPEG
  /// to [outputPath], copying the source's metadata (orientation reset since
  /// the pixels are now upright).
  Future<RenderOutput> renderStamped({
    required String sourcePath,
    required String outputPath,
    required StampTemplateModel template,
    required StampValues values,
    ui.Image? map,
    required int quality,
    required int? sourceOrientation,
    required int? rawWidth,
    required int? rawHeight,
  }) async {
    ui.Image? src;
    ui.Image? out;
    try {
      src = await decode(sourcePath, maxDimension: maxDimension);
      final w = src.width;
      final h = src.height;
      final downscaled = rawWidth != null && rawHeight != null && math.max(rawWidth, rawHeight) > maxDimension;

      // Safety net: if the decoder did NOT apply a 90° EXIF rotation the pixel
      // dimensions are unswapped; keep the orientation tag in that case.
      var resetOrientation = true;
      final rotated = sourceOrientation != null && sourceOrientation >= 5 && sourceOrientation <= 8;
      if (rotated && rawWidth != null && rawHeight != null && rawWidth != rawHeight && !downscaled) {
        if (w == rawWidth && h == rawHeight) resetOrientation = false;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(src, Offset.zero, Paint()..filterQuality = FilterQuality.none);
      StampLayout.compute(
        imageSize: Size(w.toDouble(), h.toDouble()),
        template: template,
        values: values,
        map: map,
      ).paint(canvas);
      final picture = recorder.endRecording();
      out = await picture.toImage(w, h);
      picture.dispose();
      src.dispose();
      src = null;

      final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const AppException(AppErrorKind.imageProcessing, 'Could not read rendered pixels.');
      out.dispose();
      out = null;

      final size = await _native.encodeJpeg(
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: w,
        height: h,
        quality: quality,
        outputPath: outputPath,
        metadataSourcePath: sourcePath,
        resetOrientation: resetOrientation,
      );
      return RenderOutput(width: w, height: h, fileSize: size, downscaled: downscaled);
    } catch (e) {
      throw AppException.from(e, fallback: AppErrorKind.imageProcessing, context: 'Could not render the stamp');
    } finally {
      src?.dispose();
      out?.dispose();
    }
  }

  /// Writes a ~480 px PNG thumbnail of [sourcePath] to [outputPath].
  Future<void> thumbnail(String sourcePath, String outputPath, {int maxSide = 480}) async {
    final img = await decode(sourcePath, maxDimension: maxSide);
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const AppException(AppErrorKind.imageProcessing, 'Thumbnail encoding failed.');
      await File(outputPath).writeAsBytes(data.buffer.asUint8List(), flush: true);
    } finally {
      img.dispose();
    }
  }
}
