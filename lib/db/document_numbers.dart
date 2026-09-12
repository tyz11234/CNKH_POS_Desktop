import 'dart:math';

import 'package:sqflite/sqflite.dart';

/// Reserve a number inside the caller's transaction. Existing rows provide the
/// migration/import baseline; the saved sequence also covers deleted documents
/// and numbers reserved by another operation that has not inserted its row yet.
Future<String> reserveDocumentNumber(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String prefix,
}) async {
  final key = 'document_sequence:$table:$prefix';
  final saved = await db.query(
    'settings',
    columns: ['value'],
    where: 'key=?',
    whereArgs: [key],
  );
  final lastReserved = saved.isEmpty
      ? 0
      : int.tryParse(saved.single['value']?.toString() ?? '') ?? 0;
  // Table and column are internal constants, never values from user input.
  final lastStored = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COALESCE(MAX(CAST(substr($column, ?) AS INTEGER)), 0) '
        'FROM $table WHERE $column LIKE ?',
        [prefix.length + 1, '$prefix%'],
      )) ??
      0;
  final next = max(lastReserved, lastStored) + 1;
  await db.insert(
    'settings',
    {'key': key, 'value': '$next'},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  return '$prefix${next.toString().padLeft(4, '0')}';
}
