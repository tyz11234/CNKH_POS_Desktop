import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';
import 'pos_repository.dart';

class BarcodeExportResult {
  final List<File> files;
  final List<String> skippedNoBarcode;
  final Map<String, String> failures;

  const BarcodeExportResult({
    required this.files,
    required this.skippedNoBarcode,
    required this.failures,
  });

  bool get isSuccess => files.isNotEmpty && skippedNoBarcode.isEmpty && failures.isEmpty;
  bool get isPartial => files.isNotEmpty && (skippedNoBarcode.isNotEmpty || failures.isNotEmpty);
}

/// Generate barcode PNG with **full product name under the bars**.
/// Uses Flutter canvas so CJK names render (system fonts).
class BarcodeLabelService {
  BarcodeLabelService(this.repo);
  final PosRepository repo;

  Barcode _codecFor(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if ((digits.length == 12 || digits.length == 13) && digits == code) {
      final ean = Barcode.ean13();
      if (ean.isValid(code)) return ean;
    }
    final code128 = Barcode.code128();
    if (!code128.isValid(code)) {
      throw StateError('不支持的条码内容 / Unsupported barcode value');
    }
    return code128;
  }

  Future<String> autoGenerateBarcode() async {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    var base = ts.substring(ts.length - 12);
    int checkDigit(String b) {
      var sum = 0;
      for (var i = 0; i < 12; i++) {
        final d = int.parse(b[i]);
        sum += (i % 2 == 0) ? d : d * 3;
      }
      return (10 - (sum % 10)) % 10;
    }

    var code = '$base${checkDigit(base)}';
    var n = 0;
    while (await repo.findByBarcodeOrSku(code) != null && n < 30) {
      final next =
          (int.parse(base) + 1 + n).toString().padLeft(12, '0').substring(0, 12);
      base = next;
      code = '$base${checkDigit(base)}';
      n++;
    }
    return code;
  }

  /// PNG: real barcode bars + human-readable code + full product name.
  Future<Uint8List> renderPng({
    required String barcode,
    required String productName,
    int width = 640,
    int barHeight = 168,
  }) async {
    final code = barcode.trim();
    if (code.isEmpty) throw StateError('barcode empty');
    final name = productName.trim().isEmpty ? code : productName.trim();

    final codec = _codecFor(code);
    final bars = codec
        .make(
          code,
          width: width.toDouble(),
          height: barHeight.toDouble(),
          drawText: false,
        )
        .whereType<BarcodeBar>()
        .toList(growable: false);
    if (bars.isEmpty) {
      throw StateError('条码生成失败：没有可绘制的条码线条');
    }

    final nameStyle = const TextStyle(
      color: Colors.black,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );
    final namePainter = TextPainter(
      text: TextSpan(text: name, style: nameStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: width - 32.0);

    final codePainter = TextPainter(
      text: TextSpan(
        text: code,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 24.0);

    final footerH = 12 + codePainter.height + 8 + namePainter.height + 16;
    final height = (barHeight + footerH).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );
    final barPaint = Paint()..color = Colors.black;
    for (final bar in bars) {
      canvas.drawRect(
        Rect.fromLTWH(bar.left, bar.top, bar.width, bar.height),
        barPaint,
      );
    }
    var y = barHeight + 12.0;
    codePainter.paint(canvas, Offset((width - codePainter.width) / 2, y));
    y += codePainter.height + 8;
    namePainter.paint(canvas, Offset((width - namePainter.width) / 2, y));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) throw StateError('png encode failed');
    return bd.buffer.asUint8List();
  }

  Future<Directory> _exportDir() async {
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory();
    } catch (_) {
      base = Directory.systemTemp;
    }
    final d = Directory(p.join(base.path, 'barcode_exports'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> exportPngFile(
    Product product, {
    String? directoryPath,
  }) async {
    final code = product.barcode.trim();
    if (code.isEmpty) throw StateError('商品无条码 / Product has no barcode');
    final bytes = await renderPng(barcode: code, productName: product.nameZh);
    final dir = directoryPath == null ? await _exportDir() : Directory(directoryPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = code.replaceAll(RegExp(r'[^\w\-]'), '_');
    final idBit =
        product.id.length >= 8 ? product.id.substring(0, 8) : product.id;
    final file = File(p.join(dir.path, 'barcode_${safe}_$idBit.png'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<List<File>> exportMany(List<Product> products) async {
    final out = <File>[];
    for (final product in products) {
      if (product.barcode.trim().isEmpty) continue;
      out.add(await exportPngFile(product));
    }
    return out;
  }

  /// Windows-oriented batch export with per-item failure reporting. A failed
  /// product never hides successfully written labels and never silently returns.
  Future<BarcodeExportResult> exportManyToDirectory(
    List<Product> products,
    String directoryPath,
  ) async {
    final files = <File>[];
    final skipped = <String>[];
    final failures = <String, String>{};
    final dir = Directory(directoryPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    for (final product in products) {
      if (product.barcode.trim().isEmpty) {
        skipped.add(product.nameZh.isEmpty ? product.id : product.nameZh);
        continue;
      }
      try {
        files.add(await exportPngFile(product, directoryPath: directoryPath));
      } catch (e) {
        failures[product.nameZh.isEmpty ? product.id : product.nameZh] = '$e';
      }
    }
    return BarcodeExportResult(
      files: files,
      skippedNoBarcode: skipped,
      failures: failures,
    );
  }

  Future<void> openFolder(String directoryPath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Open Folder is only available on Windows');
    }
    final result = await Process.run('explorer.exe', [directoryPath]);
    if (result.exitCode != 0) {
      throw FileSystemException('无法打开文件夹 / Failed to open folder', directoryPath);
    }
  }

  Future<void> shareFiles(List<File> files) async {
    if (files.isEmpty) return;
    await Share.shareXFiles(
      [for (final f in files) XFile(f.path, mimeType: 'image/png')],
      subject: 'CNKH barcodes',
      text: '条码图片（条码+完整品名）/ Barcode + full product name',
    );
  }

  Future<void> enqueue(Product product, {int copies = 1}) async {
    if (product.barcode.trim().isEmpty) {
      throw StateError('商品无条码 / Product has no barcode');
    }
    await repo.enqueueBarcodePrint(
      productId: product.id,
      barcode: product.barcode,
      productName: product.nameZh,
      sku: product.sku,
      priceCents: product.priceCents,
      copies: copies,
    );
  }

  Future<void> enqueueMany(List<Product> products, {int copies = 1}) async {
    for (final product in products) {
      if (product.barcode.trim().isEmpty) continue;
      await enqueue(product, copies: copies);
    }
  }
}
