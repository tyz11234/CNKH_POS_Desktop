import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/app_release_notes.dart';

void main() {
  test(
    'about version and changelog stay aligned with the package version',
    () async {
      final manifest = await File('pubspec.yaml').readAsString();
      final changelog = await File('CHANGELOG.md').readAsString();
      expect(manifest, contains('version: $appVersion+$appBuildNumber'));
      expect(
        changelog,
        anyOf(
          contains('## $appVersionLabel — unreleased'),
          contains('## $appVersionLabel — released'),
        ),
      );
      expect(appVersionLabel, '$appVersion+$appBuildNumber');
      expect(appReleaseNotes, isNotEmpty);
    },
  );
}
