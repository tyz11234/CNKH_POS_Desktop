import 'dart:async';
import 'package:flutter/material.dart';

import 'models/app_user.dart';
import 'models/cart_item.dart';
import 'screens/admin/admin_hub.dart';
import 'screens/admin/products_admin.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/sales_list_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/training_page.dart';
import 'screens/barcode_scan_screen.dart';
import 'services/pos_repository.dart';
import 'services/qr_storage.dart';
import 'services/bluetooth_printer.dart';
import 'services/lan_sync.dart';
import 'theme/cnkh_theme.dart';
import 'widgets/e_receipt_actions.dart';

/// Desktop shell: left NavigationRail + wide content area.
class DesktopShell extends StatefulWidget {
  final AppUser user;
  final QrStorage qrStorage;
  final PosRepository repo;
  final VoidCallback onLogout;

  const DesktopShell({
    super.key,
    required this.user,
    required this.qrStorage,
    required this.repo,
    required this.onLogout,
  });

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _index = 0;
  int _dataEpoch = 0;
  final CartState _cart = CartState();
  late final LanSyncClient _syncClient = LanSyncClient(widget.repo);
  late final LanLiveSync _live = LanLiveSync(_syncClient);
  SyncLinkState _linkState = SyncLinkState.offline;
  int _pending = 0;
  int _overdueHolds = 0;
  Timer? _holdPoll;
  bool _railExtended = true;

  @override
  void initState() {
    super.initState();
    _live.onRemoteChange = _bumpData;
    _live.onLowStock = (event) {
      if (!mounted) return;
      final name = (event['name'] ?? event['sku'] ?? '商品').toString();
      final stock = event['stock'];
      final thr = event['threshold'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('缺货提醒 / Low stock: $name (库存 $stock ≤ $thr)'),
          backgroundColor: const Color(0xFFB26A00),
          duration: const Duration(seconds: 4),
          action: widget.user.isAdmin
              ? SnackBarAction(
                  label: '商品',
                  textColor: Colors.white,
                  onPressed: () => setState(() => _index = _navIndexOf('products')),
                )
              : null,
        ),
      );
    };
    _live.onStatusChanged = (state, pending) {
      if (!mounted) return;
      setState(() {
        _linkState = state;
        _pending = pending;
      });
    };
    _tryAutoConnect();
    _refreshOverdueHolds();
    _holdPoll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      _refreshOverdueHolds();
    });
  }

  Future<void> _refreshOverdueHolds() async {
    final mins = await widget.repo.holdTimeoutMinutes();
    final list = await widget.repo.listOverdueHeld(
      cashier: widget.user.username,
      timeoutMinutes: mins,
    );
    if (!mounted) return;
    setState(() => _overdueHolds = list.length);
  }

  @override
  void dispose() {
    _holdPoll?.cancel();
    _live.disconnect();
    super.dispose();
  }

  Future<void> _tryAutoConnect() async {
    final cfg = await _syncClient.loadConfig();
    if (cfg == null) return;
    try {
      await _live.connect(cfg);
    } catch (_) {}
  }

  Future<void> _applyPairing(LanSyncConfig cfg) async {
    try {
      await _live.connect(cfg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已配对 ${cfg.name} · ${cfg.normalizedBase}'),
          backgroundColor: CnkhColors.success,
        ),
      );
      _bumpData();
    } catch (e) {
      if (!mounted) return;
      final err = _syncClient.lastError ?? '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('配对/同步失败: $err'),
          backgroundColor: CnkhColors.danger,
        ),
      );
    }
  }

  Future<void> _pairByQr() async {
    final cfg = await Navigator.of(context).push<LanSyncConfig>(
      MaterialPageRoute(
        builder: (_) => BarcodeScanScreen(
          repo: widget.repo,
          pairingOnly: true,
        ),
      ),
    );
    if (cfg == null || !mounted) return;
    await _applyPairing(cfg);
  }

  Future<void> _forceReconcile() async {
    try {
      final msg = await _live.forceReconcile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('强制全量对账完成\n$msg'),
          backgroundColor: CnkhColors.success,
        ),
      );
      _bumpData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('对账失败: ${_syncClient.lastError ?? e}'),
          backgroundColor: CnkhColors.danger,
        ),
      );
    }
  }

  Color get _statusDotColor => switch (_linkState) {
        SyncLinkState.connected => const Color(0xFF69F0AE),
        SyncLinkState.pending => const Color(0xFFFFB300),
        SyncLinkState.offline => const Color(0xFF9E9E9E),
      };

  void _bumpData() {
    if (!mounted) return;
    setState(() => _dataEpoch++);
  }

  List<_RailItem> get _items {
    final list = <_RailItem>[
      _RailItem('pos', '收银 POS', Icons.point_of_sale, Icons.point_of_sale_outlined),
      _RailItem('today', '今日', Icons.receipt_long, Icons.receipt_long_outlined),
    ];
    if (widget.user.isAdmin) {
      list.addAll([
        _RailItem('products', '商品', Icons.inventory_2, Icons.inventory_2_outlined),
        _RailItem('customers', '客户', Icons.people, Icons.people_outline),
        _RailItem('purchases', '进货', Icons.shopping_bag, Icons.shopping_bag_outlined),
        _RailItem('reports', '报表', Icons.bar_chart, Icons.bar_chart_outlined),
        _RailItem('admin', '管理', Icons.admin_panel_settings, Icons.admin_panel_settings_outlined),
        _RailItem('maintenance', '维护', Icons.build, Icons.build_outlined),
      ]);
    }
    list.add(_RailItem('settings', '设置', Icons.settings, Icons.settings_outlined));
    return list;
  }

  int _navIndexOf(String id) {
    final items = _items;
    final i = items.indexWhere((e) => e.id == id);
    return i < 0 ? 0 : i;
  }

  Future<void> _checkout() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          cart: _cart,
          user: widget.user,
          qrStorage: widget.qrStorage,
          repo: widget.repo,
          onCancel: () => Navigator.of(context).pop(),
          onPaid: (sale) async {
            Navigator.of(context).pop();
            setState(() {
              _cart.items.clear();
              _cart.orderDiscountCents = 0;
              _dataEpoch++;
            });
            // ignore: unawaited_futures
            _live.onLocalSale(sale);
            // ignore: unawaited_futures
            () async {
              try {
                final bt = BluetoothPrinterService(widget.repo);
                if (!await bt.enabled()) return;
                final msg = await bt.tryPrintSale(sale);
                if (!mounted || msg == 'bt_off' || msg == 'ok') return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              } catch (_) {}
            }();
            await showSaleSuccessSheet(context, sale: sale, repo: widget.repo);
          },
        ),
      ),
    );
  }

  Future<void> _hold() async {
    try {
      final held = await widget.repo.holdCart(
        cart: _cart,
        cashier: widget.user.username,
      );
      setState(() {
        _cart.items.clear();
        _cart.orderDiscountCents = 0;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已挂单 ${held.holdNo}')),
      );
      await _refreshOverdueHolds();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
      );
    }
  }

  Future<void> _resume() async {
    final list = await widget.repo.listHeld(cashier: widget.user.username);
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无挂单 / No held orders')),
      );
      return;
    }
    final timeout = await widget.repo.holdTimeoutMinutes();
    final cutoff = DateTime.now().subtract(Duration(minutes: timeout));
    final selected = await showDialog<HeldOrder>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_overdueHolds > 0
            ? '取单 / Resume（超时 $_overdueHolds）'
            : '取单 / Resume'),
        children: [
          for (final h in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: Text(
                '${h.holdNo} · ${h.heldAt.substring(0, 16).replaceFirst('T', ' ')}'
                '${(DateTime.tryParse(h.heldAt)?.isBefore(cutoff) == true) ? '  ⚠超时' : ''}',
                style: TextStyle(
                  color: (DateTime.tryParse(h.heldAt)?.isBefore(cutoff) == true)
                      ? const Color(0xFFB26A00)
                      : null,
                  fontWeight: (DateTime.tryParse(h.heldAt)?.isBefore(cutoff) == true)
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final restored = await widget.repo.resumeHeld(selected);
    setState(() {
      _cart.items
        ..clear()
        ..addAll(restored.items);
      _cart.orderDiscountCents = restored.orderDiscountCents;
    });
    await _refreshOverdueHolds();
  }

  Widget _pageFor(String id) {
    switch (id) {
      case 'pos':
        return CartScreen(
          cart: _cart,
          user: widget.user,
          repo: widget.repo,
          desktopTwoPane: true,
          onChanged: () => setState(() {}),
          onCheckout: _checkout,
          onHold: _hold,
          onResume: _resume,
          onPairing: (cfg) {
            Navigator.of(context).pop();
            _applyPairing(cfg);
          },
        );
      case 'today':
        return SalesListScreen(
          repo: widget.repo,
          todayOnly: true,
          refreshToken: _dataEpoch,
          canVoid: widget.user.isAdmin,
        );
      case 'products':
        return ProductsAdminPage(repo: widget.repo, user: widget.user);
      case 'customers':
        return EntitiesPage(repo: widget.repo, kind: 'customers');
      case 'purchases':
        return PurchasesPage(repo: widget.repo, user: widget.user);
      case 'reports':
        return ReportsPage(repo: widget.repo);
      case 'admin':
        return AdminHub(
          user: widget.user,
          repo: widget.repo,
          onDataChanged: _bumpData,
        );
      case 'maintenance':
        return MaintenancePage(repo: widget.repo, onResetDone: widget.onLogout);
      case 'settings':
        return SettingsScreen(
          qrStorage: widget.qrStorage,
          user: widget.user,
          repo: widget.repo,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final safe = _index.clamp(0, items.length - 1);
    final current = items[safe];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: _railExtended,
            minExtendedWidth: 168,
            selectedIndex: safe,
            onDestinationSelected: (i) {
              setState(() {
                _index = i;
                if (items[i].id == 'today') _dataEpoch++;
              });
            },
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: Column(
                children: [
                  IconButton(
                    tooltip: _railExtended ? '收起' : '展开',
                    onPressed: () => setState(() => _railExtended = !_railExtended),
                    icon: Icon(_railExtended ? Icons.menu_open : Icons.menu),
                  ),
                  if (_railExtended) ...[
                    const SizedBox(height: 4),
                    const Text(
                      '黄金发宝号',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: CnkhColors.navy,
                      ),
                    ),
                    Text(
                      'POS Desktop',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.user.isAdmin
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF455A64),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.user.isAdmin ? 'Admin' : 'Staff',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '退出 / Logout',
                        onPressed: widget.onLogout,
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              for (final n in items)
                NavigationRailDestination(
                  icon: Icon(n.outline),
                  selectedIcon: Icon(n.filled),
                  label: Text(n.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Material(
                  elevation: 1,
                  color: CnkhColors.navy,
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Text(
                            current.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            widget.user.roleBadge,
                            style: const TextStyle(
                              color: Color(0xFFC3D2E5),
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (_overdueHolds > 0)
                            IconButton(
                              tooltip: '挂单超时',
                              onPressed: () async {
                                setState(() => _index = _navIndexOf('pos'));
                                await _resume();
                              },
                              icon: Badge(
                                label: Text('$_overdueHolds'),
                                backgroundColor: const Color(0xFFFFB300),
                                child: const Icon(
                                  Icons.pause_circle_filled,
                                  color: Color(0xFFFFB300),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: '强制全量对账',
                            onPressed: _forceReconcile,
                            icon: const Icon(Icons.sync, color: Colors.white),
                          ),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              IconButton(
                                tooltip: '扫码配对 / LAN pair',
                                onPressed: _pairByQr,
                                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                              ),
                              Positioned(
                                right: 8,
                                top: 10,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _statusDotColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24),
                                  ),
                                ),
                              ),
                              if (_pending > 0)
                                Positioned(
                                  right: 4,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFB300),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$_pending',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          IconButton(
                            tooltip: '培训 / Training',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TrainingPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.school_outlined, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: safe,
                    children: [for (final n in items) _pageFor(n.id)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem {
  final String id;
  final String label;
  final IconData filled;
  final IconData outline;
  _RailItem(this.id, this.label, this.filled, this.outline);
}
