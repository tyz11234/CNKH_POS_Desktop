import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'esc_pos_receipt.dart';
import 'receipt_template.dart';
import 'pos_repository.dart';

/// Optional Bluetooth ESC/POS receipt printer (Android-first).
/// Never blocks checkout — callers treat failures as snackbar-only.
class BluetoothPrinterService {
  BluetoothPrinterService(this.repo, {BluetoothPrinterTransport? transport})
      : _transport = transport ?? _NativeBluetoothTransport();
  final BluetoothPrinterTransport _transport;
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
    if (!_transport.supported) return [];
    try {
      return await _transport.bondedDevices();
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect([String? address]) async {
    if (!_transport.supported) return false;
    try {
      final addr = address ?? await savedAddress();
      if (addr == null || addr.isEmpty) return false;
      final ok = await _transport.connect(addr);
      if (ok) await saveAddress(addr);
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!_transport.supported) return;
    try {
      await _transport.disconnect();
    } catch (_) {}
  }

  Future<bool> isConnected() async {
    if (!_transport.supported) return false;
    try {
      return await _transport.isConnected();
    } catch (_) {
      return false;
    }
  }

  /// Print sale receipt if BT enabled. Returns status code/message (never throws).
  Future<String> tryPrintSale(SaleRecord sale, {String? storeName}) async {
    try {
      if (!await enabled()) return 'bt_off';
      if (!_transport.supported) {
        return '此设备不支持蓝牙小票机 / BT printer not supported here';
      }
      var connected = await isConnected();
      if (!connected) connected = await connect();
      if (!connected) {
        return '未连接蓝牙打印机 / No Bluetooth printer connected';
      }
      final template = await ReceiptTemplate.load(repo);
      final effective = storeName != null && storeName.trim().isNotEmpty
          ? template.copyWith(storeName: storeName.trim())
          : template;
      final text = effective.renderFromSale(sale);
      final dots = int.tryParse(await repo.getSetting('bt_printer_width_dots', fallback: '384')) ?? 384;
      final bytes = await buildReceiptBytes(text, widthDots: dots);
      final ok = await _transport.writeBytes(bytes);
      return ok ? 'ok' : '打印失败 / Print failed';
    } catch (e) {
      return '打印失败: $e';
    }
  }

  /// Shared by the actual print entry and automated raster-output tests.
  Future<List<int>> buildReceiptBytes(String text, {int widthDots = 384}) =>
      EscPosReceiptEncoder().encode(text, widthDots: widthDots);
}

/// The production adapter and tests use the same print entry, including
/// platform/capability checks, connection and the final byte write.
abstract class BluetoothPrinterTransport {
  bool get supported;
  Future<List<BluetoothInfo>> bondedDevices();
  Future<bool> connect(String address);
  Future<void> disconnect();
  Future<bool> isConnected();
  Future<bool> writeBytes(List<int> bytes);
}

class _NativeBluetoothTransport implements BluetoothPrinterTransport {
  @override bool get supported => BluetoothPrinterService.isPlatformSupported;
  @override Future<List<BluetoothInfo>> bondedDevices() => PrintBluetoothThermal.pairedBluetooths;
  @override Future<bool> connect(String address) => PrintBluetoothThermal.connect(macPrinterAddress: address);
  @override Future<void> disconnect() async { await PrintBluetoothThermal.disconnect; }
  @override Future<bool> isConnected() => PrintBluetoothThermal.connectionStatus;
  @override Future<bool> writeBytes(List<int> bytes) => PrintBluetoothThermal.writeBytes(bytes);
}
