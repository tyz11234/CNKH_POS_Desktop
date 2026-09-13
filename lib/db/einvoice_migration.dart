import 'package:sqflite/sqflite.dart';

/// Database migration helpers for e-Invoice support.
/// Keeps e-Invoice tables isolated from existing POS tables.
Future<void> ensureEInvoiceSchema(Database db) async {
  await db.execute('''
CREATE TABLE IF NOT EXISTS e_invoice_settings (
  id TEXT PRIMARY KEY,
  tin TEXT NOT NULL DEFAULT '',
  brn TEXT NOT NULL DEFAULT '',
  client_id TEXT NOT NULL DEFAULT '',
  client_secret TEXT NOT NULL DEFAULT '',
  environment TEXT NOT NULL DEFAULT 'sandbox',
  updated_at TEXT NOT NULL DEFAULT ''
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS e_invoice_documents (
  id TEXT PRIMARY KEY,
  sale_id TEXT NOT NULL,
  invoice_no TEXT NOT NULL,
  submission_uid TEXT NOT NULL DEFAULT '',
  document_uuid TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  error_message TEXT NOT NULL DEFAULT '',
  submitted_at TEXT
)
''');

  await db.execute('''
CREATE TABLE IF NOT EXISTS e_invoice_logs (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL,
  action TEXT NOT NULL,
  request_body TEXT NOT NULL DEFAULT '',
  response_body TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
)
''');
}
