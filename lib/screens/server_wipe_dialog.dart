import 'package:flutter/material.dart';

import '../services/lan_sync.dart';
import '../services/pos_repository.dart';
import '../theme/cnkh_theme.dart';

/// One selectable server-data category for the go-live wipe.
class WipeCategory {
  final String key;
  final String label;
  final bool paymentsLedger;
  const WipeCategory(this.key, this.label, {this.paymentsLedger = false});
}

const kWipeCategories = <WipeCategory>[
  WipeCategory('sales', '销售记录'),
  WipeCategory('purchases', '采购记录'),
  WipeCategory('payments', '收款记录（到账账本）', paymentsLedger: true),
  WipeCategory('stock_moves', '库存流水'),
  WipeCategory('held_orders', '挂单'),
  WipeCategory('daily_closings', '日结记录'),
  WipeCategory('einvoices', '电子发票记录'),
  WipeCategory('products', '商品'),
  WipeCategory('customers', '客户'),
  WipeCategory('suppliers', '供应商'),
  WipeCategory('categories', '商品分类'),
  WipeCategory('audit', '审计日志与打印队列'),
  WipeCategory('stock_zero', '库存数量清零（保留商品）'),
];

/// Checkbox dialog for wiping TEST data off the server before go-live.
///
/// Flow: tick categories -> 「计算影响」 (dry run, shows exact counts) ->
/// 「确认清空」 -> done. Accounts are never wiped. The server bumps its
/// data epoch on a real wipe, so other devices refuse to push pre-wipe
/// data back and prompt for a local reset instead.
class ServerWipeDialog extends StatefulWidget {
  final PosRepository repo;
  final LanSyncConfig cfg;
  const ServerWipeDialog({super.key, required this.repo, required this.cfg});

  @override
  State<ServerWipeDialog> createState() => _ServerWipeDialogState();
}

class _ServerWipeDialogState extends State<ServerWipeDialog> {
  final _selected = <String>{};
  Map<String, int>? _dryCounts;
  Map<String, int>? _doneCounts;
  bool _busy = false;
  String? _error;

  LanSyncClient get _client => LanSyncClient(widget.repo);

  List<String> get _hostCats => [
    for (final c in kWipeCategories)
      if (_selected.contains(c.key) && !c.paymentsLedger) c.key,
  ];
  bool get _withPayments => _selected.contains('payments');

  Future<Map<String, int>> _run({required bool dryRun}) async {
    final merged = <String, int>{};
    if (_hostCats.isNotEmpty || !dryRun) {
      final r = await _client.adminWipe(widget.cfg, _hostCats, dryRun: dryRun);
      (r['counts'] as Map?)?.forEach((k, v) {
        if (k != '_epoch') merged['$k'] = (v as num).toInt();
      });
    }
    if (_withPayments) {
      final r = await _client.adminWipePayments(widget.cfg, dryRun: dryRun);
      (r['counts'] as Map?)?.forEach((k, v) {
        merged['$k'] = (v as num).toInt();
      });
    }
    return merged;
  }

  Future<void> _dryRun() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final counts = await _run(dryRun: true);
      if (!mounted) return;
      setState(() => _dryCounts = counts);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '计算失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('最后确认'),
        content: Text(
          '将永久删除服务器上勾选的 ${_selected.length} 类数据，共约 '
          '${_dryCounts?.values.fold<int>(0, (a, b) => a + b) ?? 0} 条。\n\n'
          '此操作不可恢复。账号密码不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CnkhColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final counts = await _run(dryRun: false);
      if (!mounted) return;
      setState(() => _doneCounts = counts);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '清空失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_doneCounts != null) {
      final total = _doneCounts!.values.fold<int>(0, (a, b) => a + b);
      return AlertDialog(
        title: const Text('服务器数据已清空'),
        content: Text(
          '共删除 $total 条数据。\n\n'
          '接下来请在本机执行一次「初始化 / 清空全部数据」，'
          '然后用管理员账号重新登录。其他设备下次连接时会收到提示，'
          '同样需要先做本机初始化——旧的测试数据不会再回流到服务器。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('清空服务器测试数据'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '勾选要清除的数据类别。此操作只影响服务器，账号密码不会被清除。',
                style: TextStyle(fontSize: 13, color: CnkhColors.muted),
              ),
              const SizedBox(height: 8),
              for (final c in kWipeCategories)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected.contains(c.key),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            _selected.add(c.key);
                          } else {
                            _selected.remove(c.key);
                          }
                          _dryCounts = null;
                        }),
                  title: Text(c.label),
                  subtitle: _dryCounts != null && _selected.contains(c.key)
                      ? Text(
                          '将删除 ${_dryCounts![c.key] ?? 0} 条',
                          style: const TextStyle(color: CnkhColors.danger),
                        )
                      : null,
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: CnkhColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: _busy || _selected.isEmpty ? null : _dryRun,
          child: const Text('计算影响'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: CnkhColors.danger),
          onPressed: _busy || _dryCounts == null ? null : _execute,
          child: Text(_busy ? '处理中…' : '确认清空'),
        ),
      ],
    );
  }
}
