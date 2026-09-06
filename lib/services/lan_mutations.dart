import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../db/app_database.dart';
import 'sale_reversal.dart';

Future<void> applyLanMutation(Database db, Map<String, dynamic> op) async {
  final id = op['id']?.toString() ?? '';
  if (id.isEmpty) throw const FormatException('operation id required');
  final kind = op['kind']?.toString() ?? '';
  final p = Map<String, dynamic>.from(op['payload'] as Map);
  await db.transaction((txn) async {
    if ((await txn.query(
      'sync_applied_operations',
      where: 'id=?',
      whereArgs: [id],
    )).isNotEmpty)
      return;
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
              existing.first[key] != row[key])
            throw StateError('同步冲突：$entityId 的 $key 已在电脑修改');
          changes[key] = row[key];
        }
      }
      if (entity == 'product') {
        if (row['price_cents'] is! int ||
            row['cost_cents'] is! int ||
            (row['price_cents'] as int) < 0 ||
            (row['cost_cents'] as int) < 0 ||
            row['stock'] is! num ||
            !(row['stock'] as num).isFinite)
          throw const FormatException('invalid product');
        for (final key in ['barcode', 'sku']) {
          if ((row[key]?.toString() ?? '').isEmpty) continue;
          if ((await txn.query(
            'products',
            where: '$key=? AND id<>? AND is_deleted=0',
            whereArgs: [row[key], entityId],
          )).isNotEmpty)
            throw StateError('商品 $key 重复，请核对关联');
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
          (old - (p['before_stock'] as num)).abs() > 0.000001)
        throw StateError('盘点冲突：电脑库存已变动，请核对 $pid');
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
          (p['total_cents'] as int) < 0)
        throw const FormatException('invalid purchase');
      final pid = p['id'] as String;
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
      });
      for (final line in lines) {
        final qty = (line['qty'] as num).toDouble();
        final cost = (line['unitCostCents'] as num?)?.toInt();
        if (!qty.isFinite || qty <= 0 || (cost ?? 0) < 0)
          throw const FormatException('invalid purchase line');
        if (await txn.rawUpdate(
              'UPDATE products SET stock=stock+?${cost == null ? '' : ',cost_cents=?'} WHERE id=? AND is_deleted=0',
              [qty, if (cost != null) cost, line['productId']],
            ) !=
            1)
          throw StateError('进货商品未同步');
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
    } else if (kind == 'sale_void') {
      var rows = await txn.rawQuery(
        'SELECT sales.* FROM sales JOIN lan_sync_mobile_sales m ON sales.id=m.sale_id WHERE m.client_sale_id=?',
        [p['client_sale_id']],
      );
      if (rows.isEmpty)
        rows = await txn.query(
          'sales',
          where: 'receipt_no=?',
          whereArgs: [p['receipt_no']],
        );
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
