import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'pos_repository.dart';

class UserAdminService {
  UserAdminService(this.repo);

  final PosRepository repo;

  Future<List<Map<String, Object?>>> listUsers() async {
    final db = await repo.database.db;
    return db.query('demo_users', orderBy: 'role, username');
  }

  Future<void> createUser({
    required String username,
    required String displayName,
    required String role,
    bool isActive = true,
  }) async {
    final name = username.trim().toLowerCase();
    final display = displayName.trim();
    final normalizedRole = _role(role);
    if (name.isEmpty || !RegExp(r'^[a-z0-9._-]{2,40}$').hasMatch(name)) {
      throw StateError('账号只能使用 2–40 位英文字母、数字、点、底线或连字符');
    }
    if (display.isEmpty) throw StateError('显示名称不能为空');
    final db = await repo.database.db;
    final existing = await db.query(
      'demo_users',
      where: 'username=? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    if (existing.isNotEmpty) throw StateError('账号已存在');
    await db.insert('demo_users', <String, Object?>{
      'id': AppDatabase.newId(),
      'username': name,
      'display_name': display,
      'role': normalizedRole,
      'is_active': isActive ? 1 : 0,
    });
  }

  Future<void> updateUser({
    required String id,
    required String displayName,
    required String role,
    required bool isActive,
  }) async {
    final display = displayName.trim();
    final normalizedRole = _role(role);
    if (display.isEmpty) throw StateError('显示名称不能为空');
    final db = await repo.database.db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'demo_users',
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('账号不存在');
      final old = rows.first;
      final wasActiveAdmin = old['role'] == 'ADMIN' && old['is_active'] == 1;
      final remainsActiveAdmin = normalizedRole == 'ADMIN' && isActive;
      if (wasActiveAdmin && !remainsActiveAdmin) {
        final count = Sqflite.firstIntValue(
              await txn.rawQuery(
                "SELECT COUNT(*) FROM demo_users WHERE role='ADMIN' AND is_active=1 AND id<>?",
                [id],
              ),
            ) ??
            0;
        if (count == 0) {
          throw StateError('不能停用或降级最后一个有效管理员');
        }
      }
      await txn.update(
        'demo_users',
        <String, Object?>{
          'display_name': display,
          'role': normalizedRole,
          'is_active': isActive ? 1 : 0,
        },
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  Future<void> setPin(String username, String pin) {
    return repo.auth.setUserPin(username, pin);
  }

  String _role(String raw) {
    final role = raw.trim().toUpperCase();
    if (role != 'ADMIN' && role != 'STAFF') {
      throw StateError('角色必须是 ADMIN 或 STAFF');
    }
    return role;
  }
}
