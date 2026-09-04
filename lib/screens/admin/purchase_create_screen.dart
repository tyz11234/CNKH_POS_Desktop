import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../db/app_database.dart';
import '../../models/app_user.dart';
import '../../models/money.dart';
import '../../models/product.dart';
import '../../services/pos_repository.dart';
import '../../services/purchase_invoice.dart';
import '../../services/purchase_invoice_ocr.dart';
import '../../services/scan_feedback.dart';
import '../../theme/cnkh_theme.dart';
import '../../widgets/money_text.dart';
import '../barcode_scan_screen.dart';
import '../qr_capture_screen.dart';

const _kLastSupplierId = 'purchase_last_supplier_id';

/// Full-screen 进货 draft: scan products / invoice QR / OCR, review, commit.
class PurchaseCreateScreen extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;

  const PurchaseCreateScreen({
    super.key,
    required this.repo,
    required this.user,
  });

  @override
  State<PurchaseCreateScreen> createState() => _PurchaseCreateScreenState();
}

class _PurchaseCreateScreenState extends State<PurchaseCreateScreen> {
  List<Supplier> _suppliers = [];
  Supplier? _supplier;
  final _notes = TextEditingController();
  final _barcodeField = TextEditingController();
  final _barcodeFocus = FocusNode();
  final List<PurchaseDraftLine> _lines = [];
  String? _rawOcrText;
  bool _busy = false;
  late final PurchaseLineMatcher _matcher = PurchaseLineMatcher(widget.repo);

  bool get _cameraOk {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _notes.dispose();
    _barcodeField.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final list = await widget.repo.listSuppliers();
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString(_kLastSupplierId);
    Supplier? selected;
    if (lastId != null) {
      for (final s in list) {
        if (s.id == lastId) {
          selected = s;
          break;
        }
      }
    }
    selected ??= list.isEmpty ? null : list.first;
    if (!mounted) return;
    setState(() {
      _suppliers = list;
      _supplier = selected;
    });
  }

  Future<void> _rememberSupplier(Supplier s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSupplierId, s.id);
  }

  Future<void> _addOrEditSupplier({Supplier? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final email = TextEditingController(text: existing?.email ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '新增供应商' : '编辑供应商'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: '名称 *',
                  hintText: '供应商 / 档口名称',
                ),
                autofocus: true,
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: '电话'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: '邮箱 / 地址备注'),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: '备注'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final n = name.text.trim();
    if (n.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写供应商名称')),
      );
      return;
    }
    final s = Supplier(
      id: existing?.id ?? AppDatabase.newId(),
      name: n,
      phone: phone.text.trim(),
      email: email.text.trim(),
      notes: notes.text.trim(),
    );
    await widget.repo.upsertSupplier(s);
    await _rememberSupplier(s);
    final list = await widget.repo.listSuppliers();
    if (!mounted) return;
    setState(() {
      _suppliers = list;
      _supplier = s;
    });
  }

  int get _totalCents => _lines
      .where((l) => l.selected)
      .fold<int>(0, (s, l) => s + l.subtotalCents);

  int get _createCount =>
      _lines.where((l) => l.selected && l.willCreate).length;

  int get _existCount =>
      _lines.where((l) => l.selected && !l.willCreate).length;

  Future<void> _mergeLines(List<PurchaseDraftLine> incoming,
      {bool replace = false}) async {
    setState(() => _busy = true);
    try {
      final resolved = await _matcher.resolve(incoming);
      if (!mounted) return;
      setState(() {
        if (replace) {
          _lines
            ..clear()
            ..addAll(resolved);
        } else {
          for (final line in resolved) {
            final idx = _lines.indexWhere((e) {
              if (line.productId != null && e.productId == line.productId) {
                return true;
              }
              final code = line.barcode.isNotEmpty ? line.barcode : line.sku;
              if (code.isNotEmpty &&
                  (e.barcode == code || e.sku == code)) {
                return true;
              }
              return normalizeProductName(e.name) ==
                      normalizeProductName(line.name) &&
                  line.name.trim().isNotEmpty;
            });
            if (idx >= 0) {
              _lines[idx].qty += line.qty;
              if (line.unitCostCents > 0) {
                _lines[idx].unitCostCents = line.unitCostCents;
              }
            } else {
              _lines.add(line);
            }
          }
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addProductScan(Product p, {double qty = 1}) async {
    await _mergeLines([
      PurchaseDraftLine(
        name: p.nameZh,
        qty: qty,
        unitCostCents: p.costCents > 0 ? p.costCents : 0,
        sku: p.sku,
        barcode: p.barcode,
        productId: p.id,
        willCreate: false,
        sellPriceCents: p.priceCents,
        matchNote: '扫码加入',
      ),
    ]);
    await playScanFeedback(widget.repo);
  }

  Future<void> _onWedgeSubmit(String raw) async {
    final code = raw.trim();
    _barcodeField.clear();
    if (code.isEmpty) return;

    final payload = PurchaseInvoicePayload.tryParse(code);
    if (payload != null) {
      await _applyPayload(payload);
      return;
    }

    final product = await widget.repo.findByBarcodeOrSku(code);
    if (!mounted) return;
    if (product == null) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未找到商品'),
          content: Text('条码/SKU：$code\n可新建草稿行，或跳过。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'skip'),
                child: const Text('跳过')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'create'),
                child: const Text('加入为新商品')),
          ],
        ),
      );
      if (action == 'create') {
        await _mergeLines([
          PurchaseDraftLine(
            name: code,
            qty: 1,
            barcode: code,
            willCreate: true,
            matchNote: '未知条码 · 将新建',
          ),
        ]);
      }
      return;
    }
    await _addProductScan(product);
  }

  Future<void> _applyPayload(PurchaseInvoicePayload payload) async {
    if (payload.supplierId != null ||
        (payload.supplierName != null && payload.supplierName!.isNotEmpty)) {
      Supplier? match;
      for (final s in _suppliers) {
        if (payload.supplierId != null && s.id == payload.supplierId) {
          match = s;
          break;
        }
      }
      if (match == null && payload.supplierName != null) {
        final want = payload.supplierName!.trim().toLowerCase();
        for (final s in _suppliers) {
          if (s.name.trim().toLowerCase() == want) {
            match = s;
            break;
          }
        }
      }
      if (match != null) {
        setState(() => _supplier = match);
        await _rememberSupplier(match);
      } else if (payload.supplierName != null &&
          payload.supplierName!.trim().isNotEmpty) {
        // Offer to create supplier from QR
        if (mounted) {
          final create = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('二维码含供应商'),
              content: Text('「${payload.supplierName}」不在列表中，是否新建？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('否')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('新建并选用')),
              ],
            ),
          );
          if (create == true) {
            final s = Supplier(
              id: AppDatabase.newId(),
              name: payload.supplierName!.trim(),
            );
            await widget.repo.upsertSupplier(s);
            await _rememberSupplier(s);
            final list = await widget.repo.listSuppliers();
            if (mounted) {
              setState(() {
                _suppliers = list;
                _supplier = s;
              });
            }
          }
        }
      }
    }
    if (payload.notes.isNotEmpty) {
      _notes.text = payload.notes;
    }
    await _mergeLines(payload.lines, replace: _lines.isEmpty);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已导入进货单 ${payload.lines.length} 行，请核对'),
        backgroundColor: CnkhColors.success,
      ),
    );
  }

  Future<void> _openContinuousScan() async {
    if (!_cameraOk) {
      _barcodeFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('桌面请用扫码枪/粘贴条码；或点「进货单二维码」粘贴内容'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BarcodeScanScreen(
          repo: widget.repo,
          onProduct: (p) {
            _addProductScan(p);
          },
          onPairing: null,
        ),
      ),
    );
  }

  Future<void> _scanInvoiceQr() async {
    String? raw;
    if (_cameraOk) {
      raw = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => const QrCaptureScreen(
            title: '扫进货单二维码',
            hint: '对准供应商进货单 QR（CNKHPO1:…）',
          ),
        ),
      );
    } else {
      raw = await _promptPaste(
        title: '粘贴进货单二维码内容',
        hint: 'CNKHPO1:{…} 或 JSON',
      );
    }
    if (raw == null || raw.trim().isEmpty) return;
    final payload = PurchaseInvoicePayload.tryParse(raw);
    if (payload == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法识别进货单格式，请查看「格式说明」'),
          backgroundColor: CnkhColors.danger,
        ),
      );
      return;
    }
    await _applyPayload(payload);
  }

  Future<String?> _promptPaste({
    required String title,
    String hint = '',
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _ocrFromImage({required bool camera}) async {
    final picker = ImagePicker();
    XFile? file;
    try {
      file = await picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开相机/相册：$e')),
      );
      return;
    }
    if (file == null) return;

    setState(() => _busy = true);
    String? text;
    try {
      text = await PurchaseInvoiceOcr.recognizeFile(file.path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      final pasted = await _promptPaste(
        title: 'OCR 不可用或未识别到文字',
        hint: '${PurchaseInvoiceOcr.capabilityNote}\n\n可在此粘贴单据文字（品名 数量 单价）',
      );
      if (pasted == null || pasted.trim().isEmpty) return;
      text = pasted;
    }
    await _applyOcrText(text);
  }

  Future<void> _pasteOcrText() async {
    final pasted = await _promptPaste(
      title: '粘贴单据文字',
      hint: '每行：品名  数量  单价\n例如：螺丝M6  100  0.15',
    );
    if (pasted == null || pasted.trim().isEmpty) return;
    await _applyOcrText(pasted);
  }

  Future<void> _applyOcrText(String text) async {
    final parsed = PurchaseInvoiceTextParser.parse(text);
    if (parsed.isEmpty) {
      if (!mounted) return;
      setState(() => _rawOcrText = text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未能解析出行项目，已保存原文供参考 — 请手动加行或改格式'),
          backgroundColor: CnkhColors.warning,
        ),
      );
      return;
    }
    setState(() => _rawOcrText = text);
    await _mergeLines(parsed, replace: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('识别到 ${parsed.length} 行（请核对品名/数量/进货价）'),
        backgroundColor: CnkhColors.success,
      ),
    );
  }

  Future<void> _manualAddLine() async {
    final products = await widget.repo.searchProducts('', limit: 80);
    if (!mounted) return;
    Product? picked;
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController();
    if (products.isNotEmpty) {
      picked = products.first;
      costCtrl.text = centsToRm(picked.costCents).toStringAsFixed(2);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('手动加行'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (products.isEmpty)
                  const Text('目录无商品，可用扫码「将新建」')
                else
                  DropdownButton<Product>(
                    isExpanded: true,
                    value: picked,
                    items: [
                      for (final p in products)
                        DropdownMenuItem(
                          value: p,
                          child: Text('${p.nameZh} (${p.sku})'),
                        ),
                    ],
                    onChanged: (v) => setLocal(() {
                      picked = v;
                      if (v != null) {
                        costCtrl.text =
                            centsToRm(v.costCents).toStringAsFixed(2);
                      }
                    }),
                  ),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: '数量'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: costCtrl,
                  decoration: const InputDecoration(
                    labelText: '进货价 RM',
                    prefixText: 'RM ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('加入')),
          ],
        ),
      ),
    );
    if (ok != true || picked == null) return;
    final q = double.tryParse(qtyCtrl.text.trim()) ?? 0;
    if (q <= 0) return;
    final cost = rmToCents(double.tryParse(costCtrl.text.trim()) ?? 0);
    await _mergeLines([
      PurchaseDraftLine(
        name: picked!.nameZh,
        qty: q,
        unitCostCents: cost,
        sku: picked!.sku,
        barcode: picked!.barcode,
        productId: picked!.id,
        willCreate: false,
        sellPriceCents: picked!.priceCents,
        matchNote: '手动加入',
      ),
    ]);
  }

  Future<void> _editLine(int index) async {
    final line = _lines[index];
    final name = TextEditingController(text: line.name);
    final qty = TextEditingController(text: line.qty.toString());
    final cost = TextEditingController(
        text: centsToRm(line.unitCostCents).toStringAsFixed(2));
    final sell = TextEditingController(
        text: centsToRm(line.effectiveSellCents).toStringAsFixed(2));
    final barcode = TextEditingController(text: line.barcode);
    final sku = TextEditingController(text: line.sku);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.willCreate ? '编辑（将新建）' : '编辑进货行'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '品名')),
              TextField(
                  controller: barcode,
                  decoration: const InputDecoration(labelText: '条码')),
              TextField(
                  controller: sku,
                  decoration: const InputDecoration(labelText: 'SKU')),
              TextField(
                controller: qty,
                decoration: const InputDecoration(labelText: '数量'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: cost,
                decoration: const InputDecoration(
                    labelText: '进货价 RM', prefixText: 'RM '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              if (line.willCreate)
                TextField(
                  controller: sell,
                  decoration: const InputDecoration(
                      labelText: '售价 RM（新建商品）', prefixText: 'RM '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.trim()) ?? line.qty;
    setState(() {
      line.name = name.text.trim();
      line.barcode = barcode.text.trim();
      line.sku = sku.text.trim();
      line.qty = q <= 0 ? line.qty : q;
      line.unitCostCents =
          rmToCents(double.tryParse(cost.text.trim()) ?? 0);
      if (line.willCreate) {
        line.sellPriceCents =
            rmToCents(double.tryParse(sell.text.trim()) ?? 0);
      }
    });
    // Re-resolve match after edits
    final resolved = await _matcher.resolve([line]);
    if (!mounted || resolved.isEmpty) return;
    setState(() => _lines[index] = resolved.first..selected = line.selected);
  }

  void _showFormatHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('进货单二维码格式'),
        content: const SingleChildScrollView(
          child: SelectableText(PurchaseInvoicePayload.helpZh),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    if (_supplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择或新增供应商')),
      );
      return;
    }
    final selected = _lines.where((l) => l.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少勾选一行')),
      );
      return;
    }
    final createN = selected.where((l) => l.willCreate).length;
    final existN = selected.length - createN;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认进货'),
        content: Text(
          '供应商：${_supplier!.name}\n'
          '已有商品 $existN 行 · 将新建 $createN 个商品\n'
          '合计进货额：${formatRm(_totalCents)}\n\n'
          '新建商品：进货价取单据价，售价默认同进货价（可在行内改）。\n'
          '库存将通过进货 API 增加。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回核对')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认提交')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await _matcher.commit(
        lines: _lines,
        supplier: _supplier!,
        operator: widget.user.username,
        notes: _notes.text.trim(),
      );
      await _rememberSupplier(_supplier!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('进货成功'),
          backgroundColor: CnkhColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('进货失败：$e'),
          backgroundColor: CnkhColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码/单据进货'),
        actions: [
          IconButton(
            tooltip: '格式说明',
            onPressed: _showFormatHelp,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _supplierCard(),
                      const SizedBox(height: 12),
                      _scanActionsCard(),
                      const SizedBox(height: 12),
                      _wedgeField(),
                      if (_rawOcrText != null) ...[
                        const SizedBox(height: 8),
                        ExpansionTile(
                          title: const Text('OCR / 粘贴原文'),
                          subtitle: const Text('低置信度时请对照原文修改'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                _rawOcrText!,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '明细 ${_lines.length} 行',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const Spacer(),
                          Text(
                            '已有 $_existCount · 新建 $_createCount',
                            style: const TextStyle(color: CnkhColors.muted),
                          ),
                          IconButton(
                            tooltip: '手动加行',
                            onPressed: _manualAddLine,
                            icon: const Icon(Icons.playlist_add),
                          ),
                        ],
                      ),
                      if (_lines.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              '用「扫码进货」连续扫商品，或「进货单二维码 / 拍照识别」导入整单。\n'
                              '${PurchaseInvoiceOcr.capabilityNote}',
                              style: const TextStyle(
                                  color: CnkhColors.muted, height: 1.4),
                            ),
                          ),
                        )
                      else
                        ...List.generate(_lines.length, _lineTile),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notes,
                        decoration: const InputDecoration(
                          labelText: '备注',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                _bottomBar(),
              ],
            ),
    );
  }

  Widget _supplierCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_outlined, color: CnkhColors.navy),
            const SizedBox(width: 10),
            Expanded(
              child: _suppliers.isEmpty
                  ? const Text('尚无供应商 — 请新增',
                      style: TextStyle(fontWeight: FontWeight.w700))
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<Supplier>(
                        isExpanded: true,
                        value: _supplier,
                        hint: const Text('选择供应商'),
                        items: [
                          for (final s in _suppliers)
                            DropdownMenuItem(
                              value: s,
                              child: Text(
                                s.phone.isEmpty ? s.name : '${s.name} · ${s.phone}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _supplier = v);
                          await _rememberSupplier(v);
                        },
                      ),
                    ),
            ),
            IconButton(
              tooltip: '新增供应商',
              onPressed: () => _addOrEditSupplier(),
              icon: const Icon(Icons.person_add_alt_1),
              color: CnkhColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanActionsCard() {
    return Card(
      color: CnkhColors.softBlue,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '扫码进货',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _openContinuousScan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('扫码进货'),
                ),
                OutlinedButton.icon(
                  onPressed: _scanInvoiceQr,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('进货单二维码'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _ocrFromImage(camera: true),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('拍照识别'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _ocrFromImage(camera: false),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('选图识别'),
                ),
                OutlinedButton.icon(
                  onPressed: _pasteOcrText,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('粘贴文本'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wedgeField() {
    return TextField(
      controller: _barcodeField,
      focusNode: _barcodeFocus,
      decoration: InputDecoration(
        labelText: '扫码枪 / 粘贴条码或进货单码',
        hintText: '扫描后回车',
        prefixIcon: const Icon(Icons.qr_code_scanner),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.keyboard_return),
          onPressed: () => _onWedgeSubmit(_barcodeField.text),
        ),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: _onWedgeSubmit,
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'[\u0000]')),
      ],
    );
  }

  Widget _lineTile(int i) {
    final line = _lines[i];
    final tag = line.willCreate ? '将新建' : '已有商品';
    final tagColor =
        line.willCreate ? CnkhColors.warning : CnkhColors.success;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: line.selected,
          onChanged: (v) => setState(() => line.selected = v ?? false),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                line.name.isEmpty ? '(无品名)' : line.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  color: tagColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${line.barcode.isNotEmpty ? line.barcode : line.sku} · '
          '数量 ${line.qty} · 进货价 ${formatRm(line.unitCostCents)}'
          '${line.willCreate ? " · 售价 ${formatRm(line.effectiveSellCents)}" : ""}'
          '${line.matchNote.isNotEmpty ? "\n${line.matchNote}" : ""}'
          '${line.confidence < 0.55 ? " · 低置信度" : ""}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _editLine(i),
        ),
        onTap: () => _editLine(i),
        onLongPress: () => setState(() => _lines.removeAt(i)),
      ),
    );
  }

  Widget _bottomBar() {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('进货合计',
                        style: TextStyle(color: CnkhColors.muted, fontSize: 12)),
                    MoneyText(amountCents: _totalCents, fontSize: 22),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _lines.isEmpty ? null : _commit,
                icon: const Icon(Icons.check),
                label: const Text('核对并提交'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
