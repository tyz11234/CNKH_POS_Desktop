import 'dart:convert';

/// Pure helpers for gross-profit reporting (testable without SQLite).
///
/// COGS is estimated as sold qty × current catalog [costByProductId] unless a
/// sale line already carries `unitCostCents` / `costCents`.
class ProfitTotals {
  final int revenueCents;
  final int cogsCents;
  final int ticketCount;
  final bool cogsEstimated;

  const ProfitTotals({
    required this.revenueCents,
    required this.cogsCents,
    required this.ticketCount,
    required this.cogsEstimated,
  });

  int get grossProfitCents => revenueCents - cogsCents;

  /// Gross margin percent (0–100+), or 0 when revenue is 0.
  double get grossMarginPercent =>
      revenueCents == 0 ? 0 : (grossProfitCents * 100.0) / revenueCents;
}

/// [sales] maps must include `total_cents` (or `totalCents`) and `lines_json`
/// (JSON list of line maps with `productId`/`product_id` and `qty`).
ProfitTotals computeProfitTotals({
  required List<Map<String, Object?>> sales,
  required Map<String, int> costByProductId,
}) {
  var revenue = 0;
  var cogs = 0;
  var estimated = false;
  for (final sale in sales) {
    revenue += (sale['total_cents'] as int?) ??
        (sale['totalCents'] as int?) ??
        0;
    final raw = sale['lines_json'] ?? sale['linesJson'];
    if (raw is! String || raw.isEmpty) continue;
    late final List<dynamic> lines;
    try {
      lines = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      continue;
    }
    for (final line in lines) {
      if (line is! Map) continue;
      final m = Map<String, dynamic>.from(line);
      final qty = (m['qty'] as num?)?.toDouble() ?? 0;
      if (qty == 0) continue;
      final lineCost = (m['unitCostCents'] as num?)?.toInt() ??
          (m['costCents'] as num?)?.toInt();
      final pid = (m['productId'] ?? m['product_id'])?.toString();
      if (lineCost != null) {
        cogs += (lineCost * qty).round();
      } else {
        estimated = true;
        final key=pid?.startsWith('pc-')==true?pid!.substring(3):pid;
        final unit = key == null ? 0 : (costByProductId[key] ?? 0);
        cogs += (unit * qty).round();
      }
    }
  }
  return ProfitTotals(
    revenueCents: revenue,
    cogsCents: cogs,
    ticketCount: sales.length,
    cogsEstimated: estimated,
  );
}
