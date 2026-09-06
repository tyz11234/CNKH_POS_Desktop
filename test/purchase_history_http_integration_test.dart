import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/db/ocr_purchase_schema.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('purchase history endpoint is authenticated and read-only for stock', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-purchase-http-');
    final database = AppDatabase.forTesting('${dir.path}/desktop.db', seed: false);
    final repo = PosRepository(database: database);
    late LanPairingHost host;

    try {
      final db = await database.db;
      await ensureOcrPurchaseSchema(db);
      await repo.upsertProduct(
        const Product(
          id: 'p-purchase-http',
          nameZh: '测试商品',
          nameEn: 'Test Product',
          sku: 'PUR-HTTP-1',
          barcode: '9550000000097',
          priceCents: 800,
          costCents: 250,
          stock: 12,
        ),
      );
      await db.insert('suppliers', <String, Object?>{
        'id': 's-purchase-http',
        'name': '测试供应商',
        'phone': '',
        'email': '',
        'notes': '',
        'is_deleted': 0,
      });
      await db.insert('purchases', <String, Object?>{
        'id': 'purchase-http-1',
        'purchase_no': 'PO-HTTP-1',
        'supplier_id': 's-purchase-http',
        'supplier_name': '测试供应商',
        'purchased_at': '2026-09-06T12:00:00.000Z',
        'total_cents': 500,
        'lines_json': jsonEncode(<Object?>[
          <String, Object?>{
            'productId': 'p-purchase-http',
            'name': '测试商品',
            'qty': 2.0,
            'unit': 'pcs',
            'conversionFactor': 1.0,
            'unitCostCents': 250,
            'subtotalCents': 500,
          },
        ]),
        'notes': 'history endpoint test',
        'invoice_no': 'INV-HTTP-1',
        'invoice_date': '2026-09-06',
        'discount_cents': 0,
        'tax_cents': 0,
        'delivery_fee_cents': 0,
        'other_fee_cents': 0,
        'source': 'desktop',
        'draft_id': null,
        'image_path': '',
        'ocr_raw_text': 'RAW OCR EVIDENCE',
        'reversed': 0,
        'reversed_at': null,
        'reversed_by': null,
        'reversal_reason': '',
        'reversal_notes': '',
      });

      host = LanPairingHost.forTesting(
        repo,
        database: database,
        configuredPort: 0,
      );
      await host.start();
      final token = await repo.getSetting('lan_host_token');
      final baseUrl = 'http://127.0.0.1:${host.port}';

      final unauthorized = await http.get(
        Uri.parse('$baseUrl/api/v1/purchases'),
      );
      expect(unauthorized.statusCode, HttpStatus.unauthorized);

      final headers = <String, String>{'X-CNKH-Token': token};
      final health = await http.get(
        Uri.parse('$baseUrl/api/v1/health'),
        headers: headers,
      );
      expect(health.statusCode, HttpStatus.ok);
      final healthBody = jsonDecode(health.body) as Map<String, dynamic>;
      expect((healthBody['capabilities'] as List), contains('purchases_v1'));

      final before = await repo.getProduct('p-purchase-http');
      expect(before!.stock, 12);
      final movesBefore = await db.query('stock_moves');

      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/purchases'),
        headers: headers,
      );
      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['ok'], true);
      final items = (body['items'] as List).cast<Map>();
      final purchase = items.singleWhere((m) => m['pc_id'] == 'purchase-http-1');
      expect(purchase['purchase_no'], 'PO-HTTP-1');
      expect(purchase['supplier_id'], 's-purchase-http');
      expect(purchase['invoice_no'], 'INV-HTTP-1');
      expect(purchase['invoice_date'], '2026-09-06');
      expect(purchase['total_cents'], 500);
      expect(purchase['ocr_raw_text'], 'RAW OCR EVIDENCE');
      expect(purchase['reversed'], 0);
      final lines = (purchase['lines'] as List).cast<Map>();
      expect(lines, hasLength(1));
      expect(lines.single['productId'], 'p-purchase-http');
      expect((lines.single['qty'] as num).toDouble(), 2.0);

      final after = await repo.getProduct('p-purchase-http');
      expect(after!.stock, 12);
      expect(await db.query('stock_moves'), movesBefore);
    } finally {
      try {
        await host.stop();
      } catch (_) {}
      await database.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });
}
