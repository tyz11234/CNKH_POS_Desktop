import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/desktop_backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Desktop backup validation and rollback', () {
    late Directory root;
    late String dbPath;
    late String imagesPath;
    late AppDatabase database;
    late DesktopBackupService backups;

    setUp(() async {
      AppDatabase.ensureFfi();
      root = await Directory.systemTemp.createTemp('cnkh-backup-guard-');
      dbPath = '${root.path}/pos.db';
      imagesPath = '${root.path}/product_images';
      database = AppDatabase.forTesting(dbPath, seed: false);
      await (await database.db).insert(
        'products',
        const Product(
          id: 'p1',
          sku: 'P1',
          barcode: '10001',
          nameZh: '商品',
          nameEn: 'Product',
          priceCents: 100,
          costCents: 50,
          stock: 8,
        ).toMap(),
      );
      await Directory(imagesPath).create(recursive: true);
      await File('$imagesPath/p1.jpg').writeAsBytes([1, 2, 3]);
      backups = DesktopBackupService(
        databasePath: dbPath,
        productImagesDirectory: imagesPath,
        closeDatabase: database.close,
      );
    });

    tearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<String> packageDatabase(String sourcePath, String name) async {
      final bytes = await File(sourcePath).readAsBytes();
      final manifestBytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'magic': kCnkhBackupMagic,
            'format_version': kCnkhBackupFormatVersion,
            'created_at': '2026-10-03T00:00:00Z',
            'database_user_version': AppDatabase.schemaVersion,
            'database_file': 'database/cnkh_pos_desktop.db',
            'product_images': <Object?>[],
          }),
        ),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile('database/cnkh_pos_desktop.db', bytes.length, bytes),
        )
        ..addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
        );
      final encoded = ZipEncoder().encode(archive);
      final path = '${root.path}/$name.cnkhbackup';
      await File(path).writeAsBytes(encoded, flush: true);
      return path;
    }

    test(
      'rejects missing required tables, columns, and future user_version',
      () async {
        final missingTablePath = '${root.path}/missing-table.db';
        final missingTableDb = AppDatabase.forTesting(
          missingTablePath,
          seed: false,
        );
        await (await missingTableDb.db).execute('DROP TABLE customers');
        await missingTableDb.close();
        final missingTable = await backups.validateBackup(
          await packageDatabase(missingTablePath, 'missing-table'),
        );
        expect(missingTable.valid, isFalse);
        expect(missingTable.message, contains('customers'));

        final missingEInvoicePath = '${root.path}/missing-einvoice.db';
        final missingEInvoiceDb = AppDatabase.forTesting(
          missingEInvoicePath,
          seed: false,
        );
        await (await missingEInvoiceDb.db).execute(
          'DROP TABLE e_invoice_documents',
        );
        await missingEInvoiceDb.close();
        final missingEInvoice = await backups.validateBackup(
          await packageDatabase(missingEInvoicePath, 'missing-einvoice'),
        );
        expect(missingEInvoice.valid, isFalse);
        expect(missingEInvoice.message, contains('e_invoice_documents'));

        final missingColumnPath = '${root.path}/missing-column.db';
        final missingColumnDb = AppDatabase.forTesting(
          missingColumnPath,
          seed: false,
        );
        await (await missingColumnDb.db).execute(
          'ALTER TABLE products DROP COLUMN cost_cents',
        );
        await missingColumnDb.close();
        final missingColumn = await backups.validateBackup(
          await packageDatabase(missingColumnPath, 'missing-column'),
        );
        expect(missingColumn.valid, isFalse);
        expect(missingColumn.message, contains('cost_cents'));

        final missingOutboxColumnPath = '${root.path}/missing-outbox-column.db';
        final missingOutboxColumnDb = AppDatabase.forTesting(
          missingOutboxColumnPath,
          seed: false,
        );
        await (await missingOutboxColumnDb.db).execute(
          'ALTER TABLE sync_outbox DROP COLUMN payload_json',
        );
        await missingOutboxColumnDb.close();
        final missingOutboxColumn = await backups.validateBackup(
          await packageDatabase(
            missingOutboxColumnPath,
            'missing-outbox-column',
          ),
        );
        expect(missingOutboxColumn.valid, isFalse);
        expect(missingOutboxColumn.message, contains('payload_json'));

        final futurePath = '${root.path}/future-version.db';
        final futureDb = AppDatabase.forTesting(futurePath, seed: false);
        await (await futureDb.db).execute('PRAGMA user_version = 999');
        await futureDb.close();
        final future = await backups.validateBackup(
          await packageDatabase(futurePath, 'future-version'),
        );
        expect(future.valid, isFalse);
        expect(future.message, contains('高于当前支持版本'));
      },
    );

    test(
      'accepts a supported v7 backup through the application migration path',
      () async {
        final legacyPath = '${root.path}/legacy-v7.db';
        final legacy = AppDatabase.forTesting(legacyPath, seed: false);
        final db = await legacy.db;
        // Model a prior supported schema: OCR/e-Invoice tables are absent and
        // user_version is the version used before those migrations.
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'e_invoice%'",
        );
        for (final table in tables) {
          await db.execute('DROP TABLE "${table['name']}"');
        }
        await db.execute('PRAGMA user_version = 7');
        await legacy.close();

        final result = await backups.validateBackup(
          await packageDatabase(legacyPath, 'legacy-v7'),
        );
        expect(result.valid, isTrue, reason: result.message);
        expect(result.databaseUserVersion, 7);

        final restored = AppDatabase.forTesting(
          '${root.path}/restored-v7.db',
          seed: false,
        );
        try {
          final path = await packageDatabase(legacyPath, 'legacy-v7-restore');
          await DesktopBackupService(
            databasePath: '${root.path}/restored-v7.db',
            productImagesDirectory: '${root.path}/legacy-images',
            closeDatabase: restored.close,
          ).restoreBackup(path);
          await AppDatabase.validateRestoredDatabase(await restored.db);
        } finally {
          await restored.close();
        }
      },
    );

    test(
      'migration failure leaves production database and images unchanged',
      () async {
        final backupPath = '${root.path}/good.cnkhbackup';
        await backups.createBackup(backupPath);
        await (await database.db).update(
          'products',
          {'stock': 99.0},
          where: 'id=?',
          whereArgs: ['p1'],
        );
        await File('$imagesPath/p1.jpg').writeAsBytes([9, 9, 9]);
        var calls = 0;
        final failing = DesktopBackupService(
          databasePath: dbPath,
          productImagesDirectory: imagesPath,
          closeDatabase: database.close,
          migrateAndValidateDatabase: (path) async {
            calls++;
            if (calls == 2) {
              throw StateError('injected staged migration failure');
            }
            await AppDatabase.migrateAndValidateBackupFile(path);
          },
        );
        await expectLater(
          failing.restoreBackup(backupPath),
          throwsA(isA<StateError>()),
        );
        expect(calls, 2);
        expect(
          (await (await database.db).query(
            'products',
            where: 'id=?',
            whereArgs: ['p1'],
          )).single['stock'],
          99.0,
        );
        expect(await File('$imagesPath/p1.jpg').readAsBytes(), [9, 9, 9]);
      },
    );

    test(
      'production reopen failure rolls back both database and image directory',
      () async {
        final backupPath = '${root.path}/good-reopen.cnkhbackup';
        await backups.createBackup(backupPath);
        await (await database.db).update(
          'products',
          {'stock': 99.0},
          where: 'id=?',
          whereArgs: ['p1'],
        );
        await File('$imagesPath/p1.jpg').writeAsBytes([8, 8, 8]);
        final failing = DesktopBackupService(
          databasePath: dbPath,
          productImagesDirectory: imagesPath,
          closeDatabase: database.close,
          reopenAndValidateDatabase: () async =>
              throw StateError('injected reopen failure'),
        );
        await expectLater(
          failing.restoreBackup(backupPath),
          throwsA(isA<StateError>()),
        );
        final product = (await (await database.db).query(
          'products',
          where: 'id=?',
          whereArgs: ['p1'],
        )).single;
        expect(product['stock'], 99.0);
        expect(await File('$imagesPath/p1.jpg').readAsBytes(), [8, 8, 8]);
      },
    );
  });
}
