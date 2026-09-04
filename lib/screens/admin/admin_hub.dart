import 'package:flutter/material.dart';

import '../../db/app_database.dart';
import '../../models/app_user.dart';
import '../../models/money.dart';
import '../../models/product.dart';
import '../../services/pos_repository.dart';
import '../../theme/cnkh_theme.dart';
import '../../services/e_receipt.dart';
import '../../widgets/money_text.dart';
import '../sales_list_screen.dart';
import 'products_admin.dart';

class AdminHub extends StatelessWidget {
  final AppUser user;
  final PosRepository repo;
  final VoidCallback? onDataChanged;

  const AdminHub({
    super.key,
    required this.user,
    required this.repo,
    this.onDataChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <_Tile>[
      _Tile('主页 Dashboard', Icons.dashboard_outlined, () => _open(context, DashboardPage(repo: repo))),
      _Tile('商品 Products', Icons.inventory_2_outlined, () => _open(context, ProductsAdminPage(repo: repo, user: user))),
      _Tile('分类 Categories', Icons.category_outlined, () => _open(context, CategoriesAdminPage(repo: repo))),
      _Tile('条码队列 Barcode Queue', Icons.qr_code_2, () => _open(context, BarcodeQueuePage(repo: repo))),
      _Tile('销售 Sales', Icons.receipt_long, () => _open(
            context,
            _ScaffoldPage(
              title: '销售记录 / Sales',
              body: SalesListScreen(repo: repo, todayOnly: false, canVoid: true),
            ),
          )),
      _Tile('客户 Customers', Icons.people_outline, () => _open(context, EntitiesPage(repo: repo, kind: 'customers'))),
      _Tile('供应商 Suppliers', Icons.local_shipping_outlined, () => _open(context, EntitiesPage(repo: repo, kind: 'suppliers'))),
      _Tile('进货 Purchases', Icons.shopping_bag_outlined, () => _open(context, PurchasesPage(repo: repo, user: user))),
      _Tile('盘点 Stocktake', Icons.fact_check_outlined, () => _open(context, StocktakePage(repo: repo, user: user))),
      _Tile('员工 Users', Icons.badge_outlined, () => _open(context, UsersPage(repo: repo))),
      _Tile('报表 Reports', Icons.bar_chart, () => _open(context, ReportsPage(repo: repo))),
      _Tile('日结 Daily Close', Icons.point_of_sale, () => _open(context, DailyClosePage(repo: repo, user: user))),
      _Tile('维护 Maintenance', Icons.build_outlined, () => _open(context, MaintenancePage(repo: repo))),
      _Tile('折扣审计 Audit', Icons.history, () => _open(context, AuditLogPage(repo: repo))),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('管理 / Admin', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        const Text('本地演示数据 · Local-first parity screens',
            style: TextStyle(color: CnkhColors.muted)),
        const SizedBox(height: 12),
        ...tiles.map(
          (t) => Card(
            child: ListTile(
              leading: Icon(t.icon, color: CnkhColors.primary),
              title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: t.onTap,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Card(
          color: Color(0xFFFFF7E6),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'PC-only（本版不做）：条码标签硬件打印、Windows 备份/还原二进制格式。\n'
              'PC-only: barcode label hardware printing; Windows backup/restore binary format.',
              style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF7A5A10)),
            ),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) {
      onDataChanged?.call();
    });
  }
}

class _Tile {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  _Tile(this.title, this.icon, this.onTap);
}

class _ScaffoldPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  const _ScaffoldPage({required this.title, required this.body, this.actions});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: canPop
            ? IconButton(
                tooltip: '返回 / Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: actions,
      ),
      body: body,
    );
  }
}

class DashboardPage extends StatefulWidget {
  final PosRepository repo;
  const DashboardPage({super.key, required this.repo});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, int>? _d;
  @override
  void initState() {
    super.initState();
    widget.repo.dashboardToday().then((v) {
      if (mounted) setState(() => _d = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return _ScaffoldPage(
      title: 'Dashboard',
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _kpi('今日销售额 / Sales today', d['salesTotal']!),
                _kpi('现金 / Cash', d['cash']!),
                _kpi('卡 / Card', d['card']!),
                _kpi('DuitNow', d['duitnow']!),
                _kpi('今日赊账余额 / Credit today', d['creditOutstandingToday']!),
                _kpi('全部未清赊账 / Credit open', d['creditOutstandingAll']!),
                _kpi('单数 / Tickets', d['ticketCount']!, money: false),
              ],
            ),
    );
  }

  Widget _kpi(String label, int value, {bool money = true}) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: money
            ? MoneyText(amountCents: value, fontSize: 18)
            : Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
    );
  }
}


class EntitiesPage extends StatefulWidget {
  final PosRepository repo;
  final String kind; // customers | suppliers
  const EntitiesPage({super.key, required this.repo, required this.kind});
  @override
  State<EntitiesPage> createState() => _EntitiesPageState();
}

class _EntitiesPageState extends State<EntitiesPage> {
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.kind == 'customers') {
      _items = await widget.repo.listCustomers();
    } else {
      _items = await widget.repo.listSuppliers();
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final extra = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.kind == 'customers' ? '新增客户' : '新增供应商'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: '电话')),
            TextField(
              controller: extra,
              decoration: InputDecoration(
                labelText: widget.kind == 'customers' ? '备注' : 'Email',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    if (widget.kind == 'customers') {
      await widget.repo.upsertCustomer(Customer(
        id: AppDatabase.newId(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        notes: extra.text.trim(),
      ));
    } else {
      await widget.repo.upsertSupplier(Supplier(
        id: AppDatabase.newId(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        email: extra.text.trim(),
      ));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: widget.kind == 'customers' ? '客户' : '供应商',
      actions: [IconButton(onPressed: _edit, icon: const Icon(Icons.add))],
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final e = _items[i];
          if (e is Customer) {
            return ListTile(
              title: Text(e.name),
              subtitle: Text('${e.phone}\n${e.notes}'),
              isThreeLine: true,
              onLongPress: () async {
                await widget.repo.softDeleteCustomer(e.id);
                await _load();
              },
            );
          }
          final s = e as Supplier;
          return ListTile(
            title: Text(s.name),
            subtitle: Text('${s.phone}\n${s.email}'),
            isThreeLine: true,
            onLongPress: () async {
              await widget.repo.softDeleteSupplier(s.id);
              await _load();
            },
          );
        },
      ),
    );
  }
}

class PurchasesPage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  const PurchasesPage({super.key, required this.repo, required this.user});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  List<Map<String, Object?>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _rows = await widget.repo.listPurchases();
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final suppliers = await widget.repo.listSuppliers();
    final products = await widget.repo.searchProducts('', limit: 50);
    if (!mounted || suppliers.isEmpty || products.isEmpty) return;
    var supplier = suppliers.first;
    var product = products.first;
    final qty = TextEditingController(text: '10');
    final cost = TextEditingController(
        text: centsToRm(product.costCents).toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('简易进货 / Simple purchase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<Supplier>(
                isExpanded: true,
                value: supplier,
                items: [
                  for (final s in suppliers)
                    DropdownMenuItem(value: s, child: Text(s.name)),
                ],
                onChanged: (v) => setLocal(() => supplier = v!),
              ),
              DropdownButton<Product>(
                isExpanded: true,
                value: product,
                items: [
                  for (final p in products)
                    DropdownMenuItem(value: p, child: Text(p.nameZh)),
                ],
                onChanged: (v) => setLocal(() {
                  product = v!;
                  cost.text = centsToRm(product.costCents).toStringAsFixed(2);
                }),
              ),
              TextField(controller: qty, decoration: const InputDecoration(labelText: '数量')),
              TextField(controller: cost, decoration: const InputDecoration(labelText: '成本 RM', prefixText: 'RM ')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.trim()) ?? 0;
    final unitCost = rmToCents(double.tryParse(cost.text.trim()) ?? 0);
    final total = (unitCost * q).round();
    await widget.repo.createPurchase(
      supplierId: supplier.id,
      supplierName: supplier.name,
      lines: [
        {
          'productId': product.id,
          'name': product.nameZh,
          'qty': q,
          'unitCostCents': unitCost,
          'subtotalCents': total,
        }
      ],
      totalCents: total,
      operator: widget.user.username,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: '进货 / Purchases',
      actions: [IconButton(onPressed: _create, icon: const Icon(Icons.add))],
      body: ListView.builder(
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final r = _rows[i];
          return ListTile(
            title: Text('${r['purchase_no']} · ${r['supplier_name']}'),
            subtitle: Text('${r['purchased_at']}'),
            trailing: MoneyText(amountCents: r['total_cents'] as int, fontSize: 14),
          );
        },
      ),
    );
  }
}

class StocktakePage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  const StocktakePage({super.key, required this.repo, required this.user});
  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  List<Product> _items = [];
  @override
  void initState() {
    super.initState();
    widget.repo.searchProducts('', limit: 100).then((v) {
      if (mounted) setState(() => _items = v);
    });
  }

  Future<void> _adjust(Product p) async {
    final ctrl = TextEditingController(text: p.stock.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('盘点 ${p.nameZh}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '实盘数量'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.adjustStock(
      productId: p.id,
      newStock: double.tryParse(ctrl.text.trim()) ?? p.stock,
      operator: widget.user.username,
      reason: 'stocktake',
    );
    final list = await widget.repo.searchProducts('', limit: 100);
    if (mounted) setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: '盘点 / Stocktake',
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final p = _items[i];
          return ListTile(
            title: Text(p.nameZh),
            subtitle: Text('账面 ${p.stock} ${p.unit}'),
            trailing: const Icon(Icons.edit),
            onTap: () => _adjust(p),
          );
        },
      ),
    );
  }
}

class UsersPage extends StatefulWidget {
  final PosRepository repo;
  const UsersPage({super.key, required this.repo});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, Object?>> _users = [];
  @override
  void initState() {
    super.initState();
    widget.repo.listUsers().then((v) {
      if (mounted) setState(() => _users = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: '员工账号 (demo)',
      body: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, i) {
          final u = _users[i];
          return ListTile(
            leading: Icon(
              u['role'] == 'ADMIN' ? Icons.admin_panel_settings : Icons.person,
              color: CnkhColors.primary,
            ),
            title: Text('${u['display_name']}'),
            subtitle: Text('${u['username']} · ${u['role']}'),
          );
        },
      ),
    );
  }
}

class ReportsPage extends StatefulWidget {
  final PosRepository repo;
  const ReportsPage({super.key, required this.repo});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  Map<String, int>? _r;
  @override
  void initState() {
    super.initState();
    final day = DateTime.now().toIso8601String().substring(0, 10);
    widget.repo.reportByPayment(startDay: day, endDay: day).then((v) {
      if (mounted) setState(() => _r = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return _ScaffoldPage(
      title: '报表 / Reports (today)',
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final k in ['CASH', 'CARD', 'DUITNOW_QR', 'CREDIT', 'TOTAL'])
                  Card(
                    child: ListTile(
                      title: Text(k),
                      trailing: MoneyText(amountCents: r[k] ?? 0, fontSize: 16),
                    ),
                  ),
              ],
            ),
    );
  }
}

class DailyClosePage extends StatefulWidget {
  final PosRepository repo;
  final AppUser user;
  const DailyClosePage({super.key, required this.repo, required this.user});
  @override
  State<DailyClosePage> createState() => _DailyClosePageState();
}

class _DailyClosePageState extends State<DailyClosePage> {
  final _open = TextEditingController(text: '0.00');
  final _count = TextEditingController(text: '0.00');
  final _notes = TextEditingController();
  int _systemCash = 0;
  List<Map<String, Object?>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dash = await widget.repo.dashboardToday();
    _systemCash = dash['cash'] ?? 0;
    _history = await widget.repo.listClosings();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final day = DateTime.now().toIso8601String().substring(0, 10);
    await widget.repo.saveDailyClosing(
      businessDate: day,
      openingCashCents: rmToCents(double.tryParse(_open.text) ?? 0),
      countedCashCents: rmToCents(double.tryParse(_count.text) ?? 0),
      systemCashCents: _systemCash,
      closedBy: widget.user.username,
      notes: _notes.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日结已保存 / Closing saved')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: '日结 / Daily cash',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('系统现金 / System cash: ${formatRm(_systemCash)}'),
          const SizedBox(height: 8),
          TextField(controller: _open, decoration: const InputDecoration(labelText: '开档现金 RM', prefixText: 'RM ')),
          TextField(controller: _count, decoration: const InputDecoration(labelText: '实盘现金 RM', prefixText: 'RM ')),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: '备注')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('保存日结')),
          const Divider(height: 32),
          const Text('历史 / History', style: TextStyle(fontWeight: FontWeight.w800)),
          ..._history.map((h) => ListTile(
                title: Text('${h['business_date']}'),
                subtitle: Text(
                    '系统 ${formatRm(h['system_cash_cents'] as int)} · 实盘 ${formatRm(h['counted_cash_cents'] as int)}'),
              )),
        ],
      ),
    );
  }
}

class MaintenancePage extends StatelessWidget {
  final PosRepository repo;
  final VoidCallback? onResetDone;
  const MaintenancePage({super.key, required this.repo, this.onResetDone});

  Future<void> _factoryReset(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('初始化 / Factory reset'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '将清空全部业务数据（销售、挂单、进货、盘点、日结、审计、商品、客户、供应商、分类、设置），'
                '然后重新写入种子目录与演示账号，并清空电子收据缓存。\n\n'
                '请输入「初始化」确认：',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '初始化',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CnkhColors.danger),
            onPressed: () {
              if (ctrl.text.trim() == '初始化') {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.factoryResetLocalData();
    final deleted = await clearEReceiptCache();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已初始化。电子收据缓存已删 $deleted 个 PDF。请重新登录。'),
        backgroundColor: CnkhColors.success,
      ),
    );
    onResetDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return _ScaffoldPage(
      title: '维护 / Maintenance',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            color: Color(0xFFFFF7E6),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '桌面端维护：可清除演示交易，或执行完整「初始化」工厂重置。\n'
                'Windows 旧版二进制备份/还原仍由 -CNKH_POS_V5 提供；本工程为 Flutter 桌面本地库。',
                style: TextStyle(height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CnkhColors.danger),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清除演示交易？'),
                  content: const Text('不会删除商品/客户种子数据。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
                  ],
                ),
              );
              if (ok == true) {
                await repo.clearDemoData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除演示交易')),
                  );
                }
              }
            },
            child: const Text('清除演示交易数据 / Clear demo sales'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB71C1C),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _factoryReset(context),
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('初始化清空全部数据 / Factory reset',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          const Text(
            '需输入「初始化」确认。完成后需重新登录（种子 Admin/Staff 会重建）。',
            style: TextStyle(color: CnkhColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}


class AuditLogPage extends StatefulWidget {
  final PosRepository repo;
  const AuditLogPage({super.key, required this.repo});
  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  bool _todayOnly = true;
  String _userFilter = '';
  List<AuditEntry> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.repo.listAudit(
      todayOnly: _todayOnly,
      username: _userFilter.trim().isEmpty ? null : _userFilter.trim(),
    );
    if (!mounted) return;
    setState(() {
      _rows = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('折扣/改价审计 / Audit')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('今日'),
                  selected: _todayOnly,
                  onSelected: (v) {
                    setState(() => _todayOnly = v);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '按用户名筛选 / Filter user',
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      _userFilter = v;
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('暂无审计记录'))
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final a = _rows[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${a.action} · ${a.productName ?? a.context}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${a.occurredAt.replaceFirst('T', ' ').substring(0, 19)}\n'
                              '${a.username} (${a.role})  ${a.oldValue} → ${a.newValue}'
                              '${a.reason.isEmpty ? '' : ' · ${a.reason}'}',
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
