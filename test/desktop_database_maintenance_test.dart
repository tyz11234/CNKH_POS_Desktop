import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cnkh_pos_desktop/db/app_database.dart';
import 'package:cnkh_pos_desktop/services/desktop_database_maintenance.dart';
import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'maintenance pause drains current work and holds new work until resume',
    () async {
      final maintenance = DesktopDatabaseMaintenance.shared;
      final entered = Completer<void>();
      final release = Completer<void>();
      var queuedStarted = false;
      try {
        final active = maintenance.run(() async {
          entered.complete();
          await release.future;
          return 'finished';
        });
        await entered.future;

        var pauseFinished = false;
        final pause = maintenance.pauseAndDrain().then((_) {
          pauseFinished = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(pauseFinished, isFalse);

        final queued = maintenance.run(() async {
          queuedStarted = true;
          return 'resumed';
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(queuedStarted, isFalse);

        release.complete();
        expect(await active, 'finished');
        await pause;
        expect(pauseFinished, isTrue);
        expect(queuedStarted, isFalse);

        maintenance.resume();
        expect(await queued, 'resumed');
        expect(queuedStarted, isTrue);
      } finally {
        if (!release.isCompleted) release.complete();
        maintenance.resume();
      }
    },
  );

  test(
    'stopAndDrain waits for an accepted LAN request body to finish',
    () async {
      AppDatabase.ensureFfi();
      final dir = await Directory.systemTemp.createTemp('cnkh-host-drain-');
      final database = AppDatabase.forTesting(
        '${dir.path}/desktop.db',
        seed: false,
      );
      final repo = PosRepository(database: database);
      final host = LanPairingHost.forTesting(
        repo,
        database: database,
        configuredPort: 0,
      );
      Socket? socket;
      try {
        await host.start();
        final token = await repo.getSetting('lan_host_token');
        socket = await Socket.connect(InternetAddress.loopbackIPv4, host.port);
        socket.write(
          'POST /api/v1/mutations HTTP/1.1\r\n'
          'Host: 127.0.0.1\r\n'
          'Content-Type: application/json\r\n'
          'X-CNKH-Token: $token\r\n'
          'Content-Length: 17\r\n'
          'Connection: close\r\n\r\n'
          '{"operations":',
        );
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        var stopped = false;
        final draining = host.stopAndDrain().then((_) => stopped = true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(stopped, isFalse);

        socket.write('[]}');
        await socket.flush();
        final response = await utf8.decoder
            .bind(socket)
            .join()
            .timeout(const Duration(seconds: 5));
        await draining.timeout(const Duration(seconds: 5));
        expect(response, contains('200 OK'));
        expect(response, contains('"acknowledged":[]'));
        expect(stopped, isTrue);
        expect(host.isRunning, isFalse);
      } finally {
        socket?.destroy();
        await host.stop();
        await database.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
