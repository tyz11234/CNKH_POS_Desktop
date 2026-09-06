import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const String kCnkhBackupMagic = 'CNKH_POS_DESKTOP_BACKUP';
const int kCnkhBackupFormatVersion = 1;

class BackupValidationResult {
  const BackupValidationResult({
    required this.valid,
    this.message = '',
    this.createdAt = '',
    this.databaseUserVersion = 0,
    this.imageCount = 0,
  });

  final bool valid;
  final String message;
  final String createdAt;
  final int databaseUserVersion;
  final int imageCount;
}

class DesktopBackupService {
  DesktopBackupService({
    this.databasePath,
    this.productImagesDirectory,
    this.closeDatabase,
  });

  final String? databasePath;
  final String? productImagesDirectory;
  final Future<void> Function()? closeDatabase;

  Future<String> _dbPath() async {
    if (databasePath != null) return databasePath!;
    final root = await getApplicationDocumentsDirectory();
    return p.join(root.path, 'cnkh_pos_desktop.db');
  }

  Future<String> _imagesPath() async {
    if (productImagesDirectory != null) return productImagesDirectory!;
    final root = await getApplicationDocumentsDirectory();
    return p.join(root.path, 'product_images');
  }

  Future<File> createBackup(String destinationPath) async {
    final target = File(destinationPath);
    if (target.path.trim().isEmpty) {
      throw ArgumentError('备份保存路径不能为空');
    }
    final dbPath = await _dbPath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw StateError('POS 数据库不存在：$dbPath');
    }

    // Closing the connection flushes WAL/SHM state before the database bytes are
    // copied. AppDatabase opens lazily again on the next repository operation.
    await closeDatabase?.call();

    final dbBytes = await dbFile.readAsBytes();
    final dbMeta = await _validateDatabaseBytes(dbBytes);
    final imagesDir = Directory(await _imagesPath());
    final imageEntries = <Map<String, Object?>>[];
    final archive = Archive();
    archive.addFile(
      ArchiveFile('database/cnkh_pos_desktop.db', dbBytes.length, dbBytes),
    );

    if (await imagesDir.exists()) {
      await for (final entity in imagesDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: imagesDir.path);
        final normalized = relative.replaceAll('\\', '/');
        if (normalized.startsWith('../') || normalized == '..') continue;
        final bytes = await entity.readAsBytes();
        final entryName = 'product_images/$normalized';
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
        imageEntries.add(<String, Object?>{
          'path': normalized,
          'bytes': bytes.length,
        });
      }
    }

    final manifest = <String, Object?>{
      'magic': kCnkhBackupMagic,
      'format_version': kCnkhBackupFormatVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'database_user_version': dbMeta.databaseUserVersion,
      'database_file': 'database/cnkh_pos_desktop.db',
      'product_images': imageEntries,
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    final temp = File('${target.path}.tmp');
    if (await temp.exists()) await temp.delete();
    await temp.writeAsBytes(zipBytes, flush: true);
    final validation = await validateBackup(temp.path);
    if (!validation.valid) {
      await temp.delete();
      throw StateError('备份生成后校验失败：${validation.message}');
    }
    if (await target.exists()) await target.delete();
    return temp.rename(target.path);
  }

  Future<BackupValidationResult> validateBackup(String backupPath) async {
    try {
      final file = File(backupPath);
      if (!await file.exists()) {
        return const BackupValidationResult(valid: false, message: '备份文件不存在');
      }
      final decoded = ZipDecoder().decodeBytes(await file.readAsBytes(), verify: true);
      final manifestFile = _entry(decoded, 'manifest.json');
      final dbEntry = _entry(decoded, 'database/cnkh_pos_desktop.db');
      if (manifestFile == null || dbEntry == null) {
        return const BackupValidationResult(
          valid: false,
          message: '缺少 manifest 或数据库文件',
        );
      }
      final manifestRaw = manifestFile.readBytes();
      if (manifestRaw == null) {
        return const BackupValidationResult(valid: false, message: 'manifest 无法读取');
      }
      final manifest = jsonDecode(utf8.decode(manifestRaw));
      if (manifest is! Map) {
        return const BackupValidationResult(valid: false, message: 'manifest 格式错误');
      }
      if (manifest['magic'] != kCnkhBackupMagic) {
        return const BackupValidationResult(valid: false, message: '不是 CNKH POS 备份');
      }
      if ((manifest['format_version'] as num?)?.toInt() !=
          kCnkhBackupFormatVersion) {
        return const BackupValidationResult(valid: false, message: '不支持的备份版本');
      }
      final dbBytes = dbEntry.readBytes();
      if (dbBytes == null || dbBytes.isEmpty) {
        return const BackupValidationResult(valid: false, message: '数据库内容为空');
      }
      final dbValidation = await _validateDatabaseBytes(dbBytes);
      final imageCount = decoded.files
          .where((e) => e.isFile && e.name.startsWith('product_images/'))
          .length;
      return BackupValidationResult(
        valid: true,
        message: 'OK',
        createdAt: manifest['created_at']?.toString() ?? '',
        databaseUserVersion: dbValidation.databaseUserVersion,
        imageCount: imageCount,
      );
    } catch (e) {
      return BackupValidationResult(valid: false, message: '$e');
    }
  }

  Future<void> restoreBackup(String backupPath) async {
    final validation = await validateBackup(backupPath);
    if (!validation.valid) {
      throw StateError('备份文件无效：${validation.message}');
    }

    final dbPath = await _dbPath();
    final imagesPath = await _imagesPath();
    final activeDb = File(dbPath);
    final activeImages = Directory(imagesPath);
    final parent = activeDb.parent;
    await parent.create(recursive: true);

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stageDir = Directory(p.join(parent.path, '.cnkh_restore_$stamp'));
    final rollbackDb = File('$dbPath.before_restore_$stamp');
    final rollbackImages = Directory('$imagesPath.before_restore_$stamp');
    await stageDir.create(recursive: true);

    var dbReplaced = false;
    var imagesReplaced = false;
    try {
      final decoded = ZipDecoder().decodeBytes(
        await File(backupPath).readAsBytes(),
        verify: true,
      );
      final dbEntry = _entry(decoded, 'database/cnkh_pos_desktop.db')!;
      final stagedDb = File(p.join(stageDir.path, 'cnkh_pos_desktop.db'));
      await stagedDb.writeAsBytes(dbEntry.readBytes()!, flush: true);
      await _validateDatabaseFile(stagedDb.path);

      final stagedImages = Directory(p.join(stageDir.path, 'product_images'));
      for (final entry in decoded.files) {
        if (!entry.isFile || !entry.name.startsWith('product_images/')) continue;
        final relative = entry.name.substring('product_images/'.length);
        if (!_safeArchiveRelativePath(relative)) {
          throw StateError('备份包含不安全的图片路径');
        }
        final bytes = entry.readBytes();
        if (bytes == null) throw StateError('图片附件无法读取：$relative');
        final out = File(p.join(stagedImages.path, p.normalize(relative)));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(bytes, flush: true);
      }

      await closeDatabase?.call();

      if (await activeDb.exists()) {
        await activeDb.rename(rollbackDb.path);
      }
      await stagedDb.rename(activeDb.path);
      dbReplaced = true;

      if (await activeImages.exists()) {
        await activeImages.rename(rollbackImages.path);
      }
      if (await stagedImages.exists()) {
        await stagedImages.rename(activeImages.path);
      } else {
        await activeImages.create(recursive: true);
      }
      imagesReplaced = true;

      // Validate the exact bytes now occupying the production path. Any failure
      // below must roll back both DB and images as one restore operation.
      await _validateDatabaseFile(activeDb.path);

      if (await rollbackDb.exists()) await rollbackDb.delete();
      if (await rollbackImages.exists()) {
        await rollbackImages.delete(recursive: true);
      }
    } catch (e) {
      await closeDatabase?.call();
      try {
        if (dbReplaced && await activeDb.exists()) await activeDb.delete();
        if (await rollbackDb.exists()) await rollbackDb.rename(activeDb.path);
      } catch (_) {}
      try {
        if (imagesReplaced && await activeImages.exists()) {
          await activeImages.delete(recursive: true);
        }
        if (await rollbackImages.exists()) {
          await rollbackImages.rename(activeImages.path);
        }
      } catch (_) {}
      throw StateError('恢复失败，已尝试回滚原数据：$e');
    } finally {
      if (await stageDir.exists()) {
        await stageDir.delete(recursive: true);
      }
    }
  }

  ArchiveFile? _entry(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.name == name) return file;
    }
    return null;
  }

  bool _safeArchiveRelativePath(String relative) {
    if (relative.isEmpty) return false;
    final normalized = relative.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.contains('../')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
    return true;
  }

  Future<BackupValidationResult> _validateDatabaseBytes(Uint8List bytes) async {
    final tempDir = await Directory.systemTemp.createTemp('cnkh_backup_validate_');
    try {
      final file = File(p.join(tempDir.path, 'db.sqlite'));
      await file.writeAsBytes(bytes, flush: true);
      return _validateDatabaseFile(file.path);
    } finally {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
  }

  Future<BackupValidationResult> _validateDatabaseFile(String path) async {
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final integrity = db.select('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first.toString().toLowerCase() != 'ok') {
        throw StateError('SQLite integrity_check 失败');
      }
      const required = <String>{
        'products',
        'customers',
        'suppliers',
        'sales',
        'purchases',
        'stock_moves',
        'settings',
      };
      final rows = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      final names = <String>{for (final row in rows) row['name'].toString()};
      final missing = required.difference(names);
      if (missing.isNotEmpty) {
        throw StateError('数据库缺少必要表：${missing.join(', ')}');
      }
      final versionRows = db.select('PRAGMA user_version');
      final userVersion = versionRows.isEmpty
          ? 0
          : (versionRows.first.values.first as num?)?.toInt() ?? 0;
      return BackupValidationResult(
        valid: true,
        message: 'OK',
        databaseUserVersion: userVersion,
      );
    } finally {
      db?.dispose();
    }
  }
}
