import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/services/e_receipt.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-receipt-render-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });

  test(
    '100 and 300 long Chinese item rows render into paged 80mm PDFs',
    () async {
      for (final count in [100, 300]) {
        final lines = [
          for (var i = 0; i < count; i++)
            {
              'nameZh': '中文商品${i.toString().padLeft(3, '0')}超长名称垫圈螺丝配件',
              'nameEn': 'Long hardware item $i',
              'sku': 'SKU-$i',
              'qty': 1,
              'unitPriceCents': 125,
              'lineTotalCents': 125,
            },
        ];
        final sale = SaleRecord(
          id: 'receipt-$count',
          receiptNo: 'TEST-$count',
          soldAt: '2026-10-03T12:00:00Z',
          cashier: '收银员 Admin',
          paymentMethod: 'CASH',
          subtotalCents: count * 125,
          itemDiscountCents: 0,
          orderDiscountCents: 0,
          roundingCents: 0,
          totalCents: count * 125,
          paidCents: count * 125,
          changeCents: 0,
          creditOutstandingCents: 0,
          linesJson: jsonEncode(lines),
        );
        final file = await writeReceiptPdfTemp(
          sale,
          template: const ReceiptTemplate(
            storeName: '黄金发宝号',
            footerLines: '谢谢光临 · 中文页脚',
            notes: '备注：请核对商品与数量 · Receipt note',
          ),
        );
        expect(await file.length(), greaterThan(10000));
        final info = await Process.run('pdfinfo', [file.path]);
        expect(info.exitCode, 0, reason: '${info.stderr}');
        final pageMatch = RegExp(
          r'Pages:\s+(\d+)',
        ).firstMatch(info.stdout as String);
        expect(pageMatch, isNotNull);
        expect(int.parse(pageMatch!.group(1)!), greaterThan(1));

        final extracted = await Process.run('pdftotext', [
          '-enc',
          'UTF-8',
          file.path,
          '-',
        ], stdoutEncoding: utf8);
        expect(extracted.exitCode, 0, reason: '${extracted.stderr}');
        expect(extracted.stdout, contains('中文商品000'));
        expect(extracted.stdout, contains('中文页脚'));
        expect(extracted.stdout, contains('备注：请核对商品与数量'));

        final fonts = await Process.run('pdffonts', [file.path]);
        expect(fonts.exitCode, 0, reason: '${fonts.stderr}');
        expect(fonts.stdout.toString(), contains('NotoSansSC'));
        final outputPrefix = '${temp.path}/receipt-$count-page1';
        final render = await Process.run('pdftoppm', [
          '-f',
          '1',
          '-l',
          '1',
          '-singlefile',
          '-png',
          '-scale-to',
          '1000',
          file.path,
          outputPrefix,
        ]);
        expect(render.exitCode, 0, reason: '${render.stderr}');
        expect(await File('$outputPrefix.png').length(), greaterThan(1000));

        final artifactDir = Platform.environment['CNKH_PDF_ARTIFACT_DIR'];
        if (artifactDir != null && artifactDir.isNotEmpty) {
          final out = Directory(artifactDir);
          await out.create(recursive: true);
          await file.copy('${out.path}/desktop-$count.pdf');
          await File(
            '$outputPrefix.png',
          ).copy('${out.path}/desktop-$count.png');
        }
      }
    },
  );
}
