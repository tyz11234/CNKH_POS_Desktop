import 'dart:convert';

import 'package:cnkh_pos_desktop/services/profit_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gross profit from catalog cost estimate', () {
    final sales = [
      {
        'total_cents': 1000,
        'lines_json': jsonEncode([
          {'productId': 'p1', 'qty': 2},
          {'productId': 'p2', 'qty': 1},
        ]),
      },
    ];
    final totals = computeProfitTotals(
      sales: sales,
      costByProductId: {'p1': 200, 'p2': 100},
    );
    expect(totals.revenueCents, 1000);
    expect(totals.cogsCents, 500);
    expect(totals.grossProfitCents, 500);
    expect(totals.grossMarginPercent, closeTo(50.0, 0.01));
    expect(totals.cogsEstimated, isTrue);
    expect(totals.ticketCount, 1);
  });

  test('uses line unitCostCents when present', () {
    final sales = [
      {
        'total_cents': 800,
        'lines_json': jsonEncode([
          {'productId': 'p1', 'qty': 2, 'unitCostCents': 150},
        ]),
      },
    ];
    final totals = computeProfitTotals(
      sales: sales,
      costByProductId: {'p1': 999},
    );
    expect(totals.cogsCents, 300);
    expect(totals.cogsEstimated, isFalse);
    expect(totals.grossProfitCents, 500);
  });

  test('empty sales', () {
    final totals = computeProfitTotals(sales: [], costByProductId: {});
    expect(totals.revenueCents, 0);
    expect(totals.cogsCents, 0);
    expect(totals.cogsEstimated, isFalse);
  });
}
