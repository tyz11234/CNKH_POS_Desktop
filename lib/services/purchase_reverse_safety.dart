import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

import 'purchase_reverse_plan.dart';

export 'purchase_reverse_plan.dart' show kUnsafePurchaseReverseMessage;

/// Reverses a committed purchase only when every affected product can be
/// proven safe to roll back. The whole preflight and mutation happen inside the
/// caller's transaction: one unsafe line aborts the entire reversal.
Future<void> reversePurchaseSafely(
  DatabaseExecutor txn, {
  required Map<String, Object?> purchase,
  required String operator,
  required String reason,
  String notes = '',
  String? occurredAt,
}) async {
  if (reason.trim().isEmpty) {
    throw ArgumentError('撤销原因不能为空');
  }
  if (purchase['reversed'] == 1) return;

  final purchaseId = purchase['id']?.toString() ?? '';
  final purchaseNo = purchase['purchase_no']?.toString() ?? '';
  if (purchaseId.isEmpty || purchaseNo.isEmpty) {
    throw const FormatException('invalid purchase');
  }

  final existingReversal = await txn.query(
    'purchase_reversals',
    where: 'purchase_id=?',
    whereArgs: <Object?>[purchaseId],
    limit: 1,
  );
  if (existingReversal.isNotEmpty) return;

  final plans = await planPurchaseReverse(txn, purchase);

  final now = occurredAt ?? DateTime.now().toIso8601String();
  for (final plan in plans) {
    final update = <String, Object?>{
      'stock': plan.currentStock - plan.quantity,
      if (plan.restoreCost != null) 'cost_cents': plan.restoreCost,
    };
    await txn.update(
      'products',
      update,
      where: 'id=?',
      whereArgs: <Object?>[plan.productId],
    );
    await txn.insert('stock_moves', <String, Object?>{
      'id': AppDatabase.newId(),
      'product_id': plan.productId,
      'change': -plan.quantity,
      'reason': 'purchase_reversal',
      'created_at': now,
      'operator': operator,
      'notes': '$purchaseNo · ${reason.trim()}',
    });
  }

  await txn.insert('purchase_reversals', <String, Object?>{
    'id': AppDatabase.newId(),
    'purchase_id': purchaseId,
    'reversed_at': now,
    'reversed_by': operator,
    'reason': reason.trim(),
    'notes': notes.trim(),
  });
  await txn.update(
    'purchases',
    <String, Object?>{
      'reversed': 1,
      'reversed_at': now,
      'reversed_by': operator,
      'reversal_reason': reason.trim(),
      'reversal_notes': notes.trim(),
    },
    where: 'id=?',
    whereArgs: <Object?>[purchaseId],
  );
  await txn.insert('purchase_audit_log', <String, Object?>{
    'id': AppDatabase.newId(),
    'purchase_id': purchaseId,
    'occurred_at': now,
    'username': operator,
    'action': 'purchase_reversed_from_mobile',
    'field_name': 'status',
    'original_value': 'committed',
    'final_value': 'reversed',
    'details': '${reason.trim()}${notes.trim().isEmpty ? '' : ': ${notes.trim()}'}',
  });
}
