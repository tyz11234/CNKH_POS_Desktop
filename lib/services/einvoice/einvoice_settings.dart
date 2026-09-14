import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import '../sync_store.dart';

/// The database holds authenticated ciphertext. Its key stays in OS secure storage.
abstract class EInvoiceKeyStore {
  Future<String?> read();
  Future<void> write(String value);
}
class OsEInvoiceKeyStore implements EInvoiceKeyStore {
  static const _storage = FlutterSecureStorage();
  static const _name = 'cnkh.myinvois.aes256.v1';
  @override Future<String?> read() => _storage.read(key: _name);
  @override Future<void> write(String value) => _storage.write(key: _name, value: value);
}
class EInvoiceSettingsStore {
  EInvoiceSettingsStore(this.db, {EInvoiceKeyStore? keys}) : keys = keys ?? OsEInvoiceKeyStore();
  final Database db;
  final EInvoiceKeyStore keys;
  static final _lock = AsyncMutex();
  final _cipher = AesGcm.with256bits();
  Future<SecretKey> _key({required bool create}) async {
    final existing = await keys.read();
    if (existing != null) return SecretKey(base64Decode(existing));
    if (!create) throw StateError('本机凭据密钥不可用，请重新输入 Client ID / Secret');
    final key = await _cipher.newSecretKey();
    await keys.write(base64Encode(await key.extractBytes()));
    return key;
  }
  Future<Map<String, dynamic>> load({String environment = 'sandbox', bool credentials = false}) => _lock.run(() async {
    _environment(environment);
    final rows = await db.query('e_invoice_settings', where: 'environment=?', whereArgs: [environment], orderBy: 'updated_at DESC, id ASC', limit: 1);
    if (rows.isEmpty) return {'environment': environment};
    final row = rows.single;
    final result = <String, dynamic>{'tin': row['tin'], 'brn': row['brn'], ...jsonDecode(row['profile_json'] as String) as Map<String, dynamic>, 'environment': environment};
    if (credentials && (row['credentials_cipher'] as String).isNotEmpty) {
      final box = jsonDecode(row['credentials_cipher'] as String) as Map<String, dynamic>;
      final plain = await _cipher.decrypt(SecretBox(base64Decode(box['data']), nonce: base64Decode(box['nonce']), mac: Mac(base64Decode(box['mac']))), secretKey: await _key(create: false), aad: utf8.encode(environment));
      result.addAll(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
    }
    return result;
  });
  Future<void> save(Map<String, dynamic> profile, {required String clientId, required String clientSecret}) => _lock.run(() async {
    final environment = profile['environment'] as String;
    _environment(environment);
    if (clientId.trim().isEmpty || clientSecret.isEmpty) throw StateError('Client ID / Secret 必填');
    final box = await _cipher.encrypt(utf8.encode(jsonEncode({'client_id': clientId.trim(), 'client_secret': clientSecret})), secretKey: await _key(create: true), aad: utf8.encode(environment));
    final safe = Map<String, dynamic>.from(profile)..remove('client_id')..remove('client_secret');
    await db.insert('e_invoice_settings', {
      'id': environment, 'environment': environment, 'tin': safe['tin'] ?? '', 'brn': safe['brn'] ?? '',
      'profile_json': jsonEncode(safe), 'client_id': '', 'client_secret': '',
      'credentials_cipher': jsonEncode({'data': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes)}),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
  static void _environment(String value) {
    if (value != 'sandbox' && value != 'production') throw ArgumentError('Invalid environment');
  }
}
