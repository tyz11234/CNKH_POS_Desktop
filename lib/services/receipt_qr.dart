import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'qr_storage.dart';

/// The same locally configured payment image used by the checkout screen.
/// Both output formats retain its aspect ratio and add a white quiet zone.
class ReceiptQrImage {
  ReceiptQrImage._(this._source);

  final img.Image _source;

  static Future<ReceiptQrImage?> load() async {
    try {
      final path = await QrStorage().getLocalPath();
      if (path == null) return null;
      final image = img.decodeImage(await File(path).readAsBytes());
      if (image == null) return null;
      return ReceiptQrImage._(img.bakeOrientation(image));
    } catch (_) {
      // A missing / unreadable image must not prevent receipt creation or add
      // a misleading "scan to pay" caption without an actual payment code.
      return null;
    }
  }

  /// Fits the complete image inside the printable square without stretching,
  /// with at least 14% whitespace on each side, including for tightly cropped QR.
  /// This covers four modules even for the smallest (21-module) QR symbol.
  img.Image raster({int widthDots = 576}) {
    if (widthDots <= 0) throw ArgumentError.value(widthDots, 'widthDots');
    final quiet = math.max(1, (widthDots * 0.14).ceil());
    final available = math.max(1, widthDots - quiet * 2);
    final scale = available / math.max(_source.width, _source.height);
    final width = math.max(1, (_source.width * scale).round());
    final height = math.max(1, (_source.height * scale).round());
    final scaled = img.copyResize(
      _source,
      width: width,
      height: height,
      interpolation: img.Interpolation.nearest,
    );
    final result = img.Image(
      width: widthDots,
      height: height + quiet * 2,
      numChannels: 4,
    );
    img.fill(result, color: img.ColorRgba8(255, 255, 255, 255));
    img.compositeImage(
      result,
      scaled,
      dstX: (widthDots - width) ~/ 2,
      dstY: quiet,
    );
    return result;
  }

  Uint8List pngBytes() =>
      Uint8List.fromList(img.encodePng(raster(widthDots: 768)));
}
