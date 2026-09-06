import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('OCR attachment localhost integration', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;
    late LanPairingHost host;
    late String token;
    late Uri endpoint;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_attachment_http_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
      final db = await database.db;
      await db.insert(
        'products',
        const Product(
          id: 'product-http-1',
          nameZh: '测试商品',
          nameEn: 'Test Product',
          sku: 'HTTP-1',
          barcode: '9550000000105',
          priceCents: 500,
          costCents: 200,
          stock: 10,
        ).toMap(),
      );
      host = LanPairingHost.forTesting(
        repo,
        database: database,
        configuredPort: 0,
      );
      await host.start();
      token = await repo.getSetting('lan_host_token');
      endpoint = Uri.parse('http://127.0.0.1:${host.port}/api/v1/mutations');
    });

    tearDown(() async {
      await host.stop();
      await database.close();
      await dir.delete(recursive: true);
    });

    Future<Map<String, dynamic>> postOperation(Map<String, dynamic> operation) async {
      final response = await http.post(
        endpoint,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'X-CNKH-Token': token,
        },
        body: jsonEncode(<String, Object?>{
          'operations': <Object?>[operation],
        }),
      );
      expect(response.statusCode, 200);
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    test('attachment retry is ACKed once without replaying purchase stock', () async {
      const purchaseOperationId = 'http-purchase-op-1';
      const purchaseId = 'http-purchase-1';
      final purchase = <String, dynamic>{
        'id': purchaseOperationId,
        'kind': 'purchase',
        'payload': <String, Object?>{
          'id': purchaseId,
          'supplier_id': 'supplier-http',
          'supplier_name': 'HTTP Supplier',
          'purchased_at': '2026-09-06T11:00:00Z',
          'invoice_no': 'HTTP-INV-1',
          'invoice_date': '2026-09-06',
          'total_cents': 600,
          'source': 'ocr',
          'draft_id': 'http-draft-1',
          'ocr_raw_text': '测试商品 3 x 2.00',
          'operator': 'staff',
          'lines': <Object?>[
            <String, Object?>{
              'productId': 'product-http-1',
              'name': '测试商品',
              'qty': 3.0,
              'invoiceQty': 3.0,
              'unit': 'pcs',
              'unitCostCents': 200,
              'invoiceUnitCostCents': 200,
              'subtotalCents': 600,
              'beforeCostCents': 200,
            },
          ],
        },
      };
      final purchaseResult = await postOperation(purchase);
      expect(purchaseResult['ok'], true);
      expect(purchaseResult['acknowledged'], contains(purchaseOperationId));

      final db = await database.db;
      final afterPurchase =
          (await db.query('products', where: 'id=?', whereArgs: ['product-http-1']))
              .single;
      expect((afterPurchase['stock'] as num).toDouble(), 13.0);

      final bytes = utf8.encode('original-invoice-binary-evidence');
      final hash = hex((await Sha256().hash(bytes)).bytes);
      const attachmentOperationId = 'http-attachment-op-1';
      final attachment = <String, dynamic>{
        'id': attachmentOperationId,
        'kind': 'purchase_attachment',
        'payload': <String, Object?>{
          'attachment_id': '$purchaseId-invoice-original',
          'purchase_id': purchaseId,
          'kind': 'invoice_original',
          'filename': '原始单据.jpg',
          'content_hash': hash,
          'base64': base64Encode(bytes),
          'created_at': '2026-09-06T11:00:01Z',
        },
      };

      final first = await postOperation(attachment);
      expect(first['ok'], true);
      expect(first['acknowledged'], contains(attachmentOperationId));

      // Simulate lost ACK at the Mobile side: exact same durable operation is
      // POSTed again after Desktop already committed the bytes.
      final second = await postOperation(attachment);
      expect(second['ok'], true);
      expect(second['acknowledged'], contains(attachmentOperationId));

      final stored = await db.query(
        'purchase_attachments',
        where: 'purchase_id=?',
        whereArgs: [purchaseId],
      );
      expect(stored, hasLength(1));
      expect(stored.single['filename'], '原始单据.jpg');
      expect(stored.single['content_hash'], hash);

      final afterRetry =
          (await db.query('products', where: 'id=?', whereArgs: ['product-http-1']))
              .single;
      expect((afterRetry['stock'] as num).toDouble(), 13.0);
      expect(
        await db.query(
          'sync_applied_operations',
          where: 'id=?',
          whereArgs: [attachmentOperationId],
        ),
        hasLength(1),
      );
    });
  });
}
