import 'package:sqflite/sqflite.dart';

/// Additive, idempotent migration. Never alters a POS business table.
Future<void> ensureEInvoiceSchema(DatabaseExecutor db) async {
  await db.execute("""CREATE TABLE IF NOT EXISTS e_invoice_settings (
    id TEXT PRIMARY KEY, tin TEXT NOT NULL DEFAULT '', brn TEXT NOT NULL DEFAULT '',
    client_id TEXT NOT NULL DEFAULT '', client_secret TEXT NOT NULL DEFAULT '',
    environment TEXT NOT NULL DEFAULT 'sandbox', updated_at TEXT NOT NULL DEFAULT '')""");
  await db.execute("""CREATE TABLE IF NOT EXISTS e_invoice_documents (
    id TEXT PRIMARY KEY, sale_id TEXT NOT NULL, invoice_no TEXT NOT NULL,
    submission_uid TEXT NOT NULL DEFAULT '', document_uuid TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending', error_message TEXT NOT NULL DEFAULT '', submitted_at TEXT)""");
  await db.execute("""CREATE TABLE IF NOT EXISTS e_invoice_logs (
    id TEXT PRIMARY KEY, document_id TEXT NOT NULL, action TEXT NOT NULL,
    request_json TEXT NOT NULL DEFAULT '', response_json TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)""");
  Future<void> columns(String table, Map<String, String> additions) async {
    final names = (await db.rawQuery('PRAGMA table_info($table)')).map((r) => r['name']).toSet();
    for (final entry in additions.entries) {
      if (!names.contains(entry.key)) await db.execute('ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}');
    }
  }
  await columns('e_invoice_settings', {
    'profile_json': "TEXT NOT NULL DEFAULT '{}'",
    'credentials_cipher': "TEXT NOT NULL DEFAULT ''",
    'signing_certificate_cipher': "TEXT NOT NULL DEFAULT ''",
    'signing_certificate_name': "TEXT NOT NULL DEFAULT ''",
  });
  await columns('e_invoice_documents', {
    'environment': "TEXT NOT NULL DEFAULT 'sandbox'",
    'payload_json': "TEXT NOT NULL DEFAULT ''",
    'payload_hash': "TEXT NOT NULL DEFAULT ''",
    'buyer_json': "TEXT NOT NULL DEFAULT '{}'",
    'updated_at': "TEXT NOT NULL DEFAULT ''",
    'long_id': "TEXT NOT NULL DEFAULT ''",
    'attempt_no': 'INTEGER NOT NULL DEFAULT 1',
    'parent_document_id': "TEXT NOT NULL DEFAULT ''",
  });
  // Both historical scaffold variants remain readable.
  await columns('e_invoice_logs', {
    'request_json': "TEXT NOT NULL DEFAULT ''", 'response_json': "TEXT NOT NULL DEFAULT ''",
  });
  // Only legacy rows that received the default attempt number need a
  // backfill. Never renumber valid attempts on a later database open.
  final duplicateAttempts = await db.rawQuery('''SELECT sale_id,environment,COUNT(*) AS n
    FROM e_invoice_documents GROUP BY sale_id,environment
    HAVING COUNT(*)>COUNT(DISTINCT attempt_no)''');
  for (final group in duplicateAttempts) {
    final documents = await db.query('e_invoice_documents',
      columns: ['id'], where: 'sale_id=? AND environment=?',
      whereArgs: [group['sale_id'], group['environment']],
      orderBy: 'updated_at,id');
    for (var i = 0; i < documents.length; i++) {
      await db.update('e_invoice_documents', {'attempt_no': i + 1},
        where: 'id=?', whereArgs: [documents[i]['id']]);
    }
  }
  // Legacy scaffolds did not encrypt credentials. Require re-entry rather than retain plaintext.
  await db.execute('PRAGMA secure_delete = ON');
  await db.execute("UPDATE e_invoice_settings SET client_id='', client_secret='' WHERE client_id<>'' OR client_secret<>''");
  await db.execute('CREATE INDEX IF NOT EXISTS idx_einvoice_sale ON e_invoice_documents(sale_id, environment)');
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_einvoice_sale_attempt ON e_invoice_documents(sale_id, environment, attempt_no)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_einvoice_status ON e_invoice_documents(status)');
}
