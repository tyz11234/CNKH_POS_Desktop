import 'package:flutter/material.dart';

import '../../db/app_database.dart';
import '../../services/pos_repository.dart';
import '../../theme/cnkh_theme.dart';

class EntitiesAdminPage extends StatefulWidget {
  const EntitiesAdminPage({
    super.key,
    required this.repo,
    required this.kind,
  }) : assert(kind == 'customers' || kind == 'suppliers');

  final PosRepository repo;
  final String kind;

  @override
  State<EntitiesAdminPage> createState() => _EntitiesAdminPageState();
}

class _EntitiesAdminPageState extends State<EntitiesAdminPage> {
  List<Object> _items = const [];
  final Set<String> _selected = <String>{};
  bool _busy = false;

  bool get _customers => widget.kind == 'customers';
  String get _title => _customers ? '客户 / Customers' : '供应商 / Suppliers';

  String _id(Object item) => item is Customer ? item.id : (item as Supplier).id;
  String _name(Object item) =>
      item is Customer ? item.name : (item as Supplier).name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = _customers
        ? await widget.repo.listCustomers()
        : await widget.repo.listSuppliers();
    if (!mounted) return;
    setState(() {
      _items = rows.cast<Object>();
      _selected.removeWhere((id) => !_items.any((e) => _id(e) == id));
    });
  }

  Future<void> _edit([Object? existing]) async {
    if (_busy) return;
    final customer = existing is Customer ? existing : null;
    final supplier = existing is Supplier ? existing : null;
    final name = TextEditingController(text: customer?.name ?? supplier?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? supplier?.phone ?? '');
    final extra = TextEditingController(
      text: _customers ? (customer?.notes ?? '') : (supplier?.email ?? ''),
    );
    final notes = TextEditingController(text: supplier?.notes ?? '');
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            existing == null
                ? (_customers ? '新增客户' : '新增供应商')
                : (_customers ? '编辑客户' : '编辑供应商'),
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  onChanged: (_) {
                    if (error != null) setLocal(() => error = null);
                  },
                  decoration: InputDecoration(
                    labelText: '名称 / Name',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: '电话 / Phone'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: extra,
                  decoration: InputDecoration(
                    labelText: _customers ? '备注 / Notes' : 'Email',
                  ),
                ),
                if (!_customers) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: '备注 / Notes'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setLocal(() => error = '名称不能为空');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      if (_customers) {
        await widget.repo.upsertCustomer(
          Customer(
            id: customer?.id ?? AppDatabase.newId(),
            name: name.text.trim(),
            phone: phone.text.trim(),
            notes: extra.text.trim(),
          ),
        );
      } else {
        await widget.repo.upsertSupplier(
          Supplier(
            id: supplier?.id ?? AppDatabase.newId(),
            name: name.text.trim(),
            phone: phone.text.trim(),
            email: extra.text.trim(),
            notes: notes.text.trim(),
          ),
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existing == null ? '已新增' : '已保存修改')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      name.dispose();
      phone.dispose();
      extra.dispose();
      notes.dispose();
    }
  }

  Future<bool> _confirmDelete(List<Object> items) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(items.length == 1 ? '确认删除？' : '确认批量删除？'),
            content: Text(
              items.length == 1
                  ? '确定删除「${_name(items.single)}」吗？历史销售、进货和审计记录不会被删除。'
                  : '确定删除所选的 ${items.length} 个${_customers ? '客户' : '供应商'}吗？历史记录会继续保留。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteItems(List<Object> items) async {
    if (_busy || items.isEmpty || !await _confirmDelete(items)) return;
    setState(() => _busy = true);
    var completed = 0;
    try {
      for (final item in items) {
        if (_customers) {
          await widget.repo.softDeleteCustomer(_id(item));
        } else {
          await widget.repo.softDeleteSupplier(_id(item));
        }
        completed++;
      }
      _selected.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $completed 项')),
        );
      }
    } catch (e) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已完成 $completed 项；其余失败：$e'),
            backgroundColor: CnkhColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_items.map(_id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedItems = _items.where((e) => _selected.contains(_id(e))).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _edit(),
                      icon: const Icon(Icons.add),
                      label: Text(_customers ? '新增客户' : '新增供应商'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy || _items.isEmpty ? null : _selectAll,
                      icon: const Icon(Icons.select_all),
                      label: Text(
                        _selected.length == _items.length && _items.isNotEmpty
                            ? '取消全选'
                            : '全选',
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy || selectedItems.isEmpty
                          ? null
                          : () => _deleteItems(selectedItems),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('删除所选 (${selectedItems.length})'),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${_items.length} · 已选 ${selectedItems.length}',
                      style: const TextStyle(color: CnkhColors.muted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final id = _id(item);
                    final selected = _selected.contains(id);
                    final subtitle = item is Customer
                        ? '${item.phone}${item.notes.isEmpty ? '' : '  ·  ${item.notes}'}'
                        : '${(item as Supplier).phone}${item.email.isEmpty ? '' : '  ·  ${item.email}'}${item.notes.isEmpty ? '' : '  ·  ${item.notes}'}';
                    return ListTile(
                      leading: Checkbox(
                        value: selected,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                }),
                      ),
                      title: Text(
                        _name(item),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(subtitle),
                      selected: selected,
                      onDoubleTap: _busy ? null : () => _edit(item),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '编辑 / Edit',
                            onPressed: _busy ? null : () => _edit(item),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: '删除 / Delete',
                            onPressed: _busy ? null : () => _deleteItems([item]),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_busy)
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
