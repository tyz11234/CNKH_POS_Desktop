import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/services/desktop_backup.dart';

void main() {
  group('DesktopBackupService', () {
    late Directory root;
    late String dbPath;
    late String imagesPath;
    late AppDatabase database;
    late DesktopBackupService backups;

    setUp(() async {
      AppDatabase.ensureFfi();
      root = await Directory.systemTemp.createTemp('cnkh_desktop_backup_');
      dbPath = '${root.path}${Platform.pathSeparator}cnkh_pos_desktop.db';
      imagesPath = '${root.path}${Platform.pathSeparator}product_images';
      database = AppDatabase.forTesting(dbPath, seed: false);
      final db = await database.db;
      await db.insert(
        'products',
        const Product(
          id: 'p1',
          nameZh: '备份商品',
          nameEn: 'Backup Product',
          sku: 'SKU-BACKUP',
          barcode: '1234567890128',
          priceCents: 1990,
          stock: 8,
        ).toMap(),
      );
      await db.insert('customers', <String, Object?>{
        'id': 'c1',
        'name': 'Backup Customer',
        'phone': '0123456789',
        'notes': '',
        'is_deleted': 0,
      });
      await db.insert('suppliers', <String, Object?>{
        'id': 's1',
        'name': 'Backup Supplier',
        'phone': '',
        'email': 'supplier@example.com',
        'notes': '',
        'is_deleted': 0,
      });
      await db.insert(
        'settings',
        <String, Object?>{'key': 'store_name', 'value': 'Backup Store'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final images = Directory(imagesPath);
      await images.create(recursive: true);
      await File('${images.path}${Platform.pathSeparator}p1.jpg')
          .writeAsBytes(<int>[1, 2, 3, 4, 5], flush: true);

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

    test('creates a validated backup with database and product images', () async {
      final path = '${root.path}${Platform.pathSeparator}store.cnkhbackup';
      final file = await backups.createBackup(path);
      expect(await file.exists(), true);

      final validation = await backups.validateBackup(path);
      expect(validation.valid, true, reason: validation.message);
      expect(validation.databaseUserVersion, greaterThanOrEqualTo(0));
      expect(validation.imageCount, 1);
    });

    test('restore replaces changed data and images with backup snapshot', () async {
      final path = '${root.path}${Platform.pathSeparator}store.cnkhbackup';
      await backups.createBackup(path);

      var db = await database.db;
      await db.update(
        'products',
        <String, Object?>{'name_zh': '已被修改', 'stock': 99.0},
        where: 'id=?',
        whereArgs: <Object?>['p1'],
      );
      await File('$imagesPath${Platform.pathSeparator}p1.jpg')
          .writeAsBytes(<int>[9, 9, 9], flush: true);

      await backups.restoreBackup(path);

      db = await database.db;
      final products = await db.query('products', where: 'id=?', whereArgs: ['p1']);
      expect(products.single['name_zh'], '备份商品');
      expect((products.single['stock'] as num).toDouble(), 8.0);
      final image = await File('$imagesPath${Platform.pathSeparator}p1.jpg').readAsBytes();
      expect(image, <int>[1, 2, 3, 4, 5]);
    });

    test('invalid backup is rejected before current database is modified', () async {
      final bad = File('${root.path}${Platform.pathSeparator}bad.cnkhbackup');
      await bad.writeAsString('not a zip', flush: true);

      await expectLater(
        backups.restoreBackup(bad.path),
        throwsA(isA<StateError>()),
      );

      final db = await database.db;
      final products = await db.query('products', where: 'id=?', whereArgs: ['p1']);
      expect(products, hasLength(1));
      expect(products.single['name_zh'], '备份商品');
    });
  });
}
