import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/user_admin_service.dart';

void main() {
  group('UserAdminService', () {
    late Directory dir;
    late AppDatabase database;
    late PosRepository repo;
    late UserAdminService service;

    setUp(() async {
      AppDatabase.ensureFfi();
      dir = await Directory.systemTemp.createTemp('cnkh_user_admin_');
      database = AppDatabase.forTesting('${dir.path}/test.db', seed: false);
      repo = PosRepository(database: database);
      service = UserAdminService(repo);
      final db = await database.db;
      await db.insert('demo_users', <String, Object?>{
        'id': 'admin-1',
        'username': 'admin',
        'display_name': 'Admin',
        'role': 'ADMIN',
        'is_active': 1,
      });
    });

    tearDown(() async {
      await database.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('creates and edits staff while preserving username identity', () async {
      await service.createUser(
        username: 'cashier1',
        displayName: 'Cashier One',
        role: 'STAFF',
      );
      var users = await service.listUsers();
      final staff = users.singleWhere((u) => u['username'] == 'cashier1');
      final id = staff['id'] as String;
      expect(staff['role'], 'STAFF');
      expect(staff['is_active'], 1);

      await service.updateUser(
        id: id,
        displayName: 'Senior Cashier',
        role: 'ADMIN',
        isActive: true,
      );
      users = await service.listUsers();
      final edited = users.singleWhere((u) => u['id'] == id);
      expect(edited['username'], 'cashier1');
      expect(edited['display_name'], 'Senior Cashier');
      expect(edited['role'], 'ADMIN');
    });

    test('cannot disable or demote the last active admin', () async {
      await expectLater(
        service.updateUser(
          id: 'admin-1',
          displayName: 'Admin',
          role: 'STAFF',
          isActive: true,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.updateUser(
          id: 'admin-1',
          displayName: 'Admin',
          role: 'ADMIN',
          isActive: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('admin can be disabled after another active admin exists', () async {
      await service.createUser(
        username: 'admin2',
        displayName: 'Admin Two',
        role: 'ADMIN',
      );
      await service.updateUser(
        id: 'admin-1',
        displayName: 'Admin',
        role: 'ADMIN',
        isActive: false,
      );
      final users = await service.listUsers();
      final first = users.singleWhere((u) => u['id'] == 'admin-1');
      expect(first['is_active'], 0);
    });
  });
}
