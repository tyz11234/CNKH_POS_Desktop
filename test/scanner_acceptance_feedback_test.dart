import 'dart:async';

import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/screens/barcode_scan_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _product = Product(
  id: 'p1',
  nameZh: '商品',
  nameEn: 'Product',
  sku: 'P1',
  barcode: 'B1',
  priceCents: 100,
);

class _ScanRepo extends PosRepository {
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [_product];
  @override
  Future<String> getSetting(String key, {String fallback = ''}) async =>
      key == 'scan_feedback' ? 'beep' : fallback;
}

void main() {
  var beeps = 0;
  setUp(() {
    beeps = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick') {
            beeps++;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<void> pick(
    WidgetTester tester,
    Future<bool> Function(Product) onProduct,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BarcodeScanScreen(repo: _ScanRepo(), onProduct: onProduct),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('商品'));
    await tester.pumpAndSettle();
  }

  testWidgets('a refused manual scan does not play accepted-item feedback', (
    tester,
  ) async {
    await pick(tester, (_) async => false);
    expect(beeps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending add plays feedback only after acceptance', (
    tester,
  ) async {
    final result = Completer<bool>();
    await pick(tester, (_) => result.future);
    expect(beeps, 0);
    result.complete(true);
    await tester.pumpAndSettle();
    expect(beeps, 1);
  });

  testWidgets('a rejected add is visible and does not play success feedback', (
    tester,
  ) async {
    await pick(tester, (_) async => throw StateError('库存读取失败'));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('库存读取失败'), findsOneWidget);
    expect(beeps, 0);
  });
}
