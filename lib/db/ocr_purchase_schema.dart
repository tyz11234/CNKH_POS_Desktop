import 'package:sqflite/sqflite.dart';

Future<void> ensureOcrPurchaseSchema(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(purchases)');
  final names = <String>{for (final row in columns) row['name']?.toString() ?? ''};

  Future<void> add(String name, String sql) async {
    if (!names.contains(name)) {
      await db.execute('ALTER TABLE purchases ADD COLUMN $name $sql');
      names.add(name);
    }
  }

  await add('invoice_no', "TEXT NOT NULL DEFAULT ''");
  await add('invoice_date', "TEXT NOT NULL DEFAULT ''");
  await add('discount_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('tax_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('delivery_fee_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('other_fee_cents', 'INTEGER NOT NULL DEFAULT 0');
  await add('source', "TEXT NOT NULL DEFAULT 'manual'");
  await add('draft_id', 'TEXT');
  await add('image_path', "TEXT NOT NULL DEFAULT ''");
  await add('ocr_raw_text', "TEXT NOT NULL DEFAULT ''");
  await add('reversed', 'INTEGER NOT NULL DEFAULT 0');
  await add('reversed_at', 'TEXT');
  await add('reversed_by', 'TEXT');
  await add('reversal_reason', "TEXT NOT NULL DEFAULT ''");
  await add('reversal_notes', "TEXT NOT NULL DEFAULT ''");

  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_reversals (
  id TEXT PRIMARY KEY,
  purchase_id TEXT NOT NULL UNIQUE,
  reversed_at TEXT NOT NULL,
  reversed_by TEXT NOT NULL,
  reason TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT ''
)''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS purchase_audit_log (
  id TEXT PRIMARY KEY,
  purchase_id TEXT,
  draft_id TEXT,
  occurred_at TEXT NOT NULL,
  username TEXT NOT NULL,
  action TEXT NOT NULL,
  field_name TEXT NOT NULL DEFAULT '',
  original_value TEXT NOT NULL DEFAULT '',
  final_value TEXT NOT NULL DEFAULT '',
  details TEXT NOT NULL DEFAULT ''
)''');
}
