import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/e_receipt.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase database;
  late PosRepository repo;
  final sharedFiles = <Map<Object?, Object?>>[];
  var nativeUnavailable = false;

  setUp(() async {
    AppDatabase.ensureFfi();
    root = await Directory.systemTemp.createTemp('cnkh-windows-share-');
    database = AppDatabase.forTesting('${root.path}/desktop.db', seed: false);
    repo = PosRepository(database: database);
    await repo.setSetting(kEReceiptCacheDirKey, '${root.path}/cache');
    sharedFiles.clear();
    nativeUnavailable = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(kWhatsAppShareChannel),
      (call) async {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        expect(await File(args['path'] as String).exists(), isTrue);
        if (nativeUnavailable) {
          throw MissingPluginException('WhatsApp unavailable');
        }
        return false; // Clipboard/native delivery failed after app launch attempt.
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        expect(call.method, 'shareFiles');
        sharedFiles.add(Map<Object?, Object?>.from(call.arguments as Map));
        return 'success';
      },
    );
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(kWhatsAppShareChannel),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      null,
    );
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'false native clipboard result and missing WhatsApp both share the cached PDF',
    () async {
      final sale = SaleRecord(
        id: 's1',
        receiptNo: '收据-中文-001',
        soldAt: '2026-10-03T12:00:00Z',
        cashier: 'admin',
        paymentMethod: 'CASH',
        subtotalCents: 100,
        itemDiscountCents: 0,
        orderDiscountCents: 0,
        roundingCents: 0,
        totalCents: 100,
        paidCents: 100,
        changeCents: 0,
        creditOutstandingCents: 0,
        linesJson: jsonEncode([
          {
            'nameZh': '中文商品',
            'qty': 1,
            'unitPriceCents': 100,
            'lineTotalCents': 100,
          },
        ]),
      );

      for (final unavailable in [false, true]) {
        nativeUnavailable = unavailable;
        final result = await shareEReceiptPdf(
          sale: sale,
          phoneRaw: '0123456789',
          repo: repo,
          template: const ReceiptTemplate(storeName: '黄金发宝号'),
          forceWindowsShareChannel: true,
        );
        expect(result, contains('Shared via system sheet'));
      }

      expect(sharedFiles, hasLength(2));
      for (final request in sharedFiles) {
        final paths = (request['paths'] as List).cast<String>();
        expect(paths, hasLength(1));
        expect(await File(paths.single).exists(), isTrue);
        expect(request['mimeTypes'], ['application/pdf']);
        expect(request['text'], contains('收据-中文-001'));
      }
    },
  );
}
