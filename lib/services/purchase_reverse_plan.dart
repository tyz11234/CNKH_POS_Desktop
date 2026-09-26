import 'dart:convert';

import 'package:sqflite/sqflite.dart';

const String kUnsafePurchaseReverseMessage =
    '该进货后的库存已经发生后续变化，无法安全直接撤销，请使用库存调整或人工处理。';

class PurchaseReversePlan {
  const PurchaseReversePlan({
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

/// Validate the whole purchase before any stock is changed. Repeated invoice
/// rows are one inventory change per product, with the first pre-purchase cost
/// and the last applied purchase cost. Ledger insertion order, not wall-clock
/// timestamps, determines whether later inventory activity prevents reversal.
Future<List<PurchaseReversePlan>> planPurchaseReverse(
  DatabaseExecutor txn,
  Map<String, Object?> purchase,
) async {
  final purchaseNo = purchase['purchase_no']?.toString() ?? '';
  final rawLines = jsonDecode(purchase['lines_json']?.toString() ?? '[]');
  if (purchaseNo.isEmpty || rawLines is! List || rawLines.isEmpty) {
    throw const FormatException('invalid reversal lines');
  }
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final raw in rawLines) {
    if (raw is! Map) throw const FormatException('invalid reversal line');
    final line = Map<String, dynamic>.from(raw);
    final id = line['productId']?.toString() ?? '';
    final qty = (line['qty'] as num?)?.toDouble() ?? 0;
    if (id.isEmpty || !qty.isFinite || qty <= 0) {
      throw const FormatException('invalid reversal line');
    }
    (grouped[id] ??= []).add(line);
  }

  final plans = <PurchaseReversePlan>[];
  for (final entry in grouped.entries) {
    final productId = entry.key;
    final lines = entry.value;
    final quantity = lines.fold<double>(0, (sum, line) => sum + (line['qty'] as num));
    final rows = await txn.query('products',
        where: 'id=? AND is_deleted=0', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) throw StateError('原进货商品已不存在，无法安全撤销');
    final stock = (rows.single['stock'] as num).toDouble();
    if (!quantity.isFinite || !stock.isFinite || stock + 0.0000001 < quantity) {
      throw StateError(kUnsafePurchaseReverseMessage);
    }

    final moves = await txn.query('stock_moves',
        where: 'product_id=?', whereArgs: [productId], orderBy: 'rowid ASC');
    var foundPurchase = false;
    var purchasedQuantity = 0.0;
    for (final move in moves) {
      final own = move['reason'] == 'purchase' && move['notes'] == purchaseNo;
      if (own) {
        foundPurchase = true;
        final delta = (move['change'] as num).toDouble();
        if (!delta.isFinite || delta <= 0) {
          throw StateError(kUnsafePurchaseReverseMessage);
        }
        purchasedQuantity += delta;
      } else if (foundPurchase) {
        throw StateError(kUnsafePurchaseReverseMessage);
      }
    }
    if (!foundPurchase || !purchasedQuantity.isFinite ||
        (purchasedQuantity - quantity).abs() > 0.0000001) {
      throw StateError(kUnsafePurchaseReverseMessage);
    }

    final currentCost = (rows.single['cost_cents'] as num?)?.toInt() ?? 0;
    // Older records contain only Mobile's cached beforeCostCents. Do not use
    // that value to overwrite Desktop's actual execution-time cost.
    final beforeCost = (lines.first['desktopBeforeCostCents'] as num?)?.toInt();
    int? purchaseCost;
    for (final line in lines) {
      purchaseCost = (line['unitCostCents'] as num?)?.toInt() ?? purchaseCost;
    }
    plans.add(PurchaseReversePlan(
      productId: productId,
      quantity: quantity,
      currentStock: stock,
      restoreCost: purchaseCost != null && beforeCost != null &&
              currentCost == purchaseCost ? beforeCost : null,
    ));
  }
  return plans;
}
