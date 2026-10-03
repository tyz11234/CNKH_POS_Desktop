import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:ffi';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import 'document_numbers.dart';
import 'einvoice_migration.dart';
import 'ocr_purchase_schema.dart';
import 'reliability_schema.dart';

/// Local-first SQLite for CNKH POS Desktop (local-first).
class AppDatabase {
  static const int schemaVersion = 10;
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  AppDatabase.forTesting(String path, {bool seed = false})
    : _testPath = path,
      _seedData = seed;
  String? _testPath;
  bool _seedData = true;
  Database? _db;
  Future<Database>? _opening;
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }

  Future<Database> get db => _opening ??= _open().catchError((Object e) {
    _opening = null;
    throw e;
  });
  static bool _ffiReady = false;

  static void ensureFfi() {
    if (_ffiReady) return;
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      if (Platform.isLinux) {
        // Desktop distros often ship only libsqlite3.so.N (no unversioned .so).
        open.overrideFor(OperatingSystem.linux, () {
          const candidates = <String>[
            '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
            '/usr/lib/x86_64-linux-gnu/libsqlite3.so',
            '/lib/x86_64-linux-gnu/libsqlite3.so.0',
            'libsqlite3.so.0',
            'libsqlite3.so',
          ];
          Object? last;
          for (final path in candidates) {
            try {
              return DynamicLibrary.open(path);
            } catch (e) {
              last = e;
            }
          }
          throw StateError('Failed to load libsqlite3: $last');
        });
      }
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiReady = true;
  }

  Future<Database> _open() async {
    if (_db != null) return _db!;
    ensureFfi();
    final dir = _testPath == null
        ? await getApplicationDocumentsDirectory()
        : null;
    final path = _testPath ?? p.join(dir!.path, 'cnkh_pos_desktop.db');
    _db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        final count =
            Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM products'),
            ) ??
            0;
        if (_seedData && count == 0) await _seed(db);
      },
    );
    return _db!;
  }

  /// Opens a staged backup using the application's real sqflite upgrade path,
  /// then verifies the schema and queries required by normal POS startup.
  static Future<void> migrateAndValidateBackupFile(String path) async {
    final probe = AppDatabase.forTesting(path, seed: false);
    try {
      final db = await probe.db;
      await validateRestoredDatabase(db);
    } finally {
      await probe.close();
    }
  }

  static Future<void> validateRestoredDatabase(DatabaseExecutor db) async {
    const requiredColumns = <String, Set<String>>{
      'products': {
        'id',
        'name_zh',
        'price_cents',
        'cost_cents',
        'stock',
        'is_deleted',
        'image_path',
      },
      'categories': {'id', 'name', 'is_deleted'},
      'customers': {'id', 'name', 'phone', 'is_deleted'},
      'suppliers': {'id', 'name', 'phone', 'email', 'is_deleted'},
      'sales': {
        'id',
        'receipt_no',
        'customer_id',
        'customer_phone',
        'lines_json',
        'voided',
      },
      'purchases': {
        'id',
        'purchase_no',
        'supplier_id',
        'lines_json',
        'source',
        'reversed',
      },
      'stock_moves': {'id', 'product_id', 'change', 'reason', 'created_at'},
      'held_orders': {'id', 'hold_no', 'cashier', 'held_at', 'payload_json'},
      'daily_closings': {
        'id',
        'business_date',
        'counted_cash_cents',
        'closed_at',
        'closed_by',
      },
      'barcode_print_queue': {
        'id',
        'product_id',
        'barcode',
        'product_name',
        'status',
        'created_at',
      },
      'settings': {'key', 'value'},
      'demo_users': {'id', 'username', 'display_name', 'role', 'is_active'},
      'user_credentials': {'username', 'salt', 'pin_hash', 'failed_attempts'},
      'sync_outbox': {
        'id',
        'kind',
        'entity_id',
        'payload_json',
        'created_at',
        'last_error',
      },
      'sync_entity_ids': {'entity', 'remote_id', 'local_id'},
      'sync_applied_operations': {'id', 'applied_at'},
      'stock_reversals': {'sale_id', 'reversed_at'},
      'audit_logs': {'id', 'occurred_at', 'username', 'action'},
      'purchase_reversals': {
        'id',
        'purchase_id',
        'reversed_at',
        'reversed_by',
        'reason',
      },
      'purchase_audit_log': {
        'id',
        'purchase_id',
        'occurred_at',
        'username',
        'action',
      },
      'purchase_attachments': {
        'id',
        'purchase_id',
        'kind',
        'filename',
        'content_hash',
        'content',
        'created_at',
      },
      'e_invoice_settings': {
        'id',
        'environment',
        'profile_json',
        'credentials_cipher',
        'signing_certificate_cipher',
      },
      'e_invoice_documents': {
        'id',
        'sale_id',
        'invoice_no',
        'submission_uid',
        'document_uuid',
        'status',
        'environment',
        'payload_json',
        'payload_hash',
        'attempt_no',
      },
      'e_invoice_logs': {
        'id',
        'document_id',
        'action',
        'request_json',
        'response_json',
        'created_at',
      },
    };
    for (final entry in requiredColumns.entries) {
      final columns = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final names = columns
          .map((column) => column['name']?.toString() ?? '')
          .toSet();
      final missing = entry.value.difference(names);
      if (missing.isNotEmpty) {
        throw StateError('数据库 ${entry.key} 缺少必要列：${missing.join(', ')}');
      }
    }
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final version = (versionRows.first['user_version'] as num?)?.toInt() ?? 0;
    if (version != schemaVersion) {
      throw StateError('数据库版本 $version 未迁移到当前版本 $schemaVersion');
    }
    for (final sql in const [
      'SELECT id, stock, price_cents, cost_cents FROM products LIMIT 1',
      'SELECT id, customer_id, customer_phone, lines_json FROM sales LIMIT 1',
      'SELECT id, supplier_id, lines_json, reversed FROM purchases LIMIT 1',
      'SELECT id, hold_no, payload_json FROM held_orders LIMIT 1',
      'SELECT id, business_date, counted_cash_cents FROM daily_closings LIMIT 1',
      'SELECT id, product_id, barcode, status FROM barcode_print_queue LIMIT 1',
      'SELECT username, salt, pin_hash FROM user_credentials LIMIT 1',
      'SELECT id, kind, entity_id, payload_json FROM sync_outbox LIMIT 1',
      'SELECT entity, remote_id, local_id FROM sync_entity_ids LIMIT 1',
      'SELECT id, applied_at FROM sync_applied_operations LIMIT 1',
      'SELECT purchase_id, content_hash, content FROM purchase_attachments LIMIT 1',
      'SELECT id, environment, credentials_cipher FROM e_invoice_settings LIMIT 1',
      'SELECT id, status, document_uuid, submission_uid FROM e_invoice_documents LIMIT 1',
      'SELECT id, document_id, action FROM e_invoice_logs LIMIT 1',
      'SELECT key, value FROM settings LIMIT 1',
    ]) {
      await db.rawQuery(sql);
    }
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isEmpty ||
        integrity.first.values.first.toString().toLowerCase() != 'ok') {
      throw StateError('SQLite integrity_check 失败');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
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
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT ''
)''');
    await db.execute('''
CREATE TABLE barcode_print_queue (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  barcode TEXT NOT NULL,
  product_name TEXT NOT NULL,
  sku TEXT NOT NULL DEFAULT '',
  price_cents INTEGER NOT NULL DEFAULT 0,
  copies INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  synced_at TEXT
)''');
    await db.execute('''
CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  is_deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  is_deleted INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE sales (
  id TEXT PRIMARY KEY,
  receipt_no TEXT NOT NULL UNIQUE,
  sold_at TEXT NOT NULL,
  cashier TEXT NOT NULL,
  payment_method TEXT NOT NULL,
  deposit_method TEXT,
  customer_id TEXT,
  customer_name TEXT,
  customer_phone TEXT,
  subtotal_cents INTEGER NOT NULL,
  item_discount_cents INTEGER NOT NULL DEFAULT 0,
  order_discount_cents INTEGER NOT NULL DEFAULT 0,
  rounding_cents INTEGER NOT NULL DEFAULT 0,
  total_cents INTEGER NOT NULL,
  paid_cents INTEGER NOT NULL,
  change_cents INTEGER NOT NULL DEFAULT 0,
  credit_outstanding_cents INTEGER NOT NULL DEFAULT 0,
  lines_json TEXT NOT NULL,
  voided INTEGER NOT NULL DEFAULT 0,
  void_note TEXT NOT NULL DEFAULT '',
  synced_at TEXT
)''');
    await db.execute('''
CREATE TABLE held_orders (
  id TEXT PRIMARY KEY,
  hold_no TEXT NOT NULL,
  cashier TEXT NOT NULL,
  held_at TEXT NOT NULL,
  payload_json TEXT NOT NULL
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
CREATE TABLE stock_moves (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  change REAL NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  operator TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT ''
)''');
    await db.execute('''
CREATE TABLE daily_closings (
  id TEXT PRIMARY KEY,
  business_date TEXT NOT NULL UNIQUE,
  opening_cash_cents INTEGER NOT NULL DEFAULT 0,
  counted_cash_cents INTEGER NOT NULL DEFAULT 0,
  system_cash_cents INTEGER NOT NULL DEFAULT 0,
  notes TEXT NOT NULL DEFAULT '',
  closed_at TEXT NOT NULL,
  closed_by TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE demo_users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1
)''');
    await db.execute('''

CREATE TABLE audit_logs (
  id TEXT PRIMARY KEY,
  occurred_at TEXT NOT NULL,
  username TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT '',
  action TEXT NOT NULL,
  module TEXT NOT NULL DEFAULT 'pos',
  product_id TEXT,
  product_name TEXT,
  context TEXT NOT NULL DEFAULT '',
  old_value TEXT NOT NULL DEFAULT '',
  new_value TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL DEFAULT ''
)''');
    await ensureReliabilitySchema(db);
    await ensureOcrPurchaseSchema(db);
    await ensureEInvoiceSchema(db);
    if (_seedData) await _seed(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 10) await ensureEInvoiceSchema(db);
    if (oldVersion < 7) await ensureReliabilitySchema(db);
    if (oldVersion < 2) {
      final cols = await db.rawQuery('PRAGMA table_info(sales)');
      final names = <String>{
        for (final row in cols) (row['name'] as String?) ?? '',
      };
      if (!names.contains('customer_phone')) {
        await db.execute('ALTER TABLE sales ADD COLUMN customer_phone TEXT');
      }
    }
    if (oldVersion < 3) {
      final cols = await db.rawQuery('PRAGMA table_info(sales)');
      final names = <String>{
        for (final row in cols) (row['name'] as String?) ?? '',
      };
      if (!names.contains('synced_at')) {
        await db.execute('ALTER TABLE sales ADD COLUMN synced_at TEXT');
      }
    }
    if (oldVersion < 4) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  occurred_at TEXT NOT NULL,
  username TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT '',
  action TEXT NOT NULL,
  module TEXT NOT NULL DEFAULT 'pos',
  product_id TEXT,
  product_name TEXT,
  context TEXT NOT NULL DEFAULT '',
  old_value TEXT NOT NULL DEFAULT '',
  new_value TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL DEFAULT ''
)''');
    }
    if (oldVersion < 5) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT ''
)''');
      final cols5 = await db.rawQuery('PRAGMA table_info(products)');
      final names5 = <String>{
        for (final row in cols5) (row['name'] as String?) ?? '',
      };
      if (!names5.contains('image_path')) {
        await db.execute(
          "ALTER TABLE products ADD COLUMN image_path TEXT NOT NULL DEFAULT ''",
        );
      }
      if (!names5.contains('reorder_level')) {
        await db.execute(
          'ALTER TABLE products ADD COLUMN reorder_level REAL NOT NULL DEFAULT 0',
        );
      }
      final cats = await db.rawQuery(
        "SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND trim(category) != '' AND is_deleted=0",
      );
      for (final row in cats) {
        final name = (row['category'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        await db.insert('categories', {
          'id': newId(),
          'name': name,
          'is_deleted': 0,
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    if (oldVersion < 6) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS barcode_print_queue (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  barcode TEXT NOT NULL,
  product_name TEXT NOT NULL,
  sku TEXT NOT NULL DEFAULT '',
  price_cents INTEGER NOT NULL DEFAULT 0,
  copies INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  synced_at TEXT
)''');
    }
    if (oldVersion < 8) {
      await ensureOcrPurchaseSchema(db);
    }
  }

  Future<void> _seed(Database db) async {
    final catalogRaw = await rootBundle.loadString('assets/catalog.json');
    final catalog = (jsonDecode(catalogRaw) as List)
        .cast<Map<String, dynamic>>();
    final batch = db.batch();
    for (final j in catalog) {
      final p = Product.fromJson(j);
      batch.insert(
        'products',
        p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    final custRaw = await rootBundle.loadString('assets/seed_customers.json');
    for (final j
        in (jsonDecode(custRaw) as List).cast<Map<String, dynamic>>()) {
      batch.insert('customers', {
        'id': j['id'],
        'name': j['name'],
        'phone': j['phone'] ?? '',
        'notes': j['notes'] ?? '',
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final supRaw = await rootBundle.loadString('assets/seed_suppliers.json');
    for (final j in (jsonDecode(supRaw) as List).cast<Map<String, dynamic>>()) {
      batch.insert('suppliers', {
        'id': j['id'],
        'name': j['name'],
        'phone': j['phone'] ?? '',
        'email': j['email'] ?? '',
        'notes': j['notes'] ?? '',
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final u in [
      {
        'id': 'u1',
        'username': 'admin',
        'display_name': 'Store Admin',
        'role': 'ADMIN',
      },
      {
        'id': 'u2',
        'username': 'staff',
        'display_name': 'Cashier 1',
        'role': 'STAFF',
      },
      {
        'id': 'u3',
        'username': 'staff2',
        'display_name': 'Cashier 2',
        'role': 'STAFF',
      },
    ]) {
      batch.insert('demo_users', {
        ...u,
        'is_active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    batch.insert('settings', {
      'key': 'store_name',
      'value': '黄金发宝号',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    batch.insert('settings', {
      'key': 'product_images_enabled',
      'value': '0',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    batch.insert('settings', {
      'key': 'bt_printer_enabled',
      'value': '0',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    batch.insert('settings', {
      'key': 'low_stock_threshold',
      'value': '10',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await batch.commit(noResult: true);
  }

  Future<void> clearDemoTransactionalData() async {
    final d = await db;
    await d.transaction((txn) async {
      for (final table in [
        'purchase_attachments',
        'purchase_audit_log',
        'purchase_reversals',
        'sales',
        'held_orders',
        'purchases',
        'stock_moves',
        'daily_closings',
      ]) {
        try {
          await txn.delete(table);
        } catch (_) {}
      }
    });
  }

  /// Full local wipe: all business tables, then re-seed catalog/customers/suppliers
  /// and demo_users / default settings. Keeps app usable after reset.
  Future<void> factoryResetLocalData() async {
    final d = await db;
    await d.transaction((txn) async {
      // Reset business data without reopening unauthenticated admin setup.
      await txn.delete(
        'user_credentials',
        where: 'username<>?',
        whereArgs: ['admin'],
      );
      for (final table in [
        'sync_entity_ids',
        'sync_outbox',
        'sync_applied_operations',
        'stock_reversals',
        'lan_sync_mobile_sales',
        'purchase_attachments',
        'purchase_audit_log',
        'purchase_reversals',
        'sales',
        'held_orders',
        'purchases',
        'stock_moves',
        'daily_closings',
        'audit_logs',
        'barcode_print_queue',
        'products',
        'customers',
        'suppliers',
        'categories',
        'settings',
        'demo_users',
      ]) {
        try {
          if (table == 'settings') {
            await txn.delete(
              table,
              where: "key NOT LIKE 'document_sequence:%'",
            );
          } else {
            await txn.delete(table);
          }
        } catch (_) {}
      }
    });
    await _seed(d);
  }

  Future<String> nextReceiptNo({DatabaseExecutor? executor}) async {
    if (executor == null) {
      final d = await db;
      return d.transaction((txn) => nextReceiptNo(executor: txn));
    }
    final day = DateTime.now()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    final prefix = 'M$day-';
    return _reserveNumber(
      table: 'sales',
      column: 'receipt_no',
      prefix: prefix,
      executor: executor,
    );
  }

  Future<String> nextHoldNo() =>
      _reserveNumber(table: 'held_orders', column: 'hold_no', prefix: 'H-');

  Future<String> nextPurchaseNo({DatabaseExecutor? executor}) => _reserveNumber(
    table: 'purchases',
    column: 'purchase_no',
    prefix: 'PO-',
    executor: executor,
  );

  Future<String> _reserveNumber({
    required String table,
    required String column,
    required String prefix,
    DatabaseExecutor? executor,
  }) async {
    if (executor != null) {
      return reserveDocumentNumber(
        executor,
        table: table,
        column: column,
        prefix: prefix,
      );
    }
    final d = await db;
    return d.transaction(
      (txn) => reserveDocumentNumber(
        txn,
        table: table,
        column: column,
        prefix: prefix,
      ),
    );
  }

  static String newId() => const Uuid().v4();
}
