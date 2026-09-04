import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Local product image files under app documents `/product_images/`.
class ProductImageStore {
  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(root.path, 'product_images'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> pathFor(String productId, {String ext = 'jpg'}) async {
    final d = await _dir();
    return p.join(d.path, '$productId.$ext');
  }

  Future<String?> saveBytes(String productId, Uint8List bytes,
      {String ext = 'jpg'}) async {
    final path = await pathFor(productId, ext: ext);
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<String?> saveFromFile(String productId, String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final ext = p.extension(sourcePath).replaceFirst('.', '');
    final useExt = ext.isEmpty ? 'jpg' : ext;
    final dest = await pathFor(productId, ext: useExt);
    await src.copy(dest);
    return dest;
  }

  Future<Uint8List?> readBytes(String productId) async {
    final d = await _dir();
    await for (final e in d.list()) {
      if (e is File && p.basenameWithoutExtension(e.path) == productId) {
        return e.readAsBytes();
      }
    }
    return null;
  }

  Future<String?> localPath(String productId) async {
    final d = await _dir();
    await for (final e in d.list()) {
      if (e is File && p.basenameWithoutExtension(e.path) == productId) {
        return e.path;
      }
    }
    return null;
  }

  Future<void> delete(String productId) async {
    final d = await _dir();
    await for (final e in d.list()) {
      if (e is File && p.basenameWithoutExtension(e.path) == productId) {
        await e.delete();
      }
    }
  }

  Future<String?> toBase64(String productId) async {
    final bytes = await readBytes(productId);
    if (bytes == null) return null;
    return base64Encode(bytes);
  }

  Future<String?> saveBase64(String productId, String b64,
      {String ext = 'jpg'}) async {
    try {
      final bytes = base64Decode(b64);
      return await saveBytes(productId, bytes, ext: ext);
    } catch (_) {
      return null;
    }
  }
}
