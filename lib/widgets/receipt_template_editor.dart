import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pos_repository.dart';
import '../services/receipt_template.dart';
import '../theme/cnkh_theme.dart';
import 'receipt_preview_pane.dart';

/// Admin settings: left editors + right live 80mm-style preview.
/// Preview updates on every keystroke / toggle (no Save needed for preview).
class ReceiptTemplateEditor extends StatefulWidget {
  final PosRepository repo;
  final bool canEdit;

  const ReceiptTemplateEditor({
    super.key,
    required this.repo,
    required this.canEdit,
  });

  @override
  State<ReceiptTemplateEditor> createState() => _ReceiptTemplateEditorState();
}

class _ReceiptTemplateEditorState extends State<ReceiptTemplateEditor> {
  final _store = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _notes = TextEditingController();
  final _width = TextEditingController(text: '$kDefaultReceiptCharWidth');

  bool _loading = true;
  bool _saving = false;

  bool _showSku = true;
  bool _showCashier = true;
  bool _showDatetime = true;
  bool _showPayment = true;
  bool _showChange = true;
  bool _showDiscount = true;
  bool _showUnitPrice = true;
  bool _showQty = true;
  bool _showDuitNowQr = false;

  late final VoidCallback _rebuild;

  @override
  void initState() {
    super.initState();
    _rebuild = () {
      if (mounted) setState(() {});
    };
    for (final c in [
      _store,
      _address,
      _phone,
      _header,
      _footer,
      _notes,
      _width,
    ]) {
      c.addListener(_rebuild);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _store,
      _address,
      _phone,
      _header,
      _footer,
      _notes,
      _width,
    ]) {
      c.removeListener(_rebuild);
      c.dispose();
    }
    super.dispose();
  }

  ReceiptTemplate get _draft {
    final w = int.tryParse(_width.text.trim()) ?? kDefaultReceiptCharWidth;
    return ReceiptTemplate(
      storeName: _store.text,
      address: _address.text,
      phone: _phone.text,
      headerLines: _header.text,
      footerLines: _footer.text,
      notes: _notes.text,
      showSku: _showSku,
      showCashier: _showCashier,
      showDatetime: _showDatetime,
      showPaymentMethod: _showPayment,
      showChange: _showChange,
      showDiscount: _showDiscount,
      showUnitPrice: _showUnitPrice,
      showQty: _showQty,
      showDuitNowQr: _showDuitNowQr,
      charWidth: w.clamp(24, 64),
    );
  }

  Future<void> _load() async {
    final t = await ReceiptTemplate.load(widget.repo);
    if (!mounted) return;
    setState(() {
      _store.text = t.storeName;
      _address.text = t.address;
      _phone.text = t.phone;
      _header.text = t.headerLines;
      _footer.text = t.footerLines;
      _notes.text = t.notes;
      _width.text = '${t.charWidth}';
      _showSku = t.showSku;
      _showCashier = t.showCashier;
      _showDatetime = t.showDatetime;
      _showPayment = t.showPaymentMethod;
      _showChange = t.showChange;
      _showDiscount = t.showDiscount;
      _showUnitPrice = t.showUnitPrice;
      _showQty = t.showQty;
      _showDuitNowQr = t.showDuitNowQr;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!widget.canEdit || _saving) return;
    setState(() => _saving = true);
    try {
      await _draft.save(widget.repo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('小票格式已保存 / Receipt template saved')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (!widget.canEdit || _saving) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认小票格式？'),
        content: const Text('将重置店名/地址/页眉页脚与显示开关为默认值。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ReceiptTemplate.resetToDefaults(widget.repo);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复默认 / Defaults restored')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(void Function() apply) {
    if (!widget.canEdit) return;
    setState(apply);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final previewText = _draft.renderSample();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('小票格式 / Receipt',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              widget.canEdit
                  ? '左侧编辑即时预览右侧 80mm 小票；打印与电子收据共用此模板。'
                  : '仅管理员可编辑小票格式 · Staff view-only',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: CnkhColors.muted),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final editors = _buildEditors();
                final preview = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('实时预览 / Live preview (80mm)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: CnkhColors.muted,
                              fontWeight: FontWeight.w600,
                            )),
                    const SizedBox(height: 8),
                    ReceiptPreviewPane(text: previewText),
                  ],
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: editors),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: preview),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    editors,
                    const SizedBox(height: 16),
                    preview,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditors() {
    final enabled = widget.canEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _store,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: '店名 / Store name',
            hintText: '黄金发宝号',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _address,
          enabled: enabled,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '地址 / Address',
            hintText: '多行可分行居中',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: '电话 / Phone',
            hintText: '03-xxxx xxxx',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _header,
          enabled: enabled,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '页眉 / Header lines',
            hintText: '每行一条，居中显示',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _footer,
          enabled: enabled,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '页脚 / Footer lines',
            hintText: 'Thank you / 谢谢光临',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          enabled: enabled,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '备注 / Notes',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _width,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '字符宽度 / Char width (80mm ≈ 40)',
            hintText: '40',
          ),
        ),
        const SizedBox(height: 8),
        Text('显示开关 / Show', style: Theme.of(context).textTheme.bodySmall),
        Wrap(
          children: [
            _sw('SKU/条码', _showSku, (v) => _toggle(() => _showSku = v)),
            _sw('收银员', _showCashier, (v) => _toggle(() => _showCashier = v)),
            _sw('日期时间', _showDatetime, (v) => _toggle(() => _showDatetime = v)),
            _sw('付款方式', _showPayment, (v) => _toggle(() => _showPayment = v)),
            _sw('找零', _showChange, (v) => _toggle(() => _showChange = v)),
            _sw('折扣行', _showDiscount, (v) => _toggle(() => _showDiscount = v)),
            _sw('单价', _showUnitPrice, (v) => _toggle(() => _showUnitPrice = v)),
            _sw('数量', _showQty, (v) => _toggle(() => _showQty = v)),
            _sw('DuitNow QR', _showDuitNowQr,
                (v) => _toggle(() => _showDuitNowQr = v)),
          ],
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存 / Save'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('恢复默认 / Reset'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sw(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: value,
      onSelected: widget.canEdit ? onChanged : null,
      selectedColor: CnkhColors.softBlue,
      checkmarkColor: CnkhColors.primary,
    );
  }
}
