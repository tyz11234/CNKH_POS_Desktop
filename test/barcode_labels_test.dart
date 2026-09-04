import 'package:cnkh_pos_desktop/services/barcode_labels.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderPng includes PNG magic and CJK name layout', () async {
    final svc = BarcodeLabelService(PosRepository());
    final bytes = await svc.renderPng(
      barcode: '1234567890128',
      productName: '水管接头 Pipe fitting',
    );
    expect(bytes.length, greaterThan(100));
    expect(bytes[0], 0x89);
    expect(bytes[1], 0x50); // P
    expect(bytes[2], 0x4E); // N
    expect(bytes[3], 0x47); // G
  });

  test('renderPng rejects empty barcode', () async {
    final svc = BarcodeLabelService(PosRepository());
    expect(
      () => svc.renderPng(barcode: '  ', productName: 'x'),
      throwsA(isA<StateError>()),
    );
  });
}
