import 'dart:convert';

import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/screens/admin/purchase_create_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/purchase_invoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyRepo extends PosRepository {
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
  }) async => [];
}

void main() {
  for (final qty in ['NaN', 'Infinity', '1e309', 0, -1]) {
    test('QR rejects invalid quantity $qty before creating a draft', () {
      final raw = jsonEncode({
        'v': 1,
        'lines': [
          {'name': '商品', 'qty': qty, 'costCents': 100},
        ],
      });
      expect(PurchaseInvoicePayload.tryParse(raw), isNull);
    });
  }

  test(
    'QR rejects quantities and money whose line total overflows exact cents',
    () {
      final raw = jsonEncode({
        'v': 1,
        'lines': [
          {'name': '商品', 'qty': 1e200, 'costCents': 1000000000000000},
        ],
      });
      expect(PurchaseInvoicePayload.tryParse(raw), isNull);
    },
  );

  test('QR retains valid zero cost and integral numeric cent fields', () {
    final payload = PurchaseInvoicePayload.tryParse(
      jsonEncode({
        'v': 1,
        'lines': [
          {'name': '赠品', 'qty': 1, 'costCents': 0},
          {
            'name': '商品',
            'qty': 2.5,
            'costCents': 100.0,
            'sellPriceCents': 200.0,
          },
        ],
      }),
    );
    expect(payload, isNotNull);
    expect(payload!.lines.map((line) => line.subtotalCents), [0, 250]);
    expect(payload.lines.last.sellPriceCents, 200);
  });

  test('OCR refuses oversized money rather than saturating an integer', () {
    expect(
      () => PurchaseInvoiceTextParser.parse('螺丝 x1 RM${'9' * 100}'),
      throwsFormatException,
    );
  });

  testWidgets(
    'malformed invoice QR shows an error while the draft remains empty',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseCreateScreen(
            repo: _EmptyRepo(),
            user: const AppUser(username: 'admin', role: AppRole.admin),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('进货单二维码'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'CNKHPO1:{"v":1,"lines":[{"name":"商品","qty":"NaN","costCents":100}]}',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('无法识别进货单格式'), findsOneWidget);
      expect(find.text('明细 0 行'), findsOneWidget);
    },
  );

  testWidgets(
    'oversized pasted money shows a validation error without adding lines',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseCreateScreen(
            repo: _EmptyRepo(),
            user: const AppUser(username: 'admin', role: AppRole.admin),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴文本'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        '螺丝 x1 RM${'9' * 100}',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('进货单数量或金额无效'), findsOneWidget);
      expect(find.text('明细 0 行'), findsOneWidget);
    },
  );
}
