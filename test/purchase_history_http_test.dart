import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('purchases_v1 exposes structured history without local image path', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-purchase-history-http-');
    final database = AppDatabase.forTesting('${dir.path}/desktop.db', seed: false);
    final repo = PosRepository(database: database);
    final host = LanPairingHost.forTesting(
      repo,
      database: database,
      configuredPort: 0,
    );
    try {
      await repo.upsertSupplier(const Supplier(id: 's1', name: 'Supplier One'));
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
            'unit': 'pcs',
            'conversionFactor': 1.0,
            'unitCostCents': 250,
            'subtotalCents': 500,
            'originalQty': 2.0,
          },
        ],
        totalCents: 500,
        operator: 'admin',
      );
      final db = await database.db;
      final purchase = (await db.query('purchases')).single;
      await db.update(
        'purchases',
        <String, Object?>{
          'invoice_no': 'INV-100',
          'invoice_date': '2026-09-06',
          'tax_cents': 30,
          'delivery_fee_cents': 20,
          'source': 'ocr',
          'draft_id': 'draft-100',
          'ocr_raw_text': 'supplier invoice raw text',
          'image_path': r'C:\private\desktop\invoice.jpg',
        },
        where: 'id=?',
        whereArgs: <Object?>[purchase['id']],
      );

      await host.start();
      final token = await repo.getSetting('lan_host_token');
      final base = 'http://127.0.0.1:${host.port}';
      final headers = <String, String>{'X-CNKH-Token': token};

      final health = await http.get(Uri.parse('$base/api/v1/health'), headers: headers);
      expect(health.statusCode, HttpStatus.ok);
      final healthBody = jsonDecode(health.body) as Map<String, dynamic>;
      expect((healthBody['capabilities'] as List), contains('purchases_v1'));

      final unauthorized = await http.get(Uri.parse('$base/api/v1/purchases'));
      expect(unauthorized.statusCode, HttpStatus.unauthorized);

      final response = await http.get(
        Uri.parse('$base/api/v1/purchases'),
        headers: headers,
      );
      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      expect(body['ok'], true);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      final item = Map<String, dynamic>.from(items.single as Map);
      expect(item['pc_id'], purchase['id']);
      expect(item['supplier_id'], 's1');
      expect(item['invoice_no'], 'INV-100');
      expect(item['tax_cents'], 30);
      expect(item['delivery_fee_cents'], 20);
      expect(item['source'], 'ocr');
      expect(item['draft_id'], 'draft-100');
      expect(item['ocr_raw_text'], 'supplier invoice raw text');
      expect(item.containsKey('image_path'), isFalse);
      final lines = item['lines'] as List;
      expect(lines, hasLength(1));
      expect((lines.single as Map)['productId'], 'p1');
      expect((lines.single as Map)['conversionFactor'], 1.0);
      expect((lines.single as Map)['originalQty'], 2.0);
    } finally {
      await host.stop();
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
