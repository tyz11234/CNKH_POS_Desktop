import 'package:cnkh_pos_mobile/services/einvoice/einvoice_status_store.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart' as pc;
import 'package:cnkh_pos_desktop/services/pos_repository.dart' as pc;
import 'package:cnkh_pos_desktop/models/product.dart' as pc;
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart' as phone;
import 'package:cnkh_pos_mobile/services/pos_repository.dart' as phone;
import 'package:cnkh_pos_mobile/models/cart_item.dart' as phone;
import 'package:cnkh_pos_mobile/services/lan_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late pc.AppDatabase desktopDb;
  late phone.AppDatabase mobileDb;
  late pc.PosRepository desktop;
  late phone.PosRepository mobile;
  late LanPairingHost host;
  late LanSyncClient client;
  late LanSyncConfig config;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-pair-');
    desktopDb = pc.AppDatabase.forTesting('${temp.path}/pc.db');
    mobileDb = phone.AppDatabase.forTesting('${temp.path}/phone.db');
    desktop = pc.PosRepository(database: desktopDb);
    mobile = phone.PosRepository(database: mobileDb);
    await desktop.upsertProduct(const pc.Product(id:'desktop-product', nameZh:'商品', nameEn:'Product', sku:'SKU-1', barcode:'10001', priceCents:100, costCents:40, stock:10));
    await mobile.upsertProduct(const phone.Product(id:'phone-product', nameZh:'商品', nameEn:'Product', sku:'SKU-1', barcode:'10001', priceCents:100, costCents:40, stock:10));
    await desktop.upsertCustomer(const pc.Customer(id:'desktop-customer', name:'Customer', phone:'0123456'));
    await mobile.upsertCustomer(const phone.Customer(id:'phone-customer', name:'Customer', phone:'0123456'));
    host = LanPairingHost.forTesting(desktop, database: desktopDb);
    await host.start();
    config = LanSyncConfig(baseUrl:'http://127.0.0.1:${host.port}', token:await desktop.getSetting('lan_host_token'));
    client = LanSyncClient(mobile);
    await client.saveConfig(config);
    await client.forceReconcile(config);
  });
  tearDown(() async { await host.stop(); await desktopDb.close(); await mobileDb.close(); await temp.delete(recursive:true); });
  Future<phone.SaleRecord> sell({bool credit = false}) async => mobile.createSale(
    cart:phone.CartState(items:[phone.CartItem(product:(await mobile.getProduct('phone-product'))!, qty:2)]),
    paymentMethod:credit ? 'CREDIT' : 'CASH', paidCents:credit ? 0 : 200, cashier:'staff',
    customer:credit ? const phone.Customer(id:'phone-customer',name:'Customer',phone:'0123456') : null);
  test('offline sale keeps pending and authenticated LAN mirrors all e-Invoice states', () async {
    final sale = await sell();
    final store = EInvoiceStatusStore(await mobileDb.db);
    expect((await store.history(config.normalizedBase, 'production')).single['status'], 'pending');
    await client.synchronize(config);
    final d = await desktopDb.db;
    final imported = (await desktop.salesAll()).single;
    await d.insert('e_invoice_documents', {'id':'status-test','sale_id':imported.id,'invoice_no':imported.receiptNo,'environment':'production','status':'submitted'});
    for (final state in ['submitted','validated','rejected']) {
      await d.update('e_invoice_documents', {'status':state}, where:'id=?',whereArgs:['status-test']);
      await client.synchronize(config);
      expect((await store.history(config.normalizedBase, 'production')).single['status'], state);
      expect((await mobile.salesAll()).single.id, sale.id);
    }
    expect((await store.history(config.normalizedBase, 'sandbox')).single['status'], 'pending');
    await host.stop();
    await expectLater(client.synchronize(config), throwsA(anything));
    expect((await store.history(config.normalizedBase, 'production')).single['status'], 'rejected');
  });
  test('cancelled offline sale drains at zero host stock and unblocks later operations', () async {
    await desktop.setSetting('stock_policy', 'block');
    final sale = await sell();
    await mobile.upsertCustomer(const phone.Customer(id: 'new-customer', name: 'New customer'));
    await mobile.voidSale(sale.id, 'cancel offline');
    await mobile.upsertSupplier(const phone.Supplier(id: 'new-supplier', name: 'After cancellation'));
    await desktop.adjustStock(productId: 'desktop-product', newStock: 0, operator: 'admin');
    await client.synchronize(config);
    await client.synchronize(config);
    expect((await desktop.getProduct('desktop-product'))!.stock, 0);
    expect((await mobile.getProduct('phone-product'))!.stock, 0);
    expect((await desktop.salesAll()).single.voided, 1);
    expect(await (await desktopDb.db).query('stock_reversals'), hasLength(1));
    expect(await (await desktopDb.db).query('suppliers', where: 'id=?', whereArgs: ['new-supplier']), hasLength(1));
    expect(await (await mobileDb.db).query('sync_outbox'), isEmpty);
  });

  test('stocktake between sale and void retains inventory dependencies', () async {
    await desktop.setSetting('stock_policy', 'block');
    final sale = await sell();
    await mobile.adjustStock(productId: 'phone-product', newStock: 9, operator: 'admin');
    await mobile.voidSale(sale.id, 'cancel after stocktake');
    await client.synchronize(config);
    await client.synchronize(config);
    expect((await desktop.getProduct('desktop-product'))!.stock, 11);
    expect((await mobile.getProduct('phone-product'))!.stock, 11);
    expect((await desktop.salesAll()).single.voided, 1);
    expect(await (await mobileDb.db).query('sync_outbox'), isEmpty);
  });
}
