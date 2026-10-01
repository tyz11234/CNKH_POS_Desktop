import 'dart:convert';
import 'package:sqflite/sqflite.dart';

Future<String?> lanProductAlias(DatabaseExecutor db, String mobileId) async {
  final rows = await db.query('settings', where: 'key=?',
      whereArgs: ['lan_product_alias:$mobileId']);
  return rows.isEmpty ? null : rows.single['value'] as String;
}

/// Existing settings storage keeps aliases and replayable ACK results in the
/// business transaction. Many phones can point to one Desktop product, but a
/// phone's historical ID can never point to a different Desktop entity.
Future<void> rememberLanProductAlias(DatabaseExecutor db, String mobileId,
    String desktopId, String operationId) async {
  final previous = await lanProductAlias(db, mobileId);
  if (previous != null && previous != desktopId) {
    throw StateError('历史商品身份关联冲突，原请求保留');
  }
  await db.insert('settings', {'key': 'lan_product_alias:$mobileId',
    'value': desktopId}, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('settings', {'key': 'lan_mutation_result:$operationId',
    'value': jsonEncode({'entity': 'product', 'local_id': mobileId,
      'remote_id': desktopId})}, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<Map<String, Object?>?> lanMutationIdentityAck(
    DatabaseExecutor db, String operationId) async {
  final rows = await db.query('settings', where: 'key=?',
      whereArgs: ['lan_mutation_result:$operationId']);
  return rows.isEmpty ? null :
      Map<String, Object?>.from(jsonDecode(rows.single['value'] as String) as Map);
}

Future<Map<String, Object?>> resolveLanSaleProduct(DatabaseExecutor db,
    Map<String, Object?> line, {required bool allowDeleted}) async {
  var id = (line['productId'] ?? line['product_id'])?.toString() ?? '';
  if (id.startsWith('pc-')) id = id.substring(3);
  final alias = await lanProductAlias(db, id);
  id = alias ?? id;
  final direct = await db.query('products', where: 'id=?', whereArgs: [id]);
  if (direct.isNotEmpty && !allowDeleted && direct.single['is_deleted'] == 1) {
    throw StateError('原销售商品已删除，不能关联到重建商品；业务保留');
  }
  if (alias != null && direct.isEmpty) {
    throw StateError('历史销售商品关联目标不存在，业务保留');
  }
  Future<Map<String, Object?>?> unique(String column, String value) async {
    if (value.isEmpty) return null;
    final rows = await db.query('products', where: '$column=? AND is_deleted=0',
        whereArgs: [value], limit: 2);
    if (rows.length > 1) throw StateError('销售商品 $column 不唯一，业务保留');
    return rows.isEmpty ? null : rows.single;
  }
  final sku = await unique('sku', '${line['sku'] ?? line['productSku'] ?? ''}'.trim());
  final barcode = await unique('barcode', '${line['barcode'] ?? line['productBarcode'] ?? ''}'.trim());
  if (sku != null && barcode != null && sku['id'] != barcode['id']) {
    throw StateError('销售商品 SKU 与条码指向不同实体，业务保留');
  }
  final natural = barcode ?? sku;
  if (direct.isNotEmpty) {
    if (natural != null && natural['id'] != id) {
      throw StateError('销售商品 ID 与 SKU/条码关联冲突，业务保留');
    }
    return direct.single;
  }
  if (natural == null) throw StateError('销售商品未找到，业务保留');
  return natural;
}
