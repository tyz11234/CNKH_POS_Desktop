import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/sync_role.dart';
import 'package:cnkh_pos_desktop/services/lan_mutations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;
  const product = Product(
    id: 'p1',
    nameZh: '原商品',
    nameEn: 'Original',
    sku: 'SKU-1',
    barcode: 'BAR-1',
    priceCents: 1000,
    costCents: 300,
    stock: 10,
    unit: 'pcs',
  );
  Product other({String sku = 'SKU-2', String barcode = 'BAR-2'}) => Product(
    id: 'p2',
    nameZh: '另一商品',
    nameEn: 'Other',
    sku: sku,
    barcode: barcode,
    priceCents: 500,
    stock: 20,
  );

  setUp(() async {
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('identity-hold-');
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertProduct(product);
  });
  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  test(
    'save rejects normalized same-field and cross-field duplicates atomically',
    () async {
      final db = await database.db;
      final outboxBefore = await db.query('sync_outbox');
      for (final duplicate in [
        other(barcode: ' bar-1 '),
        other(sku: ' sku-1 '),
        other(barcode: ' sKu-1 '),
        other(sku: ' bAr-1 '),
      ]) {
        await expectLater(repo.upsertProduct(duplicate), throwsStateError);
        expect(await repo.getProduct('p2'), isNull);
      }
      expect(await db.query('sync_outbox'), outboxBefore);
      expect(await db.query('stock_moves'), isEmpty);
    },
  );

  test(
    'self edits, identical own SKU/barcode and deleted codes are allowed',
    () async {
      final ownCodes = product.copyWith(sku: ' Both ', barcode: 'both');
      await repo.upsertProduct(ownCodes, original: product);
      await repo.upsertProduct(
        ownCodes.copyWith(nameZh: 'Edited'),
        original: ownCodes,
      );
      expect((await repo.findByBarcodeOrSku(' BOTH '))!.id, product.id);
      await repo.softDeleteProduct(product.id);
      await repo.upsertProduct(other(sku: 'both', barcode: 'BOTH'));
      expect((await repo.findByBarcodeOrSku(' both '))!.id, 'p2');
      expect((await repo.getProduct(product.id))!.isDeleted, 1);
    },
  );

  test(
    'validation uses final merged row rather than stale editor identifiers',
    () async {
      await repo.upsertProduct(
        product.copyWith(sku: 'FRESH'),
        original: product,
      );
      await repo.upsertProduct(other(barcode: 'SKU-1'));
      await repo.upsertProduct(
        product.copyWith(nameZh: 'Edited'),
        original: product,
      );
      final saved = (await repo.getProduct(product.id))!;
      expect(saved.sku, 'FRESH');
      expect(saved.nameZh, 'Edited');
      expect((await repo.findByBarcodeOrSku('SKU-1'))!.id, 'p2');
    },
  );

  test('concurrent duplicate creates commit only one product', () async {
    final attempts = [
      other(barcode: 'shared'),
      const Product(
        id: 'p3',
        nameZh: 'Third',
        nameEn: 'Third',
        sku: ' SHARED ',
        barcode: 'BAR-3',
        priceCents: 500,
      ),
    ];
    final results = await Future.wait(
      attempts.map((p) async {
        try {
          await repo.upsertProduct(p);
          return true;
        } on StateError {
          return false;
        }
      }),
    );
    expect(results.where((saved) => saved), hasLength(1));
    expect(await (await database.db).query('products'), hasLength(2));
    expect(
      await (await database.db).query('sync_outbox'),
      hasLength(isDesktopHost ? 0 : 2),
    );
  });

  test('legacy duplicates are preserved and scans refuse ambiguity', () async {
    final db = await database.db;
    await db.insert('products', other(sku: ' bar-1 ').toMap());
    await expectLater(repo.findByBarcodeOrSku('BAR-1'), throwsStateError);
    expect(await db.query('products'), hasLength(2));
    // Deletion must remain possible to resolve a pre-existing collision.
    await repo.softDeleteProduct('p2');
    expect((await repo.findByBarcodeOrSku(' bar-1 '))!.id, product.id);
    expect(await db.query('products'), hasLength(2));
  });

  test(
    'conflicting edit rolls back product, stock ledger and outbox together',
    () async {
      await repo.upsertProduct(other());
      final db = await database.db;
      final outboxBefore = await db.query('sync_outbox');
      await expectLater(
        repo.upsertProduct(
          product.copyWith(barcode: ' sku-2 ', stock: 50),
          original: product,
        ),
        throwsStateError,
      );
      expect((await repo.getProduct(product.id))!.toMap(), product.toMap());
      expect(await db.query('stock_moves'), isEmpty);
      expect(await db.query('sync_outbox'), outboxBefore);
    },
  );

  test('held order preserves price and display while using current inventory and identity', () async {
    final held = await repo.holdCart(
      cart: CartState(
        orderDiscountCents: 100,
        items: [CartItem(product: product, qty: 2, discountCents: 50)],
      ),
      cashier: 'admin',
    );
    await repo.upsertProduct(
      product.copyWith(
        priceCents: 1500,
        costCents: 400,
        nameZh: '改名',
        nameEn: 'Renamed',
        sku: 'NEW-SKU',
        barcode: 'NEW-BAR',
        stock: 7,
        unit: 'box',
      ),
    );
    final resumed = await repo.resumeHeld(held);
    final line = resumed.items.single;
    expect(line.product.priceCents, 1000);
    expect(line.product.nameZh, product.nameZh);
    expect(line.product.nameEn, product.nameEn);
    expect(line.product.unit, 'pcs');
    expect(line.product.stock, 7);
    expect(line.product.costCents, 400);
    expect(line.product.sku, 'NEW-SKU');
    expect(line.product.barcode, 'NEW-BAR');
    expect(line.qty, 2);
    expect(line.discountCents, 50);
    expect(resumed.rawPayableCents, 1850);
    final sale = await repo.createSale(
      cart: resumed,
      paymentMethod: 'CASH',
      paidCents: 2000,
      cashier: 'admin',
    );
    expect(sale.totalCents, 1850);
    expect((await repo.getProduct(product.id))!.stock, 5);
    expect((jsonDecode(sale.linesJson) as List).single['unitPriceCents'], 1000);
  });

  test(
    'legacy holds without snapshots continue to resume at current price',
    () async {
      final row = <String, Object?>{
        'id': 'legacy',
        'hold_no': 'H-legacy',
        'cashier': 'admin',
        'held_at': '2026-01-01T10:00:00',
        'payload_json': jsonEncode({
          'orderDiscountCents': 10,
          'items': [
            {'productId': product.id, 'qty': 2, 'discountCents': 30},
          ],
        }),
      };
      await (await database.db).insert('held_orders', row);
      await repo.upsertProduct(product.copyWith(priceCents: 1500));
      final resumed = await repo.resumeHeld(HeldOrder.fromMap(row));
      expect(resumed.items.single.product.priceCents, 1500);
      expect(resumed.items.single.qty, 2);
      expect(resumed.rawPayableCents, 2960);
      expect(await repo.listHeld(cashier: 'admin'), isEmpty);
    },
  );

  test(
    'restoring a snapshot never resurrects a deleted product for checkout',
    () async {
      final held = await repo.holdCart(
        cart: CartState(items: [CartItem(product: product)]),
        cashier: 'admin',
      );
      await repo.softDeleteProduct(product.id);
      final resumed = await repo.resumeHeld(held);
      expect(resumed.items.single.product.isDeleted, 1);
      await expectLater(
        repo.createSale(
          cart: resumed,
          paymentMethod: 'CASH',
          paidCents: 1000,
          cashier: 'admin',
        ),
        throwsStateError,
      );
      expect(await repo.salesAll(), isEmpty);
    },
  );

  test(
    'missing product does not silently discard held lines or delete the hold',
    () async {
      final held = await repo.holdCart(
        cart: CartState(items: [CartItem(product: product)]),
        cashier: 'admin',
      );
      await (await database.db).delete(
        'products',
        where: 'id=?',
        whereArgs: [product.id],
      );
      await expectLater(repo.resumeHeld(held), throwsStateError);
      expect((await repo.listHeld(cashier: 'admin')).single.id, held.id);
    },
  );
  test(
    'LAN edit checks merged identifiers rather than stale before fields',
    () async {
      await repo.upsertProduct(
        product.copyWith(sku: 'FRESH'),
        original: product,
      );
      await repo.upsertProduct(other(barcode: 'SKU-1'));
      final db = await database.db;
      await applyLanMutation(db, {
        'id': 'merged-identifiers',
        'kind': 'product_upsert',
        'payload': {
          'before': product.toMap(),
          'row': product.copyWith(nameZh: 'From phone').toMap(),
        },
      });
      final saved = (await repo.getProduct(product.id))!;
      expect(saved.sku, 'FRESH');
      expect(saved.nameZh, 'From phone');
      expect(await db.query('sync_applied_operations'), hasLength(1));
    },
  );

  test(
    'LAN cross-field collision is rejected without ACK or stock changes',
    () async {
      await repo.upsertProduct(other());
      final db = await database.db;
      await expectLater(
        applyLanMutation(db, {
          'id': 'cross-field-collision',
          'kind': 'product_upsert',
          'payload': {
            'before': product.toMap(),
            'row': product.copyWith(barcode: ' sku-2 ', stock: 50).toMap(),
          },
        }),
        throwsStateError,
      );
      expect((await repo.getProduct(product.id))!.toMap(), product.toMap());
      expect(await db.query('sync_applied_operations'), isEmpty);
      expect(await db.query('stock_moves'), isEmpty);
    },
  );

  test('new purchase product cannot bypass shared code validation', () async {
    final duplicate = other(barcode: ' sku-1 ');
    await expectLater(
      repo.createPurchase(
        supplierId: 'supplier',
        supplierName: 'Supplier',
        operator: 'admin',
        totalCents: 500,
        newProducts: [duplicate],
        lines: [
          {'productId': duplicate.id, 'qty': 1, 'unitCostCents': 500},
        ],
      ),
      throwsStateError,
    );
    expect(await repo.getProduct(duplicate.id), isNull);
    expect(await (await database.db).query('purchases'), isEmpty);
    expect(await (await database.db).query('stock_moves'), isEmpty);
  });
}
