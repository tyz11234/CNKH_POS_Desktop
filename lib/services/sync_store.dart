import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../db/app_database.dart';
import 'sync_role.dart';

Future<String> readSetting(
  DatabaseExecutor db,
  String key, {
  String fallback = '',
}) async {
  final rows = await db.query('settings', where: 'key=?', whereArgs: [key]);
  return rows.isEmpty ? fallback : rows.first['value'] as String;
}

Future<String> remoteEntityId(
  DatabaseExecutor db,
  String entity,
  String id,
) async {
  final rows = await db.query(
    'sync_entity_ids',
    where: 'entity=? AND local_id=?',
    whereArgs: [entity, id],
  );
  if (rows.isNotEmpty) return rows.first['remote_id'] as String;
  final prefix = switch (entity) {
    'customer' => 'pc-c-',
    'category' => 'pc-cat-',
    _ => 'pc-',
  };
  return id.startsWith(prefix) ? id.substring(prefix.length) : id;
}

Future<String?> mappedLocalId(
  DatabaseExecutor db,
  String entity,
  Object? id,
) async {
  if (id == null) return null;
  final rows = await db.query(
    'sync_entity_ids',
    where: 'entity=? AND remote_id=?',
    whereArgs: [entity, '$id'],
  );
  return rows.isEmpty ? null : rows.first['local_id'] as String;
}

Future<void> rememberEntityId(
  DatabaseExecutor db,
  String entity,
  Object? remoteId,
  String localId,
) async {
  if (remoteId == null) return;
  final previous = await db.query(
    'sync_entity_ids',
    where: 'entity=? AND local_id=?',
    whereArgs: [entity, localId],
  );
  if (previous.isNotEmpty && previous.first['remote_id'] != '$remoteId')
    throw StateError('商品或客户关联冲突，请核对重复资料');
  await db.insert('sync_entity_ids', {
    'entity': entity,
    'remote_id': '$remoteId',
    'local_id': localId,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> queueMutation(
  DatabaseExecutor db,
  String kind,
  String entityId,
  Map<String, Object?> payload,
) async {
  if (isDesktopHost || (await readSetting(db, 'lan_sync_host')).isEmpty) return;
  await db.insert('sync_outbox', {
    'id': AppDatabase.newId(),
    'kind': kind,
    'entity_id': entityId,
    'payload_json': jsonEncode(payload),
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
}

class AsyncMutex {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
