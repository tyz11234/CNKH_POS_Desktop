import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../db/app_database.dart';
import '../models/product.dart';
import 'pos_repository.dart';
import 'product_images.dart';
import 'qr_storage.dart';
import 'sync_store.dart';

const String kPairingPrefix = 'cnkh-sync:v1|';

enum SyncLinkState { offline, connected, pending }

class LanSyncConfig {
  final String baseUrl;
  final String token;
  final String name;
  const LanSyncConfig({
    required this.baseUrl,
    this.token = '',
    this.name = 'CNKH-PC',
  });

  String get normalizedBase {
    var u = baseUrl.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri get wsUri {
    final base = Uri.parse(normalizedBase);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final qp = <String, String>{};
    if (token.trim().isNotEmpty) qp['token'] = token.trim();
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/api/v1/ws',
      queryParameters: qp.isEmpty ? null : qp,
    );
  }
}

/// Parse pairing QR: `cnkh-sync:v1|{json}` or raw JSON with baseUrl.
/// Thrown when the server reports a newer data epoch than this device
/// has seen: the server data was wiped (go-live reset) and this device
/// must NOT push its pre-wipe data back. The device clears the block by
/// running a local factory reset, after which it adopts the new epoch.
class ServerWipedException implements Exception {
  final int serverEpoch;
  ServerWipedException(this.serverEpoch);
  @override
  String toString() =>
      '服务器数据已被清空（清零代号 $serverEpoch），本机数据已停止同步，请先做本机初始化';
}

class PairingExpiredException implements Exception {
  final String message;
  PairingExpiredException([this.message = 'pairing QR expired']);
  @override
  String toString() => message;
}

/// Parse pairing QR. Throws [PairingExpiredException] if `exp` is in the past.
LanSyncConfig? parsePairingQr(String raw) {
  var text = raw.trim();
  if (text.startsWith(kPairingPrefix)) {
    text = text.substring(kPairingPrefix.length);
  } else if (text.startsWith('cnkh-sync:')) {
    final pipe = text.indexOf('|');
    if (pipe < 0) return null;
    text = text.substring(pipe + 1);
  }
  try {
    final data = jsonDecode(text);
    if (data is! Map) return null;
    final base = (data['baseUrl'] ?? data['base_url'] ?? '').toString().trim();
    if (base.isEmpty) return null;
    final exp = data['exp'];
    if (exp != null) {
      final expSec = exp is int ? exp : int.tryParse('$exp');
      if (expSec != null &&
          expSec < DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        throw PairingExpiredException('配对码已过期 / Pairing QR expired — ask PC to refresh');
      }
    }
    return LanSyncConfig(
      baseUrl: base,
      token: (data['token'] ?? '').toString(),
      name: (data['name'] ?? 'CNKH-PC').toString(),
    );
  } on PairingExpiredException {
    rethrow;
  } catch (_) {
    return null;
  }
}

bool looksLikePairingPayload(String raw) {
  final t = raw.trim();
  if (t.startsWith(kPairingPrefix) || t.startsWith('cnkh-sync:')) return true;
  if (t.startsWith('{') && t.contains('baseUrl')) {
    return parsePairingQr(t) != null;
  }
  return false;
}

class LanSyncClient {
  LanSyncClient(this.repo, {AppDatabase? database})
      : _db = database ?? repo.database;

  final PosRepository repo;
  final AppDatabase _db;
  String? lastError;

  Map<String, String> _headers(LanSyncConfig cfg) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (cfg.token.trim().isNotEmpty) {
      h['X-CNKH-Token'] = cfg.token.trim();
    }
    return h;
  }

  Future<Map<String, dynamic>> health(LanSyncConfig cfg) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/health');
    final res = await http
        .get(uri, headers: _headers(cfg))
        .timeout(const Duration(seconds: 5));
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> saveConfig(LanSyncConfig cfg) async {
    await repo.setSetting('lan_sync_host', cfg.normalizedBase);
    await repo.setSetting('lan_sync_token', cfg.token);
    await repo.setSetting('lan_sync_name', cfg.name);
  }

  Future<LanSyncConfig?> loadConfig() async {
    final host = await repo.getSetting('lan_sync_host');
    if (host.trim().isEmpty) return null;
    return LanSyncConfig(
      baseUrl: host,
      token: await repo.getSetting('lan_sync_token'),
      name: await repo.getSetting('lan_sync_name', fallback: 'CNKH-PC'),
    );
  }

  Future<int> countUnsyncedSales() async {
    final d = await _db.db;
    final n = Sqflite.firstIntValue(await d.rawQuery(
          "SELECT COUNT(*) FROM sales WHERE voided=0 AND (synced_at IS NULL OR synced_at='')",
        )) ??
        0;
    return n;
  }

  /// Refuses to sync when the server was wiped after this device last
  /// synced. First contact adopts the server's epoch; a factory reset
  /// wipes the stored epoch, which also unblocks the device.
  Future<void> _guardDataEpoch(LanSyncConfig cfg) async {
    final h = await health(cfg);
    final serverEpoch = (h['data_epoch'] as num?)?.toInt();
    if (serverEpoch == null) return; // older host without wipe support
    final stored = int.tryParse(await repo.getSetting('server_data_epoch'));
    if (stored == null) {
      await repo.setSetting('server_data_epoch', '$serverEpoch');
    } else if (serverEpoch > stored) {
      throw ServerWipedException(serverEpoch);
    } else if (serverEpoch < stored) {
      await repo.setSetting('server_data_epoch', '$serverEpoch');
    }
  }

  /// Checkbox server wipe (host data). Returns the decoded response.
  Future<Map<String, dynamic>> adminWipe(
    LanSyncConfig cfg,
    List<String> categories, {
    bool dryRun = false,
  }) async {
    final res = await http
        .post(
          Uri.parse('${cfg.normalizedBase}/api/v1/admin/wipe'),
          headers: _headers(cfg),
          body: jsonEncode({'categories': categories, 'dry_run': dryRun}),
        )
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['ok'] != true) {
      throw StateError('${body['error'] ?? '服务器拒绝了清空请求'}');
    }
    return body;
  }

  /// Checkbox server wipe for the payment-records ledger (ai helper).
  Future<Map<String, dynamic>> adminWipePayments(
    LanSyncConfig cfg, {
    bool dryRun = false,
  }) async {
    final res = await http
        .post(
          Uri.parse('${cfg.normalizedBase}/api/v1/admin/wipe-payments'),
          headers: _headers(cfg),
          body: jsonEncode({'dry_run': dryRun}),
        )
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['ok'] != true) {
      throw StateError('${body['error'] ?? '服务器拒绝了清空请求'}');
    }
    return body;
  }

  /// Decodes a QR image (bytes) through the server's QR decoder and
  /// returns its EMV payload, or null when no QR could be read. Used
  /// when the merchant QR is imported in Settings.
  Future<String?> decodeQrPayload(LanSyncConfig cfg, List<int> bytes) async {
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('${cfg.normalizedBase}/api/v1/qr/decode'),
      );
      if (cfg.token.trim().isNotEmpty) {
        req.headers['X-CNKH-' 'Token'] = cfg.token.trim();
      }
      req.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'qr.jpg'),
      );
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final payload = (body['payload'] ?? '').toString();
      return payload.isEmpty ? null : payload;
    } catch (_) {
      return null;
    }
  }

  Future<String> pullCatalog(LanSyncConfig cfg) async {
    await _guardDataEpoch(cfg);
    lastError = null;
    try {
      final since = await repo.getSetting('lan_sync_products_cursor');
      final q = since.isEmpty ? '' : '?since=${Uri.encodeQueryComponent(since)}';
      final productsUri = Uri.parse('${cfg.normalizedBase}/api/v1/products$q');
      final customersUri = Uri.parse('${cfg.normalizedBase}/api/v1/customers$q');
      final categoriesUri =
          Uri.parse('${cfg.normalizedBase}/api/v1/categories$q');
      final pRes = await http
          .get(productsUri, headers: _headers(cfg))
          .timeout(const Duration(seconds: 30));
      final cRes = await http
          .get(customersUri, headers: _headers(cfg))
          .timeout(const Duration(seconds: 30));
      Map<String, dynamic> catBody = {'ok': true, 'items': []};
      try {
        final catRes = await http
            .get(categoriesUri, headers: _headers(cfg))
            .timeout(const Duration(seconds: 20));
        catBody =
            jsonDecode(utf8.decode(catRes.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      final pBody =
          jsonDecode(utf8.decode(pRes.bodyBytes)) as Map<String, dynamic>;
      final cBody =
          jsonDecode(utf8.decode(cRes.bodyBytes)) as Map<String, dynamic>;
      if (pBody['ok'] != true) throw StateError('products: ${pBody['error']}');
      if (cBody['ok'] != true) throw StateError('customers: ${cBody['error']}');

      final products = (pBody['items'] as List?) ?? [];
      final customers = (cBody['items'] as List?) ?? [];
      final categories = (catBody['ok'] == true ? catBody['items'] as List? : []) ?? [];
      var maxCursor = since;
      final d = await _db.db;
      await d.transaction((txn) async {
        for (final raw in categories) {
          final m = Map<String, dynamic>.from(raw as Map);
          final updated = (m['updated_at'] as String?) ?? '';
          if (updated.compareTo(maxCursor) > 0) maxCursor = updated;
          await _upsertCategory(txn, m);
        }
        for (final raw in products) {
          final m = Map<String, dynamic>.from(raw as Map);
          final updated = (m['updated_at'] as String?) ?? '';
          if (updated.compareTo(maxCursor) > 0) maxCursor = updated;
          await _upsertProduct(txn, m);
        }
        for (final raw in customers) {
          final m = Map<String, dynamic>.from(raw as Map);
          final updated = (m['updated_at'] as String?) ?? '';
          if (updated.compareTo(maxCursor) > 0) maxCursor = updated;
          await _upsertCustomer(txn, m);
        }
      });
      // Optionally pull images for products that advertise has_image
      final imagesOn = await repo.productImagesEnabled();
      if (imagesOn) {
        for (final raw in products) {
          final m = Map<String, dynamic>.from(raw as Map);
          if (m['has_image'] == true && m['pc_id'] != null) {
            try {
              await pullProductImage(cfg, pcId: (m['pc_id'] as num).toInt(),
                  localProductId: 'pc-${m['pc_id']}');
            } catch (_) {}
          }
        }
      }
      await repo.setSetting('lan_sync_products_cursor', maxCursor);
      await repo.setSetting(
        'lan_sync_last_pull',
        DateTime.now().toIso8601String(),
      );
      // Shop-level state that used to live only on this device.
      try {
        final h = await health(cfg);
        final caps = h['capabilities'] as List? ?? const [];
        if (caps.contains('store_settings_v1')) {
          try { await _syncStoreSettings(cfg); } catch (_) {}
        }
        if (caps.contains('held_orders_v1')) {
          try { await _syncHeldOrders(cfg); } catch (_) {}
        }
        if (caps.contains('daily_closings_v1')) {
          try { await _syncDailyClosings(cfg); } catch (_) {}
        }
        if (caps.contains('product_image_upload_v1')) {
          try { await _uploadProductImages(cfg); } catch (_) {}
        }
      } catch (_) {}
      return 'Pulled ${products.length} products, ${customers.length} customers, ${categories.length} categories';
    } catch (e) {
      lastError = '$e';
      rethrow;
    }
  }

  Future<void> _upsertProduct(
      DatabaseExecutor txn, Map<String, dynamic> m) async {
    final sku = (m['sku'] as String?) ?? '';
    final barcode = (m['barcode'] as String?) ?? '';
    final pcId = m['pc_id'];
    Map<String, Object?>? existing;
    if (barcode.isNotEmpty) {
      final rows = await txn.query('products',
          where: 'barcode=?', whereArgs: [barcode], limit: 1);
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && sku.isNotEmpty) {
      final rows = await txn
          .query('products', where: 'sku=?', whereArgs: [sku], limit: 1);
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && pcId != null) {
      final rows = await txn.query('products',
          where: 'id=?', whereArgs: ['pc-$pcId'], limit: 1);
      if (rows.isNotEmpty) existing = rows.first;
    }
    final id = (existing?['id'] as String?) ?? 'pc-$pcId';
    final existingImg = (existing?['image_path'] as String?) ?? '';
    final product = Product(
      id: id,
      nameZh: (m['name_zh'] as String?) ?? (m['name'] as String?) ?? '',
      nameEn: (m['name_en'] as String?) ?? (m['name'] as String?) ?? '',
      sku: sku,
      barcode: barcode,
      priceCents: (m['price_cents'] as num?)?.toInt() ?? 0,
      costCents: (m['cost_cents'] as num?)?.toInt() ?? 0,
      stock: (m['stock'] as num?)?.toDouble() ?? 0,
      unit: (m['unit'] as String?) ?? 'pcs',
      category: (m['category'] as String?) ?? '',
      isDeleted: (m['is_deleted'] as num?)?.toInt() ?? 0,
      imagePath: existingImg,
      reorderLevel: (m['reorder_level'] as num?)?.toDouble() ?? 0,
    );
    await txn.insert('products', product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertCustomer(
      DatabaseExecutor txn, Map<String, dynamic> m) async {
    final pcId = m['pc_id'];
    final phone = (m['phone'] as String?) ?? '';
    final name = (m['name'] as String?) ?? '';
    Map<String, Object?>? existing;
    if (phone.isNotEmpty) {
      final rows = await txn.query('customers',
          where: 'phone=? AND is_deleted=0', whereArgs: [phone], limit: 1);
      if (rows.isNotEmpty) existing = rows.first;
    }
    if (existing == null && name.isNotEmpty) {
      final rows = await txn.query('customers',
          where: 'name=? AND is_deleted=0', whereArgs: [name], limit: 1);
      if (rows.isNotEmpty) existing = rows.first;
    }
    final id = (existing?['id'] as String?) ?? 'pc-c-$pcId';
    await txn.insert(
      'customers',
      {
        'id': id,
        'name': name,
        'phone': phone,
        'notes': (m['notes'] as String?) ?? '',
        'is_deleted': (m['is_deleted'] as num?)?.toInt() ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }


  Future<void> _upsertCategory(
      DatabaseExecutor txn, Map<String, dynamic> m) async {
    final name = ((m['name'] as String?) ?? '').trim();
    if (name.isEmpty) return;
    final pcId = m['pc_id'];
    final existing = await txn.query(
      'categories',
      where: 'name=? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    final id = existing.isNotEmpty
        ? (existing.first['id'] as String)
        : 'pc-cat-$pcId';
    await txn.insert(
      'categories',
      {
        'id': id,
        'name': name,
        'is_deleted': (m['is_deleted'] as num?)?.toInt() ?? 0,
        'updated_at': (m['updated_at'] as String?) ??
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> pullProductImage(
    LanSyncConfig cfg, {
    required int pcId,
    required String localProductId,
  }) async {
    final uri =
        Uri.parse('${cfg.normalizedBase}/api/v1/product_images/$pcId');
    final res = await http
        .get(uri, headers: _headers(cfg))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return;
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) return;
    final b64 = body['base64'] as String?;
    if (b64 == null || b64.isEmpty) return;
    final store = ProductImageStore();
    final saved = await store.saveBase64(
      localProductId,
      b64,
      ext: (body['ext'] as String?) ?? 'jpg',
    );
    if (saved != null) {
      final d = await _db.db;
      await d.update('products', {'image_path': saved},
          where: 'id=?', whereArgs: [localProductId]);
    }
  }

  /// Settings keys that belong to the shop (not to one device) and are
  /// exchanged with the server's store-settings store. Device-bound keys
  /// (printer, sync connection, cursors) are deliberately excluded.
  static const _storeSettingDbKeys = <String>[
    'store_name',
    'store_address',
    'store_phone',
    'receipt_header',
    'receipt_footer',
    'receipt_notes',
    'receipt_show_sku',
    'receipt_show_cashier',
    'receipt_show_datetime',
    'receipt_show_payment',
    'receipt_show_change',
    'receipt_show_discount',
    'receipt_show_unit_price',
    'receipt_show_qty',
    'receipt_show_duitnow_qr',
    'receipt_char_width',
    'low_stock_threshold',
    'stock_policy',
    'hold_timeout_minutes',
    'product_images_enabled',
    'scan_feedback',
  ];

  static String _fnvHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  static String _snapshotHash(Map<String, String> m) {
    final keys = m.keys.toList()..sort();
    return _fnvHash(keys.map((k) => '$k=${m[k]}').join('\n'));
  }

  static String _bytesHash(List<int> bytes) {
    // 32-bit FNV-1a: 64-bit literals cannot be represented in JS, and this
    // code also compiles into the web build.
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return '${bytes.length}-${h.toRadixString(16)}';
  }

  Future<Map<String, String>> _storeSnapshot() async {
    final out = <String, String>{};
    for (final k in _storeSettingDbKeys) {
      final v = await repo.getSetting(k);
      if (v.isNotEmpty) out[k] = v;
    }
    final payload = await QrStorage().getPayload();
    if (payload != null && payload.isNotEmpty) {
      out['duitnow_qr_payload'] = payload;
    }
    return out;
  }

  /// Two-way store settings exchange. Local edits win (pushed); when the
  /// local copy is unchanged since the last exchange, server changes are
  /// applied. The server POST is upsert-only, so pushing can never delete
  /// keys another device set.
  Future<void> _syncStoreSettings(LanSyncConfig cfg) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/store-settings');
    final res = await http
        .get(uri, headers: _headers(cfg))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) return;
    final serverSettings = <String, String>{
      for (final e in (body['settings'] as Map? ?? const {}).entries)
        '${e.key}': '${e.value}',
    };
    final version = (body['version'] as num?)?.toInt() ?? 0;
    final local = await _storeSnapshot();
    final localHash = _snapshotHash(local);
    final syncedHash = await repo.getSetting('store_settings_hash');
    final seenVersion =
        int.tryParse(await repo.getSetting('store_settings_version')) ?? -1;
    if (local.isNotEmpty && localHash != syncedHash) {
      final post = await http
          .post(
            uri,
            headers: _headers(cfg),
            body: jsonEncode({'settings': local}),
          )
          .timeout(const Duration(seconds: 15));
      if (post.statusCode == 200) {
        final pb =
            jsonDecode(utf8.decode(post.bodyBytes)) as Map<String, dynamic>;
        if (pb['ok'] == true) {
          await repo.setSetting('store_settings_hash', localHash);
          await repo.setSetting(
            'store_settings_version',
            '${(pb['version'] as num?)?.toInt() ?? version}',
          );
        }
      }
      return;
    }
    if (version != seenVersion) {
      for (final e in serverSettings.entries) {
        if (e.key == 'duitnow_qr_payload') {
          await QrStorage().setPayload(e.value);
        } else if (_storeSettingDbKeys.contains(e.key)) {
          await repo.setSetting(e.key, e.value);
        }
      }
      final applied = await _storeSnapshot();
      await repo.setSetting('store_settings_hash', _snapshotHash(applied));
      await repo.setSetting('store_settings_version', '$version');
    }
  }

  Future<String> _translateHeldPayload(
    String payloadJson,
    Future<String> Function(String) mapId,
  ) async {
    try {
      final m = jsonDecode(payloadJson) as Map<String, dynamic>;
      for (final raw in (m['items'] as List? ?? const [])) {
        final item = raw as Map<String, dynamic>;
        final pid = item['productId']?.toString();
        if (pid != null && pid.isNotEmpty) item['productId'] = await mapId(pid);
      }
      return jsonEncode(m);
    } catch (_) {
      return payloadJson;
    }
  }

  Future<bool> _postMutations(
    LanSyncConfig cfg,
    List<Map<String, Object?>> ops,
  ) async {
    if (ops.isEmpty) return true;
    final res = await http
        .post(
          Uri.parse('${cfg.normalizedBase}/api/v1/mutations'),
          headers: _headers(cfg),
          body: jsonEncode({'operations': ops}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) return false;
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return body['ok'] == true;
  }

  /// Held orders are immutable create/delete records, so reconciliation is
  /// a set merge: push local-only/changed holds, propagate tombstoned
  /// deletions, pull server-only holds. Product ids inside the payload
  /// are translated through the sync id map in both directions.
  Future<void> _syncHeldOrders(LanSyncConfig cfg) async {
    final d = await _db.db;
    final res = await http
        .get(
          Uri.parse('${cfg.normalizedBase}/api/v1/held-orders'),
          headers: _headers(cfg),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) return;
    final serverRows = <Map<String, dynamic>>[
      for (final r in (body['items'] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    final serverById = <String, Map<String, dynamic>>{
      for (final r in serverRows) '${r['id']}': r,
    };
    var tombstones = <String>[];
    try {
      final raw = await repo.getSetting('held_tombstones');
      if (raw.isNotEmpty) {
        tombstones = (jsonDecode(raw) as List).map((e) => '$e').toList();
      }
    } catch (_) {}
    final tombSet = tombstones.toSet();
    final localRows = await d.query('held_orders');
    final localById = <String, Map<String, Object?>>{
      for (final r in localRows) '${r['id']}': r,
    };
    final ops = <Map<String, Object?>>[];
    for (final id in tombSet) {
      if (serverById.containsKey(id)) {
        ops.add({
          'id': AppDatabase.newId(),
          'kind': 'held_delete',
          'client_entity_id': id,
          'payload': {'id': id},
        });
      }
    }
    for (final r in localRows) {
      final id = '${r['id']}';
      if (tombSet.contains(id)) continue;
      final translated = await _translateHeldPayload(
        '${r['payload_json']}',
        (localId) async => remoteEntityId(d, 'product', localId),
      );
      final s = serverById[id];
      if (s == null ||
          '${s['payload_json']}' != translated ||
          '${s['hold_no']}' != '${r['hold_no']}' ||
          '${s['cashier']}' != '${r['cashier']}' ||
          '${s['held_at']}' != '${r['held_at']}') {
        ops.add({
          'id': AppDatabase.newId(),
          'kind': 'held_upsert',
          'client_entity_id': id,
          'payload': {
            'row': {
              'id': id,
              'hold_no': '${r['hold_no']}',
              'cashier': '${r['cashier']}',
              'held_at': '${r['held_at']}',
              'payload_json': translated,
            },
          },
        });
      }
    }
    if (!await _postMutations(cfg, ops)) return; // retry next cycle
    if (tombstones.isNotEmpty) {
      await repo.setSetting('held_tombstones', '[]');
    }
    for (final s in serverRows) {
      final id = '${s['id']}';
      if (localById.containsKey(id) || tombSet.contains(id)) continue;
      final translated = await _translateHeldPayload(
        '${s['payload_json']}',
        (remoteId) async =>
            await mappedLocalId(d, 'product', remoteId) ?? remoteId,
      );
      await d.insert('held_orders', {
        'id': id,
        'hold_no': '${s['hold_no']}',
        'cashier': '${s['cashier']}',
        'held_at': '${s['held_at']}',
        'payload_json': translated,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Daily closings: one row per business date; the later closed_at wins.
  Future<void> _syncDailyClosings(LanSyncConfig cfg) async {
    final d = await _db.db;
    final res = await http
        .get(
          Uri.parse('${cfg.normalizedBase}/api/v1/daily-closings'),
          headers: _headers(cfg),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) return;
    Map<String, Object?> closingRow(Map<String, dynamic> r) => {
      'id': '${r['id']}',
      'business_date': '${r['business_date']}',
      'opening_cash_cents': (r['opening_cash_cents'] as num?)?.toInt() ?? 0,
      'counted_cash_cents': (r['counted_cash_cents'] as num?)?.toInt() ?? 0,
      'system_cash_cents': (r['system_cash_cents'] as num?)?.toInt() ?? 0,
      'notes': '${r['notes'] ?? ''}',
      'closed_at': '${r['closed_at']}',
      'closed_by': '${r['closed_by']}',
    };
    final serverByDate = <String, Map<String, dynamic>>{
      for (final r in (body['items'] as List? ?? const []))
        '${(r as Map)['business_date']}': Map<String, dynamic>.from(r),
    };
    final localRows = await d.query('daily_closings');
    final localByDate = <String, Map<String, Object?>>{
      for (final r in localRows) '${r['business_date']}': r,
    };
    final ops = <Map<String, Object?>>[];
    for (final e in localByDate.entries) {
      final s = serverByDate[e.key];
      if (s == null ||
          '${s['closed_at']}'.compareTo('${e.value['closed_at']}') < 0) {
        ops.add({
          'id': AppDatabase.newId(),
          'kind': 'daily_closing_upsert',
          'client_entity_id': '${e.value['id']}',
          'payload': {'row': closingRow(Map<String, dynamic>.from(e.value))},
        });
        serverByDate[e.key] = Map<String, dynamic>.from(e.value);
      }
    }
    if (!await _postMutations(cfg, ops)) return;
    for (final e in serverByDate.entries) {
      final l = localByDate[e.key];
      if (l == null ||
          '${e.value['closed_at']}'.compareTo('${l['closed_at']}') > 0) {
        await d.delete(
          'daily_closings',
          where: 'business_date=?',
          whereArgs: [e.key],
        );
        await d.insert('daily_closings', closingRow(e.value));
      }
    }
  }

  /// Uploads locally-set product images to the server so other clients can
  /// pull them through the existing image download path. A stored content
  /// hash per product keeps this a no-op when nothing changed.
  Future<void> _uploadProductImages(LanSyncConfig cfg) async {
    final d = await _db.db;
    final rows = await d.query(
      'products',
      columns: ['id', 'image_path'],
      where: "image_path IS NOT NULL AND image_path<>''",
    );
    final store = ProductImageStore();
    for (final r in rows) {
      final localId = '${r['id']}';
      final bytes = await store.readBytes(localId);
      if (bytes == null || bytes.isEmpty) continue;
      final hash = _bytesHash(bytes);
      final doneKey = 'product_image_uploaded_$localId';
      if (await repo.getSetting(doneKey) == hash) continue;
      final remoteId = await remoteEntityId(d, 'product', localId);
      final uri = Uri.parse(
        '${cfg.normalizedBase}/api/v1/product_images/${Uri.encodeComponent(remoteId)}',
      );
      var uploaded = false;
      try {
        final get = await http
            .get(uri, headers: _headers(cfg))
            .timeout(const Duration(seconds: 10));
        if (get.statusCode == 200) {
          final gb =
              jsonDecode(utf8.decode(get.bodyBytes)) as Map<String, dynamic>;
          final b64 = gb['base64'] as String?;
          if (b64 != null &&
              b64.isNotEmpty &&
              _bytesHash(base64Decode(b64)) == hash) {
            uploaded = true;
          }
        }
      } catch (_) {}
      if (!uploaded) {
        final path = '${r['image_path']}';
        final dot = path.lastIndexOf('.');
        final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : 'jpg';
        final post = await http
            .post(
              uri,
              headers: _headers(cfg),
              body: jsonEncode({'base64': base64Encode(bytes), 'ext': ext}),
            )
            .timeout(const Duration(seconds: 30));
        if (post.statusCode == 200) {
          final pb =
              jsonDecode(utf8.decode(post.bodyBytes)) as Map<String, dynamic>;
          uploaded = pb['ok'] == true;
        }
      }
      if (uploaded) await repo.setSetting(doneKey, hash);
    }
  }


  Future<String> pushCategories(LanSyncConfig cfg) async {
    final cats = await repo.listCategories();
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/categories');
    final res = await http
        .post(
          uri,
          headers: _headers(cfg),
          body: jsonEncode({
            'items': [
              for (final c in cats) {'name': c.name},
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) throw StateError('${body['error']}');
    return 'Pushed ${body['saved'] ?? cats.length} categories';
  }

  Future<String> pushBarcodeQueue(LanSyncConfig cfg) async {
    final rows = await repo.listBarcodeQueue(status: 'pending');
    if (rows.isEmpty) return 'No pending barcode queue';
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/barcode_queue');
    final res = await http
        .post(
          uri,
          headers: _headers(cfg),
          body: jsonEncode({
            'items': [
              for (final m in rows)
                {
                  'product_id': m['product_id'],
                  'barcode': m['barcode'],
                  'product_name': m['product_name'],
                  'sku': m['sku'],
                  'price_cents': m['price_cents'],
                  'copies': m['copies'],
                  'created_at': m['created_at'],
                  'source': 'phone',
                },
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) throw StateError('${body['error']}');
    for (final m in rows) {
      await repo.clearBarcodeQueueItem(m['id'] as String, status: 'synced');
    }
    return 'Pushed barcode queue ${body['saved'] ?? rows.length}';
  }

  Future<String> pushSales(LanSyncConfig cfg) async {
    await _guardDataEpoch(cfg);
    lastError = null;
    try {
      final d = await _db.db;
      final rows = await d.query(
        'sales',
        where: "voided=0 AND (synced_at IS NULL OR synced_at='')",
        orderBy: 'sold_at ASC',
        limit: 200,
      );
      final sales = [
        for (final m in rows)
          {
            'receipt_no': m['receipt_no'],
            'sold_at': m['sold_at'],
            'cashier': m['cashier'],
            'payment_method': m['payment_method'],
            'deposit_method': m['deposit_method'],
            'customer_name': m['customer_name'],
            'customer_phone': m['customer_phone'],
            'subtotal_cents': m['subtotal_cents'],
            'discount_cents': (m['item_discount_cents'] as int? ?? 0) +
                (m['order_discount_cents'] as int? ?? 0),
            'order_discount_cents': m['order_discount_cents'],
            'total_cents': m['total_cents'],
            'paid_cents': m['paid_cents'],
            'change_cents': m['change_cents'],
            'lines': jsonDecode((m['lines_json'] as String?) ?? '[]'),
          }
      ];
      if (sales.isEmpty) {
        await repo.setSetting(
            'lan_sync_last_push', DateTime.now().toIso8601String());
        return 'No unsynced sales';
      }
      final uri = Uri.parse('${cfg.normalizedBase}/api/v1/sales');
      final res = await http
          .post(
            uri,
            headers: _headers(cfg),
            body: jsonEncode({'sales': sales}),
          )
          .timeout(const Duration(seconds: 45));
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (body['ok'] != true) {
        throw StateError('${body['error'] ?? body}');
      }
      final now = DateTime.now().toIso8601String();
      await d.transaction((txn) async {
        for (final m in rows) {
          await txn.update(
            'sales',
            {'synced_at': now},
            where: 'id=?',
            whereArgs: [m['id']],
          );
        }
      });
      await repo.setSetting('lan_sync_last_push', now);
      await repo.setSetting('lan_sync_last_error', '');
      return 'Pushed ${body['imported'] ?? sales.length} '
          '(skipped ${body['skipped'] ?? 0})';
    } catch (e) {
      lastError = '$e';
      await repo.setSetting('lan_sync_last_error', lastError!);
      rethrow;
    }
  }

  Future<String> pullSales(LanSyncConfig cfg) async {
    await _guardDataEpoch(cfg);
    lastError = null;
    try {
      final since = await repo.getSetting('lan_sync_sales_cursor');
      final uri = Uri.parse(
        '${cfg.normalizedBase}/api/v1/sales${since.isEmpty ? '' : '?since=${Uri.encodeQueryComponent(since)}'}',
      );
      final res = await http
          .get(uri, headers: _headers(cfg))
          .timeout(const Duration(seconds: 30));
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (body['ok'] != true) throw StateError('${body['error']}');
      final items = (body['items'] as List?) ?? [];
      final d = await _db.db;
      var maxSold = since;
      var imported = 0;
      await d.transaction((txn) async {
        for (final raw in items) {
          final m = Map<String, dynamic>.from(raw as Map);
          final receipt = (m['receipt_no'] as String?) ?? '';
          if (receipt.isEmpty) continue;
          final soldAt = (m['sold_at'] as String?) ?? '';
          if (soldAt.compareTo(maxSold) > 0) maxSold = soldAt;
          final existing = await txn.query('sales',
              where: 'receipt_no=?', whereArgs: [receipt], limit: 1);
          if (existing.isNotEmpty) continue;
          final lines = m['lines'] ?? [];
          await txn.insert('sales', {
            'id': AppDatabase.newId(),
            'receipt_no': receipt,
            'sold_at': soldAt,
            'cashier': 'pc-sync',
            'payment_method': m['payment_method'] ?? 'CASH',
            'deposit_method': m['deposit_method'],
            'customer_id': null,
            'customer_name': m['customer_name'],
            'customer_phone': m['customer_phone'],
            'subtotal_cents': m['subtotal_cents'] ?? m['total_cents'] ?? 0,
            'item_discount_cents': 0,
            'order_discount_cents': m['discount_cents'] ?? 0,
            'rounding_cents': 0,
            'total_cents': m['total_cents'] ?? 0,
            'paid_cents': m['paid_cents'] ?? m['total_cents'] ?? 0,
            'change_cents': m['change_cents'] ?? 0,
            'credit_outstanding_cents': 0,
            'lines_json': jsonEncode(lines),
            'voided': m['is_deleted'] ?? 0,
            'void_note': '',
            'synced_at': DateTime.now().toIso8601String(),
          });
          imported++;
        }
      });
      await repo.setSetting('lan_sync_sales_cursor', maxSold);
      return 'Pulled $imported sales';
    } catch (e) {
      lastError = '$e';
      await repo.setSetting('lan_sync_last_error', lastError!);
      rethrow;
    }
  }

  Future<void> notifyPcSale(LanSyncConfig cfg,
      {required String receiptNo}) async {
    final uri = Uri.parse('${cfg.normalizedBase}/api/v1/notify');
    await http
        .post(
          uri,
          headers: _headers(cfg),
          body: jsonEncode({
            'type': 'sale',
            'source': 'phone',
            'receipt_no': receiptNo,
          }),
        )
        .timeout(const Duration(seconds: 5));
  }

  /// Force full reconcile: pull catalog + sales, push pending.
  Future<String> forceReconcile(LanSyncConfig cfg) async {
    await _guardDataEpoch(cfg);
    final a = await pullCatalog(cfg);
    final b = await pullSales(cfg);
    final c = await pushSales(cfg);
    var d = '';
    try {
      d = await pushBarcodeQueue(cfg);
    } catch (e) {
      d = 'barcode queue: $e';
    }
    try {
      await pushCategories(cfg);
    } catch (_) {}
    await repo.setSetting('lan_sync_last_full', DateTime.now().toIso8601String());
    return '$a\n$b\n$c\n$d';
  }

  Future<String> fullSync(LanSyncConfig cfg) => forceReconcile(cfg);
}

/// Near-real-time listener: WebSocket + poll fallback + auto-retry pending.
class LanLiveSync {
  LanLiveSync(this.client);

  final LanSyncClient client;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Timer? _poll;
  Timer? _retry;
  LanSyncConfig? _cfg;
  bool connected = false;
  int pendingCount = 0;
  void Function()? onRemoteChange;
  void Function(Map<String, dynamic> event)? onLowStock;
  void Function(SyncLinkState state, int pending)? onStatusChanged;
  bool serverWipeDetected = false;
  void Function()? onServerWipeDetected;

  void _noteWipe(Object e) {
    if (e is ServerWipedException && !serverWipeDetected) {
      serverWipeDetected = true;
      onServerWipeDetected?.call();
    }
  }

  SyncLinkState get linkState {
    if (!connected) return SyncLinkState.offline;
    if (pendingCount > 0) return SyncLinkState.pending;
    return SyncLinkState.connected;
  }

  Future<void> _emitStatus() async {
    pendingCount = await client.countUnsyncedSales();
    onStatusChanged?.call(linkState, pendingCount);
  }

  Future<void> connect(LanSyncConfig cfg) async {
    await disconnect();
    _cfg = cfg;
    await client.saveConfig(cfg);
    final h = await client.health(cfg);
    if (h['ok'] != true) throw StateError('health failed');
    try {
      _ws = WebSocketChannel.connect(cfg.wsUri);
      _wsSub = _ws!.stream.listen(
        (msg) async {
          try {
            final data = msg is String ? jsonDecode(msg) : null;
            if (data is! Map) return;
            final t = data['type'];
            if (t == 'sale') {
              await _onSaleEvent();
            } else if (t == 'low_stock') {
              onLowStock?.call(Map<String, dynamic>.from(data));
            } else if (t == 'category' || t == 'product_image') {
              final c = _cfg;
              if (c != null) {
                try {
                  await client.pullCatalog(c);
                  onRemoteChange?.call();
                } catch (_) {}
              }
            }
          } catch (_) {}
        },
        onError: (_) async {
          connected = false;
          await _emitStatus();
        },
        onDone: () async {
          connected = false;
          await _emitStatus();
        },
      );
      connected = true;
    } catch (_) {
      connected = false;
    }
    await _emitStatus();

    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      final c = _cfg;
      if (c == null) return;
      try {
        await client.pullSales(c);
        onRemoteChange?.call();
        _ws?.sink.add(jsonEncode({'type': 'ping'}));
        await _emitStatus();
      } catch (e) {
        _noteWipe(e);
      }
    });

    // Auto-retry pending pushes every 12s while connected
    _retry = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (!connected || _cfg == null) return;
      final n = await client.countUnsyncedSales();
      if (n == 0) {
        await _emitStatus();
        return;
      }
      try {
        await client.pushSales(_cfg!);
        await _emitStatus();
        onRemoteChange?.call();
      } catch (_) {
        await _emitStatus();
      }
    });

    try {
      await client.pullCatalog(cfg);
      await client.pullSales(cfg);
      await client.pushSales(cfg);
    } catch (e) {
      _noteWipe(e);
    }
    await _emitStatus();
  }

  Future<void> _onSaleEvent() async {
    final c = _cfg;
    if (c == null) return;
    try {
      await client.pullSales(c);
      onRemoteChange?.call();
      await _emitStatus();
    } catch (_) {}
  }

  Future<void> onLocalSale(SaleRecord sale) async {
    final c = _cfg ?? await client.loadConfig();
    if (c == null) {
      await _emitStatus();
      return;
    }
    try {
      await client.pushSales(c);
      await client.notifyPcSale(c, receiptNo: sale.receiptNo);
    } catch (_) {}
    await _emitStatus();
  }

  Future<String> forceReconcile() async {
    final c = _cfg ?? await client.loadConfig();
    if (c == null) throw StateError('not paired');
    final msg = await client.forceReconcile(c);
    await _emitStatus();
    onRemoteChange?.call();
    return msg;
  }

  Future<void> disconnect() async {
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    _poll?.cancel();
    _poll = null;
    _retry?.cancel();
    _retry = null;
    connected = false;
    await _emitStatus();
  }
}
