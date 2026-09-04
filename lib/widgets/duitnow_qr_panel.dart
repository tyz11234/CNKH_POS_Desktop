import 'dart:io';

import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../theme/cnkh_theme.dart';

class DuitNowQrPanel extends StatelessWidget {
  final String? imagePath;
  final int amountCents;
  final bool fullscreenFriendly;
  final VoidCallback? onTapExpand;
  final VoidCallback? onPickImage;

  const DuitNowQrPanel({
    super.key,
    required this.imagePath,
    required this.amountCents,
    this.fullscreenFriendly = false,
    this.onTapExpand,
    this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && File(imagePath!).existsSync();
    final size = fullscreenFriendly
        ? MediaQuery.sizeOf(context).shortestSide * 0.72
        : 220.0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFED1C24).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFED1C24).withValues(alpha: 0.35)),
          ),
          child: const Text(
            'DuitNow QR  /  扫码付款',
            style: TextStyle(
              color: Color(0xFFB71C1C),
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '应付 / Amount',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          formatRm(amountCents),
          style: const TextStyle(
            color: CnkhColors.navy,
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: hasImage ? onTapExpand : onPickImage,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CnkhColors.border, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? Image.file(File(imagePath!), fit: BoxFit.contain)
                : _Placeholder(onPick: onPickImage),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          hasImage
              ? '请顾客扫描此码付款 / Ask customer to scan'
              : '尚未设置收款码 — 请到设置导入 / No QR yet — import in Settings',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (hasImage && onTapExpand != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onTapExpand,
            icon: const Icon(Icons.fullscreen),
            label: const Text('全屏显示 QR / Full screen'),
          ),
        ],
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  final VoidCallback? onPick;
  const _Placeholder({this.onPick});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2, size: 72, color: CnkhColors.muted),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '点击导入 DuitNow QR\nTap to import QR image',
              textAlign: TextAlign.center,
              style: TextStyle(color: CnkhColors.muted, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen QR for counter presentation.
class DuitNowQrFullscreen extends StatelessWidget {
  final String imagePath;
  final int amountCents;

  const DuitNowQrFullscreen({
    super.key,
    required this.imagePath,
    required this.amountCents,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CnkhColors.deepNavy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('DuitNow QR'),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '黄金发宝号',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatRm(amountCents),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 24),
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Image.file(File(imagePath), fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '请扫描付款 / Scan to pay',
                  style: TextStyle(color: Color(0xFFAFC2DB), fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
