import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cnkh_pos_desktop/db/app_database.dart' as pc;
import 'package:cnkh_pos_desktop/models/cart_item.dart' as pc;
import 'package:cnkh_pos_desktop/services/pos_repository.dart' as pc;
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_mobile/db/app_database.dart' as phone;
import 'package:cnkh_pos_mobile/models/cart_item.dart' as phone;
import 'package:cnkh_pos_mobile/services/pos_repository.dart' as phone;
import 'package:cnkh_pos_mobile/services/purchase_ocr_repository.dart';
import 'package:cnkh_pos_mobile/services/lan_sync.dart';

class LoseProductAck extends http.BaseClient {
  final inner = http.Client(); bool lost = false;
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isProduct = request is http.Request && request.url.path == '/api/v1/mutations' &&
      (jsonDecode(request.body)['operations'] as List).any((op) => op['kind']=='product_upsert');
    final response = await inner.send(request);
    if (isProduct && !lost) { lost=true; await response.stream.drain<void>();
      throw const SocketException('product committed, ACK lost'); }
    return response;
  }
  @override void close() => inner.close();
}

/// Exercise v1 peers that predate identity ACKs and barcode sale snapshots.
class LegacyIdentityWire extends http.BaseClient {
  final inner = http.Client();
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path == '/api/v1/mutations') {
        for (final op in body['operations'] as List) { op.remove('client_entity_id'); }
      } else if (request.url.path == '/api/v1/sales') {
        for (final sale in body['sales'] as List) {
          for (final line in sale['lines'] as List) { line.remove('barcode'); }
        }
      }
      request.body = jsonEncode(body);
    }
    final response = await inner.send(request);
    if (request.url.path != '/api/v1/mutations') return response;
    final body = jsonDecode(await response.stream.bytesToString()) as Map<String, dynamic>;
    body.remove('entity_mappings');
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))),
        response.statusCode, headers: {...response.headers}..remove('content-length'));
  }
  @override void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); HttpOverrides.global = null;
  late Directory temp; late pc.AppDatabase desktopDb; late phone.AppDatabase mobileDb;
  late pc.PosRepository desktop; late phone.PosRepository mobile;
  late LanPairingHost host; late LanSyncConfig config; late LanSyncClient client;
  setUp(() async {
    temp=await Directory.systemTemp.createTemp('cnkh-eleven-http-');
    desktopDb=pc.AppDatabase.forTesting('${temp.path}/pc.db',seed:false);
    mobileDb=phone.AppDatabase.forTesting('${temp.path}/phone.db',seed:false);
    desktop=pc.PosRepository(database:desktopDb,clock:()=>DateTime(2026,10,1,12));
    mobile=phone.PosRepository(database:mobileDb,clock:()=>DateTime(2026,10,1,12));
    host=LanPairingHost.forTesting(desktop,database:desktopDb); await host.start();
    config=LanSyncConfig(baseUrl:'http://127.0.0.1:${host.port}',token:await desktop.getSetting('lan_host_token'));
    client=LanSyncClient(mobile);
  });
  tearDown(() async {await host.stop();await desktopDb.close();await mobileDb.close();await temp.delete(recursive:true);});
  Future<void> products({double pcStock=100,double phoneStock=0,String sku=''}) async {
    await desktop.upsertProduct(pc.Product(id:'pc-original',nameZh:'商品',nameEn:'Product',
      sku:sku,barcode:'10001',priceCents:100,costCents:40,stock:pcStock));
    await mobile.upsertProduct(phone.Product(id:'phone-original',nameZh:'商品',nameEn:'Product',
      sku:sku,barcode:'10001',priceCents:100,costCents:40,stock:phoneStock));
  }
  Future<phone.SaleRecord> sale({bool credit=false}) async => mobile.createSale(
    cart:phone.CartState(items:[phone.CartItem(product:(await mobile.getProduct('phone-original'))!,qty:2)]),
    paymentMethod:credit?'CREDIT':'CASH',paidCents:credit?30:200,cashier:'admin',
    depositMethod:credit?'CASH':null,customer:credit?const phone.Customer(id:'c',name:'Buyer',phone:'0123'):null);
  Future<String> purchase() async {
    await mobile.createPurchase(supplierId:'s',supplierName:'Supplier',
      lines:[{'productId':'phone-original','qty':5,'unitCostCents':60}],totalCents:300,operator:'admin');
    return (await mobile.listPurchases()).single['id'] as String;
  }
  Future<Map<String,dynamic>> postMutation(Map<String,Object?> op) async {
    final response=await http.post(Uri.parse('${config.normalizedBase}/api/v1/mutations'),
      headers:{'Content-Type':'application/json','X-CNKH-Token':config.token},
      body:jsonEncode({'operations':[op]}));
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String,dynamic>;
  }
  test('F01 first pairing, empty SKU, offline sale, lost/repeated product ACK and retry deduct once', () async {
    await products(); final sold=await sale();
    final db=await mobileDb.db;
    final productOp=(await db.query('sync_outbox',where:"kind='product_upsert'")).single;
    final transport=LoseProductAck();
    final retryClient=LanSyncClient(mobile,httpClient:transport);
    try {
      await retryClient.saveConfig(config);
      await expectLater(retryClient.synchronize(config),throwsA(anything));
      expect(await db.query('sync_outbox'),hasLength(2));
      expect(await desktop.salesAll(),isEmpty);
      await retryClient.synchronize(config);await retryClient.synchronize(config);
      expect((await desktop.getProduct('pc-original'))!.stock,98);
      expect((await mobile.getProduct('phone-original'))!.stock,98);
      expect(await desktop.salesAll(),hasLength(1));
      expect((await mobile.salesAll()).single.id,sold.id);
      final replay=await postMutation({'id':productOp['id'],'kind':'product_upsert',
        'client_entity_id':'phone-original','payload':jsonDecode(productOp['payload_json'] as String)});
      expect(replay['acknowledged'],[productOp['id']]);
      expect((replay['entity_mappings'] as List).single['remote_id'],'pc-original');
      expect(await db.query('sync_entity_ids',where:"entity='product'"),hasLength(1));
      expect(await (await desktopDb.db).query('stock_moves',where:"reason='sale'"),hasLength(1));
      expect(await db.query('sync_outbox'),isEmpty);
    } finally {transport.close();}
  });
  test('F01 ambiguous preexisting barcode preserves sales and operations with no inventory writes', () async {
    await products();await sale();
    await (await desktopDb.db).insert('products',const pc.Product(id:'ambiguous',nameZh:'商品',nameEn:'Product',
      sku:'',barcode:'10001',priceCents:100,costCents:40,stock:20).toMap());
    await client.saveConfig(config);
    await expectLater(client.synchronize(config),throwsStateError);
    expect(await (await mobileDb.db).query('sync_outbox'),hasLength(2));
    expect(await desktop.salesAll(),isEmpty);
    expect((await desktop.getProduct('pc-original'))!.stock,100);
  });
  test('F01 v1 peer without barcode or identity ACK resolves its historical product alias before catalog pull', () async {
    await products(); await sale();
    final transport = LegacyIdentityWire();
    try {
      final legacy = LanSyncClient(mobile, httpClient: transport);
      await legacy.saveConfig(config);
      await legacy.synchronize(config); await legacy.synchronize(config);
      expect((await desktop.getProduct('pc-original'))!.stock, 98);
      expect((await mobile.getProduct('phone-original'))!.stock, 98);
      expect(await desktop.salesAll(), hasLength(1));
      expect(await (await mobileDb.db).query('sync_outbox'), isEmpty);
    } finally { transport.close(); }
  });
  for(final full in [false,true]) {
    test('F02 ${full?'full':'incremental'} tombstone/recreate preserves historical IDs and repeated catalog succeeds', () async {
      await products(sku:'SKU-1');await client.saveConfig(config);await client.synchronize(config);
      final oldSale=await sale();final oldPurchase=await purchase();await client.synchronize(config);
      await desktop.softDeleteProduct('pc-original');
      await desktop.upsertProduct(const pc.Product(id:'pc-rebuilt',nameZh:'商品',nameEn:'Product',
        sku:'SKU-1',barcode:'10001',priceCents:100,costCents:80,stock:50));
      await client.synchronize(config,full:full);await client.synchronize(config,full:full);
      final db=await mobileDb.db;
      final mappings=await db.query('sync_entity_ids',where:"entity='product'");
      expect(mappings.singleWhere((m)=>m['local_id']=='phone-original')['remote_id'],'pc-original');
      final fresh=mappings.singleWhere((m)=>m['remote_id']=='pc-rebuilt')['local_id'] as String;
      expect(fresh,isNot('phone-original'));expect((await mobile.getProduct(fresh))!.stock,50);
      final old=(await db.query('products',where:'id=?',whereArgs:['phone-original'])).single;
      expect(old['is_deleted'],1);
      final saleRow=(await db.query('sales',where:'id=?',whereArgs:[oldSale.id])).single;
      expect(jsonDecode(saleRow['lines_json'] as String)[0]['productId'],'phone-original');
      final purchaseRow=(await db.query('purchases',where:'id=?',whereArgs:[oldPurchase])).single;
      expect(jsonDecode(purchaseRow['lines_json'] as String)[0]['productId'],'phone-original');
      expect(await db.query('stock_moves',where:'product_id=?',whereArgs:['phone-original']),isNotEmpty);
      expect(await db.query('sync_outbox'),isEmpty);
    });
  }
  test('F02 pending old purchase cannot be rebound to a rebuilt SKU; request and cursor stay intact', () async {
    await products(sku:'SKU-1');await client.saveConfig(config);await client.synchronize(config);
    final id=await purchase();final db=await mobileDb.db;
    final cursor=await mobile.getSetting('lan_sync_products_cursor');
    final queue=await db.query('sync_outbox');
    await desktop.softDeleteProduct('pc-original');
    await desktop.upsertProduct(const pc.Product(id:'pc-rebuilt',nameZh:'商品',nameEn:'Product',
      sku:'SKU-1',barcode:'10001',priceCents:100,costCents:80,stock:50));
    await expectLater(client.synchronize(config),throwsStateError);
    expect(await mobile.getSetting('lan_sync_products_cursor'),cursor);
    expect((await db.query('sync_outbox')).single['id'],queue.single['id']);
    expect(jsonDecode((await db.query('purchases',where:'id=?',whereArgs:[id])).single['lines_json'] as String)[0]['productId'],'phone-original');
    expect((await desktop.getProduct('pc-rebuilt'))!.stock,50);
    expect(await (await desktopDb.db).query('purchases'),isEmpty);
  });
  for(final initial in [0.0,100.0]) {
    test('F04 first pairing inventory baseline $initial permits actual purchase reversal once', () async {
      await products(pcStock:initial);final id=await purchase();
      await client.saveConfig(config);await client.synchronize(config);
      expect((await mobile.getProduct('phone-original'))!.stock,initial+5);
      await PurchaseOcrRepository(mobile).reversePurchase(purchaseId:id,operator:'admin',reason:'incorrect invoice');
      await client.synchronize(config);await client.synchronize(config);
      expect((await desktop.getProduct('pc-original'))!.stock,initial);
      expect((await mobile.getProduct('phone-original'))!.stock,initial);
      expect((await (await mobileDb.db).query('purchases')).single['reversed'],1);
      expect((await (await desktopDb.db).query('purchases')).single['reversed'],1);
      expect(await (await desktopDb.db).query('purchase_reversals'),hasLength(1));
      expect(await (await mobileDb.db).query('sync_outbox'),isEmpty);
    });
  }
  test('F04 genuine sale then void blocks queued reversal, retains rejection and later queue continues', () async {
    await products();final id=await purchase();await client.saveConfig(config);await client.synchronize(config);
    await PurchaseOcrRepository(mobile).reversePurchase(purchaseId:id,operator:'admin',reason:'incorrect invoice');
    final p=(await desktop.getProduct('pc-original'))!;
    final sold=await desktop.createSale(cart:pc.CartState(items:[pc.CartItem(product:p)]),paymentMethod:'CASH',paidCents:100,cashier:'admin');
    await desktop.voidSale(sold.id,'same stock, real activity');
    await mobile.upsertCustomer(const phone.Customer(id:'later',name:'After rejected request'));
    await client.synchronize(config);await client.synchronize(config);
    final db=await mobileDb.db;
    final request=(await db.query('sync_outbox')).single;
    expect(request['kind'],'purchase_reverse');expect(request['delivery_state'],'rejected');
    expect((await db.query('purchases')).single['reversed'],0);
    expect((await (await desktopDb.db).query('purchases')).single['reversed'],0);
    expect((await mobile.getProduct('phone-original'))!.stock,105);
    expect((await desktop.getProduct('pc-original'))!.stock,105);
    expect(await (await desktopDb.db).query('customers',where:'id=?',whereArgs:['later']),hasLength(1));
    expect(await db.query('stock_moves',where:"reason='desktop_catalog_sync'"),isNotEmpty);
    await expectLater(PurchaseOcrRepository(mobile).reversePurchase(purchaseId:id,operator:'admin',reason:'repeat'),throwsStateError);
  });
  test('F11 cash sales, LAN void and credit cash deposits are recomputed on both closing entries', () async {
    await products();await client.saveConfig(config);await client.synchronize(config);
    await mobile.upsertCustomer(const phone.Customer(id:'c',name:'Buyer',phone:'0123'));
    final first=await sale();await sale(credit:true);await mobile.voidSale(first.id,'LAN void');
    await client.synchronize(config);
    for(final repo in [desktop,mobile]) {
      // Different package repository types share this public call signature.
      await (repo as dynamic).saveDailyClosing(businessDate:'2026-10-01',openingCashCents:0,
        countedCashCents:30,systemCashCents:99999,closedBy:'admin');
      final rows=await (repo as dynamic).listClosings() as List;
      expect(rows.single['business_date'],'2026-10-01');expect(rows.single['system_cash_cents'],30);
    }
  });
}
