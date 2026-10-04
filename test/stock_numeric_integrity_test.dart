import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  const product = Product(
    id: 'p1',
    nameZh: '商品',
    nameEn: 'Product',
    sku: 'SKU1',
    barcode: '10001',
    priceCents: 100,
    costCents: 40,
    stock: 1e308,
  );

  setUp(() async {
    AppDatabase.ensureFfi();
    temp = await Directory.systemTemp.createTemp('cnkh-stock-number-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
    await (await database.db).delete('sync_outbox');
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  test(
    'stocktake overflow cannot persist an infinite ledger movement',
    () async {
      await expectLater(
        repo.adjustStock(productId: 'p1', newStock: -1e308, operator: 'admin'),
        throwsArgumentError,
      );
      final db = await database.db;
      expect((await repo.getProduct('p1'))!.stock, 1e308);
      expect(await db.query('stock_moves'), isEmpty);
      expect(await db.query('sync_outbox'), isEmpty);
    },
  );

  test(
    'product edit overflow rolls back catalog ledger and pending mutation',
    () async {
      await expectLater(
        repo.upsertProduct(product.copyWith(stock: -1e308), original: product),
        throwsArgumentError,
      );
      final db = await database.db;
      expect((await repo.getProduct('p1'))!.stock, 1e308);
      expect(await db.query('stock_moves'), isEmpty);
      expect(await db.query('sync_outbox'), isEmpty);
    },
  );

  test(
    'purchase stock overflow rejects the whole business transaction',
    () async {
      await expectLater(
        repo.createPurchase(
          supplierId: 's1',
          supplierName: 'Supplier',
          lines: const [
            {'productId': 'p1', 'qty': 1e308, 'unitCostCents': 40},
          ],
          totalCents: 100,
          operator: 'admin',
        ),
        throwsArgumentError,
      );
      final db = await database.db;
      expect((await repo.getProduct('p1'))!.stock, 1e308);
      expect(await db.query('purchases'), isEmpty);
      expect(await db.query('stock_moves'), isEmpty);
      expect(await db.query('sync_outbox'), isEmpty);
    },
  );

  test(
    'product reorder level cannot persist an infinite JSON number',
    () async {
      await expectLater(
        repo.upsertProduct(product.copyWith(reorderLevel: double.infinity)),
        throwsArgumentError,
      );
      expect((await repo.getProduct('p1'))!.reorderLevel, 0);
    },
  );
  test(
    'purchase fractional unit cost never truncates a cent in persistence',
    () async {
      await expectLater(
        repo.createPurchase(
          supplierId: 's1',
          supplierName: 'Supplier',
          lines: const [
            {'productId': 'p1', 'qty': 1, 'unitCostCents': 1.5},
          ],
          totalCents: 100,
          operator: 'admin',
        ),
        throwsArgumentError,
      );
      final db = await database.db;
      expect(await db.query('purchases'), isEmpty);
      expect((await repo.getProduct('p1'))!.costCents, 40);
      expect(await db.query('stock_moves'), isEmpty);
      expect(await db.query('sync_outbox'), isEmpty);
    },
  );
}
