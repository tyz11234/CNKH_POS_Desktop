import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/product.dart';
import 'lan_sync.dart' show kPairingPrefix;
import 'pos_repository.dart';
import 'lan_mutations.dart';
import 'sale_reversal.dart';
import 'sync_store.dart';

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
  DateTime? expiresAt,
}) {
  final now = DateTime.now().toUtc();
  final expiry = (expiresAt ?? now.add(const Duration(minutes: 7))).toUtc();
  return '$kPairingPrefix${jsonEncode(<String, Object?>{
    'baseUrl': baseUrl,
    'token': token,
    'name': name,
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': expiry.millisecondsSinceEpoch ~/ 1000,
  })}';
}

/// Desktop is the authoritative LAN host for Mobile clients.
/// Database triggers keep a monotonic change log so catalog/sales endpoints can
/// serve real incremental updates without changing the POS business tables.
class LanPairingHost {
  LanPairingHost._(
    this.repo, {
    AppDatabase? database,
    this.configuredPort = 8787,
    this.name = 'CNKH-PC',
  }) : _db = database ?? repo.database;

  LanPairingHost.forTesting(
    this.repo, {
    required AppDatabase database,
    this.configuredPort = 0,
    this.name = 'CNKH-PC',
  }) : _db = database;
  static final Expando<LanPairingHost> _hosts = Expando<LanPairingHost>();

  static LanPairingHost shared(PosRepository repo) {
    return _hosts[repo.database] ??= LanPairingHost._(repo);
  }

  static const String _tokenSetting = 'lan_host_token';

  final PosRepository repo;
  final AppDatabase _db;
  final int configuredPort;
  final String name;

  HttpServer? _server;
  Timer? _changePoll;
  String _localIp = '127.0.0.1';
  String _token = '';
  final Set<WebSocket> _sockets = <WebSocket>{};
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  final StreamController<int> _connectionCounts =
      StreamController<int>.broadcast(sync: true);
  int _eventSeq = 0;
  int _lastChangeSeq = 0;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? configuredPort;
  String get localIp => _localIp;
  int get connectedClients => _sockets.length;
  final _dataChanges = StreamController<void>.broadcast();
  Stream<void> get dataChanges => _dataChanges.stream;
  Stream<int> get connectionCounts => _connectionCounts.stream;

  Future<void>? _starting;
  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    if (_server != null) return;

    _token = await _ensureToken();
    _localIp = await findBestLocalIPv4();
    final db = await _db.db;
    await _ensureChangeTracking(db);
    _lastChangeSeq = await _latestChangeSeq(db);

    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        configuredPort,
        shared: false,
      );
      _server = server;
      _changePoll = Timer.periodic(const Duration(milliseconds: 500), (_) {
        unawaited(_pollDatabaseChanges());
      });
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

  Future<String> rotatePairingToken() async {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    await repo.setSetting(_tokenSetting, token);
    _token = token;
    for (final socket in _sockets.toList()) {
      try {
        await socket.close(WebSocketStatus.policyViolation, 'Pairing token rotated');
      } catch (_) {}
    }
    _sockets.clear();
    _emitConnectionCount();
    return token;
  }

  Future<void> forceBroadcast() async {
    final db = await _db.db;
    final cursor = await _latestChangeSeq(db);
    _publish(<String, Object?>{
      'type': 'reconcile',
      'reason': 'force_reconcile',
      'full': true,
      'data_cursor': cursor,
    });
  }

  Future<void> stop() async {
    try {
      await _starting;
    } catch (_) {}
    _changePoll?.cancel();
    _changePoll = null;
    for (final socket in _sockets.toList()) {
      try {
        await socket.close(WebSocketStatus.goingAway, 'Desktop shutting down');
      } catch (_) {}
    }
    _sockets.clear();
    _emitConnectionCount();
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

  Future<void> _ensureChangeTracking(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS lan_sync_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  entity_name TEXT NOT NULL DEFAULT '',
  deleted INTEGER NOT NULL DEFAULT 0,
  changed_at TEXT NOT NULL
)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lan_sync_changes_entity_seq '
      'ON lan_sync_changes(entity, seq)',
    );
    await db.execute('''
CREATE TABLE IF NOT EXISTS lan_sync_mobile_sales (
  client_sale_id TEXT PRIMARY KEY,
  sale_id TEXT NOT NULL,
  original_receipt TEXT NOT NULL,
  canonical_receipt TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');

    const nowSql = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";
    final triggers = <String>[
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_products_ai AFTER INSERT ON products BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('product',NEW.id,NEW.name_zh,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_products_au AFTER UPDATE ON products BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('product',NEW.id,NEW.name_zh,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_products_ad AFTER DELETE ON products BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('product',OLD.id,OLD.name_zh,1,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_customers_ai AFTER INSERT ON customers BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('customer',NEW.id,NEW.name,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_customers_au AFTER UPDATE ON customers BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('customer',NEW.id,NEW.name,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_customers_ad AFTER DELETE ON customers BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('customer',OLD.id,OLD.name,1,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_suppliers_ai AFTER INSERT ON suppliers BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('supplier',NEW.id,NEW.name,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_suppliers_au AFTER UPDATE ON suppliers BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('supplier',NEW.id,NEW.name,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_suppliers_ad AFTER DELETE ON suppliers BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('supplier',OLD.id,OLD.name,1,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_categories_ai AFTER INSERT ON categories BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('category',NEW.id,NEW.name,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_categories_au AFTER UPDATE ON categories BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('category',NEW.id,NEW.name,NEW.is_deleted,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_categories_ad AFTER DELETE ON categories BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('category',OLD.id,OLD.name,1,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_sales_ai AFTER INSERT ON sales BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('sale',NEW.id,NEW.receipt_no,NEW.voided,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_sales_au AFTER UPDATE ON sales BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('sale',NEW.id,NEW.receipt_no,NEW.voided,$nowSql);
      END''',
      '''CREATE TRIGGER IF NOT EXISTS lan_sync_sales_ad AFTER DELETE ON sales BEGIN
        INSERT INTO lan_sync_changes(entity,entity_id,entity_name,deleted,changed_at)
        VALUES('sale',OLD.id,OLD.receipt_no,1,$nowSql);
      END''',
    ];
    for (final sql in triggers) {
      await db.execute(sql);
    }

    if (await _latestChangeSeq(db) == 0) {
      await db.insert('lan_sync_changes', <String, Object?>{
        'entity': 'meta',
        'entity_id': 'baseline',
        'entity_name': 'baseline',
        'deleted': 0,
        'changed_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Future<int> _latestChangeSeq(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(seq),0) AS seq FROM lan_sync_changes',
    );
    return (rows.first['seq'] as num?)?.toInt() ?? 0;
  }

  Future<void> _pollDatabaseChanges() async {
    if (_server == null) return;
    try {
      final db = await _db.db;
      final rows = await db.query(
        'lan_sync_changes',
        where: 'seq>?',
        whereArgs: <Object?>[_lastChangeSeq],
        orderBy: 'seq ASC',
        limit: 500,
      );
      if (rows.isEmpty) return;

      var hasCatalog = false;
      var hasSale = false;
      var maxSeq = _lastChangeSeq;
      for (final row in rows) {
        final seq = (row['seq'] as num?)?.toInt() ?? 0;
        if (seq > maxSeq) maxSeq = seq;
        final entity = row['entity']?.toString() ?? '';
        if (entity == 'sale') {
          hasSale = true;
        } else if (entity != 'meta') {
          hasCatalog = true;
        }
      }
      _lastChangeSeq = maxSeq;
      _dataChanges.add(null);
      if (hasCatalog) {
        _publish(<String, Object?>{
          'type': 'catalog',
          'data_cursor': maxSeq,
        });
      }
      if (hasSale) {
        _publish(<String, Object?>{'type': 'sale', 'data_cursor': maxSeq});
      }
    } catch (_) {
      // A failed change poll must never stop the LAN server.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (!_authorized(request)) {
      await _json(request.response, HttpStatus.unauthorized, <String, Object?>{
        'ok': false,
        'error': 'unauthorized',
      });
      return;
    }

    final path = request.uri.path;

    if (request.method == 'GET' && path == '/api/v1/health') {
      final db = await _db.db;
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'ok': true,
        'service': 'CNKH POS Desktop',
        'protocol': 1,
        'capabilities': [
          'mutations_v1',
          'stable_ids',
          'void_sales',
          'cost_snapshot',
          'suppliers_v1',
          'product_images_v1',
          'purchases_v1',
          'barcode_queue_idempotency',
          'einvoice_status_v1',
        ],
        'stock_policy': await repo.stockPolicy(),
        'role': 'host',
        'time': DateTime.now().toIso8601String(),
        'name': name,
        'clients': connectedClients,
        'cursor': await _latestChangeSeq(db),
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
    if (request.method == 'GET' &&
        request.uri.pathSegments.length == 4 &&
        request.uri.pathSegments[0] == 'api' &&
        request.uri.pathSegments[1] == 'v1' &&
        request.uri.pathSegments[2] == 'product_images') {
      await _getProductImage(request, request.uri.pathSegments[3]);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/customers') {
      await _getCustomers(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/suppliers') {
      await _getSuppliers(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/categories') {
      await _getCategories(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/purchases') {
      await _getPurchases(request);
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/einvoices') {
      final db = await _db.db;
      final after = request.uri.queryParameters['after'] ?? '';
      final rows = await db.rawQuery('''SELECT d.id AS document_id, d.sale_id,
        COALESCE(m.client_sale_id,'') AS client_sale_id, d.invoice_no AS receipt_no,
        d.environment, d.status, d.updated_at FROM e_invoice_documents d
        LEFT JOIN lan_sync_mobile_sales m ON m.sale_id=d.sale_id
        WHERE d.id>? ORDER BY d.id LIMIT 200''', [after]);
      await _json(request.response, HttpStatus.ok, {'items': rows, 'has_more': rows.length == 200, 'next': rows.isEmpty ? after : rows.last['document_id']});
      return;
    }
    if (request.method == 'GET' && path == '/api/v1/sales') {
      await _getSales(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/v1/mutations') {
      final body = await _readJson(request);
      final operations = body['operations'];
      if (operations is! List) {
        throw const FormatException('operations must be a list');
      }
      final db = await _db.db;
      final ack = <String>[];
      String? error;
      String? failed;
      for (final raw in operations) {
        final op = Map<String, dynamic>.from(raw as Map);
        try {
          await applyLanMutation(db, op);
          ack.add(op['id'] as String);
        } catch (e) {
          error = '$e';
          failed = op['id']?.toString();
          break;
        }
      }
      await _json(request.response, HttpStatus.ok, {
        'ok': error == null,
        'acknowledged': ack,
        'failed_id': failed,
        'error': error,
      });
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
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'ok': true,
      });
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

    await _json(request.response, HttpStatus.notFound, <String, Object?>{
      'ok': false,
      'error': 'not_found',
    });
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value('X-CNKH-Token')?.trim() ?? '';
    final query = request.uri.queryParameters['token']?.trim() ?? '';
    return _token.isNotEmpty && (header == _token || query == _token);
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      await _json(request.response, HttpStatus.badRequest, <String, Object?>{
        'ok': false,
        'error': 'websocket_upgrade_required',
      });
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    socket.pingInterval = const Duration(seconds: 20);
    _sockets.add(socket);
    _emitConnectionCount();
    socket.add(jsonEncode(<String, Object?>{'type': 'ready', 'role': 'host'}));
    socket.listen(
      (message) {
        if (_isPingMessage(message)) {
          socket.add(jsonEncode(<String, Object?>{'type': 'pong'}));
        }
      },
      onDone: () {
        _sockets.remove(socket);
        _emitConnectionCount();
      },
      onError: (_) {
        _sockets.remove(socket);
        _emitConnectionCount();
      },
      cancelOnError: true,
    );
  }

  bool _isPingMessage(Object? message) {
    if (message == 'ping') return true;
    if (message is! String) return false;
    try {
      final data = jsonDecode(message);
      return data is Map && data['type'] == 'ping';
    } catch (_) {
      return false;
    }
  }

  void _emitConnectionCount() {
    if (!_connectionCounts.isClosed) {
      _connectionCounts.add(_sockets.length);
    }
  }

  int _requestedCursor(HttpRequest request) {
    return int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;
  }

  Future<Map<String, Map<String, Object?>>> _changesFor(
    Database db,
    String entity,
    int since,
  ) async {
    if (since <= 0) return <String, Map<String, Object?>>{};
    final rows = await db.query(
      'lan_sync_changes',
      where: 'entity=? AND seq>?',
      whereArgs: <Object?>[entity, since],
      orderBy: 'seq ASC',
    );
    final latestById = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final id = row['entity_id']?.toString() ?? '';
      if (id.isNotEmpty) latestById[id] = row;
    }
    return latestById;
  }

  Future<void> _getProducts(HttpRequest request) async {
    final db = await _db.db;
    final since = _requestedCursor(request);
    final cursor = await _latestChangeSeq(db);
    final items = <Map<String, Object?>>[];

    if (since <= 0) {
      final rows = await db.query('products', orderBy: 'name_zh');
      for (final row in rows) {
        items.add(_productPayload(row));
      }
    } else {
      final changes = await _changesFor(db, 'product', since);
      for (final entry in changes.entries) {
        final change = entry.value;
        final rows = await db.query(
          'products',
          where: 'id=?',
          whereArgs: <Object?>[entry.key],
          limit: 1,
        );
        if (rows.isEmpty) {
          items.add(<String, Object?>{
            'pc_id': entry.key,
            'name_zh': change['entity_name'] ?? '',
            'name_en': '',
            'sku': '',
            'barcode': '',
            'price_cents': 0,
            'cost_cents': 0,
            'stock': 0,
            'unit': 'pcs',
            'category': '',
            'is_deleted': 1,
            'reorder_level': 0,
            'has_image': false,
            'updated_at': change['changed_at'] ?? '',
          });
        } else {
          items.add(
            _productPayload(
              rows.first,
              updatedAt: change['changed_at']?.toString() ?? '',
            ),
          );
        }
      }
    }

    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
      'cursor': cursor,
    });
  }

  Map<String, Object?> _productPayload(
    Map<String, Object?> m, {
    String updatedAt = '',
  }) {
    final imagePath = m['image_path']?.toString().trim() ?? '';
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    return <String, Object?>{
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
      'has_image': hasImage,
      'updated_at': updatedAt,
    };
  }

  Future<void> _getProductImage(HttpRequest request, String productId) async {
    final db = await _db.db;
    final rows = await db.query(
      'products',
      where: 'id=? AND is_deleted=0',
      whereArgs: <Object?>[productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _json(request.response, HttpStatus.notFound, <String, Object?>{
        'ok': false,
        'error': 'product_not_found',
      });
      return;
    }
    final imagePath = rows.first['image_path']?.toString().trim() ?? '';
    if (imagePath.isEmpty) {
      await _json(request.response, HttpStatus.notFound, <String, Object?>{
        'ok': false,
        'error': 'image_not_found',
      });
      return;
    }
    final file = File(imagePath);
    if (!await file.exists()) {
      await _json(request.response, HttpStatus.notFound, <String, Object?>{
        'ok': false,
        'error': 'image_not_found',
      });
      return;
    }
    final bytes = await file.readAsBytes();
    final name = file.uri.pathSegments.isEmpty ? '' : file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1).toLowerCase()
        : 'jpg';
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'product_id': productId,
      'ext': ext,
      'bytes': bytes.length,
      'base64': base64Encode(bytes),
    });
  }

  Future<void> _getCustomers(HttpRequest request) async {
    final db = await _db.db;
    final since = _requestedCursor(request);
    final cursor = await _latestChangeSeq(db);
    final items = <Map<String, Object?>>[];

    if (since <= 0) {
      final rows = await db.query('customers', orderBy: 'name');
      for (final row in rows) {
        items.add(_customerPayload(row));
      }
    } else {
      final changes = await _changesFor(db, 'customer', since);
      for (final entry in changes.entries) {
        final change = entry.value;
        final rows = await db.query(
          'customers',
          where: 'id=?',
          whereArgs: <Object?>[entry.key],
          limit: 1,
        );
        if (rows.isEmpty) {
          items.add(<String, Object?>{
            'pc_id': entry.key,
            'name': change['entity_name'] ?? '',
            'phone': '',
            'notes': '',
            'is_deleted': 1,
            'updated_at': change['changed_at'] ?? '',
          });
        } else {
          items.add(
            _customerPayload(
              rows.first,
              updatedAt: change['changed_at']?.toString() ?? '',
            ),
          );
        }
      }
    }

    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
      'cursor': cursor,
    });
  }

  Map<String, Object?> _customerPayload(
    Map<String, Object?> m, {
    String updatedAt = '',
  }) {
    return <String, Object?>{
      'pc_id': m['id'],
      'name': m['name'],
      'phone': m['phone'],
      'notes': m['notes'],
      'is_deleted': m['is_deleted'],
      'updated_at': updatedAt,
    };
  }

  Future<void> _getSuppliers(HttpRequest request) async {
    final db = await _db.db;
    final since = _requestedCursor(request);
    final cursor = await _latestChangeSeq(db);
    final items = <Map<String, Object?>>[];

    if (since <= 0) {
      final rows = await db.query('suppliers', orderBy: 'name');
      for (final row in rows) {
        items.add(_supplierPayload(row));
      }
    } else {
      final changes = await _changesFor(db, 'supplier', since);
      for (final entry in changes.entries) {
        final change = entry.value;
        final rows = await db.query(
          'suppliers',
          where: 'id=?',
          whereArgs: <Object?>[entry.key],
          limit: 1,
        );
        if (rows.isEmpty) {
          items.add(<String, Object?>{
            'pc_id': entry.key,
            'name': change['entity_name'] ?? '',
            'phone': '',
            'email': '',
            'notes': '',
            'is_deleted': 1,
            'updated_at': change['changed_at'] ?? '',
          });
        } else {
          items.add(
            _supplierPayload(
              rows.first,
              updatedAt: change['changed_at']?.toString() ?? '',
            ),
          );
        }
      }
    }

    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
      'cursor': cursor,
    });
  }

  Map<String, Object?> _supplierPayload(
    Map<String, Object?> m, {
    String updatedAt = '',
  }) {
    return <String, Object?>{
      'pc_id': m['id'],
      'name': m['name'],
      'phone': m['phone'],
      'email': m['email'],
      'notes': m['notes'],
      'is_deleted': m['is_deleted'],
      'updated_at': updatedAt,
    };
  }

  Future<void> _getCategories(HttpRequest request) async {
    final db = await _db.db;
    final since = _requestedCursor(request);
    final cursor = await _latestChangeSeq(db);
    final items = <Map<String, Object?>>[];

    if (since <= 0) {
      final rows = await db.query('categories', orderBy: 'name');
      for (final row in rows) {
        items.add(_categoryPayload(row));
      }
    } else {
      final changes = await _changesFor(db, 'category', since);
      for (final entry in changes.entries) {
        final change = entry.value;
        final rows = await db.query(
          'categories',
          where: 'id=?',
          whereArgs: <Object?>[entry.key],
          limit: 1,
        );
        if (rows.isEmpty) {
          items.add(<String, Object?>{
            'pc_id': entry.key,
            'name': change['entity_name'] ?? '',
            'is_deleted': 1,
            'updated_at': change['changed_at'] ?? '',
          });
        } else {
          items.add(
            _categoryPayload(
              rows.first,
              updatedAt: change['changed_at']?.toString(),
            ),
          );
        }
      }
    }

    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
      'cursor': cursor,
    });
  }

  Map<String, Object?> _categoryPayload(
    Map<String, Object?> m, {
    String? updatedAt,
  }) {
    return <String, Object?>{
      'pc_id': m['id'],
      'name': m['name'],
      'is_deleted': m['is_deleted'],
      'updated_at': updatedAt ?? m['updated_at'] ?? '',
    };
  }

  Future<void> _getPurchases(HttpRequest request) async {
    final db = await _db.db;
    final rows = await db.query('purchases', orderBy: 'purchased_at ASC');
    final items = <Map<String, Object?>>[];
    for (final row in rows) {
      items.add(_purchasePayload(row));
    }
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
      'cursor': await _latestChangeSeq(db),
    });
  }

  Map<String, Object?> _purchasePayload(Map<String, Object?> m) {
    Object? lines;
    try {
      lines = jsonDecode(m['lines_json']?.toString() ?? '[]');
    } catch (_) {
      lines = <Object?>[];
    }
    return <String, Object?>{
      'pc_id': m['id'],
      'purchase_no': m['purchase_no'],
      'supplier_id': m['supplier_id'],
      'supplier_name': m['supplier_name'],
      'purchased_at': m['purchased_at'],
      'total_cents': m['total_cents'],
      'lines': lines,
      'notes': m['notes'],
      'invoice_no': m['invoice_no'],
      'invoice_date': m['invoice_date'],
      'discount_cents': m['discount_cents'],
      'tax_cents': m['tax_cents'],
      'delivery_fee_cents': m['delivery_fee_cents'],
      'other_fee_cents': m['other_fee_cents'],
      'source': m['source'],
      'draft_id': m['draft_id'],
      'ocr_raw_text': m['ocr_raw_text'],
      'reversed': m['reversed'],
      'reversed_at': m['reversed_at'],
      'reversed_by': m['reversed_by'],
      'reversal_reason': m['reversal_reason'],
      'reversal_notes': m['reversal_notes'],
      'is_deleted': 0,
    };
  }

  Future<void> _getSales(HttpRequest request) async {
    final db = await _db.db;
    final since = _requestedCursor(request);
    final cursor = await _latestChangeSeq(db);
    final items = <Map<String, Object?>>[];

    if (since <= 0) {
      final rows = await db.query('sales', orderBy: 'sold_at ASC');
      for (final row in rows) {
        items.add(_salePayload(row));
      }
    } else {
      final changes = await _changesFor(db, 'sale', since);
      for (final entry in changes.entries) {
        final change = entry.value;
        final rows = await db.query(
          'sales',
          where: 'id=?',
          whereArgs: <Object?>[entry.key],
          limit: 1,
        );
        if (rows.isEmpty) {
          items.add(<String, Object?>{
            'pc_id': entry.key,
            'receipt_no': change['entity_name'] ?? '',
            'sold_at': '',
            'is_deleted': 1,
            'updated_at': change['changed_at'] ?? '',
            'lines': <Object?>[],
          });
        } else {
          items.add(
            _salePayload(
              rows.first,
              updatedAt: change['changed_at']?.toString() ?? '',
            ),
          );
        }
      }
    }

    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'items': items,
      'cursor': cursor,
    });
  }

  Map<String, Object?> _salePayload(
    Map<String, Object?> m, {
    String updatedAt = '',
  }) {
    final rawLines = (m['lines_json'] as String?) ?? '[]';
    Object? lines;
    try {
      lines = jsonDecode(rawLines);
    } catch (_) {
      lines = <Object?>[];
    }
    return <String, Object?>{
      'pc_id': m['id'],
      'receipt_no': m['receipt_no'],
      'sold_at': m['sold_at'],
      'cashier': m['cashier'],
      'payment_method': m['payment_method'],
      'deposit_method': m['deposit_method'],
      'customer_id': m['customer_id'],
      'rounding_cents': m['rounding_cents'],
      'credit_outstanding_cents': m['credit_outstanding_cents'],
      'customer_name': m['customer_name'],
      'customer_phone': m['customer_phone'],
      'subtotal_cents': m['subtotal_cents'],
      'discount_cents':
          ((m['item_discount_cents'] as int?) ?? 0) +
              ((m['order_discount_cents'] as int?) ?? 0),
      'order_discount_cents': m['order_discount_cents'],
      'total_cents': m['total_cents'],
      'paid_cents': m['paid_cents'],
      'change_cents': m['change_cents'],
      'lines': lines,
      'is_deleted': m['voided'],
      'void_note': m['void_note'],
      'updated_at': updatedAt,
    };
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
    final receipts = <Map<String, Object?>>[];

    for (final raw in rawSales) {
      if (raw is! Map) {
        skipped++;
        continue;
      }
      final sale = Map<String, Object?>.from(raw);
      final originalReceipt = sale['receipt_no']?.toString().trim() ?? '';
      final clientSaleId = sale['client_sale_id']?.toString().trim() ?? '';
      if (originalReceipt.isEmpty) {
        skipped++;
        continue;
      }

      final result = await db.transaction<Map<String, Object?>>((txn) async {
        if (clientSaleId.isNotEmpty) {
          final mapped = await txn.query(
            'lan_sync_mobile_sales',
            where: 'client_sale_id=?',
            whereArgs: <Object?>[clientSaleId],
            limit: 1,
          );
          if (mapped.isNotEmpty) {
            if (_asInt(sale['voided']) == 1) {
              await reverseSale(
                txn,
                mapped.first['sale_id'] as String,
                sale['void_note']?.toString() ?? 'void',
              );
            }
            return <String, Object?>{
              'inserted': false,
              'receipt':
                  mapped.first['canonical_receipt']?.toString() ??
                      originalReceipt,
            };
   …5683 tokens truncated…ULL,
  total_cents INTEGER NOT NULL,
  lines_json TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT ''
)''');
            await db.execute('''
CREATE TABLE sync_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_error TEXT NOT NULL DEFAULT ''
)''');
          },
        ),
      );
      await legacy.insert('products', {
        'id': 'legacy-product',
        'name_zh': '旧商品',
        'name_en': 'Legacy Product',
        'sku': 'OLD-1',
        'barcode': '9550000000099',
        'price_cents': 500,
        'cost_cents': 300,
        'stock': 7.0,
        'unit': 'pcs',
        'category': 'Legacy',
        'is_deleted': 0,
        'image_path': '',
        'reorder_level': 1.0,
      });
      await legacy.insert('purchases', {
        'id': 'legacy-purchase',
        'purchase_no': 'PO-LEGACY',
        'supplier_id': 'legacy-supplier',
        'supplier_name': '旧供应商',
        'purchased_at': '2026-08-30T12:00:00Z',
        'total_cents': 2100,
        'lines_json': '[]',
        'notes': 'keep me',
      });
      await legacy.insert('sync_outbox', {
        'id': 'legacy-outbox',
        'kind': 'supplier_upsert',
        'entity_id': 'legacy-supplier',
        'payload_json': '{}',
        'created_at': '2026-08-30T12:01:00Z',
        'last_error': 'offline',
      });
      await legacy.close();

      final database = AppDatabase.forTesting(path, seed: false);
      final db = await database.db;
      final version = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));
      expect(version, 9);

      final product = await db.query(
        'products',
        where: 'id=?',
        whereArgs: ['legacy-product'],
      );
      expect(product, hasLength(1));
      expect(product.single['stock'], 7.0);

      final purchase = await db.query(
        'purchases',
        where: 'id=?',
        whereArgs: ['legacy-purchase'],
      );
      expect(purchase, hasLength(1));
      expect(purchase.single['notes'], 'keep me');
      expect(purchase.single['invoice_no'], '');
      expect(purchase.single['reversed'], 0);

      final outbox = await db.query(
        'sync_outbox',
        where: 'id=?',
        whereArgs: ['legacy-outbox'],
      );
      expect(outbox, hasLength(1));
      expect(outbox.single['last_error'], 'offline');

      final attachmentTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_attachments'",
      );
      expect(attachmentTable, hasLength(1));
      final auditTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_audit_log'",
      );
      expect(auditTable, hasLength(1));

      await database.close();
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
