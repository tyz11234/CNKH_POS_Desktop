import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../db/ocr_purchase_schema.dart';

class PurchaseAttachmentInfo {
  const PurchaseAttachmentInfo({
    required this.id,
    required this.purchaseId,
    required this.kind,
    required this.filename,
    required this.contentHash,
    required this.createdAt,
  });

  final String id;
  final String purchaseId;
  final String kind;
  final String filename;
  final String contentHash;
  final String createdAt;
}

class PurchaseAttachmentStore {
  PurchaseAttachmentStore({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> _db() async {
    final db = await _database.db;
    await ensureOcrPurchaseSchema(db);
    return db;
  }

  Future<List<PurchaseAttachmentInfo>> listForPurchase(String purchaseId) async {
    final db = await _db();
    final rows = await db.query(
      'purchase_attachments',
      columns: const [
        'id',
        'purchase_id',
        'kind',
        'filename',
        'content_hash',
        'created_at',
      ],
      where: 'purchase_id=?',
      whereArgs: [purchaseId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => PurchaseAttachmentInfo(
            id: row['id']?.toString() ?? '',
            purchaseId: row['purchase_id']?.toString() ?? '',
            kind: row['kind']?.toString() ?? '',
            filename: row['filename']?.toString() ?? '',
            contentHash: row['content_hash']?.toString() ?? '',
            createdAt: row['created_at']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<Uint8List> readVerifiedBytes(String attachmentId) async {
    final db = await _db();
    final rows = await db.query(
      'purchase_attachments',
      where: 'id=?',
      whereArgs: [attachmentId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('附件不存在');
    final row = rows.first;
    final raw = row['content'];
    if (raw is! List<int>) throw StateError('附件内容损坏');
    final bytes = Uint8List.fromList(raw);
    final expected = row['content_hash']?.toString().toLowerCase().trim() ?? '';
    final actual = _hex((await Sha256().hash(bytes)).bytes);
    if (expected.isEmpty || actual != expected) {
      throw StateError('附件完整性校验失败，请重新同步原始单据');
    }
    return bytes;
  }

  Future<File> exportToDirectory(
    String attachmentId,
    Directory directory,
  ) async {
    if (!await directory.exists()) {
      throw FileSystemException('目标文件夹不存在', directory.path);
    }
    final db = await _db();
    final rows = await db.query(
      'purchase_attachments',
      columns: const ['filename'],
      where: 'id=?',
      whereArgs: [attachmentId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('附件不存在');
    final bytes = await readVerifiedBytes(attachmentId);
    final original = rows.first['filename']?.toString().trim() ?? '';
    final safeName = _safeFilename(original.isEmpty ? '$attachmentId.bin' : original);
    var target = File(p.join(directory.path, safeName));
    if (await target.exists()) {
      final stem = p.basenameWithoutExtension(safeName);
      final ext = p.extension(safeName);
      var n = 2;
      do {
        target = File(p.join(directory.path, '$stem ($n)$ext'));
        n++;
      } while (await target.exists());
    }
    await target.writeAsBytes(bytes, flush: true);
    return target;
  }

  String _safeFilename(String input) {
    var name = input.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    while (name.endsWith('.') || name.endsWith(' ')) {
      name = name.substring(0, name.length - 1);
    }
    if (name.isEmpty) name = 'invoice_original.bin';
    return name;
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
