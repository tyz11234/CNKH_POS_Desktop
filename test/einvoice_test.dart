import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/db/einvoice_schema.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
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
const _testPfxB64 = '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';
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

  for (final viaLan in [false, true]) {
    test('F03 ${viaLan ? 'LAN' : 'local'} void during OAuth prevents all tax submission', () async {
      final s = await sale();
      await repo.auth.initializeAdmin('839201'); await repo.auth.login('admin', '839201');
      final authEntered = Completer<void>(); final releaseAuth = Completer<void>();
      var submits = 0;
      final service = EInvoiceService(repo, keyStore: MemoryKeys(), documentSigner: testSign,
        clientFactory: (env, settings) => MyInvoisClient(environment: env,
          credentials: () => settings.load(environment: env, credentials: true),
          transport: MockClient((request) async {
            if (request.url.path == '/connect/token') {
              authEntered.complete(); await releaseAuth.future;
              return http.Response('{"access_token":"fake","expires_in":3600}',200);
            }
            submits++; return http.Response('{}',200);
          })));
      await service.saveSettings(supplier, 'id', 'secret');
      await service.prepare(s.id, 'sandbox', buyer);
      final pending = service.submitPendingInvoice(s.id);
      final assertion = expectLater(pending, throwsStateError);
      await authEntered.future;
      LanPairingHost? host;
      try {
        if (viaLan) {
          HttpOverrides.global = null;
          host = LanPairingHost.forTesting(repo, database: database); await host.start();
          final response = await http.post(Uri.parse('http://127.0.0.1:${host.port}/api/v1/mutations'),
            headers: {'Content-Type':'application/json','X-CNKH-Token':await repo.getSetting('lan_host_token')},
            body: jsonEncode({'operations':[{'id':'void-during-oauth','kind':'sale_void',
              'payload':{'client_sale_id':s.id,'receipt_no':s.receiptNo,'note':'cancel'}}]}));
          expect(jsonDecode(response.body)['acknowledged'], ['void-during-oauth']);
        } else { await repo.voidSale(s.id, 'cancel'); }
        releaseAuth.complete(); await assertion;
        expect(submits,0);
        final db = await database.db;
        expect((await db.query('sales',where:'id=?',whereArgs:[s.id])).single['voided'],1);
        final doc = (await db.query('e_invoice_documents')).single;
        expect(doc['status'],'pending'); expect(doc['payload_hash'],isNotEmpty);
        expect(doc['document_uuid'],'');
        expect(await db.query('e_invoice_logs',where:"action='pos_sale_void'"),hasLength(1));
      } finally { if (!releaseAuth.isCompleted) releaseAuth.complete(); await host?.stop(); service.dispose(); }
    });
  }
  test('F03 claim wins over local and LAN void; accepted UUID and duplicate-submit protection survive', () async {
    final s = await sale();
    await repo.auth.initializeAdmin('839201'); await repo.auth.login('admin','839201');
    final entered = Completer<void>(); final release = Completer<void>(); var posts = 0;
    final service = EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign,
      clientFactory:(env,settings)=>MyInvoisClient(environment:env,
        credentials:()=>settings.load(environment:env,credentials:true),transport:MockClient((r) async {
          if (r.url.path=='/connect/token') return http.Response('{"access_token":"fake","expires_in":3600}',200);
          posts++; entered.complete(); await release.future;
          return http.Response(jsonEncode({'submissionUID':'retained-uid','acceptedDocuments':[
            {'invoiceCodeNumber':s.receiptNo,'uuid':'retained-uuid'}]}),202);
        })));
    await service.saveSettings(supplier,'id','secret'); await service.prepare(s.id,'sandbox',buyer);
    final submitting=service.submitPendingInvoice(s.id); await entered.future;
    HttpOverrides.global=null;
    final host=LanPairingHost.forTesting(repo,database:database); await host.start();
    try {
      await expectLater(repo.voidSale(s.id,'late void'),throwsStateError);
      final response=await http.post(Uri.parse('http://127.0.0.1:${host.port}/api/v1/mutations'),
        headers:{'Content-Type':'application/json','X-CNKH-Token':await repo.getSetting('lan_host_token')},
        body:jsonEncode({'operations':[{'id':'late-lan-void','kind':'sale_void','payload':{
          'client_sale_id':s.id,'receipt_no':s.receiptNo,'note':'late void'}}]}));
      expect(jsonDecode(utf8.decode(response.bodyBytes))['acknowledged'],isEmpty);
      release.complete(); await submitting;
      await expectLater(service.submitPendingInvoice(s.id),throwsStateError);
      final db=await database.db; final doc=(await db.query('e_invoice_documents')).single;
      expect(doc['document_uuid'],'retained-uuid'); expect(doc['submission_uid'],'retained-uid');
      expect(doc['status'],'submitted'); expect(posts,1);
      expect((await db.query('sales',where:'id=?',whereArgs:[s.id])).single['voided'],0);
      expect(await db.query('stock_reversals'),isEmpty);
      expect(await db.query('sync_applied_operations',where:'id=?',whereArgs:['late-lan-void']),isEmpty);
      expect(await db.query('e_invoice_logs',where:"action='submit_start'"),hasLength(1));
    } finally { if(!release.isCompleted) release.complete(); await host.stop(); service.dispose(); }
  });
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
    expect(await upgraded.getVersion(),10);
    for(final e in before.entries) { expect(await upgraded.query(e.key),e.value); }
    for(final table in ['e_invoice_logs','e_invoice_documents','e_invoice_settings']) { expect(await upgraded.query(table),isEmpty); }
    await ensureEInvoiceSchema(upgraded);
  });
  test('legacy duplicate e-Invoice rows migrate to ordered immutable attempts', () async {
    final db = await database.db;
    await db.execute('DROP TABLE e_invoice_documents');
    await db.execute('''CREATE TABLE e_invoice_documents (
      id TEXT PRIMARY KEY, sale_id TEXT NOT NULL, invoice_no TEXT NOT NULL,
      submission_uid TEXT NOT NULL DEFAULT '', document_uuid TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending', error_message TEXT NOT NULL DEFAULT '', submitted_at TEXT)''');
    for (final id in ['old-a','old-b']) {
      await db.insert('e_invoice_documents', {'id': id, 'sale_id': 'same-sale', 'invoice_no': 'R-1', 'status': 'rejected'});
    }
    await ensureEInvoiceSchema(db);
    final attempts = await db.query('e_invoice_documents', orderBy: 'attempt_no');
    expect(attempts.map((r) => r['id']), ['old-a','old-b']);
    expect(attempts.map((r) => r['attempt_no']), [1,2]);
    expect(attempts.map((r) => r['parent_document_id']), ['', '']);
    // Updating the first attempt later must not change its number or collide
    // with the unique index when the schema is checked on the next open.
    await db.update('e_invoice_documents', {'updated_at': '2099-01-01'},
      where: 'id=?', whereArgs: ['old-a']);
    await ensureEInvoiceSchema(db);
    expect((await db.query('e_invoice_documents', orderBy: 'attempt_no'))
      .map((r) => r['id']), ['old-a','old-b']);
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
  test('unknown result preserves UUID and audit; Invalid correction appends a new attempt', () async {
    final s=await sale();
    await repo.auth.initializeAdmin('839201');
    await repo.auth.login('admin','839201');
    final db=await database.db;
    var posts=0, detailCalls=0, currentStatus='Processing';
    final keys=MemoryKeys();
    EInvoiceService makeService()=>EInvoiceService(repo,keyStore:keys,documentSigner:testSign,clientFactory:(env,settings)=>MyInvoisClient(
      environment:env,
      credentials:()=>settings.load(environment:env,credentials:true),
      transport:MockClient((r)async{
        if(r.url.path=='/connect/token') return http.Response('{"access_token":"t","expires_in":3600}',200);
        if(r.method=='POST') {
          posts++;
          final request=jsonDecode(r.body) as Map<String,dynamic>;
          final submittedCode=request['documents'][0]['codeNumber'];
          final uid=posts==1?'uuid-original':'uuid-correction';
          return http.Response(jsonEncode({'submissionUID':'submission-$posts','acceptedDocuments':[{'uuid':uid,'invoiceCodeNumber':submittedCode}]}),202);
        }
        if(r.url.path.startsWith('/api/v1.0/documentsubmissions/')) {
          return http.Response(jsonEncode({'documentSummary':[{
            'uuid':'uuid-original','status':currentStatus,
            if(currentStatus=='Invalid') 'validationResults':{'validationSteps':[{'status':'Invalid','error':[{'code':'BuyerTinMismatch','message':'Buyer TIN does not match'}]}]},
          }]}),200);
        }
        if(r.url.path.endsWith('/details')) {
          detailCalls++;
          final status='Invalid';
          return http.Response(jsonEncode({
            'uuid':'uuid-original','status':status,'internalId':s.receiptNo,
            'issuerTin':supplier['tin'],'totalPayableAmount':20.0,
            if(status=='Invalid') 'validationResults':{'validationSteps':[{'status':'Invalid','error':[{'code':'BuyerTinMismatch','message':'Buyer TIN does not match'}]}]},
          }),200);
        }
        return http.Response('{}',500);
      }),
    ));
    final service=makeService();
    await service.saveSettings(supplier,'id','secret');
    await service.prepare(s.id,'sandbox',buyer);
    await service.submitPendingInvoice(s.id);
    final original=(await db.query('e_invoice_documents')).single;
    final originalPayload=original['payload_json'];
    await expectLater(service.refresh(original['id'] as String),throwsStateError);
    var unchanged=(await db.query('e_invoice_documents')).single;
    expect(unchanged['status'],'submitted');
    expect(unchanged['document_uuid'],'uuid-original');
    final unknownAudit=jsonDecode((await db.query('e_invoice_logs',where:'action=?',whereArgs:['query'])).last['response_json'] as String);
    expect(unknownAudit['status'],'unknown_status');
    expect(unknownAudit['remote_status'],'Processing');
    expect(unknownAudit['uuid'],'uuid-original');
    // Previous releases stored MyInvois Invalid as Rejected with a UUID.
    await db.update('e_invoice_documents',{'status':'rejected'},where:'id=?',whereArgs:[original['id']]);
    await expectLater(service.prepare(s.id,'sandbox',buyer),throwsStateError);
    currentStatus='Invalid';
    final retryService=makeService();
    await retryService.refresh(original['id'] as String);
    await retryService.reconcile(original['id'] as String,'uuid-original');
    expect(detailCalls,1);
    final invalid=(await db.query('e_invoice_documents',where:'id=?',whereArgs:[original['id']])).single;
    expect(invalid['status'],'invalid');
    expect(invalid['document_uuid'],'uuid-original');
    expect(invalid['payload_json'],originalPayload);
    expect(invalid['error_message'],contains('Buyer TIN does not match'));
    await expectLater(retryService.prepare(s.id,'sandbox',buyer),throwsStateError);
    await expectLater(retryService.cancel(original['id'] as String,'not allowed'),throwsStateError);
    final correction=jsonDecode(await retryService.prepareCorrection(s.id,'sandbox',buyer)) as Map<String,dynamic>;
    expect(correction['Invoice'][0]['ID'][0]['_'],'${s.receiptNo}-C2');
    final attempts=await db.query('e_invoice_documents',where:'sale_id=?',whereArgs:[s.id],orderBy:'attempt_no');
    expect(attempts,hasLength(2));
    expect(attempts[0]['document_uuid'],'uuid-original');
    expect(attempts[0]['status'],'invalid');
    expect(attempts[1]['attempt_no'],2);
    expect(attempts[1]['parent_document_id'],original['id']);
    expect(attempts[1]['status'],'pending');
    final history=await retryService.history('sandbox');
    expect(history.where((r)=>r['sale_id']==s.id && r['is_latest_attempt']==true)
      .single['document_id'],attempts[1]['id']);
    // Regenerating an unsubmitted correction keeps its invoice number and
    // the link to the original Invalid document.
    final regenerated=jsonDecode(await retryService.prepare(s.id,'sandbox',buyer));
    expect(regenerated['Invoice'][0]['ID'][0]['_'],'${s.receiptNo}-C2');
    expect((await db.query('e_invoice_documents',where:'id=?',whereArgs:[attempts[1]['id']]))
      .single['parent_document_id'],original['id']);
    await retryService.submitPendingInvoice(s.id);
    final submitted=await db.query('e_invoice_documents',where:'id=?',whereArgs:[attempts[1]['id']]);
    expect(submitted.single['status'],'submitted');
    expect(submitted.single['document_uuid'],'uuid-correction');
    expect(await db.query('e_invoice_documents',where:'document_uuid=?',whereArgs:['uuid-original']),hasLength(1));
    expect((await db.query('e_invoice_logs',where:'action=?',whereArgs:['correction_created'])),hasLength(1));
    expect(posts,2);
    service.dispose();
    retryService.dispose();
  });
  test('synchronous MyInvois rejection remains auditable and can be retried without UUID', () async {
    final s=await sale();
    await repo.auth.initializeAdmin('839201');
    await repo.auth.login('admin','839201');
    final db=await database.db;
    var posts=0;
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign,clientFactory:(env,settings)=>MyInvoisClient(
      environment:env,credentials:()=>settings.load(environment:env,credentials:true),transport:MockClient((r)async{
        if(r.url.path=='/connect/token') return http.Response('{"access_token":"t","expires_in":3600}',200);
        if(r.method=='POST') {
          posts++;
          final code=(jsonDecode(r.body) as Map)['documents'][0]['codeNumber'];
          if(posts==1) return http.Response(jsonEncode({'submissionUID':'rejected-submission','rejectedDocuments':[{'invoiceCodeNumber':code,'error':{'code':'InvalidBuyer','message':'Buyer details rejected'}}]}),202);
          return http.Response(jsonEncode({'submissionUID':'accepted-submission','acceptedDocuments':[{'uuid':'accepted-uuid','invoiceCodeNumber':code}]}),202);
        }
        return http.Response('{}',500);
      }),
    ));
    await service.saveSettings(supplier,'id','secret');
    await service.prepare(s.id,'sandbox',buyer);
    await service.submitPendingInvoice(s.id);
    final rejected=(await db.query('e_invoice_documents')).single;
    expect(rejected['status'],'rejected');
    expect(rejected['document_uuid'],'');
    expect(rejected['error_message'],contains('拒收'));
    expect(rejected['submission_uid'],'rejected-submission');
    expect(rejected['error_message'],contains('Buyer details rejected'));
    final submitAudit=await db.query('e_invoice_logs',where:'action=?',whereArgs:['submit']);
    expect(submitAudit.single['response_json'],contains('InvalidBuyer'));
    await service.prepare(s.id,'sandbox',buyer);
    await service.submitPendingInvoice(s.id);
    final attempts=await db.query('e_invoice_documents',where:'sale_id=?',whereArgs:[s.id],orderBy:'attempt_no');
    expect(attempts,hasLength(2));
    expect(attempts[0]['status'],'rejected');
    expect(attempts[0]['document_uuid'],'');
    expect(attempts[1]['status'],'submitted');
    expect(attempts[1]['invoice_no'],s.receiptNo);
    expect(attempts[1]['attempt_no'],2);
    expect((await db.query('e_invoice_logs',where:'action=?',whereArgs:['retry_created'])),hasLength(1));
    expect(posts,2);
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
  test('lost submit response is reconciled via Get Submission without another POST', () async {
    final s=await sale();
    await repo.auth.initializeAdmin('839201');
    await repo.auth.login('admin','839201');
    var posts=0,queries=0;
    var matches=false;
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign,
      clientFactory:(env,settings)=>MyInvoisClient(environment:env,
        credentials:()=>settings.load(environment:env,credentials:true),
        transport:MockClient((r)async {
          if(r.url.path=='/connect/token') return http.Response('{"access_token":"t","expires_in":3600}',200);
          if(r.method=='POST') { posts++; throw const SocketException('ACK lost'); }
          expect(r.url.path,'/api/v1.0/documentsubmissions/portal-uid');
          queries++;
          return http.Response(jsonEncode({'documentSummary':[{
            'uuid':'portal-uuid','submissionUid':'portal-uid','status':'Valid',
            'internalId':matches?s.receiptNo:'OTHER-INVOICE',
            'issuerTin':supplier['tin'],'totalPayableAmount':20.0,
          }]}),200);
        })));
    await service.saveSettings(supplier,'id','secret');
    await service.prepare(s.id,'sandbox',buyer);
    await expectLater(service.submitPendingInvoice(s.id),throwsA(isA<SocketException>()));
    final db=await database.db;
    final doc=(await db.query('e_invoice_documents')).single;
    await expectLater(service.reconcile(doc['id'] as String,'portal-uuid'),throwsStateError);
    expect(queries,0);
    await expectLater(service.reconcile(doc['id'] as String,'portal-uuid',submissionUid:'portal-uid'),throwsStateError);
    expect((await db.query('e_invoice_documents')).single['status'],'needs_review');
    expect((await db.query('e_invoice_documents')).single['document_uuid'],'');
    matches=true;
    await service.reconcile(doc['id'] as String,'portal-uuid',submissionUid:'portal-uid');
    final recovered=(await db.query('e_invoice_documents')).single;
    expect(recovered['status'],'validated');
    expect(recovered['document_uuid'],'portal-uuid');
    expect(recovered['submission_uid'],'portal-uid');
    await expectLater(service.prepare(s.id,'sandbox',buyer),throwsStateError);
    await expectLater(service.submitPendingInvoice(s.id),throwsStateError);
    final audit=await db.query('e_invoice_logs');
    expect(audit.any((r)=>'${r['response_json']}'.contains('unknown_outcome')),true);
    expect(audit.any((r)=>'${r['response_json']}'.contains('identity_mismatch')),true);
    expect(audit.any((r)=>'${r['response_json']}'.contains('validated')),true);
    expect(posts,1);
    expect(queries,2);
    service.dispose();
  });
  test('a synchronously rejected correction retries its own invoice number and retains all attempts', () async {
    final s=await sale();
    await repo.auth.initializeAdmin('839201');
    await repo.auth.login('admin','839201');
    var posts=0;
    final codes=<String>[];
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign,
      clientFactory:(env,settings)=>MyInvoisClient(environment:env,
        credentials:()=>settings.load(environment:env,credentials:true),
        transport:MockClient((r)async {
          if(r.url.path=='/connect/token') return http.Response('{"access_token":"t","expires_in":3600}',200);
          if(r.method=='POST') {
            posts++;
            final code=jsonDecode(r.body)['documents'][0]['codeNumber'] as String;
            codes.add(code);
            if(posts==2) return http.Response(jsonEncode({'submissionUID':'rejected-correction',
              'rejectedDocuments':[{'invoiceCodeNumber':code,'error':{'code':'BuyerError','message':'Correct the buyer'}}]}),202);
            return http.Response(jsonEncode({'submissionUID':'uid-$posts',
              'acceptedDocuments':[{'invoiceCodeNumber':code,'uuid':'uuid-$posts'}]}),202);
          }
          return http.Response('{"documentSummary":[{"uuid":"uuid-1","status":"Invalid"}]}',200);
        })));
    await service.saveSettings(supplier,'id','secret');
    await service.prepare(s.id,'sandbox',buyer);
    await service.submitPendingInvoice(s.id);
    final db=await database.db;
    final original=(await db.query('e_invoice_documents')).single;
    await service.refresh(original['id'] as String);
    await service.prepareCorrection(s.id,'sandbox',buyer);
    await service.submitPendingInvoice(s.id);
    await service.prepare(s.id,'sandbox',{...buyer,'name':'Corrected Buyer'});
    await service.submitPendingInvoice(s.id);
    final attempts=await db.query('e_invoice_documents',orderBy:'attempt_no');
    expect(attempts.map((r)=>r['status']),['invalid','rejected','submitted']);
    expect(attempts[0]['document_uuid'],'uuid-1');
    expect(attempts[0]['payload_json'],original['payload_json']);
    expect(attempts[2]['parent_document_id'],attempts[1]['id']);
    expect(codes,[s.receiptNo,'${s.receiptNo}-C2','${s.receiptNo}-C2']);
    await expectLater(service.prepareCorrection(s.id,'sandbox',buyer),throwsStateError);
    await expectLater(service.submitPendingInvoice(s.id),throwsStateError);
    expect(posts,3);
    service.dispose();
  });
  test('a legacy Pending row with a submission UID must be reconciled without clearing its evidence', () async {
    final s=await sale();
    await repo.auth.initializeAdmin('839201');
    await repo.auth.login('admin','839201');
    var posts=0;
    final service=EInvoiceService(repo,keyStore:MemoryKeys(),documentSigner:testSign,
      clientFactory:(env,settings)=>MyInvoisClient(environment:env,
        credentials:()=>settings.load(environment:env,credentials:true),
        transport:MockClient((request)async {
          if(request.url.path=='/connect/token') return http.Response('{"access_token":"t","expires_in":3600}',200);
          if(request.method=='POST') { posts++; return http.Response('{}',500); }
          expect(request.url.path,'/api/v1.0/documentsubmissions/legacy-submission');
          return http.Response(jsonEncode({'documentSummary':[{
            'uuid':'legacy-uuid','submissionUid':'legacy-submission','status':'Valid',
            'internalId':s.receiptNo,'issuerTin':supplier['tin'],'totalPayableAmount':20.0,
          }]}),200);
        })));
    await service.saveSettings(supplier,'id','secret');
    await service.prepare(s.id,'sandbox',buyer);
    final db=await database.db;
    final original=(await db.query('e_invoice_documents')).single;
    await db.update('e_invoice_documents',{'submission_uid':'legacy-submission'},
      where:'id=?',whereArgs:[original['id']]);
    await expectLater(service.prepare(s.id,'sandbox',buyer),throwsStateError);
    await expectLater(service.submitPendingInvoice(s.id),throwsStateError);
    final preserved=(await db.query('e_invoice_documents')).single;
    expect(preserved['submission_uid'],'legacy-submission');
    expect(preserved['payload_json'],original['payload_json']);
    await service.reconcile(original['id'] as String,'legacy-uuid');
    final recovered=(await db.query('e_invoice_documents')).single;
    expect(recovered['document_uuid'],'legacy-uuid');
    expect(recovered['status'],'validated');
    expect(recovered['payload_json'],original['payload_json']);
    expect(await db.query('e_invoice_documents'),hasLength(1));
    expect(posts,0);
    service.dispose();
  });
}
