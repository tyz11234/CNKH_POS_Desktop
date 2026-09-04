import 'package:flutter/material.dart';

import '../models/money.dart';
import '../services/bluetooth_printer.dart';
import '../services/pos_repository.dart';
import '../services/receipt_template.dart';
import '../theme/cnkh_theme.dart';
import '../widgets/e_receipt_actions.dart';
import '../widgets/money_text.dart';
import '../widgets/receipt_preview_pane.dart';

/// Full-page receipt detail: same [ReceiptTemplate.renderFromSale] as print / e-receipt.
class SaleReceiptDetailScreen extends StatefulWidget {
  final SaleRecord sale;
  final PosRepository repo;

  const SaleReceiptDetailScreen({
    super.key,
    required this.sale,
    required this.repo,
  });

  static Future<void> open(
    BuildContext context, {
    required SaleRecord sale,
    required PosRepository repo,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SaleReceiptDetailScreen(sale: sale, repo: repo),
      ),
    );
  }

  @override
  State<SaleReceiptDetailScreen> createState() =>
      _SaleReceiptDetailScreenState();
}

class _SaleReceiptDetailScreenState extends State<SaleReceiptDetailScreen> {
  bool _loading = true;
  String _receiptText = '';
  String? _error;

  SaleRecord get sale => widget.sale;
  bool get voided => sale.voided == 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final template = await ReceiptTemplate.load(widget.repo);
      final text = template.renderFromSale(sale);
      if (!mounted) return;
      setState(() {
        _receiptText = text;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _printBt() async {
    final bt = BluetoothPrinterService(widget.repo);
    final msg = await bt.tryPrintSale(sale);
    if (!mounted) return;
    if (msg == 'bt_off') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('蓝牙打印未开启 / BT printer off')),
      );
    } else if (msg == 'ok') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已发送蓝牙小票 / Printed')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: CnkhColors.danger),
      );
    }
  }

  String get _soldAtLabel {
    final raw = sale.soldAt;
    if (raw.length >= 19) {
      return raw.substring(0, 19).replaceFirst('T', ' ');
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小票详情 / Receipt'),
        leading: IconButton(
          tooltip: '返回 / Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '加载失败 / Failed: $_error',
                      style: const TextStyle(color: CnkhColors.danger),
                    ),
                  ),
                )
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetaHeader(sale: sale, soldAtLabel: _soldAtLabel, voided: voided),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '小票预览 / Receipt preview (80mm)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: CnkhColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ReceiptPreviewPane(
                        text: _receiptText,
                        fill: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _ActionBar(
          voided: voided,
          onEReceipt: () => sendEReceiptFlow(
            context,
            sale: sale,
            repo: widget.repo,
          ),
          onPrint: _printBt,
          onClose: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _MetaHeader extends StatelessWidget {
  final SaleRecord sale;
  final String soldAtLabel;
  final bool voided;

  const _MetaHeader({
    required this.sale,
    required this.soldAtLabel,
    required this.voided,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CnkhColors.border)),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _chip(Icons.receipt, '单号', sale.receiptNo),
            _chip(Icons.schedule, '时间', soldAtLabel),
            _chip(Icons.person_outline, '收银', sale.cashier),
            _chip(Icons.payments_outlined, '付款', sale.paymentMethod),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('合计 / Total  ',
                    style: TextStyle(fontSize: 12, color: CnkhColors.muted)),
                MoneyText(amountCents: sale.totalCents, fontSize: 18),
              ],
            ),
            if ((sale.customerName ?? '').isNotEmpty ||
                (sale.customerPhone ?? '').isNotEmpty)
              _chip(
                Icons.contact_phone_outlined,
                '客户',
                [
                  if ((sale.customerName ?? '').isNotEmpty) sale.customerName!,
                  if ((sale.customerPhone ?? '').isNotEmpty) sale.customerPhone!,
                ].join(' · '),
              ),
            if (voided)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8E8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '已作废 / VOID${sale.voidNote.isNotEmpty ? ': ${sale.voidNote}' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB00020),
                  ),
                ),
              ),
            if (sale.creditOutstandingCents > 0)
              Text(
                '欠款 ${formatRm(sale.creditOutstandingCents)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB26A00),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: CnkhColors.muted),
        const SizedBox(width: 4),
        Text(
          '$label ',
          style: const TextStyle(fontSize: 12, color: CnkhColors.muted),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool voided;
  final VoidCallback onEReceipt;
  final VoidCallback onPrint;
  final VoidCallback onClose;

  const _ActionBar({
    required this.voided,
    required this.onEReceipt,
    required this.onPrint,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (!voided)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: onEReceipt,
                  icon: const Icon(Icons.picture_as_pdf, size: 20),
                  label: const Text('电子收据 PDF / E-receipt'),
                ),
              if (!voided)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: onPrint,
                  icon: const Icon(Icons.print, size: 20),
                  label: const Text('蓝牙打印 / BT print'),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: onClose,
                child: const Text('关闭 / Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
