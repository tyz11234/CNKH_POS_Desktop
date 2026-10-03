import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mockPackageInfoForTests() async {
  final manifest = await File('pubspec.yaml').readAsString();
  final version = RegExp(
    r'^version:\s*([^+\s]+)\+([^\s]+)\s*$',
    multiLine: true,
  ).firstMatch(manifest);
  if (version == null) {
    throw StateError('pubspec.yaml is missing a version and build number');
  }

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (_) async => <String, Object?>{
          'appName': 'CNKH POS',
          'packageName': 'com.cnkh.pos',
          'version': version.group(1),
          'buildNumber': version.group(2),
          'buildSignature': '',
          'installerStore': null,
        },
      );
}
