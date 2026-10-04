import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/screens/cart_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _product = Product(
  id: 'p1',
  nameZh: '商品',
  nameEn: 'Product',
  sku: 'P1',
  barcode: 'B1',
  priceCents: 500,
  stock: 10,
);

class _Repo extends PosRepository {
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [_product];
  @override
  Future<List<Category>> listCategories({bool includeDeleted = false}) async =>
      [];
  @override
  Future<bool> productImagesEnabled() async => false;
  @override
  Future<void> logAudit({
    required String username,
    required String role,
    required String action,
    String module = 'pos',
    String? productId,
    String? productName,
    String context = '',
    String oldValue = '',
    String newValue = '',
    String reason = '',
  }) async {}
}

void main() {
  for (final order in [false, true]) {
    for (final action in ['确定', '取消']) {
      testWidgets(
        'focused ${order ? 'order' : 'line'} discount closes safely with $action',
        (tester) async {
          tester.view.physicalSize = const Size(1440, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final cart = CartState(items: [CartItem(product: _product)]);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CartScreen(
                  cart: cart,
                  user: const AppUser(username: 'admin', role: AppRole.admin),
                  repo: _Repo(),
                  onChanged: () {},
                  onCheckout: () {},
                  onHold: () async {},
                  onResume: () async {},
                  desktopTwoPane: true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(order ? '整单折扣' : '行折扣 / Discount'));
          await tester.pumpAndSettle();
          if (!order) {
            await tester.tap(find.text('金额 RM'));
            await tester.pumpAndSettle();
          }
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            '1.00',
          );
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            order ? cart.orderDiscountCents : cart.items.single.discountCents,
            action == '确定' ? 100 : 0,
          );
        },
      );
    }
  }
}
