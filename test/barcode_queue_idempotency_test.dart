import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('barcode queue LAN idempotency', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;
    late LanPairingHost host;
    late String token;
    late Uri endpoint;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_barcode_queue_ack_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
      host = LanPairingHost.forTesting(
        repo,
        database: database,
        configuredPort: 0,
      );
      await host.start();
      token = await repo.getSetting('lan_host_token');
      endpoint = Uri.parse('http://127.0.0.1:${host.port}/api/v1/barcode_queue');
    });

    tearDown(() async {
      await host.stop();
      await database.close();
      await dir.delete(recursive: true);
    });

    Future<Map<String, dynamic>> postQueue(String operationId) async {
      final response = await http.post(
        endpoint,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'X-CNKH-Token': token,
        },
        body: jsonEncode(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'operation_id': operationId,
              'product_id': 'pc-product-1',
              'barcode': '1234567890128',
              'product_name': 'Test Product',
              'sku': 'SKU-1',
              'price_cents': 1290,
              'copies': 2,
              'created_at': '2026-09-06T10:00:00.000Z',
              'source': 'phone',
            },
          ],
        }),
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    test('same operation retry is acknowledged but stored once', () async {
      const operationId = 'mobile-op-123';

      final first = await postQueue(operationId);
      expect(first['ok'], true);
      expect(first['acknowledged'], contains(operationId));

      // Simulate ACK loss: Mobile retries the exact same local queue operation.
      final second = await postQueue(operationId);
      expect(second['ok'], true);
      expect(second['acknowledged'], contains(operationId));

      final db = await database.db;
      final rows = await db.query(
        'barcode_print_queue',
        where: 'id=?',
        whereArgs: ['mobile-barcode-$operationId'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['product_id'], 'product-1');
      expect(rows.single['barcode'], '1234567890128');
      expect(rows.single['copies'], 2);

      final all = await db.query('barcode_print_queue');
      expect(all, hasLength(1));
    });
  });
}
