import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/pos_repository.dart';
import '../../services/purchase_attachment_store.dart';
import '../../theme/cnkh_theme.dart';
import '../../widgets/money_text.dart';

class PurchaseDetailPage extends StatefulWidget {
  const PurchaseDetailPage({
    super.key,
    required this.repo,
    required this.purchaseId,
  });

  final PosRepository repo;
  final String purchaseId;

  @override
  State<PurchaseDetailPage> createState() => _PurchaseDetailPageState();
}

class _PurchaseDetailPageState extends State<PurchaseDetailPage> {
  Map<String, Object?>? _purchase;
  List<PurchaseAttachmentInfo> _attachments = const [];
  bool _loading = true;
  bool _exporting = false;

  PurchaseAttachmentStore get _store =>
      PurchaseAttachmentStore(database: widget.repo.database);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await widget.repo.database.db;
    final rows = await db.query(
      'purchases',
      where: 'id=?',
      whereArgs: [widget.purchaseId],
      limit: 1,
    );
    final attachments = await _store.listForPurchase(widget.purchaseId);
    if (!mounted) return;
    setState(() {
      _purchase = rows.isEmpty ? null : rows.first;
      _attachments = attachments;
      _loading = false;
    });
  }

  Future<void> _export(PurchaseAttachmentInfo attachment) async {
    if (_exporting) return;
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择原始进货单导出文件夹',
    );
    if (!mounted) return;
    if (dir == null || dir.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消导出 / Export cancelled')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final file = await _store.exportToDirectory(
        attachment.id,
        Directory(dir),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('原始单据已导出：${file.path}'),
          action: SnackBarAction(
            label: '打开文件夹',
            onPressed: () => _openFolder(file.parent.path),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('附件导出失败：$e'),
          backgroundColor: CnkhColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', <String>[path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>[path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', <String>[path]);
      }
    } catch (_) {}
  }

  Widget _field(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(
                label,
                style: const TextStyle(
                  color: CnkhColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(child: SelectableText(value?.toString() ?? '')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final purchase = _purchase;
    return Scaffold(
      appBar: AppBar(title: const Text('进货详情 / Purchase Detail')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : purchase == null
              ? const Center(child: Text('进货记录不存在'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${purchase['purchase_no']} · ${purchase['supplier_name']}',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                MoneyText(
                                  amountCents:
                                      (purchase['total_cents'] as num).toInt(),
                                  fontSize: 18,
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            _field('时间 / Purchased at', purchase['purchased_at']),
                            _field('Invoice No', purchase['invoice_no']),
                            _field('Invoice Date', purchase['invoice_date']),
                            _field('来源 / Source', purchase['source']),
                            _field(
                              '状态 / Status',
                              purchase['reversed'] == 1 ? 'REVERSED' : 'COMMITTED',
                            ),
                            _field('备注 / Notes', purchase['notes']),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '原始单据 / Invoice Evidence',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '附件导出前会重新校验 SHA-256。校验失败时不会写出损坏文件。',
                              style: TextStyle(
                                color: CnkhColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_attachments.isEmpty)
                              const Text('此进货单没有已同步的 Original Invoice 附件。')
                            else
                              for (final attachment in _attachments)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.attach_file),
                                  title: Text(
                                    attachment.filename.isEmpty
                                        ? attachment.kind
                                        : attachment.filename,
                                  ),
                                  subtitle: Text(
                                    '${attachment.kind}\nSHA-256 ${attachment.contentHash}',
                                  ),
                                  isThreeLine: true,
                                  trailing: FilledButton.icon(
                                    onPressed: _exporting
                                        ? null
                                        : () => _export(attachment),
                                    icon: const Icon(Icons.folder_outlined),
                                    label: const Text('导出'),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OCR Evidence',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              purchase['ocr_raw_text']?.toString().isEmpty == false
                                  ? purchase['ocr_raw_text'].toString()
                                  : '无 OCR 原始文字',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
