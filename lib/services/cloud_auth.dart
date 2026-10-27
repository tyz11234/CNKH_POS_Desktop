import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import 'lan_sync.dart';

/// Snapshot of the server's account state (GET /api/v1/auth/users).
class CloudAuthState {
  CloudAuthState({required this.users, required this.anyCredential});

  /// User rows as plain maps: username / role / display_name / is_active /
  /// has_pin.
  final List<Map<String, Object?>> users;

  /// True when the server holds at least one PIN credential, i.e. accounts
  /// have been initialized on the server.
  final bool anyCredential;
}

/// Client for the host's server-primary account endpoints (auth_v1).
/// The server keeps the master copy of accounts + PIN credentials; all
/// clients verify logins against it so one set of accounts works everywhere.
class CloudAuthClient {
  static Map<String, String> _headers(LanSyncConfig cfg) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (cfg.token.trim().isNotEmpty) {
      h['X-CNKH-Token'] = cfg.token.trim();
    }
    return h;
  }

  /// Fetches the server's account state, or null when the server is
  /// unreachable or does not speak auth_v1 (older host build).
  static Future<CloudAuthState?> tryFetchState(LanSyncConfig cfg) async {
    try {
      final uri = Uri.parse('${cfg.normalizedBase}/api/v1/auth/users');
      final res = await http
          .get(uri, headers: _headers(cfg))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final users = <Map<String, Object?>>[
        for (final u in (body['users'] as List? ?? const []))
          (u as Map).cast<String, Object?>(),
      ];
      return CloudAuthState(
        users: users,
        anyCredential: body['any_credential'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Verifies a login against the server. Throws StateError with a
  /// user-facing message on bad credentials / lockout.
  static Future<AppUser> login(
    LanSyncConfig cfg,
    String username,
    String pin,
  ) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/auth/login');
    final res = await http
        .post(
          uri,
          headers: _headers(cfg),
          body: jsonEncode({'username': username, 'pin': pin}),
        )
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw StateError(
        (body['error'] ?? '账号或 PIN 无效').toString(),
      );
    }
    final u = (body['user'] as Map).cast<String, Object?>();
    return AppUser(
      username: (u['username'] ?? '').toString(),
      role: u['role'] == 'ADMIN' ? AppRole.admin : AppRole.staff,
      displayName: (u['display_name'] ?? '').toString(),
    );
  }

  /// First-time bootstrap on the server (only succeeds while the server
  /// holds no credentials at all).
  static Future<void> initializeAdmin(LanSyncConfig cfg, String pin) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/auth/initialize-admin');
    final res = await http
        .post(uri, headers: _headers(cfg), body: jsonEncode({'pin': pin}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      throw StateError((body['error'] ?? '服务器初始化失败').toString());
    }
  }
}
