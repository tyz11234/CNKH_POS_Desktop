import 'package:flutter/material.dart';

import '../models/money.dart';
import '../services/pos_repository.dart';
import '../theme/cnkh_theme.dart';
import '../widgets/e_receipt_actions.dart';
import 'sale_receipt_detail_screen.dart';
import '../widgets/money_text.dart';

class SalesListScreen extends StatefulWidget {
  final PosRepository repo;
  final bool todayOnly;
  final bool canVoid;
  final bool asRoute;
  final int refreshToken;

  const SalesListScreen({
    super.key,
    required this.repo,
    this.todayOnly = true,
    this.canVoid = false,
    this.asRoute = false,
    this.refreshToken = 0,
  });

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  List<SaleRecord> _sales = [];
  List<SaleRecord> _filtered = [];
  bool _loading = true;
  final _q = TextEditingController();
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SalesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.todayOnly != widget.todayOnly) {
      _load();
    }
  }

  Future<void> _load() async {
    final list = widget.todayOnly
        ? await widget.repo.salesToday()
        : await widget.repo.salesAll();
    if (!mounted) return;
    setState(() {
      _sales = list;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _q.text.trim().toLowerCase();
    setState(() {
      _filtered = [
        for (final s in _sales)
          if (_match(s, q)) s,
      ];
    });
  }

  bool _match(SaleRecord s, String q) {
    if (_from != null) {
      final sold = DateTime.tryParse(s.soldAt);
      if (sold != null && sold.isBefore(_from!)) return false;
    }
    if (_to != null) {
      final sold = DateTime.tryParse(s.soldAt);
      final end = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59);
      if (sold != null && sold.isAfter(end)) return false;
    }
    if (q.isEmpty) return true;
    final phone = (s.customerPhone ?? '').toLowerCase();
    final name = (s.customerName ?? '').toLowerCase();
    return s.receiptNo.toLowerCase().contains(q) ||
        phone.contains(q) ||
        name.contains(q) ||
        s.paymentMethod.toLowerCase().contains(q);
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() => _from = d);
    _applyFilter();
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() => _to = d);
    _applyFilter();
  }

  Future<void> _void(SaleRecord s) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('作废备注 / Void note'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '原因 / Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('作废')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.voidSale(s.id, ctrl.text.trim().isEmpty ? 'void' : ctrl.text.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              TextField(
                controller: _q,
                decoration: const InputDecoration(
                  hintText: '搜索单号 / 手机 / 客户',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(_from == null
                        ? '从日期'
                        : _from!.toIso8601String().substring(0, 10)),
                  ),
                  TextButton.icon(
                    onPressed: _pickTo,
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(_to == null
                        ? '到日期'
                        : _to!.toIso8601String().substring(0, 10)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _from = null;
                        _to = null;
                        _q.clear();
                      });
                      _applyFilter();
                    },
                    child: const Text('清除'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                              child: Text('暂无销售记录 / No sales',
                                  style: TextStyle(color: CnkhColors.muted))),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final s = _filtered[i];
                          final voided = s.voided == 1;
                          return Card(
                            color: voided ? const Color(0xFFFFF1F1) : null,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => SaleReceiptDetailScreen.open(
                                context,
                                sale: s,
                                repo: widget.repo,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${s.receiptNo} · ${s.paymentMethod}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              decoration: voided
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${s.soldAt.substring(0, 19).replaceFirst('T', ' ')}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: CnkhColors.muted,
                                            ),
                                          ),
                                          Text(
                                            '${s.customerName ?? s.cashier}'
                                            '${(s.customerPhone ?? '').isNotEmpty ? ' · ${s.customerPhone}' : ''}'
                                            '${s.creditOutstandingCents > 0 ? ' · 欠 ${formatRm(s.creditOutstandingCents)}' : ''}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                          if (voided)
                                            Text(
                                              'VOID: ${s.voidNote}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFFB00020),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        MoneyText(
                                            amountCents: s.totalCents, fontSize: 16),
                                        const SizedBox(height: 2),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!voided)
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                tooltip: 'E-receipt PDF',
                                                icon: const Icon(
                                                  Icons.picture_as_pdf,
                                                  color: Color(0xFF25D366),
                                                  size: 22,
                                                ),
                                                onPressed: () => sendEReceiptFlow(
                                                  context,
                                                  sale: s,
                                                  repo: widget.repo,
                                                ),
                                              ),
                                            if (widget.canVoid && !voided)
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: const Size(36, 28),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                onPressed: () => _void(s),
                                                child: const Text('作废',
                                                    style: TextStyle(fontSize: 12)),
                                              ),
                                            const Icon(
                                              Icons.chevron_right,
                                              color: CnkhColors.muted,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
    if (!widget.asRoute) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.todayOnly ? '今日销售 / Today' : '销售记录 / Sales'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                tooltip: '返回 / Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: body,
    );
  }
}
