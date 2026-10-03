import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/app_release_notes.dart';
import 'package:cnkh_pos_desktop/app_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );

  test('About version uses installed package metadata', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(packageInfoChannel, (call) async {
      expect(call.method, 'getAll');
      return <String, Object?>{
        'appName': 'CNKH POS',
        'packageName': 'com.cnkh.pos',
        'version': '9.8.7',
        'buildNumber': '42',
        'buildSignature': '',
        'installerStore': null,
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(packageInfoChannel, null),
    );

    expect(await loadAppVersionLabel(), '9.8.7+42');
    expect(appReleaseNotes, isNotEmpty);
  });

  test('package version is recorded in the changelog', () {
    final packageVersion = RegExp(
      r'^version:\s*([^\s#]+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
    final changelog = File('CHANGELOG.md').readAsStringSync();

    expect(
      changelog,
      contains(
        RegExp('^## ${RegExp.escape(packageVersion)} —', multiLine: true),
      ),
    );
  });
}
