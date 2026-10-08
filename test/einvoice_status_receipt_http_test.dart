import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'corrected invoice status carries the original sale receipt for Mobile',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'cnkh-einvoice-receipt-',
      );
      final database = AppDatabase.forTesting(
        '${temp.path}/desktop.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      final host = LanPairingHost.forTesting(
        repo,
        database: database,
        configuredPort: 0,
      );
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final transport = IOClient(HttpClient());
      HttpOverrides.global = previousOverrides;
      try {
        const product = Product(
          id: 'p1',
          sku: 'P1',
          barcode: 'P1',
          nameZh: '商品',
          nameEn: 'Product',
          priceCents: 100,
          stock: 2,
        );
        await repo.upsertProduct(product);
        final sale = await repo.createSale(
          cart: CartState(items: [CartItem(product: product)]),
          paymentMethod: 'CASH',
          paidCents: 100,
          cashier: 'test',
        );
        final db = await database.db;
        await db.insert('e_invoice_documents', {
          'id': 'tax-original',
          'sale_id': sale.id,
          'invoice_no': sale.receiptNo,
          'environment': 'sandbox',
          'status': 'invalid',
          'attempt_no': 1,
        });
        await db.insert('e_invoice_documents', {
          'id': 'tax-correction',
          'sale_id': sale.id,
          'invoice_no': '${sale.receiptNo}-C2',
          'environment': 'sandbox',
          'status': 'validated',
          'attempt_no': 2,
        });
        await host.start();
        final response = await transport.get(
          Uri.parse(
            'http://127.0.0.1:${host.port}/api/v1/einvoices?status_version=2',
          ),
          headers: {'X-CNKH-Token': await repo.getSetting('lan_host_token')},
        );
        expect(response.statusCode, 200);
        final status =
            ((jsonDecode(response.body) as Map)['items'] as List).single as Map;
        expect(status['document_id'], 'tax-correction');
        expect(status['client_sale_id'], '');
        expect(status['receipt_no'], sale.receiptNo);
        expect(status['invoice_no'], '${sale.receiptNo}-C2');
        expect(status['status'], 'validated');
      } finally {
        transport.close();
        await host.stop();
        await database.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
