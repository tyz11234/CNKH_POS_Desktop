import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/screens/cart_screen.dart';
import 'package:cnkh_pos_desktop/screens/checkout_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/qr_storage.dart';

const _oldProduct = Product(
  id: 'old',
  sku: 'OLD',
  barcode: 'OLD',
  nameZh: 'Old product',
  nameEn: 'Old product',
  priceCents: 2000,
  stock: 10,
);
const _nextProduct = Product(
  id: 'next',
  sku: 'NEXT',
  barcode: 'NEXT',
  nameZh: 'Next product',
  nameEn: 'Next product',
  priceCents: 500,
  stock: 10,
);
const _user = AppUser(username: 'admin', role: AppRole.admin);

class _QrStorage extends QrStorage {
  @override
  Future<String?> getLocalPath() async => null;
}

class _Repository extends PosRepository {
  int commits = 0;
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [_oldProduct, _nextProduct];
  @override
  Future<List<Category>> listCategories({bool includeDeleted = false}) async =>
      [];
  @override
  Future<bool> productImagesEnabled() async => false;
  @override
  Future<String> stockPolicy() async => 'block';
  @override
  Future<Product?> getProduct(String id) async => _oldProduct;
  @override
  Future<List<Customer>> listCustomers({
    int? limit,
    int offset = 0,
    String query = '',
  }) async => [const Customer(id: 'customer', name: 'Customer')];
  @override
  Future<int> customerOutstandingCents(String customerId) async => 0;
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
    commits++;
    final due = cart.payableCents(isCredit: paymentMethod == 'CREDIT');
    return SaleRecord(
      id: 'sale',
      receiptNo: 'TEST-1',
      soldAt: '2026-10-01T10:00:00',
      cashier: cashier,
      paymentMethod: paymentMethod,
      subtotalCents: 2000,
      itemDiscountCents: 0,
      orderDiscountCents: 2000,
      roundingCents: 0,
      totalCents: due,
      paidCents: paidCents,
      changeCents: paidCents - due,
      creditOutstandingCents: 0,
      linesJson: '[]',
    );
  }
}

void main() {
  void largeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final removeIcon in [Icons.delete_outline, Icons.remove]) {
    testWidgets('last-line removal $removeIcon cannot discount the next sale', (
      tester,
    ) async {
      largeView(tester);
      final cart = CartState(
        items: [CartItem(product: _oldProduct)],
        orderDiscountCents: 1000,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, rebuild) => CartScreen(
                cart: cart,
                user: _user,
                repo: _Repository(),
                onChanged: () => rebuild(() {}),
                onCheckout: () {},
                onHold: () async {},
                onResume: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(removeIcon));
      await tester.tap(find.byIcon(removeIcon));
      await tester.pumpAndSettle();
      expect(cart.items, isEmpty);
      expect(cart.orderDiscountCents, 0);
      await tester.ensureVisible(find.text('Next product').first);
      await tester.tap(find.text('Next product').first);
      await tester.pumpAndSettle();
      expect(cart.items.single.product.id, 'next');
      expect(cart.payableCents(isCredit: false), 500);
      expect(tester.takeException(), isNull);
    });
  }

  for (final credit in [false, true]) {
    testWidgets(
      'invalid ${credit ? 'deposit' : 'cash'} never commits a zero-due sale',
      (tester) async {
        largeView(tester);
        final repo = _Repository();
        final cart = CartState(
          items: [CartItem(product: _oldProduct)],
          orderDiscountCents: 2000,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CheckoutScreen(
              cart: cart,
              user: _user,
              qrStorage: _QrStorage(),
              repo: repo,
              onCancel: () {},
              onPaid: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (credit) {
          await tester.tap(find.text('赊账\nCredit'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButton<Customer?>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Customer  ').last);
          await tester.pumpAndSettle();
        }
        final field = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText ==
                  (credit ? '定金金额 / Deposit amount' : '收取现金 / Cash tendered'),
        );
        for (final invalid in [
          '',
          'NaN',
          'Infinity',
          '1e999',
          '-1',
          '1.234',
          '1,23',
          '999999999999999999999',
        ]) {
          await tester.enterText(field, invalid);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: invalid);
          expect(
            tester.widget<TextField>(field).decoration!.errorText,
            isNotNull,
          );
          await tester.tap(find.text('确认收款 / Confirm'));
          await tester.pumpAndSettle();
          expect(repo.commits, 0, reason: invalid);
          ScaffoldMessenger.of(tester.element(find.byType(CheckoutScreen)))
              .removeCurrentSnackBar();
          await tester.pumpAndSettle();
        }
        await tester.enterText(field, '0.00');
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
        await tester.tap(find.text('确认收款 / Confirm'));
        await tester.pumpAndSettle();
        expect(repo.commits, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'payment parser preserves cents and rejects unsupported input and overflow',
    () {
      expect(tryParsePaymentCents('1,234.56'), 123456);
      expect(tryParsePaymentCents(' 0.29 '), 29);
      expect(tryParsePaymentCents('.5'), 50);
      expect(tryParsePaymentCents('1.'), 100);
      expect(tryParsePaymentCents('90071992547409.91'), 9007199254740991);
      for (final text in [
        '90071992547409.92',
        '90071992547410',
        'NaN',
        'Infinity',
        '1e999',
        '-0.01',
        '1.234',
        '1,2,3',
      ]) {
        expect(tryParsePaymentCents(text), isNull, reason: text);
      }
    },
  );
}
