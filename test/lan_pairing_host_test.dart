import 'dart:convert';

import 'package:cnkh_pos_desktop/services/lan_pairing_host.dart';
import 'package:cnkh_pos_desktop/services/lan_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop pairing payload remains compatible with cnkh-sync v1 and expires', () {
    final raw = buildPairingPayload(
      baseUrl: 'http://192.168.1.20:8787',
      token: '0123456789abcdef0123456789abcdef',
      name: 'CNKH-PC',
    );

    expect(raw.startsWith(kPairingPrefix), isTrue);
    final payload = jsonDecode(raw.substring(kPairingPrefix.length)) as Map;
    expect(payload['iat'], isA<int>());
    expect(payload['exp'], isA<int>());
    expect((payload['exp'] as int) - (payload['iat'] as int), inInclusiveRange(419, 421));

    final cfg = parsePairingQr(raw);
    expect(cfg, isNotNull);
    expect(cfg!.normalizedBase, 'http://192.168.1.20:8787');
    expect(cfg.token, '0123456789abcdef0123456789abcdef');
    expect(cfg.name, 'CNKH-PC');
  });

  test('expired desktop pairing payload is rejected by current parser', () {
    final raw = buildPairingPayload(
      baseUrl: 'http://192.168.1.20:8787',
      token: '0123456789abcdef0123456789abcdef',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
    );

    expect(() => parsePairingQr(raw), throwsA(isA<PairingExpiredException>()));
  });
}
