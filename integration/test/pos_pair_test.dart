import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:cnkh_pos_desktop/db/app_database.dart' as pc;
import 'package:cnkh_pos_desktop/services/pos_repository.dart' as pc;
import 'package:cnkh_pos_desktop/models/product.dart' as pc;
import 'package:cnkh_pos_desktop/models/cart_item.dart' as pcCart;
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/desktop_backup.dart';
import 'package:cnkh_pos_desktop/services/purchase_reverse_safety.dart' as pcPurchase;
import 'package:cnkh_pos_mobile/db/app_database.dart' as phone;
import 'package:cnkh_pos_mobile/services/pos_repository.dart' as phone;
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart' as phoneOcr;
import 'package:cnkh_pos_mobile/models/cart_item.dart' as phone;
import 'package:cnkh_pos_mobile/services/lan_sync.dart';

class _LoseReverseAck extends http.BaseClient {
  final http.Client _inner = http.Client();
  bool lost = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final reverse = request is http.Request && request.url.path == '/api/v1/mutations' &&
        (jsonDecode(request.body)['operations'] as List).any((op) => op['kind'] == 'purchase_reverse');
    final response = await _inner.send(request);
    if (reverse && !lost) {
      lost = true;
      await response.stream.drain<void>();
      throw const SocketException('Desktop committed; reversal ACK lost');
    }
    return response;
  }
  @override
  void close() => _inner.close();
}

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
  test('purchase made before first pairing uploads before catalog and retries idempotently', () async {
    final offlineDb = phone.AppDatabase.forTesting('${temp.path}/unpaired.db', seed:false);
    final offlineRepo = phone.PosRepository(database:offlineDb);
    final offlineClient = LanSyncClient(offlineRepo);
    try {
      await offlineRepo.upsertProduct(const phone.Product(
        id:'unpaired-phone-product', nameZh:'商品', nameEn:'Product', sku:'SKU-1',
        barcode:'10001', priceCents:100, costCents:200, stock:10,
      ));
      await offlineRepo.createPurchase(
        supplierId:'unpaired-supplier', supplierName:'Supplier',
        lines:[{'productId':'unpaired-phone-product','qty':5,'unitCostCents':60}],
        totalCents:300, operator:'admin',
      );
      var outbox=await (await offlineDb.db).query('sync_outbox', orderBy:'seq ASC');
      expect(outbox.map((row)=>row['kind']),['product_upsert','purchase']);
      final purchaseOperation=outbox.singleWhere((row)=>row['kind']=='purchase');
      final purchasePayload=jsonDecode(purchaseOperation['payload_json'] as String);
      await offlineClient.saveConfig(config);
      await offlineClient.synchronize(config);
      await offlineClient.synchronize(config);
      expect((await desktop.getProduct('desktop-product'))!.stock,15);
      expect((await offlineRepo.getProduct('unpaired-phone-product'))!.stock,15);
      expect(await (await desktopDb.db).query('purchases'),hasLength(1));
      expect(await (await offlineDb.db).query('sync_outbox'),isEmpty);
      expect(await (await desktopDb.db).query('stock_moves',where:"reason='purchase'"),hasLength(1));
      final transport=HttpClient();
      try {
        final request=await transport.postUrl(Uri.parse('${config.normalizedBase}/api/v1/mutations'));
        request.headers.set('X-CNKH-Token',config.token);
        request.headers.contentType=ContentType.json;
        request.write(jsonEncode({'operations':[{'id':'replacement-ack','kind':'purchase','payload':purchasePayload}]}));
        final response=await request.close();
        final body=jsonDecode(await response.transform(utf8.decoder).join()) as Map<String,dynamic>;
        expect(response.statusCode,200);
        expect(body['acknowledged'],contains('replacement-ack'));
      } finally {
        transport.close(force:true);
      }
      expect((await desktop.getProduct('desktop-product'))!.stock,15);
      expect(await (await desktopDb.db).query('purchases'),hasLength(1));
      final changedPayload=jsonDecode(jsonEncode(purchasePayload)) as Map<String,dynamic>;
      final changedLine=Map<String,dynamic>.from((changedPayload['lines'] as List).single as Map);
      changedLine['qty']=6;
      changedPayload['lines']=[changedLine];
      final mismatchTransport=HttpClient();
      try {
        final request=await mismatchTransport.postUrl(Uri.parse('${config.normalizedBase}/api/v1/mutations'));
        request.headers.set('X-CNKH-Token',config.token);
        request.headers.contentType=ContentType.json;
        request.write(jsonEncode({'operations':[{'id':'changed-purchase-payload','kind':'purchase','payload':changedPayload}]}));
        final response=await request.close();
        final body=jsonDecode(await response.transform(utf8.decoder).join()) as Map<String,dynamic>;
        expect(body['ok'],false);
        expect(body['acknowledged'],isEmpty);
      } finally {
        mismatchTransport.close(force:true);
      }
      expect((await desktop.getProduct('desktop-product'))!.stock,15);
      final desktopPurchase=(await (await desktopDb.db).query('purchases')).single;
      final savedLines=jsonDecode(desktopPurchase['lines_json'] as String) as List;
      expect((savedLines.single as Map)['beforeCostCents'],200);
      expect((savedLines.single as Map)['desktopBeforeCostCents'],40);
      await (await desktopDb.db).transaction((txn)=>pcPurchase.reversePurchaseSafely(
        txn,purchase:desktopPurchase,operator:'admin',reason:'desktop cost authority check',
      ));
      expect((await desktop.getProduct('desktop-product'))!.stock,10);
      expect((await desktop.getProduct('desktop-product'))!.costCents,40);
    } finally {
      await offlineDb.close();
    }
  });
  test('unpaired stocktake uploads against the existing Desktop SKU before pull', () async {
    final offlineDb=phone.AppDatabase.forTesting('${temp.path}/unpaired-stocktake.db',seed:false);
    final offlineRepo=phone.PosRepository(database:offlineDb);
    final offlineClient=LanSyncClient(offlineRepo);
    try {
      await offlineRepo.upsertProduct(const phone.Product(
        id:'unpaired-stocktake-product',nameZh:'商品',nameEn:'Product',sku:'SKU-1',
        barcode:'10001',priceCents:100,costCents:40,stock:10,
      ));
      await offlineRepo.adjustStock(productId:'unpaired-stocktake-product',newStock:12,operator:'staff');
      final queued=await (await offlineDb.db).query('sync_outbox',orderBy:'seq ASC');
      expect(queued.map((row)=>row['kind']),['product_upsert','stocktake']);
      await offlineClient.saveConfig(config);
      await offlineClient.synchronize(config);
      await offlineClient.synchronize(config);
      expect((await desktop.getProduct('desktop-product'))!.stock,12);
      expect((await offlineRepo.getProduct('unpaired-stocktake-product'))!.stock,12);
      expect(await (await offlineDb.db).query('sync_outbox'),isEmpty);
    } finally {
      await offlineDb.close();
    }
  });
  test('a stale SKU cannot redirect a mapped pending purchase to another Desktop product', () async {
    await desktop.upsertProduct(const pc.Product(id:'desktop-product',nameZh:'商品',nameEn:'Product',
      sku:'RENAMED-SKU',barcode:'RENAMED-BC',priceCents:100,costCents:40,stock:10));
    await desktop.upsertProduct(const pc.Product(id:'other-desktop-product',nameZh:'另一商品',nameEn:'Other',
      sku:'SKU-1',barcode:'10001',priceCents:100,costCents:30,stock:50));
    await mobile.createPurchase(supplierId:'supplier',supplierName:'Supplier',
      lines:[{'productId':'phone-product','qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
    final db=await mobileDb.db;
    final operation=(await db.query('sync_outbox')).single;
    expect(jsonDecode(operation['payload_json'] as String)['lines'][0]['productId'],'desktop-product');
    await expectLater(client.synchronize(config),throwsStateError);
    expect((await desktop.getProduct('desktop-product'))!.stock,10);
    expect((await desktop.getProduct('other-desktop-product'))!.stock,50);
    expect((await mobile.getProduct('phone-product'))!.stock,15);
    expect(await (await desktopDb.db).query('purchases'),isEmpty);
    final retained=(await db.query('sync_outbox')).single;
    expect(retained['id'],operation['id']);
    expect(retained['last_error'],contains('ID 与 SKU/条码'));
  });
  test('v9 unpaired purchase upgrade replays the initial stock baseline against an empty or existing catalog', () async {
    for (final existing in [true,false]) {
      final path='${temp.path}/legacy-${existing ? 'existing' : 'new'}.db';
      var legacyDb=phone.AppDatabase.forTesting(path,seed:false);
      var legacyRepo=phone.PosRepository(database:legacyDb);
      final id=existing?'legacy-phone-existing':'legacy-phone-new';
      await legacyRepo.upsertProduct(phone.Product(id:id,nameZh:'商品',nameEn:'Product',
        sku:existing?'SKU-1':'NEW-SKU',barcode:existing?'10001':'NEW-BC',
        priceCents:100,costCents:40,stock:10));
      await legacyRepo.createPurchase(supplierId:'supplier',supplierName:'Supplier',
        lines:[{'productId':id,'qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
      final old=await legacyDb.db;
      await old.delete('sync_outbox'); // pre-v10 builds skipped these unpaired writes.
      await old.setVersion(9);
      await legacyDb.close();
      legacyDb=phone.AppDatabase.forTesting(path,seed:false);
      legacyRepo=phone.PosRepository(database:legacyDb);
      try {
        final pending=await (await legacyDb.db).query('sync_outbox',orderBy:'seq');
        expect(pending.map((r)=>r['kind']),['product_upsert','purchase']);
        expect(jsonDecode(pending.first['payload_json'] as String)['row']['stock'],10);
        final firstPair=LanSyncClient(legacyRepo);
        await firstPair.saveConfig(config);
        await firstPair.synchronize(config);
        await firstPair.synchronize(config);
        final desktopId=existing?'desktop-product':id;
        expect((await desktop.getProduct(desktopId))!.stock,15);
        expect((await legacyRepo.getProduct(id))!.stock,15);
        expect(await (await legacyDb.db).query('sync_outbox'),isEmpty);
        expect(await (await desktopDb.db).query('stock_moves',
          where:"product_id=? AND reason='purchase'",whereArgs:[desktopId]),hasLength(1));
      } finally {
        await legacyDb.close();
      }
    }
  });
  test('a later pre-pair catalog edit resolves its original ID and preserves Desktop baseline cost', () async {
    final offlineDb=phone.AppDatabase.forTesting('${temp.path}/pre-pair-edit.db',seed:false);
    final offline=phone.PosRepository(database:offlineDb);
    try {
      await offline.upsertProduct(const phone.Product(id:'unpaired-edit',nameZh:'商品',nameEn:'Product',
        sku:'SKU-1',barcode:'10001',priceCents:100,costCents:200,stock:10));
      await offline.upsertProduct(const phone.Product(id:'unpaired-edit',nameZh:'更正名称',nameEn:'Product',
        sku:'SKU-1',barcode:'10001',priceCents:100,costCents:200,stock:10));
      await offline.createPurchase(supplierId:'supplier',supplierName:'Supplier',
        lines:[{'productId':'unpaired-edit','qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
      final firstPair=LanSyncClient(offline);
      await firstPair.saveConfig(config);
      await firstPair.synchronize(config);
      final product=(await desktop.getProduct('desktop-product'))!;
      expect(product.nameZh,'更正名称');
      expect(product.stock,15);
      final purchase=(await (await desktopDb.db).query('purchases')).single;
      expect(jsonDecode(purchase['lines_json'] as String)[0]['desktopBeforeCostCents'],40);
      expect(await (await offlineDb.db).query('sync_outbox'),isEmpty);
    } finally {
      await offlineDb.close();
    }
  });
  test('stock history endpoint preserves Desktop sale and void with zero net change', () async {
    await mobile.createPurchase(
      supplierId:'mobile-supplier', supplierName:'Mobile Supplier',
      lines:[{'productId':'phone-product','qty':5,'unitCostCents':60}],
      totalCents:300, operator:'staff',
    );
    await client.synchronize(config);
    final purchase=(await (await mobileDb.db).query('purchases')).single;
    expect((await desktop.getProduct('desktop-product'))!.stock,15);

    final product=(await desktop.getProduct('desktop-product'))!;
    final sale=await desktop.createSale(
      cart:pcCart.CartState(items:[pcCart.CartItem(product:product,qty:4)]),
      paymentMethod:'CASH',paidCents:400,cashier:'desktop-staff',
    );
    await desktop.voidSale(sale.id,'test net zero');
    final transport=HttpClient();
    try {
      final request=await transport.getUrl(Uri.parse('${config.normalizedBase}/api/v1/stock-moves'));
      request.headers.set('X-CNKH-Token',config.token);
      final response=await request.close();
      final body=jsonDecode(await response.transform(utf8.decoder).join()) as Map<String,dynamic>;
      expect(response.statusCode,200);
      final items=(body['items'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
      final saleMoves=items.where((r)=>r['source_id']==sale.id).toList();
      expect(saleMoves.map((r)=>r['reason']).toSet(),{'sale','sale_void'});
      expect(saleMoves.fold<double>(0,(sum,r)=>sum+(r['change'] as num).toDouble()),0);
      expect(items.any((r)=>r['reason']=='purchase' && r['source_id']==purchase['id']),isTrue);
      expect(saleMoves.map((r)=>(r['cursor'] as num).toInt()).toList(),orderedEquals(
        saleMoves.map((r)=>(r['cursor'] as num).toInt()).toList()..sort(),
      ));
      final healthRequest=await transport.getUrl(Uri.parse('${config.normalizedBase}/api/v1/health'));
      healthRequest.headers.set('X-CNKH-Token',config.token);
      final healthResponse=await healthRequest.close();
      final health=jsonDecode(await healthResponse.transform(utf8.decoder).join()) as Map<String,dynamic>;
      expect(health['capabilities'],contains('stock_moves_v1'));
      expect(health['stock_moves_cursor'],body['cursor']);

      await client.synchronize(config);
      await expectLater(phoneOcr.PurchaseOcrRepository(mobile).reversePurchase(
        purchaseId:purchase['id'] as String, operator:'staff', reason:'must not reverse after PC activity',
      ),throwsA(isA<StateError>()));
      expect((await mobile.getProduct('phone-product'))!.stock,15);
      expect((await desktop.getProduct('desktop-product'))!.stock,15);
      final markers=await (await mobileDb.db).query('stock_moves',where:"reason='desktop_catalog_sync'");
      expect(markers,hasLength(2));
      expect((await (await mobileDb.db).query('purchases')).single['reversed'],0);
    } finally {
      transport.close(force:true);
    }
  });
  test('a reverse rejected after queuing keeps both inventories and allows the next operation', () async {
    await mobile.createPurchase(supplierId:'supplier',supplierName:'Supplier',
      lines:[{'productId':'phone-product','qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
    await client.synchronize(config);
    final phoneDb=await mobileDb.db;
    final purchase=(await phoneDb.query('purchases')).single;
    await phoneOcr.PurchaseOcrRepository(mobile).reversePurchase(
      purchaseId:purchase['id'] as String,operator:'admin',reason:'queued before Desktop changed');
    final originalRequest=(await phoneDb.query('sync_outbox')).single;
    expect((await mobile.getProduct('phone-product'))!.stock,15);
    expect((await phoneDb.query('purchases')).single['reversed'],0);
    await mobile.upsertSupplier(const phone.Supplier(id:'later-supplier',name:'Later Supplier',phone:'0199999'));
    final sale=await desktop.createSale(
      cart:pcCart.CartState(items:[pcCart.CartItem(product:(await desktop.getProduct('desktop-product'))!,qty:2)]),
      paymentMethod:'CASH',paidCents:200,cashier:'desktop');
    await desktop.voidSale(sale.id,'net zero after reverse request');
    final message=await client.synchronize(config);
    expect(message,contains('原请求已保留'));
    expect((await desktop.getProduct('desktop-product'))!.stock,15);
    expect((await mobile.getProduct('phone-product'))!.stock,15);
    expect((await (await desktopDb.db).query('purchases')).single['reversed'],0);
    expect((await phoneDb.query('purchases')).single['reversed'],0);
    expect(await phoneDb.query('purchase_reversals'),isEmpty);
    expect((await desktop.listSuppliers()).any((s)=>s.name=='Later Supplier'),true);
    final retained=(await phoneDb.query('sync_outbox')).single;
    expect(retained['id'],originalRequest['id']);
    expect(retained['delivery_state'],'rejected');
    expect('${retained['last_error']}',isNotEmpty);
    await client.synchronize(config);
    expect((await mobile.getProduct('phone-product'))!.stock,15);
    expect(await phoneDb.query('purchase_audit_log',where:"action='purchase_reverse_rejected'"),hasLength(1));
    expect((await phoneDb.query('sync_outbox')).single['id'],originalRequest['id']);
  });
  test('a committed reverse with a lost ACK is retried and applied locally exactly once', () async {
    await mobile.createPurchase(supplierId:'supplier',supplierName:'Supplier',
      lines:[{'productId':'phone-product','qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
    await client.synchronize(config);
    final phoneDb=await mobileDb.db;
    final purchase=(await phoneDb.query('purchases')).single;
    await phoneOcr.PurchaseOcrRepository(mobile).reversePurchase(
      purchaseId:purchase['id'] as String,operator:'admin',reason:'lost ACK test');
    final original=(await phoneDb.query('sync_outbox')).single;
    final transport=_LoseReverseAck();
    final retrying=LanSyncClient(mobile,httpClient:transport);
    try {
      await expectLater(retrying.synchronize(config),throwsA(isA<SocketException>()));
      expect((await desktop.getProduct('desktop-product'))!.stock,10);
      expect((await mobile.getProduct('phone-product'))!.stock,15);
      expect((await phoneDb.query('purchases')).single['reversed'],0);
      expect((await phoneDb.query('sync_outbox')).single['id'],original['id']);
      await retrying.synchronize(config);
      await retrying.synchronize(config);
      expect((await desktop.getProduct('desktop-product'))!.stock,10);
      expect((await desktop.getProduct('desktop-product'))!.costCents,40);
      expect((await mobile.getProduct('phone-product'))!.stock,10);
      expect((await mobile.getProduct('phone-product'))!.costCents,40);
      expect((await phoneDb.query('purchases')).single['reversed'],1);
      expect(await phoneDb.query('sync_outbox'),isEmpty);
      expect(await phoneDb.query('stock_moves',where:"reason='purchase_reversal'"),hasLength(1));
      expect(await (await desktopDb.db).query('stock_moves',where:"reason='purchase_reversal'"),hasLength(1));
      expect(await phoneDb.query('purchase_audit_log',where:"action='purchase_reverse_acknowledged'"),hasLength(1));
    } finally {
      transport.close();
    }
  });
  test('backup cursor rollback reconciles missing Desktop catalog and protects pending local work', () async {
    final port=host.port;
    await host.stop();
    final images='${temp.path}/images';
    await Directory(images).create();
    final backups=DesktopBackupService(databasePath:'${temp.path}/pc.db',
      productImagesDirectory:images,closeDatabase:desktopDb.close);
    final backup='${temp.path}/older.cnkhbackup';
    await backups.createBackup(backup);
    await desktop.upsertProduct(const pc.Product(id:'desktop-later',nameZh:'后来商品',nameEn:'Later',
      sku:'LATER',barcode:'20002',priceCents:100,stock:6));
    host=LanPairingHost.forTesting(desktop,database:desktopDb,configuredPort:port);
    await host.start();
    await client.synchronize(config);
    const localId='pc-desktop-later';
    expect((await mobile.getProduct(localId))!.stock,6);
    final newerCursor=int.parse(await mobile.getSetting('lan_sync_products_cursor'));
    await host.stop();
    await backups.restoreBackup(backup);
    host=LanPairingHost.forTesting(desktop,database:desktopDb,configuredPort:port);
    await host.start();
    await client.synchronize(config);
    expect(int.parse(await mobile.getSetting('lan_sync_products_cursor')),lessThan(newerCursor));
    final phoneRows=await (await mobileDb.db).query('products',where:'id=?',whereArgs:[localId]);
    expect(phoneRows.single['is_deleted'],1);
    expect(await mobileDb.db.then((db)=>db.query('sync_entity_ids',where:"entity='product' AND local_id=?",whereArgs:[localId])),hasLength(1));

    // A local operation is attempted before the snapshot; its rejection stops
    // catalog application, so the pending operation and product stay usable.
    await mobileDb.db.then((db)=>db.update('products',{'is_deleted':0},where:'id=?',whereArgs:[localId]));
    await mobile.adjustStock(productId:localId,newStock:8,operator:'staff');
    await expectLater(client.synchronize(config),throwsStateError);
    final protected=await (await mobileDb.db).query('products',where:'id=?',whereArgs:[localId]);
    expect(protected.single['is_deleted'],0);
    expect(protected.single['stock'],8);
    expect(await mobileDb.db.then((db)=>db.query('sync_outbox')),hasLength(1));
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
