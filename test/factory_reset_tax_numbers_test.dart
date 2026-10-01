import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/db/einvoice_schema.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/einvoice/einvoice_service.dart';
import 'einvoice_test.dart' as ei;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('F10 same-day repeated factory reset reserves beyond all retained tax attempts and lost old sequences', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-reset-tax-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: true);
    final repo = PosRepository(database: database);
    final service = EInvoiceService(repo, keyStore: ei.MemoryKeys(), documentSigner: ei.testSign);
    try {
      await repo.auth.initializeAdmin('839201'); await repo.auth.login('admin', '839201');
      const p = Product(id: 'p-reset', nameZh: '测试商品', nameEn: 'Test Product', sku: 'P-RESET',
        barcode: '10001', priceCents: 100, costCents: 40, stock: 20);
      Future<SaleRecord> sell() async {
        await repo.upsertProduct(p);
        return repo.createSale(cart: CartState(items: [CartItem(product: p)]),
          paymentMethod: 'CASH', paidCents: 100, cashier: 'admin');
      }
      final oldSale = await sell();
      final prefix = oldSale.receiptNo.substring(0, oldSale.receiptNo.lastIndexOf('-')+1);
      final db = await database.db;
      await db.insert('e_invoice_documents', {'id': 'tax-old', 'sale_id': oldSale.id,
        'invoice_no': oldSale.receiptNo, 'status': 'validated', 'document_uuid': 'keep-uuid',
        'submission_uid': 'keep-uid', 'environment': 'sandbox'});
      await db.insert('e_invoice_documents', {'id': 'tax-correction', 'sale_id': oldSale.id,
        'invoice_no': '${prefix}0042-C3', 'status': 'needs_review', 'document_uuid': 'keep-uuid-2',
        'environment': 'production', 'attempt_no': 3, 'parent_document_id': 'tax-old'});
      await db.insert('e_invoice_logs', {'id': 'audit-old', 'document_id': 'tax-old',
        'action': 'submit', 'created_at': DateTime.now().toIso8601String()});
      var tax = await db.query('e_invoice_documents', orderBy: 'id');
      var logs = await db.query('e_invoice_logs');
      await db.delete('settings', where: "key LIKE 'document_sequence:%'");
      await db.setVersion(9); await database.close();
      final upgraded = await database.db;
      await ensureEInvoiceSchema(upgraded); await ensureEInvoiceSchema(upgraded);
      for (final expected in [43,44]) {
        await repo.factoryResetLocalData();
        expect(await upgraded.query('e_invoice_documents', orderBy: 'id'), tax);
        expect(await upgraded.query('e_invoice_logs'), logs);
        final newSale = await sell();
        expect(newSale.receiptNo, '$prefix${expected.toString().padLeft(4, '0')}');
        await service.saveSettings(ei.supplier, 'id', 'secret');
        await service.prepare(newSale.id, 'sandbox', ei.buyer);
        expect((await upgraded.query('e_invoice_documents', where: 'sale_id=?',
          whereArgs: [newSale.id])).single['invoice_no'], newSale.receiptNo);
        // The next reset retains this pending attempt too.
        tax = await upgraded.query('e_invoice_documents', orderBy: 'id');
        logs = await upgraded.query('e_invoice_logs');
      }
    } finally { service.dispose(); await database.close(); await temp.delete(recursive: true); }
  });
}
