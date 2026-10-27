import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/cloud_auth.dart';
import '../services/lan_sync.dart';
import '../services/pos_repository.dart';
import '../theme/cnkh_theme.dart';

class LoginScreen extends StatefulWidget {
  final ValueChanged<AppUser> onLoggedIn;
  final PosRepository repo;

  const LoginScreen({super.key, required this.onLoggedIn,required this.repo});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController(text: 'staff');
  final _pinCtrl = TextEditingController();
  AppRole _role = AppRole.staff;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _onRoleChanged(Set<AppRole> selected) {
    if (selected.isEmpty) return;
    final role = selected.first;
    setState(() {
      _role = role;
      // Prefill demo username for the chosen role.
      if (role == AppRole.admin &&
          (_userCtrl.text.trim().isEmpty ||
              _userCtrl.text.trim().toLowerCase().startsWith('staff'))) {
        _userCtrl.text = 'admin';
      } else if (role == AppRole.staff &&
          (_userCtrl.text.trim().isEmpty ||
              _userCtrl.text.trim().toLowerCase() == 'admin')) {
        _userCtrl.text = 'staff';
      }
    });
  }

  String? _setupPin;
  LanSyncConfig? _serverSetupCfg;
  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final username = _userCtrl.text.trim();
      final pin = _pinCtrl.text;

      // Confirming a pending first-time setup (local or on the server).
      final pendingSetup = _setupPin;
      if (pendingSetup != null) {
        if (username.toLowerCase() != 'admin') {
          throw StateError('首次使用请输入 admin 并设置 6–12 位数字 PIN');
        }
        if (pin != pendingSetup) throw StateError('两次 PIN 不一致');
        final setupCfg = _serverSetupCfg;
        _setupPin = null;
        _serverSetupCfg = null;
        if (setupCfg != null) {
          // Initialize on the server first, then cache the same PIN locally.
          await CloudAuthClient.initializeAdmin(setupCfg, pendingSetup);
          await widget.repo.auth.initializeAdmin(pendingSetup);
          final user = await CloudAuthClient.login(
            setupCfg,
            'admin',
            pendingSetup,
          );
          await widget.repo.auth.cacheServerLogin(user, pendingSetup);
          if (mounted) widget.onLoggedIn(user);
          return;
        }
        await widget.repo.auth.initializeAdmin(pendingSetup);
        if (mounted) {
          setState(() => _error = '管理员 PIN 已设置，请再次点击登录');
        }
        return;
      }

      // Server-primary accounts: when a server is configured and reachable,
      // it holds the master copy of accounts + PINs for all clients.
      final cfg = await LanSyncClient(widget.repo).loadConfig();
      CloudAuthState? server;
      if (cfg != null) {
        server = await CloudAuthClient.tryFetchState(cfg);
      }
      if (cfg != null && server != null) {
        if (!server.anyCredential) {
          if (await widget.repo.auth.needsSetup()) {
            // Nothing anywhere yet: initialize on the server.
            if (username.toLowerCase() != 'admin') {
              throw StateError('首次使用请输入 admin 并设置 6–12 位数字 PIN');
            }
            if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
              throw StateError('PIN 必须是 6–12 位数字');
            }
            _serverSetupCfg = cfg;
            setState(() => _setupPin = pin);
            if (mounted) {
              setState(() => _error = '请再次输入同一 PIN 确认设置（将保存在服务器，三端共用）');
            }
            return;
          }
          // This device has accounts but the server has none yet: log in
          // locally; an admin login seeds the server with these accounts.
          final user = await widget.repo.auth.login(username, pin);
          if (user.isAdmin) {
            await widget.repo.auth.pushAuthToServer();
          }
          if (mounted) widget.onLoggedIn(user);
          return;
        }
        // The server is the account master: verify the PIN there.
        final user = await CloudAuthClient.login(cfg, username, pin);
        await widget.repo.auth.cacheServerLogin(user, pin);
        await widget.repo.auth.applyServerUsers(server.users);
        if (mounted) widget.onLoggedIn(user);
        return;
      }

      // No server configured / reachable: original local-only flow.
      if (await widget.repo.auth.needsSetup()) {
        if (username.toLowerCase() != 'admin') {
          throw StateError('首次使用请输入 admin 并设置 6–12 位数字 PIN');
        }
        if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
          throw StateError('PIN 必须是 6–12 位数字');
        }
        setState(() => _setupPin = pin);
        if (mounted) setState(() => _error = '请再次输入同一 PIN 确认设置');
        return;
      }
      final user = await widget.repo.auth.login(username, pin);
      if (mounted) widget.onLoggedIn(user);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Lets a fresh device point at the shop server (address + token) before
  /// logging in, so accounts come from the server instead of local setup.
  Future<void> _showServerSettings() async {
    final syncClient = LanSyncClient(widget.repo);
    final existing = await syncClient.loadConfig();
    if (!mounted) return;
    final addrCtrl = TextEditingController(
      text: existing?.baseUrl ?? '',
    );
    final tokenCtrl = TextEditingController(text: existing?.token ?? '');
    String? dialogError;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('服务器设置 / Server settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: '服务器地址 / Address',
                  hintText: 'http://43.156.169.203',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tokenCtrl,
                decoration: const InputDecoration(
                  labelText: '同步令牌 / Token',
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 12),
                Text(
                  dialogError!,
                  style: const TextStyle(color: CnkhColors.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消 / Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await syncClient.saveConfig(
                    LanSyncConfig(
                      baseUrl: addrCtrl.text.trim(),
                      token: tokenCtrl.text.trim(),
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setDialogState(() => dialogError = '$e');
                }
              },
              child: const Text('保存 / Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _error = '服务器已保存，请登录（账号以服务器为准）');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [CnkhColors.deepNavy, CnkhColors.topBar, Color(0xFF123A66)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Center(
                        child: Text(
                          '◆',
                          style: TextStyle(color: Colors.white, fontSize: 34),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '黄金发宝号',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mobile Companion  ·  手机收银助手',
                      style: TextStyle(
                        color: Color(0xFFAFC2DB),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '登录 / Login',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '输入账号与已设置的 PIN\n'
                              'Sign in with your assigned account and PIN',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '角色 / Role',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            SegmentedButton<AppRole>(
                              segments: const [
                                ButtonSegment<AppRole>(
                                  value: AppRole.admin,
                                  label: Text('管理员 Admin'),
                                  icon: Icon(Icons.admin_panel_settings_outlined),
                                ),
                                ButtonSegment<AppRole>(
                                  value: AppRole.staff,
                                  label: Text('员工 Staff'),
                                  icon: Icon(Icons.badge_outlined),
                                ),
                              ],
                              selected: {_role},
                              onSelectionChanged: _onRoleChanged,
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _userCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '账号 / Username',
                                hintText: 'admin / staff',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pinCtrl,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: 'PIN / 密码',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: CnkhColors.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('登录 / Sign in'),
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: _busy ? null : _showServerSettings,
                              icon: const Icon(Icons.dns_outlined, size: 16),
                              label: const Text('服务器设置 / Server'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '首次使用：admin 设置 PIN；员工 PIN 由管理员设置\n'
                      'First use: set admin PIN; admin assigns staff PINs',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFC3D2E5), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
