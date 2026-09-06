import 'package:flutter/material.dart';

import '../../services/pos_repository.dart';
import '../../services/user_admin_service.dart';
import '../../theme/cnkh_theme.dart';

class UserAdminPage extends StatefulWidget {
  const UserAdminPage({super.key, required this.repo});

  final PosRepository repo;

  @override
  State<UserAdminPage> createState() => _UserAdminPageState();
}

class _UserAdminPageState extends State<UserAdminPage> {
  late final UserAdminService _service = UserAdminService(widget.repo);
  List<Map<String, Object?>> _users = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await _service.listUsers();
    if (mounted) setState(() => _users = users);
  }

  Future<void> _edit([Map<String, Object?>? existing]) async {
    if (_busy) return;
    final username = TextEditingController(text: existing?['username']?.toString() ?? '');
    final display = TextEditingController(text: existing?['display_name']?.toString() ?? '');
    var role = existing?['role']?.toString() == 'ADMIN' ? 'ADMIN' : 'STAFF';
    var active = existing == null || existing['is_active'] == 1;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? '新增员工账号' : '编辑员工账号'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: username,
                  enabled: existing == null,
                  autofocus: existing == null,
                  decoration: InputDecoration(
                    labelText: '账号 / Username',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: display,
                  decoration: const InputDecoration(labelText: '显示名称 / Display name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '角色 / Role'),
                  items: const [
                    DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN · 管理员')),
                    DropdownMenuItem(value: 'STAFF', child: Text('STAFF · 员工')),
                  ],
                  onChanged: (value) {
                    if (value != null) setLocal(() => role = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('账号启用 / Active'),
                  value: active,
                  onChanged: (value) => setLocal(() => active = value),
                ),
                if (existing == null)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '建立账号后会继续要求设置 6–12 位数字 PIN。',
                      style: TextStyle(fontSize: 12, color: CnkhColors.muted),
                    ),
                  ),
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
                if (username.text.trim().isEmpty || display.text.trim().isEmpty) {
                  setLocal(() => error = '账号和显示名称不能为空');
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
    if (ok != true) {
      username.dispose();
      display.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await _service.createUser(
          username: username.text,
          displayName: display.text,
          role: role,
          isActive: active,
        );
        await _load();
        if (mounted) await _setPin(username.text.trim());
      } else {
        await _service.updateUser(
          id: existing['id'] as String,
          displayName: display.text,
          role: role,
          isActive: active,
        );
        await _load();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('员工账号已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      username.dispose();
      display.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPin(String username) async {
    final pin = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('设置 $username PIN'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '新 PIN（6–12 位数字）',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '再次输入 PIN'),
                ),
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
                if (pin.text != confirmation.text) {
                  setLocal(() => error = '两次 PIN 不一致');
                  return;
                }
                if (!RegExp(r'^\d{6,12}$').hasMatch(pin.text)) {
                  setLocal(() => error = 'PIN 必须是 6–12 位数字');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存 PIN'),
            ),
          ],
        ),
      ),
    );
    try {
      if (ok == true) {
        await _service.setPin(username, pin.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN 已重设')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      pin.dispose();
      confirmation.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('员工账号 / Users')),
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
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('新增账号'),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${_users.length} 个账号',
                      style: const TextStyle(color: CnkhColors.muted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final admin = user['role'] == 'ADMIN';
                    final active = user['is_active'] == 1;
                    return ListTile(
                      leading: Icon(
                        admin ? Icons.admin_panel_settings : Icons.badge_outlined,
                        color: active ? CnkhColors.primary : CnkhColors.muted,
                      ),
                      title: Text(
                        user['display_name']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: active ? null : CnkhColors.muted,
                        ),
                      ),
                      subtitle: Text(
                        '${user['username']} · ${user['role']} · ${active ? 'ACTIVE' : 'DISABLED'}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _setPin(user['username'] as String),
                            icon: const Icon(Icons.password),
                            label: const Text('重设 PIN'),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: '编辑账号 / Edit',
                            onPressed: _busy ? null : () => _edit(user),
                            icon: const Icon(Icons.edit_outlined),
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
