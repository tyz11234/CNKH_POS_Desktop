import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/cart_item.dart';
import '../models/money.dart';
import '../services/pos_repository.dart';
import '../services/qr_storage.dart';
import '../theme/cnkh_theme.dart';
import '../widgets/duitnow_qr_panel.dart';
import '../widgets/money_text.dart';
import '../widgets/cash_change_dialog.dart';
import '../services/e_receipt.dart' show formatRmPlain;

enum PayMethod { cash, card, duitnow, credit }

class CheckoutScreen extends StatefulWidget {
  final CartState cart;
  final AppUser user;
  final QrStorage qrStorage;
  final PosRepository repo;
  final void Function(SaleRecord sale) onPaid;
  final VoidCallback onCancel;

  const CheckoutScreen({
    super.key,
    required this.cart,
    required this.user,
    required this.qrStorage,
    required this.repo,
    required this.onPaid,
    required this.onCancel,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  PayMethod _method = PayMethod.cash;
  PayMethod _deposit = PayMethod.cash;
  String? _qrPath;
  final _cashCtrl = TextEditingController();
  final _depositCtrl = TextEditingController(text: '0.00');
  final _phoneCtrl = TextEditingController();
  List<Customer> _customers = [];
  Customer? _customer;
  bool _busy = false;
  int _outstandingCents = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _cashCtrl.addListener(() => setState(() {}));
    _depositCtrl.addListener(() => setState(() {}));
  }

  Future<void> _load() async {
    final qr = await widget.qrStorage.getLocalPath();
    final customers = await widget.repo.listCustomers();
    if (!mounted) return;
    setState(() {
      _qrPath = qr;
      _customers = customers;
      _syncCashField();
    });
  }

  void _syncCashField() {
    final due = widget.cart.payableCents(isCredit: _method == PayMethod.credit);
    _cashCtrl.text = centsToRm(due).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _depositCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  int get _raw => widget.cart.rawPayableCents;
  int get _due =>
      widget.cart.payableCents(isCredit: _method == PayMethod.credit);
  int get _rounding =>
      _method == PayMethod.credit ? 0 : checkoutRoundingAdjustment(_raw);

  int _parseRm(String text) {
    final raw = text.trim().replaceAll(',', '');
    final rm = double.tryParse(raw);
    if (rm == null) return 0;
    return rmToCents(rm);
  }

  String _methodKey(PayMethod m) => switch (m) {
        PayMethod.cash => 'CASH',
        PayMethod.card => 'CARD',
        PayMethod.duitnow => 'DUITNOW_QR',
        PayMethod.credit => 'CREDIT',
      };

  String _methodLabel(PayMethod m) => switch (m) {
        PayMethod.cash => '现金\nCash',
        PayMethod.card => '卡\nCard',
        PayMethod.duitnow => 'DuitNow',
        PayMethod.credit => '赊账\nCredit',
      };

  Future<void> _confirm() async {
    if (_busy) return;
    final policy = await widget.repo.stockPolicy();
    for (final item in widget.cart.items) {
      if (item.qty > item.product.stock) {
        if (policy == 'block') {
          _toast('库存不足：${item.product.nameZh} (有 ${item.product.stock})', error: true);
          return;
        }
        final cont = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('库存不足 / Low stock'),
            content: Text('${item.product.nameZh}\n需要 ${item.qty} · 库存 ${item.product.stock}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('仍结账')),
            ],
          ),
        );
        if (cont != true) return;
      }
    }
    if (_method == PayMethod.credit) {
      if (_customer == null) {
        _toast('赊账必须选择客户 / Credit requires a customer', error: true);
        return;
      }
      final deposit = _parseRm(_depositCtrl.text);
      if (deposit > _raw) {
        _toast('定金不能超过应付 / Deposit exceeds total', error: true);
        return;
      }
      if (deposit > 0 && _deposit == PayMethod.credit) {
        _toast('定金方式无效 / Invalid deposit method', error: true);
        return;
      }
    } else {
      final paid = _method == PayMethod.cash ? _parseRm(_cashCtrl.text) : _due;
      if (paid < _due) {
        _toast('金额不足 / Insufficient', error: true);
        return;
      }
    }

    setState(() => _busy = true);
    try {
      final isCredit = _method == PayMethod.credit;
      final paid = isCredit
          ? _parseRm(_depositCtrl.text)
          : (_method == PayMethod.cash ? _parseRm(_cashCtrl.text) : _due);
      final phone = _phoneCtrl.text.trim();
      final sale = await widget.repo.createSale(
        cart: widget.cart,
        paymentMethod: _methodKey(_method),
        paidCents: paid,
        cashier: widget.user.username,
        depositMethod: isCredit && paid > 0 ? _methodKey(_deposit) : null,
        customer: _customer,
        customerPhone: phone.isNotEmpty ? phone : _customer?.phone,
      );
      if (!mounted) return;
      if (_method == PayMethod.cash) {
        await showCashChangeDialog(
          context,
          tenderedCents: paid,
          dueCents: _due,
        );
      }
      if (!mounted) return;
      widget.onPaid(sale);
    } catch (e) {
      _toast('$e', error: true);
      setState(() => _busy = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? CnkhColors.danger : null,
      ),
    );
  }

  Widget _payChip(PayMethod m) {
    final selected = _method == m;
    return Expanded(
      child: Material(
        color: selected ? CnkhColors.navy : CnkhColors.softBlue,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _method = m;
            _syncCashField();
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? CnkhColors.navy : CnkhColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Text(
              _methodLabel(m),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : CnkhColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tendered = _parseRm(_cashCtrl.text);
    final change = tendered - _due;

    return Scaffold(
      appBar: AppBar(
        title: const Text('结账 / Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: CnkhColors.softBlue,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      children: [
                        Text(
                          '应付 / Due',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: CnkhColors.navy,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MoneyText(
                              amountCents: _due, fontSize: 40, hero: true),
                        ),
                        if (_rounding != 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            '舍入 / Rounding: ${formatRm(_rounding)}  (raw ${formatRm(_raw)})',
                            style: const TextStyle(
                                color: CnkhColors.muted, fontSize: 12),
                          ),
                        ],
                        if (widget.cart.orderDiscountApplied > 0 ||
                            widget.cart.itemDiscountsCents > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '折扣 / Discounts: −${formatRm(widget.cart.itemDiscountsCents + widget.cart.orderDiscountApplied)}',
                            style: const TextStyle(
                                color: CnkhColors.success, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('付款方式 / Payment',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < PayMethod.values.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _payChip(PayMethod.values[i]),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '客户 / Customer（赊账必选；电子收据可选）',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Customer?>(
                      isExpanded: true,
                      value: _customer,
                      hint: const Text('选择客户 / Select'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— 无 —')),
                        ..._customers.map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              '${c.name}  ${c.phone}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (c) async {
                        setState(() {
                          _customer = c;
                          _outstandingCents = 0;
                          if (c != null && c.phone.trim().isNotEmpty) {
                            _phoneCtrl.text = c.phone;
                          }
                        });
                        if (c != null) {
                          final o =
                              await widget.repo.customerOutstandingCents(c.id);
                          if (mounted) setState(() => _outstandingCents = o);
                        }
                      },
                    ),
                  ),
                ),
                if (_customer != null && _outstandingCents > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CnkhColors.danger),
                    ),
                    child: Text(
                      '⚠ 赊账未结 / Outstanding: ${formatRmPlain(_outstandingCents)}',
                      style: const TextStyle(
                        color: CnkhColors.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '手机号 / Phone（电子收据可选）',
                    hintText: '01x-xxx xxxx',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                if (_method == PayMethod.duitnow)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DuitNowQrPanel(
                        imagePath: _qrPath,
                        amountCents: _due,
                        fullscreenFriendly: true,
                        onPickImage: () => _toast(
                            '请到设置导入 QR（仅管理员）/ Import QR in Settings (Admin)'),
                        onTapExpand: _qrPath == null
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DuitNowQrFullscreen(
                                      imagePath: _qrPath!,
                                      amountCents: _due,
                                    ),
                                  ),
                                );
                              },
                      ),
                    ),
                  )
                else if (_method == PayMethod.cash) ...[
                  TextField(
                    controller: _cashCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                      labelText: '收取现金 / Cash tendered',
                      prefixText: 'RM ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: change >= 0
                          ? const Color(0xFFE8F8EE)
                          : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: change >= 0
                            ? CnkhColors.success
                            : CnkhColors.danger,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          change >= 0 ? '找零 / Change' : '金额不足 / Insufficient',
                          style: TextStyle(
                            color: change >= 0
                                ? CnkhColors.successDeep
                                : CnkhColors.danger,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatRm(change < 0 ? 0 : change),
                            style: TextStyle(
                              color: change >= 0
                                  ? CnkhColors.success
                                  : CnkhColors.danger,
                              fontWeight: FontWeight.w900,
                              fontSize: 32,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_method == PayMethod.card)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '请刷卡后确认 / Complete card payment then confirm.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else ...[
                  Text('定金 / Deposit',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _depositCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '定金金额 / Deposit amount',
                      prefixText: 'RM ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in [
                        PayMethod.cash,
                        PayMethod.card,
                        PayMethod.duitnow
                      ])
                        FilterChip(
                          label: Text(_methodKey(m)),
                          selected: _deposit == m,
                          selectedColor: CnkhColors.navy,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _deposit == m
                                ? Colors.white
                                : CnkhColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) => setState(() => _deposit = m),
                        ),
                    ],
                  ),
                  if (_deposit == PayMethod.duitnow &&
                      _parseRm(_depositCtrl.text) > 0) ...[
                    const SizedBox(height: 12),
                    DuitNowQrPanel(
                      imagePath: _qrPath,
                      amountCents: _parseRm(_depositCtrl.text),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CnkhColors.softBlue,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CnkhColors.border),
                    ),
                    child: Text(
                      '赊账余额 / Outstanding: ${formatRm((_raw - _parseRm(_depositCtrl.text)).clamp(0, _raw))}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: CnkhColors.navy,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: CnkhColors.success),
                  onPressed: _busy ? null : _confirm,
                  child: Text(
                    _busy ? '保存中…' : '确认收款 / Confirm',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
