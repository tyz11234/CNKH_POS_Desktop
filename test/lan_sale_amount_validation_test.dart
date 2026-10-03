import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  late LanPairingHost host;
  late Map<String, String> headers;

  setUp(() async {
    AppDatabase.ensureFfi();
    temp = await Directory.systemTemp.createTemp('cnkh-sale-amounts-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertProduct(
      const Product(
        id: 'p1',
        nameZh: '商品',
        nameEn: 'Product',
        sku: 'SKU-1',
        barcode: '10001',
        priceCents: 100,
        costCents: 40,
        stock: 10,
      ),
    );
    host = LanPairingHost.forTesting(
      repo,
      database: database,
      configuredPort: 0,
    );
    await host.start();
    headers = {
      'Content-Type': 'application/json',
      'X-CNKH-Token': await repo.getSetting('lan_host_token'),
    };
  });

  tearDown(() async {
    await host.stop();
    await database.close();
    await temp.delete(recursive: true);
  });

  Map<String, Object?> sale() => {
    'client_sale_id': 'phone-sale',
    'receipt_no': 'PHONE-001',
    'sold_at': '2026-10-03T10:00:00.000',
    'cashier': 'staff',
    'payment_method': 'CASH',
    'subtotal_cents': 100,
    'total_cents': 100,
    'paid_cents': 100,
    'change_cents': 0,
    'lines': [
      {'productId': 'p1', 'qty': 1, 'unitPriceCents': 100},
    ],
  };

  Future<http.Response> post(Map<String, Object?> payload) => http.post(
    Uri.parse('http://127.0.0.1:${host.port}/api/v1/sales'),
    headers: headers,
    body: jsonEncode({
      'sales': [payload],
    }),
  );

  for (final field in [
    'subtotal_cents',
    'total_cents',
    'paid_cents',
    'change_cents',
    'discount_cents',
    'order_discount_cents',
  ]) {
    for (final invalid in [-1, 1.5, 'invalid']) {
      test(
        'rejects $field=$invalid without applying the sale or inventory',
        () async {
          final response = await post({...sale(), field: invalid});
          expect(
            response.statusCode,
            HttpStatus.badRequest,
            reason: response.body,
          );
          final db = await database.db;
          expect(await db.query('sales'), isEmpty);
          expect(await db.query('lan_sync_mobile_sales'), isEmpty);
          expect(await db.query('stock_moves'), isEmpty);
          expect((await repo.getProduct('p1'))!.stock, 10);
        },
      );
    }
  }

  test(
    'legacy integer strings and omitted optional amounts remain compatible',
    () async {
      final response = await post({
        ...sale(),
        'subtotal_cents': '100',
        'total_cents': '100',
        'paid_cents': null,
        'change_cents': null,
        'rounding_cents': '-2',
      });
      expect(response.statusCode, HttpStatus.ok, reason: response.body);
      final imported = (await repo.salesAll()).single;
      expect(imported.totalCents, 100);
      expect(imported.paidCents, 100);
      expect(imported.roundingCents, -2);
      expect((await repo.getProduct('p1'))!.stock, 9);
    },
  );
}
