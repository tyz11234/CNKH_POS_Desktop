import 'dart:io';
import 'dart:typed_data';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/db/ocr_purchase_schema.dart';
import 'package:cnkh_pos_desktop/services/purchase_attachment_store.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Desktop exports verified invoice original with Chinese filename', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-attachment-export-');
    final out = Directory('${temp.path}/导出资料');
    await out.create();
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    try {
      final db = await database.db;
      await ensureOcrPurchaseSchema(db);
      await db.insert('purchases', {
        'id': 'p-attach',
        'purchase_no': 'PO-ATTACH',
        'supplier_name': '供应商A',
        'purchased_at': '2026-09-06T10:00:00Z',
        'total_cents': 100,
        'lines_json': '[]',
        'notes': '',
      });
      final bytes = Uint8List.fromList(
        List<int>.generate(2048, (i) => (i * 13) & 0xff),
      );
      final hash = hex((await Sha256().hash(bytes)).bytes);
      await db.insert('purchase_attachments', {
        'id': 'att-export',
        'purchase_id': 'p-attach',
        'kind': 'invoice_original',
        'filename': '进货单 原图.jpg',
        'content_hash': hash,
        'content': bytes,
        'source': 'mobile',
        'created_at': '2026-09-06T10:00:01Z',
      });

      final store = PurchaseAttachmentStore(database: database);
      final list = await store.listForPurchase('p-attach');
      expect(list, hasLength(1));
      expect(list.single.filename, '进货单 原图.jpg');

      final exported = await store.exportToDirectory('att-export', out);
      expect(exported.path, endsWith('进货单 原图.jpg'));
      expect(await exported.readAsBytes(), bytes);

      final duplicate = await store.exportToDirectory('att-export', out);
      expect(duplicate.path, endsWith('进货单 原图 (2).jpg'));
      expect(await duplicate.readAsBytes(), bytes);
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });

  test('Desktop refuses to export a corrupted attachment', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-attachment-corrupt-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    try {
      final db = await database.db;
      await ensureOcrPurchaseSchema(db);
      await db.insert('purchases', {
        'id': 'p-bad',
        'purchase_no': 'PO-BAD',
        'supplier_name': 'Supplier',
        'purchased_at': '2026-09-06T10:00:00Z',
        'total_cents': 100,
        'lines_json': '[]',
        'notes': '',
      });
      await db.insert('purchase_attachments', {
        'id': 'att-bad',
        'purchase_id': 'p-bad',
        'kind': 'invoice_original',
        'filename': 'bad.jpg',
        'content_hash': List<String>.filled(64, '0').join(),
        'content': Uint8List.fromList(<int>[1, 2, 3, 4]),
        'source': 'mobile',
        'created_at': '2026-09-06T10:00:01Z',
      });

      final store = PurchaseAttachmentStore(database: database);
      await expectLater(
        store.exportToDirectory('att-bad', temp),
        throwsA(isA<StateError>()),
      );
    } finally {
      await database.close();
      await temp.delete(recursive: true);
    }
  });
}
