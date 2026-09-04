import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local DuitNow QR image storage.
/// Production: sync from Admin desktop later (TBD).
class QrStorage {
  static const _keyPath = 'duitnow_qr_local_path';

  Future<String?> getLocalPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyPath);
    if (path == null || path.isEmpty) return null;
    if (!File(path).existsSync()) return null;
    return path;
  }

  Future<String> saveFromPicker(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'duitnow'));
    if (!destDir.existsSync()) {
      destDir.createSync(recursive: true);
    }
    final ext = p.extension(sourcePath).toLowerCase();
    final safeExt = (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp')
        ? ext
        : '.png';
    // Remove prior copies with other extensions to avoid stale files.
    for (final staleExt in ['.png', '.jpg', '.jpeg', '.webp']) {
      final stale = File(p.join(destDir.path, 'payment_qr$staleExt'));
      if (stale.existsSync() && staleExt != safeExt) {
        await stale.delete();
      }
    }
    final dest = File(p.join(destDir.path, 'payment_qr$safeExt'));
    await File(sourcePath).copy(dest.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPath, dest.path);
    return dest.path;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyPath);
    if (path != null) {
      final f = File(path);
      if (f.existsSync()) {
        await f.delete();
      }
    }
    await prefs.remove(_keyPath);
  }
}
