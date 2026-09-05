import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/product.dart';
import 'lan_sync.dart' show kPairingPrefix;
import 'pos_repository.dart';

class LanPairingOffer {
  const LanPairingOffer({
    required this.payload,
    required this.baseUrl,
    required this.token,
    required this.name,
  });

  final String payload;
  final String baseUrl;
  final String token;
  final String name;
}

String buildPairingPayload({
  required String baseUrl,
  required String token,
  String name = 'CNKH-PC',
}) {
  return '$kPairingPrefix${jsonEncode(<String, Object?>{
    'baseUrl': baseUrl,
    'token': token,
    'name': name,
  })}';
}

/// Process-lived LAN host for the published Mobile APK `cnkh-sync:v1` flow.
class LanPairingHost {
  LanPairingHost._(
    this.repo, {
    AppDatabase? database,
    this.configuredPort = 8787,
    this.name = 'CNKH-PC',
  }) : _db = database ?? AppDatabase.instance;

  static LanPairingHost? _shared;

  static LanPairingHost shared(PosRepository repo) {
    return _shared ??= LanPairingHost._(repo);
  }

  static const String _tokenSetting = 'lan_host_token';

  final PosRepository repo;
  final AppDatabase _db;
  final int configuredPort;
  final String name;

  HttpServer? _server;
  String _localIp = '127.0.0.1';
  String _token = '';
  final Set<WebSocket> _sockets = <WebSocket>{};
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  int _eventSeq = 0;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? configuredPort;
  String get localIp => _localIp;

  Future<void> start() async {
    if (_server != null) return;

    _token = await _ensureToken();
    _localIp = await findBestLocalIPv4();

    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        configuredPort,
        shared: false,
      );
      _server = server;
      unawaited(
        server.forEach((request) async {
          try {
            await _handle(request);
          } on FormatException catch (e) {
            await _safeJson(
              request.response,
              HttpStatus.badRequest,
              <String, Object?>{
                'ok': false,
                'error': 'invalid_request',
                'message': e.message,
              },
            );
          } catch (e) {
            await _safeJson(
              request.response,
              HttpStatus.internalServerError,
              <String, Object?>{
                'ok': false,
                'error': 'internal_error',
                'message': '$e',
              },
            );
          }
        }),
      );
    } on SocketException catch (e) {
      throw StateError(
        '无法启动局域网同步服务 :$configuredPort。端口可能被占用或被系统阻止。$e',
      );
    }
  }

  Future<LanPairingOffer> prepareOffer() async {
    await start();
    // Refresh the advertised address every time the pairing page opens.
    // The PC may have joined Wi-Fi after app startup or changed networks.
    _localIp = await findBestLocalIPv4();
    if (_localIp == '127.0.0.1') {
      throw StateError('未找到局域网 IPv4 地址，请确认电脑已连接与手机相同的 Wi-Fi。');
    }
    final baseUrl = 'http://$_localIp:$port';
    return LanPairingOffer(
      payload: buildPairingPayload(
        baseUrl: baseUrl,
        token: _token,
        name: name,
      ),
      baseUrl: baseUrl,
      token: _token,
      name: name,
    );
  }

  Future<void> stop() async {
    for (final socket in _sockets.toList()) {
      try {
        await socket.close(WebSocketStatus.goingAway, 'Desktop shutting down');
      } catch (_) {}
    }
    _sockets.clear();
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<String> _ensureToken() async {
    var token = (await repo.getSetting(_tokenSetting)).trim();
    if (token.length >= 24) return token;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    token = base64UrlEncode(bytes).replaceAll('=', '');
    await repo.setSetting(_tokenSetting, token);
    return token;
  }

  Future<void> _handle(HttpRequest request) async {
    if (!_authorized(request)) {
      await _json(
        request.response,
        HttpStatus.unauthorized,
        <String, Object?>{'ok': false, 'error': 'unauthorized'},
      );
      return;
    }

    final path = request.uri.path;

    if (request.method == 'GET' && path == '/api/v1/health') {
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'ok': true,
        'service': 'CNKH POS Desktop',
        'protocol': 1,
        'time': DateTime.now().toIso8601String(),
        'name': name,
      });
      return;
    }

    if (request.method == 'GET' && path == '/api/v1/ws') {
      await _handleWebSocket(request);
      return;
    }

    if (request.method == 'GET' && path == '/api/v1/products') {
      await _getProducts(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/customers') {
      await _getCustomers(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/categories') {
      await _getCategories(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/sales') {
      await _getSales(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/v1/sales') {
      await _postSales(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/v1/notify') {
      final body = await _readJson(request);
      _publish(<String, Object?>{
        ...body,
        'type': body['type']?.toString() ?? 'sale',
      });
      await _json(
        request.response,
        HttpStatus.ok,
        <String, Object?>{'ok': true},
      );
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/events/poll') {
      final after =
          int.tryParse(request.uri.queryParameters['after'] ?? '') ?? 0;
      final items = _events
          .where((e) => ((e['seq'] as int?) ?? 0) > after)
          .toList(growable: false);
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'ok': true,
        'items': items,
        'events': items,
        'cursor': _eventSeq,
      });
      return;
    }
    if (request.method == 'POST' && path == '/api/v1/categories') {
      await _postCategories(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/v1/barcode_queue') {
      await _postBarcodeQueue(request);
      return;
    }

    await _json(
      request.response,
      HttpStatus.notFound,
      <String, Object?>{'ok': false, 'error': 'not_found'},
    );
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value('X-CNKH-Token')?.trim() ?? '';
    final query = request.uri.queryParameters['token']?.trim() ?? '';
    return _token.isNotEmpty && (header == _token || query == _token);
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      await _json(
        request.response,
        HttpStatus.badRequest,
        <String, Object?>{
          'ok': false,
          'error': 'websocket_upgrade_required',
        },
      );
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = const Duration(seconds: 20);
    _sockets.add(socket);
    socket.add(jsonEncode(<String, Object?>{'type': 'ready'}));
    socket.listen(
      (message) {
        if (message == 'ping') {
          socket.add(jsonEncode(<String, Object?>{'type': 'pong'}));
        }
      },
      onDone: () => _sockets.remove(socket),
      onError: (_) => _sockets.remove(socket),
      cancelOnError: true,
    );
  }

  Future<void> _getProducts(HttpRequest request) async {
    final db = await _db.db;
    final rows = await db.query('products', orderBy: 'name_zh');
    final items = <Map<String, Object?>>[
      for (final m in rows)
        <String, Object?>{
          'pc_id': m['id'],
          'name_zh': m['name_zh'],
          'name_en': m['name_en'],
          'sku': m['sku'],
          'barcode': m['barcode'],
          'price_cents': m['price_cents'],
          'cost_cents': m['cost_cents'],
          'stock': m['stock'],
          'unit': m['unit'],
          'category': m['category'],
          'is_deleted': m['is_deleted'],
          'reorder_level': m['reorder_level'],
          'has_image': false,
          'updated_at': '',
        },
    ];
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
    });
  }

  Future<void> _getCustomers(HttpRequest request) async {
    final db = await _db.db;
    final rows = await db.query('customers', orderBy: 'name');
    final items = <Map<String, Object?>>[
      for (final m in rows)
        <String, Object?>{
          'pc_id': m['id'],
          'name': m['name'],
          'phone': m['phone'],
          'notes': m['notes'],
          'is_deleted': m['is_deleted'],
          'updated_at': '',
        },
    ];
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
    });
  }

  Future<void> _getCategories(HttpRequest request) async {
    final db = await _db.db;
    final rows = await db.query('categories', orderBy: 'name');
    final items = <Map<String, Object?>>[
      for (final m in rows)
        <String, Object?>{
          'pc_id': m['id'],
          'name': m['name'],
          'is_deleted': m['is_deleted'],
          'updated_at': m['updated_at'],
        },
    ];
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
    });
  }

  Future<void> _getSales(HttpRequest request) async {
    final db = await _db.db;
    final rows = await db.query('sales', orderBy: 'sold_at ASC');
    final items = <Map<String, Object?>>[];
    for (final m in rows) {
      final rawLines = (m['lines_json'] as String?) ?? '[]';
      Object? lines;
      try {
        lines = jsonDecode(rawLines);
      } catch (_) {
        lines = <Object?>[];
      }
      items.add(<String, Object?>{
        'pc_id': m['id'],
        'receipt_no': m['receipt_no'],
        'sold_at': m['sold_at'],
        'cashier': m['cashier'],
        'payment_method': m['payment_method'],
        'deposit_method': m['deposit_method'],
        'customer_name': m['customer_name'],
        'customer_phone': m['customer_phone'],
        'subtotal_cents': m['subtotal_cents'],
        'discount_cents': ((m['item_discount_cents'] as int?) ?? 0) +
            ((m['order_discount_cents'] as int?) ?? 0),
        'order_discount_cents': m['order_discount_cents'],
        'total_cents': m['total_cents'],
        'paid_cents': m['paid_cents'],
        'change_cents': m['change_cents'],
        'lines': lines,
        'is_deleted': m['voided'],
      });
    }
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
    });
  }

  Future<void> _postSales(HttpRequest request) async {
    final body = await _readJson(request);
    final rawSales = body['sales'];
    if (rawSales is! List) {
      throw const FormatException('sales must be a list');
    }

    final db = await _db.db;
    var imported = 0;
    var skipped = 0;

    for (final raw in rawSales) {
      if (raw is! Map) {
        skipped++;
        continue;
      }
      final sale = Map<String, Object?>.from(raw);
      final receipt = sale['receipt_no']?.toString().trim() ?? '';
      if (receipt.isEmpty) {
        skipped++;
        continue;
      }

      final existing = await db.query(
        'sales',
        columns: <String>['id'],
        where: 'receipt_no=?',
        whereArgs: <Object?>[receipt],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        skipped++;
        continue;
      }

      final lines = sale['lines'] is List
          ? List<Object?>.from(sale['lines']! as List)
          : <Object?>[];
      final subtotal = _asInt(sale['subtotal_cents']);
      final orderDiscount = _asInt(sale['order_discount_cents']);
      final totalDiscount = _asInt(sale['discount_cents']);
      final itemDiscount = max(0, totalDiscount - orderDiscount);
      final total = _asInt(sale['total_cents']);
      final paid = _asInt(sale['paid_cents'], fallback: total);
      final payment = sale['payment_method']?.toString() ?? 'CASH';
      final outstanding = payment.toUpperCase() == 'CREDIT'
          ? max(0, total - paid)
          : 0;
      final now = DateTime.now().toIso8601String();

      await db.transaction((txn) async {
        await txn.insert('sales', <String, Object?>{
          'id': AppDatabase.newId(),
          'receipt_no': receipt,
          'sold_at': sale['sold_at']?.toString() ?? now,
          'cashier': sale['cashier']?.toString() ?? 'mobile-sync',
          'payment_method': payment,
          'deposit_method': sale['deposit_method']?.toString(),
          'customer_id': null,
          'customer_name': sale['customer_name']?.toString(),
          'customer_phone': sale['customer_phone']?.toString(),
          'subtotal_cents': subtotal,
          'item_discount_cents': itemDiscount,
          'order_discount_cents': orderDiscount,
          'rounding_cents': 0,
          'total_cents': total,
          'paid_cents': paid,
          'change_cents': _asInt(sale['change_cents']),
          'credit_outstanding_cents': outstanding,
          'lines_json': jsonEncode(lines),
          'voided': 0,
          'void_note': '',
          'synced_at': now,
        });

        for (final rawLine in lines) {
          if (rawLine is! Map) continue;
          final line = Map<String, Object?>.from(rawLine);
          var productId = (line['productId'] ?? line['product_id'])
                  ?.toString()
                  .trim() ??
              '';
          if (productId.startsWith('pc-')) {
            productId = productId.substring(3);
          }
          final qty =
              _asDouble(line['qty'] ?? line['quantity'], fallback: 1);
          if (productId.isEmpty || qty <= 0) continue;
          await txn.rawUpdate(
            'UPDATE products SET stock=stock-? WHERE id=?',
            <Object?>[qty, productId],
          );
        }
      });

      imported++;
      _publish(<String, Object?>{
        'type': 'sale',
        'source': 'phone',
        'receipt_no': receipt,
      });
    }

    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'imported': imported,
      'skipped': skipped,
    });
  }

  Future<void> _postCategories(HttpRequest request) async {
    final body = await _readJson(request);
    final rawItems = body['items'];
    if (rawItems is! List) {
      throw const FormatException('items must be a list');
    }
    var saved = 0;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      await repo.upsertCategory(Category(id: '', name: name));
      saved++;
    }
    _publish(<String, Object?>{'type': 'category'});
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'saved': saved,
    });
  }

  Future<void> _postBarcodeQueue(HttpRequest request) async {
    final body = await _readJson(request);
    final rawItems = body['items'];
    if (rawItems is! List) {
      throw const FormatException('items must be a list');
    }
    var saved = 0;
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      var productId = raw['product_id']?.toString().trim() ?? '';
      if (productId.startsWith('pc-')) {
        productId = productId.substring(3);
      }
      final barcode = raw['barcode']?.toString() ?? '';
      final productName = raw['product_name']?.toString() ?? '';
      if (barcode.isEmpty || productName.isEmpty) continue;
      await repo.enqueueBarcodePrint(
        productId: productId,
        barcode: barcode,
        productName: productName,
        sku: raw['sku']?.toString() ?? '',
        priceCents: _asInt(raw['price_cents']),
        copies: _asInt(raw['copies'], fallback: 1),
      );
      saved++;
    }
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'saved': saved,
    });
  }

  void _publish(Map<String, Object?> event) {
    final withSeq = <String, Object?>{
      ...event,
      'seq': ++_eventSeq,
      'time': DateTime.now().toIso8601String(),
    };
    _events.add(withSeq);
    if (_events.length > 200) {
      _events.removeRange(0, _events.length - 200);
    }
    final message = jsonEncode(withSeq);
    for (final socket in _sockets.toList()) {
      try {
        socket.add(message);
      } catch (_) {
        _sockets.remove(socket);
      }
    }
  }

  Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.trim().isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('JSON object required');
    return Map<String, Object?>.from(decoded);
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _safeJson(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    try {
      await _json(response, status, body);
    } on StateError {
      // Response was already committed by another route.
    }
  }

  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _asDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static Future<String> findBestLocalIPv4() async {
    List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
    } on SocketException {
      return '127.0.0.1';
    }

    final candidates = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (!address.isLoopback && !value.startsWith('169.254.')) {
          candidates.add(value);
        }
      }
    }
    if (candidates.isEmpty) return '127.0.0.1';

    candidates.sort((a, b) => _ipScore(b).compareTo(_ipScore(a)));
    return candidates.first;
  }

  static int _ipScore(String ip) {
    if (ip.startsWith('192.168.')) return 300;
    if (ip.startsWith('10.')) return 220;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      final second = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (second != null && second >= 16 && second <= 31) return 210;
    }
    return 100;
  }
}
