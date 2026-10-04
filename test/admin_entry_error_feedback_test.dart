import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/screens/admin/admin_hub.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/widgets/receipt_template_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _product = Product(
  id: 'p1',
  nameZh: '商品',
  nameEn: 'Product',
  sku: 'P1',
  barcode: 'B1',
  priceCents: 100,
  stock: 10,
);

class _FailRepo extends PosRepository {
  int stockWrites = 0;
  @override
  Future<String> getSetting(String key, {String fallback = ''}) async =>
      fallback;
  @override
  Future<void> setSetting(String key, String value) async =>
      throw StateError('设置数据库不可写');
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [_product];
  @override
  Future<void> adjustStock({
    required String productId,
    required double newStock,
    required String operator,
    String reason = 'stocktake',
    String notes = '',
  }) async {
    if (!newStock.isFinite) throw ArgumentError('库存数量无效');
    stockWrites++;
  }
}

void main() {
  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'receipt template save failure is shown and releases the busy state',
    (tester) async {
      await size(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptTemplateEditor(repo: _FailRepo(), canEdit: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('保存 / Save');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('设置数据库不可写'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(of: button, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'receipt template reset failure is shown and releases the busy state',
    (tester) async {
      await size(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptTemplateEditor(repo: _FailRepo(), canEdit: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('恢复默认 / Reset');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('设置数据库不可写'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(of: button, matching: find.byType(OutlinedButton)),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('stocktake rejects non-finite quantity with a visible error', (
    tester,
  ) async {
    await size(tester);
    final repo = _FailRepo();
    await tester.pumpWidget(
      MaterialApp(
        home: StocktakePage(
          repo: repo,
          user: const AppUser(username: 'admin', role: AppRole.admin),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('商品'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'NaN');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('库存数量无效'), findsOneWidget);
    expect(repo.stockWrites, 0);
  });
}
