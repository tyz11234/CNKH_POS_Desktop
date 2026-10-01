import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/purchase_invoice.dart';
import 'package:cnkh_pos_desktop/services/purchase_reverse_safety.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp; late AppDatabase database; late PosRepository repo;
  late PurchaseLineMatcher matcher;
  const supplier = Supplier(id: 's', name: 'Supplier');
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-matcher-atomic-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database); matcher = PurchaseLineMatcher(repo);
    await repo.upsertProduct(const Product(id: 'p', nameZh: 'Screw', nameEn: 'Screw',
      sku: 'P1', barcode: '10001', priceCents: 100, costCents: 40, stock: 10));
  });
  tearDown(() async { await database.close(); await temp.delete(recursive: true); });
  Future<void> reverse() async {
    final db = await database.db;
    final purchase = (await db.query('purchases')).single;
    await db.transaction((txn) => reversePurchaseSafely(txn, purchase: purchase,
      operator: 'admin', reason: 'wrong invoice'));
  }
  test('F07 actual matcher snapshots authoritative original cost across duplicate lines, retries and reversal', () async {
    final lines = await matcher.resolve([
      PurchaseDraftLine(name: 'Screw', barcode: '10001', qty: 2, unitCostCents: 60),
      PurchaseDraftLine(name: 'Screw', barcode: '10001', qty: 3, unitCostCents: 70)]);
    // Cost changed after preview: execution must use the current authority.
    final current = (await repo.getProduct('p'))!;
    await repo.upsertProduct(current.copyWith(costCents: 45), original: current);
    await matcher.commit(lines: lines, supplier: supplier, operator: 'admin');
    await matcher.commit(lines: lines, supplier: supplier, operator: 'admin');
    final db = await database.db;
    final purchase = (await db.query('purchases')).single;
    final saved = jsonDecode(purchase['lines_json'] as String) as List;
    expect(saved.map((l) => l['desktopBeforeCostCents']), [45,45]);
    expect((await repo.getProduct('p'))!.stock, 15);
    expect((await repo.getProduct('p'))!.costCents, 70);
    await reverse(); await reverse();
    expect((await repo.getProduct('p'))!.stock, 10);
    expect((await repo.getProduct('p'))!.costCents, 45);
  });
  test('F07 middle failure rolls back costs, new products, numbers, moves and purchase', () async {
    final db = await database.db;
    final lines = [PurchaseDraftLine(name: 'New', sku: 'NEW', qty: 1, unitCostCents: 80),
      PurchaseDraftLine(name: 'Screw', productId: 'p', willCreate: false, qty: 2, unitCostCents: 60)];
    await db.execute("CREATE TRIGGER fail_purchase BEFORE INSERT ON stock_moves WHEN NEW.reason='purchase' AND NEW.product_id='p' BEGIN SELECT RAISE(ABORT,'injected line failure'); END");
    await expectLater(matcher.commit(lines: lines, supplier: supplier, operator: 'admin'), throwsA(anything));
    expect((await repo.getProduct('p'))!.stock, 10);
    expect((await repo.getProduct('p'))!.costCents, 40);
    expect(await db.query('products'), hasLength(1));
    expect(await db.query('purchases'), isEmpty);
    expect(await db.query('stock_moves'), isEmpty);
    expect(await db.query('settings', where: "key LIKE 'document_sequence:purchases:%'"), isEmpty);
    expect(lines.first.productId, isNull);
    await db.execute('DROP TRIGGER fail_purchase');
    await matcher.commit(lines: lines, supplier: supplier, operator: 'admin');
    await matcher.commit(lines: lines, supplier: supplier, operator: 'admin');
    expect(await db.query('purchases'), hasLength(1));
    expect(await db.query('products'), hasLength(2));
    expect((await repo.getProduct('p'))!.stock, 12);
  });
  test('F07 later authoritative cost and old purchases are never guessed on reversal', () async {
    final lines = await matcher.resolve([PurchaseDraftLine(name: 'Screw', barcode: '10001', qty: 2, unitCostCents: 60)]);
    await matcher.commit(lines: lines, supplier: supplier, operator: 'admin');
    final current = (await repo.getProduct('p'))!;
    await repo.upsertProduct(current.copyWith(costCents: 90), original: current);
    await reverse();
    expect((await repo.getProduct('p'))!.costCents, 90);
    expect((await repo.getProduct('p'))!.stock, 10);
    final db = await database.db;
    final old = (await db.query('purchases')).single;
    final stored = (jsonDecode(old['lines_json'] as String) as List).map((r) => Map<String,dynamic>.from(r as Map)..remove('desktopBeforeCostCents')).toList();
    expect(stored.single.containsKey('desktopBeforeCostCents'), isFalse);
  });
  test('F07 actual reversal of a legacy record without original snapshot preserves the known cost', () async {
    final lines = await matcher.resolve([PurchaseDraftLine(name: 'Screw', barcode: '10001', qty: 2, unitCostCents: 60)]);
    await matcher.commit(lines: lines, supplier: supplier, operator: 'admin');
    final db = await database.db;
    final purchase = (await db.query('purchases')).single;
    final oldLines = (jsonDecode(purchase['lines_json'] as String) as List)
      .map((r) => Map<String,dynamic>.from(r as Map)..remove('desktopBeforeCostCents')).toList();
    await db.update('purchases', {'lines_json': jsonEncode(oldLines)});
    await reverse();
    expect((await repo.getProduct('p'))!.stock, 10);
    expect((await repo.getProduct('p'))!.costCents, 60);
  });

}
