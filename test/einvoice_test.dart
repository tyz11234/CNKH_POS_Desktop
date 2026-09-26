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
import 'package:cnkh_pos_desktop/services/einvoice/einvoice_signer.dart';
import 'package:cnkh_pos_desktop/services/einvoice/invoice_mapper.dart';
import 'package:cnkh_pos_desktop/services/einvoice/myinvois_client.dart';

class MemoryKeys implements EInvoiceKeyStore {
  String? value;
  @override Future<String?> read() async => value;
  @override Future<void> write(String v) async { value = v; }
}
const _testPfxB64 = 'MIIKnwIBAzCCClUGCSqGSIb3DQEHAaCCCkYEggpCMIIKPjCCBLIGCSqGSIb3DQEHBqCCBKMwggSfAgEAMIIEmAYJKoZIhvcNAQcBMFcGCSqGSIb3DQEFDTBKMCkGCSqGSIb3DQEFDDAcBAiQU6+AlV/JywICCAAwDAYIKoZIhvcNAgkFADAdBglghkgBZQMEASoEEH4mECokZ+jZ50S20mD2SDqAggQwsjv2HUsXAPFgM+JRWk6QKSdMq3MD7fpi0JMA41VU8zHcsHTXfx6nnPVNNMnh4xeieHnYBzIHDuIbMDsq5x1yMH5SvulAZz5rr+Y+RoeaB/qe7K3e8uPGP4lGnuAVXADF15iUEMPhaVtdUSUuOe/gvzrqQxKAo+0s0JvpNyF9lj9dfp8cq86EKuOYpmRd0RoxSArUEhzZt4UXcyEx7pF3OOvMvKgu0Rc7JwYVV0Nw4EQ/lhKOlz+sQBv/4S5g+3ZGqdvTD2gAgFbEFI/VFB7bBZCuF3D1GdRo/ThUCMbks+5g/Stx01EEakkj/IlmqtF1bqrnx9HEHhy8kta+RposV8OAunP7RrAsbRNiOgpp6P21RJ2L/UJOq55nF/SJJziQ8ZU/eWUPffGYj2olo/DTbVhAWbTf+MptX0LjcS/hAgG8iJimVj3OWQDwfSUy1gBaZ3c1OnYmYof+//UbQ9js6LUywZAnHDtp7/yBNmMhs6Qb9mgwXMXq0S085GEfFaAtXNkKebFLAJ4Ox7Ogc2hEZ3gtbUC4aT/xP9HkRo63IhEA1kcNvdXSFvJrkCtXi1dA4yLNDUYldQ7gRbBXlSRsJbwXb4PTzoZIE5Xhoe13daORQwSPx7B6G5qrVgqaPofnLYmWx2Kqrg4zyS+olR7moLkFtnhs/DkdHpOVu8465lE8AeEh71uWZsrX1+qvonxRCdSJBdjx9shQmTVxBPfvr5TZd7UlPRNtVxHkEkJxh/16bGE2gUhDnAIfcotfYb1p/6D+W3I6AyGIdzHn7/zS3ljI/TnX5MNJi23srW28MrTQ0J5yeyLyQe3zDL0TqqfMh3Qip5iEAWfONvUYcLu6wcKjaeg/OcfBnIR+eIQ7q1hoWgyW5L61KczUzD1nzBoVkAcnQ6vkMxr6AAQi4hzGB5SQD/IdSATGZFAeJTbKjiLQFCAe+jolOCCqSzA9+DpS8kpMmGE0mhqygfGLsMtsiPZ/LI7OrTlyI+wtZMZlbikf80sMm8OuchUKOQqr4TceElALOqWR/IIEywdB5vyDdGT4QzmPSCyiRcDzjLbw0t3pnra3jgOCXltIP//rsAWmBp9wiizFOhZlFU2ucoTe3uvWK1oRvow97MajIqQtuEvmoHAo6vjaX0z4c3F9SwqGyeCtVugX4TWYTlzEeLA5SrwEKNRylZ+7MZhuBXGdwP9GzG6X0X8i5GRFY+SCrioRkNTCmuYcrsaODUWQHzRYNOHym7GyvI1Isg8vjYR8h+PGPboUGkVKjWV6UVkppchq668GPhsaFKBXujST25O9nH0ljAC507FoR6dK3UzUrob+aiTlyZUIYLJwboVE6gXOS+zl3GEV97N+nIkgF6kJHY7k/tdZoiPPaosc7HFPZfFfI7wYWbci2lzuMu/6KotVszefz/IkBu2yo6UcKa7KJjCCBYQGCSqGSIb3DQEHAaCCBXUEggVxMIIFbTCCBWkGCyqGSIb3DQEMCgECoIIFMTCCBS0wVwYJKoZIhvcNAQUNMEowKQYJKoZIhvcNAQUMMBwECAOnyOOoARGTAgIIADAMBggqhkiG9w0CCQUAMB0GCWCGSAFlAwQBKgQQeQfU4zPS0h1AFqOCaufUXwSCBNDBeT1DNzLdBt1/ICY7YLUPQS1E0OkD5WKik5RBvbMNUWquR1XeCL5g3wB1abaFT4jYDAVMt8XQzrEqDEXKZl9qv08IM6pU6X4N+bOpcaa5Lhp4MXflx45nwkLSiBC/Jf3sWxQlcZ0BlWYvIq0zxizVZzgEymM0eDWKDSc1t+Xe073kwaKwPK/tnTtwPES7xgDwk0T/NbIsAxTepBwYtqljbSJmbLkaHSchKfLnQPFVWexZG5nJ751OXAmWPqKcU4Uy4YQ0NX2EwatB6LJVGPpKZEQccRj1nQay/Tm+2k/3+aW5vC7nroBtoD+ixNypAQTi+fxTLbaLvgkmiyMH6rGw1JUl+ARo6yUZ26xA37++dAr40XiNJW1ZF4w6GUe8pUJjGsQQOUVZM1FH6+zN43E8ZNxVDReCJ2v4IqaDJaheBqTndDpB9HjIVU4piU/K7YyrIAXbaaM2Mbjnx686TxVINDTlJnelOeqfLc+nrPcbehS5a5fainh2gnNkk6Nv0D/qx7CfLjQMj0uMAIfJrJBF7g8gJRef+gHoItbYf72KDRo2NgfJs4lMpngw9ZVI3Od20taqB5V+dEg6RYwyjouFSnPeZHaCxum7VFfi1Kj405X3isBvOotjvBWOfIE7GQyXPy80SRHG+dfzwfWzq/O4tZqtvBLBvHjLQb+OhvKOotAYTQF1w26dhl0F961KiMawcgHisIDt7L9t17cKm/+fVP9HEQpZbVC/2RZcuj85eE61SeGWtfG3sz+iqd96RcgeLiyooSHcP77vt3K3wYLwaLGZm4jGZ5prnIMH7CpOicRRKZh3fL22YYAojeDnMuLDVsSoRxiOsPQ9+wyJ3DKZl7e6NHRw2+02GiwxpFiGahkhV8ahB4OnqovRTrLUeZwd5wEwOt0mLNF12/+YZSfAsHRgmGWe2NmMOv3DKGN0xJ/Cy1PMAccn1uJWUPPNyqm7uFaT1fY9UqAaBzYLFL6RSYO2V5CEBpaoC/xAgrP4hvlfBusSc0EJ52S/SKuFkJKD+LIlgTGdpSYTwq5J8TDxfUzG80rzTnJfDeWpv34kCJAciiEiPJzQTrfclZQGYaenUf0kQdvWnwD14K95xaS7k+WiQCIxAERT604r/0DQHqh/QzPqad2UwyBh8yDk2DyiDABlW7T7pSnA2cIKkmdo5P7gyCIk4gSoYkOetVm70XZkouk3ulyXt768+kCTm+88Y1GXAQ7uKlENbrcXDquGQobxNm4b18e4aQIUCq49DOCmNpMpPmebNhlt0PKU4uB1nlPBfKfsMfi908BXaNQWoZYwPa86DDPXEA8bYb730e6fOzzVQW+cLk9m14Btcw2Co9JJvn2tL5am27Fj5Sm58Ro3K3uSw1iVPBYF21kB8ECWlqEaaBnP6Bjb3UvCJ+0IDZxECzjDbgftAzxyvGa4W/2JSyZSmb3GrXWuvcdNfzzZx+wj1GIEaa0ht6N9aaxht35yRKdDqgEVOdniYNl//ceP+7lqwGE7t2e+KqNdEUx5CPt4Idg7l5A+hzeGspiDP8jpaGQBUNnnd6IqMwF34PbeosN96ledameBgh11Rk6PGuKANLZE6zMKY3bk/nBbz+kYfXUZb0mXfFkqXfriM8YUvxn1Db4BImZgRg/3DzElMCMGCSqGSIb3DQEJFTEWBBQ0OyJ9VKrxFtvNGkW3aelmV3GOlzBBMDEwDQYJYIZIAWUDBAIBBQAEIKiPVejuHy6eV3WVlPqZy1EYtfeNxfuEQgt2a2KObHqKBAiC76dDNxrNYgICCAA=';
const _testPfxPassword = 'cnkh-test-only';
Future<String> testSign(
  String json,
  String environment,
  EInvoiceSettingsStore settings,
) =>
    EInvoiceSigner().sign(
      json,
      pfx: base64Decode(_testPfxB64),
      password: _testPfxPassword,
      expectedTin: 'C1234567890',
      expectedBrn: '202001234567',
    );
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
  test('PFX profile is checked and generated signature is mathematically valid', () async {
    final signer = EInvoiceSigner();
    final pfx = base64Decode(_testPfxB64);
    await signer.validateCertificate(
      pfx,
      _testPfxPassword,
      expectedTin: 'C1234567890',
      expectedBrn: '202001234567',
    );
    await expectLater(
      signer.validateCertificate(
        pfx,
        _testPfxPassword,
        expectedTin: 'C0000000000',
        expectedBrn: '202001234567',
      ),
      throwsStateError,
    );

    final signed = await signer.sign(
      '{"Invoice":[{"InvoiceTypeCode":[{"_":"01","listVersionID":"1.0"}],"ID":[{"_":"TEST-1"}]}]}',
      pfx: pfx,
      password: _testPfxPassword,
      expectedTin: 'C1234567890',
      expectedBrn: '202001234567',
    );
    final payload = jsonDecode(signed) as Map<String, dynamic>;
    expect(() => EInvoiceSigner.requireSignedInvoice(payload), returnsNormally);
    ((payload['Invoice'] as List).single as Map)['ID'][0]['_'] = 'TAMPERED';
    expect(
      () => EInvoiceSigner.requireSignedInvoice(payload),
      throwsStateError,
    );
  });

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
  test('certificate storage is encrypted and survives ordinary profile saves', () async {
    final db = await database.db; final store = EInvoiceSettingsStore(db,keys:MemoryKeys());
    await store.save(supplier,clientId:'client',clientSecret:'secret');
    await store.saveSigningCertificate('sandbox',[1,2,3,4],'pfx-password','signing.p12');
    final cipher = (await db.query('e_invoice_settings')).single['signing_certificate_cipher'];
    await store.save({...supplier,'name':'Updated'},clientId:'client',clientSecret:'secret');
    final row = (await db.query('e_invoice_settings')).single;
    expect(row['signing_certificate_cipher'],cipher);
    expect(jsonEncode(row),isNot(contains('pfx-password')));
    expect(row['signing_certificate_name'],'signing.p12');
  });
  test('certificate name survives a new settings store and matches saved environment state', () async {
    final db = await database.db;
    final keys = MemoryKeys();
    final first = EInvoiceSettingsStore(db, keys: keys);
    await first.saveSigningCertificate('sandbox', [1, 2, 3, 4], 'pfx-password', 'signing.p12');

    final reopened = EInvoiceSettingsStore(db, keys: keys);
    expect(await reopened.signingCertificateName('sandbox'), 'signing.p12');
    expect(await reopened.signingCertificateName('production'), isNull);
    expect(await reopened.loadSigningCertificate('sandbox'), {
      'pfx': base64Encode([1, 2, 3, 4]),
      'password': 'pfx-password',
    });
  });
  test('unsigned invoice cannot be prepared for submission without a certificate', () async {
    final s=await sale();await repo.auth.initializeAdmin('839201');await repo.auth.login('admin','839201');
    final service=EInvoiceService(repo,keyStore:MemoryKeys());
    await service.saveSettings(supplier,'id','secret');
    await expectLater(service.prepare(s.id,'sandbox',buyer),throwsStateError);
    expect(await (await database.db).query('e_invoice_documents'),isEmpty);
    service.dispose();
  });
  test('legacy unsigned pending invoices are blocked at submit time', () async {
    final s=await sale();await repo.auth.initializeAdmin('839201');await repo.auth.login('admin','839201');
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign);
    await service.saveSettings(supplier,'id','secret');
    await service.prepare(s.id,'sandbox',buyer);
    final db=await database.db;final doc=(await db.query('e_invoice_documents')).single;
    final payload=jsonDecode(doc['payload_json'] as String) as Map<String,dynamic>;
    final invoice=(payload['Invoice'] as List).single as Map<String,dynamic>;
    invoice.remove('Signature');invoice.remove('UBLExtensions');
    invoice['InvoiceTypeCode'][0]['listVersionID']='1.0';
    await db.update('e_invoice_documents',{'payload_json':jsonEncode(payload)},where:'id=?',whereArgs:[doc['id']]);
    await expectLater(service.submitPendingInvoice(s.id),throwsStateError);
    service.dispose();
  });
  test('legacy scaffold retains identity and logs but removes plaintext credentials', () async {
    final db = await database.db;
    await db.insert('e_invoice_settings', {'id':'legacy','tin':'C1234567890','brn':'202001234567','client_id':'legacy-id','client_secret':'legacy-password'});
    await db.execute('DROP TABLE e_invoice_logs');
    await db.execute("CREATE TABLE e_invoice_logs (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, action TEXT NOT NULL, request_body TEXT NOT NULL DEFAULT '', response_body TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)");
    await db.insert('e_invoice_logs', {'id':'old-log','document_id':'old-doc','action':'test','request_body':'retained','created_at':'2026-09-13'});
    await ensureEInvoiceSchema(db);
    final profile = await EInvoiceSettingsStore(db,keys:MemoryKeys()).load();
    expect(profile['tin'],'C1234567890');
    expect(profile['brn'],'202001234567');
    expect((await db.query('e_invoice_settings')).single['client_secret'],'');
    expect((await db.query('e_invoice_logs')).single['request_body'],'retained');
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
  test('Retry-After is respected and credentials are never sent through redirects', () async {
    var now=DateTime.utc(2026,9,14),calls=0;
    final c=MyInvoisClient(environment:'sandbox',now:()=>now,credentials:()async=>{'client_id':'id','client_secret':'secret'},transport:MockClient((r)async{
      expect(r.followRedirects,false);
      if(r.url.path=='/connect/token')return http.Response('{"access_token":"t","expires_in":3600}',200);
      calls++;
      return calls==1 ? http.Response('{}',429,headers:{'retry-after':'30'}) : http.Response('{"documentSummary":[]}',200);
    }));
    await expectLater(c.queryStatus('uid'),throwsA(isA<MyInvoisException>()));
    await expectLater(c.queryStatus('uid'),throwsStateError);expect(calls,1);
    now=now.add(const Duration(seconds:31));await c.queryStatus('uid');expect(calls,2);c.close();
  });
  test('durable duplicate guard, status query and cancellation leave sale intact', () async {
    final s=await sale();await repo.auth.initializeAdmin('839201');await repo.auth.login('admin','839201');
    final db=await database.db;final original=await db.query('sales');var posts=0;
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign,clientFactory:(env,settings)=>MyInvoisClient(environment:env,credentials:()=>settings.load(environment:env,credentials:true),transport:MockClient((r)async{
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
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign,clientFactory:(env,settings)=>MyInvoisClient(environment:env,credentials:()=>settings.load(environment:env,credentials:true),transport:MockClient((r)async{
      if(r.url.path=='/connect/token')return http.Response('{"access_token":"t","expires_in":3600}',200);
      throw const SocketException('lost response');
    })));
    await service.saveSettings(supplier,'id','secret');await service.prepare(s.id,'sandbox',buyer);
    await expectLater(service.submitPendingInvoice(s.id),throwsA(isA<SocketException>()));
    final restarted=EInvoiceService(repo);await expectLater(restarted.submitPendingInvoice(s.id),throwsStateError);
    expect((await (await database.db).query('e_invoice_documents')).single['status'],'needs_review');service.dispose();restarted.dispose();
  });
}
