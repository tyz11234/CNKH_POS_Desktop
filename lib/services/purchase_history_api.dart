import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

Future<void> ensurePurchaseHistoryTracking(Database db) async {
  const nowSql = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";
  await db.execute('''
CREATE TRIGGER IF NOT EXISTS lan_sync_purchases_ai AFTER INSERT ON purchases BEGIN
  INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
  VALUES('purchase',NEW.id,NEW.purchase_no,0,$nowSql);
END''');
  await db.execute('''
CREATE TRIGGER IF NOT EXISTS lan_sync_purchases_au AFTER UPDATE ON purchases BEGIN
  INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
  VALUES('purchase',NEW.id,NEW.purchase_no,0,$nowSql);
END''');
  await db.execute('''
CREATE TRIGGER IF NOT EXISTS lan_sync_purchases_ad AFTER DELETE ON purchases BEGIN
  INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
  VALUES('purchase',OLD.id,OLD.purchase_no,1,$nowSql);
END''');
}

Future<int> _latestCursor(Database db) async {
  final rows = await db.rawQuery(
    'SELECT COALESCE(MAX(seq),0) AS seq FROM lan_sync_changes',
  );
  return (rows.first['seq'] as num?)?.toInt() ?? 0;
}

Map<String, Object?> _payload(
  Map<String, Object?> row, {
  String updatedAt = '',
}) {
  Object? lines;
  try {
    lines = jsonDecode(row['lines_json']?.toString() ?? '[]');
  } catch (_) {
    lines = const <Object?>[];
  }
  return <String, Object?>{
    'pc_id': row['id'],
    'purchase_no': row['purchase_no'],
    'supplier_id': row['supplier_id'],
    'supplier_name': row['supplier_name'],
    'purchased_at': row['purchased_at'],
    'total_cents': row['total_cents'],
    'lines': lines,
    'notes': row['notes'],
    'invoice_no': row['invoice_no'],
    'invoice_date': row['invoice_date'],
    'discount_cents': row['discount_cents'],
    'tax_cents': row['tax_cents'],
    'delivery_fee_cents': row['delivery_fee_cents'],
    'other_fee_cents': row['other_fee_cents'],
    'source': row['source'],
    'draft_id': row['draft_id'],
    'ocr_raw_text': row['ocr_raw_text'],
    'reversed': row['reversed'],
    'reversed_at': row['reversed_at'],
    'reversed_by': row['reversed_by'],
    'reversal_reason': row['reversal_reason'],
    'reversal_notes': row['reversal_notes'],
    'is_deleted': 0,
    'updated_at': updatedAt,
  };
}

Future<void> servePurchaseHistory(
  HttpRequest request,
  Database db,
) async {
  await ensurePurchaseHistoryTracking(db);
  final since = int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;
  final cursor = await _latestCursor(db);
  final items = <Map<String, Object?>>[];

  if (since <= 0) {
    final rows = await db.query('purchases', orderBy: 'purchased_at ASC');
    for (final row in rows) {
      items.add(_payload(row));
    }
  } else {
    final changes = await db.query(
      'lan_sync_changes',
      where: 'entity=? AND seq>?',
      whereArgs: <Object?>['purchase', since],
      orderBy: 'seq ASC',
    );
    final latestById = <String, Map<String, Object?>>{};
    for (final row in changes) {
      final id = row['entity_id']?.toString() ?? '';
      if (id.isNotEmpty) latestById[id] = row;
    }
    for (final entry in latestById.entries) {
      final rows = await db.query(
        'purchases',
        where: 'id=?',
        whereArgs: <Object?>[entry.key],
        limit: 1,
      );
      if (rows.isEmpty) {
        items.add(<String, Object?>{
          'pc_id': entry.key,
          'purchase_no': entry.value['entity_name'] ?? '',
          'is_deleted': 1,
          'updated_at': entry.value['changed_at'] ?? '',
          'lines': const <Object?>[],
        });
      } else {
        items.add(
          _payload(
            rows.first,
            updatedAt: entry.value['changed_at']?.toString() ?? '',
          ),
        );
      }
    }
  }

  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(<String, Object?>{
    'ok': true,
    'items': items,
    'cursor': cursor,
  }));
  await request.response.close();
}
