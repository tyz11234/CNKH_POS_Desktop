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
    temp = await Directory.systemTemp.createTemp('cnkh-sale-identity-');
    database = AppDatabase.forTesting('${temp.path}/pos.db');
    repo = PosRepository(database: database);
    await repo.upsertProduct(const Product(
      id: 'p1', nameZh: '商品', nameEn: 'Product', sku: 'SKU-1',
      barcode: '10001', priceCents: 100, costCents: 40, stock: 10,
    ));
    host = LanPairingHost.forTesting(repo, database: database, configuredPort: 0);
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

  Map<String, Object?> sale({String? id, String productId = 'p1', bool voided = false}) => {
    if (id != null) 'client_sale_id': id,
    'receipt_no': 'COLLISION-001',
    'sold_at': '2026-09-12T10:00:00.000',
    'cashier': 'staff',
    'payment_method': 'CASH',
    'subtotal_cents': 100,
    'total_cents': 100,
    'paid_cents': 100,
    'change_cents': 0,
    'voided': voided ? 1 : 0,
    'void_note': voided ? 'cancel' : '',
    'lines': [{'productId': productId, 'qty': 1, 'unitPriceCents': 100}],
  };

  Future<Map<String, dynamic>> post(Map<String, Object?> payload) async {
    final response = await http.post(
      Uri.parse('http://127.0.0.1:${host.port}/api/v1/sales'),
      headers: headers,
      body: jsonEncode({'sales': [payload]}),
    );
    expect(response.statusCode, 200, reason: response.body);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  test('different client IDs stay distinct even with identical receipts and contents', () async {
    final first = await post(sale(id: 'same-prefix-device-one'));
    final second = await post(sale(id: 'same-prefix-device-two'));
    final third = await post(sale(id: 'same-prefix-device-three'));
    expect(first['imported'], 1);
    expect(second['imported'], 1);
    expect(third['imported'], 1);
    final receipts = [first, second, third]
        .map((b) => ((b['receipts'] as List).single as Map)['receipt_no']).toSet();
    expect(receipts, hasLength(3));
    final retry = await post(sale(id: 'same-prefix-device-two'));
    expect(retry['imported'], 0);
    expect((await repo.getProduct('p1'))!.stock, 7);
    expect(await repo.salesAll(), hasLength(3));
    expect(await (await database.db).query('lan_sync_mobile_sales'), hasLength(3));

    await post(sale(id: 'same-prefix-device-two', voided: true));
    await post(sale(id: 'same-prefix-device-two', voided: true));
    expect((await repo.getProduct('p1'))!.stock, 8);
    expect((await repo.salesAll()).where((s) => s.voided == 1), hasLength(1));
  });

  test('legacy pc-prefixed retry and void do not replay stock mutations', () async {
    final first = await post(sale(productId: 'pc-p1'));
    final retry = await post(sale(productId: 'pc-p1'));
    expect(first['imported'], 1);
    expect(retry['imported'], 0);
    expect((await repo.getProduct('p1'))!.stock, 9);
    await post(sale(productId: 'pc-p1', voided: true));
    await post(sale(productId: 'pc-p1', voided: true));
    expect((await repo.getProduct('p1'))!.stock, 10);
    expect((await repo.salesAll()).single.voided, 1);
    expect(await (await database.db).query('stock_reversals'), hasLength(1));
  });

  test('legacy canonical receipt collision also applies a later void once', () async {
    await post(sale(id: 'modern-sale'));
    final legacy = {...sale(), 'sold_at': '2026-09-12T11:00:00.000'};
    final imported = await post(legacy);
    expect(imported['imported'], 1);
    expect(((imported['receipts'] as List).single as Map)['receipt_no'],
        isNot('COLLISION-001'));
    await post({...legacy, 'voided': 1});
    await post({...legacy, 'voided': 1});
    expect((await repo.getProduct('p1'))!.stock, 9);
    expect(await repo.salesAll(), hasLength(2));
  });
}
