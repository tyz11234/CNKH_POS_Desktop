import 'dart:convert';
import 'dart:io' show HttpDate;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import '../sync_store.dart';

class MyInvoisException implements Exception {
  const MyInvoisException(this.statusCode, this.operation, {this.retryAfter});
  final int statusCode;
  final String operation;
  final String? retryAfter;
  @override String toString() => 'MyInvois $operation: HTTP $statusCode${retryAfter == null ? '' : ' (Retry-After: $retryAfter)'}';
}
class MyInvoisClient {
  MyInvoisClient({required this.environment, required this.credentials, http.Client? transport, DateTime Function()? now})
    : _http = transport ?? http.Client(), _now = now ?? DateTime.now {
    if (!['sandbox', 'production'].contains(environment)) throw ArgumentError('Invalid environment');
  }
  final String environment;
  final Future<Map<String, dynamic>> Function() credentials;
  final http.Client _http;
  final DateTime Function() _now;
  final _authLock = AsyncMutex();
  String? _accessToken;
  DateTime? _expires;
  DateTime? _retryNotBefore;
  String get baseUrl => environment == 'production' ? 'https://api.myinvois.hasil.gov.my' : 'https://preprod-api.myinvois.hasil.gov.my';
  void close() => _http.close();
  void clearToken() { _accessToken = null; _expires = null; }
  Future<void> authenticate() => _authLock.run(() async {
    final retry = _retryNotBefore;
    if (retry != null && retry.isAfter(_now())) throw StateError('MyInvois 暂时限流，请等待 ${retry.difference(_now()).inSeconds + 1} 秒后重试');
    if (_accessToken != null && _expires!.isAfter(_now().add(const Duration(seconds: 60)))) return;
    final cfg = await credentials();
    if ('${cfg['client_id'] ?? ''}'.isEmpty || '${cfg['client_secret'] ?? ''}'.isEmpty) throw StateError('请先保存 MyInvois 凭据');
    final request = http.Request('POST', Uri.parse('$baseUrl/connect/token'))
      ..followRedirects = false
      ..bodyFields = {
      'client_id': cfg['client_id'] as String, 'client_secret': cfg['client_secret'] as String,
      'grant_type': 'client_credentials', 'scope': 'InvoicingAPI',
      };
    final response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 30))).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) { _rememberRetry(response); throw MyInvoisException(response.statusCode, 'authentication', retryAfter: response.headers['retry-after']); }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token'];
    final expires = data['expires_in'];
    if (token is! String || token.isEmpty || expires is! num || expires <= 0) throw const FormatException('Invalid OAuth response');
    _accessToken = token; _expires = _now().add(Duration(seconds: expires.toInt()));
  });
  Future<Map<String, dynamic>> _request(String method, String path, {Map<String, dynamic>? body, int expected = 200}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await authenticate();
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..followRedirects = false
        ..headers.addAll({'Authorization': 'Bearer $_accessToken', 'Content-Type': 'application/json'});
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 30))).timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 && attempt == 0) { clearToken(); continue; }
      if (response.statusCode != expected) { _rememberRetry(response); throw MyInvoisException(response.statusCode, method, retryAfter: response.headers['retry-after']); }
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw const MyInvoisException(401, 'authentication');
  }
  void _rememberRetry(http.Response response) {
    final value = response.headers['retry-after'];
    if (value == null) {
      if (response.statusCode == 429) _retryNotBefore = _now().add(const Duration(seconds: 60));
      return;
    }
    final seconds = int.tryParse(value);
    if (seconds != null) { _retryNotBefore = _now().add(Duration(seconds: seconds < 0 ? 0 : seconds)); return; }
    try { _retryNotBefore = HttpDate.parse(value); } catch (_) { _retryNotBefore = _now().add(const Duration(seconds: 60)); }
  }
  static Future<Map<String, dynamic>> envelope(String invoiceNo, String json) async {
    final bytes = utf8.encode(json);
    if (bytes.length > 300 * 1024) throw StateError('单张 e-Invoice 超过 300 KB');
    final hash = await Sha256().hash(bytes);
    return {'documents': [{'format': 'JSON', 'codeNumber': invoiceNo, 'documentHash': hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), 'document': base64Encode(bytes)}]};
  }
  Future<Map<String, dynamic>> submitDocument(Map<String, dynamic> envelope) => _request('POST', '/api/v1.0/documentsubmissions/', body: envelope, expected: 202);
  Future<Map<String, dynamic>> queryStatus(String uid) => _request('GET', '/api/v1.0/documentsubmissions/${Uri.encodeComponent(uid)}?pageNo=1&pageSize=100');
  Future<Map<String, dynamic>> documentDetails(String uuid) => _request('GET', '/api/v1.0/documents/${Uri.encodeComponent(uuid)}/details');
  Future<Map<String, dynamic>> cancelDocument(String uuid, String reason) {
    if (reason.trim().isEmpty || reason.length > 300) throw ArgumentError('取消原因须为 1–300 字');
    return _request('PUT', '/api/v1.0/documents/state/${Uri.encodeComponent(uuid)}/state', body: {'status': 'cancelled', 'reason': reason.trim()});
  }
}
