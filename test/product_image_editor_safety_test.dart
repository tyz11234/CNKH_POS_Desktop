import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:cnkh_pos_desktop/models/app_user.dart';
import 'package:cnkh_pos_desktop/models/product.dart';
import 'package:cnkh_pos_desktop/screens/admin/products_admin.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

class _Picker extends ImagePickerPlatform {
  _Picker(this.path);
  final String path;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(path);
}

class _ProductRepo extends PosRepository {
  _ProductRepo(this.product, {this.failSave = false});
  Product product;
  final bool failSave;
  int writes = 0;
  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 80,
    int offset = 0,
    String? category,
  }) async => [product];
  @override
  Future<bool> productImagesEnabled() async => true;
  @override
  Future<void> upsertProduct(Product value, {Product? original}) async {
    if (failSave) throw StateError('保存失败');
    product = value;
    writes++;
  }
}

class _DelayedPicker extends ImagePickerPlatform {
  final result = Completer<XFile?>();
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) => result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File original;
  late List<int> originalBytes;
  late ImagePickerPlatform previousPicker;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('product-image-editor-');
    await Directory('${dir.path}/product_images').create();
    final picture = img.Image(width: 2, height: 2);
    img.fill(picture, color: img.ColorRgb8(255, 0, 0));
    originalBytes = img.encodePng(picture);
    original = File('${dir.path}/product_images/p1.png');
    await original.writeAsBytes(originalBytes);
    img.fill(picture, color: img.ColorRgb8(0, 0, 255));
    final picked = File('${dir.path}/replacement.png');
    await picked.writeAsBytes(img.encodePng(picture));
    previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _Picker(picked.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
  });
  tearDown(() async {
    ImagePickerPlatform.instance = previousPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final cleanup = Stopwatch()..start();
    while (true) {
      try {
        await dir.delete(recursive: true);
        break;
      } on FileSystemException catch (e) {
        if (!Platform.isWindows ||
            e.osError?.errorCode != 32 ||
            cleanup.elapsedMilliseconds >= 10000) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  Future<void> openEditor(
    WidgetTester tester,
    _ProductRepo repo, {
    bool pickImage = true,
  }) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final cache = PaintingBinding.instance.imageCache;
      final decoding = Stopwatch()..start();
      // FileImage decoding owns a native read handle on Windows. Complete
      // pending streams before clearing their cache bookkeeping or the files.
      while (cache.pendingImageCount > 0 &&
          decoding.elapsedMilliseconds < 10000) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(cache.pendingImageCount, 0);
      cache.clear();
      cache.clearLiveImages();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProductsAdminPage(
          repo: repo,
          user: const AppUser(username: 'admin', role: AppRole.admin),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('商品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑 / Edit'));
    await tester.pumpAndSettle();
    if (!pickImage) return;
    await tester.ensureVisible(find.text('选择商品图片 / Pick image'));
    await tester.tap(find.text('选择商品图片 / Pick image'));
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final finished = await tester.runAsync(() async {
        final files = await Directory(
          '${dir.path}/product_images',
        ).list().toList();
        final bytes = await original.readAsBytes();
        final draftPaths = files
            .whereType<File>()
            .where((file) => file.path != original.path)
            .map((file) => file.path)
            .toSet();
        final preview = tester
            .widgetList<Image>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Image),
              ),
            )
            .any(
              (widget) =>
                  widget.image is FileImage &&
                  draftPaths.contains((widget.image as FileImage).file.path),
            );
        return (files.length > 1 && preview) ||
            bytes.toString() != originalBytes.toString();
      });
      if (finished == true) return;
    }
    fail('Image selection did not finish within two seconds');
  }

  _ProductRepo repository({bool failSave = false}) => _ProductRepo(
    Product(
      id: 'p1',
      nameZh: '商品',
      nameEn: 'Product',
      sku: 'P1',
      barcode: 'B1',
      priceCents: 100,
      imagePath: original.path,
    ),
    failSave: failSave,
  );

  for (final action in ['保存', '取消']) {
    testWidgets('a focused product field can close with $action', (
      tester,
    ) async {
      final repo = repository();
      await openEditor(tester, repo, pickImage: false);
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '中文名',
      );
      await tester.enterText(field, '商品改名');
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.writes, action == '保存' ? 1 : 0);
      expect(repo.product.nameZh, action == '保存' ? '商品改名' : '商品');
    });
  }

  testWidgets(
    'a late image selection after cancel leaves no draft or original change',
    (tester) async {
      final picker = _DelayedPicker();
      ImagePickerPlatform.instance = picker;
      final repo = repository();
      await openEditor(tester, repo, pickImage: false);
      await tester.ensureVisible(find.text('选择商品图片 / Pick image'));
      await tester.tap(find.text('选择商品图片 / Pick image'));
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      picker.result.complete(XFile('${dir.path}/replacement.png'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await tester.runAsync(original.readAsBytes), originalBytes);
      expect(
        await tester.runAsync(
          () => Directory('${dir.path}/product_images').list().length,
        ),
        1,
      );
      expect(repo.writes, 0);
    },
  );

  testWidgets('canceling a replacement image preserves the original bytes', (
    tester,
  ) async {
    final repo = repository();
    await openEditor(tester, repo);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(original.readAsBytes), originalBytes);
    expect(repo.writes, 0);
    expect(repo.product.imagePath, original.path);
  });

  testWidgets('saving a replacement uses a separate image revision', (
    tester,
  ) async {
    final repo = repository();
    await openEditor(tester, repo);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(repo.product.imagePath, isNot(original.path));
    expect(await tester.runAsync(original.readAsBytes), originalBytes);
    expect(
      await tester.runAsync(() => File(repo.product.imagePath).exists()),
      isTrue,
    );
  });

  testWidgets('a rejected save preserves the original image', (tester) async {
    final repo = repository(failSave: true);
    await openEditor(tester, repo);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(await tester.runAsync(original.readAsBytes), originalBytes);
    expect(repo.writes, 0);
  });
}
