import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/ocr_purchase_schema.dart';
import 'pos_repository.dart';

class PurchaseEditInput {
  const PurchaseEditInput({
    required this.supplierId,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.discountCents,
    required this.taxCents,
    required this.deliveryFeeCents,
    required this.otherFeeCents,
    required this.totalCents,
    required this.notes,
  });

  final String supplierId;
  final String invoiceNo;
  final String invoiceDate;
  final int discountCents;
  final int taxCents;
  final int deliveryFeeCents;
  final int otherFeeCents;
  final int totalCents;
  final String notes;
}

class PurchaseEditService {
  PurchaseEditService(this.repo);

  final PosRepository repo;

  static int? parseMoneyCents(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    text = text
        .replaceAll(RegExp(r'RM', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty || text.contains(RegExp(r'[^0-9,.-]'))) return null;
    if (text.contains('-')) return null;

    final lastDot = text.lastIndexOf('.');
    final lastComma = text.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      final decimal = lastDot > lastComma ? '.' : ',';
      final thousands = decimal == '.' ? ',' : '.';
      final groups = text.split(thousands);
      if (groups.any((part) => part.isEmpty)) return null;
      text = text.replaceAll(thousands, '');
      if (decimal == ',') text = text.replaceAll(',', '.');
    } else if (lastComma >= 0) {
      final parts = text.split(',');
      if (parts.any((part) => part.isEmpty)) return null;
      if (parts.length > 2) {
        final tail = parts.last;
        if (tail.length == 2 &&
            parts.skip(1).take(parts.length - 2).every((p) => p.length == 3)) {
          text = '${parts.take(parts.length - 1).join()}.$tail';
        } else if (parts.skip(1).every((p) => p.length == 3)) {
          text = parts.join();
        } else {
          return null;
        }
      } else {
        final tail = parts.last;
        if (tail.length == 2) {
          text = '${parts.first}.$tail';
        } else if (tail.length == 3) {
          text = parts.join();
        } else {
          return null;
        }
      }
    } else if (lastDot >= 0 && text.indexOf('.') != lastDot) {
      final parts = text.split('.');
      if (parts.any((part) => part.isEmpty)) return null;
      final tail = parts.last;
      if (tail.length == 2 &&
          parts.skip(1).take(parts.length - 2).every((p) => p.length == 3)) {
        text = '${parts.take(parts.length - 1).join()}.$tail';
      } else if (parts.skip(1).every((p) => p.length == 3)) {
        text = parts.join();
      } else {
        return null;
      }
    }

    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0) return null;
    return (value * 100).round();
  }

  Future<void> updateMetadata({
    required String purchaseId,
    required PurchaseEditInput input,
    String operator = 'desktop-admin',
  }) async {
    if (purchaseId.trim().isEmpty) throw ArgumentError('进货 ID 无效');
    if (input.supplierId.trim().isEmpty) throw ArgumentError('请选择供应商');
    for (final cents in <int>[
      input.discountCents,
      input.taxCents,
      input.deliveryFeeCents,
      input.otherFeeCents,
      input.totalCents,
    ]) {
      if (cents < 0) throw ArgumentError('金额不能为负数');
    }

    final db = await repo.database.db;
    await ensureOcrPurchaseSchema(db);
    await db.transaction((txn) async {
      final purchases = await txn.query(
        'purchases',
        where: 'id=?',
        whereArgs: <Object?>[purchaseId],
        limit: 1,
      );
      if (purchases.isEmpty) throw StateError('进货记录不存在');
      final before = purchases.first;
      if ((before['reversed'] as num?)?.toInt() == 1) {
        throw StateError('已撤销的进货记录不能再编辑');
      }

      final suppliers = await txn.query(
        'suppliers',
        where: 'id=? AND is_deleted=0',
        whereArgs: <Object?>[input.supplierId],
        limit: 1,
      );
      if (suppliers.isEmpty) throw StateError('供应商不存在或已删除');
      final supplierName = suppliers.first['name']?.toString() ?? '';

      final invoiceNo = input.invoiceNo.trim();
      if (invoiceNo.isNotEmpty) {
        final duplicate = await txn.rawQuery(
          '''SELECT id FROM purchases
             WHERE supplier_id=?
               AND lower(trim(invoice_no))=lower(trim(?))
               AND COALESCE(reversed,0)=0
               AND id<>?
             LIMIT 1''',
          <Object?>[input.supplierId, invoiceNo, purchaseId],
        );
        if (duplicate.isNotEmpty) {
          throw StateError('该供应商的 Invoice No 已存在，已阻止重复进货资料。');
        }
      }

      final after = <String, Object?>{
        'supplier_id': input.supplierId,
        'supplier_name': supplierName,
        'invoice_no': invoiceNo,
        'invoice_date': input.invoiceDate.trim(),
        'discount_cents': input.discountCents,
        'tax_cents': input.taxCents,
        'delivery_fee_cents': input.deliveryFeeCents,
        'other_fee_cents': input.otherFeeCents,
        'total_cents': input.totalCents,
        'notes': input.notes.trim(),
      };

      final changed = <String, Object?>{};
      for (final entry in after.entries) {
        if (before[entry.key] != entry.value) changed[entry.key] = entry.value;
      }
      if (changed.isEmpty) return;

      await txn.update(
        'purchases',
        changed,
        where: 'id=?',
        whereArgs: <Object?>[purchaseId],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      for (final entry in changed.entries) {
        await txn.insert('purchase_audit_log', <String, Object?>{
          'id': AppDatabase.newId(),
          'purchase_id': purchaseId,
          'draft_id': before['draft_id'],
          'occurred_at': now,
          'username': operator,
          'action': 'purchase_metadata_edited',
          'field_name': entry.key,
          'original_value': '${before[entry.key] ?? ''}',
          'final_value': '${entry.value ?? ''}',
          'details': 'Desktop safe edit; stock and purchase lines unchanged',
        });
      }
    });
  }
}
