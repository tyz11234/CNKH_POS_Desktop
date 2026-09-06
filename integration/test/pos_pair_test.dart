import 'dart:convert';
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
  test('different IDs map sale customer and void exactly once', () async {
    final sale = await sell(credit:true);
    await client.synchronize(config);
    await client.synchronize(config);
    expect((await desktop.getProduct('desktop-product'))!.stock, 8);
    final rows = await (await desktopDb.db).query('sales');
    expect(rows, hasLength(1));
    expect(rows.single['customer_id'], 'desktop-customer');
    expect(rows.single['credit_outstanding_cents'], 200);
    await mobile.voidSale(sale.id, 'cancel');
    await client.synchronize(config);
    await client.forceReconcile(config);
    expect((await desktop.getProduct('desktop-product'))!.stock, 10);
    expect((await mobile.getProduct('phone-product'))!.stock, 10);
    expect((await (await desktopDb.db).query('sales')).single['voided'], 1);
    expect(await (await mobileDb.db).query('sync_outbox'), isEmpty);
  });
  test('offline purchase sale and void keep operation order', () async {
    await mobile.createPurchase(supplierId:'s1', supplierName:'Supplier', lines:[{'productId':'phone-product','qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
    final sale = await sell();
    await mobile.voidSale(sale.id, 'cancel offline');
    await client.synchronize(config);
    await client.synchronize(config);
    expect((await desktop.getProduct('desktop-product'))!.stock, 15);
    expect((await mobile.getProduct('phone-product'))!.stock, 15);
    expect((await desktop.getProduct('desktop-product'))!.costCents, 60);
    expect(await (await desktopDb.db).query('purchases'), hasLength(1));
    expect(await (await desktopDb.db).query('stock_reversals'), hasLength(1));
  });
  test('stocktake conflict preserves operation and both inventories', () async {
    await mobile.adjustStock(productId:'phone-product',newStock:12,operator:'admin');
    await desktop.adjustStock(productId:'desktop-product',newStock:9,operator:'admin');
    await expectLater(client.synchronize(config), throwsStateError);
    expect((await desktop.getProduct('desktop-product'))!.stock,9);
    expect((await mobile.getProduct('phone-product'))!.stock,12);
    final pending = await (await mobileDb.db).query('sync_outbox');
    expect(pending,hasLength(1));
    expect(pending.single['last_error'],isNotEmpty);
    await desktop.adjustStock(productId:'desktop-product',newStock:10,operator:'admin');
    await client.synchronize(config);
    expect((await desktop.getProduct('desktop-product'))!.stock,12);
    expect(await (await mobileDb.db).query('sync_outbox'),isEmpty);
  });
  test('initial offline connection retries after server returns', () async {
    final port = host.port;
    await host.stop();
    final live = LanLiveSync(client);
    try {
      await expectLater(live.connect(config),throwsStateError);
      host = LanPairingHost.forTesting(desktop,database:desktopDb,configuredPort:port);
      await host.start();
      final deadline = DateTime.now().add(const Duration(seconds:15));
      while (!live.connected && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds:100));
      }
      expect(live.connected,isTrue);
    } finally { await live.disconnect(); }
  });
  test('lost purchase acknowledgement does not add stock again on retry', () async {
    await mobile.createPurchase(supplierId:'s1', supplierName:'Supplier', lines:[{'productId':'phone-product','qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
    final op = (await (await mobileDb.db).query('sync_outbox')).single;
    final transport = HttpClient();
    try {
      final request = await transport.postUrl(Uri.parse('${config.normalizedBase}/api/v1/mutations'));
      request.headers.set('X-CNKH-Token',config.token);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'operations':[{'id':op['id'],'kind':op['kind'],'payload':jsonDecode(op['payload_json'] as String)}]}));
      final response = await request.close();
      expect(response.statusCode,200);
      await response.drain<void>();
      // Simulate app death before saving the acknowledgement: outbox is retained.
    } finally { transport.close(force:true); }
    expect((await desktop.getProduct('desktop-product'))!.stock,15);
    await client.synchronize(config);
    expect((await desktop.getProduct('desktop-product'))!.stock,15);
    expect((await mobile.getProduct('phone-product'))!.stock,15);
    expect(await (await desktopDb.db).query('purchases'),hasLength(1));
    expect(await (await mobileDb.db).query('sync_outbox'),isEmpty);
  });
  test('PC void propagates without another sale upload', () async {
    await sell();
    await client.synchronize(config);
    final sale = (await desktop.salesAll()).single;
    await desktop.voidSale(sale.id, 'PC cancel');
    await client.synchronize(config);
    expect((await mobile.getProduct('phone-product'))!.stock, 10);
    expect((await (await mobileDb.db).query('sales')).single['voided'], 1);
    expect(await desktop.salesAll(), hasLength(1));
  });
}
