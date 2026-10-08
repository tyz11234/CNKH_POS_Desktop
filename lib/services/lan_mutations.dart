import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/ocr_purchase_schema.dart';
import 'purchase_reverse_safety.dart';
import 'sale_reversal.dart';
import 'lan_product_identity.dart';
import 'product_identity.dart';

Future<String> _resolvePurchaseProductId(
  DatabaseExecutor txn,
  Map<String, dynamic> line,
  String requestedId,
) async {
  final alias = await lanProductAlias(txn, requestedId);
  requestedId = alias ?? requestedId;
  final historical = await txn.query('products', columns: ['is_deleted'], where: 'id=?', whereArgs: [requestedId]);
  if ((alias != null && historical.isEmpty) || (historical.isNotEmpty && historical.single['is_deleted'] == 1)) {
    throw StateError('原进货商品已删除或移除，历史业务不能关联到重建商品');
  }
  final sku = (line['productSku'] ?? line['sku'])?.toString().trim() ?? '';
  final barcode =
      (line['productBarcode'] ?? line['barcode'])?.toString().trim() ?? '';
  final direct = await txn.query(
    'products',
    columns: const ['id', 'sku', 'barcode'],
    where: 'id=? AND is_deleted=0',
    whereArgs: [requestedId],
    limit: 1,
  );
  Future<String?> uniqueMatch(String column, String value) async {
    if (value.isEmpty) return null;
    final rows = await txn.query(
      'products',
      columns: const ['id'],
      where: '$column=? AND is_deleted=0',
      whereArgs: [value],
      limit: 2,
    );
    if (rows.length > 1) throw StateError('进货商品 $column 不唯一，请核对商品资料');
    return rows.isEmpty ? null : rows.single['id'] as String;
  }

  final skuId = await uniqueMatch('sku', sku);
  final barcodeId = await uniqueMatch('barcode', barcode);
  if (skuId != null && barcodeId != null && skuId != barcodeId) {
    throw StateError('进货商品 SKU 与条码指向不同商品，操作仍保留在手机队列');
  }
  final identityId = barcodeId ?? skuId;
  if (direct.isNotEmpty && identityId != null && identityId != requestedId) {
    throw StateError('进货商品 ID 与 SKU/条码指向不同商品，操作仍保留在手机队列');
  }
  if (identityId != null) return identityId;
  if (direct.isEmpty) throw StateError('进货商品未同步，操作仍保留在手机队列');
  if ((sku.isNotEmpty && direct.single['sku'] != sku) ||
      (barcode.isNotEmpty && direct.single['barcode'] != barcode)) {
    throw StateError('进货商品资料与电脑不一致，请核对 SKU/条码');
  }
  return direct.single['id'] as String;
}

Future<bool> _matchesAppliedPurchase(
  DatabaseExecutor txn,
  Map<String, Object?> existing,
  Map<String, dynamic> payload,
) async {
  bool sameValue(String column, Object? fallback) =>
      '${existing[column] ?? fallback ?? ''}' == '${fallback ?? ''}';
  if (existing['purchase_no'] != 'PO-M-${(payload['id']?.toString() ?? '').replaceAll('-', '')}') return false;
  for (final key in [
    'total_cents', 'purchased_at', 'supplier_name', 'invoice_no', 'invoice_date',
    'notes', 'discount_cents', 'tax_cents', 'delivery_fee_cents', 'other_fee_cents',
    'source', 'draft_id', 'ocr_raw_text',
  ]) {
    final fallback = switch (key) {
      'source' => payload[key] ?? 'mobile',
      'invoice_no' || 'invoice_date' || 'notes' || 'ocr_raw_text' => payload[key] ?? '',
      'discount_cents' || 'tax_cents' || 'delivery_fee_cents' || 'other_fee_cents' => payload[key] ?? 0,
      _ => payload[key],
    };
    if (!sameValue(key, fallback)) return false;
  }

  var expectedSupplierId = payload['supplier_id']?.toString().trim() ?? '';
  if (expectedSupplierId.isNotEmpty) {
    final direct = await txn.query('suppliers', columns: const ['id'],
      where: 'id=? AND is_deleted=0', whereArgs: [expectedSupplierId], limit: 1);
    if (direct.isEmpty) {
      final name = payload['supplier_name']?.toString().trim() ?? '';
      final phone = payload['supplier_phone']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        final matches = await txn.query('suppliers', columns: const ['id'],
          where: phone.isEmpty ? 'name=? AND is_deleted=0' : 'name=? AND phone=? AND is_deleted=0',
          whereArgs: phone.isEmpty ? [name] : [name, phone], limit: 2);
        if (matches.length > 1) return false;
        if (matches.length == 1) expectedSupplierId = matches.single['id'] as String;
      }
    }
  }
  if ('${existing['supplier_id'] ?? ''}' != expectedSupplierId) return false;

  final incoming = payload['lines'];
  if (incoming is! List || incoming.isEmpty) return false;
  final storedRaw = jsonDecode(existing['lines_json']?.toString() ?? '[]');
  if (storedRaw is! List || storedRaw.length != incoming.length) return false;
  for (var i = 0; i < incoming.length; i++) {
    if (incoming[i] is! Map || storedRaw[i] is! Map) return false;
    final line = Map<String, dynamic>.from(incoming[i] as Map);
    final saved = Map<String, dynamic>.from(storedRaw[i] as Map);
    final requestedId = (line['productId'] ?? line['product_id'])?.toString().trim() ?? '';
    final productId = await _resolvePurchaseProductId(txn, line, requestedId);
    final incomingQty = line['qty'] ?? line['quantity'];
    final savedQty = saved['qty'] ?? saved['quantity'];
    final incomingCost = line['unitCostCents'];
    final savedCost = saved['unitCostCents'];
    if (productId != '${saved['productId'] ?? saved['product_id'] ?? ''}' ||
        incomingQty is! num || savedQty is! num ||
        (incomingQty.toDouble() - savedQty.toDouble()).abs() > 0.0000001 ||
        (incomingCost is num ? incomingCost.toInt() : null) !=
            (savedCost is num ? savedCost.toInt() : null)) return false;
  }
  return true;
}

Future<Map<String, Object?>?> _existingCatalogIdentity(
  DatabaseExecutor txn,
  String entity,
  Map<String, Object?> row,
) async {
  Future<Map<String, Object?>?> unique(String table, String where, List<Object?> args) async {
    final rows = await txn.query(table, where: where,
      whereArgs: args, limit: 2);
    if (rows.length > 1) throw StateError('本地新建的 $entity 与电脑资料匹配不唯一，操作仍保留在手机队列');
    return rows.isEmpty ? null : rows.single;
  }

  if (entity == 'product') {
    final sku = row['sku']?.toString().trim() ?? '';
    final barcode = row['barcode']?.toString().trim() ?? '';
    final skuId = sku.isEmpty ? null : await unique('products', 'sku=? AND is_deleted=0', [sku]);
    final barcodeId = barcode.isEmpty ? null : await unique('products', 'barcode=? AND is_deleted=0', [barcode]);
    if (skuId != null && barcodeId != null && skuId['id'] != barcodeId['id']) {
      throw StateError('新商品 SKU 与条码分别匹配不同电脑商品，操作仍保留在手机队列');
    }
    return barcodeId ?? skuId;
  }
  if (entity == 'customer') {
    final name = row['name']?.toString().trim() ?? '';
    final phone = row['phone']?.toString().trim() ?? '';
    return name.isEmpty ? null : await unique('customers', 'name=? AND phone=? AND is_deleted=0', [name, phone]);
  }
  if (entity == 'supplier') {
    final name = row['name']?.toString().trim() ?? '';
    final phone = row['phone']?.toString().trim() ?? '';
    final email = row['email']?.toString().trim() ?? '';
    final emailId = email.isEmpty ? null : await unique('suppliers', 'email=? COLLATE NOCASE AND is_deleted=0', [email]);
    final contactId = name.isEmpty ? null : await unique('suppliers', 'name=? AND phone=? AND is_deleted=0', [name, phone]);
    if (emailId != null && contactId != null && emailId['id'] != contactId['id']) {
      throw StateError('新供应商邮箱与名称/电话分别匹配不同电脑记录，操作仍保留在手机队列');
    }
    return emailId ?? contactId;
  }
  if (entity == 'category') {
    final name = row['name']?.toString().trim() ?? '';
    return name.isEmpty ? null : await unique('categories', 'name=? COLLATE NOCASE AND is_deleted=0', [name]);
  }
  return null;
}

Future<void> applyLanMutation(Database db, Map<String, dynamic> op) async {
  final id = op['id']?.toString() ?? '';
  if (id.isEmpty) throw const FormatException('operation id required');
  final kind = op['kind']?.toString() ?? '';
  final p = Map<String, dynamic>.from(op['payload'] as Map);
  await ensureOcrPurchaseSchema(db);
  await db.transaction((txn) async {
    if ((await txn.query(
      'sync_applied_operations',
      where: 'id=?',
      whereArgs: [id],
    )).isNotEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    if (kind.endsWith('_upsert')) {
      final entity = kind.substring(0, kind.length - 7);
      final table = switch (entity) {
        'product' => 'products',
        'customer' => 'customers',
        'supplier' => 'suppliers',
        'category' => 'categories',
        _ => throw const FormatException('unsupported entity'),
      };
      final allowed = switch (entity) {
        'product' => [
          'name_zh',
          'name_en',
          'sku',
          'barcode',
          'price_cents',
          'cost_cents',
          'stock',
          'unit',
          'category',
          'is_deleted',
          'reorder_level',
        ],
        'supplier' => ['name', 'phone', 'email', 'notes', 'is_deleted'],
        'category' => ['name', 'is_deleted', 'updated_at'],
        _ => ['name', 'phone', 'notes', 'is_deleted'],
      };
      final row = Map<String, Object?>.from(p['row'] as Map);
      var entityId = row['id']?.toString() ?? '';
      if (entityId.isEmpty) throw const FormatException('entity id required');
      final mobileEntityId = op['client_entity_id']?.toString() ?? entityId;
      if (entity == 'product') entityId = await lanProductAlias(txn, entityId) ?? entityId;
      final before = p['before'] is Map
          ? Map<String, Object?>.from(p['before'] as Map)
          : null;
      var existing = await txn.query(
        table,
        where: 'id=?',
        whereArgs: [entityId],
      );
      final identity = existing.isEmpty
          ? await _existingCatalogIdentity(txn, entity, before ?? row)
          : null;
      if (identity != null && before == null && row['is_deleted'] != 1) {
        // Before first pairing Mobile IDs can differ from the Desktop's IDs.
        // Stock/cost in a new matching catalog row are a local baseline, not
        // an inventory delta. Pending purchases/stocktakes apply separately.
        // Other differences require resolution; never silently ACK an edit.
        for (final key in allowed) {
          if (['stock', 'cost_cents', 'updated_at'].contains(key)) continue;
          if (row.containsKey(key) && row[key] != identity[key]) {
            throw StateError('首次配对冲突：$entityId 的 $key 与电脑不同，操作仍保留在手机队列');
          }
        }
        if (entity == 'product') await rememberLanProductAlias(txn, mobileEntityId, identity['id'] as String, id);
        await txn.insert('sync_applied_operations', {
          'id': id,
          'applied_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return;
      }
      if (identity != null && before != null) {
        // A later pre-pair edit still carries the original Mobile ID. Resolve
        // it using its before snapshot, then retain normal conflict checks.
        entityId = identity['id'] as String;
        existing = [identity];
      }
      final changes = <String, Object?>{};
      for (final key in allowed) {
        if (row.containsKey(key) &&
            (before == null || row[key] != before[key])) {
          if (key != 'updated_at' &&
              existing.isNotEmpty &&
              before != null &&
              existing.first[key] != before[key] &&
              existing.first[key] != row[key]) {
            throw StateError('同步冲突：$entityId 的 $key 已在电脑修改');
          }
          changes[key] = row[key];
        }
      }
      if (entity == 'product') {
        if (row['price_cents'] is! int ||
            row['cost_cents'] is! int ||
            (row['price_cents'] as int) < 0 ||
            (row['cost_cents'] as int) < 0 ||
            row['stock'] is! num ||
            !(row['stock'] as num).isFinite) {
          throw const FormatException('invalid product');
        }
        await requireUniqueProductCodes(txn, {
          if (existing.isNotEmpty) ...existing.single,
          ...changes,
          'id': entityId,
        });
      }
      if (entity == 'product') await rememberLanProductAlias(txn, mobileEntityId, entityId, id);
      if (existing.isEmpty) {
        if (before != null) throw StateError('电脑端记录已删除');
        await txn.insert(table, {'id': entityId, ...changes});
      } else if (changes.isNotEmpty) {
        await txn.update(table, changes, where: 'id=?', whereArgs: [entityId]);
        if (entity == 'product' && changes.containsKey('stock') &&
            changes['stock'] != existing.first['stock']) {
          await txn.insert('stock_moves', {
            'id': AppDatabase.newId(),
            'product_id': entityId,
            'change': (changes['stock'] as num) - (existing.first['stock'] as num),
            'reason': 'product_edit',
            'created_at': now,
            'operator': 'mobile-sync',
            'notes': '商品编辑调整库存',
          });
        }
        if (entity == 'category' &&
            (changes.containsKey('name') || changes['is_deleted'] == 1)) {
          await txn.update(
            'products',
            {'category': changes['is_deleted'] == 1 ? '' : row['name']},
            where: 'category=? AND is_deleted=0',
            whereArgs: [existing.first['name']],
          );
        }
      }
    } else if (kind == 'stocktake') {
      final requestedId = p['product_id']?.toString().trim() ?? '';
      final pid = await _resolvePurchaseProductId(txn, p, requestedId);
      final rows = await txn.query(
        'products',
        where: 'id=? AND is_deleted=0',
        whereArgs: [pid],
      );
      if (rows.isEmpty) throw StateError('盘点商品不存在');
      final old = (rows.first['stock'] as num).toDouble();
      final stock = (p['stock'] as num).toDouble();
      if (!stock.isFinite ||
          (old - (p['before_stock'] as num)).abs() > 0.000001) {
        throw StateError('盘点冲突：电脑库存已变动，请核对 $pid');
      }
      await txn.update(
        'products',
        {'stock': stock},
        where: 'id=?',
        whereArgs: [pid],
      );
      await txn.insert('stock_moves', {
        'id': AppDatabase.newId(),
        'product_id': pid,
        'change': stock - old,
        'reason': 'stocktake',
        'created_at': now,
        'operator': p['operator'] ?? 'mobile-sync',
        'notes': p['notes'] ?? '',
      });
    } else if (kind == 'purchase') {
      final lines = (p['lines'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (lines.isEmpty ||
          p['total_cents'] is! int ||
          (p['total_cents'] as int) < 0) {
        throw const FormatException('invalid purchase');
      }
      final pid = p['id']?.toString() ?? '';
      if (pid.isEmpty) throw const FormatException('purchase id required');
      final alreadyApplied = await txn.query(
        'purchases',
        where: 'id=?',
        whereArgs: [pid],
        limit: 1,
      );
      if (alreadyApplied.isNotEmpty) {
        final existing = alreadyApplied.single;
        final same = await _matchesAppliedPurchase(txn, existing, p);
        if (!same) throw StateError('进货操作 ID 已存在但内容不一致，已保留待处理操作');
        // Supports safe repair of pre-v10 unpaired Outbox rows and Lost-ACK
        // replay with a replacement operation ID: never apply stock twice.
        await txn.insert('sync_applied_operations', {
          'id': id,
          'applied_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        return;
      }
      var supplierId = p['supplier_id']?.toString().trim() ?? '';
      final invoiceNo = p['invoice_no']?.toString().trim() ?? '';
      final overrideDuplicate = p['duplicate_override'] == true;
      final overrideReason =
          p['duplicate_override_reason']?.toString().trim() ?? '';
      if (overrideDuplicate && overrideReason.isEmpty) {
        throw const FormatException('duplicate override reason required');
      }
      if (supplierId.isNotEmpty) {
        final direct = await txn.query(
          'suppliers',
          columns: const ['id', 'name', 'phone'],
          where: 'id=? AND is_deleted=0',
          whereArgs: [supplierId],
          limit: 1,
        );
        if (direct.isEmpty) {
          final supplierName = p['supplier_name']?.toString().trim() ?? '';
          final supplierPhone = p['supplier_phone']?.toString().trim() ?? '';
          if (supplierName.isNotEmpty) {
            final matches = await txn.query(
              'suppliers',
              columns: const ['id'],
              where: supplierPhone.isEmpty
                  ? 'name=? AND is_deleted=0'
                  : 'name=? AND phone=? AND is_deleted=0',
              whereArgs: supplierPhone.isEmpty
                  ? [supplierName]
                  : [supplierName, supplierPhone],
              limit: 2,
            );
            if (matches.length > 1) throw StateError('供应商资料不唯一，进货仍保留在手机队列');
            if (matches.length == 1) supplierId = matches.single['id'] as String;
          }
        }
      }
      if (supplierId.isNotEmpty && invoiceNo.isNotEmpty) {
        final duplicate = await txn.rawQuery(
          '''SELECT id, purchase_no FROM purchases
             WHERE supplier_id=?
               AND lower(trim(invoice_no))=lower(trim(?))
               AND COALESCE(reversed,0)=0
               AND id<>?
             LIMIT 1''',
          [supplierId, invoiceNo, pid],
        );
        if (duplicate.isNotEmpty && !overrideDuplicate) {
          throw StateError('该供应商的 Invoice No 已经入库，已阻止跨设备重复入库。');
        }
      }
      final no = 'PO-M-${pid.replaceAll('-', '')}';
      final desktopBeforeCosts = <String, int>{};
      final storedLines = <Map<String, dynamic>>[];
      for (final line in lines) {
        var productId = line['productId']?.toString().trim() ?? '';
        if (productId.isEmpty) throw const FormatException('purchase product required');
        productId = await _resolvePurchaseProductId(txn, line, productId);
        line['productId'] = productId;
        if (!desktopBeforeCosts.containsKey(productId)) {
          final productRows = await txn.query(
            'products',
            columns: const ['cost_cents'],
            where: 'id=? AND is_deleted=0',
            whereArgs: [productId],
            limit: 1,
          );
          if (productRows.isEmpty) throw StateError('进货商品未同步');
          desktopBeforeCosts[productId] =
              (productRows.single['cost_cents'] as num?)?.toInt() ?? 0;
        }
        // Store the Desktop execution-time cost in this transaction. The
        // Mobile beforeCostCents remains for legacy/audit compatibility only.
        storedLines.add({
          ...line,
          'desktopBeforeCostCents': desktopBeforeCosts[productId],
        });
      }
      await txn.insert('purchases', {
        'id': pid,
        'purchase_no': no,
        'supplier_id': supplierId.isEmpty ? null : supplierId,
        'supplier_name': p['supplier_name'],
        'purchased_at': p['purchased_at'],
        'total_cents': p['total_cents'],
        'lines_json': jsonEncode(storedLines),
        'notes': p['notes'] ?? '',
        'invoice_no': p['invoice_no'] ?? '',
        'invoice_date': p['invoice_date'] ?? '',
        'discount_cents': p['discount_cents'] ?? 0,
        'tax_cents': p['tax_cents'] ?? 0,
        'delivery_fee_cents': p['delivery_fee_cents'] ?? 0,
        'other_fee_cents': p['other_fee_cents'] ?? 0,
        'source': p['source'] ?? 'mobile',
        'draft_id': p['draft_id'],
        'image_path': '',
        'ocr_raw_text': p['ocr_raw_text'] ?? '',
        'reversed': 0,
      });
      for (final line in lines) {
        final qty = (line['qty'] as num).toDouble();
        final cost = (line['unitCostCents'] as num?)?.toInt();
        if (!qty.isFinite || qty <= 0 || (cost ?? 0) < 0) {
          throw const FormatException('invalid purchase line');
        }
        if (await txn.rawUpdate(
              'UPDATE products SET stock=stock+?${cost == null ? '' : ',cost_cents=?'} WHERE id=? AND is_deleted=0',
              [qty, if (cost != null) cost, line['productId']],
            ) !=
            1) {
          throw StateError('进货商品未同步');
        }
        await txn.insert('stock_moves', {
          'id': AppDatabase.newId(),
          'product_id': line['productId'],
          'change': qty,
          'reason': 'purchase',
          'created_at': now,
          'operator': p['operator'] ?? 'mobile-sync',
          'notes': no,
        });
      }
      if ((p['source']?.toString() ?? '') == 'ocr') {
        await txn.insert('purchase_audit_log', {
          'id': AppDatabase.newId(),
          'purchase_id': pid,
          'draft_id': p['draft_id'],
          'occurred_at': now,
          'username': p['operator'] ?? 'mobile-sync',
          'action': 'ocr_purchase_synced',
          'field_name': '',
          'original_value': '',
          'final_value': '${p['total_cents']}',
          'details': 'invoice=${p['invoice_no'] ?? ''}',
        });
      }
      if (overrideDuplicate) {
        await txn.insert('purchase_audit_log', {
          'id': AppDatabase.newId(),
          'purchase_id': pid,
          'draft_id': p['draft_id'],
          'occurred_at': now,
          'username': p['operator'] ?? 'mobile-sync',
          'action': 'duplicate_invoice_override_synced',
          'field_name': 'invoice_no',
          'original_value': invoiceNo,
          'final_value': invoiceNo,
          'details': overrideReason,
        });
      }
    } else if (kind == 'purchase_attachment') {
      final attachmentId = p['attachment_id']?.toString().trim() ?? '';
      final purchaseId = p['purchase_id']?.toString().trim() ?? '';
      final expectedHash = p['content_hash']?.toString().toLowerCase().trim() ?? '';
      final encoded = p['base64']?.toString() ?? '';
      if (attachmentId.isEmpty ||
          purchaseId.isEmpty ||
          expectedHash.isEmpty ||
          encoded.isEmpty) {
        throw const FormatException('invalid purchase attachment');
      }
      if ((await txn.query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchaseId],
        limit: 1,
      )).isEmpty) {
        throw StateError('附件对应的进货尚未同步');
      }
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('invalid attachment size');
      }
      final actualHash = _hex((await Sha256().hash(bytes)).bytes);
      if (actualHash != expectedHash) {
        throw StateError('附件校验失败，请重新同步');
      }
      final existingAttachment = await txn.query(
        'purchase_attachments',
        where: 'id=?',
        whereArgs: [attachmentId],
        limit: 1,
      );
      if (existingAttachment.isNotEmpty) {
        if (existingAttachment.first['content_hash']?.toString() != expectedHash) {
          throw StateError('附件 ID 冲突');
        }
      } else {
        await txn.insert('purchase_attachments', {
          'id': attachmentId,
          'purchase_id': purchaseId,
          'kind': p['kind']?.toString() ?? 'invoice_original',
          'filename': p['filename']?.toString() ?? '',
          'content_hash': expectedHash,
          'content': bytes,
          'source': 'mobile',
          'created_at': p['created_at']?.toString() ?? now,
        });
        await txn.insert('purchase_audit_log', {
          'id': AppDatabase.newId(),
          'purchase_id': purchaseId,
          'occurred_at': now,
          'username': p['operator']?.toString() ?? 'mobile-sync',
          'action': 'invoice_attachment_received',
          'field_name': 'attachment',
          'original_value': '',
          'final_value': attachmentId,
          'details': 'hash=$expectedHash; kind=${p['kind'] ?? 'invoice_original'}',
        });
      }
    } else if (kind == 'purchase_reverse') {
      final purchaseId = p['purchase_id']?.toString() ?? '';
      if (purchaseId.isEmpty) {
        throw const FormatException('purchase id required');
      }
      final rows = await txn.query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('撤销目标进货尚未同步');
      await reversePurchaseSafely(
        txn,
        purchase: rows.first,
        operator: p['operator']?.toString() ?? 'mobile-sync',
        reason: p['reason']?.toString() ?? 'reversal',
        notes: p['notes']?.toString() ?? '',
        occurredAt: now,
      );
    } else if (kind == 'sale_void') {
      var rows = await txn.rawQuery(
        'SELECT sales.* FROM sales JOIN lan_sync_mobile_sales m ON sales.id=m.sale_id WHERE m.client_sale_id=?',
        [p['client_sale_id']],
      );
      if (rows.isEmpty) {
        rows = await txn.query(
          'sales',
          where: 'receipt_no=?',
          whereArgs: [p['receipt_no']],
        );
      }
      if (rows.isEmpty) throw StateError('作废目标销售尚未同步');
      await reverseSale(
        txn,
        rows.first['id'] as String,
        p['note']?.toString() ?? 'void',
      );
    } else {
      throw FormatException('unsupported mutation: $kind');
    }
    await txn.insert('sync_applied_operations', {'id': id, 'applied_at': now});
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
