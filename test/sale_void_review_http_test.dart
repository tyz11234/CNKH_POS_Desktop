import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LAN sale void refusal is structured, retryable, and idempotent',
    () async {
      final dir = await Directory.systemTemp.createTemp('cnkh-sale-void-host-');
      final database = AppDatabase.forTesting(
        '${dir.path}/desktop.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      const product = Product(
        id: 'p1',
        sku: 'P1',
        barcode: '10001',
        nameZh: '商品',
        nameEn: 'Product',
        priceCents: 100,
        costCents: 50,
        stock: 100,
      );
      await repo.upsertProduct(product);
      final host = LanPairingHost.forTesting(
        repo,
        database: database,
        configuredPort: 0,
      );
      await host.start();
      final endpoint = Uri.parse(
        'http://127.0.0.1:${host.port}/api/v1/mutations',
      );
      // Bypass FlutterTest's network-denying HttpOverrides for loopback HTTP.
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final client = IOClient(HttpClient());
      HttpOverrides.global = previousOverrides;
      final headers = {
        'Content-Type': 'application/json',
        'X-CNKH-Token': await repo.getSetting('lan_host_token'),
      };

      Future<Map<String, dynamic>> send(
        String operationId,
        SaleRecord sale,
      ) async {
        final response = await client.post(
          endpoint,
          headers: headers,
          body: jsonEncode({
            'operations': [
              {
                'id': operationId,
                'kind': 'sale_void',
                'client_entity_id': sale.id,
                'payload': {
                  'client_sale_id': sale.id,
                  'receipt_no': sale.receiptNo,
                  'note': 'Mobile request',
                },
              },
            ],
          }),
        );
        expect(response.statusCode, 200);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      Future<SaleRecord> makeSale() => repo.createSale(
        cart: CartState(items: [CartItem(product: product)]),
        paymentMethod: 'CASH',
        paidCents: 100,
        cashier: 'admin',
      );

      try {
        final db = await database.db;
        final blockedCases = <({String status, String uuid, String uid})>[
          (status: 'submitting', uuid: '', uid: ''),
          (status: 'needs_review', uuid: '', uid: ''),
          (status: 'pending', uuid: 'known-uuid', uid: ''),
          (status: 'pending', uuid: '', uid: 'known-submission'),
        ];
        for (var i = 0; i < blockedCases.length; i++) {
          final state = blockedCases[i];
          final sale = await makeSale();
          await db.insert('e_invoice_documents', {
            'id': 'tax-${sale.id}',
            'sale_id': sale.id,
            'invoice_no': sale.receiptNo,
            'environment': 'sandbox',
            'status': state.status,
            'document_uuid': state.uuid,
            'submission_uid': state.uid,
            'attempt_no': 1,
          });
          final before = (await repo.getProduct(product.id))!.stock;
          final result = await send('void-blocked-$i', sale);
          expect(result['acknowledged'], isEmpty);
          expect(result['rejected_operation'], {
            'id': 'void-blocked-$i',
            'kind': 'sale_void',
            'code': 'sale_void_requires_review',
          });
          expect(result['error'], contains('核对 MyInvois'));
          expect((await repo.getProduct(product.id))!.stock, before);
          expect(
            (await db.query(
              'sales',
              where: 'id=?',
              whereArgs: [sale.id],
            )).single['voided'],
            0,
          );
          expect(
            await db.query(
              'sync_applied_operations',
              where: 'id=?',
              whereArgs: ['void-blocked-$i'],
            ),
            isEmpty,
          );
        }

        final retrySale = await makeSale();
        await db.insert('e_invoice_documents', {
          'id': 'tax-${retrySale.id}',
          'sale_id': retrySale.id,
          'invoice_no': retrySale.receiptNo,
          'environment': 'sandbox',
          'status': 'pending',
          'document_uuid': 'known-retry-uuid',
          'submission_uid': '',
          'attempt_no': 1,
        });
        final refused = await send('same-void-operation', retrySale);
        expect(
          refused['rejected_operation']['code'],
          'sale_void_requires_review',
        );
        expect((await repo.getProduct(product.id))!.stock, lessThan(100));

        await db.update(
          'e_invoice_documents',
          {'status': 'rejected'},
          where: 'sale_id=?',
          whereArgs: [retrySale.id],
        );
        final accepted = await send('same-void-operation', retrySale);
        expect(accepted['ok'], true);
        expect(accepted['acknowledged'], ['same-void-operation']);
        final stockAfter = (await repo.getProduct(product.id))!.stock;
        final duplicateAck = await send('same-void-operation', retrySale);
        expect(duplicateAck['acknowledged'], ['same-void-operation']);
        expect((await repo.getProduct(product.id))!.stock, stockAfter);
        expect(
          await db.query(
            'stock_reversals',
            where: 'sale_id=?',
            whereArgs: [retrySale.id],
          ),
          hasLength(1),
        );
        expect(
          await db.query(
            'sync_applied_operations',
            where: 'id=?',
            whereArgs: ['same-void-operation'],
          ),
          hasLength(1),
        );

        final noIdentifierSale = await makeSale();
        await db.insert('e_invoice_documents', {
          'id': 'tax-${noIdentifierSale.id}',
          'sale_id': noIdentifierSale.id,
          'invoice_no': noIdentifierSale.receiptNo,
          'environment': 'sandbox',
          'status': 'pending',
          'document_uuid': '',
          'submission_uid': '',
          'attempt_no': 1,
        });
        expect(
          (await send('allowed-pending-empty', noIdentifierSale))['ok'],
          true,
        );
      } finally {
        client.close();
        await host.stop();
        await database.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
