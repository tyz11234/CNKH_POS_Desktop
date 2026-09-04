import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../theme/cnkh_theme.dart';

class MoneyText extends StatelessWidget {
  /// Amount in sen (1/100 RM). Prefer this over floating RM.
  final int amountCents;
  final double fontSize;
  final FontWeight weight;
  final Color? color;
  final bool hero;

  const MoneyText({
    super.key,
    required this.amountCents,
    this.fontSize = 18,
    this.weight = FontWeight.w800,
    this.color,
    this.hero = false,
  });

  /// Convenience when caller still has an RM double (rounded to cents).
  factory MoneyText.rm({
    Key? key,
    required double amount,
    double fontSize = 18,
    FontWeight weight = FontWeight.w800,
    Color? color,
    bool hero = false,
  }) {
    return MoneyText(
      key: key,
      amountCents: rmToCents(amount),
      fontSize: fontSize,
      weight: weight,
      color: color,
      hero: hero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = formatRm(amountCents);
    return Text(
      text,
      style: TextStyle(
        color: color ?? (hero ? CnkhColors.navy : CnkhColors.ink),
        fontSize: hero ? fontSize.clamp(28, 40) : fontSize,
        fontWeight: weight,
        letterSpacing: hero ? -0.5 : 0,
      ),
    );
  }
}
