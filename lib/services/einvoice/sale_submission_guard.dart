import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../db/app_database.dart';

/// Called inside the same transaction as every POS/LAN sale reversal. A tax
/// claim wins over reversal until its result is known; an earlier reversal
/// wins over a later claim. Never erase a UUID or an uncertain submission.
Future<void> guardAndAuditSaleVoid(DatabaseExecutor txn, String saleId) async {
  final documents = await txn.query('e_invoice_documents',
      where: 'sale_id=?', whereArgs: [saleId]);
  for (final doc in documents) {
    if (['submitting', 'needs_review'].contains(doc['status']) ||
        (doc['status'] == 'pending' &&
            ('${doc['document_uuid'] ?? ''}'.isNotEmpty ||
                '${doc['submission_uid'] ?? ''}'.isNotEmpty))) {
      throw StateError('税务提交处理中或结果未知，请先核对 MyInvois 后再作废；原请求保留');
    }
  }
  for (final doc in documents) {
    await txn.insert('e_invoice_logs', {
      'id': AppDatabase.newId(), 'document_id': doc['id'],
      'action': 'pos_sale_void', 'request_json': '{}',
      'response_json': jsonEncode({'status': doc['status'],
        'document_uuid': doc['document_uuid'],
        'submission_uid': doc['submission_uid']}),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
