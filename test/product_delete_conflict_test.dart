import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_mutations.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale product upsert cannot resurrect a synced tombstone', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-product-tombstone-');
    final database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);

    try {
      const product = Product(
        id: 'product-remote-1',
        nameZh: '同步商品',
        nameEn: 'Synced Product',
        sku: 'SYNC-DEL-1',
        barcode: '1234567890128',
        priceCents: 500,
        costCents: 300,
        stock: 12,
      );
      await repo.upsertProduct(product);
      final db = await database.db;
      final active = product.toMap();
      final deleted = {...active, 'is_deleted': 1};

      await applyLanMutation(db, {
        'id': 'delete-op-1',
        'kind': 'product_upsert',
        'payload': {
          'row': deleted,
          'before': active,
        },
      });

      var stored = await db.query(
        'products',
        where: 'id=?',
        whereArgs: [product.id],
      );
      expect(stored, hasLength(1));
      expect(stored.single['is_deleted'], 1);

      await expectLater(
        applyLanMutation(db, {
          'id': 'stale-active-op-2',
          'kind': 'product_upsert',
          'payload': {
            'row': active,
            'before': active,
          },
        }),
        throwsA(isA<StateError>()),
      );

      stored = await db.query(
        'products',
        where: 'id=?',
        whereArgs: [product.id],
      );
      expect(stored.single['is_deleted'], 1);
      expect(await repo.findByBarcodeOrSku(product.barcode), isNull);
    } finally {
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
