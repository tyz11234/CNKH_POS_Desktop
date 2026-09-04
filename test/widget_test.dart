import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('app boots to login with role picker', (tester) async {
    await tester.pumpWidget(const CnkhPosDesktopApp());
    expect(find.textContaining('黄金发宝号'), findsOneWidget);
    expect(find.textContaining('员工 Staff'), findsOneWidget);
    expect(find.textContaining('管理员 Admin'), findsOneWidget);
  });

  testWidgets('staff login reaches POS shell', (tester) async {
    await tester.pumpWidget(const CnkhPosDesktopApp());
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('登录 / Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // DB seed may take a moment
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('收银台'), findsOneWidget);
    expect(find.textContaining('Staff'), findsWidgets);
  });

  testWidgets('admin settings shows import; staff view-only', (tester) async {
    await tester.pumpWidget(const CnkhPosDesktopApp());
    await tester.tap(find.text('管理员 Admin'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('登录 / Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Admin'), findsWidgets);

    await tester.tap(find.textContaining('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('从相册导入'), findsOneWidget);

    await tester.tap(find.byTooltip('退出 / Logout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('员工 Staff'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('登录 / Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.textContaining('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('仅管理员可更改收款码'), findsOneWidget);
    expect(find.textContaining('从相册导入'), findsNothing);
  });
}
