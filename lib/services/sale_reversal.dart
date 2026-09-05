import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../db/app_database.dart';
import 'sync_store.dart';

Future<void> reverseSale(DatabaseExecutor txn, String id, String note) async {
  final rows = await txn.query('sales', where: 'id=?', whereArgs: [id]);
  if (rows.isEmpty) throw StateError('销售不存在');
  final sale = rows.first;
  if (sale['voided'] == 1) return;
  if ((await txn.query(
    'stock_reversals',
    where: 'sale_id=?',
    whereArgs: [id],
  )).isNotEmpty)
    return;
  final quantities = <String, double>{};
  final moves = await txn.query(
    'stock_moves',
    where: 'reason=? AND notes=?',
    whereArgs: ['sale', sale['receipt_no']],
  );
  if (moves.isNotEmpty) {
    for (final m in moves) {
      final pid = m['product_id'] as String;
      quantities[pid] =
          (quantities[pid] ?? 0) - (m['change'] as num).toDouble();
    }
  } else {
    for (final raw in jsonDecode(sale['lines_json'] as String) as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final remote = (m['productId'] ?? m['product_id']).toString();
      var pid = await mappedLocalId(txn, 'product', remote) ?? remote;
      if ((await txn.query(
            'products',
            where: 'id=?',
            whereArgs: [pid],
          )).isEmpty &&
          pid.startsWith('pc-'))
        pid = pid.substring(3);
      quantities[pid] =
          (quantities[pid] ?? 0) +
          ((m['qty'] ?? m['quantity']) as num).toDouble();
    }
  }
  final now = DateTime.now().toIso8601String();
  for (final e in quantities.entries) {
    if (!e.value.isFinite || e.value <= 0) throw StateError('销售数量无效');
    if (await txn.rawUpdate('UPDATE products SET stock=stock+? WHERE id=?', [
          e.value,
          e.key,
        ]) !=
        1)
      throw StateError('无法恢复库存：商品不存在');
    await txn.insert('stock_moves', {
      'id': AppDatabase.newId(),
      'product_id': e.key,
      'change': e.value,
      'reason': 'sale_void',
      'created_at': now,
      'operator': sale['cashier'],
      'notes': sale['receipt_no'],
    });
  }
  await txn.insert('stock_reversals', {'sale_id': id, 'reversed_at': now});
  await txn.update(
    'sales',
    {'voided': 1, 'void_note': note},
    where: 'id=?',
    whereArgs: [id],
  );
}
