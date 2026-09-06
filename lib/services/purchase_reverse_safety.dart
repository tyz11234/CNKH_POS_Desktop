import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

const String kUnsafePurchaseReverseMessage =
    '该进货后的库存已经发生后续变化，无法安全直接撤销，请使用库存调整或人工处理。';

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

  final rawLines = jsonDecode(purchase['lines_json']?.toString() ?? '[]');
  if (rawLines is! List || rawLines.isEmpty) {
    throw const FormatException('invalid reversal lines');
  }

  final plans = <_ReversePlan>[];
  for (final raw in rawLines) {
    if (raw is! Map) throw const FormatException('invalid reversal line');
    final line = Map<String, dynamic>.from(raw);
    final productId = line['productId']?.toString() ?? '';
    final qty = (line['qty'] as num?)?.toDouble() ?? 0;
    if (productId.isEmpty || !qty.isFinite || qty <= 0) {
      throw const FormatException('invalid reversal line');
    }

    final productRows = await txn.query(
      'products',
      where: 'id=? AND is_deleted=0',
      whereArgs: <Object?>[productId],
      limit: 1,
    );
    if (productRows.isEmpty) {
      throw StateError('原进货商品已不存在，无法安全撤销');
    }
    final product = productRows.first;
    final currentStock = (product['stock'] as num?)?.toDouble() ?? double.nan;
    if (!currentStock.isFinite || currentStock + 0.0000001 < qty) {
      throw StateError(kUnsafePurchaseReverseMessage);
    }

    // Locate the stock move created by this exact purchase. We deliberately use
    // the unique purchase number rather than purchased_at because Mobile and
    // Desktop clocks may differ when an offline purchase is synchronized.
    final moves = await txn.query(
      'stock_moves',
      columns: <String>['id', 'reason', 'created_at', 'notes'],
      where: 'product_id=?',
      whereArgs: <Object?>[productId],
      orderBy: 'created_at ASC, rowid ASC',
    );
    final ownMoveIndexes = <int>[];
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (move['reason']?.toString() == 'purchase' &&
          move['notes']?.toString() == purchaseNo) {
        ownMoveIndexes.add(i);
      }
    }
    if (ownMoveIndexes.length != 1) {
      throw StateError(kUnsafePurchaseReverseMessage);
    }
    final ownIndex = ownMoveIndexes.single;
    // Any later business move makes attribution unsafe. If another move shares
    // the same timestamp but follows the purchase row, it is also considered a
    // later change and blocks automatic reversal.
    if (ownIndex != moves.length - 1) {
      throw StateError(kUnsafePurchaseReverseMessage);
    }

    final currentCost = (product['cost_cents'] as num?)?.toInt() ?? 0;
    final purchaseCost = (line['unitCostCents'] as num?)?.toInt();
    final beforeCost = (line['beforeCostCents'] as num?)?.toInt();
    plans.add(
      _ReversePlan(
        productId: productId,
        quantity: qty,
        currentStock: currentStock,
        restoreCost: purchaseCost != null &&
                beforeCost != null &&
                currentCost == purchaseCost
            ? beforeCost
            : null,
      ),
    );
  }

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

class _ReversePlan {
  const _ReversePlan({
    required this.productId,
    required this.quantity,
    required this.currentStock,
    this.restoreCost,
  });

  final String productId;
  final double quantity;
  final double currentStock;
  final int? restoreCost;
}
