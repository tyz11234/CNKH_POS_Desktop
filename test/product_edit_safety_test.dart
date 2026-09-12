import 'dart:io';
import 'package:cnkh_pos_desktop/services/lan_mutations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/purchase_reverse_plan.dart';

void main() {
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;
  const product = Product(id: 'p1', nameZh: '商品', nameEn: 'Product',
      sku: 'P1', barcode: 'match', priceCents: 100, stock: 10);
  setUp(() async {
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('product-edit-');
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
  });
  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  test('nonempty search sorts multiple database results safely', () async {
    await repo.upsertProduct(const Product(id: 'p2', nameZh: 'match',
        nameEn: 'Another', sku: 'P2', barcode: 'other', priceCents: 100));
    final results = await repo.searchProducts('match');
    expect(results, hasLength(2));
    expect(results.first.id, 'p1');
  });

  test('name edit preserves inventory and cost changed since opening editor', () async {
    await repo.upsertProduct(product.copyWith(stock: 8, costCents: 50));
    await repo.upsertProduct(product.copyWith(nameZh: '新名称'), original: product);
    final saved = (await repo.getProduct('p1'))!;
    expect(saved.nameZh, '新名称');
    expect(saved.stock, 8);
    expect(saved.costCents, 50);
    final db = await database.db;
    expect(await db.query('stock_moves'), hasLength(1));
  });

  test('explicit stale inventory edit fails without partial name or ledger changes', () async {
    await repo.upsertProduct(product.copyWith(stock: 8));
    await expectLater(repo.upsertProduct(product.copyWith(nameZh: '错误', stock: 12),
        original: product), throwsStateError);
    final saved = (await repo.getProduct('p1'))!;
    expect(saved.stock, 8);
    expect(saved.nameZh, product.nameZh);
    expect(await (await database.db).query('stock_moves'), hasLength(1));
  });

  test('stale editor cannot resurrect a deleted product', () async {
    await repo.softDeleteProduct(product.id);
    await expectLater(repo.upsertProduct(product.copyWith(nameZh: '新名称'),
        original: product), throwsStateError);
    expect((await repo.getProduct(product.id))!.isDeleted, 1);
  });

  test('inventory edits record delta and prevent unsafe purchase reversal', () async {
    await repo.createPurchase(supplierId: 's1', supplierName: 'Supplier',
        totalCents: 500, operator: 'admin', lines: [
          {'productId': 'p1', 'qty': 5, 'unitCostCents': 100},
        ]);
    final current = (await repo.getProduct('p1'))!;
    await repo.upsertProduct(current.copyWith(stock: 12), original: current);
    final db = await database.db;
    final moves = await db.query('stock_moves', where: "reason='product_edit'");
    expect(moves, hasLength(1));
    expect(moves.single['change'], -3);
    final purchase = (await db.query('purchases')).single;
    await expectLater(db.transaction((txn) => planPurchaseReverse(txn, purchase)),
        throwsStateError);
    expect((await repo.getProduct('p1'))!.stock, 12);
  });
  test('synced inventory edit writes exactly one ledger entry across retries', () async {
    final db = await database.db;
    final op = <String, dynamic>{
      'id': 'edit-stock', 'kind': 'product_upsert',
      'payload': {'before': product.toMap(), 'row': product.copyWith(stock: 7).toMap()},
    };
    await applyLanMutation(db, op);
    await applyLanMutation(db, op);
    expect((await repo.getProduct('p1'))!.stock, 7);
    final moves = await db.query('stock_moves', where: "reason='product_edit'");
    expect(moves, hasLength(1));
    expect(moves.single['change'], -3);
  });

}
