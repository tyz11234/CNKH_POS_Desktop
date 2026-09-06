import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_mutations.dart';

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

  test('OCR purchase mutation and reversal are idempotent', () async {
    final db = await database.db;
    final purchaseOp = <String, dynamic>{
      'id': 'op-purchase-1',
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

    await applyLanMutation(db, purchaseOp);
    await applyLanMutation(db, purchaseOp);
    final afterPurchase = (await db.query('products', where: 'id=?', whereArgs: ['p1'])).single;
    expect((afterPurchase['stock'] as num).toDouble(), 15);
    expect(afterPurchase['cost_cents'], 320);
    final purchase = (await db.query('purchases', where: 'id=?', whereArgs: ['mobile-purchase-1'])).single;
    expect(purchase['source'], 'ocr');
    expect(purchase['invoice_no'], 'INV-001');

    final reverseOp = <String, dynamic>{
      'id': 'op-reverse-1',
      'kind': 'purchase_reverse',
      'payload': {
        'purchase_id': 'mobile-purchase-1',
        'reason': 'OCR error',
        'notes': 'test',
        'operator': 'admin',
      },
    };
    await applyLanMutation(db, reverseOp);
    await applyLanMutation(db, reverseOp);
    final afterReverse = (await db.query('products', where: 'id=?', whereArgs: ['p1'])).single;
    expect((afterReverse['stock'] as num).toDouble(), 10);
    expect(afterReverse['cost_cents'], 300);
    expect(
      (await db.query('purchase_reversals', where: 'purchase_id=?', whereArgs: ['mobile-purchase-1'])),
      hasLength(1),
    );
  });
}
