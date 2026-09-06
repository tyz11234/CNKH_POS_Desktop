import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/purchase_edit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money parser accepts thousands but rejects malformed manual input', () {
    expect(PurchaseEditService.parseMoneyCents('RM 1,234.56'), 123456);
    expect(PurchaseEditService.parseMoneyCents('1.234,56'), 123456);
    expect(PurchaseEditService.parseMoneyCents('12.50'), 1250);
    expect(PurchaseEditService.parseMoneyCents('12..50'), isNull);
    expect(PurchaseEditService.parseMoneyCents('-1.00'), isNull);
  });

  test('safe edit changes metadata and audit without changing lines or stock', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-purchase-edit-');
    final database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);
    try {
      await repo.upsertSupplier(
        const Supplier(id: 's1', name: 'Supplier One'),
      );
      await repo.upsertSupplier(
        const Supplier(id: 's2', name: 'Supplier Two'),
      );
      await repo.upsertProduct(
        const Product(
          id: 'p1',
          nameZh: '商品',
          nameEn: 'Product',
          sku: 'P1',
          barcode: '9550000000011',
          priceCents: 500,
          costCents: 200,
          stock: 10,
        ),
      );
      await repo.createPurchase(
        supplierId: 's1',
        supplierName: 'Supplier One',
        lines: const <Map<String, Object?>>[
          <String, Object?>{
            'productId': 'p1',
            'name': '商品',
            'qty': 2.0,
            'unitCostCents': 250,
            'subtotalCents': 500,
          },
        ],
        totalCents: 500,
        operator: 'admin',
      );

      final db = await database.db;
      final purchase = (await db.query('purchases')).single;
      final id = purchase['id'] as String;
      final oldLines = purchase['lines_json'];
      final stockBefore = (await repo.getProduct('p1'))!.stock;

      await PurchaseEditService(repo).updateMetadata(
        purchaseId: id,
        operator: 'admin',
        input: const PurchaseEditInput(
          supplierId: 's2',
          invoiceNo: 'INV-100',
          invoiceDate: '2026-09-06',
          discountCents: 10,
          taxCents: 30,
          deliveryFeeCents: 20,
          otherFeeCents: 5,
          totalCents: 545,
          notes: 'corrected metadata',
        ),
      );

      final edited = (await db.query(
        'purchases',
        where: 'id=?',
        whereArgs: <Object?>[id],
      )).single;
      expect(edited['supplier_id'], 's2');
      expect(edited['supplier_name'], 'Supplier Two');
      expect(edited['invoice_no'], 'INV-100');
      expect(edited['tax_cents'], 30);
      expect(edited['lines_json'], oldLines);
      expect((await repo.getProduct('p1'))!.stock, stockBefore);

      final moves = await db.query('stock_moves', where: 'product_id=?', whereArgs: ['p1']);
      expect(moves, hasLength(1));
      final audit = await db.query(
        'purchase_audit_log',
        where: "purchase_id=? AND action='purchase_metadata_edited'",
        whereArgs: <Object?>[id],
      );
      expect(audit, isNotEmpty);
      expect(audit.any((row) => row['field_name'] == 'supplier_id'), isTrue);
      expect(audit.any((row) => row['field_name'] == 'invoice_no'), isTrue);
    } finally {
      await database.close();
      await dir.delete(recursive: true);
    }
  });

  test('duplicate supplier invoice and reversed purchase edits are blocked', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-purchase-edit-guard-');
    final database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);
    try {
      await repo.upsertSupplier(const Supplier(id: 's1', name: 'Supplier One'));
      final db = await database.db;
      final now = DateTime.now().toIso8601String();
      await db.insert('purchases', <String, Object?>{
        'id': 'a',
        'purchase_no': 'PO-A',
        'supplier_id': 's1',
        'supplier_name': 'Supplier One',
        'purchased_at': now,
        'total_cents': 100,
        'lines_json': '[]',
        'notes': '',
        'invoice_no': 'DUP-1',
        'reversed': 0,
      });
      await db.insert('purchases', <String, Object?>{
        'id': 'b',
        'purchase_no': 'PO-B',
        'supplier_id': 's1',
        'supplier_name': 'Supplier One',
        'purchased_at': now,
        'total_cents': 100,
        'lines_json': '[]',
        'notes': '',
        'invoice_no': '',
        'reversed': 0,
      });

      const duplicateInput = PurchaseEditInput(
        supplierId: 's1',
        invoiceNo: 'DUP-1',
        invoiceDate: '',
        discountCents: 0,
        taxCents: 0,
        deliveryFeeCents: 0,
        otherFeeCents: 0,
        totalCents: 100,
        notes: '',
      );
      await expectLater(
        PurchaseEditService(repo).updateMetadata(
          purchaseId: 'b',
          input: duplicateInput,
        ),
        throwsA(isA<StateError>()),
      );

      await db.update('purchases', {'reversed': 1}, where: 'id=?', whereArgs: ['b']);
      await expectLater(
        PurchaseEditService(repo).updateMetadata(
          purchaseId: 'b',
          input: const PurchaseEditInput(
            supplierId: 's1',
            invoiceNo: 'OTHER',
            invoiceDate: '',
            discountCents: 0,
            taxCents: 0,
            deliveryFeeCents: 0,
            otherFeeCents: 0,
            totalCents: 100,
            notes: '',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    } finally {
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
