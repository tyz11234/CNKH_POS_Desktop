import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/desktop_backup.dart';
import '../../services/pos_repository.dart';
import '../../theme/cnkh_theme.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key, required this.repo});

  final PosRepository repo;

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  late final DesktopBackupService _service = DesktopBackupService(
    closeDatabase: widget.repo.database.close,
  );
  bool _busy = false;
  String _lastPath = '';

  String _defaultName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'CNKH_POS_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}.cnkhbackup';
  }

  Future<void> _createBackup() async {
    if (_busy) return;
    var path = await FilePicker.platform.saveFile(
      dialogTitle: '选择 CNKH POS 备份保存位置',
      fileName: _defaultName(),
      type: FileType.custom,
      allowedExtensions: const ['cnkhbackup'],
      lockParentWindow: true,
    );
    if (path == null || path.trim().isEmpty) return;
    if (!path.toLowerCase().endsWith('.cnkhbackup')) {
      path = '$path.cnkhbackup';
    }

    setState(() => _busy = true);
    try {
      final file = await _service.createBackup(path);
      final validation = await _service.validateBackup(file.path);
      if (!mounted) return;
      setState(() => _lastPath = file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '备份完成 · DB v${validation.databaseUserVersion} · '
            '${validation.imageCount} 张商品图片\n${file.path}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败：$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 CNKH POS 备份文件',
      type: FileType.custom,
      allowedExtensions: const ['cnkhbackup'],
      allowMultiple: false,
      lockParentWindow: true,
    );
    final path = picked?.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final validation = await _service.validateBackup(path);
      if (!validation.valid) {
        throw StateError(validation.message);
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('确认恢复备份？'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '恢复会用备份中的业务数据替换当前本机数据。系统会先保留当前数据库作为回滚快照；恢复校验失败会自动回滚。',
                    ),
                    const SizedBox(height: 12),
                    Text('备份时间：${validation.createdAt.isEmpty ? '未知' : validation.createdAt}'),
                    Text('数据库版本：${validation.databaseUserVersion}'),
                    Text('商品图片：${validation.imageCount} 张'),
                    const SizedBox(height: 8),
                    Text(
                      path,
                      style: const TextStyle(fontSize: 12, color: CnkhColors.muted),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确认恢复'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;

      await _service.restoreBackup(path);
      // Force a reopen now so SQLite migration/integrity errors surface before
      // reporting success to the user.
      await widget.repo.database.db;
      if (!mounted) return;
      setState(() => _lastPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('恢复完成，当前数据库已重新打开并通过校验')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败：$e'), backgroundColor: CnkhColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLastLocation() async {
    if (_lastPath.isEmpty || !Platform.isWindows) return;
    try {
      await Process.start(
        'explorer.exe',
        <String>['/select,', _lastPath],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件位置：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复 / Backup & Restore')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Windows 本机备份', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        '备份包含 CNKH POS SQLite 业务数据库与商品图片。保存时可自行选择文件夹和文件名。',
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _busy ? null : _createBackup,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('建立备份 / Create Backup'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('恢复本机数据', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        '系统会先验证备份格式与 SQLite integrity，再进行替换；任何恢复异常都会尝试恢复原数据库和商品图片。',
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _restoreBackup,
                        icon: const Icon(Icons.restore),
                        label: const Text('选择备份并恢复 / Restore Backup'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_lastPath.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('最近使用的备份文件'),
                    subtitle: SelectableText(_lastPath),
                    trailing: Platform.isWindows
                        ? OutlinedButton.icon(
                            onPressed: _busy ? null : _openLastLocation,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('打开位置'),
                          )
                        : null,
                  ),
                ),
              ],
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
