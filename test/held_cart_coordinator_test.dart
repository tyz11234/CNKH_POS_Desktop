import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/held_cart_coordinator.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase database;
  late PosRepository repo;

  setUp(() async {
    AppDatabase.ensureFfi();
    directory = await Directory.systemTemp.createTemp('cnkh_hold_race_');
    database = AppDatabase.forTesting('${directory.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  const first = Product(
    id: 'p1',
    sku: 'P1',
    barcode: '1',
    nameZh: '商品一',
    nameEn: 'One',
    priceCents: 100,
  );
  const second = Product(
    id: 'p2',
    sku: 'P2',
    barcode: '2',
    nameZh: '商品二',
    nameEn: 'Two',
    priceCents: 200,
  );

  test(
    'writes a click-time snapshot once and keeps later cart edits',
    () async {
      final db = await database.db;
      final entered = Completer<void>();
      final release = Completer<void>();
      final writeLock = db.transaction((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;

      final cart = CartState(items: [CartItem(product: first, qty: 1)]);
      final action = HeldCartCoordinator();
      final pending = action.hold(repo: repo, cart: cart, cashier: 'admin');
      expect(action.isBusy, isTrue);
      expect(
        await action.hold(repo: repo, cart: cart, cashier: 'admin'),
        isNull,
      );

      cart.items.single.qty = 3;
      cart.items.add(CartItem(product: second));
      cart.orderDiscountCents = 25;
      release.complete();
      await writeLock;

      final result = (await pending)!;
      expect(result.cartCleared, isFalse);
      final held = (await repo.listHeld(cashier: 'admin')).single;
      final payload = jsonDecode(held.payloadJson) as Map;
      expect(payload['items'], [
        {'productId': 'p1', 'qty': 1, 'discountCents': 0},
      ]);
      expect(cart.items.map((item) => item.product.id), ['p1', 'p2']);
      expect(cart.items.first.qty, 3);
      expect(cart.orderDiscountCents, 25);
      expect(action.isBusy, isFalse);
    },
  );

  test(
    'clears an unchanged cart after save and preserves it on write failure',
    () async {
      final action = HeldCartCoordinator();
      final unchanged = CartState(
        items: [CartItem(product: first)],
        orderDiscountCents: 10,
      );
      final result = await action.hold(
        repo: repo,
        cart: unchanged,
        cashier: 'admin',
      );
      expect(result!.cartCleared, isTrue);
      expect(unchanged.items, isEmpty);
      expect(unchanged.orderDiscountCents, 0);

      final db = await database.db;
      await db.execute(
        '''CREATE TRIGGER reject_held_order BEFORE INSERT ON held_orders
      BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END''',
      );
      final retained = CartState(items: [CartItem(product: second, qty: 2)]);
      await expectLater(
        action.hold(repo: repo, cart: retained, cashier: 'admin'),
        throwsA(anything),
      );
      expect(retained.items.single.qty, 2);
      expect(action.isBusy, isFalse);
    },
  );
}
