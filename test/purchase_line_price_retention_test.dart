import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/screens/admin/purchase_create_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/widgets/money_text.dart';

const _product = Product(
  id: 'p1',
  nameZh: '商品',
  nameEn: 'Product',
  sku: 'P1',
  barcode: 'B1',
  priceCents: 300,
  costCents: 50,
);

class _PurchaseRepo extends PosRepository {
  List<Map<String, Object?>>? committedLines;
  int? committedTotal;
  @override
  Future<List<Supplier>> listSuppliers() async => [
    const Supplier(id: 's1', name: '供应商'),
  ];
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [_product];
  @override
  Future<Product?> findByBarcodeOrSku(String code) async => _product;
  @override
  Future<void> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<Map<String, Object?>> lines,
    required int totalCents,
    required String operator,
    String notes = '',
    String? purchaseId,
    List<Product> newProducts = const [],
  }) async {
    committedLines = lines;
    committedTotal = totalCents;
  }
}

void main() {
  testWidgets(
    'successive invoice imports preserve different costs for one product',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _PurchaseRepo();
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseCreateScreen(
            repo: repo,
            user: const AppUser(username: 'admin', role: AppRole.admin),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 100; attempt++) {
        if (find.byType(DropdownButton<String>).evaluate().isNotEmpty) break;
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(find.byType(DropdownButton<String>), findsOneWidget);

      Future<void> importLine(int cost) async {
        await tester.tap(find.text('进货单二维码'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          'CNKHPO1:${jsonEncode({
            'v': 1,
            'lines': [
              {'name': '商品', 'barcode': 'B1', 'qty': 1, 'costCents': cost},
            ],
          })}',
        );
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
      }

      await importLine(100);
      await importLine(200);
      final total = tester.widget<MoneyText>(find.byType(MoneyText).last);
      expect(total.amountCents, 300);
      ScaffoldMessenger.of(tester.element(find.byType(PurchaseCreateScreen))).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.text('核对并提交'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(repo.committedTotal, 300);
      expect(repo.committedLines, hasLength(2));
      expect(repo.committedLines!.map((line) => line['unitCostCents']), [
        100,
        200,
      ]);
      expect(repo.committedLines!.map((line) => line['qty']), [1.0, 1.0]);
    },
  );
}
