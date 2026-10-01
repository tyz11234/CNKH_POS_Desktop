import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/e_receipt.dart';
import 'package:cnkh_pos_desktop/services/qr_storage.dart';
import 'package:cnkh_pos_desktop/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  late File owned;
  late File contract;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('cnkh-cache-settings-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path);
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.setSetting(kEReceiptCacheDirKey, temp.path);
    final sale = SaleRecord(id: 'cache-sale', receiptNo: 'CACHE-1',
      soldAt: '2026-10-01T12:00:00', cashier: 'Admin', paymentMethod: 'CASH',
      subtotalCents: 100, itemDiscountCents: 0, orderDiscountCents: 0,
      roundingCents: 0, totalCents: 100, paidCents: 100, changeCents: 0,
      creditOutstandingCents: 0, linesJson: '[]');
    // Exercise the real PDF writer and ownership registration before the UI.
    owned = await writeReceiptPdfCached(sale, repo: repo,
        template: const ReceiptTemplate(storeName: 'Test Shop', footerLines: 'Thanks'));
    contract = await owned.copy('${temp.path}/supplier-contract.PDF');
  });
  tearDown(() async {
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    await temp.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 80));
    }
  }
  testWidgets('F05 actual settings clear deletes its own generated PDF and preserves the selected folder documents',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(
      qrStorage: QrStorage(), repo: repo,
      user: const AppUser(username: 'admin', role: AppRole.admin)))));
    await flush(tester);
    final clear = find.text('电子收据缓存 / E-receipt cache');
    await tester.scrollUntilVisible(clear, 500, maxScrolls: 30,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(clear);
    await flush(tester);
    expect(find.text('清空电子收据缓存？'), findsOneWidget);
    expect(find.text('当前约 1 个 PDF。清空后无法从本机重发旧缓存。'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await flush(tester);
    await tester.runAsync(() async {
      expect(await owned.exists(), isFalse);
      expect(await contract.exists(), isTrue);
      expect(await countEReceiptCache(repo: repo), 0);
    });
    expect(find.text('已删除 1 个缓存 PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
