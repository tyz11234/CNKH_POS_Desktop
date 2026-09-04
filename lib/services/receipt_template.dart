import 'dart:convert';

import 'pos_repository.dart';

/// Brand default store name (黄金发宝号).
const String kStoreName = '黄金发宝号';

/// Default 80mm thermal character width (matches prior kReceiptWidth).
const int kDefaultReceiptCharWidth = 40;
const int kReceiptWidth = kDefaultReceiptCharWidth;

const String kDefaultReceiptFooter = 'Thank you / 谢谢光临';

String formatRmPlain(int cents) {
  final sign = cents < 0 ? '-' : '';
  final a = cents.abs();
  return '$sign${'RM'} ${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

/// Settings keys for receipt template (single source of truth).
abstract final class ReceiptSettingKeys {
  static const storeName = 'store_name';
  static const address = 'store_address';
  static const phone = 'store_phone';
  static const header = 'receipt_header';
  static const footer = 'receipt_footer';
  static const notes = 'receipt_notes';
  static const showSku = 'receipt_show_sku';
  static const showCashier = 'receipt_show_cashier';
  static const showDatetime = 'receipt_show_datetime';
  static const showPayment = 'receipt_show_payment';
  static const showChange = 'receipt_show_change';
  static const showDiscount = 'receipt_show_discount';
  static const showUnitPrice = 'receipt_show_unit_price';
  static const showQty = 'receipt_show_qty';
  static const showDuitNowQr = 'receipt_show_duitnow_qr';
  static const charWidth = 'receipt_char_width';
}

/// Editable receipt layout shared by thermal print, e-receipt PDF, and settings preview.
class ReceiptTemplate {
  final String storeName;
  final String address;
  final String phone;
  final String headerLines;
  final String footerLines;
  final String notes;
  final bool showSku;
  final bool showCashier;
  final bool showDatetime;
  final bool showPaymentMethod;
  final bool showChange;
  final bool showDiscount;
  final bool showUnitPrice;
  final bool showQty;
  final bool showDuitNowQr;
  final int charWidth;

  const ReceiptTemplate({
    this.storeName = kStoreName,
    this.address = '',
    this.phone = '',
    this.headerLines = '',
    this.footerLines = kDefaultReceiptFooter,
    this.notes = '',
    this.showSku = true,
    this.showCashier = true,
    this.showDatetime = true,
    this.showPaymentMethod = true,
    this.showChange = true,
    this.showDiscount = true,
    this.showUnitPrice = true,
    this.showQty = true,
    this.showDuitNowQr = false,
    this.charWidth = kDefaultReceiptCharWidth,
  });

  static ReceiptTemplate defaults() => const ReceiptTemplate();

  ReceiptTemplate copyWith({
    String? storeName,
    String? address,
    String? phone,
    String? headerLines,
    String? footerLines,
    String? notes,
    bool? showSku,
    bool? showCashier,
    bool? showDatetime,
    bool? showPaymentMethod,
    bool? showChange,
    bool? showDiscount,
    bool? showUnitPrice,
    bool? showQty,
    bool? showDuitNowQr,
    int? charWidth,
  }) {
    return ReceiptTemplate(
      storeName: storeName ?? this.storeName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      headerLines: headerLines ?? this.headerLines,
      footerLines: footerLines ?? this.footerLines,
      notes: notes ?? this.notes,
      showSku: showSku ?? this.showSku,
      showCashier: showCashier ?? this.showCashier,
      showDatetime: showDatetime ?? this.showDatetime,
      showPaymentMethod: showPaymentMethod ?? this.showPaymentMethod,
      showChange: showChange ?? this.showChange,
      showDiscount: showDiscount ?? this.showDiscount,
      showUnitPrice: showUnitPrice ?? this.showUnitPrice,
      showQty: showQty ?? this.showQty,
      showDuitNowQr: showDuitNowQr ?? this.showDuitNowQr,
      charWidth: charWidth ?? this.charWidth,
    );
  }

  int get width => charWidth.clamp(24, 64);

  static bool _flag(String v, {bool fallback = true}) {
    final t = v.trim().toLowerCase();
    if (t.isEmpty) return fallback;
    return t == '1' || t == 'true' || t == 'yes' || t == 'on';
  }

  static Future<ReceiptTemplate> load(PosRepository repo) async {
    final name = await repo.getSetting(
      ReceiptSettingKeys.storeName,
      fallback: kStoreName,
    );
    final address = await repo.getSetting(ReceiptSettingKeys.address);
    final phone = await repo.getSetting(ReceiptSettingKeys.phone);
    final header = await repo.getSetting(ReceiptSettingKeys.header);
    final footer = await repo.getSetting(
      ReceiptSettingKeys.footer,
      fallback: kDefaultReceiptFooter,
    );
    final notes = await repo.getSetting(ReceiptSettingKeys.notes);
    final widthRaw = await repo.getSetting(
      ReceiptSettingKeys.charWidth,
      fallback: '$kDefaultReceiptCharWidth',
    );
    final width = int.tryParse(widthRaw.trim()) ?? kDefaultReceiptCharWidth;

    Future<bool> flag(String key, {bool fallback = true}) async => _flag(
          await repo.getSetting(key, fallback: fallback ? '1' : '0'),
          fallback: fallback,
        );

    return ReceiptTemplate(
      storeName: name.trim().isEmpty ? kStoreName : name.trim(),
      address: address,
      phone: phone,
      headerLines: header,
      footerLines: footer,
      notes: notes,
      showSku: await flag(ReceiptSettingKeys.showSku),
      showCashier: await flag(ReceiptSettingKeys.showCashier),
      showDatetime: await flag(ReceiptSettingKeys.showDatetime),
      showPaymentMethod: await flag(ReceiptSettingKeys.showPayment),
      showChange: await flag(ReceiptSettingKeys.showChange),
      showDiscount: await flag(ReceiptSettingKeys.showDiscount),
      showUnitPrice: await flag(ReceiptSettingKeys.showUnitPrice),
      showQty: await flag(ReceiptSettingKeys.showQty),
      showDuitNowQr:
          await flag(ReceiptSettingKeys.showDuitNowQr, fallback: false),
      charWidth: width.clamp(24, 64),
    );
  }

  Future<void> save(PosRepository repo) async {
    Future<void> put(String key, String value) => repo.setSetting(key, value);
    Future<void> putFlag(String key, bool v) => put(key, v ? '1' : '0');

    await put(
      ReceiptSettingKeys.storeName,
      storeName.trim().isEmpty ? kStoreName : storeName.trim(),
    );
    await put(ReceiptSettingKeys.address, address.trim());
    await put(ReceiptSettingKeys.phone, phone.trim());
    await put(ReceiptSettingKeys.header, headerLines);
    await put(ReceiptSettingKeys.footer, footerLines);
    await put(ReceiptSettingKeys.notes, notes);
    await put(ReceiptSettingKeys.charWidth, '$width');
    await putFlag(ReceiptSettingKeys.showSku, showSku);
    await putFlag(ReceiptSettingKeys.showCashier, showCashier);
    await putFlag(ReceiptSettingKeys.showDatetime, showDatetime);
    await putFlag(ReceiptSettingKeys.showPayment, showPaymentMethod);
    await putFlag(ReceiptSettingKeys.showChange, showChange);
    await putFlag(ReceiptSettingKeys.showDiscount, showDiscount);
    await putFlag(ReceiptSettingKeys.showUnitPrice, showUnitPrice);
    await putFlag(ReceiptSettingKeys.showQty, showQty);
    await putFlag(ReceiptSettingKeys.showDuitNowQr, showDuitNowQr);
  }

  static Future<void> resetToDefaults(PosRepository repo) async {
    await defaults().save(repo);
  }

  static String truncate(String s, int width) {
    if (s.length <= width) return s;
    return s.substring(0, width);
  }

  static String center(String s, int width) {
    if (s.length >= width) return truncate(s, width);
    final pad = width - s.length;
    final left = pad ~/ 2;
    return (' ' * left) + s + (' ' * (pad - left));
  }

  static String pair(String left, String right, int width) {
    final l = truncate(left, width - 1);
    final r = right;
    final space = width - l.length - r.length;
    if (space < 1) return truncate('$l $r', width);
    return l + (' ' * space) + r;
  }

  void _addCenteredBlock(List<String> out, String block, int w) {
    for (final raw in block.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      out.add(center(line.trim(), w));
    }
  }

  /// Render thermal / monospace receipt text from sale-like fields.
  String render({
    required String receiptNo,
    required String soldAt,
    required String paymentMethod,
    required int subtotalCents,
    required int discountCents,
    required int totalCents,
    required int paidCents,
    required int changeCents,
    required List<Map<String, Object?>> lines,
    String cashier = '',
  }) {
    final w = width;
    final out = <String>[];

    final name = storeName.trim().isEmpty ? kStoreName : storeName.trim();
    out.add(center(name, w));
    if (address.trim().isNotEmpty) {
      _addCenteredBlock(out, address, w);
    }
    if (phone.trim().isNotEmpty) {
      out.add(center(phone.trim(), w));
    }
    if (headerLines.trim().isNotEmpty) {
      _addCenteredBlock(out, headerLines, w);
    }
    out.add('-' * w);
    out.add(truncate('Receipt: $receiptNo', w));
    if (showDatetime) {
      final dt = soldAt.length >= 19
          ? soldAt.substring(0, 19).replaceFirst('T', ' ')
          : soldAt;
      out.add(truncate('Date: $dt', w));
    }
    if (showCashier && cashier.trim().isNotEmpty) {
      out.add(truncate('Cashier: ${cashier.trim()}', w));
    }
    out.add('-' * w);

    for (final line in lines) {
      final nameZh = (line['nameZh'] as String?)?.trim() ?? '';
      final nameEn = (line['nameEn'] as String?)?.trim() ?? '';
      final itemName = nameZh.isNotEmpty
          ? nameZh
          : (nameEn.isNotEmpty ? nameEn : 'Item');
      out.add(truncate(itemName, w));

      if (showSku) {
        final sku = (line['sku'] as String?)?.trim() ?? '';
        final barcode = (line['barcode'] as String?)?.trim() ?? '';
        final code = sku.isNotEmpty ? sku : barcode;
        if (code.isNotEmpty) {
          out.add(truncate('  SKU: $code', w));
        }
      }

      final qtyRaw = line['qty'] ?? 1;
      final qty = qtyRaw is int ? qtyRaw : int.tryParse('$qtyRaw') ?? 1;
      final unit = line['unitPriceCents'] as int? ?? 0;
      final disc = line['lineDiscountCents'] as int? ?? 0;
      final lineTotal = line['lineTotalCents'] as int? ?? (unit * qty);
      final gross = lineTotal + disc;

      final leftParts = <String>[];
      if (showQty) leftParts.add('$qty pcs');
      if (showUnitPrice) leftParts.add('x ${formatRmPlain(unit)}');
      if (leftParts.isEmpty) {
        out.add(pair('  ', formatRmPlain(gross), w));
      } else {
        out.add(pair('  ${leftParts.join(' ')}', formatRmPlain(gross), w));
      }
      if (showDiscount && disc > 0) {
        out.add(pair('  Discount / 折扣', formatRmPlain(-disc), w));
      }
    }

    out.add('-' * w);
    out.add(pair('SUBTOTAL', formatRmPlain(subtotalCents), w));
    if (showDiscount) {
      out.add(pair('DISCOUNT', formatRmPlain(-discountCents), w));
    }
    out.add(pair('TOTAL', formatRmPlain(totalCents), w));
    out.add(pair('PAID', formatRmPlain(paidCents), w));
    if (showChange) {
      out.add(pair('CHANGE', formatRmPlain(changeCents), w));
    }
    if (showPaymentMethod) {
      out.add(truncate('Payment: $paymentMethod', w));
    }
    out.add('-' * w);

    if (footerLines.trim().isNotEmpty) {
      _addCenteredBlock(out, footerLines, w);
    }
    if (notes.trim().isNotEmpty) {
      _addCenteredBlock(out, notes, w);
    }
    if (showDuitNowQr) {
      out.add(center('[DuitNow QR]', w));
      out.add(center('Scan to pay / 扫码付款', w));
    }
    return out.join('\n');
  }

  String renderFromSale(SaleRecord sale) {
    List<Map<String, Object?>> lines = const [];
    try {
      final raw = jsonDecode(sale.linesJson);
      if (raw is List) {
        lines = [
          for (final e in raw)
            if (e is Map)
              {
                for (final entry in e.entries)
                  entry.key.toString(): entry.value as Object?,
              },
        ];
      }
    } catch (_) {}
    final discount = sale.itemDiscountCents + sale.orderDiscountCents;
    return render(
      receiptNo: sale.receiptNo,
      soldAt: sale.soldAt,
      paymentMethod: sale.paymentMethod,
      subtotalCents: sale.subtotalCents,
      discountCents: discount,
      totalCents: sale.totalCents,
      paidCents: sale.paidCents,
      changeCents: sale.changeCents,
      lines: lines,
      cashier: sale.cashier,
    );
  }

  /// Sample sale used by settings live preview.
  static List<Map<String, Object?>> sampleLines() => [
        {
          'nameZh': '螺丝钉 M4',
          'nameEn': 'Screw M4',
          'sku': 'HW-M4-20',
          'barcode': '9551234567890',
          'qty': 2,
          'unitPriceCents': 500,
          'lineDiscountCents': 0,
          'lineTotalCents': 1000,
        },
        {
          'nameZh': '强力胶',
          'nameEn': 'Super glue',
          'sku': 'CH-GLUE-01',
          'barcode': '',
          'qty': 1,
          'unitPriceCents': 850,
          'lineDiscountCents': 50,
          'lineTotalCents': 800,
        },
      ];

  String renderSample() {
    return render(
      receiptNo: 'M20260904-0001',
      soldAt: '2026-09-04T14:30:00.000',
      paymentMethod: 'CASH',
      subtotalCents: 1850,
      discountCents: 50,
      totalCents: 1800,
      paidCents: 2000,
      changeCents: 200,
      lines: sampleLines(),
      cashier: 'Cashier 1',
    );
  }
}
