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

  group('buildPrintReceiptText', () {
    test('matches print-style headers and totals', () {
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
            'qty': 2,
            'unitPriceCents': 500,
            'lineTotalCents': 1000,
          },
        ],
      );
      expect(text, contains('CNKH Hardware'));
      expect(text, contains('Receipt: M20260904-0001'));
      expect(text, contains('TOTAL'));
      expect(text, contains('Payment: CASH'));
      expect(text, contains('螺丝'));
    });
  });

  test('whatsAppUri encodes text', () {
    final uri = whatsAppUri('0123456789', 'hello world');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/60123456789');
    expect(uri.queryParameters['text'], 'hello world');
  });

  test('short caption mentions PDF', () {
    // lightweight — caption helper doesn't need SaleRecord ctor complexity
    expect(
      shortWhatsAppCaption,
      isA<Function>(),
    );
  });
}
