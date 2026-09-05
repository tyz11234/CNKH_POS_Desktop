import 'dart:async';

/// In-process change bus used by the Desktop LAN host.
///
/// Repository writes publish here; [LanPairingHost] forwards the changes to
/// connected Mobile clients over WebSocket / poll events. No UI dependency.
class LanSyncEventBus {
  LanSyncEventBus._();

  static final LanSyncEventBus instance = LanSyncEventBus._();

  final StreamController<Map<String, Object?>> _controller =
      StreamController<Map<String, Object?>>.broadcast(sync: true);

  Stream<Map<String, Object?>> get stream => _controller.stream;

  void publish(String type, {Map<String, Object?> data = const {}}) {
    if (_controller.isClosed) return;
    _controller.add(<String, Object?>{
      'type': type,
      ...data,
    });
  }

  void catalog({String reason = 'catalog'}) {
    publish('catalog', data: <String, Object?>{'reason': reason});
  }

  void sale({String? receiptNo, String reason = 'sale'}) {
    publish('sale', data: <String, Object?>{
      'reason': reason,
      if (receiptNo != null && receiptNo.isNotEmpty) 'receipt_no': receiptNo,
    });
  }
}
