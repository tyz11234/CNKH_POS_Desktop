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
import 'receipt_template.dart';

export 'receipt_template.dart'
    show
        ReceiptTemplate,
        ReceiptSettingKeys,
        kStoreName,
        kReceiptWidth,
        kDefaultReceiptCharWidth,
        kDefaultReceiptFooter,
        formatRmPlain;

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

/// Thermal / preview text via [ReceiptTemplate] (single source of truth).
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
  String footer = kDefaultReceiptFooter,
  String notes = '',
  ReceiptTemplate? template,
}) {
  final effective = template ??
      ReceiptTemplate(
        storeName: storeName,
        address: address,
        phone: phone,
        footerLines: footer,
        notes: notes,
      );
  return effective.render(
    receiptNo: receiptNo,
    soldAt: soldAt,
    paymentMethod: paymentMethod,
    subtotalCents: subtotalCents,
    discountCents: discountCents,
    totalCents: totalCents,
    paidCents: paidCents,
    changeCents: changeCents,
    lines: lines,
    cashier: cashier,
  );
}

String buildPrintReceiptTextFromSale(
  SaleRecord sale, {
  String storeName = kStoreName,
  ReceiptTemplate? template,
}) {
  final effective = template ??
      ReceiptTemplate(storeName: storeName.isEmpty ? kStoreName : storeName);
  return effective.renderFromSale(sale);
}

/// Load persisted template then render sale (print + PDF path).
Future<String> buildPrintReceiptTextFromSaleAsync(
  SaleRecord sale, {
  PosRepository? repo,
  String? storeNameOverride,
}) async {
  final r = repo ?? PosRepository();
  var template = await ReceiptTemplate.load(r);
  if (storeNameOverride != null && storeNameOverride.trim().isNotEmpty) {
    template = template.copyWith(storeName: storeNameOverride.trim());
  }
  return template.renderFromSale(sale);
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

pw.Font? _receiptPdfFont;

Future<pw.Font> _loadReceiptPdfFont() async {
  if (_receiptPdfFont != null) return _receiptPdfFont!;
  final data = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
  _receiptPdfFont = pw.Font.ttf(data);
  return _receiptPdfFont!;
}

Future<File> writeReceiptPdfTemp(
  SaleRecord sale, {
  String storeName = kStoreName,
  ReceiptTemplate? template,
  PosRepository? repo,
}) async {
  final ReceiptTemplate effective;
  if (template != null) {
    effective = template;
  } else if (repo != null) {
    effective = await ReceiptTemplate.load(repo);
  } else {
    effective = ReceiptTemplate(
      storeName: storeName.isEmpty ? kStoreName : storeName,
    );
  }
  final text = effective.renderFromSale(sale);
  final font = await _loadReceiptPdfFont();
  final doc = pw.Document();
  // 80mm thermal-ish page width — Noto Sans SC embeds CJK (Courier cannot)
  const pageWidth = 80.0 * PdfPageFormat.mm;
  final lines = text.split('\n');
  final pageHeight = (lines.length * 12.0 + 40).clamp(200.0, 2000.0);
  final style = pw.TextStyle(
    font: font,
    fontSize: 7.5,
    lineSpacing: 1.2,
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(pageWidth, pageHeight, marginAll: 4 * PdfPageFormat.mm),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            pw.Text(line, style: style),
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
  ReceiptTemplate? template,
  PosRepository? repo,
}) async {
  final dir = await eReceiptCacheDir();
  final safe = sale.receiptNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/receipt_$safe.pdf');
  final tmp = await writeReceiptPdfTemp(
    sale,
    storeName: storeName,
    template: template,
    repo: repo,
  );
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
/// - **Windows**: open WhatsApp Desktop (`whatsapp://send`) and put PDF on clipboard
///   (CF_HDROP) so user can Ctrl+V into the chat.
/// - **Fallback**: system share sheet only if channel fails / WhatsApp missing.
/// PDF stays in 7-day cache; never deleted right after share.
Future<String> shareEReceiptPdf({
  required SaleRecord sale,
  required String phoneRaw,
  String storeName = kStoreName,
  ReceiptTemplate? template,
  PosRepository? repo,
}) async {
  final digits = normalizeMyPhone(phoneRaw);
  if (digits.isEmpty) throw ArgumentError('invalid phone');
  final pdf = await writeReceiptPdfCached(
    sale,
    storeName: storeName,
    template: template,
    repo: repo,
  );
  final caption = shortWhatsAppCaption(sale, storeName: storeName);

  final useNativeChannel = !kIsWeb &&
      (Platform.isAndroid || Platform.isWindows || Platform.isLinux);
  if (useNativeChannel) {
    try {
      if (Platform.isLinux) {
        // Best-effort: open WhatsApp protocol; PDF path shown in caption hint.
        final uri =
            'whatsapp://send?phone=$digits&text=${Uri.encodeComponent(caption)}';
        final r = await Process.run('xdg-open', [uri], runInShell: false);
        if (r.exitCode == 0) {
          return '已打开 WhatsApp（Linux）。请手动附加 PDF：\n${pdf.path}\n'
              'Opened WhatsApp. Attach PDF manually:\n${pdf.path}';
        }
      } else {
        const channel = MethodChannel(kWhatsAppShareChannel);
        final ok = await channel.invokeMethod<bool>('sharePdf', {
          'path': pdf.path,
          'text': caption,
          'phone': digits,
        });
        if (ok == true) {
          if (Platform.isWindows) {
            return '已打开 WhatsApp，PDF 已复制到剪贴板 — 在聊天中按 Ctrl+V 粘贴附件。'
                '文件已缓存 7 天。\n'
                'Opened WhatsApp; PDF on clipboard — press Ctrl+V in chat to attach. '
                'Cached 7 days.';
          }
          return '已打开 WhatsApp（PDF 已附加）。文件已缓存 7 天。\n'
              'Opened WhatsApp with PDF attached. Cached 7 days.';
        }
      }
    } catch (_) {
      // Fall through to system share if WhatsApp missing / channel error.
    }
  }

  // Fallback: Share.shareXFiles only — never wa.me alone (no file attach).
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
