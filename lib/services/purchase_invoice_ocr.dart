import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device OCR for paper purchase invoices (best-effort).
/// Android/iOS only; desktop/web returns null.
class PurchaseInvoiceOcr {
  PurchaseInvoiceOcr._();

  static bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  static String get capabilityNote => isSupported
      ? '纸质单据：拍照/选图后用本机 OCR 识别品名、数量、单价（请务必核对）。'
      : '本机 OCR 仅支持 Android/iOS。桌面请：①扫进货单二维码 ②粘贴识别文本 ③用手机拍照识别。';

  static Future<String?> recognizeFile(String imagePath) async {
    if (!isSupported) return null;
    final f = File(imagePath);
    if (!await f.exists()) return null;
    TextRecognizer? recognizer;
    try {
      final input = InputImage.fromFilePath(imagePath);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final latin = (await recognizer.processImage(input)).text.trim();
      await recognizer.close();
      recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final zh = (await recognizer.processImage(input)).text.trim();
      if (latin.isEmpty && zh.isEmpty) return null;
      if (latin.isEmpty) return zh;
      if (zh.isEmpty) return latin;
      final seen = <String>{};
      final buf = StringBuffer();
      for (final line in '$latin\n$zh'.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || !seen.add(t)) continue;
        buf.writeln(t);
      }
      final s = buf.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    } finally {
      await recognizer?.close();
    }
  }
}
