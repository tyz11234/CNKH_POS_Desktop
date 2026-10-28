import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../db/app_database.dart';
import '../models/app_user.dart';

/// Structural validation of the PBKDF2 credential used by actual login.
bool hasValidPinCredential(Map<String, Object?> row) {
  try {
    return base64Decode(row['salt'] as String).length == 24 &&
        base64Decode(row['pin_hash'] as String).length == 32;
  } catch (_) { return false; }
}

Future<String> _digest(List<String> input) async {
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKeyFromPassword(password: input[0], nonce: base64Decode(input[1]));
  return base64Encode(await key.extractBytes());
}

class AuthService {
  AuthService({AppDatabase? database}) : _db = database ?? AppDatabase.instance;
  final AppDatabase _db;
  AppUser? _session;
  AppUser? get currentUser => _session;
  void logout() => _session = null;
  Future<bool> needsSetup() async =>
      (await (await _db.db).query('user_credentials', limit: 1)).isEmpty;
  Future<Map<String, Object?>> _credential(String user, String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin))
      throw StateError('PIN 必须是 6–12 位数字');
    final random = Random.secure();
    final salt = base64Encode(List.generate(24, (_) => random.nextInt(256)));
    return {
      'username': user.trim().toLowerCase(),
      'salt': salt,
      'pin_hash': await compute(_digest, [pin, salt]),
      'failed_attempts': 0,
      'locked_until': '',
    };
  }

  Future<void> initializeAdmin(String pin) async {
    final record = await _credential('admin', pin);
    final db = await _db.db;
    await db.transaction((txn) async {
      if ((await txn.query('user_credentials', limit: 1)).isNotEmpty)
        throw StateError('管理员已初始化');
      await txn.insert('user_credentials', record);
    });
    unawaited(pushAuthToServer());
  }

  Future<AppUser> login(String username, String pin) async {
    final db = await _db.db;
    final name = username.trim().toLowerCase();
    final users = await db.query(
      'demo_users',
      where: 'lower(username)=? AND is_active=1',
      whereArgs: [name],
      limit: 1,
    );
    final creds = await db.query(
      'user_credentials',
      where: 'username=? COLLATE NOCASE',
      whereArgs: [name],
    );
    if (users.isEmpty || creds.isEmpty || !hasValidPinCredential(creds.first))
      throw StateError('账号或 PIN 无效，未设置 PIN 请联系管理员');
    final c = creds.first;
    final until = DateTime.tryParse(c['locked_until'] as String);
    if (until != null && until.isAfter(DateTime.now().toUtc()))
      throw StateError('尝试次数过多，请 5 分钟后重试');
    final actual = base64Decode(
      await compute(_digest, [pin, c['salt'] as String]),
    );
    final expected = base64Decode(c['pin_hash'] as String);
    var diff = actual.length ^ expected.length;
    for (var i = 0; i < actual.length && i < expected.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    if (diff != 0) {
      await db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE user_credentials SET failed_attempts=failed_attempts+1 WHERE username=? COLLATE NOCASE',
          [name],
        );
        final row = (await txn.query(
          'user_credentials',
          where: 'username=? COLLATE NOCASE',
          whereArgs: [name],
        )).single;
        if ((row['failed_attempts'] as int) >= 5)
          await txn.update(
            'user_credentials',
            {
              'failed_attempts': 0,
              'locked_until': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            },
            where: 'username=? COLLATE NOCASE',
            whereArgs: [name],
          );
      });
      throw StateError('账号或 PIN 无效');
    }
    await db.update(
      'user_credentials',
      {'failed_attempts': 0, 'locked_until': ''},
      where: 'username=? COLLATE NOCASE',
      whereArgs: [name],
    );
    final u = users.first;
    return _session = AppUser(
      username: u['username'] as String,
      role: u['role'] == 'ADMIN' ? AppRole.admin : AppRole.staff,
      displayName: u['display_name'] as String,
    );
  }

  Future<void> setUserPin(String username, String pin) async {
    if (_session?.isAdmin != true) throw StateError('仅管理员可设置 PIN');
    final db = await _db.db;
    if ((await db.query(
      'demo_users',
      where: 'username=? COLLATE NOCASE',
      whereArgs: [username],
    )).isEmpty)
      throw StateError('账号不存在');
    final credential = await _credential(username, pin);
    await db.transaction((txn) async {
      await txn.delete('user_credentials', where: 'username=? COLLATE NOCASE',
          whereArgs: [username.trim()]);
      await txn.insert('user_credentials', credential);
    });
    unawaited(pushAuthToServer());
  }

  // ---------------------------------------------------------------------------
  // Server-primary accounts (auth_v1). The cloud host keeps the master copy of
  // demo_users + user_credentials; every client verifies PINs against it and
  // pushes account changes up, so all clients share one set of accounts.
  // ---------------------------------------------------------------------------

  /// Stateless PIN verification used by the host's POST /api/v1/auth/login.
  /// Applies the same lockout bookkeeping as [login] but never sets a session.
  Future<AppUser?> verifyUserPin(String username, String pin) async {
    final db = await _db.db;
    final name = username.trim().toLowerCase();
    final users = await db.query(
      'demo_users',
      where: 'lower(username)=? AND is_active=1',
      whereArgs: [name],
      limit: 1,
    );
    final creds = await db.query(
      'user_credentials',
      where: 'username=? COLLATE NOCASE',
      whereArgs: [name],
    );
    if (users.isEmpty || creds.isEmpty || !hasValidPinCredential(creds.first)) {
      return null;
    }
    final c = creds.first;
    final until = DateTime.tryParse(c['locked_until'] as String);
    if (until != null && until.isAfter(DateTime.now().toUtc())) {
      throw StateError('尝试次数过多，请 5 分钟后重试');
    }
    final actual = base64Decode(
      await compute(_digest, [pin, c['salt'] as String]),
    );
    final expected = base64Decode(c['pin_hash'] as String);
    var diff = actual.length ^ expected.length;
    for (var i = 0; i < actual.length && i < expected.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    if (diff != 0) {
      await db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE user_credentials SET failed_attempts=failed_attempts+1 WHERE username=? COLLATE NOCASE',
          [name],
        );
        final row = (await txn.query(
          'user_credentials',
          where: 'username=? COLLATE NOCASE',
          whereArgs: [name],
        )).single;
        if ((row['failed_attempts'] as int) >= 5) {
          await txn.update(
            'user_credentials',
            {
              'failed_attempts': 0,
              'locked_until': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
            },
            where: 'username=? COLLATE NOCASE',
            whereArgs: [name],
          );
        }
      });
      return null;
    }
    await db.update(
      'user_credentials',
      {'failed_attempts': 0, 'locked_until': ''},
      where: 'username=? COLLATE NOCASE',
      whereArgs: [name],
    );
    final u = users.first;
    return AppUser(
      username: u['username'] as String,
      role: u['role'] == 'ADMIN' ? AppRole.admin : AppRole.staff,
      displayName: u['display_name'] as String,
    );
  }

  /// Upserts one demo_users row keyed by username (keeping the local id).
  Future<void> _upsertUserRow(
    DatabaseExecutor db, {
    required String username,
    required String role,
    required String displayName,
    required int isActive,
  }) async {
    final existing = await db.query(
      'demo_users',
      where: 'username=? COLLATE NOCASE',
      whereArgs: [username.trim()],
      limit: 1,
    );
    final values = <String, Object?>{
      'username': username.trim().toLowerCase(),
      'display_name': displayName,
      'role': role,
      'is_active': isActive,
    };
    if (existing.isEmpty) {
      await db.insert('demo_users', {
        'id': 'u_${username.trim().toLowerCase()}',
        ...values,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.update(
        'demo_users',
        values,
        where: 'username=? COLLATE NOCASE',
        whereArgs: [username.trim()],
      );
    }
  }

  /// Caches a server-verified login locally: upserts the user row and stores
  /// a local credential derived from the PIN the user just typed, so the same
  /// PIN also works offline on this device.
  Future<void> cacheServerLogin(AppUser user, String pin) async {
    final credential = await _credential(user.username, pin);
    final db = await _db.db;
    await db.transaction((txn) async {
      await _upsertUserRow(
        txn,
        username: user.username,
        role: user.isAdmin ? 'ADMIN' : 'STAFF',
        displayName: user.displayName,
        isActive: 1,
      );
      await txn.delete(
        'user_credentials',
        where: 'username=? COLLATE NOCASE',
        whereArgs: [user.username],
      );
      await txn.insert('user_credentials', credential);
    });
    // The server verified this login: adopt it as the local session too,
    // so session-gated actions (admin PIN management, audit) keep working.
    _session = user;
  }

  /// Refreshes local demo_users rows from the server's master list.
  Future<void> applyServerUsers(List<Map<String, Object?>> users) async {
    final db = await _db.db;
    await db.transaction((txn) async {
      for (final u in users) {
        final username = (u['username'] ?? '').toString();
        if (username.isEmpty) continue;
        await _upsertUserRow(
          txn,
          username: username,
          role: (u['role'] ?? 'STAFF').toString(),
          displayName: (u['display_name'] ?? username).toString(),
          isActive: (u['is_active'] as num?)?.toInt() ?? 1,
        );
      }
    });
  }

  /// Raw account data for server import (migration / account pushes).
  Future<Map<String, Object?>> exportAuthData() async {
    final db = await _db.db;
    final users = await db.query('demo_users');
    final creds = await db.query(
      'user_credentials',
      columns: ['username', 'salt', 'pin_hash'],
    );
    return {'users': users, 'credentials': creds};
  }

  /// Applies an auth import (used by the host's /api/v1/auth/import):
  /// upserts user rows and replaces credentials per username.
  Future<void> importAuthData(Map<String, Object?> data) async {
    final db = await _db.db;
    final users = (data['users'] as List?) ?? const [];
    final creds = (data['credentials'] as List?) ?? const [];
    await db.transaction((txn) async {
      for (final raw in users.take(200)) {
        final u = (raw as Map).cast<String, Object?>();
        final username = (u['username'] ?? '').toString();
        if (username.isEmpty) continue;
        await _upsertUserRow(
          txn,
          username: username,
          role: (u['role'] ?? 'STAFF').toString(),
          displayName: (u['display_name'] ?? username).toString(),
          isActive: (u['is_active'] as num?)?.toInt() ?? 1,
        );
      }
      for (final raw in creds.take(200)) {
        final c = (raw as Map).cast<String, Object?>();
        if (!hasValidPinCredential(c)) continue;
        final username = (c['username'] ?? '').toString().trim().toLowerCase();
        if (username.isEmpty) continue;
        await txn.delete(
          'user_credentials',
          where: 'username=? COLLATE NOCASE',
          whereArgs: [username],
        );
        await txn.insert('user_credentials', {
          'username': username,
          'salt': c['salt'],
          'pin_hash': c['pin_hash'],
          'failed_attempts': 0,
          'locked_until': '',
        });
      }
    });
  }

  /// Best-effort push of all local accounts + credentials to the configured
  /// server, keeping the server's master copy current.
  Future<void> pushAuthToServer() async {
    try {
      final db = await _db.db;
      final rows = await db.query(
        'settings',
        where: "key IN ('lan_sync_host','lan_sync_token')",
      );
      final values = {for (final r in rows) r['key']: r['value']};
      final host = (values['lan_sync_host'] as String? ?? '').trim();
      final token = (values['lan_sync_token'] as String? ?? '').trim();
      if (host.isEmpty) return;
      var base = host;
      if (!base.startsWith('http://') && !base.startsWith('https://')) {
        base = 'http://$base';
      }
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final data = await exportAuthData();
      if ((data['credentials'] as List).isEmpty) return;
      await http
          .post(
            Uri.parse('$base/api/v1/auth/import'),
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'X-CNKH-Token': token,
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best effort only: the login flow reconciles again next time.
    }
  }
}
