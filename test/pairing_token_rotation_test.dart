import 'dart:convert';
import 'dart:io';

import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('rotating pairing token revokes old HTTP and WebSocket credentials', () async {
    AppDatabase.ensureFfi();
    final dir = await Directory.systemTemp.createTemp('cnkh-pairing-rotate-');
    final database = AppDatabase.forTesting('${dir.path}/pos.db', seed: false);
    final repo = PosRepository(database: database);
    final host = LanPairingHost.forTesting(
      repo,
      database: database,
      configuredPort: 0,
    );

    try {
      await host.start();
      final oldToken = await repo.getSetting('lan_host_token');
      expect(oldToken.length, greaterThanOrEqualTo(24));

      final health = Uri.parse('http://127.0.0.1:${host.port}/api/v1/health');
      final before = await http.get(
        health,
        headers: {'X-CNKH-Token': oldToken},
      );
      expect(before.statusCode, HttpStatus.ok);

      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${host.port}/api/v1/ws?token=$oldToken',
      );
      final ready = jsonDecode(
        (await socket.first.timeout(const Duration(seconds: 3))) as String,
      ) as Map<String, dynamic>;
      expect(ready['type'], 'ready');
      expect(host.connectedClients, 1);
      final socketClosed = socket.done;

      final newToken = await host.rotatePairingToken();
      expect(newToken, isNot(equals(oldToken)));
      await socketClosed.timeout(const Duration(seconds: 3));
      expect(host.connectedClients, 0);

      final rejected = await http.get(
        health,
        headers: {'X-CNKH-Token': oldToken},
      );
      expect(rejected.statusCode, HttpStatus.unauthorized);

      final accepted = await http.get(
        health,
        headers: {'X-CNKH-Token': newToken},
      );
      expect(accepted.statusCode, HttpStatus.ok);
    } finally {
      await host.stop();
      await database.close();
      await dir.delete(recursive: true);
    }
  });
}
