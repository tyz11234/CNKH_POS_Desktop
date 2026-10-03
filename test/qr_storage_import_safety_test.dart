import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cnkh_pos_desktop/services/qr_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cnkh-qr-import-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => temp.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  test('failed replacement preserves the saved QR file and preference', () async {
    final source = await File('${temp.path}/original.png').writeAsBytes([1, 2, 3]);
    final storage = QrStorage();
    final original = await storage.saveFromPicker(source.path);

    await expectLater(
      storage.saveFromPicker('${temp.path}/missing.jpg'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await storage.getLocalPath(), original);
    expect(await File(original).readAsBytes(), [1, 2, 3]);
  });

  test('successful replacement is durable before the old QR is removed', () async {
    final source = await File('${temp.path}/original.png').writeAsBytes([1, 2, 3]);
    final replacement = await File('${temp.path}/replacement.jpg').writeAsBytes([4, 5, 6]);
    final storage = QrStorage();
    final original = await storage.saveFromPicker(source.path);
    final current = await storage.saveFromPicker(replacement.path);
    expect(await storage.getLocalPath(), current);
    expect(await File(current).readAsBytes(), [4, 5, 6]);
    expect(await File(original).exists(), isFalse);
    await storage.clear();
    expect(await storage.getLocalPath(), isNull);
    expect(await File(current).exists(), isFalse);
  });

  test('an existing local QR can be selected again', () async {
    final source = await File('${temp.path}/original.png').writeAsBytes([7, 8, 9]);
    final storage = QrStorage();
    final original = await storage.saveFromPicker(source.path);
    final current = await storage.saveFromPicker(original);
    expect(await storage.getLocalPath(), current);
    expect(await File(current).readAsBytes(), [7, 8, 9]);
  });
}

