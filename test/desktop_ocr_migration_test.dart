import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Desktop v7 database upgrades to v8 without losing business/outbox data', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-desktop-v7-v8-');
    final path = '${temp.path}/pos.db';
    try {
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, version) async {
            await db.execute('''
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  name_zh TEXT NOT NULL,
  name_en TEXT NOT NULL,
  sku TEXT,
  barcode TEXT,
  price_cents INTEGER NOT NULL,
  cost_cents INTEGER NOT NULL DEFAULT 0,
  stock REAL NOT NULL DEFAULT 0,
  unit TEXT NOT NULL DEFAULT 'pcs',
  category TEXT NOT NULL DEFAULT '',
  is_deleted INTEGER NOT NULL DEFAULT 0,
  image_path TEXT NOT NULL DEFAULT '',
  reorder_level REAL NOT NULL DEFAULT 0
)''');
            await db.execute('''
CREATE TABLE purchases (
  id TEXT PRIMARY KEY,
  purchase_no TEXT NOT NULL,
  supplier_id TEXT,
  supplier_name TEXT NOT NULL,
  purchased_at TEXT NOT NULL,
  total_cents INTEGER NOT NULL,
  lines_json TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT ''
)''');
            await db.execute('''
CREATE TABLE sync_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_error TEXT NOT NULL DEFAULT ''
)''');
          },
        ),
      );
      await legacy.insert('products', {
        'id': 'legacy-product',
        'name_zh': '旧商品',
        'name_en': 'Legacy Product',
        'sku': 'OLD-1',
        'barcode': '9550000000099',
        'price_cents': 500,
        'cost_cents': 300,
        'stock': 7.0,
        'unit': 'pcs',
        'category': 'Legacy',
        'is_deleted': 0,
        'image_path': '',
        'reorder_level': 1.0,
      });
      await legacy.insert('purchases', {
        'id': 'legacy-purchase',
        'purchase_no': 'PO-LEGACY',
        'supplier_id': 'legacy-supplier',
        'supplier_name': '旧供应商',
        'purchased_at': '2026-08-30T12:00:00Z',
        'total_cents': 2100,
        'lines_json': '[]',
        'notes': 'keep me',
      });
      await legacy.insert('sync_outbox', {
        'id': 'legacy-outbox',
        'kind': 'supplier_upsert',
        'entity_id': 'legacy-supplier',
        'payload_json': '{}',
        'created_at': '2026-08-30T12:01:00Z',
        'last_error': 'offline',
      });
      await legacy.close();

      final database = AppDatabase.forTesting(path, seed: false);
      final db = await database.db;
      final version = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));
      expect(version, 8);

      final product = await db.query(
        'products',
        where: 'id=?',
        whereArgs: ['legacy-product'],
      );
      expect(product, hasLength(1));
      expect(product.single['stock'], 7.0);

      final purchase = await db.query(
        'purchases',
        where: 'id=?',
        whereArgs: ['legacy-purchase'],
      );
      expect(purchase, hasLength(1));
      expect(purchase.single['notes'], 'keep me');
      expect(purchase.single['invoice_no'], '');
      expect(purchase.single['reversed'], 0);

      final outbox = await db.query(
        'sync_outbox',
        where: 'id=?',
        whereArgs: ['legacy-outbox'],
      );
      expect(outbox, hasLength(1));
      expect(outbox.single['last_error'], 'offline');

      final attachmentTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_attachments'",
      );
      expect(attachmentTable, hasLength(1));
      final auditTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_audit_log'",
      );
      expect(auditTable, hasLength(1));

      await database.close();
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
