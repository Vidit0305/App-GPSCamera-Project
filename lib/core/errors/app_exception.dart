import 'dart:io';

import 'package:flutter/services.dart';

enum AppErrorKind {
  cameraInit,
  cameraPermission,
  locationPermission,
  gpsDisabled,
  gpsTimeout,
  geocoding,
  offline,
  exifRead,
  exifWrite,
  unsupportedFormat,
  storage,
  imageProcessing,
  galleryPermission,
  map,
  noConsent,
  unknown,
}

/// A user-presentable error with a category so screens can offer the right
/// recovery (retry, open settings, enable GPS...).
class AppException implements Exception {
  const AppException(this.kind, this.message, {this.cause});

  final AppErrorKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;

  /// Converts arbitrary exceptions into a meaningful [AppException].
  static AppException from(Object error, {AppErrorKind fallback = AppErrorKind.unknown, String? context}) {
    if (error is AppException) return error;
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      // ENOSPC (28) on Android/iOS, ERROR_DISK_FULL (112) on Windows.
      if (code == 28 || code == 112) {
        return AppException(AppErrorKind.storage,
            'Not enough storage space. Free up space on the device and try again.', cause: error);
      }
      return AppException(AppErrorKind.storage,
          '${context ?? 'File operation failed'}: ${error.message}', cause: error);
    }
    if (error is PlatformException) {
      switch (error.code) {
        case 'UNSUPPORTED_FORMAT':
          return AppException(AppErrorKind.unsupportedFormat, error.message ?? 'Unsupported image format.',
              cause: error);
        case 'NO_SPACE':
          return AppException(AppErrorKind.storage, 'Not enough storage space.', cause: error);
      }
      return AppException(fallback, '${context ?? 'Operation failed'}: ${error.message ?? error.code}',
          cause: error);
    }
    return AppException(fallback, context == null ? '$error' : '$context: $error', cause: error);
  }
}
