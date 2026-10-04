import 'dart:io';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_mutations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  setUp(() async {
    AppDatabase.ensureFfi();
    temp = await Directory.systemTemp.createTemp('cnkh-purchase-amount-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    await (await database.db).insert(
      'products',
      const Product(
        id: 'p1',
        nameZh: '商品',
        nameEn: 'Product',
        sku: 'SKU1',
        barcode: '10001',
        priceCents: 100,
        costCents: 40,
        stock: 10,
      ).toMap(),
    );
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Map<String, dynamic> operation() => {
    'id': 'op-1',
    'kind': 'purchase',
    'payload': {
      'id': 'purchase-1',
      'supplier_id': 's1',
      'supplier_name': 'Supplier',
      'purchased_at': '2026-10-03T10:00:00Z',
      'total_cents': 100,
      'lines': [
        {'productId': 'p1', 'qty': 1.0, 'unitCostCents': 100},
      ],
    },
  };

  for (final field in [
    'discount_cents',
    'tax_cents',
    'delivery_fee_cents',
    'other_fee_cents',
    'unitCostCents',
    'subtotalCents',
  ]) {
    for (final invalid in [-0.5, 1.5]) {
      test('rejects malformed purchase $field=$invalid atomically', () async {
        final op = operation();
        final payload = op['payload'] as Map<String, dynamic>;
        if (field.endsWith('_cents')) {
          payload[field] = invalid;
        } else {
          ((payload['lines'] as List).single as Map)[field] = invalid;
        }
        final db = await database.db;
        await expectLater(applyLanMutation(db, op), throwsFormatException);
        expect(await db.query('purchases'), isEmpty);
        expect(await db.query('stock_moves'), isEmpty);
        expect(await db.query('sync_applied_operations'), isEmpty);
        final product = (await db.query('products')).single;
        expect(product['stock'], 10);
        expect(product['cost_cents'], 40);
      });
    }
  }
}
