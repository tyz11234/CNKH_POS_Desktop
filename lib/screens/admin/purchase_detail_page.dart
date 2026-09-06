import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/pos_repository.dart';
import '../../services/purchase_attachment_store.dart';
import '../../services/purchase_edit_service.dart';
import '../../theme/cnkh_theme.dart';
import '../../widgets/money_text.dart';

class PurchaseDetailPage extends StatefulWidget {
  const PurchaseDetailPage({
    super.key,
    required this.repo,
    required this.purchaseId,
  });

  final PosRepository repo;
  final String purchaseId;

  @override
  State<PurchaseDetailPage> createState() => _PurchaseDetailPageState();
}

class _PurchaseDetailPageState extends State<PurchaseDetailPage> {
  Map<String, Object?>? _purchase;
  List<PurchaseAttachmentInfo> _attachments = const [];
  bool _loading = true;
  bool _exporting = false;
  bool _editing = false;

  PurchaseAttachmentStore get _store =>
      PurchaseAttachmentStore(database: widget.repo.database);
  PurchaseEditService get _editService => PurchaseEditService(widget.repo);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await widget.repo.database.db;
    final rows = await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: [widget.purchaseId],
      limit: 1,
    );
    final attachments = await _store.listForPurchase(widget.purchaseId);
    if (!mounted) return;
    setState(() {
      _purchase = rows.isEmpty ? null : rows.first;
      _attachments = attachments;
      _loading = false;
    });
  }

  String _moneyText(Object? value) {
    final cents = (value as num?)?.toInt() ?? 0;
    return (cents / 100).toStringAsFixed(2);
  }

  Future<void> _edit() async {
    if (_editing || _purchase == null) return;
    final purchase = _purchase!;
    if ((purchase['reversed'] as num?)?.toInt() == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已撤销的进货记录不能再编辑')),
      );
      return;
    }

    final suppliers = await widget.repo.listSuppliers();
    if (!mounted) return;
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用供应商，请先建立供应商。')),
      );
      return;
    }

    var supplier = suppliers.firstWhere(
      (s) => s.id == purchase['supplier_id']?.toString(),
      orElse: () => suppliers.first,
    );
    final invoiceNo = TextEditingController(
      text: purchase['invoice_no']?.toString() ?? '',
    );
    final invoiceDate = TextEditingController(
      text: purchase['invoice_date']?.toString() ?? '',
    );
    final discount = TextEditingController(
      text: _moneyText(purchase['discount_cents']),
    );
    final tax = TextEditingController(text: _moneyText(purchase['tax_cents']));
    final delivery = TextEditingController(
      text: _moneyText(purchase['delivery_fee_cents']),
    );
    final other = TextEditingController(
      text: _moneyText(purchase['other_fee_cents']),
    );
    final total = TextEditingController(text: _moneyText(purchase['total_cents']));
    final notes = TextEditingController(text: purchase['notes']?.toString() ?? '');
    final errors = <String, String?>{};
    PurchaseEditInput? input;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          int? parse(String key, TextEditingController controller) {
            final cents = PurchaseEditService.parseMoneyCents(controller.text);
            errors[key] = cents == null ? '金额格式错误，例如 12.50 或 1,234.56' : null;
            return cents;
          }

          return AlertDialog(
            title: const Text('编辑进货资料 / Edit Purchase'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '为保护库存历史，这里只编辑结构化资料与费用。商品数量/成本/库存如需纠正，请使用 Reverse 后重新进货或库存调整。',
                        style: TextStyle(color: CnkhColors.muted, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Supplier>(
                      initialValue: supplier,
                      decoration: const InputDecoration(labelText: '供应商 / Supplier'),
                      items: [
                        for (final s in suppliers)
                          DropdownMenuItem(value: s, child: Text(s.name)),
                      ],
                      onChanged: (value) {
                        if (value != null) setLocal(() => supplier = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: invoiceNo,
                      decoration: const InputDecoration(labelText: 'Invoice No'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: invoiceDate,
                      decoration: const InputDecoration(
                        labelText: 'Invoice Date',
                        hintText: 'YYYY-MM-DD',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _moneyField('Discount RM', 'discount', discount, errors),
                    const SizedBox(height: 8),
                    _moneyField('Tax / SST RM', 'tax', tax, errors),
                    const SizedBox(height: 8),
                    _moneyField('Delivery RM', 'delivery', delivery, errors),
                    const SizedBox(height: 8),
                    _moneyField('Other Fee RM', 'other', other, errors),
                    const SizedBox(height: 8),
                    _moneyField('Total RM', 'total', total, errors),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: '备注 / Notes'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final d = parse('discount', discount);
                  final t = parse('tax', tax);
                  final del = parse('delivery', delivery);
                  final oth = parse('other', other);
                  final tot = parse('total', total);
                  if (<int?>[d, t, del, oth, tot].any((v) => v == null)) {
                    setLocal(() {});
                    return;
                  }
                  input = PurchaseEditInput(
                    supplierId: supplier.id,
                    invoiceNo: invoiceNo.text,
                    invoiceDate: invoiceDate.text,
                    discountCents: d!,
                    taxCents: t!,
                    deliveryFeeCents: del!,
                    otherFeeCents: oth!,
                    totalCents: tot!,
                    notes: notes.text,
                  );
                  Navigator.pop(ctx, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    for (final controller in <TextEditingController>[
      invoiceNo,
      invoiceDate,
      discount,
      tax,
      delivery,
      other,
      total,
      notes,
    ]) {
      controller.dispose();
    }
    if (ok != true || input == null || !mounted) return;

    setState(() => _editing = true);
    try {
      await _editService.updateMetadata(
        purchaseId: widget.purchaseId,
        input: input!,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('进货资料已更新；库存与进货明细数量未改变。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e'), backgroundColor: CnkhColors.danger),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Widget _moneyField(
    String label,
    String key,
    TextEditingController controller,
    Map<String, String?> errors,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'RM ',
        errorText: errors[key],
      ),
    );
  }

  Future<void> _export(PurchaseAttachmentInfo attachment) async {
    if (_exporting) return;
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择原始进货单导出文件夹',
    );
    if (!mounted) return;
    if (dir == null || dir.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消导出 / Export cancelled')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final file = await _store.exportToDirectory(
        attachment.id,
        Directory(dir),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('原始单据已导出：${file.path}'),
          action: SnackBarAction(
            label: '打开文件夹',
            onPressed: () => _openFolder(file.parent.path),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('附件导出失败：$e'),
          backgroundColor: CnkhColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openFolder(String path) async {
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('explorer.exe', <String>[path]);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', <String>[path]);
      } else if (Platform.isLinux) {
        result = await Process.run('xdg-open', <String>[path]);
      } else {
        throw UnsupportedError('当前平台不支持打开文件夹');
      }
      if (result.exitCode != 0) {
        throw StateError('系统返回 ${result.exitCode}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件夹：$e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  Widget _field(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(
                label,
                style: const TextStyle(
                  color: CnkhColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(child: SelectableText(value?.toString() ?? '')),
          ],
        ),
      );

  List<Map<String, dynamic>> _lines(Map<String, Object?> purchase) {
    try {
      final raw = jsonDecode(purchase['lines_json']?.toString() ?? '[]');
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchase = _purchase;
    final lines = purchase == null ? const <Map<String, dynamic>>[] : _lines(purchase);
    return Scaffold(
      appBar: AppBar(
        title: const Text('进货详情 / Purchase Detail'),
        actions: [
          if (purchase != null && purchase['reversed'] != 1)
            IconButton(
              tooltip: '编辑进货资料 / Edit',
              onPressed: _editing ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : purchase == null
              ? const Center(child: Text('进货记录不存在'))
              : Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${purchase['purchase_no']} · ${purchase['supplier_name']}',
                                        style: Theme.of(context).textTheme.titleLarge,
                                      ),
                                    ),
                                    MoneyText(
                                      amountCents:
                                          (purchase['total_cents'] as num).toInt(),
                                      fontSize: 18,
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                _field('时间 / Purchased at', purchase['purchased_at']),
                                _field('Invoice No', purchase['invoice_no']),
                                _field('Invoice Date', purchase['invoice_date']),
                                _field('Discount', 'RM ${_moneyText(purchase['discount_cents'])}'),
                                _field('Tax / SST', 'RM ${_moneyText(purchase['tax_cents'])}'),
                                _field('Delivery', 'RM ${_moneyText(purchase['delivery_fee_cents'])}'),
                                _field('Other Fee', 'RM ${_moneyText(purchase['other_fee_cents'])}'),
                                _field('来源 / Source', purchase['source']),
                                _field(
                                  '状态 / Status',
                                  purchase['reversed'] == 1 ? 'REVERSED' : 'COMMITTED',
                                ),
                                _field('备注 / Notes', purchase['notes']),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '进货明细 / Items',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                if (lines.isEmpty)
                                  const Text('没有可显示的进货明细')
                                else
                                  for (final line in lines)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        line['name']?.toString() ??
                                            line['rawProductName']?.toString() ??
                                            line['productId']?.toString() ??
                                            '',
                                      ),
                                      subtitle: Text(
                                        'Qty ${line['invoiceQty'] ?? line['qty'] ?? ''} '
                                        '${line['unit'] ?? ''} · Conversion ${line['conversionFactor'] ?? line['conversion_factor'] ?? 1}',
                                      ),
                                      trailing: Text(
                                        'RM ${_moneyText(line['subtotalCents'] ?? line['lineSubtotalCents'])}',
                                      ),
                                    ),
                                const SizedBox(height: 4),
                                const Text(
                                  '已入库数量/成本不在这里直接改写；需要纠正库存时请使用 Reverse + 正确进货，或库存调整。',
                                  style: TextStyle(color: CnkhColors.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '原始单据 / Invoice Evidence',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '附件导出前会重新校验 SHA-256。校验失败时不会写出损坏文件。',
                                  style: TextStyle(
                                    color: CnkhColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (_attachments.isEmpty)
                                  const Text('此进货单没有已同步的 Original Invoice 附件。')
                                else
                                  for (final attachment in _attachments)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.attach_file),
                                      title: Text(
                                        attachment.filename.isEmpty
                                            ? attachment.kind
                                            : attachment.filename,
                                      ),
                                      subtitle: Text(
                                        '${attachment.kind}\nSHA-256 ${attachment.contentHash}',
                                      ),
                                      isThreeLine: true,
                                      trailing: FilledButton.icon(
                                        onPressed: _exporting
                                            ? null
                                            : () => _export(attachment),
                                        icon: const Icon(Icons.folder_outlined),
                                        label: const Text('导出'),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'OCR Evidence',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  purchase['ocr_raw_text']?.toString().isEmpty == false
                                      ? purchase['ocr_raw_text'].toString()
                                      : '无 OCR 原始文字',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_editing)
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Color(0x22000000),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
