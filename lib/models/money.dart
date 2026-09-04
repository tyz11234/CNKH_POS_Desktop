/// Integer-cent money helpers (sen). Never store MYR as binary float.
int rmToCents(double rm) => (rm * 100).round();

double centsToRm(int cents) => cents / 100.0;

String formatRm(int cents) {
  final sign = cents < 0 ? '-' : '';
  final a = cents.abs();
  return '$sign${'RM'} ${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

int clampDiscountCents(int discountCents, int lineCents) =>
    discountCents.clamp(0, lineCents < 0 ? 0 : lineCents);

/// CNKH checkout rounding (non-credit): last digit 1-4→0, 5 stays, 6-9→10.
int roundCheckoutCents(int cents) {
  if (cents < 0) throw ArgumentError('negative');
  final r = cents % 10;
  if (r == 0 || r == 5) return cents;
  if (r >= 1 && r <= 4) return cents - r;
  return cents + (10 - r);
}

int checkoutRoundingAdjustment(int cents) => roundCheckoutCents(cents) - cents;

/// Percent discount of [grossCents], half-up to nearest sen.
int percentDiscountCents(int grossCents, double percent) {
  if (grossCents <= 0 || percent <= 0) return 0;
  final raw = (grossCents * percent / 100.0).round();
  return clampDiscountCents(raw, grossCents);
}

/// Allocate order discount across line nets (largest remainder / proportional).
Map<String, int> allocateOrderDiscount(
  List<(String id, int netCents)> lines,
  int orderDiscountCents,
) {
  final result = {for (final e in lines) e.$1: 0};
  if (orderDiscountCents <= 0 || lines.isEmpty) return result;
  final totalNet = lines.fold<int>(0, (s, e) => s + e.$2);
  if (totalNet <= 0) return result;
  final capped = orderDiscountCents.clamp(0, totalNet);
  var allocated = 0;
  final remainders = <(String, double)>[];
  for (final (id, net) in lines) {
    final exact = capped * net / totalNet;
    final base = exact.floor();
    result[id] = base;
    allocated += base;
    remainders.add((id, exact - base));
  }
  var left = capped - allocated;
  remainders.sort((a, b) => b.$2.compareTo(a.$2));
  for (final (id, _) in remainders) {
    if (left <= 0) break;
    result[id] = result[id]! + 1;
    left--;
  }
  return result;
}
