import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/ocr_purchase_schema.dart';
import 'purchase_reverse_safety.dart';
import 'sale_reversal.dart';

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
      final entityId = row['id']?.toString() ?? '';
      if (entityId.isEmpty) throw const FormatException('entity id required');
      final before = p['before'] is Map
          ? Map<String, Object?>.from(p['before'] as Map)
          : null;
      final existing = await txn.query(
        table,
        where: 'id=?',
        whereArgs: [entityId],
      );
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
        for (final key in ['barcode', 'sku']) {
          if ((row[key]?.toString() ?? '').isEmpty) continue;
          if ((await txn.query(
            'products',
            where: '$key=? AND id<>? AND is_deleted=0',
            whereArgs: [row[key], entityId],
          )).isNotEmpty) {
            throw StateError('商品 $key 重复，请核对关联');
          }
        }
      }
      if (existing.isEmpty) {
        if (before != null) throw StateError('电脑端记录已删除');
        await txn.insert(table, {'id': entityId, ...changes});
      } else if (changes.isNotEmpty) {
        await txn.update(table, changes, where: 'id=?', whereArgs: [entityId]);
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
      final pid = p['product_id'] as String;
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
      final supplierId = p['supplier_id']?.toString().trim() ?? '';
      final invoiceNo = p['invoice_no']?.toString().trim() ?? '';
      final overrideDuplicate = p['duplicate_override'] == true;
      final overrideReason =
          p['duplicate_override_reason']?.toString().trim() ?? '';
      if (overrideDuplicate && overrideReason.isEmpty) {
        throw const FormatException('duplicate override reason required');
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
      await txn.insert('purchases', {
        'id': pid,
        'purchase_no': no,
        'supplier_id': p['supplier_id'],
        'supplier_name': p['supplier_name'],
        'purchased_at': p['purchased_at'],
        'total_cents': p['total_cents'],
        'lines_json': jsonEncode(lines),
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
