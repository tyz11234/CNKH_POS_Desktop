import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/user_admin_service.dart';
import 'package:cnkh_pos_desktop/screens/admin/user_admin_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase database;
  late PosRepository repo;
  // Initialize FFI and credentials in the real setup zone, as the existing
  // login widget suite does; only page interaction uses the virtual clock.
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-admin-cancel-');
    database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await (await database.db).insert('demo_users', {'id': 'admin1', 'username': 'admin',
      'display_name': 'Admin', 'role': 'ADMIN', 'is_active': 1});
    await repo.auth.initializeAdmin('123456');
    await repo.auth.login('admin', '123456');
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });
  testWidgets('F08 page creation followed by PIN cancel keeps a login-capable admin', (tester) async {
    Future<void> flush() async {
      for (var i=0;i<6;i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:50)));
        await tester.pump(const Duration(milliseconds:100));
      }
    }
    Future<void> waitFor(Finder finder) async {
      // SQLite uses real I/O. Wait for the actual UI state rather than assuming
      // a fixed 300 ms is sufficient on a busy Windows runner.
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(() =>
            Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.pumpAndSettle();
      expect(finder, findsOneWidget);
    }
      await tester.pumpWidget(MaterialApp(home: UserAdminPage(repo:repo))); await flush();
      // Start the async page action in the real zone, including the database
      // continuation after its dialog completes.
      await tester.runAsync(() async { await tester.tap(find.text('新增账号')); });
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0),'Admin2');
      await tester.enterText(find.byType(TextField).at(1),'Second Admin');
      await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
      await tester.tap(find.text('ADMIN · 管理员').last); await tester.pumpAndSettle();
      await tester.runAsync(() async { await tester.tap(find.text('保存')); });
      await waitFor(find.text('设置 Admin2 PIN'));
      expect(find.text('设置 Admin2 PIN'),findsOneWidget);
      await tester.runAsync(() async { await tester.tap(find.text('取消')); });
      await waitFor(find.text('员工账号已保存'));
      await tester.runAsync(() async {
        final service=UserAdminService(repo);
        await expectLater(service.updateUser(id:'admin1',displayName:'Admin',role:'STAFF',isActive:true),throwsStateError);
        await expectLater(service.updateUser(id:'admin1',displayName:'Admin',role:'ADMIN',isActive:false),throwsStateError);
        repo.auth.logout(); expect((await repo.auth.login('ADMIN','123456')).isAdmin,isTrue);
        await expectLater(repo.auth.login('admin2','000000'),throwsStateError);
      });
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(),isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
