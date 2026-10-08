import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/purchase_invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  late PurchaseLineMatcher matcher;
  const supplier = Supplier(id: 'supplier', name: 'Supplier');

  setUp(() async {
    AppDatabase.ensureFfi();
    temp = await Directory.systemTemp.createTemp('cnkh-purchase-merge-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    matcher = PurchaseLineMatcher(repo);
    await repo.upsertProduct(
      const Product(
        id: 'a',
        nameZh: 'Screw',
        nameEn: 'Screw',
        sku: 'SKU-A',
        barcode: 'CODE-A',
        priceCents: 500,
        costCents: 200,
        stock: 0,
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  Future<void> addSameNameProduct() => repo.upsertProduct(
    const Product(
      id: 'b',
      nameZh: 'Screw',
      nameEn: 'Screw',
      sku: 'SKU-B',
      barcode: 'CODE-B',
      priceCents: 600,
      costCents: 200,
      stock: 0,
    ),
  );

  Future<Map<String, Object?>> commit(List<PurchaseDraftLine> lines) async {
    await matcher.commit(lines: lines, supplier: supplier, operator: 'admin');
    return (await (await database.db).query('purchases')).single;
  }

  test(
    'appending QR then OCR keeps both cost batches and commits RM50',
    () async {
      final payload = PurchaseInvoicePayload.tryParse(
        'CNKHPO1:{"v":1,"lines":[{"name":"Screw","barcode":"CODE-A",'
        '"qty":10,"costCents":200}]}',
      )!;
      final draft = await matcher.resolve(payload.lines);
      final ocr = PurchaseInvoiceTextParser.parse('Screw 10 3.00');
      expect(ocr, hasLength(1));
      appendPurchaseDraftLines(draft, await matcher.resolve(ocr));

      expect(draft, hasLength(2));
      expect(draft.map((line) => line.unitCostCents), [200, 300]);
      expect(draft.fold<int>(0, (sum, line) => sum + line.subtotalCents), 5000);
      final purchase = await commit(draft);
      expect(purchase['total_cents'], 5000);
      final saved = jsonDecode(purchase['lines_json'] as String) as List;
      expect(saved.map((line) => line['subtotalCents']), [2000, 3000]);
      expect((await repo.getProduct('a'))!.stock, 20);
      expect((await repo.getProduct('a'))!.costCents, 300);
    },
  );

  test(
    'same-name scanned products retain separate stock and invoice lines',
    () async {
      await addSameNameProduct();
      final draft = await matcher.resolve([
        PurchaseDraftLine(
          name: 'Screw',
          barcode: 'CODE-A',
          qty: 1,
          unitCostCents: 200,
        ),
      ]);
      appendPurchaseDraftLines(
        draft,
        await matcher.resolve([
          PurchaseDraftLine(
            name: 'Screw',
            barcode: 'CODE-B',
            qty: 1,
            unitCostCents: 200,
          ),
        ]),
      );

      expect(draft.map((line) => line.productId), ['a', 'b']);
      final purchase = await commit(draft);
      expect(purchase['total_cents'], 400);
      expect(jsonDecode(purchase['lines_json'] as String), hasLength(2));
      expect((await repo.getProduct('a'))!.stock, 1);
      expect((await repo.getProduct('b'))!.stock, 1);
    },
  );

  test(
    'unknown distinct codes never fall back to a same-name catalog product',
    () async {
      final draft = await matcher.resolve([
        PurchaseDraftLine(
          name: 'Screw',
          barcode: 'NEW-A',
          qty: 1,
          unitCostCents: 200,
        ),
      ]);
      appendPurchaseDraftLines(
        draft,
        await matcher.resolve([
          PurchaseDraftLine(
            name: 'Screw',
            barcode: 'NEW-B',
            qty: 1,
            unitCostCents: 200,
          ),
        ]),
      );
      expect(draft, hasLength(2));
      expect(
        draft.every((line) => line.willCreate && line.productId == null),
        isTrue,
      );

      await commit(draft);
      expect((await repo.getProduct('a'))!.stock, 0);
      final newA = (await repo.findByBarcodeOrSku('NEW-A'))!;
      final newB = (await repo.findByBarcodeOrSku('NEW-B'))!;
      expect(newA.id, isNot(newB.id));
      expect(newA.stock, 1);
      expect(newB.stock, 1);
    },
  );

  test('a returning cost batch preserves the latest product cost', () async {
    final draft = <PurchaseDraftLine>[];
    for (final cost in [200, 300, 200]) {
      appendPurchaseDraftLines(
        draft,
        await matcher.resolve([
          PurchaseDraftLine(
            name: 'Screw',
            barcode: 'CODE-A',
            qty: 10,
            unitCostCents: cost,
          ),
        ]),
      );
    }
    expect(draft, hasLength(3));
    expect((await commit(draft))['total_cents'], 7000);
    expect((await repo.getProduct('a'))!.stock, 30);
    expect((await repo.getProduct('a'))!.costCents, 200);
  });

  test('manual product ID is retained even when names are identical', () async {
    await addSameNameProduct();
    final draft = await matcher.resolve([
      PurchaseDraftLine(
        name: 'Screw',
        productId: 'b',
        willCreate: false,
        qty: 1,
        unitCostCents: 200,
      ),
    ]);
    expect(draft.single.productId, 'b');
    expect(draft.single.barcode, 'CODE-B');
  });

  test(
    'ambiguous name-only OCR does not silently select the first product',
    () async {
      await addSameNameProduct();
      final draft = await matcher.resolve(
        PurchaseInvoiceTextParser.parse('Screw 1 2.00'),
      );
      expect(draft.single.productId, isNull);
      expect(draft.single.willCreate, isTrue);
    },
  );

  test('repeated scans at the same cost still combine quantities', () async {
    final draft = await matcher.resolve([
      PurchaseDraftLine(
        name: 'Screw',
        barcode: 'CODE-A',
        qty: 1,
        unitCostCents: 200,
      ),
    ]);
    appendPurchaseDraftLines(
      draft,
      await matcher.resolve([
        PurchaseDraftLine(
          name: 'Screw',
          barcode: 'CODE-A',
          qty: 2,
          unitCostCents: 200,
        ),
      ]),
    );
    expect(draft, hasLength(1));
    expect(draft.single.qty, 3);
    expect((await commit(draft))['total_cents'], 600);
    expect((await repo.getProduct('a'))!.stock, 3);
  });

  test('fractional quantities retain each original rounded subtotal', () async {
    final draft = await matcher.resolve([
      PurchaseDraftLine(
        name: 'Screw',
        barcode: 'CODE-A',
        qty: 0.5,
        unitCostCents: 1,
      ),
    ]);
    appendPurchaseDraftLines(
      draft,
      await matcher.resolve([
        PurchaseDraftLine(
          name: 'Screw',
          barcode: 'CODE-A',
          qty: 0.5,
          unitCostCents: 1,
        ),
      ]),
    );
    expect(draft, hasLength(2));
    expect((await commit(draft))['total_cents'], 2);
    expect((await repo.getProduct('a'))!.stock, 1);
  });

  test('new selected quantity is not hidden in an unchecked line', () async {
    final draft = await matcher.resolve([
      PurchaseDraftLine(
        name: 'Screw',
        barcode: 'CODE-A',
        qty: 1,
        unitCostCents: 200,
        selected: false,
      ),
    ]);
    appendPurchaseDraftLines(
      draft,
      await matcher.resolve([
        PurchaseDraftLine(
          name: 'Screw',
          barcode: 'CODE-A',
          qty: 2,
          unitCostCents: 200,
        ),
      ]),
    );
    expect(draft, hasLength(2));
    expect((await commit(draft))['total_cents'], 400);
    expect((await repo.getProduct('a'))!.stock, 2);
  });
}
