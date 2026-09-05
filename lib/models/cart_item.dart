import 'money.dart';
import 'product.dart';

export 'money.dart';
export 'product.dart';

class CartItem {
  final Product product;
  int qty;
  /// Line discount in sen (after qty × unit).
  int discountCents;

  CartItem({
    required this.product,
    this.qty = 1,
    this.discountCents = 0,
  });

  int get grossCents => product.priceCents * qty;

  int get lineDiscountCents => clampDiscountCents(discountCents, grossCents);

  int get lineTotalCents => grossCents - lineDiscountCents;

  Map<String, Object?> toJson() => {
        'productId': product.id,
        'qty': qty,
        'discountCents': discountCents,
      };
}

class CartState {
  final List<CartItem> items;
  int orderDiscountCents;

  CartState({List<CartItem>? items, this.orderDiscountCents = 0})
      : items = items ?? [];

  int get subtotalGrossCents =>
      items.fold(0, (s, e) => s + e.grossCents);

  int get itemDiscountsCents =>
      items.fold(0, (s, e) => s + e.lineDiscountCents);

  int get netBeforeOrderDiscount =>
      items.fold(0, (s, e) => s + e.lineTotalCents);

  int get orderDiscountApplied =>
      clampDiscountCents(orderDiscountCents, netBeforeOrderDiscount);

  int get rawPayableCents =>
      netBeforeOrderDiscount - orderDiscountApplied;

  /// Non-credit payable after CNKH rounding.
  int payableCents({required bool isCredit}) =>
      isCredit ? rawPayableCents : roundCheckoutCents(rawPayableCents);

  int get itemCount => items.fold(0, (s, e) => s + e.qty);

  CartItem? find(String productId) {
    for (final i in items) {
      if (i.product.id == productId) return i;
    }
    return null;
  }

  List<Map<String, Object?>> toLinesJson() => [
        for (final i in items)
          {
            ...i.toJson(),
            'nameZh': i.product.nameZh,
            'nameEn': i.product.nameEn,
            'sku': i.product.sku,
            'barcode':i.product.barcode,
            'unitPriceCents': i.product.priceCents,
            'grossCents': i.grossCents,
            'lineDiscountCents': i.lineDiscountCents,
            'lineTotalCents': i.lineTotalCents,
          }
      ];
}
