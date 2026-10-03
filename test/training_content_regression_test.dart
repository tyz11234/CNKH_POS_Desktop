import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/screens/training_page.dart';

void main() {
  test('MyInvois training covers certificates and durable Invalid reconciliation', () {
    final setup = TrainingPage.lessons.singleWhere((lesson) => lesson.$2 == 'einvoice_setup').$3;
    final errors = TrainingPage.lessons.singleWhere((lesson) => lesson.$1 == '常见错误处理').$3;
    expect(setup, contains('PFX/P12'));
    expect(errors, contains('Invalid'));
    expect(errors, contains('Submission UID'));
    expect(errors, contains('更正尝试'));
  });
}
