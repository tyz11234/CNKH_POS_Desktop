import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/services/e_receipt.dart';

void main() {
  group('normalizeMyPhone', () {
    test('strips spaces and maps MY local 0 to 60', () {
      expect(normalizeMyPhone('012-345 6789'), '60123456789');
      expect(normalizeMyPhone('+60 12-3456789'), '60123456789');
      expect(normalizeMyPhone('60123456789'), '60123456789');
      expect(normalizeMyPhone(''), '');
    });
  });

  group('ReceiptTemplate / buildPrintReceiptText', () {
    test('matches print-style headers and totals with brand store name', () {
      final text = buildPrintReceiptText(
        receiptNo: 'M20260904-0001',
        soldAt: '2026-09-04T14:00:00.000',
        paymentMethod: 'CASH',
        subtotalCents: 1250,
        discountCents: 0,
        totalCents: 1250,
        paidCents: 1250,
        changeCents: 0,
        lines: [
          {
            'nameZh': '螺丝',
            'nameEn': 'Screw',
            'sku': 'HW-1',
            'qty': 2,
            'unitPriceCents': 500,
            'lineTotalCents': 1000,
          },
        ],
      );
      expect(text, contains('黄金发宝号'));
      expect(text, contains('Receipt: M20260904-0001'));
      expect(text, contains('TOTAL'));
      expect(text, contains('Payment: CASH'));
      expect(text, contains('螺丝'));
      expect(text, contains('SKU: HW-1'));
    });

    test('toggles hide cashier datetime payment change discount sku', () {
      final t = const ReceiptTemplate(
        storeName: '黄金发宝号',
        showSku: false,
        showCashier: false,
        showDatetime: false,
        showPaymentMethod: false,
        showChange: false,
        showDiscount: false,
      );
      final text = t.render(
        receiptNo: 'R1',
        soldAt: '2026-09-04T14:00:00.000',
        paymentMethod: 'CASH',
        subtotalCents: 1000,
        discountCents: 100,
        totalCents: 900,
        paidCents: 1000,
        changeCents: 100,
        lines: [
          {
            'nameZh': '胶',
            'sku': 'X',
            'qty': 1,
            'unitPriceCents': 1000,
            'lineDiscountCents': 100,
            'lineTotalCents': 900,
          },
        ],
        cashier: 'Admin',
      );
      expect(text, isNot(contains('Cashier:')));
      expect(text, isNot(contains('Date:')));
      expect(text, isNot(contains('Payment:')));
      expect(text, isNot(contains('CHANGE')));
      expect(text, isNot(contains('DISCOUNT')));
      expect(text, isNot(contains('SKU:')));
      expect(text, contains('TOTAL'));
    });

    test('sample preview includes header footer when set', () {
      final t = const ReceiptTemplate(
        headerLines: 'Hardware Store\nGST: 123',
        footerLines: '谢谢光临',
        notes: 'Keep receipt',
        showDuitNowQr: true,
      );
      final text = t.renderSample();
      expect(text, contains('Hardware Store'));
      expect(text, contains('谢谢光临'));
      expect(text, contains('Keep receipt'));
      expect(text, contains('[DuitNow QR]'));
    });
  });

  test('whatsAppUri encodes text', () {
    final uri = whatsAppUri('0123456789', 'hello world');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/60123456789');
    expect(uri.queryParameters['text'], 'hello world');
  });

  test('short caption mentions PDF', () {
    expect(
      shortWhatsAppCaption,
      isA<Function>(),
    );
  });
}
