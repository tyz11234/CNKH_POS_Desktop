import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  group('Desktop LAN host sync safety', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;
    late LanPairingHost host;
    late String token;
    late String baseUrl;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_lan_host_safety_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
      final image = File('${dir.path}/p1.jpg');
      await image.writeAsBytes(<int>[10, 20, 30, 40, 50], flush: true);
      await repo.upsertProduct(
        Product(
          id: 'p1',
          nameZh: '商品一',
          nameEn: 'Product One',
          sku: 'SKU-1',
          barcode: '1111111111116',
          priceCents: 100,
          costCents: 50,
          stock: 10,
          imagePath: image.path,
        ),
      );
      await repo.upsertProduct(
        const Product(
          id: 'p2',
          nameZh: '商品二',
          nameEn: 'Product Two',
          sku: 'SKU-2',
          barcode: '2222222222222',
          priceCents: 100,
          costCents: 50,
          stock: 10,
        ),
      );
      host = LanPairingHost.forTesting(
        repo,
        database: database,
        configuredPort: 0,
      );
      await host.start();
      token = await repo.getSetting('lan_host_token');
      baseUrl = 'http://127.0.0.1:${host.port}';
    });

    tearDown(() async {
      await host.stop();
      await database.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Map<String, String> headers() => <String, String>{
          'Content-Type': 'application/json',
          'X-CNKH-Token': token,
        };

    test('catalog advertises real image and authenticated endpoint returns bytes', () async {
      final catalog = await http.get(
        Uri.parse('$baseUrl/api/v1/products'),
        headers: headers(),
      );
      expect(catalog.statusCode, 200);
      final catalogBody = jsonDecode(catalog.body) as Map<String, dynamic>;
      final items = (catalogBody['items'] as List).cast<Map>();
      final p1 = items.singleWhere((e) => e['pc_id'] == 'p1');
      expect(p1['has_image'], true);

      final unauthorized = await http.get(
        Uri.parse('$baseUrl/api/v1/product_images/p1'),
      );
      expect(unauthorized.statusCode, 401);

      final imageResponse = await http.get(
        Uri.parse('$baseUrl/api/v1/product_images/p1'),
        headers: headers(),
      );
      expect(imageResponse.statusCode, 200);
      final imageBody = jsonDecode(imageResponse.body) as Map<String, dynamic>;
      expect(imageBody['ok'], true);
      expect(imageBody['product_id'], 'p1');
      expect(base64Decode(imageBody['base64'] as String), <int>[10, 20, 30, 40, 50]);
    });

    test('legacy sales with same time total and payment but different lines stay distinct', () async {
      const soldAt = '2026-09-06T10:00:00.000Z';

      Future<Map<String, dynamic>> post(String productId) async {
        final response = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: headers(),
          body: jsonEncode(<String, Object?>{
            'sales': <Object?>[
              <String, Object?>{
                'receipt_no': 'LEGACY-001',
                'sold_at': soldAt,
                'cashier': 'staff',
                'payment_method': 'CASH',
                'subtotal_cents': 100,
                'discount_cents': 0,
                'order_discount_cents': 0,
                'total_cents': 100,
                'paid_cents': 100,
                'change_cents': 0,
                'lines': <Object?>[
                  <String, Object?>{
                    'productId': productId,
                    'qty': 1.0,
                    'unitPriceCents': 100,
                  },
                ],
              },
            ],
          }),
        );
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      final first = await post('p1');
      expect(first['imported'], 1);
      final firstReceipt = ((first['receipts'] as List).single as Map)['receipt_no'];
      expect(firstReceipt, 'LEGACY-001');

      final second = await post('p2');
      expect(second['imported'], 1);
      expect(second['skipped'], 0);
      final secondReceipt = ((second['receipts'] as List).single as Map)['receipt_no'];
      expect(secondReceipt, isNot('LEGACY-001'));

      // The exact same legacy retry is still deduplicated against its stronger
      // payload fingerprint, so Lost ACK does not double-deduct stock.
      final retry = await post('p2');
      expect(retry['imported'], 0);
      expect(retry['skipped'], 1);
      expect(((retry['receipts'] as List).single as Map)['receipt_no'], secondReceipt);

      final db = await database.db;
      final sales = await db.query('sales');
      expect(sales, hasLength(2));
      final product1 = await db.query('products', where: 'id=?', whereArgs: ['p1']);
      final product2 = await db.query('products', where: 'id=?', whereArgs: ['p2']);
      expect((product1.single['stock'] as num).toDouble(), 9.0);
      expect((product2.single['stock'] as num).toDouble(), 9.0);
    });
  });
}
