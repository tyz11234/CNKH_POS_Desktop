import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pos_repository.dart';

const String kStoreName = '黄金发宝号';
const int kReceiptWidth = 40;
const String kEReceiptCacheDirKey = 'ereceipt_cache_dir';
const String kWhatsAppShareChannel = 'com.cnkh.cnkh_pos_desktop/whatsapp_share';

/// Strip spaces/dashes; MY local `0…` → `60…`. Returns digits only or ''.
String normalizeMyPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.startsWith('+')) {
    digits = digits.substring(1);
  }
  digits = digits.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('0') && digits.length >= 9) {
    digits = '60${digits.substring(1)}';
  }
  return digits;
}

String formatRmPlain(int cents) {
  final sign = cents < 0 ? '-' : '';
  final a = cents.abs();
  return '$sign${'RM'} ${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

String _truncate(String s, int width) {
  if (s.length <= width) return s;
  return s.substring(0, width);
}

String _center(String s, int width) {
  if (s.length >= width) return _truncate(s, width);
  final pad = width - s.length;
  final left = pad ~/ 2;
  return (' ' * left) + s + (' ' * (pad - left));
}

String _pair(String left, String right, int width) {
  final l = _truncate(left, width - 1);
  final r = right;
  final space = width - l.length - r.length;
  if (space < 1) return _truncate('$l $r', width);
  return l + (' ' * space) + r;
}

/// 40-col thermal text matching PC ``PrintingService.render_text``.
String buildPrintReceiptText({
  required String receiptNo,
  required String soldAt,
  required String paymentMethod,
  required int subtotalCents,
  required int discountCents,
  required int totalCents,
  required int paidCents,
  required int changeCents,
  required List<Map<String, Object?>> lines,
  String storeName = kStoreName,
  String cashier = '',
  String address = '',
  String phone = '',
  String footer = 'Thank you / 谢谢光临',
  String notes = '',
}) {
  final w = kReceiptWidth;
  final out = <String>[];
  out.add(_center(storeName, w));
  if (address.trim().isNotEmpty) out.add(_center(address.trim(), w));
  if (phone.trim().isNotEmpty) out.add(_center(phone.trim(), w));
  out.add('-' * w);
  out.add(_truncate('Receipt: $receiptNo', w));
  final dt = soldAt.length >= 19
      ? soldAt.substring(0, 19).replaceFirst('T', ' ')
      : soldAt;
  out.add(_truncate('Date: $dt', w));
  if (cashier.isNotEmpty) out.add(_truncate('Cashier: $cashier', w));
  out.add('-' * w);
  for (final line in lines) {
    final nameZh = (line['nameZh'] as String?)?.trim() ?? '';
    final nameEn = (line['nameEn'] as String?)?.trim() ?? '';
    final name = nameZh.isNotEmpty
        ? nameZh
        : (nameEn.isNotEmpty ? nameEn : 'Item');
    out.add(_truncate(name, w));
    final qty = line['qty'] ?? 1;
    final unit = line['unitPriceCents'] as int? ?? 0;
    final qtyStr = '$qty';
    final lineTotal = line['lineTotalCents'] as int? ??
        (unit * (qty is int ? qty : int.tryParse('$qty') ?? 1));
    final disc = line['lineDiscountCents'] as int? ?? 0;
    final detail = '  $qtyStr pcs x ${formatRmPlain(unit)}';
    out.add(_pair(detail, formatRmPlain(lineTotal + disc), w));
    if (disc > 0) {
      out.add(_pair('  Discount / 折扣', formatRmPlain(-disc), w));
    }
  }
  out.add('-' * w);
  out.add(_pair('SUBTOTAL', formatRmPlain(subtotalCents), w));
  out.add(_pair('DISCOUNT', formatRmPlain(-discountCents), w));
  out.add(_pair('TOTAL', formatRmPlain(totalCents), w));
  out.add(_pair('PAID', formatRmPlain(paidCents), w));
  out.add(_pair('CHANGE', formatRmPlain(changeCents), w));
  out.add(_truncate('Payment: $paymentMethod', w));
  out.add('-' * w);
  if (footer.trim().isNotEmpty) out.add(_center(footer.trim(), w));
  if (notes.trim().isNotEmpty) out.add(_center(notes.trim(), w));
  return out.join('\n');
}

String buildPrintReceiptTextFromSale(SaleRecord sale, {String storeName = kStoreName}) {
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
  final discount =
      sale.itemDiscountCents + sale.orderDiscountCents;
  return buildPrintReceiptText(
    receiptNo: sale.receiptNo,
    soldAt: sale.soldAt,
    paymentMethod: sale.paymentMethod,
    subtotalCents: sale.subtotalCents,
    discountCents: discount,
    totalCents: sale.totalCents,
    paidCents: sale.paidCents,
    changeCents: sale.changeCents,
    lines: lines,
    storeName: storeName,
    cashier: sale.cashier,
  );
}

String shortWhatsAppCaption(SaleRecord sale, {String storeName = kStoreName}) =>
    '$storeName\n'
    '电子收据 PDF / E-Receipt PDF\n'
    '单号 / No: ${sale.receiptNo}\n'
    '请查看附件收据 / Please see attached receipt PDF.';

/// Legacy short builder kept for unit tests / caption helpers.
String buildEReceiptText({
  required String receiptNo,
  required String soldAt,
  required String paymentMethod,
  required int totalCents,
  required List<Map<String, Object?>> lines,
  String storeName = kStoreName,
  String? customerName,
}) {
  return buildPrintReceiptText(
    receiptNo: receiptNo,
    soldAt: soldAt,
    paymentMethod: paymentMethod,
    subtotalCents: totalCents,
    discountCents: 0,
    totalCents: totalCents,
    paidCents: totalCents,
    changeCents: 0,
    lines: lines,
    storeName: storeName,
  );
}

String buildEReceiptTextFromSale(SaleRecord sale) =>
    buildPrintReceiptTextFromSale(sale);

Future<File> writeReceiptPdfTemp(
  SaleRecord sale, {
  String storeName = kStoreName,
}) async {
  final text = buildPrintReceiptTextFromSale(sale, storeName: storeName);
  final doc = pw.Document();
  // 80mm thermal-ish page width
  const pageWidth = 80.0 * PdfPageFormat.mm;
  final lines = text.split('\n');
  final pageHeight = (lines.length * 12.0 + 40).clamp(200.0, 2000.0);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(pageWidth, pageHeight, marginAll: 4 * PdfPageFormat.mm),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            pw.Text(
              line,
              style: pw.TextStyle(
                font: pw.Font.courier(),
                fontSize: 7.5,
                lineSpacing: 1.2,
              ),
            ),
        ],
      ),
    ),
  );
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/cnkh_receipt_${sale.receiptNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
  );
  await file.writeAsBytes(await doc.save(), flush: true);
  return file;
}

Uri whatsAppUri(String phoneDigits, String text) {
  final digits = normalizeMyPhone(phoneDigits);
  final encoded = Uri.encodeComponent(text);
  return Uri.parse('https://wa.me/$digits?text=$encoded');
}

Future<String> maybeEnsureContact({
  required String name,
  required String phoneRaw,
}) async {
  if (kIsWeb) return 'Web: skip contacts';
  try {
    if (Platform.isLinux) {
      return '此设备无通讯录写入 / Desktop: skip contacts';
    }
  } catch (_) {}

  final digits = normalizeMyPhone(phoneRaw);
  if (digits.isEmpty) return '';

  try {
    final granted = await FlutterContacts.requestPermission(readonly: false);
    if (!granted) {
      return '未授权通讯录，仍可通过 WhatsApp 发送 / Contacts denied — WhatsApp still opens';
    }
    final existing = await FlutterContacts.getContacts(withProperties: true);
    final wanted = digits;
    final alt = digits.startsWith('60') ? '0${digits.substring(2)}' : digits;
    for (final c in existing) {
      for (final p in c.phones) {
        final n = normalizeMyPhone(p.number);
        if (n == wanted || n == normalizeMyPhone(alt)) {
          return '';
        }
      }
    }
    final contact = Contact()
      ..name = Name(first: name.trim().isEmpty ? digits : name.trim())
      ..phones = [Phone(phoneRaw.trim().isEmpty ? digits : phoneRaw.trim())];
    await FlutterContacts.insertContact(contact);
    return '已创建联系人 / Contact saved';
  } catch (e) {
    return '通讯录跳过 / Contacts skipped: $e';
  }
}

/// App-private e-receipt PDF cache (not public gallery). Keep 7 days.
const Duration kEReceiptCacheTtl = Duration(days: 7);

/// Default cache under application support (when setting empty).
Future<String> defaultEReceiptCachePath() async {
  final root = await getApplicationSupportDirectory();
  return '${root.path}/e_receipt_cache';
}

/// Reads `ereceipt_cache_dir` from SQLite settings, else app support/e_receipt_cache.
Future<Directory> eReceiptCacheDir() async {
  String custom = '';
  try {
    custom = (await PosRepository().getSetting(kEReceiptCacheDirKey)).trim();
  } catch (_) {}
  final path = custom.isNotEmpty ? custom : await defaultEReceiptCachePath();
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Delete cached PDFs older than [kEReceiptCacheTtl]. Returns deleted count.
Future<int> purgeEReceiptCache({Duration ttl = kEReceiptCacheTtl}) async {
  final dir = await eReceiptCacheDir();
  final cutoff = DateTime.now().subtract(ttl);
  var n = 0;
  await for (final ent in dir.list()) {
    if (ent is! File) continue;
    if (!ent.path.toLowerCase().endsWith('.pdf')) continue;
    try {
      final st = await ent.stat();
      if (st.modified.isBefore(cutoff)) {
        await ent.delete();
        n++;
      }
    } catch (_) {}
  }
  return n;
}

/// Delete all cached e-receipt PDFs. Returns deleted count.
Future<int> clearEReceiptCache() async {
  final dir = await eReceiptCacheDir();
  var n = 0;
  await for (final ent in dir.list()) {
    if (ent is! File) continue;
    if (!ent.path.toLowerCase().endsWith('.pdf')) continue;
    try {
      await ent.delete();
      n++;
    } catch (_) {}
  }
  return n;
}

Future<int> countEReceiptCache() async {
  final dir = await eReceiptCacheDir();
  var n = 0;
  await for (final ent in dir.list()) {
    if (ent is File && ent.path.toLowerCase().endsWith('.pdf')) n++;
  }
  return n;
}

/// Write PDF into private cache. Filename is stable per receipt.
/// Does **not** delete after share — purge old files on startup / explicitly.
Future<File> writeReceiptPdfCached(
  SaleRecord sale, {
  String storeName = kStoreName,
}) async {
  final dir = await eReceiptCacheDir();
  final safe = sale.receiptNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/receipt_$safe.pdf');
  final tmp = await writeReceiptPdfTemp(sale, storeName: storeName);
  try {
    await tmp.copy(file.path);
  } finally {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }
  return file;
}

/// Share e-receipt PDF:
/// - **Android**: open WhatsApp directly with PDF attached (ACTION_SEND + EXTRA_STREAM).
/// - **Other platforms**: system share sheet only (no wa.me — cannot attach PDF).
/// PDF stays in 7-day cache; never deleted right after share.
Future<String> shareEReceiptPdf({
  required SaleRecord sale,
  required String phoneRaw,
  String storeName = kStoreName,
}) async {
  final digits = normalizeMyPhone(phoneRaw);
  if (digits.isEmpty) throw ArgumentError('invalid phone');
  final pdf = await writeReceiptPdfCached(sale, storeName: storeName);
  final caption = shortWhatsAppCaption(sale, storeName: storeName);

  if (!kIsWeb && Platform.isAndroid) {
    try {
      const channel = MethodChannel(kWhatsAppShareChannel);
      final ok = await channel.invokeMethod<bool>('sharePdf', {
        'path': pdf.path,
        'text': caption,
        'phone': digits,
      });
      if (ok == true) {
        return '已打开 WhatsApp（PDF 已附加）。文件已缓存 7 天。\n'
            'Opened WhatsApp with PDF attached. Cached 7 days.';
      }
    } catch (_) {
      // Fall through to system share if WhatsApp missing / channel error.
    }
  }

  // Non-Android (or Android fallback): Share.shareXFiles only — never wa.me after.
  await Share.shareXFiles(
    [
      XFile(
        pdf.path,
        mimeType: 'application/pdf',
        name: 'CNKH_${sale.receiptNo}.pdf',
      ),
    ],
    text: caption,
    subject: 'E-Receipt ${sale.receiptNo}',
  );
  return '已打开系统分享（请选 WhatsApp 发送 PDF）。文件已缓存 7 天。\n'
      'Shared via system sheet — pick WhatsApp. PDF cached 7 days.';
}

Future<bool> openWhatsApp({
  required String phoneRaw,
  required String text,
}) async {
  final digits = normalizeMyPhone(phoneRaw);
  if (digits.isEmpty) return false;
  final uri = whatsAppUri(digits, text);
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return launchUrl(uri, mode: LaunchMode.platformDefault);
}
