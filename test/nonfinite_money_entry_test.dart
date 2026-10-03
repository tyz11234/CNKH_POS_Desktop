import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/screens/checkout_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/qr_storage.dart';

const _product = Product(
  id: 'p1',
  nameZh: '商品',
  nameEn: 'Product',
  sku: 'P1',
  barcode: 'B1',
  priceCents: 100,
  stock: 10,
);

class _Repo extends PosRepository {
  int writes = 0;
  @override
  Future<List<Customer>> listCustomers() async => [];
  @override
  Future<String> stockPolicy() async => 'warn';
  @override
  Future<Product?> getProduct(String id) async => _product;
  @override
  Future<SaleRecord> createSale({
    required CartState cart,
    required String paymentMethod,
    required int paidCents,
    required String cashier,
    String? depositMethod,
    Customer? customer,
    String? customerPhone,
  }) async {
    writes++;
    throw StateError('unexpected save');
  }
}

class _Qr extends QrStorage {
  @override
  Future<String?> getLocalPath() async => null;
}

void main() {
  for (final input in ['NaN', 'Infinity', '1e309']) {
    testWidgets('cash rejects $input without crashing or saving', (
      tester,
    ) async {
      final repo = _Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckoutScreen(
              cart: CartState(items: [CartItem(product: _product)]),
              user: const AppUser(username: 'admin', role: AppRole.admin),
              qrStorage: _Qr(),
              repo: repo,
              onPaid: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == '1.00',
      );
      await tester.enterText(field, input);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('确认收款 / Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('金额格式无效'), findsOneWidget);
      expect(repo.writes, 0);
    });
  }
}
