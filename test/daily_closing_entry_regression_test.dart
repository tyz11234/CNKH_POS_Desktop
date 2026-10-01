import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/screens/admin/admin_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp; late AppDatabase database; late PosRepository repo; late DateTime clock;
  const product = Product(id: 'p', nameZh: 'Closing product', nameEn: 'Product', sku: 'CLOSE',
    barcode: '10001', priceCents: 100, costCents: 40, stock: 100);
  const user = AppUser(username: 'admin', role: AppRole.admin);
  setUp(() async {
    clock = DateTime(2026,10,1,23,59);
    temp = await Directory.systemTemp.createTemp('cnkh-close-entry-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database, clock: () => clock);
    await repo.upsertProduct(product);
  });
  tearDown(() async { await database.close(); await temp.delete(recursive: true); });
  Future<SaleRecord> sell({bool credit = false, String day = '2026-10-01'}) async {
    final sale = await repo.createSale(cart: CartState(items: [CartItem(product: product)]),
      paymentMethod: credit ? 'CREDIT' : 'CASH', paidCents: credit ? 30 : 100, cashier: 'admin',
      depositMethod: credit ? 'CASH' : null,
      customer: credit ? const Customer(id: 'c', name: 'Customer') : null);
    await (await database.db).update('sales', {'sold_at': '${day}T12:00:00'}, where: 'id=?', whereArgs: [sale.id]);
    return sale;
  }
  Future<void> flush(WidgetTester tester) async {
    for (var i=0;i<6;i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:40)));
      await tester.pump(const Duration(milliseconds:60));
    }
  }
  testWidgets('F11 actual page saves new cash and voids with cash deposits for its original day after midnight', (tester) async {
    final first = await tester.runAsync(() => sell());
    await tester.pumpWidget(MaterialApp(home: DailyClosePage(repo: repo, user: user, clock: () => clock)));
    await flush(tester);
    await tester.runAsync(() async {
      await sell(); await sell(credit: true); await repo.voidSale(first!.id, 'synced cancellation');
      await sell(day: '2026-10-02');
    });
    clock = DateTime(2026,10,2,0,1);
    await tester.tap(find.text('保存日结')); await tester.tap(find.text('保存日结'));
    await flush(tester);
    final rows = await tester.runAsync(() => repo.listClosings());
    expect(rows, hasLength(1));
    expect(rows!.single['business_date'], '2026-10-01');
    expect(rows.single['system_cash_cents'], 130);
    expect(rows.single['closed_at'], startsWith('2026-10-02'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('F11 queued concurrent sale commits before closing and duplicate saves compute their own transaction snapshot', () async {
    final db = await database.db;
    final occupied = Completer<void>(); final release = Completer<void>();
    final blocker = db.transaction((txn) async { occupied.complete(); await release.future; });
    await occupied.future;
    final sale = sell();
    final close = repo.saveDailyClosing(businessDate:'2026-10-01', openingCashCents:0,
      countedCashCents:100, systemCashCents:99999, closedBy:'admin');
    release.complete(); await blocker; await sale; await close;
    expect((await repo.listClosings()).single['system_cash_cents'],100);
    // Each repeated save derives a fresh authoritative snapshot.
    await repo.saveDailyClosing(businessDate:'2026-10-01', openingCashCents:0,
      countedCashCents:100, systemCashCents:-1, closedBy:'admin');
    final first = (await repo.listClosings()).single;
    expect(first['system_cash_cents'],100);
    await repo.saveDailyClosing(businessDate:'2026-10-01', openingCashCents:10,
      countedCashCents:110, closedBy:'admin');
    final second = (await repo.listClosings()).single;
    expect(second['id'],first['id']); expect(second['system_cash_cents'],100);
    expect(second['business_date'],'2026-10-01');
    await expectLater(repo.saveDailyClosing(businessDate:'2026-02-30', openingCashCents:0,
      countedCashCents:0, closedBy:'admin'),throwsArgumentError);
  });
}
