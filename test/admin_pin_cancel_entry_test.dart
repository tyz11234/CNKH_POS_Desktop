import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/user_admin_service.dart';
import 'package:cnkh_pos_desktop/screens/admin/user_admin_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('F08 page creation followed by PIN cancel keeps a login-capable admin', (tester) async {
    final temp = await Directory.systemTemp.createTemp('cnkh-admin-cancel-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);
    Future<void> flush() async {
      for (var i=0;i<6;i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:50)));
        await tester.pump(const Duration(milliseconds:100));
      }
    }
    try {
      await tester.runAsync(() async {
        await (await database.db).insert('demo_users',{'id':'admin1','username':'admin',
          'display_name':'Admin','role':'ADMIN','is_active':1});
        await repo.auth.initializeAdmin('123456'); await repo.auth.login('admin','123456');
      });
      await tester.pumpWidget(MaterialApp(home: UserAdminPage(repo:repo))); await flush();
      await tester.tap(find.text('新增账号')); await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0),'Admin2');
      await tester.enterText(find.byType(TextField).at(1),'Second Admin');
      await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
      await tester.tap(find.text('ADMIN · 管理员').last); await tester.pumpAndSettle();
      await tester.tap(find.text('保存')); await flush();
      expect(find.text('设置 Admin2 PIN'),findsOneWidget);
      await tester.tap(find.text('取消')); await flush();
      await tester.runAsync(() async {
        final service=UserAdminService(repo);
        await expectLater(service.updateUser(id:'admin1',displayName:'Admin',role:'STAFF',isActive:true),throwsStateError);
        await expectLater(service.updateUser(id:'admin1',displayName:'Admin',role:'ADMIN',isActive:false),throwsStateError);
        repo.auth.logout(); expect((await repo.auth.login('ADMIN','123456')).isAdmin,isTrue);
        await expectLater(repo.auth.login('admin2','000000'),throwsStateError);
      });
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(),isNull);
    } finally { await tester.runAsync(() async { await database.close(); await temp.delete(recursive:true); }); }
  });
}
