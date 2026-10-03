import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;

  setUp(() async {
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('cnkh-desktop-pages-');
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<void> insertProducts(int count) async {
    final db = await database.db;
    await db.transaction((txn) async {
      for (var i = 0; i < count; i++) {
        final key = i.toString().padLeft(3, '0');
        await txn.insert(
          'products',
          Product(
            id: 'p$key',
            sku: 'SKU-$key',
            barcode: 'BC-$key',
            nameZh: '商品 $key',
            nameEn: 'Product $key',
            priceCents: 100,
            costCents: 50,
            stock: 1,
          ).toMap(),
        );
      }
    });
  }

  Future<List<Product>> collectProductPages(int size) async {
    final all = <Product>[];
    for (var offset = 0; ; offset += size) {
      final page = await repo.searchProducts('', limit: size, offset: offset);
      all.addAll(page);
      if (page.length < size) return all;
    }
  }

  test(
    'all formerly capped product and audit rows are reachable by stable pages',
    () async {
      await insertProducts(301);
      for (final pageSize in [100, 80, 300]) {
        final pages = await collectProductPages(pageSize);
        expect(pages, hasLength(301));
        expect(pages.map((product) => product.id).toSet(), hasLength(301));
      }
      final firstEight = await repo.searchProducts('', limit: 80);
      final secondEight = await repo.searchProducts('', limit: 80, offset: 80);
      expect(firstEight.last.id, isNot(secondEight.first.id));
      expect(
        [...firstEight, ...secondEight].map((product) => product.id).toSet(),
        hasLength(160),
      );

      final db = await database.db;
      await db.transaction((txn) async {
        for (var i = 0; i < 201; i++) {
          await txn.insert('audit_logs', {
            'id': 'audit-${i.toString().padLeft(3, '0')}',
            'occurred_at': '2026-10-01T10:00:00.000',
            'username': 'admin',
            'role': 'admin',
            'action': 'discount',
            'module': 'pos',
            'context': 'receipt-$i',
          });
        }
      });
      final firstAudit = await repo.listAudit(todayOnly: false, limit: 200);
      final lastAudit = await repo.listAudit(
        todayOnly: false,
        limit: 200,
        offset: 200,
      );
      expect(firstAudit, hasLength(200));
      expect(lastAudit, hasLength(1));
      expect(
        firstAudit
            .map((row) => row.id)
            .toSet()
            .intersection(lastAudit.map((row) => row.id).toSet()),
        isEmpty,
      );
    },
  );

  test('exact barcode priority is global across SQL page boundaries', () async {
    final db = await database.db;
    await db.transaction((txn) async {
      for (var i = 0; i < 50; i++) {
        final key = i.toString().padLeft(2, '0');
        await txn.insert(
          'products',
          Product(
            id: 'name-$key',
            sku: 'N-$key',
            barcode: 'N-$key',
            nameZh: 'match item $key',
            nameEn: 'Match $key',
            priceCents: 100,
            stock: 1,
          ).toMap(),
        );
      }
      await txn.insert(
        'products',
        const Product(
          id: 'exact-code',
          sku: 'EXACT',
          barcode: 'MATCH',
          nameZh: 'match last',
          nameEn: 'Match exact',
          priceCents: 100,
          stock: 1,
        ).toMap(),
      );
    });
    final firstPage = await repo.searchProducts('MATCH', limit: 50);
    final secondPage = await repo.searchProducts(
      'MATCH',
      limit: 50,
      offset: 50,
    );
    final ids = [
      ...firstPage,
      ...secondPage,
    ].map((product) => product.id).toList();
    expect(firstPage.first.id, 'exact-code');
    expect(ids, hasLength(51));
    expect(ids.toSet(), hasLength(51));
  });
}
