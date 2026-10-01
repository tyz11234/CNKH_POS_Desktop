import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// ESC/POS GS v 0 raster output avoids printer-specific Chinese code pages.
/// Printers must support this raster command; physical acceptance is separate.
class EscPosReceiptEncoder {
  static Future<void>? _font;

  Future<List<int>> encode(String text, {int widthDots = 384}) async {
    if (widthDots != 384 && widthDots != 576) {
      throw ArgumentError('打印宽度仅支持 384 / 576 dots');
    }
    await (_font ??= _loadFont());
    final bytes = <int>[0x1b, 0x40, 0x1b, 0x61, 0];
    for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
      final painter = TextPainter(
        text: TextSpan(text: line.isEmpty ? ' ' : line,
          style: const TextStyle(color: Color(0xff000000), fontSize: 18,
            height: 1.3, fontFamily: 'monospace',
            fontFamilyFallback: ['CNKHReceiptSC'])),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: widthDots.toDouble());
      final height = math.max(24, painter.height.ceil());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xffffffff), BlendMode.src);
      painter.paint(canvas, Offset.zero);
      final picture = recorder.endRecording();
      final image = await picture.toImage(widthDots, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw StateError('无法生成打印图像');
        bytes.addAll(packRaster(data.buffer.asUint8List(), widthDots, height));
      } finally {
        image.dispose(); picture.dispose(); painter.dispose();
      }
    }
    bytes.addAll([0x0a, 0x0a, 0x0a, 0x1d, 0x56, 0]);
    return bytes;
  }

  static Future<void> _loadFont() async {
    final loader = FontLoader('CNKHReceiptSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));
    await loader.load();
  }

  /// Banding limits printer buffers; every output value is an unsigned byte.
  static List<int> packRaster(Uint8List rgba, int width, int height) {
    if (width <= 0 || width % 8 != 0 || height <= 0 || rgba.length != width * height * 4) {
      throw ArgumentError('invalid raster dimensions');
    }
    final out = <int>[];
    final stride = width ~/ 8;
    for (var top = 0; top < height; top += 128) {
      final rows = math.min(128, height - top);
      out.addAll([0x1d, 0x76, 0x30, 0, stride & 255, stride >> 8, rows & 255, rows >> 8]);
      for (var y = top; y < top + rows; y++) {
        for (var x = 0; x < width; x += 8) {
          var packed = 0;
          for (var bit = 0; bit < 8; bit++) {
            final i = (y * width + x + bit) * 4;
            final luminance = (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
            if (rgba[i + 3] > 127 && luminance < 160) packed |= 0x80 >> bit;
          }
          out.add(packed);
        }
      }
    }
    return out;
  }
}
