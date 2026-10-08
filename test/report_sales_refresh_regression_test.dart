import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/screens/admin/admin_hub.dart';
import 'package:cnkh_pos_desktop/screens/sales_list_screen.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

class _Repository extends PosRepository {
  int tickets = 0;
  int revenue = 0;
  Completer<Map<String, int>>? pendingPayment;
  final sales = <SaleRecord>[];

  @override
  Future<Map<String, int>> reportByPayment({
    required String startDay,
    required String endDay,
  }) {
    final pending = pendingPayment;
    pendingPayment = null;
    return pending?.future ?? Future.value({'CASH': revenue, 'TOTAL': revenue});
  }

  @override
  Future<Map<String, Object?>> reportProfit({
    required String startDay,
    required String endDay,
  }) async => {
    'ticketCount': tickets,
    'revenueCents': revenue,
    'grossProfitCents': revenue,
    'grossMarginPercent': 100.0,
  };

  @override
  Future<List<SaleRecord>> salesAll({int? limit}) async => sales;
}

SaleRecord _sale(String receipt, DateTime sold) => SaleRecord(
  id: receipt,
  receiptNo: receipt,
  soldAt: sold.toIso8601String(),
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
  linesJson: '[]',
);

void main() {
  testWidgets('retained report refreshes after the shell data token changes', (
    tester,
  ) async {
    final repo = _Repository();
    Widget page(int token) => MaterialApp(
      home: ReportsPage(repo: repo, refreshToken: token),
    );
    await tester.pumpWidget(page(0));
    await tester.pumpAndSettle();
    expect(find.text('共 0 笔有效销售'), findsOneWidget);
    repo.tickets = 1;
    repo.revenue = 10000;
    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();
    expect(find.text('共 1 笔有效销售'), findsOneWidget);
    expect(find.text('RM 100.00'), findsWidgets);
  });

  testWidgets('an older in-flight report cannot overwrite the latest refresh', (
    tester,
  ) async {
    final repo = _Repository();
    final slow = Completer<Map<String, int>>();
    repo.pendingPayment = slow;
    Widget page(int token) => MaterialApp(
      home: ReportsPage(repo: repo, refreshToken: token),
    );
    await tester.pumpWidget(page(0));
    await tester.pump();
    repo.tickets = 2;
    repo.revenue = 2500;
    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();
    expect(find.text('共 2 笔有效销售'), findsOneWidget);
    repo.tickets = 0;
    repo.revenue = 0;
    slow.complete({'CASH': 0, 'TOTAL': 0});
    await tester.pumpAndSettle();
    expect(find.text('共 2 笔有效销售'), findsOneWidget);
    expect(find.text('RM 25.00'), findsWidgets);
  });

  testWidgets(
    'end-date includes fractional final second but excludes following midnight',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final repo = _Repository();
      repo.sales.addAll([
        _sale(
          'LAST-SECOND',
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999),
        ),
        _sale('NEXT-DAY', DateTime(now.year, now.month, now.day + 1)),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesListScreen(repo: repo, todayOnly: false)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('LAST-SECOND'), findsWidgets);
      expect(find.textContaining('NEXT-DAY'), findsWidgets);
      await tester.tap(find.text('到日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('LAST-SECOND'), findsWidgets);
      expect(find.textContaining('NEXT-DAY'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
