import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  const product = Product(id: 'p1', nameZh: '测试', nameEn: 'Test', sku: 'T1', barcode: '1001', priceCents: 100, costCents: 40, stock: 10);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-regression-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: true);
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
  });
  tearDown(() async { await database.close(); await temp.delete(recursive:true); });
  Future<SaleRecord> sell([int qty = 1]) => repo.createSale(cart: CartState(items: [CartItem(product: product, qty: qty)]), paymentMethod: 'CASH', paidCents: qty * 100, cashier: 'staff');

  test('void restores actual deducted stock exactly once', () async {
    final sale = await sell(3);
    expect((await repo.getProduct('p1'))!.stock, 7);
    await repo.voidSale(sale.id, 'mistake');
    await repo.voidSale(sale.id, 'retry');
    expect((await repo.getProduct('p1'))!.stock, 10);
    final db = await database.db;
    expect(await db.query('stock_reversals'), hasLength(1));
  });
  test('cost is frozen at checkout even after product cost changes', () async {
    final sale = await sell();
    await repo.upsertProduct(product.copyWith(costCents: 90, stock: 9));
    final row = (await (await database.db).query('sales', where: 'id=?', whereArgs: [sale.id])).single;
    expect((jsonDecode(row['lines_json'] as String) as List).single['unitCostCents'], 40);
  });
  test('block policy checks current stock and rolls back failed checkout', () async {
    await repo.setSetting('stock_policy', 'block');
    await repo.upsertProduct(product.copyWith(stock: 1));
    await sell();
    await expectLater(sell(), throwsStateError);
    expect((await repo.getProduct('p1'))!.stock, 0);
    expect(await repo.salesAll(), hasLength(1));
  });
  test('concurrent last-item checkouts cannot oversell', () async {
    await repo.setSetting('stock_policy', 'block');
    await repo.upsertProduct(product.copyWith(stock: 1));
    final results = await Future.wait(List.generate(2, (_) async {
      try { await sell(); return true; } on StateError { return false; }
    }));
    expect(results.where((ok) => ok), hasLength(1));
    expect((await repo.getProduct('p1'))!.stock, 0);
  });
  test('history includes more than 200 sales and receipt numbers stay unique', () async {
    for (var i = 0; i < 205; i++) { await sell(); }
    final sales = await repo.salesAll();
    expect(sales, hasLength(205));
    expect(sales.map((s) => s.receiptNo).toSet(), hasLength(205));
  });
  test('authentication rejects demo PIN and takes role from saved account', () async {
    await expectLater(repo.auth.login('admin', '1234'), throwsStateError);
    await repo.auth.initializeAdmin('839201');
    await expectLater(repo.auth.initializeAdmin('111111'), throwsStateError);
    expect((await repo.auth.login('admin', '839201')).isAdmin, isTrue);
    await repo.auth.setUserPin('staff', '728394');
    repo.auth.logout();
    expect((await repo.auth.login('staff', '728394')).isAdmin, isFalse);
    await expectLater(repo.auth.setUserPin('admin', '111111'), throwsStateError);
    final row = (await (await database.db).query('user_credentials', where: 'username=?', whereArgs: ['admin'])).single;
    expect(row['pin_hash'], isNot('839201'));
    expect(row.containsValue('839201'), isFalse);
  });
}
