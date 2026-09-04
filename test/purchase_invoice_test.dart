import 'package:cnkh_pos_desktop/services/purchase_invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PurchaseInvoicePayload', () {
    test('parses CNKHPO1 prefix with name qty price', () {
      const raw =
          'CNKHPO1:{"v":1,"type":"cnkh_purchase","supplier":"五金行","lines":[{"name":"螺丝M6","qty":100,"price":0.15,"barcode":"123"}]}';
      final p = PurchaseInvoicePayload.tryParse(raw);
      expect(p, isNotNull);
      expect(p!.supplierName, '五金行');
      expect(p.lines, hasLength(1));
      expect(p.lines.first.name, '螺丝M6');
      expect(p.lines.first.qty, 100);
      expect(p.lines.first.unitCostCents, 15);
      expect(p.lines.first.barcode, '123');
    });

    test('parses costCents override', () {
      const raw =
          '{"v":1,"lines":[{"name":"A","qty":2,"costCents":250,"sku":"SKU1"}]}';
      final p = PurchaseInvoicePayload.tryParse(raw);
      expect(p!.lines.first.unitCostCents, 250);
      expect(p.lines.first.sku, 'SKU1');
    });

    test('round-trip encode', () {
      final payload = PurchaseInvoicePayload(
        supplierName: 'S',
        lines: [
          PurchaseDraftLine(name: 'N', qty: 3, unitCostCents: 100, barcode: 'B'),
        ],
      );
      final again = PurchaseInvoicePayload.tryParse(payload.encode());
      expect(again!.lines.first.unitCostCents, 100);
      expect(again.supplierName, 'S');
    });

    test('rejects empty lines', () {
      expect(PurchaseInvoicePayload.tryParse('{"v":1,"lines":[]}'), isNull);
    });
  });

  group('normalizeProductName', () {
    test('strips spaces and punct', () {
      expect(normalizeProductName(' 螺丝 · M6 '), normalizeProductName('螺丝M6'));
    });
  });

  group('PurchaseInvoiceTextParser', () {
    test('parses name qty price rows', () {
      const text = '''
品名 数量 单价
螺丝M6 100 0.15
水泥钉 x20 RM2.30
''';
      final lines = PurchaseInvoiceTextParser.parse(text);
      expect(lines.length, greaterThanOrEqualTo(2));
      final a = lines.firstWhere((e) => e.name.contains('螺丝'));
      expect(a.qty, 100);
      expect(a.unitCostCents, 15);
      final b = lines.firstWhere((e) => e.name.contains('水泥'));
      expect(b.qty, 20);
      expect(b.unitCostCents, 230);
    });
  });
}
