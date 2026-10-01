import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:cnkh_pos_desktop/services/bluetooth_printer.dart';

class RecordingPrinter implements BluetoothPrinterTransport {
  List<int> bytes = [];
  int writes = 0;
  @override bool get supported => true;
  @override Future<List<BluetoothInfo>> bondedDevices() async => [];
  @override Future<bool> connect(String address) async => true;
  @override Future<void> disconnect() async {}
  @override Future<bool> isConnected() async => true;
  @override Future<bool> writeBytes(List<int> value) async { bytes = value; writes++; return true; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('F09 actual print entry sends Chinese, English and digits as raster bytes', () async {
    final temp = await Directory.systemTemp.createTemp('cnkh-print-output-');
    final database = AppDatabase.forTesting('${temp.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);
    final printer = RecordingPrinter();
    final service = BluetoothPrinterService(repo, transport: printer);
    try {
      await repo.setSetting('bt_printer_enabled', '1');
      await repo.setSetting('store_name', '黄金发宝号 Shop 123');
      final sale = SaleRecord(id: 's', receiptNo: 'R-123', soldAt: '2026-10-01T10:00:00',
        cashier: '员工 A', paymentMethod: 'CASH', subtotalCents: 100, itemDiscountCents: 0,
        orderDiscountCents: 0, roundingCents: 0, totalCents: 100, paidCents: 100,
        changeCents: 0, creditOutstandingCents: 0,
        linesJson: jsonEncode([{'nameZh': '很长的中文商品名称测试螺丝钉 ABC 123',
          'nameEn': 'Screw', 'sku': 'SKU-123', 'qty': 1, 'unitPriceCents': 100, 'lineTotalCents': 100}]));
      expect(await service.tryPrintSale(sale), 'ok');
      expect(printer.writes, 1);
      expect(printer.bytes.every((b) => b >= 0 && b <= 255), isTrue);
      expect(printer.bytes.take(2), [0x1b, 0x40]);
      expect(printer.bytes.sublist(printer.bytes.length-3), [0x1d, 0x56, 0]);
      final narrow = await service.buildReceiptBytes('中文 ABC 123\n${'长商品名字' * 40}', widthDots: 384);
      final wide = await service.buildReceiptBytes('中文 ABC 123\n${'长商品名字' * 40}', widthDots: 576);
      expect(narrow.sublist(6, 12), [0x1d, 0x76, 0x30, 0, 48, 0]);
      expect(wide.sublist(6, 12), [0x1d, 0x76, 0x30, 0, 72, 0]);
      expect(narrow.every((b) => b >= 0 && b <= 255), isTrue);
      expect(narrow.length, greaterThan(1000));
      expect(await service.buildReceiptBytes('中文'), isNot(await service.buildReceiptBytes('英文')));
      await expectLater(service.buildReceiptBytes('text', widthDots: 500), throwsArgumentError);
    } finally { await database.close(); await temp.delete(recursive: true); }
  });
}
