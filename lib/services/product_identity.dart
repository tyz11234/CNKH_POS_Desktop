import 'package:sqflite/sqflite.dart';

const _productCodeMatch =
    '(lower(trim(sku))=lower(?) OR lower(trim(barcode))=lower(?))';

/// SKU and barcode share the scanner's identity namespace. Keep the same
/// whitespace and SQLite case-insensitive rules for both saves and scans.
Future<void> requireUniqueProductCodes(
  DatabaseExecutor db,
  Map<String, Object?> product,
) async {
  if (product['is_deleted'] == 1) return;
  final codes = {
    (product['sku']?.toString() ?? '').trim(),
    (product['barcode']?.toString() ?? '').trim(),
  }..remove('');
  if (codes.isEmpty) return;
  final rows = await db.query(
    'products',
    columns: const ['id'],
    where:
        'is_deleted=0 AND id<>? AND '
        '(${codes.map((_) => _productCodeMatch).join(' OR ')})',
    whereArgs: [
      product['id'],
      for (final code in codes) ...[code, code],
    ],
    limit: 1,
  );
  if (rows.isNotEmpty) {
    throw StateError('商品条码或 SKU 已被其他商品使用，请核对后重试');
  }
}

/// Legacy duplicate data stays intact, but must never silently choose the first
/// product. The caller displays this error and leaves the transaction unchanged.
Future<Map<String, Object?>?> findUniqueProductByCode(
  DatabaseExecutor db,
  String code,
) async {
  final value = code.trim();
  if (value.isEmpty) return null;
  final rows = await db.query(
    'products',
    where: 'is_deleted=0 AND $_productCodeMatch',
    whereArgs: [value, value],
    limit: 2,
  );
  if (rows.length > 1) {
    throw StateError('条码或 SKU 对应多个商品，请先在商品管理中修正重复资料');
  }
  return rows.isEmpty ? null : rows.single;
}
