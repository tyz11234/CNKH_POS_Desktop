import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr/qr.dart';

import '../models/product.dart';
import '../services/lan_pairing_host.dart';
import '../services/lan_sync.dart';
import '../services/pos_repository.dart';
import '../services/scan_feedback.dart';
import '../theme/cnkh_theme.dart';

/// Full-screen continuous barcode scanner.
///
/// Product mode: each successful scan adds qty+1 and **keeps the camera open**.
/// Leave only via Done/Close, or camera/permission failure → manual search.
/// Pairing QR (`cnkh-sync:…`) is distinguished from product barcodes.
class BarcodeScanScreen extends StatefulWidget {
  final PosRepository repo;
  final void Function(Product product)? onProduct;
  final void Function(LanSyncConfig config)? onPairing;
  final bool pairingOnly;

  const BarcodeScanScreen({
    super.key,
    required this.repo,
    this.onProduct,
    this.onPairing,
    this.pairingOnly = false,
  });

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  MobileScannerController? _controller;
  bool _unsupported = false;
  bool _cameraFailed = false;
  bool _handling = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _addedCount = 0;
  String _lastProductName = '';

  LanPairingOffer? _desktopOffer;
  String? _desktopPairingError;
  bool _desktopPairingBusy = false;

  @override
  void initState() {
    super.initState();
    if (_isUnsupportedPlatform) {
      _unsupported = true;
      if (widget.pairingOnly && !kIsWeb) {
        _prepareDesktopPairing();
      }
      return;
    }
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.qrCode,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
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

  Future<void> _prepareDesktopPairing() async {
    if (_desktopPairingBusy) return;
    if (mounted) {
      setState(() {
        _desktopPairingBusy = true;
        _desktopPairingError = null;
      });
    }
    try {
      final offer = await LanPairingHost.shared(widget.repo).prepareOffer();
      if (!mounted) return;
      setState(() => _desktopOffer = offer);
    } catch (e) {
      if (!mounted) return;
      setState(() => _desktopPairingError = '$e');
    } finally {
      if (mounted) setState(() => _desktopPairingBusy = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _done() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openManualSearch() async {
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ManualProductSearchSheet(repo: widget.repo),
    );
    if (picked == null || !mounted) return;
    if (widget.onProduct != null) {
      widget.onProduct!(picked);
      setState(() {
        _addedCount++;
        _lastProductName = picked.nameZh;
      });
      await playScanFeedback(widget.repo);
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || !mounted) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    final now = DateTime.now();
    if (raw == _lastCode &&
        now.difference(_lastAt) < const Duration(milliseconds: 1600)) {
      return;
    }
    _handling = true;
    _lastCode = raw;
    _lastAt = now;
    try {
      if (looksLikePairingPayload(raw)) {
        LanSyncConfig? cfg;
        try {
          cfg = parsePairingQr(raw);
        } on PairingExpiredException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
            );
          }
          return;
        }
        if (cfg != null) {
          if (widget.onPairing != null) {
            widget.onPairing!(cfg);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('配对码已识别 ${cfg.name}'),
                  backgroundColor: CnkhColors.success,
                ),
              );
            }
          } else if (mounted) {
            Navigator.of(context).pop(cfg);
          }
          return;
        }
      }

      if (widget.pairingOnly) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请扫描电脑配对二维码 / Scan PC pairing QR'),
              backgroundColor: CnkhColors.danger,
            ),
          );
        }
        return;
      }

      if (widget.onProduct == null) return;
      final product = await widget.repo.findByBarcodeOrSku(raw);
      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('未找到商品 / Product not found'),
            backgroundColor: CnkhColors.danger,
            duration: const Duration(milliseconds: 1400),
            action: SnackBarAction(
              label: '手动搜索',
              textColor: Colors.white,
              onPressed: _openManualSearch,
            ),
          ),
        );
      } else {
        widget.onProduct!(product);
        await playScanFeedback(widget.repo);
        if (!mounted) return;
        setState(() {
          _addedCount++;
          _lastProductName = product.nameZh;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已加入 ${product.nameZh} (+1)'),
            backgroundColor: CnkhColors.success,
            duration: const Duration(milliseconds: 700),
          ),
        );
      }
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.pairingOnly ? '扫码配对 / Pair' : '连续扫码 / Continuous scan';
    final desktopPairing =
        widget.pairingOnly && _isUnsupportedPlatform && !kIsWeb;
    final showManual = _unsupported || _cameraFailed || _controller == null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: '完成 / Done',
          icon: const Icon(Icons.close),
          onPressed: _done,
        ),
        actions: [
          if (!widget.pairingOnly)
            TextButton(
              onPressed: _openManualSearch,
              child: const Text('手动', style: TextStyle(color: Colors.white)),
            ),
          TextButton(
            onPressed: _done,
            child: const Text(
              '完成 Done',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: desktopPairing
          ? _DesktopPairingBody(
              offer: _desktopOffer,
              error: _desktopPairingError,
              busy: _desktopPairingBusy,
              onRetry: _prepareDesktopPairing,
              onClose: _done,
            )
          : showManual
              ? _FallbackBody(
                  pairingOnly: widget.pairingOnly,
                  onManual: widget.pairingOnly ? null : _openManualSearch,
                  onClose: _done,
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller!,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_cameraFailed) {
                            setState(() => _cameraFailed = true);
                          }
                        });
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '摄像头不可用 / Camera failed\n($error)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ),
                        );
                      },
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _addedCount == 0
                              ? '连续模式 · 扫一次加 1 件'
                              : '已加 $_addedCount 件 · $_lastProductName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black54,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.pairingOnly
                                  ? '对准电脑「同步/配对」二维码'
                                  : '商品条码加购 · 配对码 cnkh-sync 仍可识别 · 点「完成」离开',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white54),
                                    ),
                                    onPressed: _openManualSearch,
                                    child: const Text('手动搜索加购'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: CnkhColors.success,
                                    ),
                                    onPressed: _done,
                                    child: Text(
                                      _addedCount > 0
                                          ? '完成 ($_addedCount)'
                                          : '完成 Done',
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _DesktopPairingBody extends StatelessWidget {
  const _DesktopPairingBody({
    required this.offer,
    required this.error,
    required this.busy,
    required this.onRetry,
    required this.onClose,
  });

  final LanPairingOffer? offer;
  final String? error;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final data = offer;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy && data == null)
              const CircularProgressIndicator(color: Colors.white)
            else if (error != null && data == null) ...[
              const Icon(Icons.wifi_off_outlined, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新检测 / Retry'),
              ),
            ] else if (data != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                color: Colors.white,
                child: SizedBox.square(
                  dimension: 270,
                  child: CustomPaint(painter: _QrPainter(data.payload)),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '请用手机 POS 扫描此配对码',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '手机与电脑需连接同一个 Wi-Fi',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 10),
              SelectableText(
                data.baseUrl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: onClose,
              child: const Text('关闭 / Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data)
      : image = QrImage(
          QrCode.fromData(
            data: data,
            errorCorrectLevel: QrErrorCorrectLevel.M,
          ),
        );

  final String data;
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    const quiet = 4;
    final totalModules = image.moduleCount + quiet * 2;
    final cell = size.shortestSide / totalModules;
    final originX = (size.width - cell * totalModules) / 2;
    final originY = (size.height - cell * totalModules) / 2;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()..color = Colors.black;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            originX + (col + quiet) * cell,
            originY + (row + quiet) * cell,
            cell + 0.05,
            cell + 0.05,
          ),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

class _FallbackBody extends StatelessWidget {
  final bool pairingOnly;
  final VoidCallback? onManual;
  final VoidCallback onClose;
  const _FallbackBody({
    required this.pairingOnly,
    required this.onManual,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              pairingOnly
                  ? '此设备无摄像头 / 请用手机扫描配对码'
                  : '摄像头不可用或无权限\n请改用手动搜索加购',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.4),
            ),
            const SizedBox(height: 20),
            if (onManual != null) ...[
              FilledButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.search),
                label: const Text('手动搜索商品 / Manual search'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: onClose,
              child: const Text('关闭 / Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualProductSearchSheet extends StatefulWidget {
  final PosRepository repo;
  const _ManualProductSearchSheet({required this.repo});

  @override
  State<_ManualProductSearchSheet> createState() =>
      _ManualProductSearchSheetState();
}

class _ManualProductSearchSheetState extends State<_ManualProductSearchSheet> {
  final _q = TextEditingController();
  List<Product> _items = [];

  @override
  void initState() {
    super.initState();
    _reload('');
    _q.addListener(() => _reload(_q.text));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _reload(String q) async {
    final list = await widget.repo.searchProducts(q, limit: 40);
    if (mounted) setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CnkhColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '搜索商品名称 / SKU / 条码',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final p = _items[i];
                    return ListTile(
                      title: Text(
                        p.nameZh,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('${p.sku} · ${p.barcode}'),
                      trailing: Text('库存 ${p.stock}'),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
