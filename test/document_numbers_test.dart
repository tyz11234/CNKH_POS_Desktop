import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  const product = Product(
    id: 'number-product',
    nameZh: '编号测试',
    nameEn: 'Number test',
    sku: 'NUMBER-1',
    barcode: 'NUMBER-1',
    priceCents: 100,
    costCents: 40,
    stock: 20,
  );

  setUp(() async {
    AppDatabase.ensureFfi();
    temp = await Directory.systemTemp.createTemp('cnkh-document-numbers-');
    database = AppDatabase.forTesting('${temp.path}/pos.db');
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  CartState cart() => CartState(items: [CartItem(product: product)]);
  Future<SaleRecord> sell() => repo.createSale(
    cart: cart(),
    paymentMethod: 'CASH',
    paidCents: 100,
    cashier: 'staff',
  );

  test('resuming an earlier hold does not reuse a remaining hold number', () async {
    final first = await repo.holdCart(cart: cart(), cashier: 'staff');
    final second = await repo.holdCart(cart: cart(), cashier: 'staff');
    await repo.resumeHeld(first);
    final third = await repo.holdCart(cart: cart(), cashier: 'staff');

    expect(second.holdNo, 'H-0002');
    expect(third.holdNo, 'H-0003');
    expect((await repo.listHeld(cashier: 'staff')).map((h) => h.holdNo).toSet(),
        hasLength(2));
  });

  test('concurrent holds receive distinct reserved numbers', () async {
    final holds = await Future.wait(List.generate(
      4,
      (_) => repo.holdCart(cart: cart(), cashier: 'staff'),
    ));
    expect(holds.map((h) => h.holdNo).toSet(), hasLength(4));
  });

  test('concurrent purchases keep stock move references distinct', () async {
    await Future.wait(List.generate(4, (_) => repo.createPurchase(
      supplierId: 'supplier',
      supplierName: 'Supplier',
      lines: [{'productId': product.id, 'qty': 1, 'unitCostCents': 40}],
      totalCents: 40,
      operator: 'admin',
    )));
    final db = await database.db;
    final purchases = await db.query('purchases');
    expect(purchases.map((p) => p['purchase_no']).toSet(), hasLength(4));
    final moves = await db.query('stock_moves', where: "reason='purchase'");
    expect(moves.map((m) => m['notes']).toSet(), hasLength(4));
    expect((await repo.getProduct(product.id))!.stock, 24);
  });

  test('receipt allocation skips gaps and imported higher numbers', () async {
    final first = await sell();
    final second = await sell();
    final prefix = first.receiptNo.substring(0, first.receiptNo.lastIndexOf('-') + 1);
    final db = await database.db;
    await db.update('sales', {'receipt_no': '${prefix}0003'},
        where: 'id=?', whereArgs: [second.id]);
    expect((await sell()).receiptNo, '${prefix}0004');

    await db.update('sales', {'receipt_no': '${prefix}0042-PREMOTE'},
        where: 'id=?', whereArgs: [first.id]);
    expect((await sell()).receiptNo, '${prefix}0043');
  });

  test('reserved numbers survive a close and reopen without an inserted row', () async {
    expect(await database.nextPurchaseNo(), 'PO-0001');
    await database.close();
    expect(await database.nextPurchaseNo(), 'PO-0002');
  });

  test('failed checkout rolls back its receipt reservation', () async {
    final first = await sell();
    await repo.setSetting('stock_policy', 'block');
    await repo.adjustStock(productId: product.id, newStock: 0, operator: 'admin');
    await expectLater(sell(), throwsStateError);
    await repo.adjustStock(productId: product.id, newStock: 1, operator: 'admin');
    final next = await sell();
    expect(first.receiptNo.endsWith('-0001'), isTrue);
    expect(next.receiptNo.endsWith('-0002'), isTrue);
  });
}
