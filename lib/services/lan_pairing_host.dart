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
}) {
  return '$kPairingPrefix${jsonEncode(<String, Object?>{'baseUrl': baseUrl, 'token': token, 'name': name})}';
}

/// Desktop is the authoritative LAN host for Mobile clients.
///
/// Database triggers keep a monotonic change log so catalog/sales endpoints can
/// serve real incremental updates without changing the POS business tables.
class LanPairingHost {
  LanPairingHost._(
    this.repo, {
    AppDatabase? database,
    this.configuredPort = 8787,
    this.name = 'CNKH-PC',
  }) : _db = database ?? AppDatabase.instance;

  LanPairingHost.forTesting(
    this.repo, {
    required AppDatabase database,
    this.configuredPort = 0,
    this.name = 'CNKH-PC',
  }) : _db = database;
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

  Future<void> start() async {
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
      throw StateError('无法启动局域网同步服务 :$configuredPort。端口可能被占用或被系统阻止。$e');
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
      payload: buildPairingPayload(baseUrl: baseUrl, token: _token, name: name),
      baseUrl: baseUrl,
      token: _token,
      name: name,
    );
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
        _publish(<String, Object?>{'type': 'catalog', 'data_cursor': maxSeq});
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
    if (request.method == 'POST' && path == '/api/v1/mutations') {
      final body = await _readJson(request);
      final operations = body['operations'];
      if (operations is! List)
        throw const FormatException('operations must be a list');
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
      'has_image': false,
      'updated_at': updatedAt,
    };
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
            if (_asInt(sale['voided']) == 1)
              await reverseSale(
                txn,
                mapped.first['sale_id'] as String,
                sale['void_note']?.toString() ?? 'void',
              );
            return <String, Object?>{
              'inserted': false,
              'receipt':
                  mapped.first['canonical_receipt']?.toString() ??
                  originalReceipt,
            };
          }
        }

        var canonicalReceipt = originalReceipt;
        final existingOriginal = await txn.query(
          'sales',
          where: 'receipt_no=?',
          whereArgs: <Object?>[originalReceipt],
          limit: 1,
        );
        if (existingOriginal.isNotEmpty) {
          if (_sameIncomingSale(existingOriginal.first, sale)) {
            return <String, Object?>{
              'inserted': false,
              'receipt': originalReceipt,
            };
          }
          final suffix = clientSaleId.isNotEmpty
              ? _shortId(clientSaleId)
              : _legacySaleSuffix(sale);
          canonicalReceipt = '$originalReceipt-P$suffix';
          var attempt = 1;
          while (true) {
            final collision = await txn.query(
              'sales',
              where: 'receipt_no=?',
              whereArgs: <Object?>[canonicalReceipt],
              limit: 1,
            );
            if (collision.isEmpty) break;
            if (_sameIncomingSale(collision.first, sale)) {
              return <String, Object?>{
                'inserted': false,
                'receipt': canonicalReceipt,
              };
            }
            attempt++;
            canonicalReceipt = '$originalReceipt-P$suffix-$attempt';
          }
        }

        final lines = <Map<String, Object?>>[];
        final incomingVoided = _asInt(sale['voided']) == 1;
        final policy = await readSetting(txn, 'stock_policy', fallback: 'warn');
        final requiredQty = <String, double>{};
        for (final raw in (sale['lines'] as List? ?? [])) {
          final line = Map<String, Object?>.from(raw as Map);
          var pid = (line['productId'] ?? line['product_id'])?.toString() ?? '';
          if (pid.startsWith('pc-')) pid = pid.substring(3);
          var products = await txn.query(
            'products',
            where: 'id=?',
            whereArgs: [pid],
          );
          if (products.isEmpty && (line['sku']?.toString() ?? '').isNotEmpty)
            products = await txn.query(
              'products',
              where: 'sku=? AND is_deleted=0',
              whereArgs: [line['sku']],
            );
          if (products.length != 1 ||
              (!incomingVoided && products.first['is_deleted'] == 1))
            throw StateError('销售商品未找到或不唯一：${line['nameZh'] ?? pid}');
          pid = products.first['id'] as String;
          final qty = _asDouble(line['qty'] ?? line['quantity']);
          if (!qty.isFinite || qty <= 0)
            throw const FormatException('invalid quantity');
          requiredQty[pid] = (requiredQty[pid] ?? 0) + qty;
          if (!incomingVoided &&
              policy == 'block' &&
              (products.first['stock'] as num) < requiredQty[pid]!)
            throw StateError('库存不足，销售保留在手机待处理');
          lines.add({...line, 'productId': pid});
        }
        if (lines.isEmpty) throw const FormatException('empty sale');
        String? customerId = sale['customer_id']?.toString();
        if (customerId != null && customerId.startsWith('pc-c-'))
          customerId = customerId.substring(5);
        var customers = customerId == null
            ? <Map<String, Object?>>[]
            : await txn.query(
                'customers',
                where: 'id=?',
                whereArgs: [customerId],
              );
        if (customers.isEmpty &&
            (sale['customer_name']?.toString() ?? '').isNotEmpty)
          customers = await txn.query(
            'customers',
            where: 'name=? AND phone=?',
            whereArgs: [sale['customer_name'], sale['customer_phone'] ?? ''],
          );
        customerId = customers.length == 1
            ? customers.first['id'] as String
            : null;
        if ((sale['payment_method']?.toString() ?? '').toUpperCase() ==
                'CREDIT' &&
            customerId == null)
          throw StateError('赊账客户尚未同步或存在歧义');
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
        final saleId = AppDatabase.newId();

        await txn.insert('sales', <String, Object?>{
          'id': saleId,
          'receipt_no': canonicalReceipt,
          'sold_at': sale['sold_at']?.toString() ?? now,
          'cashier': sale['cashier']?.toString() ?? 'mobile-sync',
          'payment_method': payment,
          'deposit_method': sale['deposit_method']?.toString(),
          'customer_id': customerId,
          'customer_name': sale['customer_name']?.toString(),
          'customer_phone': sale['customer_phone']?.toString(),
          'subtotal_cents': subtotal,
          'item_discount_cents': itemDiscount,
          'order_discount_cents': orderDiscount,
          'rounding_cents': _asInt(sale['rounding_cents']),
          'total_cents': total,
          'paid_cents': paid,
          'change_cents': _asInt(sale['change_cents']),
          'credit_outstanding_cents': outstanding,
          'lines_json': jsonEncode(lines),
          'voided': incomingVoided ? 1 : 0,
          'void_note': sale['void_note']?.toString() ?? '',
          'synced_at': now,
        });

        for (final rawLine
            in incomingVoided ? <Map<String, Object?>>[] : lines) {
          if (rawLine is! Map) continue;
          final line = Map<String, Object?>.from(rawLine);
          var productId =
              (line['productId'] ?? line['product_id'])?.toString().trim() ??
              '';
          if (productId.startsWith('pc-')) {
            productId = productId.substring(3);
          }
          final qty = _asDouble(line['qty'] ?? line['quantity'], fallback: 1);
          if (productId.isEmpty || qty <= 0) continue;
          final changed = await txn.rawUpdate(
            'UPDATE products SET stock=stock-? WHERE id=?',
            <Object?>[qty, productId],
          );
          if (changed > 0) {
            await txn.insert('stock_moves', <String, Object?>{
              'id': AppDatabase.newId(),
              'product_id': productId,
              'change': -qty,
              'reason': 'sale',
              'created_at': now,
              'operator': sale['cashier']?.toString() ?? 'mobile-sync',
              'notes': canonicalReceipt,
            });
          }
        }

        if (clientSaleId.isNotEmpty) {
          await txn.insert('lan_sync_mobile_sales', <String, Object?>{
            'client_sale_id': clientSaleId,
            'sale_id': saleId,
            'original_receipt': originalReceipt,
            'canonical_receipt': canonicalReceipt,
            'created_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        return <String, Object?>{'inserted': true, 'receipt': canonicalReceipt};
      });

      final canonicalReceipt = result['receipt']?.toString() ?? originalReceipt;
      receipts.add(<String, Object?>{
        if (clientSaleId.isNotEmpty) 'client_sale_id': clientSaleId,
        'original_receipt': originalReceipt,
        'receipt_no': canonicalReceipt,
      });
      if (result['inserted'] == true) {
        imported++;
      } else {
        skipped++;
      }
    }

    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'imported': imported,
      'skipped': skipped,
      'receipts': receipts,
      'cursor': await _latestChangeSeq(db),
    });
  }

  bool _sameIncomingSale(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final sameTime =
        (existing['sold_at']?.toString() ?? '') ==
        (incoming['sold_at']?.toString() ?? '');
    final sameTotal =
        _asInt(existing['total_cents']) == _asInt(incoming['total_cents']);
    final samePayment =
        (existing['payment_method']?.toString() ?? '') ==
        (incoming['payment_method']?.toString() ?? '');
    return sameTime && sameTotal && samePayment;
  }

  String _shortId(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (cleaned.isEmpty) return 'MOBILE';
    return cleaned.length <= 6 ? cleaned : cleaned.substring(0, 6);
  }

  String _legacySaleSuffix(Map<String, Object?> sale) {
    final raw =
        '${sale['sold_at']}|${sale['total_cents']}|'
        '${sale['cashier']}|${sale['payment_method']}';
    var hash = 2166136261;
    for (final byte in utf8.encode(raw)) {
      hash ^= byte;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    final out = hash.toRadixString(36).toUpperCase();
    return out.length <= 6 ? out : out.substring(0, 6);
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
        _emitConnectionCount();
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

    final candidates = <_IpCandidate>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (address.isLoopback || value.startsWith('169.254.')) continue;
        candidates.add(
          _IpCandidate(
            value,
            _interfaceScore(interface.name) + _ipScore(value),
          ),
        );
      }
    }
    if (candidates.isEmpty) return '127.0.0.1';

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.ip;
  }

  static int _interfaceScore(String rawName) {
    final name = rawName.toLowerCase();
    const virtualMarkers = <String>[
      'virtual',
      'vmware',
      'vbox',
      'virtualbox',
      'hyper-v',
      'docker',
      'wsl',
      'tun',
      'tap',
      'vpn',
      'tailscale',
      'zerotier',
    ];
    if (virtualMarkers.any(name.contains)) return -1500;
    if (name.contains('wi-fi') ||
        name.contains('wifi') ||
        name.contains('wlan') ||
        name.contains('wireless')) {
      return 1000;
    }
    if (name.contains('ethernet') || name.startsWith('eth')) return 800;
    return 0;
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

class _IpCandidate {
  const _IpCandidate(this.ip, this.score);

  final String ip;
  final int score;
}
