import 'package:flutter/material.dart';

import '../theme/cnkh_theme.dart';

/// Shared 80mm thermal-style monospace receipt preview (settings + sale detail).
class ReceiptPreviewPane extends StatelessWidget {
  final String text;
  final String caption;
  /// Fixed height when [fill] is false.
  final double height;
  /// When true, fills the parent (parent must provide a bounded height, e.g. [Expanded]).
  final bool fill;

  const ReceiptPreviewPane({
    super.key,
    required this.text,
    this.caption = '≈ 80mm thermal',
    this.height = 420,
    this.fill = false,
  });

  static const TextStyle monospaceStyle = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: [
      'Noto Sans Mono',
      'Courier New',
      'Courier',
      'Menlo',
      'Consolas',
    ],
    fontSize: 11.5,
    height: 1.35,
    color: CnkhColors.ink,
    letterSpacing: 0,
  );

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CnkhColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFE8E8E0),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: CnkhColors.muted),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              child: SelectableText(text, style: monospaceStyle),
            ),
          ),
        ],
      ),
    );

    if (fill) return content;
    return SizedBox(height: height, child: content);
  }
}
