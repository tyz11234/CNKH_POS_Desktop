import '../models/cart_item.dart';
import 'pos_repository.dart';

class HeldCartResult {
  const HeldCartResult({required this.order, required this.cartCleared});

  final HeldOrder order;
  final bool cartCleared;
}

/// Saves the click-time cart snapshot and clears it only if the live cart did
/// not change while SQLite was writing. Concurrent taps share one operation.
class HeldCartCoordinator {
  bool _busy = false;
  bool get isBusy => _busy;

  Future<HeldCartResult?> hold({
    required PosRepository repo,
    required CartState cart,
    required String cashier,
  }) async {
    if (_busy) return null;
    if (cart.items.isEmpty) throw StateError('empty cart');
    _busy = true;
    final before = _fingerprint(cart);
    final snapshot = CartState(
      items: [
        for (final item in cart.items)
          CartItem(
            product: item.product,
            qty: item.qty,
            discountCents: item.discountCents,
          ),
      ],
      orderDiscountCents: cart.orderDiscountCents,
    );
    try {
      final order = await repo.holdCart(cart: snapshot, cashier: cashier);
      final unchanged = _fingerprint(cart) == before;
      if (unchanged) {
        cart.items.clear();
        cart.orderDiscountCents = 0;
      }
      return HeldCartResult(order: order, cartCleared: unchanged);
    } finally {
      _busy = false;
    }
  }

  String _fingerprint(CartState cart) =>
      '${cart.orderDiscountCents}|${cart.toLinesJson()}';
}
