import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/screens/admin/admin_hub.dart';
import 'package:cnkh_pos_desktop/screens/admin/entities_admin_page.dart';
import 'package:cnkh_pos_desktop/screens/admin/purchase_detail_page.dart';
import 'package:cnkh_pos_desktop/screens/admin/user_admin_page.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EntityRepo extends PosRepository {
  final List<Customer> customers = [];

  @override
  Future<List<Customer>> listCustomers() async => customers;

  @override
  Future<void> upsertCustomer(Customer customer) async {
    customers.add(customer);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppDatabase.ensureFfi();
    dir = await Directory.systemTemp.createTemp('cnkh-dialog-lifecycle-');
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    repo = PosRepository(database: database);
    await repo.upsertSupplier(const Supplier(id: 's1', name: 'Supplier One'));
    final db = await database.db;
    await db.insert('demo_users', {
      'id': 'staff-1',
      'username': 'staff1',
      'display_name': 'Staff One',
      'role': 'STAFF',
      'is_active': 1,
    });
    await db.insert('purchases', {
      'id': 'po1',
      'purchase_no': 'PO-1',
      'supplier_id': 's1',
      'supplier_name': 'Supplier One',
      'purchased_at': '2026-10-03T10:00:00',
      'total_cents': 100,
      'lines_json': '[]',
      'notes': '',
      'invoice_no': 'ORIGINAL',
      'reversed': 0,
    });
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final elapsed = Stopwatch()..start();
    while (finder.evaluate().isEmpty && elapsed.elapsedMilliseconds < 10000) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finder, findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> closeFocusedDialog(
    WidgetTester tester,
    String action, {
    String? savedMessage,
  }) async {
    await tester.tap(find.text(action));
    await tester.pump();
    final elapsed = Stopwatch()..start();
    // Let real SQLite I/O progress while the dialog exits and any saving
    // indicator is active. A spinning indicator never settles by itself.
    while ((find.byType(AlertDialog).evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
            (savedMessage != null &&
                find.text(savedMessage).evaluate().isEmpty)) &&
        elapsed.elapsedMilliseconds < 10000) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    if (savedMessage != null) expect(find.text(savedMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
  }

  testWidgets('customer save safely closes its focused name field', (
    tester,
  ) async {
    final entities = _EntityRepo();
    await mount(tester, EntitiesAdminPage(repo: entities, kind: 'customers'));
    await tester.tap(find.text('新增客户'));
    await tester.pumpAndSettle();
    await tester.enterText(field('名称 / Name'), 'New Customer');
    await closeFocusedDialog(tester, '保存');
    expect(entities.customers.single.name, 'New Customer');
  });

  testWidgets('customer cancellation leaves no write or focused field error', (
    tester,
  ) async {
    final entities = _EntityRepo();
    await mount(tester, EntitiesAdminPage(repo: entities, kind: 'customers'));
    await tester.tap(find.text('新增客户'));
    await tester.pumpAndSettle();
    await tester.enterText(field('名称 / Name'), 'Cancelled Customer');
    await closeFocusedDialog(tester, '取消');
    expect(entities.customers, isEmpty);
  });

  testWidgets('user cancellation safely closes its focused username field', (
    tester,
  ) async {
    await mount(tester, UserAdminPage(repo: repo));
    await waitFor(tester, find.text('Staff One'));
    await tester.tap(find.text('新增账号'));
    await tester.pumpAndSettle();
    await tester.enterText(field('账号 / Username'), 'newstaff');
    await closeFocusedDialog(tester, '取消');
  });

  testWidgets('PIN cancellation safely closes its focused PIN field', (
    tester,
  ) async {
    await mount(tester, UserAdminPage(repo: repo));
    await waitFor(tester, find.text('Staff One'));
    await tester.tap(find.text('重设 PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(field('新 PIN（6–12 位数字）'), '123456');
    await closeFocusedDialog(tester, '取消');
  });

  testWidgets('new user save opens the PIN step after its fields are removed', (
    tester,
  ) async {
    await mount(tester, UserAdminPage(repo: repo));
    await waitFor(tester, find.text('Staff One'));
    await tester.tap(find.text('新增账号'));
    await tester.pumpAndSettle();
    await tester.enterText(field('账号 / Username'), 'newstaff');
    await tester.enterText(field('显示名称 / Display name'), 'New Staff');
    await tester.tap(find.text('保存'));
    await waitFor(tester, find.text('设置 newstaff PIN'));
    expect(tester.takeException(), isNull);
    await tester.enterText(field('新 PIN（6–12 位数字）'), '123456');
    await closeFocusedDialog(tester, '取消');
    await tester.runAsync(() async {
      final rows = await (await database.db).query(
        'demo_users',
        where: 'username=?',
        whereArgs: ['newstaff'],
      );
      expect(rows.single['display_name'], 'New Staff');
      expect(await (await database.db).query('user_credentials'), isEmpty);
    });
  });

  for (final action in ['保存', '取消']) {
    testWidgets('purchase $action safely closes its focused invoice field', (
      tester,
    ) async {
      await mount(tester, PurchaseDetailPage(repo: repo, purchaseId: 'po1'));
      await waitFor(tester, find.text('PO-1 · Supplier One'));
      await tester.tap(find.byTooltip('编辑进货资料 / Edit'));
      await waitFor(tester, find.text('编辑进货资料 / Edit Purchase'));
      await tester.enterText(field('Invoice No'), 'CHANGED');
      await closeFocusedDialog(
        tester,
        action,
        savedMessage: action == '保存' ? '进货资料已更新；库存与进货明细数量未改变。' : null,
      );
      await tester.runAsync(() async {
        final db = await database.db;
        final rows = await db.query(
          'purchases',
          where: 'id=?',
          whereArgs: ['po1'],
        );
        expect(
          rows.single['invoice_no'],
          action == '保存' ? 'CHANGED' : 'ORIGINAL',
        );
      });
    });
  }

  testWidgets(
    'factory reset cancellation safely closes its focused confirmation',
    (tester) async {
      await mount(tester, MaintenancePage(repo: repo));
      await tester.tap(find.text('初始化清空全部数据 / Factory reset'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '初始化');
      await closeFocusedDialog(tester, '取消');
      await tester.runAsync(() async {
        expect(await (await database.db).query('purchases'), hasLength(1));
      });
    },
  );
}
