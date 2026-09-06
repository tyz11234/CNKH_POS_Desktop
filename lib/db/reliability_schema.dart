import 'package:sqflite/sqflite.dart';
Future<void> ensureReliabilitySchema(DatabaseExecutor db) async {
  for (final sql in <String>[
    "CREATE TABLE IF NOT EXISTS user_credentials (username TEXT PRIMARY KEY COLLATE NOCASE, salt TEXT NOT NULL, pin_hash TEXT NOT NULL, failed_attempts INTEGER NOT NULL DEFAULT 0, locked_until TEXT NOT NULL DEFAULT '')",
    'CREATE TABLE IF NOT EXISTS sync_entity_ids (entity TEXT NOT NULL, remote_id TEXT NOT NULL, local_id TEXT NOT NULL, PRIMARY KEY(entity,remote_id), UNIQUE(entity,local_id))',
    "CREATE TABLE IF NOT EXISTS sync_outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,kind TEXT NOT NULL,entity_id TEXT NOT NULL,payload_json TEXT NOT NULL,created_at TEXT NOT NULL,last_error TEXT NOT NULL DEFAULT '')",
    'CREATE TABLE IF NOT EXISTS sync_applied_operations (id TEXT PRIMARY KEY,applied_at TEXT NOT NULL)',
    'CREATE TABLE IF NOT EXISTS stock_reversals (sale_id TEXT PRIMARY KEY,reversed_at TEXT NOT NULL)',
    'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(sold_at,id)',
    'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id,voided)',
    'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
    'CREATE INDEX IF NOT EXISTS idx_stock_moves_product ON stock_moves(product_id)',
  ]) { await db.execute(sql); }
}
