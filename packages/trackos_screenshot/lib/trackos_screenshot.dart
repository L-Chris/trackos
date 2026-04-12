import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Provides full-screen screenshot capture via Android MediaProjection API.
class MediaProjectionScreenshot {
  static const MethodChannel _channel =
      MethodChannel('com.rethinkos.trackos/screenshot');

  /// Requests the MediaProjection permission from the user.
  /// Returns [true] if the user granted permission, [false] otherwise.
  /// Once granted, the permission token is retained until the app process ends.
  static Future<bool> requestPermission() async {
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  /// Captures the current screen content and returns raw PNG bytes.
  /// Returns [null] if capture fails.
  /// You must call [requestPermission] at least once before calling this.
  static Future<Uint8List?> takeScreenshot() async {
    return await _channel.invokeMethod<Uint8List>('takeScreenshot');
  }

  /// Opens the given [path] in the system file manager.
  /// On Android, tries the Documents UI tree picker (API 26+) then falls back
  /// to a generic ACTION_VIEW chooser.
  static Future<void> openDirectory(String path) async {
    try {
      await _channel.invokeMethod<void>('openDirectory', {'path': path});
    } catch (_) {}
  }
}

