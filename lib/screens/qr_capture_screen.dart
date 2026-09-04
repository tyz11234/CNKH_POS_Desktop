import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR/barcode capture that pops with the raw string.
class QrCaptureScreen extends StatefulWidget {
  final String title;
  final String hint;

  const QrCaptureScreen({
    super.key,
    this.title = '扫码配对 / Scan to pair',
    this.hint = '对准电脑上的配对二维码',
  });

  @override
  State<QrCaptureScreen> createState() => _QrCaptureScreenState();
}

class _QrCaptureScreenState extends State<QrCaptureScreen> {
  MobileScannerController? _controller;
  bool _unsupported = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (_isUnsupportedPlatform) {
      _unsupported = true;
      return;
    }
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    } catch (_) {
      _unsupported = true;
    }
  }

  bool get _isUnsupportedPlatform {
    if (kIsWeb) return true;
    try {
      return Platform.isLinux || Platform.isWindows;
    } catch (_) {
      return true;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _unsupported || _controller == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '此设备无摄像头 / 请用手机\n\nNo camera — use a phone to pair.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 18, height: 1.4),
                ),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller!,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => Center(
                    child: Text(
                      '此设备无摄像头 / 请用手机\n($error)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black54,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Text(
                      widget.hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
