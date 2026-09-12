import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/purchase_reverse_safety.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;

  setUp(() async {
    AppDatabase.ensureFfi();
    temp = await Directory.systemTemp.createTemp('cnkh-purchase-reverse-');
    database = AppDatabase.forTesting('${temp.path}/pos.db');
    repo = PosRepository(database: database);
    await repo.upsertProduct(const Product(
      id: 'p1', nameZh: '商品', nameEn: 'Product', sku: 'P1', barcode: 'P1',
      priceCents: 500, costCents: 100, stock: 10,
    ));
    await repo.createPurchase(
      supplierId: 's1', supplierName: 'Supplier', totalCents: 1300,
      operator: 'admin', lines: [
        {'productId': 'p1', 'qty': 2, 'unitCostCents': 200, 'beforeCostCents': 100},
        {'productId': 'p1', 'qty': 3, 'unitCostCents': 300, 'beforeCostCents': 200},
      ],
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<void> reverse() async {
    final db = await database.db;
    final purchase = (await db.query('purchases')).single;
    await db.transaction((txn) => reversePurchaseSafely(txn, purchase: purchase,
        operator: 'admin', reason: 'incorrect invoice'));
  }

  Future<void> expectUnchanged(double stock) async {
    final db = await database.db;
    expect((await repo.getProduct('p1'))!.stock, stock);
    expect((await repo.getProduct('p1'))!.costCents, 300);
    expect((await db.query('purchases')).single['reversed'], 0);
    expect(await db.query('purchase_reversals'), isEmpty);
    expect(await db.query('stock_moves', where: "reason='purchase_reversal'"), isEmpty);
  }

  test('repeated product rows reverse their combined quantity and original cost once', () async {
    await reverse();
    await reverse();
    expect((await repo.getProduct('p1'))!.stock, 10);
    expect((await repo.getProduct('p1'))!.costCents, 100);
    final db = await database.db;
    expect((await db.query('purchases')).single['reversed'], 1);
    expect(await db.query('purchase_reversals'), hasLength(1));
    final moves = await db.query('stock_moves', where: "reason='purchase_reversal'");
    expect(moves, hasLength(1));
    expect(moves.single['change'], -5);
  });

  test('stock must cover all repeated lines before any mutation', () async {
    final db = await database.db;
    await db.update('products', {'stock': 4}, where: 'id=?', whereArgs: ['p1']);
    await expectLater(reverse(), throwsStateError);
    await expectUnchanged(4);
  });

  test('missing purchase ledger blocks reversal', () async {
    final db = await database.db;
    await db.delete('stock_moves');
    await expectLater(reverse(), throwsStateError);
    await expectUnchanged(15);
  });

  test('incomplete purchase ledger blocks reversal', () async {
    final db = await database.db;
    final moves = await db.query('stock_moves');
    await db.delete('stock_moves', where: 'id=?', whereArgs: [moves.first['id']]);
    await expectLater(reverse(), throwsStateError);
    await expectUnchanged(15);
  });

  test('later inventory operation cannot hide behind an earlier clock timestamp', () async {
    final db = await database.db;
    // Use one line so the original Desktop one-move check cannot mask this bug.
    final purchase = (await db.query('purchases')).single;
    await db.update('purchases', {'lines_json': jsonEncode([
      {'productId': 'p1', 'qty': 5, 'unitCostCents': 300, 'beforeCostCents': 100},
    ])}, where: 'id=?', whereArgs: [purchase['id']]);
    await db.delete('stock_moves');
    await db.insert('stock_moves', {
      'id': 'purchase-move', 'product_id': 'p1', 'change': 5,
      'reason': 'purchase', 'notes': purchase['purchase_no'],
      'created_at': purchase['purchased_at'], 'operator': 'admin',
    });
    await db.insert('stock_moves', {
      'id': 'later-move', 'product_id': 'p1', 'change': 1,
      'reason': 'stocktake', 'notes': 'clock moved backwards',
      'created_at': '2000-01-01T00:00:00', 'operator': 'admin',
    });
    await db.update('products', {'stock': 16}, where: 'id=?', whereArgs: ['p1']);
    await expectLater(reverse(), throwsStateError);
    await expectUnchanged(16);
  });

  test('empty purchase cannot be marked reversed', () async {
    final db = await database.db;
    await db.update('purchases', {'lines_json': '[]'});
    await expectLater(reverse(), throwsA(isA<FormatException>()));
    await expectUnchanged(15);
  });
}
