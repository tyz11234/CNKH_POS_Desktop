import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/services/product_images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  test(
    'saveBase64 returns null when the image directory cannot be created',
    () async {
      final temp = await Directory.systemTemp.createTemp('cnkh-image-store-');
      final blockedRoot = File('${temp.path}/not-a-directory');
      await blockedRoot.writeAsString('file blocks directory creation');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        pathProviderChannel,
        (_) async => blockedRoot.path,
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(pathProviderChannel, null);
        await temp.delete(recursive: true);
      });

      expect(
        await ProductImageStore().saveBase64(
          'product-1',
          base64Encode([1, 2, 3]),
        ),
        isNull,
      );
    },
  );
}
