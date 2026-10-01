import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

/// A receipt is owned only after this app records its exact bytes. Legacy PDFs,
/// unrelated files, changed files, subdirectories and links are never removed.
class OwnedReceiptCache {
  OwnedReceiptCache(this.directory);
  final Directory directory;
  static const folder = 'cnkh_receipts_owned_v2';
  static const _suffix = '.cnkh-receipt.json';

  Future<void> register(File file) async {
    if (p.normalize(p.dirname(file.path)) != p.normalize(directory.path) ||
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError('收据缓存文件归属无效');
    }
    final hash = await Sha256().hash(await file.readAsBytes());
    await File('${file.path}$_suffix').writeAsString(jsonEncode({
      'format': 'cnkh-receipt-cache:v2',
      'filename': p.basename(file.path),
      'sha256': base64Encode(hash.bytes),
    }), flush: true);
  }

  Stream<File> ownedFiles() async* {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) return;
    await for (final marker in directory.list(followLinks: false)) {
      if (marker is! File || !marker.path.endsWith(_suffix)) continue;
      try {
        final record = jsonDecode(await marker.readAsString());
        final name = record['filename'];
        if (record['format'] != 'cnkh-receipt-cache:v2' ||
            name is! String || p.basename(name) != name ||
            !name.toLowerCase().endsWith('.pdf')) continue;
        final file = File(p.join(directory.path, name));
        if ('${file.path}$_suffix' != marker.path ||
            await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file) continue;
        final hash = await Sha256().hash(await file.readAsBytes());
        if (base64Encode(hash.bytes) == record['sha256']) yield file;
      } catch (_) {
        // Unknown ownership is a reason to preserve, never to delete.
      }
    }
  }

  Future<int> clear({DateTime? before}) async {
    var deleted = 0;
    await for (final file in ownedFiles()) {
      try {
        if (before != null && !(await file.stat()).modified.isBefore(before)) {
          continue;
        }
        await file.delete();
        deleted++;
        await File('${file.path}$_suffix').delete();
      } catch (_) {}
    }
    return deleted;
  }
}
