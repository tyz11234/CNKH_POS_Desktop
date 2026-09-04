import 'package:flutter/material.dart';

import '../services/e_receipt.dart';
import '../theme/cnkh_theme.dart';

Future<void> showCashChangeDialog(
  BuildContext context, {
  required int tenderedCents,
  required int dueCents,
}) {
  final change = tenderedCents - dueCents;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('找零 / CHANGE',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text('收取 / Tendered',
                style: TextStyle(color: CnkhColors.muted, fontSize: 13)),
            Text(formatRmPlain(tenderedCents),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('应付 / Due',
                style: TextStyle(color: CnkhColors.muted, fontSize: 13)),
            Text(formatRmPlain(dueCents),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const Divider(height: 28),
            const Text('找零金额', style: TextStyle(fontSize: 14)),
            Text(
              formatRmPlain(change < 0 ? 0 : change),
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: CnkhColors.success,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确认 / Confirm',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
