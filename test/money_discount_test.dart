import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/models/money.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/models/product.dart';

void main() {
  group('roundCheckoutCents', () {
    test('CNKH last-digit rules', () {
      expect(roundCheckoutCents(42), 40);
      expect(roundCheckoutCents(45), 45);
      expect(roundCheckoutCents(67), 70);
      expect(roundCheckoutCents(100), 100);
      expect(roundCheckoutCents(101), 100);
      expect(roundCheckoutCents(106), 110);
    });
  });

  group('discounts', () {
    test('percent half-up and clamp', () {
      expect(percentDiscountCents(1000, 10), 100);
      expect(percentDiscountCents(85, 50), 43); // 42.5 -> 43
      expect(clampDiscountCents(999, 100), 100);
    });

    test('cart payable: credit skips rounding', () {
      final p = Product(
        id: 'x',
        nameZh: 't',
        nameEn: 't',
        sku: 's',
        barcode: 'b',
        priceCents: 67,
      );
      final cart = CartState(items: [CartItem(product: p, qty: 1)]);
      expect(cart.rawPayableCents, 67);
      expect(cart.payableCents(isCredit: false), 70);
      expect(cart.payableCents(isCredit: true), 67);
    });

    test('order discount reduces payable', () {
      final p = Product(
        id: 'x',
        nameZh: 't',
        nameEn: 't',
        sku: 's',
        barcode: 'b',
        priceCents: 1000,
      );
      final cart = CartState(
        items: [CartItem(product: p, qty: 1)],
        orderDiscountCents: 150,
      );
      expect(cart.rawPayableCents, 850);
      expect(cart.payableCents(isCredit: false), 850);
    });

    test('allocateOrderDiscount sums exactly', () {
      final alloc = allocateOrderDiscount([
        ('a', 100),
        ('b', 200),
        ('c', 300),
      ], 100);
      expect(alloc.values.fold(0, (s, v) => s + v), 100);
    });
  });

  test('line totals integer cents', () {
    final washer = Product(
      id: 'p2',
      nameZh: '垫',
      nameEn: 'w',
      sku: 's',
      barcode: 'b',
      priceCents: 15,
    );
    final item = CartItem(product: washer, qty: 3, discountCents: 5);
    expect(item.grossCents, 45);
    expect(item.lineTotalCents, 40);
  });
}
