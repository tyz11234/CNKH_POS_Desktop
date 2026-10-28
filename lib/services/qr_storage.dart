import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'duitnow_qr.dart';

/// Device-local DuitNow QR image storage.
/// Production: sync from Admin desktop later (TBD).
class QrStorage {
  static const _keyPath = 'duitnow_qr_local_path';
  static const _keyPayload = 'duitnow_qr_payload';

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
    await prefs.remove(_keyPayload);
  }

  /// The decoded EMV payload of the imported QR image, when the image
  /// could be decoded (via the server's /api/v1/qr/decode). With a
  /// payload the checkout can generate amount-locked dynamic QRs.
  Future<String?> getPayload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(_keyPayload);
      if (payload == null || payload.isEmpty) return null;
      if (!DuitNowQr.isValid(payload)) return null;
      return payload;
    } catch (_) {
      return null; // storage unavailable (e.g. tests) — static QR still works
    }
  }

  Future<void> setPayload(String? payload) async {
    final prefs = await SharedPreferences.getInstance();
    if (payload == null || payload.isEmpty) {
      await prefs.remove(_keyPayload);
    } else {
      await prefs.setString(_keyPayload, payload);
    }
  }
}
