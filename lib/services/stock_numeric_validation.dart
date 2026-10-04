import 'package:sqflite/sqflite.dart';

/// SQLite can store Infinity, but LAN JSON cannot represent it. Validate the
/// actual arithmetic before a transaction can write stock or ledger values.
double checkedStockDifference(num target, num previous) {
  final delta = target.toDouble() - previous.toDouble();
  if (!target.isFinite || !previous.isFinite || !delta.isFinite) {
    throw ArgumentError('库存调整超出有效数量范围');
  }
  return delta;
}

Future<void> validateStockAddition(
  DatabaseExecutor db,
  String productId,
  double delta,
) async {
  if (!delta.isFinite) throw ArgumentError('库存数量无效');
  final rows = await db.query(
    'products',
    columns: ['stock'],
    where: 'id=?',
    whereArgs: [productId],
    limit: 1,
  );
  if (rows.isEmpty) return; // The existing update retains its missing-row gate.
  final current = (rows.single['stock'] as num).toDouble();
  if (!current.isFinite || !(current + delta).isFinite) {
    throw ArgumentError('库存变动超出有效数量范围');
  }
}
