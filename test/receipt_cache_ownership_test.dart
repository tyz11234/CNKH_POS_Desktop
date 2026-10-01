import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/e_receipt.dart';
import 'package:cnkh_pos_desktop/services/owned_receipt_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('F05 cleanup preserves unrelated, legacy, changed and nested PDFs', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-owned-cache-');
    final db = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    final repo = PosRepository(database: db);
    try {
      await repo.setSetting(kEReceiptCacheDirKey, temp.path);
      final unrelated = await File('${temp.path}/contract.pdf').writeAsBytes([1,2,3]);
      final legacy = await File('${temp.path}/receipt_R1.PDF').writeAsBytes([4]);
      final cache = await eReceiptCacheDir(repo: repo);
      expect(cache.path, isNot(temp.path));
      final inside = await File('${cache.path}/receipt_contract.pdf').writeAsBytes([5]);
      final old = await File('${cache.path}/owned.PDF').writeAsBytes([6]);
      final fresh = await File('${cache.path}/fresh.pdf').writeAsBytes([7]);
      final changed = await File('${cache.path}/changed.pdf').writeAsBytes([8]);
      final ownership = OwnedReceiptCache(cache);
      for (final file in [old, fresh, changed]) { await ownership.register(file); }
      await changed.writeAsBytes([9]);
      await old.setLastModified(DateTime.now().subtract(const Duration(days: 10)));
      await unrelated.setLastModified(DateTime.now().subtract(const Duration(days: 10)));
      final nested = await Directory('${cache.path}/supplier').create();
      final nestedPdf = await File('${nested.path}/invoice.pdf').writeAsBytes([10]);
      expect(await countEReceiptCache(repo: repo), 2);
      expect(await purgeEReceiptCache(repo: repo), 1);
      expect(await purgeEReceiptCache(repo: repo), 0);
      expect(await clearEReceiptCache(repo: repo), 1);
      expect(await clearEReceiptCache(repo: repo), 0);
      for (final file in [unrelated, legacy, inside, changed, nestedPdf]) {
        expect(await file.exists(), isTrue, reason: file.path);
      }
      expect(await old.exists(), isFalse);
      expect(await fresh.exists(), isFalse);
      expect(await countEReceiptCache(repo: repo), 0);
    } finally { await db.close(); await temp.delete(recursive: true); }
  });
}
