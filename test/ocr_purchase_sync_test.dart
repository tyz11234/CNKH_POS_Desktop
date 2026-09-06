import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_mutations.dart';
import 'package:cnkh_pos_desktop/services/purchase_reverse_safety.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late AppDatabase database;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-ocr-sync-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    final db = await database.db;
    await db.insert(
      'products',
      const Product(
        id: 'p1',
        nameZh: 'Coca Cola',
        nameEn: 'Coca Cola',
        sku: 'CC',
        barcode: '955000000001',
        priceCents: 450,
        costCents: 300,
        stock: 10,
      ).toMap(),
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Map<String, dynamic> purchaseOp({String opId = 'op-purchase-1'}) =>
      <String, dynamic>{
        'id': opId,
        'kind': 'purchase',
        'payload': {
          'id': 'mobile-purchase-1',
          'supplier_id': 's1',
          'supplier_name': 'ABC Trading',
          'purchased_at': '2026-09-06T10:00:00.000',
          'invoice_no': 'INV-001',
          'invoice_date': '2026-09-06',
          'total_cents': 1600,
          'discount_cents': 0,
          'tax_cents': 0,
          'delivery_fee_cents': 0,
          'other_fee_cents': 0,
          'source': 'ocr',
          'draft_id': 'draft-1',
          'ocr_raw_text': 'Coca Cola 5 PCS 3.20 16.00',
          'operator': 'staff',
          'lines': [
            {
              'productId': 'p1',
              'name': 'Coca Cola',
              'qty': 5.0,
              'invoiceQty': 5.0,
              'unit': 'PCS',
              'unitCostCents': 320,
              'invoiceUnitCostCents': 320,
              'subtotalCents': 1600,
              'beforeCostCents': 300,
            },
          ],
        },
      };

  Map<String, dynamic> reverseOp({String opId = 'op-reverse-1'}) =>
      <String, dynamic>{
        'id': opId,
        'kind': 'purchase_reverse',
        'payload': {
          'purchase_id': 'mobile-purchase-1',
          'reason': 'OCR error',
          'notes': 'test',
          'operator': 'admin',
        },
      };

  test('OCR purchase mutation and reversal are idempotent', () async {
    final db = await database.db;
    final purchase = purchaseOp();

    await applyLanMutation(db, purchase);
    await applyLanMutation(db, purchase);
    final afterPurchase =
        (await db.query('products', where: 'id=?', whereArgs: ['p1'])).single;
    expect((afterPurchase['stock'] as num).toDouble(), 15);
    expect(afterPurchase['cost_cents'], 320);
    final storedPurchase = (await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: ['mobile-purchase-1'],
    ))
        .single;
    expect(storedPurchase['source'], 'ocr');
    expect(storedPurchase['invoice_no'], 'INV-001');

    final reverse = reverseOp();
    await applyLanMutation(db, reverse);
    await applyLanMutation(db, reverse);
    final afterReverse =
        (await db.query('products', where: 'id=?', whereArgs: ['p1'])).single;
    expect((afterReverse['stock'] as num).toDouble(), 10);
    expect(afterReverse['cost_cents'], 300);
    expect(
      await db.query(
        'purchase_reversals',
        where: 'purchase_id=?',
        whereArgs: ['mobile-purchase-1'],
      ),
      hasLength(1),
    );
  });

  test('purchase reversal is blocked after a later stock movement', () async {
    final db = await database.db;
    await applyLanMutation(db, purchaseOp());

    await db.rawUpdate('UPDATE products SET stock=stock-1 WHERE id=?', ['p1']);
    await db.insert('stock_moves', {
      'id': 'later-sale-move',
      'product_id': 'p1',
      'change': -1.0,
      'reason': 'sale',
      'created_at': DateTime.now().add(const Duration(seconds: 1)).toIso8601String(),
      'operator': 'staff',
      'notes': 'M20260906-9999',
    });

    await expectLater(
      applyLanMutation(db, reverseOp()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          kUnsafePurchaseReverseMessage,
        ),
      ),
    );

    final product =
        (await db.query('products', where: 'id=?', whereArgs: ['p1'])).single;
    expect((product['stock'] as num).toDouble(), 14);
    expect(product['cost_cents'], 320);
    final purchase = (await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: ['mobile-purchase-1'],
    ))
        .single;
    expect(purchase['reversed'], 0);
    expect(
      await db.query(
        'purchase_reversals',
        where: 'purchase_id=?',
        whereArgs: ['mobile-purchase-1'],
      ),
      isEmpty,
    );
  });

  test('invoice attachment is hash checked and idempotent after lost ACK', () async {
    final db = await database.db;
    await applyLanMutation(db, purchaseOp());

    final bytes = utf8.encode('fake-invoice-image-bytes');
    final digest = await Sha256().hash(bytes);
    final hash = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final attachmentOp = <String, dynamic>{
      'id': 'purchase_attachment:att-1',
      'kind': 'purchase_attachment',
      'payload': {
        'attachment_id': 'att-1',
        'purchase_id': 'mobile-purchase-1',
        'kind': 'invoice_original',
        'filename': 'invoice.jpg',
        'content_hash': hash,
        'base64': base64Encode(bytes),
        'created_at': '2026-09-06T10:00:05.000',
      },
    };

    await applyLanMutation(db, attachmentOp);
    // Simulate a successful first POST whose ACK was lost and the exact same
    // operation was retried.
    await applyLanMutation(db, attachmentOp);

    final attachments = await db.query(
      'purchase_attachments',
      where: 'purchase_id=?',
      whereArgs: ['mobile-purchase-1'],
    );
    expect(attachments, hasLength(1));
    expect(attachments.single['content_hash'], hash);
    expect(List<int>.from(attachments.single['content'] as List), bytes);

    final bad = <String, dynamic>{
      'id': 'purchase_attachment:att-bad',
      'kind': 'purchase_attachment',
      'payload': {
        'attachment_id': 'att-bad',
        'purchase_id': 'mobile-purchase-1',
        'kind': 'invoice_original',
        'filename': 'bad.jpg',
        'content_hash': List<String>.filled(64, '0').join(),
        'base64': base64Encode(bytes),
      },
    };
    await expectLater(
      applyLanMutation(db, bad),
      throwsA(isA<StateError>()),
    );
    expect(
      await db.query('purchase_attachments', where: 'id=?', whereArgs: ['att-bad']),
      isEmpty,
    );
  });
}
