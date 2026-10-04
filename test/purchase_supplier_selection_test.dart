import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/screens/admin/purchase_create_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('cnkh-supplier-picker-');
    database = AppDatabase.forTesting('${dir.path}/desktop.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertSupplier(
      const Supplier(id: 'existing-supplier', name: '现有供应商'),
    );
    await (await database.db).insert(
      'products',
      const Product(
        id: 'p1',
        sku: 'P1',
        barcode: 'B001',
        nameZh: '商品',
        nameEn: 'Product',
        priceCents: 100,
        costCents: 50,
        stock: 10,
      ).toMap(),
    );
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<void> waitForSelectedSupplier(WidgetTester tester, String name) async {
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final dropdownFinder = find.byType(DropdownButton<String>);
      if (dropdownFinder.evaluate().isEmpty) continue;
      final dropdown = tester.widget<DropdownButton<String>>(
        dropdownFinder.first,
      );
      final selectedId = dropdown.value;
      if (selectedId == null) continue;
      // A database read here could queue behind the UI transaction while
      // runAsync stops pumping that transaction's fake-async continuations.
      // Wait for the refreshed, selected dropdown item before querying SQLite.
      if (dropdown.items!.any(
        (item) =>
            item.value == selectedId &&
            item.child is Text &&
            (item.child as Text).data == name,
      )) {
        return;
      }
    }
    fail('Supplier "$name" was not selected within 10 seconds');
  }

  Future<void> openPurchase(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PurchaseCreateScreen(
          repo: repo,
          user: const AppUser(username: 'admin', role: AppRole.admin),
        ),
      ),
    );
    await waitForSelectedSupplier(tester, '现有供应商');
  }

  Future<String> selectedSupplierId(WidgetTester tester) async {
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    expect(dropdown.value, isNotNull);
    final listed = await tester.runAsync(() => repo.listSuppliers());
    expect(listed!.any((supplier) => supplier.id == dropdown.value), isTrue);
    return dropdown.value!;
  }

  Finder supplierNameField() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == '名称 *',
  );

  testWidgets(
    'ordinary supplier creation selects the instance from the refreshed list',
    (tester) async {
      await openPurchase(tester);
      await tester.tap(find.byTooltip('新增供应商'));
      await tester.pumpAndSettle();
      await tester.enterText(supplierNameField(), '普通新供应商');
      await tester.tap(find.text('保存'));
      await waitForSelectedSupplier(tester, '普通新供应商');
      await tester.pumpAndSettle();

      final id = await selectedSupplierId(tester);
      final supplier = (await tester.runAsync(
        () => repo.listSuppliers(),
      ))!.singleWhere((value) => value.id == id);
      expect(supplier.name, '普通新供应商');
    },
  );

  testWidgets(
    'QR supplier creation selects its refreshed ID for purchase creation',
    (tester) async {
      await openPurchase(tester);
      await tester.tap(find.text('进货单二维码'));
      await tester.pumpAndSettle();
      final payload = jsonEncode({
        'v': 1,
        'type': 'cnkh_purchase',
        'supplier': '二维码新供应商',
        'lines': [
          {'name': '商品', 'qty': 2, 'costCents': 50, 'barcode': 'B001'},
        ],
      });
      await tester.enterText(find.byType(TextField).last, 'CNKHPO1:$payload');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建并选用'));
      await waitForSelectedSupplier(tester, '二维码新供应商');
      await tester.pumpAndSettle();
      expect(find.text('二维码含供应商'), findsNothing);

      final id = await selectedSupplierId(tester);
      expect(
        (await tester.runAsync(
          () => repo.listSuppliers(),
        ))!.singleWhere((value) => value.id == id).name,
        '二维码新供应商',
      );
      await tester.runAsync(
        () => repo.createPurchase(
          supplierId: id,
          supplierName: '二维码新供应商',
          lines: const [
            {'productId': 'p1', 'qty': 2, 'unitCostCents': 50},
          ],
          totalCents: 100,
          operator: 'admin',
        ),
      );

      final purchases = await tester.runAsync(
        () async => (await database.db).query('purchases'),
      );
      expect(purchases, hasLength(1));
      expect(purchases!.single['supplier_id'], id);
    },
  );
}
