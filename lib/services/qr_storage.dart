import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
    final prefs = await SharedPreferences.getInstance();
    final previousPath = prefs.getString(_keyPath);
    // Copy to a fresh file first: failed imports and selecting the saved image
    // again must never delete or truncate the current payment QR.
    final dest = File(
      p.join(destDir.path, 'payment_qr_${const Uuid().v4()}$safeExt'),
    );
    try {
      await File(sourcePath).copy(dest.path);
      if (!await prefs.setString(_keyPath, dest.path)) {
        throw StateError('Unable to save the payment QR preference');
      }
    } catch (_) {
      if (await dest.exists()) await dest.delete();
      rethrow;
    }
    // Only retire the previously selected, app-owned file after committing.
    if (previousPath != null &&
        p.dirname(previousPath) == destDir.path &&
        p.basename(previousPath).startsWith('payment_qr')) {
      try {
        final previous = File(previousPath);
        if (await previous.exists()) await previous.delete();
      } on FileSystemException {
        // A stale file does not invalidate the newly saved payment QR.
      }
    }
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
