import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/screens/checkout_screen.dart';
import 'package:cnkh_pos_desktop/services/e_receipt.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/qr_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;
  const product = Product(
    id: 'phone-test',
    sku: 'PHONE',
    barcode: 'PHONE',
    nameZh: '商品',
    nameEn: 'Product',
    priceCents: 100,
    stock: 5,
  );
  const user = AppUser(username: 'admin', role: AppRole.admin);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('cnkh-checkout-phone-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
    await repo.upsertCustomer(
      const Customer(id: 'customer-a', name: 'Customer A', phone: '0111111111'),
    );
    await repo.upsertCustomer(
      const Customer(id: 'customer-b', name: 'Customer B'),
    );
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() completed, {
    required String description,
  }) async {
    final elapsed = Stopwatch()..start();
    while (!completed()) {
      if (elapsed.elapsed >= const Duration(seconds: 10)) {
        fail('Timed out waiting for $description');
      }
      // SQLite FFI progresses in real time; widget callbacks and endOfFrame
      // must also be pumped before checking whether the operation completed.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets(
    'customer changes clear old autofill while manual phone is saved and shared',
    (tester) async {
      final cart = CartState(items: [CartItem(product: product)]);
      SaleRecord? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckoutScreen(
              cart: cart,
              user: user,
              qrStorage: QrStorage(),
              repo: repo,
              onCancel: () {},
              onPaid: (sale) => saved = sale,
            ),
          ),
        ),
      );
      final customerDropdown = find.byType(DropdownButton<Customer?>);
      await waitUntil(
        tester,
        () =>
            tester
                .widget<DropdownButton<Customer?>>(customerDropdown)
                .items!
                .length ==
            3,
        description: 'the customer directory to load',
      );
      final phoneField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.labelText ?? '').startsWith('手机号 / Phone'),
      );
      Future<void> choose(String label) async {
        await tester.tap(customerDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await choose('Customer A  0111111111');
      expect(
        tester.widget<TextField>(phoneField).controller!.text,
        '0111111111',
      );
      await choose('Customer B  ');
      expect(tester.widget<TextField>(phoneField).controller!.text, isEmpty);

      await choose('Customer A  0111111111');
      await choose('— 无 —');
      expect(tester.widget<TextField>(phoneField).controller!.text, isEmpty);

      await choose('Customer A  0111111111');
      await tester.enterText(phoneField, '0198765432');
      await choose('Customer B  ');
      expect(
        tester.widget<TextField>(phoneField).controller!.text,
        '0198765432',
      );

      await tester.tap(find.text('卡\nCard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认收款 / Confirm'));
      await waitUntil(
        tester,
        () => saved != null,
        description: 'the committed sale and onPaid callback',
      );

      expect(saved, isNotNull);
      expect(saved!.customerId, 'customer-b');
      expect(saved!.customerPhone, '0198765432');
      expect(eReceiptRecipientPhone(saved!), '0198765432');
      final persistedRows = await tester.runAsync(
        () async => (await database.db).query('sales'),
      );
      final persisted = persistedRows!.single;
      expect(persisted['customer_phone'], '0198765432');
    },
  );
}
