import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../db/app_database.dart';
import '../../models/app_user.dart';
import '../pos_repository.dart';
import '../sync_store.dart';
import 'einvoice_settings.dart';
import 'invoice_mapper.dart';
import 'myinvois_client.dart';

class EInvoiceService {
  EInvoiceService(this.repo, {this.keyStore, this.clientFactory});
  final PosRepository repo;
  final EInvoiceKeyStore? keyStore;
  final MyInvoisClient Function(String environment, EInvoiceSettingsStore settings)? clientFactory;
  static final _lock = AsyncMutex();
  final _clients = <String, MyInvoisClient>{};
  final _lastQuery = <String, DateTime>{};
  Future<EInvoiceSettingsStore> get settings async => EInvoiceSettingsStore(await repo.database.db, keys: keyStore);
  void _admin() {
    if (repo.auth.currentUser?.role != AppRole.admin) throw StateError('仅已登录管理员可操作 e-Invoice');
  }
  Future<void> initialize() async { await repo.database.db; }
  Future<MyInvoisClient> _client(String environment) async {
    final store = await settings;
    return _clients.putIfAbsent(environment, () => clientFactory?.call(environment, store) ?? MyInvoisClient(environment: environment, credentials: () => store.load(environment: environment, credentials: true)));
  }
  Future<void> saveSettings(Map<String, dynamic> profile, String id, String secret) async {
    _admin();
    await (await settings).save(profile, clientId: id, clientSecret: secret);
    _clients.remove(profile['environment'])?.close();
  }
  Future<void> testConnection(String environment) async { _admin(); await (await _client(environment)).authenticate(); }
  Future<List<Map<String, Object?>>> history(String environment) async => (await repo.database.db).rawQuery('''
    SELECT s.id AS sale_id, s.receipt_no, s.customer_name, s.customer_phone, s.total_cents, s.voided,
      d.id AS document_id, COALESCE(d.status,'pending') AS status,
      COALESCE(d.error_message,'') AS error_message, COALESCE(d.document_uuid,'') AS document_uuid,
      COALESCE(d.submission_uid,'') AS submission_uid, COALESCE(d.buyer_json,'{}') AS buyer_json
    FROM sales s LEFT JOIN e_invoice_documents d ON d.sale_id=s.id AND d.environment=?
    ORDER BY s.sold_at DESC LIMIT 500''', [environment]);
  Future<String> prepare(String saleId, String environment, Map<String, dynamic> buyer) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final previous = await db.query('e_invoice_documents', where: 'sale_id=? AND environment=?', whereArgs: [saleId, environment]);
    if (previous.any((r) => !['pending','rejected'].contains(r['status']) || '${r['document_uuid']}'.isNotEmpty)) throw StateError('此销售已有提交记录，请查询或取消，不能重复生成');
    final sale = (await db.query('sales', where: 'id=?', whereArgs: [saleId])).single;
    final profile = await (await settings).load(environment: environment);
    final payload = jsonEncode(InvoiceMapper().mapSale(sale, supplier: profile, buyer: buyer, issuedAt: DateTime.now()));
    final envelope = await MyInvoisClient.envelope(sale['receipt_no'] as String, payload);
    final id = previous.isEmpty ? '$environment:$saleId' : previous.single['id'] as String;
    await db.insert('e_invoice_documents', {
      'id': id, 'sale_id': saleId, 'invoice_no': sale['receipt_no'], 'environment': environment,
      'payload_json': payload, 'payload_hash': (envelope['documents'] as List).single['documentHash'],
      'buyer_json': jsonEncode(buyer), 'status': 'pending', 'updated_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return payload;
  });
  Future<void> submitPendingInvoice(String saleId, {String environment = 'sandbox'}) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final doc = (await db.query('e_invoice_documents', where: 'sale_id=? AND environment=?', whereArgs: [saleId, environment])).single;
    if (doc['status'] != 'pending' || '${doc['payload_json']}'.isEmpty) throw StateError('只能提交已生成且未提交的发票');
    final sale = (await db.query('sales', where: 'id=?', whereArgs: [saleId])).single;
    if (sale['voided'] == 1) throw StateError('销售已作废');
    final payload = jsonDecode(doc['payload_json'] as String) as Map<String, dynamic>;
    final invoice = (payload['Invoice'] as List).single as Map;
    final date = (invoice['IssueDate'] as List).single['_'];
    if (date != _now().substring(0,10)) throw StateError('发票日期已过期，请重新生成后提交');
    final cfg = await (await settings).load(environment: environment);
    final issuer = invoice['AccountingSupplierParty'][0]['Party'][0]['PartyIdentification'][0]['ID'][0]['_'];
    if (issuer != cfg['tin']) throw StateError('公司 TIN 已变更，请重新生成');
    final client = await _client(environment);
    await client.authenticate(); // Auth failures cannot have submitted the document.
    final id = doc['id'] as String;
    await _update(db, id, {'status': 'submitting', 'error_message': ''});
    try {
      final result = await client.submitDocument(await MyInvoisClient.envelope(doc['invoice_no'] as String, doc['payload_json'] as String));
      final accepted = result['acceptedDocuments'] as List? ?? [];
      final matching = accepted.where((r) => r['invoiceCodeNumber'] == doc['invoice_no']).toList();
      if (matching.length == 1 && '${matching.single['uuid'] ?? ''}'.isNotEmpty && '${result['submissionUID'] ?? ''}'.isNotEmpty) {
        await _update(db, id, {'status': 'submitted', 'submission_uid': result['submissionUID'], 'document_uuid': matching.single['uuid'], 'submitted_at': _now()});
      } else {
        final rejected = result['rejectedDocuments'] as List? ?? [];
        final knownRejected = rejected.any((r) => r['invoiceCodeNumber'] == doc['invoice_no']);
        await _update(db, id, {'status': knownRejected ? 'rejected' : 'needs_review', 'error_message': knownRejected ? 'MyInvois 拒收：请核对资料后重新生成' : '提交结果不完整；请在 MyInvois 核对，勿重复提交'});
      }
      await _log(db, id, 'submit', 'response_received');
    } catch (e) {
      // A timeout / 5xx / duplicate response may follow successful receipt.
      final definite = e is MyInvoisException && [400,401,403,429].contains(e.statusCode);
      await _update(db, id, {'status': definite ? 'pending' : 'needs_review', 'error_message': e is MyInvoisException ? e.toString() : '网络或响应异常，提交结果未知；请先核对 MyInvois'});
      await _log(db, id, 'submit', definite ? 'not_accepted' : 'unknown_outcome');
      rethrow;
    }
  });
  Future<void> refresh(String id) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final doc = (await db.query('e_invoice_documents', where: 'id=?', whereArgs: [id])).single;
    final uid = doc['submission_uid'] as String;
    if (uid.isEmpty) throw StateError('无 Submission UID；请用 MyInvois 中的 UUID 核对');
    final last = _lastQuery[id];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 5)) return;
    _lastQuery[id] = DateTime.now();
    final result = await (await _client(doc['environment'] as String)).queryStatus(uid);
    final rows = result['documentSummary'] as List? ?? [];
    final match = rows.where((r) => r['uuid'] == doc['document_uuid']).toList();
    if (match.length != 1) throw StateError('MyInvois 尚未返回该发票，请稍后查询');
    await _applyStatus(db, doc, Map<String, dynamic>.from(match.single));
  });
  Future<void> reconcile(String id, String uuid) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final doc = (await db.query('e_invoice_documents', where: 'id=?', whereArgs: [id])).single;
    final result = await (await _client(doc['environment'] as String)).documentDetails(uuid.trim());
    final cfg = await (await settings).load(environment: doc['environment'] as String);
    final payload = jsonDecode(doc['payload_json'] as String);
    final expected = payload['Invoice'][0]['LegalMonetaryTotal'][0]['PayableAmount'][0]['_'];
    if (result['internalId'] != doc['invoice_no'] || result['issuerTin'] != cfg['tin'] || result['totalPayableAmount'] != expected) throw StateError('UUID 的发票号码、TIN 或金额不符');
    await _applyStatus(db, doc, result);
  });
  Future<void> cancel(String id, String reason) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final doc = (await db.query('e_invoice_documents', where: 'id=?', whereArgs: [id])).single;
    if ((doc['document_uuid'] as String).isEmpty) throw StateError('无 MyInvois UUID');
    final result = await (await _client(doc['environment'] as String)).cancelDocument(doc['document_uuid'] as String, reason);
    if ('${result['status']}'.toLowerCase() != 'cancelled') throw StateError('MyInvois 尚未确认取消，请查询');
    await _update(db, id, {'status': 'cancelled', 'error_message': reason.trim()});
    await _log(db, id, 'cancel', 'cancelled');
  });
  Future<void> _applyStatus(Database db, Map<String, Object?> doc, Map<String, dynamic> result) async {
    final status = {'submitted': 'submitted', 'valid': 'validated', 'invalid': 'rejected', 'cancelled': 'cancelled'}['${result['status']}'.toLowerCase()];
    if (status == null) throw StateError('未知 MyInvois 状态');
    await _update(db, doc['id'] as String, {'status': status, 'document_uuid': result['uuid'], 'submission_uid': result['submissionUid'] ?? doc['submission_uid'], 'long_id': result['longId'] ?? '', 'error_message': status == 'rejected' ? '验证不通过，请查看 MyInvois 详细验证结果' : ''});
    await _log(db, doc['id'] as String, 'query', status);
  }
  static String _now() => DateTime.now().toUtc().toIso8601String();
  Future<void> _update(Database db, String id, Map<String, Object?> values) => db.update('e_invoice_documents', {...values, 'updated_at': _now()}, where: 'id=?', whereArgs: [id]).then((_) {});
  Future<void> _log(Database db, String id, String action, String status) => db.insert('e_invoice_logs', {'id': AppDatabase.newId(), 'document_id': id, 'action': action, 'response_json': jsonEncode({'status': status}), 'created_at': _now()}).then((_) {});
  void dispose() { for (final client in _clients.values) { client.close(); } }
}
