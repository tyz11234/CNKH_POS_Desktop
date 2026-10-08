import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:barcode/barcode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/bluetooth_printer.dart';
import 'package:cnkh_pos_desktop/services/e_receipt.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/receipt_qr.dart';

const _payload = 'CNKH-RECEIPT-QR-REGRESSION-2026';
const _platform = 'desktop';
const _fixtureModules = 29;
const _fixtureScale = 8;

class _Printer implements BluetoothPrinterTransport {
  List<int> bytes = [];
  @override
  bool get supported => true;
  @override
  Future<List<BluetoothInfo>> bondedDevices() async => [];
  @override
  Future<bool> connect(String address) async => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> isConnected() async => true;
  @override
  Future<bool> writeBytes(List<int> value) async {
    bytes = value;
    return true;
  }
}

final _sale = SaleRecord(
  id: 'qr-sale',
  receiptNo: 'QR-OUTPUT',
  soldAt: '2026-10-06T12:00:00',
  cashier: 'Admin',
  paymentMethod: 'QR',
  subtotalCents: 100,
  itemDiscountCents: 0,
  orderDiscountCents: 0,
  roundingCents: 0,
  totalCents: 100,
  paidCents: 100,
  changeCents: 0,
  creditOutstandingCents: 0,
  linesJson:
      '[{"nameEn":"Test item","qty":1,"unitPriceCents":100,"lineTotalCents":100}]',
);

/// Reconstruct exactly the bitmap a GS v 0 thermal printer receives, including
/// packet boundaries, rather than asserting that image bytes are merely present.
img.Image _decodePrinter(List<int> bytes, int width) {
  expect(bytes.take(5), [0x1b, 0x40, 0x1b, 0x61, 0]);
  final rows = <Uint8List>[];
  var offset = 5;
  while (offset < bytes.length - 6) {
    expect(bytes.sublist(offset, offset + 4), [0x1d, 0x76, 0x30, 0]);
    final stride = bytes[offset + 4] + 256 * bytes[offset + 5];
    final height = bytes[offset + 6] + 256 * bytes[offset + 7];
    expect(stride * 8, width);
    expect(height, inInclusiveRange(1, 128));
    offset += 8;
    for (var row = 0; row < height; row++) {
      rows.add(Uint8List.fromList(bytes.sublist(offset, offset + stride)));
      offset += stride;
    }
  }
  expect(bytes.sublist(offset), [0x0a, 0x0a, 0x0a, 0x1d, 0x56, 0]);
  final result = img.Image(width: width, height: rows.length);
  img.fill(result, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < width; x++) {
      if (rows[y][x ~/ 8] & (0x80 >> (x % 8)) != 0) {
        result.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }
  return result;
}

void _expectQrModules(img.Image image, img.Image qr, {int top = 0}) {
  final width = image.width;
  final quiet = (width * 0.14).ceil();
  final available = width - quiet * 2;
  for (var row = 0; row < _fixtureModules; row++) {
    for (var col = 0; col < _fixtureModules; col++) {
      final x = quiet + ((col + 0.5) * available / _fixtureModules).floor();
      final y =
          top + quiet + ((row + 0.5) * available / _fixtureModules).floor();
      expect(
        image.getPixel(x, y).r < 128,
        qr.getPixel(col * _fixtureScale + 4, row * _fixtureScale + 4).r < 128,
        reason: 'QR module $row,$col',
      );
    }
  }
  for (var x = 0; x < width; x++) {
    expect(image.getPixel(x, top).r, 255, reason: 'top quiet zone');
    expect(
      image.getPixel(x, top + width - 1).r,
      255,
      reason: 'bottom quiet zone',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  late File source;
  late img.Image qr;
  late _Printer printer;
  late BluetoothPrinterService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-qr-output-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    printer = _Printer();
    service = BluetoothPrinterService(repo, transport: printer);
    // Version 3 has 29 modules. Render via the existing barcode dependency,
    // intentionally omitting a quiet zone to check that receipt output adds it.
    qr = img.Image(
      width: _fixtureModules * _fixtureScale,
      height: _fixtureModules * _fixtureScale,
    );
    img.fill(qr, color: img.ColorRgb8(255, 255, 255));
    final bars = Barcode.qrCode(
      typeNumber: 3,
      errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
    ).make(_payload, width: qr.width.toDouble(), height: qr.height.toDouble());
    for (final bar in bars.whereType<BarcodeBar>()) {
      if (!bar.black) continue;
      img.fillRect(
        qr,
        x1: bar.left.round(),
        y1: bar.top.round(),
        x2: (bar.left + bar.width).round() - 1,
        y2: (bar.top + bar.height).round() - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
    source = await File(
      '${temp.path}/payment.png',
    ).writeAsBytes(img.encodePng(qr));
    SharedPreferences.setMockInitialValues({
      'duitnow_qr_local_path': source.path,
    });
    await repo.setSetting('bt_printer_enabled', '1');
    await const ReceiptTemplate(showDuitNowQr: true).save(repo);
  });

  tearDown(() async {
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });

  test(
    'actual print entry includes the configured QR at both printer widths',
    () async {
      for (final width in [384, 576]) {
        await repo.setSetting('bt_printer_width_dots', '$width');
        expect(await service.tryPrintSale(_sale), 'ok');
        final printed = _decodePrinter(printer.bytes, width);
        _expectQrModules(printed, qr, top: printed.height - width);
        final artifactDir = Platform.environment['CNKH_QR_ARTIFACT_DIR'];
        if (artifactDir != null) {
          await Directory(artifactDir).create(recursive: true);
          await File(
            '$artifactDir/$_platform-escpos-$width.png',
          ).writeAsBytes(img.encodePng(printed));
        }
      }
    },
  );

  test(
    'PDF contains the configured image and produces a renderable QR',
    () async {
      final file = await writeReceiptPdfTemp(_sale, repo: repo);
      final prefix = '${temp.path}/embedded';
      final extract = await Process.run('pdfimages', [
        '-png',
        file.path,
        prefix,
      ]);
      expect(extract.exitCode, 0, reason: '${extract.stderr}');
      final embedded = img.decodeImage(
        await File('$prefix-000.png').readAsBytes(),
      )!;
      expect(embedded.width, 768);
      expect(embedded.height, 768);
      _expectQrModules(embedded, qr);
      final artifactDir = Platform.environment['CNKH_QR_ARTIFACT_DIR'];
      if (artifactDir != null) {
        await Directory(artifactDir).create(recursive: true);
        await file.copy('$artifactDir/$_platform-qr.pdf');
        final rendered = await Process.run('pdftoppm', [
          '-f',
          '1',
          '-l',
          '1',
          '-singlefile',
          '-png',
          '-r',
          '203',
          file.path,
          '$artifactDir/$_platform-pdf',
        ]);
        expect(rendered.exitCode, 0, reason: '${rendered.stderr}');
      }
    },
  );

  test(
    'disabled, absent and corrupt QR images leave a usable receipt without image or scan caption',
    () async {
      await const ReceiptTemplate(showDuitNowQr: false).save(repo);
      expect(await service.tryPrintSale(_sale), 'ok');
      final disabledPrint = List<int>.of(printer.bytes);
      final disabledPdf = await writeReceiptPdfTemp(_sale, repo: repo);
      final disabledPdfBytes = await disabledPdf.readAsBytes();
      expect(
        String.fromCharCodes(disabledPdfBytes),
        isNot(matches(RegExp(r'/Subtype\s*/Image'))),
      );

      await const ReceiptTemplate(showDuitNowQr: true).save(repo);
      for (final corrupt in [false, true]) {
        if (corrupt) {
          await source.writeAsString('this is not an image');
        } else {
          await source.delete();
        }
        expect(await ReceiptQrImage.load(), isNull);
        expect(await service.tryPrintSale(_sale), 'ok');
        expect(printer.bytes, disabledPrint);
        final file = await writeReceiptPdfTemp(_sale, repo: repo);
        expect(
          String.fromCharCodes(await file.readAsBytes()),
          isNot(matches(RegExp(r'/Subtype\s*/Image'))),
        );
        final text = await Process.run('pdftotext', [file.path, '-']);
        expect(text.exitCode, 0);
        expect(text.stdout, isNot(contains('Scan to pay')));
        expect(text.stdout, isNot(contains('[DuitNow QR]')));
      }
    },
  );

  test(
    'rectangular transparent images retain proportions on a white canvas',
    () async {
      final rectangular = img.Image(width: 200, height: 100, numChannels: 4);
      img.fill(rectangular, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(
        rectangular,
        x1: 50,
        y1: 25,
        x2: 149,
        y2: 74,
        color: img.ColorRgba8(0, 0, 0, 255),
      );
      await source.writeAsBytes(img.encodePng(rectangular));
      final image = (await ReceiptQrImage.load())!.raster(widthDots: 384);
      expect(image.width, 384);
      expect(image.height, 246);
      expect(image.getPixel(32, 32).r, 255);
      expect(image.getPixel(192, 111).r, 0);
      expect(image.getPixel(192, 111).a, 255);
    },
  );
}
