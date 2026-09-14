import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/db/einvoice_schema.dart';
import 'package:cnkh_pos_desktop/models/cart_item.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/einvoice/einvoice_settings.dart';
import 'package:cnkh_pos_desktop/services/einvoice/einvoice_service.dart';
import 'package:cnkh_pos_desktop/services/einvoice/invoice_mapper.dart';
import 'package:cnkh_pos_desktop/services/einvoice/myinvois_client.dart';

class MemoryKeys implements EInvoiceKeyStore {
  String? value;
  @override Future<String?> read() async => value;
  @override Future<void> write(String v) async { value = v; }
}
final supplier = <String,dynamic>{'environment':'sandbox','name':'CNKH Test','tin':'C1234567890','brn':'202001234567','msic':'47111','activity':'Retail','address':'1 Test Street','city':'Kuala Lumpur','state':'14','phone':'+60123456789','classification':'022','tax_type':'06','tax_rate_basis_points':0};
final buyer = <String,dynamic>{'name':'Test Buyer','tin':'C9876543210','id_type':'BRN','id_number':'202009876543','address':'2 Test Street','city':'Kuala Lumpur','state':'14','phone':'+60198765432'};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase database;
  late PosRepository repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cnkh-einvoice-');
    database = AppDatabase.forTesting('${dir.path}/pos.db', seed:true);
    repo = PosRepository(database:database);
  });
  tearDown(() async { await database.close(); await dir.delete(recursive:true); });
  Future<SaleRecord> sale() async {
    const p = Product(id:'einvoice-test',sku:'EI-TEST',barcode:'955123000001',nameZh:'测试商品',nameEn:'Test Product',priceCents:1060,stock:20);
    await repo.upsertProduct(p);
    return repo.createSale(cart:CartState(items:[CartItem(product:p,qty:2,discountCents:20)],orderDiscountCents:100),paymentMethod:'CASH',paidCents:2000,cashier:'admin');
  }
  test('fresh install and v8 upgrade preserve all business rows', () async {
    await sale(); final db = await database.db;
    final before = {for(final table in ['sales','products','customers','suppliers']) table:await db.query(table)};
    for(final table in ['e_invoice_logs','e_invoice_documents','e_invoice_settings']) { await db.execute('DROP TABLE $table'); }
    await db.setVersion(8); await database.close();
    final upgraded = await database.db;
    expect(await upgraded.getVersion(),9);
    for(final e in before.entries) { expect(await upgraded.query(e.key),e.value); }
    for(final table in ['e_invoice_logs','e_invoice_documents','e_invoice_settings']) { expect(await upgraded.query(table),isEmpty); }
    await ensureEInvoiceSchema(upgraded);
  });
  test('settings encrypt both credentials and isolate environments', () async {
    final db = await database.db; final keys = MemoryKeys();
    final settings = EInvoiceSettingsStore(db,keys:keys);
    await settings.save(supplier,clientId:'secret-client-id',clientSecret:'secret-password');
    expect(jsonEncode(await db.query('e_invoice_settings')),isNot(contains('secret-client-id')));
    expect(jsonEncode(await db.query('e_invoice_settings')),isNot(contains('secret-password')));
    expect((await settings.load(credentials:true))['client_secret'],'secret-password');
    expect((await settings.load()).containsKey('client_secret'),false);
    expect((await settings.load(environment:'production',credentials:true))['client_secret'],isNull);
    keys.value = null;
    await expectLater(settings.load(credentials:true),throwsStateError);
  });
  test('mapper uses sale snapshot, discounts, rounding and inclusive tax', () async {
    final s = await sale(); final db = await database.db;
    final row = (await db.query('sales',where:'id=?',whereArgs:[s.id])).single;
    final before = jsonEncode(row);
    final json = InvoiceMapper().mapSale(row,supplier:{...supplier,'tax_type':'02','tax_rate_basis_points':600},buyer:buyer,issuedAt:DateTime.utc(2026,9,13));
    final inv = (json['Invoice'] as List).single;
    expect(inv['LegalMonetaryTotal'][0]['PayableAmount'][0]['_'],20);
    expect(inv['TaxTotal'][0]['TaxAmount'][0]['_'],1.13);
    expect(inv['LegalMonetaryTotal'][0]['TaxExclusiveAmount'][0]['_'],18.87);
    expect(jsonEncode(row),before);
    expect(() => InvoiceMapper().mapSale({...row,'total_cents':999},supplier:supplier,buyer:buyer,issuedAt:DateTime.now()),throwsFormatException);
    expect(() => InvoiceMapper().mapSale(row,supplier:supplier,buyer:{},issuedAt:DateTime.now()),throwsFormatException);
  });
  test('OAuth caches token, refreshes expiry and retries one 401', () async {
    var clock=DateTime.utc(2026,9,13),auths=0,queries=0;
    final client=MyInvoisClient(environment:'sandbox',now:()=>clock,credentials:()async=>{'client_id':'id','client_secret':'secret'},transport:MockClient((r)async{
      if(r.url.path=='/connect/token'){auths++;expect(r.body,contains('grant_type=client_credentials'));return http.Response(jsonEncode({'access_token':'token$auths','expires_in':3600}),200);}
      queries++;if(queries==1)return http.Response('{}',401);
      return http.Response('{"documentSummary":[]}',200);
    }));
    await client.queryStatus('uid');expect(auths,2);
    await client.queryStatus('uid');expect(auths,2);
    clock=clock.add(const Duration(hours:2));await client.queryStatus('uid');expect(auths,3);client.close();
  });
  test('submission envelope hashes exact UTF8 and API failures surface', () async {
    final body=await MyInvoisClient.envelope('R1','{"test":"测试"}');
    expect(utf8.decode(base64Decode(body['documents'][0]['document'])),'{"test":"测试"}');
    expect(body['documents'][0]['documentHash'],hasLength(64));
    final c=MyInvoisClient(environment:'production',credentials:()async=>{'client_id':'id','client_secret':'secret'},transport:MockClient((r)async=>r.url.path=='/connect/token'?http.Response('{"access_token":"t","expires_in":3600}',200):http.Response('{}',503)));
    await expectLater(c.submitDocument(body),throwsA(isA<MyInvoisException>()));c.close();
  });
  test('durable duplicate guard, status query and cancellation leave sale intact', () async {
    final s=await sale();await repo.auth.initializeAdmin('839201');await repo.auth.login('admin','839201');
    final db=await database.db;final original=await db.query('sales');var posts=0;
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),clientFactory:(env,settings)=>MyInvoisClient(environment:env,credentials:()=>settings.load(environment:env,credentials:true),transport:MockClient((r)async{
      if(r.url.path=='/connect/token')return http.Response('{"access_token":"t","expires_in":3600}',200);
      if(r.method=='POST'){posts++;return http.Response(jsonEncode({'submissionUID':'uid','acceptedDocuments':[{'uuid':'uuid','invoiceCodeNumber':s.receiptNo}]}),202);}
      if(r.method=='PUT')return http.Response('{"uuid":"uuid","status":"Cancelled"}',200);
      return http.Response('{"documentSummary":[{"uuid":"uuid","submissionUid":"uid","status":"Valid"}]}',200);
    })));
    await service.saveSettings(supplier,'id','secret');await service.prepare(s.id,'sandbox',buyer);
    await service.submitPendingInvoice(s.id);
    await expectLater(service.submitPendingInvoice(s.id),throwsStateError);expect(posts,1);
    var doc=(await db.query('e_invoice_documents')).single;expect(doc['status'],'submitted');
    await service.refresh(doc['id'] as String);expect((await db.query('e_invoice_documents')).single['status'],'validated');
    await service.cancel(doc['id'] as String,'Test cancellation');expect((await db.query('e_invoice_documents')).single['status'],'cancelled');
    expect(await db.query('sales'),original);
    await db.delete('sales',where:'id=?',whereArgs:[s.id]);
    final archived=(await service.history('sandbox',receipt:s.receiptNo)).single;
    expect(archived['status'],'cancelled');expect(archived['total_cents'],2000);
    await db.insert('sales',{...original.single,'id':'reused-sale-id'});
    await expectLater(service.prepare('reused-sale-id','sandbox',buyer),throwsStateError);
    service.dispose();
  });
  test('ambiguous timeout blocks retries across service restart', () async {
    final s=await sale();await repo.auth.initializeAdmin('839201');await repo.auth.login('admin','839201');
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),clientFactory:(env,settings)=>MyInvoisClient(environment:env,credentials:()=>settings.load(environment:env,credentials:true),transport:MockClient((r)async{
      if(r.url.path=='/connect/token')return http.Response('{"access_token":"t","expires_in":3600}',200);
      throw const SocketException('lost response');
    })));
    await service.saveSettings(supplier,'id','secret');await service.prepare(s.id,'sandbox',buyer);
    await expectLater(service.submitPendingInvoice(s.id),throwsA(isA<SocketException>()));
    final restarted=EInvoiceService(repo);await expectLater(restarted.submitPendingInvoice(s.id),throwsStateError);
    expect((await (await database.db).query('e_invoice_documents')).single['status'],'needs_review');service.dispose();restarted.dispose();
  });
}
