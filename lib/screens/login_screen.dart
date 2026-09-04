import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../theme/cnkh_theme.dart';

class LoginScreen extends StatefulWidget {
  final ValueChanged<AppUser> onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

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

  /// Map username hints → role, but segmented control is authoritative.
  AppUser _resolveUser(String username, AppRole selectedRole) {
    final u = username.trim().toLowerCase();
    // Username can reinforce selection for demo accounts.
    if (u == 'admin' || u.startsWith('admin')) {
      return AppUser(username: username.trim(), role: AppRole.admin);
    }
    if (u == 'staff' || u == 'staff1' || u.startsWith('staff')) {
      return AppUser(username: username.trim(), role: AppRole.staff);
    }
    // Otherwise use the segmented control selection.
    return AppUser(username: username.trim(), role: selectedRole);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_userCtrl.text.trim().isEmpty || _pinCtrl.text.trim().isEmpty) {
      setState(() {
        _busy = false;
        _error = '请输入账号与 PIN / Enter username and PIN';
      });
      return;
    }
    if (!mounted) return;
    // Demo usernames admin*/staff* map to role; otherwise use segmented control.
    widget.onLoggedIn(_resolveUser(_userCtrl.text, _role));
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
                              '选择角色后输入账号与 PIN（演示任意 PIN）\n'
                              'Pick role, then username + PIN (any PIN for demo)',
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
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '演示：admin → 管理员；staff / staff1 → 员工\n'
                      'Demo: admin → Admin; staff / staff1 → Staff',
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
