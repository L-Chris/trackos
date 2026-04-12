import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Manages the local screenshot storage directory.
/// Prefers external app-specific storage (browsable via file manager),
/// falls back to app documents directory.
class ScreenshotService {
  static const _dirName = 'trackos_screenshots';

  /// Returns (creating if necessary) the screenshots directory.
  static Future<Directory> getDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Absolute path of the screenshots directory.
  static Future<String> getDirPath() async => (await getDir()).path;

  /// Number of .jpg screenshots saved locally.
  static Future<int> count() async {
    try {
      final dir = await getDir();
      if (!await dir.exists()) return 0;
      final entities = await dir.list().toList();
      return entities
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.jpg'))
          .length;
    } catch (_) {
      return 0;
    }
  }
}

