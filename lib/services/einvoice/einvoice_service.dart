import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../db/app_database.dart';
import '../../models/app_user.dart';
import '../pos_repository.dart';
import '../sync_store.dart';
import 'einvoice_settings.dart';
import 'invoice_mapper.dart';
import 'einvoice_signer.dart';
import 'myinvois_client.dart';

class EInvoiceService {
  EInvoiceService(this.repo, {this.keyStore, this.clientFactory, EInvoiceSigner? signer, this.documentSigner}) : signer = signer ?? EInvoiceSigner();
  final PosRepository repo;
  final EInvoiceKeyStore? keyStore;
  final MyInvoisClient Function(String environment, EInvoiceSettingsStore settings)? clientFactory;
  final EInvoiceSigner signer;
  /// Test seam for integration tests; production always loads and uses the encrypted certificate.
  final Future<String> Function(String json, String environment, EInvoiceSettingsStore settings)? documentSigner;
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
  Future<void> saveSigningCertificate(String environment, List<int> pfx, String password, String name) async {
    _admin();
    final store = await settings;
    final profile = await store.load(environment: environment);
    await signer.validateCertificate(
      pfx,
      password,
      expectedTin: profile['tin']?.toString(),
      expectedBrn: profile['brn']?.toString(),
    );
    await store.saveSigningCertificate(environment, pfx, password, name);
  }
  Future<void> testConnection(String environment) async {
    _admin();
    final client = await _client(environment);
    client.clearToken(); // An explicit connection test must actually contact the server.
    await client.authenticate();
  }
  Future<List<Map<String, Object?>>> history(String environment, {String receipt = ''}) async {
    final db = await repo.database.db;
    final result = await db.rawQuery('''SELECT s.id AS sale_id, s.receipt_no, s.customer_name, s.customer_phone, s.total_cents, s.voided,
      d.id AS document_id, COALESCE(d.status,'pending') AS status,
      COALESCE(d.error_message,'') AS error_message, COALESCE(d.document_uuid,'') AS document_uuid,
      COALESCE(d.submission_uid,'') AS submission_uid, COALESCE(d.buyer_json,'{}') AS buyer_json,
      COALESCE(d.payload_json,'') AS payload_json, COALESCE(d.invoice_no,s.receipt_no) AS document_invoice_no,
      COALESCE(d.attempt_no,1) AS attempt_no, COALESCE(d.parent_document_id,'') AS parent_document_id,
      s.sold_at AS sort_time
    FROM sales s LEFT JOIN e_invoice_documents d ON d.sale_id=s.id AND d.environment=?
    WHERE (?='' OR instr(s.receipt_no,?)>0)
    UNION ALL
    SELECT d.sale_id,d.invoice_no,'原销售已移除','',0,1,d.id,d.status,d.error_message,
      d.document_uuid,d.submission_uid,d.buyer_json,d.payload_json,d.invoice_no,d.attempt_no,d.parent_document_id,d.updated_at
    FROM e_invoice_documents d WHERE d.environment=? AND NOT EXISTS(SELECT 1 FROM sales s WHERE s.id=d.sale_id)
      AND (?='' OR instr(d.invoice_no,?)>0)
    ORDER BY sort_time DESC,attempt_no DESC LIMIT 500''', [environment,receipt,receipt,environment,receipt,receipt]);
    final latestAttempts = <String, int>{};
    for (final r in result) {
      final saleId = r['sale_id'] as String;
      final attempt = r['attempt_no'] as int;
      if (attempt > (latestAttempts[saleId] ?? 0)) latestAttempts[saleId] = attempt;
    }
    return result.map((r) {
      final row = Map<String,Object?>.from(r);
      row['is_latest_attempt'] = r['attempt_no'] == latestAttempts[r['sale_id']];
      if (r['customer_name']=='原销售已移除' && (r['payload_json'] as String).isNotEmpty) {
        try { final payload=jsonDecode(r['payload_json'] as String);row['total_cents']=((payload['Invoice'][0]['LegalMonetaryTotal'][0]['PayableAmount'][0]['_'] as num)*100).round(); } catch (_) {}
      }
      return row;
    }).toList();
  }
  Future<String> prepare(String saleId, String environment, Map<String, dynamic> buyer) =>
      _lock.run(() => _prepareAttempt(saleId, environment, buyer, correction: false));

  /// Creates a separate document after a submitted UUID becomes Invalid.
  /// The original submission, UUID, payload, and logs stay intact.
  Future<String> prepareCorrection(String saleId, String environment, Map<String, dynamic> buyer) =>
      _lock.run(() => _prepareAttempt(saleId, environment, buyer, correction: true));

  Future<String> _prepareAttempt(String saleId, String environment, Map<String, dynamic> buyer, {required bool correction}) async {
    _admin();
    final db = await repo.database.db;
    final all = await db.query('e_invoice_documents', where: 'sale_id=? AND environment=?',
      whereArgs: [saleId, environment], orderBy: 'attempt_no DESC');
    final previous = all.isEmpty ? null : all.first;
    final previousStatus = previous?['status'] as String?;
    final previousUuid = '${previous?['document_uuid'] ?? ''}';
    var reusePending = false;
    if (correction) {
      if (previous == null || previousStatus != 'invalid' || previousUuid.isEmpty) {
        throw StateError('只有已取得 UUID 且 MyInvois 状态为 Invalid 的记录可生成更正尝试');
      }
    } else if (previous != null) {
      if (previousStatus == 'pending' && previousUuid.isEmpty &&
          '${previous['submission_uid'] ?? ''}'.isEmpty) {
        reusePending = true;
      } else if (previousStatus != 'rejected' || previousUuid.isNotEmpty) {
        throw StateError('此销售已有提交记录，请查询状态；需要更正时使用“生成更正尝试”');
      }
    }
    final sale = (await db.query('sales', where: 'id=?', whereArgs: [saleId])).single;
    final attemptNo = reusePending
        ? previous!['attempt_no'] as int
        : (all.isEmpty ? 1 : all.map((r) => r['attempt_no'] as int).reduce((a, b) => a > b ? a : b) + 1);
    final invoiceNo = correction
        ? _correctionInvoiceNo('${sale['receipt_no']}', attemptNo)
        : (previous?['invoice_no'] as String? ?? '${sale['receipt_no']}');
    final collisions = await db.query('e_invoice_documents', where: 'invoice_no=? AND environment=? AND sale_id<>?',
      whereArgs: [invoiceNo, environment, saleId]);
    if (collisions.isNotEmpty) throw StateError('此发票号码已有税务记录，不能重复使用');
    final issuedAt = DateTime.now();
    final profile = await (await settings).load(environment: environment);
    final unsigned = jsonEncode(InvoiceMapper().mapSale(sale, supplier: profile, buyer: buyer, issuedAt: issuedAt, invoiceNo: invoiceNo));
    final store = await settings;
    final payload = await _sign(unsigned, environment, store, profile);
    EInvoiceSigner.requireSignedInvoice(jsonDecode(payload) as Map<String, dynamic>);
    final envelope = await MyInvoisClient.envelope(invoiceNo, payload);
    final id = reusePending ? previous!['id'] as String : '$environment:$saleId:attempt:$attemptNo';
    await db.transaction((txn) async {
      final latestRows = await txn.query('e_invoice_documents', where: 'sale_id=? AND environment=?',
        whereArgs: [saleId, environment], orderBy: 'attempt_no DESC', limit: 1);
      final latest = latestRows.isEmpty ? null : latestRows.single;
      if (latest?['id'] != previous?['id'] || latest?['status'] != previousStatus ||
          '${latest?['document_uuid'] ?? ''}' != previousUuid) throw StateError('提交状态已变更，请刷新列表');
      final invoiceCollision = await txn.query('e_invoice_documents', where: 'invoice_no=? AND environment=? AND sale_id<>?',
        whereArgs: [invoiceNo, environment, saleId], limit: 1);
      if (invoiceCollision.isNotEmpty) throw StateError('此发票号码已有税务记录，不能重复使用');
      final data = <String, Object?>{
        'id': id, 'sale_id': saleId, 'invoice_no': invoiceNo, 'environment': environment,
        'payload_json': payload, 'payload_hash': (envelope['documents'] as List).single['documentHash'],
        'buyer_json': jsonEncode(buyer), 'status': 'pending', 'error_message': '',
        'submission_uid': '', 'document_uuid': '', 'submitted_at': null, 'long_id': '',
        'updated_at': _now(), 'attempt_no': attemptNo,
        'parent_document_id': reusePending
            ? previous!['parent_document_id'] ?? ''
            : (previous != null ? previous['id'] : ''),
      };
      if (reusePending) {
        await txn.update('e_invoice_documents', data, where: 'id=?', whereArgs: [id]);
      } else {
        await txn.insert('e_invoice_documents', data);
      }
      await _log(txn, id, correction ? 'correction_prepare' : 'prepare', 'pending', details: {
        if (previous != null) 'parent_document_id': previous['id'],
        'invoice_no': invoiceNo, 'attempt_no': attemptNo,
      });
      if (previous != null && !reusePending) {
        await _log(txn, previous['id'] as String, correction ? 'correction_created' : 'retry_created',
          'attempt_$attemptNo', details: {'new_document_id': id, 'invoice_no': invoiceNo});
      }
    });
    return payload;
  }

  static String _correctionInvoiceNo(String receipt, int attemptNo) {
    final suffix = '-C$attemptNo';
    final base = receipt.length > 50 - suffix.length ? receipt.substring(0, 50 - suffix.length) : receipt;
    return '$base$suffix';
  }
  Future<void> submitPendingInvoice(String saleId, {String environment = 'sandbox'}) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final docs = await db.query('e_invoice_documents', where: 'sale_id=? AND environment=?',
      whereArgs: [saleId, environment], orderBy: 'attempt_no DESC', limit: 1);
    if (docs.isEmpty) throw StateError('请先生成发票');
    final doc = docs.single;
    if (doc['status'] != 'pending' || '${doc['payload_json']}'.isEmpty ||
        '${doc['document_uuid'] ?? ''}'.isNotEmpty || '${doc['submission_uid'] ?? ''}'.isNotEmpty) {
      throw StateError('只能提交已生成且未提交的发票；已有 UUID/Submission UID 时请先查询');
    }
    final sale = (await db.query('sales', where: 'id=?', whereArgs: [saleId])).single;
    if (sale['voided'] == 1) throw StateError('销售已作废');
    final payload = jsonDecode(doc['payload_json'] as String) as Map<String, dynamic>;
    final invoice = (payload['Invoice'] as List).single as Map;
    EInvoiceSigner.requireSignedInvoice(payload);
    final date = (invoice['IssueDate'] as List).single['_'];
    if (date != _now().substring(0,10)) throw StateError('发票日期已过期，请重新生成后提交');
    final cfg = await (await settings).load(environment: environment);
    final issuer = invoice['AccountingSupplierParty'][0]['Party'][0]['PartyIdentification'][0]['ID'][0]['_'];
    if (issuer != cfg['tin']) throw StateError('公司 TIN 已变更，请重新生成');
    final client = await _client(environment);
    await client.authenticate(); // Auth failures cannot have submitted the document.
    final id = doc['id'] as String;
    final claimed = await db.transaction((txn) async {
      final changed = await txn.update('e_invoice_documents', {'status': 'submitting', 'error_message': '', 'updated_at': _now()}, where: 'id=? AND status=? AND payload_hash=?', whereArgs: [id, 'pending', doc['payload_hash']]);
      if (changed == 1) {
        await _log(txn, id, 'submit_start', 'submitting', details: {
          'invoice_no': doc['invoice_no'], 'payload_hash': doc['payload_hash'],
        });
      }
      return changed;
    });
    if (claimed != 1) throw StateError('此发票已被另一操作处理，请刷新');
    try {
      final result = await client.submitDocument(await MyInvoisClient.envelope(doc['invoice_no'] as String, doc['payload_json'] as String));
      final accepted = result['acceptedDocuments'] as List? ?? [];
      final matching = accepted.where((r) => r['invoiceCodeNumber'] == doc['invoice_no']).toList();
      final rejected = result['rejectedDocuments'] as List? ?? [];
      final matchingRejected = rejected.where((r) => r['invoiceCodeNumber'] == doc['invoice_no']).toList();
      final values = <String, Object?>{};
      if (matching.length == 1 && matchingRejected.isEmpty && '${matching.single['uuid'] ?? ''}'.isNotEmpty) {
        final uid = result['submissionUID']?.toString() ?? '';
        values.addAll({'status': uid.isEmpty ? 'needs_review' : 'submitted',
          'submission_uid': uid, 'document_uuid': matching.single['uuid'], 'submitted_at': _now(),
          'error_message': uid.isEmpty ? '已返回 UUID 但缺少 Submission UID；请在 Portal 核对，勿重复提交' : '',
        });
      } else {
        final knownRejected = matching.isEmpty && matchingRejected.length == 1;
        final errors = knownRejected
            ? _validationSummary(Map<String, dynamic>.from(matchingRejected.single))
            : '';
        values.addAll({
          'status': knownRejected ? 'rejected' : 'needs_review',
          'submission_uid': result['submissionUID']?.toString() ?? '',
          'error_message': knownRejected
              ? 'MyInvois 拒收：${errors.isEmpty ? '请核对资料后重新生成' : errors}'
              : '提交结果不完整；请在 MyInvois 核对，勿重复提交',
        });
      }
      await db.transaction((txn) async {
        await _update(txn, id, values);
        await _log(txn, id, 'submit', '${values['status']}', details: {
          'submission_uid': result['submissionUID'],
          'accepted': matching, 'rejected': matchingRejected,
        });
      });
    } catch (e) {
      // A timeout / 5xx / duplicate response may follow successful receipt.
      final definite = e is MyInvoisException && [400,401,403,429].contains(e.statusCode);
      await db.transaction((txn) async {
        await _update(txn, id, {'status': definite ? 'pending' : 'needs_review', 'error_message': e is MyInvoisException ? e.toString() : '网络或响应异常，提交结果未知；请先核对 MyInvois'});
        await _log(txn, id, 'submit', definite ? 'not_accepted' : 'unknown_outcome', details: {
          if (e is MyInvoisException) 'http_status': e.statusCode,
        });
      });
      rethrow;
    }
  });
  Future<String> _sign(
    String json,
    String environment,
    EInvoiceSettingsStore store,
    Map<String, dynamic> profile,
  ) async {
    final testSigner = documentSigner;
    if (testSigner != null) return testSigner(json, environment, store);
    final credential = await store.loadSigningCertificate(environment);
    return signer.sign(
      json,
      pfx: base64Decode(credential['pfx'] as String),
      password: credential['password'] as String,
      expectedTin: profile['tin']?.toString(),
      expectedBrn: profile['brn']?.toString(),
    );
  }
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
    if (match.length != 1) {
      await _log(db, id, 'query', 'document_not_found', details: {'submission_uid': uid, 'overall_status': result['overallStatus']});
      throw StateError('MyInvois 尚未返回该发票，请稍后查询');
    }
    await _applyStatus(db, doc, Map<String, dynamic>.from(match.single));
  });
  Future<void> reconcile(String id, String uuid, {String submissionUid = ''}) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final doc = (await db.query('e_invoice_documents', where: 'id=?', whereArgs: [id])).single;
    final storedUuid = '${doc['document_uuid'] ?? ''}';
    final invalid = doc['status'] == 'invalid';
    final unresolved = ['needs_review', 'submitting'].contains(doc['status']) ||
        (doc['status'] == 'pending' &&
          (storedUuid.isNotEmpty || '${doc['submission_uid'] ?? ''}'.isNotEmpty));
    if (!invalid && !unresolved) throw StateError('请使用查询 MyInvois；核对仅用于未知提交结果或 Invalid 验证详情');
    if (uuid.trim().isEmpty) throw StateError('请填写 MyInvois Portal 中的 UUID');
    if (storedUuid.isNotEmpty && storedUuid != uuid.trim()) {
      await _log(db, id, 'query', 'uuid_mismatch', details: {
        'stored_uuid': storedUuid,
        'requested_uuid': uuid.trim(),
      });
      throw StateError('输入 UUID 与原提交记录不符；原记录未变更');
    }
    Map<String, dynamic> result;
    if (invalid) {
      result = await (await _client(doc['environment'] as String)).documentDetails(uuid.trim());
    } else {
      final storedUid = '${doc['submission_uid'] ?? ''}';
      final uid = storedUid.isNotEmpty ? storedUid : submissionUid.trim();
      if (uid.isEmpty) throw StateError('请填写 Portal 中的 Submission UID；结果未知时不能重新提交');
      if (storedUid.isNotEmpty && submissionUid.trim().isNotEmpty && storedUid != submissionUid.trim()) {
        throw StateError('Submission UID 与原提交记录不符');
      }
      // Recover a lost submission response through Get Submission. The
      // Details endpoint is reserved for confirmed Invalid error details.
      final submission = await (await _client(doc['environment'] as String)).queryStatus(uid);
      final matching = (submission['documentSummary'] as List? ?? [])
          .where((r) => r is Map && r['uuid'] == uuid.trim()).toList();
      if (matching.length != 1) {
        await _log(db, id, 'reconcile', 'document_not_found', details: {'requested_uuid': uuid.trim(), 'submission_uid': uid});
        throw StateError('该提交未唯一返回此 UUID；记录仍为待核对，勿重复提交');
      }
      result = Map<String, dynamic>.from(matching.single as Map);
      if (result['submissionUid'] != null && result['submissionUid'] != uid) throw StateError('返回的 Submission UID 不符');
      result['submissionUid'] = uid;
    }
    final payload = jsonDecode(doc['payload_json'] as String);
    final expected = payload['Invoice'][0]['LegalMonetaryTotal'][0]['PayableAmount'][0]['_'];
    final issuer = payload['Invoice'][0]['AccountingSupplierParty'][0]['Party'][0]['PartyIdentification'][0]['ID'][0]['_'];
    if (result['uuid'] != uuid.trim() || result['internalId'] != doc['invoice_no'] ||
        result['issuerTin'] != issuer || result['totalPayableAmount'] != expected) {
      await _log(db, id, 'reconcile', 'identity_mismatch', details: {'requested_uuid': uuid.trim(), ..._statusAudit(result)});
      throw StateError('UUID 的发票号码、TIN 或金额不符；原记录未变更');
    }
    await _applyStatus(db, doc, result);
  });
  Future<void> cancel(String id, String reason) => _lock.run(() async {
    _admin(); final db = await repo.database.db;
    final doc = (await db.query('e_invoice_documents', where: 'id=?', whereArgs: [id])).single;
    if ((doc['document_uuid'] as String).isEmpty) throw StateError('无 MyInvois UUID');
    if (!['submitted','validated'].contains(doc['status'])) throw StateError('只有已接收或验证通过的发票可申请取消；Invalid/Rejected 记录保留原状态');
    final result = await (await _client(doc['environment'] as String)).cancelDocument(doc['document_uuid'] as String, reason);
    if ('${result['status']}'.toLowerCase() != 'cancelled') {
      await _log(db, id, 'cancel', 'unknown_result', details: {'response_status': result['status']});
      throw StateError('MyInvois 尚未确认取消，请查询');
    }
    await db.transaction((txn) async {
      await _update(txn, id, {'status': 'cancelled', 'error_message': reason.trim()});
      await _log(txn, id, 'cancel', 'cancelled');
    });
  });
  Future<void> _applyStatus(Database db, Map<String, Object?> doc, Map<String, dynamic> result) async {
    final rawStatus = '${result['status'] ?? ''}'.toLowerCase();
    final responseUuid = '${result['uuid'] ?? ''}';
    final savedUuid = '${doc['document_uuid'] ?? ''}';
    final status = switch (rawStatus) {
      'submitted' => 'submitted',
      'valid' => 'validated',
      'invalid' => 'invalid',
      'cancelled' => 'cancelled',
      _ => null,
    };
    final documentId = doc['id'] as String;
    if (status == null) {
      await _log(db, documentId, 'query', 'unknown_status', details: _statusAudit(result));
      throw StateError('未知 MyInvois 状态“$rawStatus”；记录未变更，请在 MyInvois 核对后重试');
    }
    if (savedUuid.isNotEmpty && responseUuid.isNotEmpty && savedUuid != responseUuid) {
      await _log(db, documentId, 'query', 'uuid_mismatch', details: {'stored_uuid': savedUuid, 'response_uuid': responseUuid, ..._statusAudit(result)});
      throw StateError('MyInvois 返回的 UUID 与原提交不符；原记录未变更');
    }
    final uuid = savedUuid.isNotEmpty ? savedUuid : responseUuid;
    if (uuid.isEmpty) {
      await _log(db, documentId, 'query', 'missing_uuid', details: _statusAudit(result));
      throw StateError('MyInvois 状态响应缺少 UUID；原记录未变更');
    }
    final summary = status == 'invalid' ? _validationSummary(result) : '';
    final error = status == 'invalid'
        ? (summary.isEmpty ? '验证失败；请核对 MyInvois 返回详情，再生成单独的更正尝试' : '验证失败：$summary')
        : '';
    await db.transaction((txn) async {
      final latest = await txn.query('e_invoice_documents', where: 'id=?', whereArgs: [documentId], limit: 1);
      if (latest.isEmpty || '${latest.single['document_uuid'] ?? ''}' != savedUuid) throw StateError('本地提交记录已变化，请刷新后核对');
      await _update(txn, documentId, {
        'status': status,
        'document_uuid': uuid,
        'submission_uid': result['submissionUid'] ?? doc['submission_uid'] ?? '',
        'long_id': result['longId'] ?? doc['long_id'] ?? '',
        'error_message': error,
      });
      await _log(txn, documentId, 'query', status, details: _statusAudit(result));
    });
  }
  static Map<String, Object?> _statusAudit(Map<String, dynamic> result) => {
    for (final key in ['status','uuid','submissionUid','longId','validationResults','errors','error'])
      if (result.containsKey(key)) key: result[key],
  };
  static String _validationSummary(Map<String, dynamic> result) {
    final found = <String>{};
    void visit(Object? value) {
      if (value is Map) {
        final message = value['message'] ?? value['Message'] ?? value['errorMessage'] ?? value['ErrorMessage'];
        if (message is String && message.trim().isNotEmpty) {
          final code = value['code'] ?? value['Code'] ?? value['errorCode'] ?? value['ErrorCode'];
          found.add('${code == null || '$code'.isEmpty ? '' : '$code: '}${message.trim()}');
        } else {
          for (final child in value.values) { visit(child); }
        }
      } else if (value is List) {
        for (final child in value) { visit(child); }
      }
    }
    visit(result['validationResults'] ?? result['errors'] ?? result['error']);
    return found.take(3).join('；');
  }
  static String _now() => DateTime.now().toUtc().toIso8601String();
  Future<void> _update(DatabaseExecutor db, String id, Map<String, Object?> values) => db.update('e_invoice_documents', {...values, 'updated_at': _now()}, where: 'id=?', whereArgs: [id]).then((_) {});
  Future<void> _log(DatabaseExecutor db, String id, String action, String status, {Map<String, Object?> details = const {}}) => db.insert('e_invoice_logs', {'id': AppDatabase.newId(), 'document_id': id, 'action': action, 'response_json': jsonEncode({'status': status, ...details}), 'created_at': _now()}).then((_) {});
  void dispose() { for (final client in _clients.values) { client.close(); } }
}
