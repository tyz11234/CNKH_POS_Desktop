import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/screens/checkout_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/qr_storage.dart';

class DelayedCheckoutRepository extends PosRepository {
  DelayedCheckoutRepository(AppDatabase database) : super(database: database);
  final gate = Completer<void>();
  int calls = 0;
  @override
  Future<SaleRecord> createSale({required CartState cart,
    required String paymentMethod, required int paidCents, required String cashier,
    String? depositMethod, Customer? customer, String? customerPhone}) async {
    calls++;
    await gate.future;
    return super.createSale(cart: cart, paymentMethod: paymentMethod,
      paidCents: paidCents, cashier: cashier, depositMethod: depositMethod,
      customer: customer, customerPhone: customerPhone);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase db;
  late DelayedCheckoutRepository repo;
  const product = Product(id: 'checkout-safe', nameZh: 'Safe product',
      nameEn: 'Safe product', sku: 'SAFE', barcode: 'SAFE', priceCents: 1000, stock: 5);
  const user = AppUser(username: 'admin', role: AppRole.admin, displayName: 'Admin');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('checkout-safe-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => temp.path);
    db = AppDatabase.forTesting('${temp.path}/db.sqlite', seed: false);
    repo = DelayedCheckoutRepository(db);
    await repo.upsertProduct(product);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final leaveProgrammatically in [false, true]) {
    testWidgets('slow commit finalizes once; forced teardown=$leaveProgrammatically', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final cart = CartState(items: [CartItem(product: product)]);
      var committed = 0, paid = 0;
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: Scaffold(body: Builder(
        builder: (context) => TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CheckoutScreen(cart: cart, user: user, qrStorage: QrStorage(), repo: repo,
            onCancel: () => nav.currentState!.pop(),
            onCommitted: (_) { committed++; cart.items.clear(); cart.orderDiscountCents = 0; },
            onPaid: (_) { paid++; nav.currentState!.pop(); }))), child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await flush(tester);
      await tester.tap(find.text('确认收款 / Confirm'));
      await flush(tester);
      expect(repo.calls, 1);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close)).onPressed, isNull);
      await nav.currentState!.maybePop();
      await tester.pump();
      expect(find.byType(CheckoutScreen), findsOneWidget);
      if (leaveProgrammatically) await tester.pumpWidget(const SizedBox());
      repo.gate.complete();
      await flush(tester);
      expect(committed, 1);
      expect(cart.items, isEmpty);
      if (!leaveProgrammatically) {
        expect(find.text('找零 / CHANGE'), findsOneWidget);
        await tester.tap(find.text('确认 / Confirm'));
        await flush(tester);
      }
      expect(paid, leaveProgrammatically ? 0 : 1);
      final sales = await tester.runAsync(() => repo.salesAll());
      final current = await tester.runAsync(() => repo.getProduct(product.id));
      expect(sales, hasLength(1));
      expect(sales!.single.totalCents, 1000);
      expect(current!.stock, 4);
      expect(repo.calls, 1);
      expect(tester.takeException(), isNull);
    });
  }
  test('resume protects active cart and cannot consume a held order twice', () async {
    final active = CartState(items: [CartItem(product: product, qty: 2)]);
    final held = await repo.holdCart(cart: CartState(items: [CartItem(product: product)]), cashier: 'admin');
    await expectLater(repo.resumeHeld(held, currentCart: active), throwsStateError);
    expect(active.items.single.qty, 2);
    expect(await repo.listHeld(cashier: 'admin'), hasLength(1));
    active.items.clear();
    final resumed = await repo.resumeHeld(held, currentCart: active);
    expect(resumed.items.single.qty, 1);
    expect(await repo.listHeld(cashier: 'admin'), isEmpty);
    await expectLater(repo.resumeHeld(held, currentCart: active), throwsStateError);
  });
}
