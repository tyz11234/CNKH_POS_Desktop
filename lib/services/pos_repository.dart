import 'dart:convert';
import 'auth_service.dart';
import 'sync_store.dart';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/cart_item.dart';
import '../models/money.dart';
import '../models/product.dart';
import 'profit_math.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String notes;
  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
  });
  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id']! as String,
        name: m['name']! as String,
        phone: (m['phone'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
      );
}

class Supplier {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String notes;
  const Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.notes = '',
  });
  factory Supplier.fromMap(Map<String, Object?> m) => Supplier(
        id: m['id']! as String,
        name: m['name']! as String,
        phone: (m['phone'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
      );
}

class SaleRecord {
  final String id;
  final String receiptNo;
  final String soldAt;
  final String cashier;
  final String paymentMethod;
  final String? depositMethod;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final int subtotalCents;
  final int itemDiscountCents;
  final int orderDiscountCents;
  final int roundingCents;
  final int totalCents;
  final int paidCents;
  final int changeCents;
  final int creditOutstandingCents;
  final String linesJson;
  final int voided;
  final String voidNote;

  SaleRecord({
    required this.id,
    required this.receiptNo,
    required this.soldAt,
    required this.cashier,
    required this.paymentMethod,
    this.depositMethod,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.subtotalCents,
    required this.itemDiscountCents,
    required this.orderDiscountCents,
    required this.roundingCents,
    required this.totalCents,
    required this.paidCents,
    required this.changeCents,
    required this.creditOutstandingCents,
    required this.linesJson,
    this.voided = 0,
    this.voidNote = '',
  });

  factory SaleRecord.fromMap(Map<String, Object?> m) => SaleRecord(
        id: m['id']! as String,
        receiptNo: m['receipt_no']! as String,
        soldAt: m['sold_at']! as String,
        cashier: m['cashier']! as String,
        paymentMethod: m['payment_method']! as String,
        depositMethod: m['deposit_method'] as String?,
        customerId: m['customer_id'] as String?,
        customerName: m['customer_name'] as String?,
        customerPhone: m['customer_phone'] as String?,
        subtotalCents: m['subtotal_cents']! as int,
        itemDiscountCents: m['item_discount_cents']! as int,
        orderDiscountCents: m['order_discount_cents']! as int,
        roundingCents: m['rounding_cents']! as int,
        totalCents: m['total_cents']! as int,
        paidCents: m['paid_cents']! as int,
        changeCents: m['change_cents']! as int,
        creditOutstandingCents: m['credit_outstanding_cents']! as int,
        linesJson: m['lines_json']! as String,
        voided: (m['voided'] as int?) ?? 0,
        voidNote: (m['void_note'] as String?) ?? '',
      );
}

class HeldOrder {
  final String id;
  final String holdNo;
  final String cashier;
  final String heldAt;
  final String payloadJson;
  HeldOrder({
    required this.id,
    required this.holdNo,
    required this.cashier,
    required this.heldAt,
    required this.payloadJson,
  });
  factory HeldOrder.fromMap(Map<String, Object?> m) => HeldOrder(
        id: m['id']! as String,
        holdNo: m['hold_no']! as String,
        cashier: m['cashier']! as String,
        heldAt: m['held_at']! as String,
        payloadJson: m['payload_json']! as String,
      );
}

class AuditEntry {
  final String id;
  final String occurredAt;
  final String username;
  final String role;
  final String action;
  final String module;
  final String? productId;
  final String? productName;
  final String context;
  final String oldValue;
  final String newValue;
  final String reason;
  AuditEntry({
    required this.id,
    required this.occurredAt,
    required this.username,
    required this.role,
    required this.action,
    this.module = 'pos',
    this.productId,
    this.productName,
    this.context = '',
    this.oldValue = '',
    this.newValue = '',
    this.reason = '',
  });
  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
        id: m['id']! as String,
        occurredAt: m['occurred_at']! as String,
        username: m['username']! as String,
        role: (m['role'] as String?) ?? '',
        action: m['action']! as String,
        module: (m['module'] as String?) ?? 'pos',
        productId: m['product_id'] as String?,
        productName: m['product_name'] as String?,
        context: (m['context'] as String?) ?? '',
        oldValue: (m['old_value'] as String?) ?? '',
        newValue: (m['new_value'] as String?) ?? '',
        reason: (m['reason'] as String?) ?? '',
      );
}

class PosRepository {
  PosRepository({AppDatabase? database}) : _db = database ?? AppDatabase.instance;
  final AppDatabase _db;
  late final AuthService auth=AuthService(database:_db);

  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    String? category,
  }) async {
    final d = await _db.db;
    final q = query.trim();
    final cat = (category ?? '').trim();
    final catClause = cat.isEmpty ? '' : ' AND category=?';
    final catArgs = cat.isEmpty ? <Object?>[] : <Object?>[cat];
    if (q.isEmpty) {
      final rows = await d.query(
        'products',
        where: 'is_deleted=0$catClause',
        whereArgs: catArgs.isEmpty ? null : catArgs,
        orderBy: 'category, name_zh',
        limit: limit,
      );
      return rows.map(Product.fromMap).toList();
    }
    final like = '%$q%';
    final rows = await d.query(
      'products',
      where:
          'is_deleted=0 AND (name_zh LIKE ? OR name_en LIKE ? OR sku LIKE ? OR barcode LIKE ? OR category LIKE ?)$catClause',
      whereArgs: [like, like, like, like, like, ...catArgs],
      orderBy: 'name_zh',
      limit: limit,
    );
    // Exact barcode first
    rows.sort((a, b) {
      final ab = (a['barcode'] as String?) ?? '';
      final bb = (b['barcode'] as String?) ?? '';
      if (ab == q) return -1;
      if (bb == q) return 1;
      return 0;
    });
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> findByBarcodeOrSku(String code) async {
    final q = code.trim();
    if (q.isEmpty) return null;
    final d = await _db.db;
    final exact = await d.query(
      'products',
      where: 'is_deleted=0 AND (barcode=? OR sku=?)',
      whereArgs: [q, q],
      limit: 1,
    );
    if (exact.isNotEmpty) return Product.fromMap(exact.first);
    // Case-insensitive sku fallback
    final rows = await d.rawQuery(
      """SELECT * FROM products
         WHERE is_deleted=0 AND (lower(barcode)=lower(?) OR lower(sku)=lower(?))
         LIMIT 1""",
      [q, q],
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<Product?> getProduct(String id) async {
    final d = await _db.db;
    final rows = await d.query('products', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<void> upsertProduct(Product p) async {
    final d = await _db.db;
    await d.insert('products', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteProduct(String id) async {
    final d = await _db.db;
    await d.update('products', {'is_deleted': 1}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> adjustStock({
    required String productId,
    required double newStock,
    required String operator,
    String reason = 'stocktake',
    String notes = '',
  }) async {
    final d = await _db.db;
    await d.transaction((txn) async {
      final rows =
          await txn.query('products', where: 'id=?', whereArgs: [productId]);
      if (rows.isEmpty) throw StateError('product missing');
      final old = (rows.first['stock'] as num).toDouble();
      final delta = newStock - old;
      await txn.update('products', {'stock': newStock},
          where: 'id=?', whereArgs: [productId]);
      await txn.insert('stock_moves', {
        'id': AppDatabase.newId(),
        'product_id': productId,
        'change': delta,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
        'operator': operator,
        'notes': notes,
      });
    });
  }

  Future<List<Customer>> listCustomers() async {
    final d = await _db.db;
    final rows = await d.query('customers',
        where: 'is_deleted=0', orderBy: 'name COLLATE NOCASE');
    return rows.map(Customer.fromMap).toList();
  }

  Future<void> upsertCustomer(Customer c) async {
    final d = await _db.db;
    await d.insert(
      'customers',
      {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'notes': c.notes,
        'is_deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDeleteCustomer(String id) async {
    final d = await _db.db;
    await d.update('customers', {'is_deleted': 1},
        where: 'id=?', whereArgs: [id]);
  }

  Future<List<Supplier>> listSuppliers() async {
    final d = await _db.db;
    final rows = await d.query('suppliers',
        where: 'is_deleted=0', orderBy: 'name COLLATE NOCASE');
    return rows.map(Supplier.fromMap).toList();
  }

  Future<void> upsertSupplier(Supplier s) async {
    final d = await _db.db;
    await d.insert(
      'suppliers',
      {
        'id': s.id,
        'name': s.name,
        'phone': s.phone,
        'email': s.email,
        'notes': s.notes,
        'is_deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDeleteSupplier(String id) async {
    final d = await _db.db;
    await d.update('suppliers', {'is_deleted': 1},
        where: 'id=?', whereArgs: [id]);
  }

  Future<SaleRecord> createSale({
    required CartState cart,
    required String paymentMethod,
    required int paidCents,
    required String cashier,
    String? depositMethod,
    Customer? customer,
    String? customerPhone,
  }) async {
    final method = paymentMethod.toUpperCase();
    final isCredit = method == 'CREDIT';
    if (isCredit && customer == null) {
      throw ArgumentError('Credit requires customer');
    }
    if (isCredit && paidCents > 0 && (depositMethod == null || depositMethod.isEmpty)) {
      throw ArgumentError('Credit deposit requires deposit method');
    }
    final raw = cart.rawPayableCents;
    final total = cart.payableCents(isCredit: isCredit);
    if (!isCredit && paidCents < total) {
      throw ArgumentError('Insufficient payment');
    }
    if (isCredit && (paidCents < 0 || paidCents > raw)) {
      throw ArgumentError('Invalid credit deposit');
    }
    final change = isCredit ? 0 : (paidCents - total);
    final outstanding = isCredit ? (raw - paidCents) : 0;
    final rounding = isCredit ? 0 : checkoutRoundingAdjustment(raw);
    final receipt = await _db.nextReceiptNo();
    final id = AppDatabase.newId();
    final now = DateTime.now().toIso8601String();
    final record = {
      'id': id,
      'receipt_no': receipt,
      'sold_at': now,
      'cashier': cashier,
      'payment_method': method,
      'deposit_method': depositMethod,
      'customer_id': customer?.id,
      'customer_name': customer?.name,
      'customer_phone': (customerPhone ?? customer?.phone)?.trim(),
      'subtotal_cents': cart.subtotalGrossCents,
      'item_discount_cents': cart.itemDiscountsCents,
      'order_discount_cents': cart.orderDiscountApplied,
      'rounding_cents': rounding,
      'total_cents': total,
      'paid_cents': paidCents,
      'change_cents': change,
      'credit_outstanding_cents': outstanding,
      'lines_json': jsonEncode(cart.toLinesJson()),
      'voided': 0,
      'void_note': '',
    };
    final d = await _db.db;
    await d.transaction((txn) async {
      await txn.insert('sales', record);
      for (final item in cart.items) {
        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [item.qty.toDouble(), item.product.id],
        );
        await txn.insert('stock_moves', {
          'id': AppDatabase.newId(),
          'product_id': item.product.id,
          'change': -item.qty.toDouble(),
          'reason': 'sale',
          'created_at': now,
          'operator': cashier,
          'notes': receipt,
        });
      }
    });
    return SaleRecord.fromMap(record);
  }

  Future<List<SaleRecord>> salesToday() async {
    final d = await _db.db;
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await d.query(
      'sales',
      where: "sold_at LIKE ? AND voided=0",
      whereArgs: ['$day%'],
      orderBy: 'sold_at DESC',
    );
    return rows.map(SaleRecord.fromMap).toList();
  }

  Future<List<SaleRecord>> salesAll({int limit = 200}) async {
    final d = await _db.db;
    final rows =
        await d.query('sales', orderBy: 'sold_at DESC', limit: limit);
    return rows.map(SaleRecord.fromMap).toList();
  }

  Future<void> voidSale(String id, String note) async {
    final d = await _db.db;
    await d.update(
      'sales',
      {'voided': 1, 'void_note': note},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<HeldOrder> holdCart({
    required CartState cart,
    required String cashier,
  }) async {
    if (cart.items.isEmpty) throw StateError('empty cart');
    final d = await _db.db;
    final holdNo = await _db.nextHoldNo();
    final id = AppDatabase.newId();
    final payload = {
      'orderDiscountCents': cart.orderDiscountCents,
      'items': [
        for (final i in cart.items)
          {
            'productId': i.product.id,
            'qty': i.qty,
            'discountCents': i.discountCents,
          }
      ],
    };
    final row = {
      'id': id,
      'hold_no': holdNo,
      'cashier': cashier,
      'held_at': DateTime.now().toIso8601String(),
      'payload_json': jsonEncode(payload),
    };
    await d.insert('held_orders', row);
    return HeldOrder.fromMap(row);
  }

  Future<List<HeldOrder>> listHeld({required String cashier}) async {
    final d = await _db.db;
    final rows = await d.query(
      'held_orders',
      where: 'cashier=?',
      whereArgs: [cashier],
      orderBy: 'held_at DESC',
    );
    return rows.map(HeldOrder.fromMap).toList();
  }

  Future<CartState> resumeHeld(HeldOrder held) async {
    final payload = jsonDecode(held.payloadJson) as Map<String, dynamic>;
    final cart = CartState(
      orderDiscountCents: payload['orderDiscountCents'] as int? ?? 0,
    );
    for (final raw in (payload['items'] as List)) {
      final m = raw as Map<String, dynamic>;
      final product = await getProduct(m['productId'] as String);
      if (product == null) continue;
      cart.items.add(CartItem(
        product: product,
        qty: m['qty'] as int,
        discountCents: m['discountCents'] as int? ?? 0,
      ));
    }
    final d = await _db.db;
    await d.delete('held_orders', where: 'id=?', whereArgs: [held.id]);
    return cart;
  }

  Future<List<Map<String, Object?>>> listPurchases() async {
    final d = await _db.db;
    return d.query('purchases', orderBy: 'purchased_at DESC');
  }

  Future<void> createPurchase({
    required String supplierId,
    required String supplierName,
    required List<Map<String, Object?>> lines,
    required int totalCents,
    required String operator,
    String notes = '',
  }) async {
    final d = await _db.db;
    final id = AppDatabase.newId();
    final no = await _db.nextPurchaseNo();
    final now = DateTime.now().toIso8601String();
    await d.transaction((txn) async {
      await txn.insert('purchases', {
        'id': id,
        'purchase_no': no,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'purchased_at': now,
        'total_cents': totalCents,
        'lines_json': jsonEncode(lines),
        'notes': notes,
      });
      for (final line in lines) {
        final pid = line['productId'] as String;
        final qty = (line['qty'] as num).toDouble();
        final unitCost = (line['unitCostCents'] as num?)?.toInt();
        if (unitCost != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ?, cost_cents = ? WHERE id = ?',
            [qty, unitCost, pid],
          );
        } else {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [qty, pid],
          );
        }
        await txn.insert('stock_moves', {
          'id': AppDatabase.newId(),
          'product_id': pid,
          'change': qty,
          'reason': 'purchase',
          'created_at': now,
          'operator': operator,
          'notes': no,
        });
      }
    });
  }

  Future<Map<String, int>> dashboardToday() async {
    final sales = await salesToday();
    var salesTotal = 0;
    var cash = 0;
    var card = 0;
    var duitnow = 0;
    var creditOutstanding = 0;
    for (final s in sales) {
      salesTotal += s.totalCents;
      switch (s.paymentMethod) {
        case 'CASH':
          cash += s.totalCents;
          break;
        case 'CARD':
          card += s.totalCents;
          break;
        case 'DUITNOW_QR':
          duitnow += s.totalCents;
          break;
        case 'CREDIT':
          creditOutstanding += s.creditOutstandingCents;
          if (s.depositMethod == 'CASH') cash += s.paidCents;
          if (s.depositMethod == 'CARD') card += s.paidCents;
          if (s.depositMethod == 'DUITNOW_QR') duitnow += s.paidCents;
          break;
      }
    }
    final all = await salesAll(limit: 5000);
    var creditOpen = 0;
    for (final s in all) {
      if (s.voided == 0) creditOpen += s.creditOutstandingCents;
    }
    return {
      'salesTotal': salesTotal,
      'cash': cash,
      'card': card,
      'duitnow': duitnow,
      'creditOutstandingToday': creditOutstanding,
      'creditOutstandingAll': creditOpen,
      'ticketCount': sales.length,
    };
  }


  /// Revenue / COGS / gross profit for [startDay]..[endDay] (inclusive, YYYY-MM-DD).
  /// COGS uses sale-line `unitCostCents` when present; otherwise sold qty × current
  /// product [cost_cents] (catalog estimate).
  Future<Map<String, Object?>> reportProfit({
    required String startDay,
    required String endDay,
  }) async {
    final d = await _db.db;
    final rows = await d.query(
      'sales',
      where: 'voided=0 AND substr(sold_at,1,10) >= ? AND substr(sold_at,1,10) <= ?',
      whereArgs: [startDay, endDay],
    );
    final products = await d.query(
      'products',
      columns: ['id', 'cost_cents'],
      where: 'is_deleted=0',
    );
    final costById = <String, int>{
      for (final p in products)
        p['id']! as String: (p['cost_cents'] as int?) ?? 0,
    };
    final totals = computeProfitTotals(sales: rows, costByProductId: costById);
    return {
      'revenueCents': totals.revenueCents,
      'cogsCents': totals.cogsCents,
      'grossProfitCents': totals.grossProfitCents,
      'grossMarginPercent': totals.grossMarginPercent,
      'ticketCount': totals.ticketCount,
      'cogsEstimated': totals.cogsEstimated,
    };
  }

  Future<Map<String, int>> reportByPayment({
    required String startDay,
    required String endDay,
  }) async {
    final d = await _db.db;
    final rows = await d.query(
      'sales',
      where: 'voided=0 AND substr(sold_at,1,10) >= ? AND substr(sold_at,1,10) <= ?',
      whereArgs: [startDay, endDay],
    );
    final out = <String, int>{
      'CASH': 0,
      'CARD': 0,
      'DUITNOW_QR': 0,
      'CREDIT': 0,
      'TOTAL': 0,
    };
    for (final m in rows) {
      final s = SaleRecord.fromMap(m);
      out[s.paymentMethod] = (out[s.paymentMethod] ?? 0) + s.totalCents;
      out['TOTAL'] = out['TOTAL']! + s.totalCents;
    }
    return out;
  }

  Future<void> saveDailyClosing({
    required String businessDate,
    required int openingCashCents,
    required int countedCashCents,
    required int systemCashCents,
    required String closedBy,
    String notes = '',
  }) async {
    final d = await _db.db;
    await d.insert(
      'daily_closings',
      {
        'id': AppDatabase.newId(),
        'business_date': businessDate,
        'opening_cash_cents': openingCashCents,
        'counted_cash_cents': countedCashCents,
        'system_cash_cents': systemCashCents,
        'notes': notes,
        'closed_at': DateTime.now().toIso8601String(),
        'closed_by': closedBy,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> listClosings() async {
    final d = await _db.db;
    return d.query('daily_closings', orderBy: 'business_date DESC');
  }

  Future<List<Map<String, Object?>>> listUsers() async {
    final d = await _db.db;
    return d.query('demo_users', orderBy: 'role, username');
  }

  Future<String> getSetting(String key, {String fallback = ''}) async {
    final d = await _db.db;
    final rows =
        await d.query('settings', where: 'key=?', whereArgs: [key]);
    if (rows.isEmpty) return fallback;
    return rows.first['value'] as String? ?? fallback;
  }

  Future<void> setSetting(String key, String value) async {
    final d = await _db.db;
    await d.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearDemoData() => _db.clearDemoTransactionalData();

  /// Wipe all local business data + re-seed. Pair with clearEReceiptCache in UI.
  Future<void> factoryResetLocalData() => _db.factoryResetLocalData();

  Future<void> logAudit({
    required String username,
    required String role,
    required String action,
    String module = 'pos',
    String? productId,
    String? productName,
    String context = '',
    String oldValue = '',
    String newValue = '',
    String reason = '',
  }) async {
    final d = await _db.db;
    await d.insert('audit_logs', {
      'id': AppDatabase.newId(),
      'occurred_at': DateTime.now().toIso8601String(),
      'username': username,
      'role': role,
      'action': action,
      'module': module,
      'product_id': productId,
      'product_name': productName,
      'context': context,
      'old_value': oldValue,
      'new_value': newValue,
      'reason': reason,
    });
  }

  Future<List<AuditEntry>> listAudit({
    String? username,
    bool todayOnly = false,
    int limit = 200,
  }) async {
    final d = await _db.db;
    final where = <String>[];
    final args = <Object?>[];
    if (todayOnly) {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      where.add("occurred_at LIKE ?");
      args.add('$day%');
    }
    if (username != null && username.isNotEmpty) {
      where.add('username=?');
      args.add(username);
    }
    final rows = await d.query(
      'audit_logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(AuditEntry.fromMap).toList();
  }


  Future<List<Category>> listCategories({bool includeDeleted = false}) async {
    final d = await _db.db;
    final rows = await d.query(
      'categories',
      where: includeDeleted ? null : 'is_deleted=0',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<Category> upsertCategory(Category c) async {
    final d = await _db.db;
    final name = c.name.trim();
    if (name.isEmpty) throw StateError('category name required');
    final now = DateTime.now().toIso8601String();
    final existing = await d.query(
      'categories',
      where: 'name=? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    final id = existing.isNotEmpty
        ? (existing.first['id'] as String)
        : (c.id.isEmpty ? AppDatabase.newId() : c.id);
    final cat = Category(id: id, name: name, isDeleted: 0, updatedAt: now);
    await d.insert('categories', cat.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return cat;
  }

  Future<void> renameCategory(String id, String newName) async {
    final d = await _db.db;
    final name = newName.trim();
    if (name.isEmpty) throw StateError('category name required');
    final rows = await d.query('categories', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('category not found');
    final oldName = rows.first['name'] as String;
    final now = DateTime.now().toIso8601String();
    await d.transaction((txn) async {
      await txn.update(
        'categories',
        {'name': name, 'updated_at': now, 'is_deleted': 0},
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.update(
        'products',
        {'category': name},
        where: 'category=? AND is_deleted=0',
        whereArgs: [oldName],
      );
    });
  }

  Future<int> deleteCategory(String id) async {
    final d = await _db.db;
    final rows = await d.query('categories', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('category not found');
    final name = rows.first['name'] as String;
    var cleared = 0;
    await d.transaction((txn) async {
      cleared = await txn.update(
        'products',
        {'category': ''},
        where: 'category=? AND is_deleted=0',
        whereArgs: [name],
      );
      await txn.delete('categories', where: 'id=?', whereArgs: [id]);
    });
    return cleared;
  }


  Future<void> enqueueBarcodePrint({
    required String productId,
    required String barcode,
    required String productName,
    String sku = '',
    int priceCents = 0,
    int copies = 1,
  }) async {
    final d = await _db.db;
    await d.insert('barcode_print_queue', {
      'id': AppDatabase.newId(),
      'product_id': productId,
      'barcode': barcode,
      'product_name': productName,
      'sku': sku,
      'price_cents': priceCents,
      'copies': copies < 1 ? 1 : copies,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'synced_at': null,
    });
  }

  Future<List<Map<String, Object?>>> listBarcodeQueue({String status = 'pending'}) async {
    final d = await _db.db;
    return d.query(
      'barcode_print_queue',
      where: 'status=?',
      whereArgs: [status],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> clearBarcodeQueueItem(String id, {String status = 'done'}) async {
    final d = await _db.db;
    await d.update(
      'barcode_print_queue',
      {'status': status, 'synced_at': DateTime.now().toIso8601String()},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> removeBarcodeQueueItem(String id) async {
    final d = await _db.db;
    await d.delete('barcode_print_queue', where: 'id=?', whereArgs: [id]);
  }

  Future<bool> productImagesEnabled() async {
    final v = await getSetting('product_images_enabled', fallback: '0');
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<bool> btPrinterEnabled() async {
    final v = await getSetting('bt_printer_enabled', fallback: '0');
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<double> lowStockThreshold() async {
    final raw = await getSetting('low_stock_threshold', fallback: '10');
    return double.tryParse(raw) ?? 10;
  }

  Future<List<Product>> listLowStockProducts() async {
    final threshold = await lowStockThreshold();
    final d = await _db.db;
    final rows = await d.rawQuery(
      "SELECT * FROM products WHERE is_deleted=0 AND ((reorder_level > 0 AND stock <= reorder_level) OR (reorder_level <= 0 AND stock <= ?)) ORDER BY stock ASC, name_zh LIMIT 100",
      [threshold],
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Stock policy: `warn` (default) or `block`.
  Future<String> stockPolicy() async =>
      getSetting('stock_policy', fallback: 'warn');

  Future<int> holdTimeoutMinutes() async {
    final raw = await getSetting('hold_timeout_minutes', fallback: '30');
    return int.tryParse(raw) ?? 30;
  }

  Future<List<HeldOrder>> listOverdueHeld({
    required String cashier,
    required int timeoutMinutes,
  }) async {
    final all = await listHeld(cashier: cashier);
    final cutoff = DateTime.now().subtract(Duration(minutes: timeoutMinutes));
    return [
      for (final h in all)
        if (DateTime.tryParse(h.heldAt)?.isBefore(cutoff) == true) h,
    ];
  }
  Future<int> customerOutstandingCents(String customerId) async {
    if (customerId.isEmpty) return 0;
    final d = await _db.db;
    final rows = await d.rawQuery(
      "SELECT COALESCE(SUM(credit_outstanding_cents),0) AS s FROM sales WHERE voided=0 AND customer_id=? AND credit_outstanding_cents>0",
      [customerId],
    );
    return (rows.first['s'] as int?) ?? 0;
  }

}
