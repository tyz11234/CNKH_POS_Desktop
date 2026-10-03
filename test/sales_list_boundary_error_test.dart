import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/screens/sales_list_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

SaleRecord sale(String receipt, DateTime soldAt) => SaleRecord(
  id: receipt,
  receiptNo: receipt,
  soldAt: soldAt.toIso8601String(),
  cashier: 'admin',
  paymentMethod: 'CARD',
  subtotalCents: 100,
  itemDiscountCents: 0,
  orderDiscountCents: 0,
  roundingCents: 0,
  totalCents: 100,
  paidCents: 100,
  changeCents: 0,
  creditOutstandingCents: 0,
  linesJson: '[]',
);

class _SalesRepo extends PosRepository {
  _SalesRepo(this.sales);
  final List<SaleRecord> sales;
  @override
  Future<List<SaleRecord>> salesAll({int? limit}) async => sales;
  @override
  Future<void> voidSale(String id, String note) async {
    throw StateError('e-Invoice 已提交，不能直接作废');
  }
}

void main() {
  testWidgets(
    'to-date includes the final fractional second and excludes next day',
    (tester) async {
      final now = DateTime.now();
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999);
      final repo = _SalesRepo([
        sale('FINAL-SECOND', end),
        sale('NEXT-DAY', DateTime(now.year, now.month, now.day + 1)),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesListScreen(repo: repo, todayOnly: false)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('到日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('FINAL-SECOND · CARD'), findsOneWidget);
      expect(find.text('NEXT-DAY · CARD'), findsNothing);
    },
  );

  testWidgets('a refused sale void is shown without an unhandled error', (
    tester,
  ) async {
    final repo = _SalesRepo([sale('PROTECTED', DateTime.now())]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesListScreen(repo: repo, todayOnly: false, canVoid: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('作废'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作废').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('e-Invoice 已提交，不能直接作废'), findsOneWidget);
    expect(find.text('PROTECTED · CARD'), findsOneWidget);
  });
}
