import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'e_receipt.dart';
import 'pos_repository.dart';

/// Optional Bluetooth ESC/POS receipt printer (Android-first).
/// Never blocks checkout — callers treat failures as snackbar-only.
class BluetoothPrinterService {
  BluetoothPrinterService(this.repo);
  final PosRepository repo;

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  Future<bool> enabled() => repo.btPrinterEnabled();

  Future<String?> savedAddress() async {
    final a = await repo.getSetting('bt_printer_address');
    return a.trim().isEmpty ? null : a.trim();
  }

  Future<void> saveAddress(String address) =>
      repo.setSetting('bt_printer_address', address.trim());

  Future<List<BluetoothInfo>> bondedDevices() async {
    if (!isPlatformSupported) return [];
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect([String? address]) async {
    if (!isPlatformSupported) return false;
    try {
      final addr = address ?? await savedAddress();
      if (addr == null || addr.isEmpty) return false;
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: addr);
      if (ok) await saveAddress(addr);
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!isPlatformSupported) return;
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }

  Future<bool> isConnected() async {
    if (!isPlatformSupported) return false;
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  /// Print sale receipt if BT enabled. Returns status code/message (never throws).
  Future<String> tryPrintSale(SaleRecord sale, {String? storeName}) async {
    try {
      if (!await enabled()) return 'bt_off';
      if (!isPlatformSupported) {
        return '此设备不支持蓝牙小票机 / BT printer not supported here';
      }
      var connected = await isConnected();
      if (!connected) connected = await connect();
      if (!connected) {
        return '未连接蓝牙打印机 / No Bluetooth printer connected';
      }
      final name = storeName ??
          await repo.getSetting('store_name', fallback: kStoreName);
      final text = buildPrintReceiptTextFromSale(sale, storeName: name);
      final bytes = _escPosFromText(text);
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      return ok ? 'ok' : '打印失败 / Print failed';
    } catch (e) {
      return '打印失败: $e';
    }
  }

  List<int> _escPosFromText(String text) {
    final out = <int>[];
    out.addAll([0x1B, 0x40]);
    out.addAll([0x1B, 0x61, 0x00]);
    for (final line in text.split('\n')) {
      out.addAll(line.codeUnits);
      out.add(0x0A);
    }
    out.addAll([0x0A, 0x0A, 0x0A]);
    out.addAll([0x1D, 0x56, 0x00]);
    return out;
  }
}
