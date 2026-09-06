import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/ocr_purchase_schema.dart';
import 'sale_reversal.dart';

Future<void> applyLanMutation(Database db, Map<String, dynamic> op) async {
  final id = op['id']?.toString() ?? '';
  if (id.isEmpty) throw const FormatException('operation id required');
  final kind = op['kind']?.toString() ?? '';
  final p = Map<String, dynamic>.from(op['payload'] as Map);
  await ensureOcrPurchaseSchema(db);
  await db.transaction((txn) async {
    if ((await txn.query(
      'sync_applied_operations',
      where: 'id=?',
      whereArgs: [id],
    )).isNotEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    if (kind.endsWith('_upsert')) {
      final entity = kind.substring(0, kind.length - 7);
      final table = switch (entity) {
        'product' => 'products',
        'customer' => 'customers',
        'supplier' => 'suppliers',
        'category' => 'categories',
        _ => throw const FormatException('unsupported entity'),
      };
      final allowed = switch (entity) {
        'product' => [
          'name_zh',
          'name_en',
          'sku',
          'barcode',
          'price_cents',
          'cost_cents',
          'stock',
          'unit',
          'category',
          'is_deleted',
          'reorder_level',
        ],
        'supplier' => ['name', 'phone', 'email', 'notes', 'is_deleted'],
        'category' => ['name', 'is_deleted', 'updated_at'],
        _ => ['name', 'phone', 'notes', 'is_deleted'],
      };
      final row = Map<String, Object?>.from(p['row'] as Map);
      final entityId = row['id']?.toString() ?? '';
      if (entityId.isEmpty) throw const FormatException('entity id required');
      final before = p['before'] is Map
          ? Map<String, Object?>.from(p['before'] as Map)
          : null;
      final existing = await txn.query(
        table,
        where: 'id=?',
        whereArgs: [entityId],
      );
      final changes = <String, Object?>{};
      for (final key in allowed) {
        if (row.containsKey(key) &&
            (before == null || row[key] != before[key])) {
          if (key != 'updated_at' &&
              existing.isNotEmpty &&
              before != null &&
              existing.first[key] != before[key] &&
              existing.first[key] != row[key]) {
            throw StateError('同步冲突：$entityId 的 $key 已在电脑修改');
          }
          changes[key] = row[key];
        }
      }
      if (entity == 'product') {
        if (row['price_cents'] is! int ||
            row['cost_cents'] is! int ||
            (row['price_cents'] as int) < 0 ||
            (row['cost_cents'] as int) < 0 ||
            row['stock'] is! num ||
            !(row['stock'] as num).isFinite) {
          throw const FormatException('invalid product');
        }
        for (final key in ['barcode', 'sku']) {
          if ((row[key]?.toString() ?? '').isEmpty) continue;
          if ((await txn.query(
            'products',
            where: '$key=? AND id<>? AND is_deleted=0',
            whereArgs: [row[key], entityId],
          )).isNotEmpty) {
            throw StateError('商品 $key 重复，请核对关联');
          }
        }
      }
      if (existing.isEmpty) {
        if (before != null) throw StateError('电脑端记录已删除');
        await txn.insert(table, {'id': entityId, ...changes});
      } else if (changes.isNotEmpty) {
        await txn.update(table, changes, where: 'id=?', whereArgs: [entityId]);
        if (entity == 'category' &&
            (changes.containsKey('name') || changes['is_deleted'] == 1)) {
          await txn.update(
            'products',
            {'category': changes['is_deleted'] == 1 ? '' : row['name']},
            where: 'category=? AND is_deleted=0',
            whereArgs: [existing.first['name']],
          );
        }
      }
    } else if (kind == 'stocktake') {
      final pid = p['product_id'] as String;
      final rows = await txn.query(
        'products',
        where: 'id=? AND is_deleted=0',
        whereArgs: [pid],
      );
      if (rows.isEmpty) throw StateError('盘点商品不存在');
      final old = (rows.first['stock'] as num).toDouble();
      final stock = (p['stock'] as num).toDouble();
      if (!stock.isFinite ||
          (old - (p['before_stock'] as num)).abs() > 0.000001) {
        throw StateError('盘点冲突：电脑库存已变动，请核对 $pid');
      }
      await txn.update(
        'products',
        {'stock': stock},
        where: 'id=?',
        whereArgs: [pid],
      );
      await txn.insert('stock_moves', {
        'id': AppDatabase.newId(),
        'product_id': pid,
        'change': stock - old,
        'reason': 'stocktake',
        'created_at': now,
        'operator': p['operator'] ?? 'mobile-sync',
        'notes': p['notes'] ?? '',
      });
    } else if (kind == 'purchase') {
      final lines = (p['lines'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (lines.isEmpty ||
          p['total_cents'] is! int ||
          (p['total_cents'] as int) < 0) {
        throw const FormatException('invalid purchase');
      }
      final pid = p['id']?.toString() ?? '';
      if (pid.isEmpty) throw const FormatException('purchase id required');
      final no = 'PO-M-${pid.replaceAll('-', '')}';
      await txn.insert('purchases', {
        'id': pid,
        'purchase_no': no,
        'supplier_id': p['supplier_id'],
        'supplier_name': p['supplier_name'],
        'purchased_at': p['purchased_at'],
        'total_cents': p['total_cents'],
        'lines_json': jsonEncode(lines),
        'notes': p['notes'] ?? '',
        'invoice_no': p['invoice_no'] ?? '',
        'invoice_date': p['invoice_date'] ?? '',
        'discount_cents': p['discount_cents'] ?? 0,
        'tax_cents': p['tax_cents'] ?? 0,
        'delivery_fee_cents': p['delivery_fee_cents'] ?? 0,
        'other_fee_cents': p['other_fee_cents'] ?? 0,
        'source': p['source'] ?? 'mobile',
        'draft_id': p['draft_id'],
        'image_path': '',
        'ocr_raw_text': p['ocr_raw_text'] ?? '',
        'reversed': 0,
      });
      for (final line in lines) {
        final qty = (line['qty'] as num).toDouble();
        final cost = (line['unitCostCents'] as num?)?.toInt();
        if (!qty.isFinite || qty <= 0 || (cost ?? 0) < 0) {
          throw const FormatException('invalid purchase line');
        }
        if (await txn.rawUpdate(
              'UPDATE products SET stock=stock+?${cost == null ? '' : ',cost_cents=?'} WHERE id=? AND is_deleted=0',
              [qty, if (cost != null) cost, line['productId']],
            ) !=
            1) {
          throw StateError('进货商品未同步');
        }
        await txn.insert('stock_moves', {
          'id': AppDatabase.newId(),
          'product_id': line['productId'],
          'change': qty,
          'reason': 'purchase',
          'created_at': now,
          'operator': p['operator'] ?? 'mobile-sync',
          'notes': no,
        });
      }
      if ((p['source']?.toString() ?? '') == 'ocr') {
        await txn.insert('purchase_audit_log', {
          'id': AppDatabase.newId(),
          'purchase_id': pid,
          'draft_id': p['draft_id'],
          'occurred_at': now,
          'username': p['operator'] ?? 'mobile-sync',
          'action': 'ocr_purchase_synced',
          'field_name': '',
          'original_value': '',
          'final_value': '${p['total_cents']}',
          'details': 'invoice=${p['invoice_no'] ?? ''}',
        });
      }
    } else if (kind == 'purchase_reverse') {
      final purchaseId = p['purchase_id']?.toString() ?? '';
      if (purchaseId.isEmpty) {
        throw const FormatException('purchase id required');
      }
      final rows = await txn.query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('撤销目标进货尚未同步');
      final purchase = rows.first;
      if (purchase['reversed'] != 1) {
        final lines = (jsonDecode(purchase['lines_json'] as String) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        for (final line in lines) {
          final productId = line['productId']?.toString() ?? '';
          final qty = (line['qty'] as num?)?.toDouble() ?? 0;
          if (productId.isEmpty || !qty.isFinite || qty <= 0) {
            throw const FormatException('invalid reversal line');
          }
          final productRows = await txn.query(
            'products',
            where: 'id=? AND is_deleted=0',
            whereArgs: [productId],
            limit: 1,
          );
          if (productRows.isEmpty) throw StateError('撤销进货商品不存在');
          final currentCost =
              (productRows.first['cost_cents'] as num?)?.toInt() ?? 0;
          final purchaseCost = (line['unitCostCents'] as num?)?.toInt();
          final beforeCost = (line['beforeCostCents'] as num?)?.toInt();
          final update = <String, Object?>{
            'stock': (productRows.first['stock'] as num).toDouble() - qty,
          };
          if (purchaseCost != null &&
              beforeCost != null &&
              currentCost == purchaseCost) {
            update['cost_cents'] = beforeCost;
          }
          await txn.update(
            'products',
            update,
            where: 'id=?',
            whereArgs: [productId],
          );
          await txn.insert('stock_moves', {
            'id': AppDatabase.newId(),
            'product_id': productId,
            'change': -qty,
            'reason': 'purchase_reversal',
            'created_at': now,
            'operator': p['operator'] ?? 'mobile-sync',
            'notes': '${purchase['purchase_no']} · ${p['reason'] ?? 'reversal'}',
          });
        }
        await txn.insert('purchase_reversals', {
          'id': AppDatabase.newId(),
          'purchase_id': purchaseId,
          'reversed_at': now,
          'reversed_by': p['operator'] ?? 'mobile-sync',
          'reason': p['reason'] ?? 'reversal',
          'notes': p['notes'] ?? '',
        });
        await txn.update(
          'purchases',
          {
            'reversed': 1,
            'reversed_at': now,
            'reversed_by': p['operator'] ?? 'mobile-sync',
            'reversal_reason': p['reason'] ?? 'reversal',
            'reversal_notes': p['notes'] ?? '',
          },
          where: 'id=?',
          whereArgs: [purchaseId],
        );
        await txn.insert('purchase_audit_log', {
          'id': AppDatabase.newId(),
          'purchase_id': purchaseId,
          'occurred_at': now,
          'username': p['operator'] ?? 'mobile-sync',
          'action': 'purchase_reversed_from_mobile',
          'field_name': 'status',
          'original_value': 'committed',
          'final_value': 'reversed',
          'details': '${p['reason'] ?? ''}${(p['notes']?.toString() ?? '').isEmpty ? '' : ': ${p['notes']}'}',
        });
      }
    } else if (kind == 'sale_void') {
      var rows = await txn.rawQuery(
        'SELECT sales.* FROM sales JOIN lan_sync_mobile_sales m ON sales.id=m.sale_id WHERE m.client_sale_id=?',
        [p['client_sale_id']],
      );
      if (rows.isEmpty) {
        rows = await txn.query(
          'sales',
          where: 'receipt_no=?',
          whereArgs: [p['receipt_no']],
        );
      }
      if (rows.isEmpty) throw StateError('作废目标销售尚未同步');
      await reverseSale(
        txn,
        rows.first['id'] as String,
        p['note']?.toString() ?? 'void',
      );
    } else {
      throw FormatException('unsupported mutation: $kind');
    }
    await txn.insert('sync_applied_operations', {'id': id, 'applied_at': now});
  });
}
