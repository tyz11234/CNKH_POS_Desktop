import 'dart:convert';

import '../db/app_database.dart';
import '../models/money.dart';
import '../models/product.dart';
import 'pos_repository.dart';

/// Compact purchase-invoice QR / structured payload.
///
/// Formats accepted:
/// 1) Prefixed: `CNKHPO1:{json}`
/// 2) Raw JSON object with `"v":1` or `"type":"cnkh_purchase"`
///
/// JSON shape:
/// ```json
/// {
///   "v": 1,
///   "type": "cnkh_purchase",
///   "supplier": "供应商名(可选)",
///   "supplierId": "可选",
///   "notes": "可选",
///   "lines": [
///     {
///       "name": "商品名",
///       "qty": 10,
///       "price": 12.50,
///       "costCents": 1250,
///       "sku": "可选",
///       "barcode": "可选"
///     }
///   ]
/// }
/// ```
/// `price` is unit cost in RM; `costCents` overrides if present.
class PurchaseInvoicePayload {
  static const prefix = 'CNKHPO1:';
  static const helpZh = '''
进货单二维码格式 / Purchase QR

前缀：CNKHPO1: + JSON，或纯 JSON（含 "v":1 / "type":"cnkh_purchase"）

字段：
• supplier / supplierId（可选）
• notes（可选）
• lines[]：
  - name 商品名（建议）
  - qty 数量
  - price 进货单价 RM，或 costCents 分
  - sku / barcode（可选，优先用于匹配目录）

示例：
CNKHPO1:{"v":1,"supplier":"五金行","lines":[{"name":"螺丝M6","qty":100,"price":0.15,"barcode":"1234567890123"}]}

扫描后进入核对页：已有商品直接进货；新商品将按进货价建档后再入库。
''';

  final String? supplierName;
  final String? supplierId;
  final String notes;
  final List<PurchaseDraftLine> lines;
  final String rawSource;

  const PurchaseInvoicePayload({
    this.supplierName,
    this.supplierId,
    this.notes = '',
    required this.lines,
    this.rawSource = '',
  });

  bool get isEmpty => lines.isEmpty;

  static bool looksLike(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (t.startsWith(prefix) || t.startsWith('cnkhpo1:')) return true;
    if (t.startsWith('{') &&
        (t.contains('"cnkh_purchase"') ||
            t.contains('"v":1') ||
            t.contains('"lines"'))) {
      return true;
    }
    return false;
  }

  /// Returns null if not a structured purchase payload.
  static PurchaseInvoicePayload? tryParse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    String jsonStr = t;
    final lower = t.toLowerCase();
    if (lower.startsWith('cnkhpo1:')) {
      jsonStr = t.substring(t.indexOf(':') + 1).trim();
    }
    if (!jsonStr.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final type = (map['type'] as String?)?.toLowerCase();
      final v = map['v'];
      final hasLines = map['lines'] is List;
      if (!hasLines) return null;
      if (type != null && type != 'cnkh_purchase' && type != 'purchase') {
        // Still accept if v==1 or prefix was used
        if (v != 1 && !lower.startsWith('cnkhpo1:')) return null;
      }
      final linesRaw = map['lines'] as List;
      final lines = <PurchaseDraftLine>[];
      for (final item in linesRaw) {
        if (item is! Map) continue;
        final line = PurchaseDraftLine.fromJson(Map<String, dynamic>.from(item));
        if (line.name.trim().isEmpty &&
            line.barcode.trim().isEmpty &&
            line.sku.trim().isEmpty) {
          continue;
        }
        if (line.qty <= 0) continue;
        lines.add(line);
      }
      if (lines.isEmpty) return null;
      return PurchaseInvoicePayload(
        supplierName: (map['supplier'] as String?)?.trim().isEmpty == true
            ? null
            : (map['supplier'] as String?)?.trim(),
        supplierId: (map['supplierId'] as String?)?.trim().isEmpty == true
            ? null
            : (map['supplierId'] as String?)?.trim(),
        notes: (map['notes'] as String?) ?? '',
        lines: lines,
        rawSource: t,
      );
    } catch (_) {
      return null;
    }
  }

  String encode({bool withPrefix = true}) {
    final body = jsonEncode({
      'v': 1,
      'type': 'cnkh_purchase',
      if (supplierName != null && supplierName!.isNotEmpty) 'supplier': supplierName,
      if (supplierId != null && supplierId!.isNotEmpty) 'supplierId': supplierId,
      if (notes.isNotEmpty) 'notes': notes,
      'lines': [for (final l in lines) l.toJson()],
    });
    return withPrefix ? '$prefix$body' : body;
  }
}

/// One draft purchase line before commit (may or may not match catalog).
class PurchaseDraftLine {
  String name;
  double qty;
  /// Unit cost in cents (进货价).
  int unitCostCents;
  String sku;
  String barcode;
  /// Matched existing product id, if any.
  String? productId;
  /// When true, commit will upsert a new Product then purchase.
  bool willCreate;
  /// Include in commit.
  bool selected;
  /// Optional sell price for new products (defaults to cost).
  int? sellPriceCents;
  String matchNote;
  double confidence;

  PurchaseDraftLine({
    required this.name,
    this.qty = 1,
    this.unitCostCents = 0,
    this.sku = '',
    this.barcode = '',
    this.productId,
    this.willCreate = true,
    this.selected = true,
    this.sellPriceCents,
    this.matchNote = '',
    this.confidence = 1,
  });

  int get subtotalCents => (unitCostCents * qty).round();

  int get effectiveSellCents => sellPriceCents ?? unitCostCents;

  factory PurchaseDraftLine.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] as String?)?.trim() ??
        (j['nameZh'] as String?)?.trim() ??
        '';
    final qty = _asDouble(j['qty'] ?? j['quantity'] ?? 1) ?? 1;
    int costCents = 0;
    if (j['costCents'] != null) {
      costCents = _asInt(j['costCents']) ?? 0;
    } else if (j['unitCostCents'] != null) {
      costCents = _asInt(j['unitCostCents']) ?? 0;
    } else if (j['price'] != null) {
      costCents = rmToCents(_asDouble(j['price']) ?? 0);
    } else if (j['unitCost'] != null) {
      costCents = rmToCents(_asDouble(j['unitCost']) ?? 0);
    } else if (j['cost'] != null) {
      costCents = rmToCents(_asDouble(j['cost']) ?? 0);
    }
    int? sell;
    if (j['sellPriceCents'] != null) {
      sell = _asInt(j['sellPriceCents']);
    } else if (j['sellPrice'] != null) {
      sell = rmToCents(_asDouble(j['sellPrice']) ?? 0);
    } else if (j['priceCents'] != null && j['costCents'] == null) {
      // Ambiguous single priceCents → treat as cost for purchase context
      costCents = costCents == 0 ? (_asInt(j['priceCents']) ?? 0) : costCents;
    }
    return PurchaseDraftLine(
      name: name,
      qty: qty <= 0 ? 1 : qty,
      unitCostCents: costCents < 0 ? 0 : costCents,
      sku: (j['sku'] as String?)?.trim() ?? '',
      barcode: (j['barcode'] as String?)?.trim() ??
          (j['code'] as String?)?.trim() ??
          '',
      sellPriceCents: sell,
    );
  }

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) 'name': name,
        'qty': qty,
        'costCents': unitCostCents,
        'price': centsToRm(unitCostCents),
        if (sku.isNotEmpty) 'sku': sku,
        if (barcode.isNotEmpty) 'barcode': barcode,
        if (sellPriceCents != null) 'sellPriceCents': sellPriceCents,
      };

  PurchaseDraftLine copy() => PurchaseDraftLine(
        name: name,
        qty: qty,
        unitCostCents: unitCostCents,
        sku: sku,
        barcode: barcode,
        productId: productId,
        willCreate: willCreate,
        selected: selected,
        sellPriceCents: sellPriceCents,
        matchNote: matchNote,
        confidence: confidence,
      );
}

int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString().trim());
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  final s = v.toString().trim().replaceAll(',', '');
  return double.tryParse(s);
}

/// Normalize product names for fuzzy equality (ZH/EN invoices).
String normalizeProductName(String s) {
  var t = s.trim().toLowerCase();
  t = t.replaceAll(RegExp(r'[\s\u3000]+'), '');
  t = t.replaceAll(RegExp(r'[·•\-_/\\|()\[\]【】（）]'), '');
  t = t.replaceAll(RegExp(r'[pcs|unit|个|件|箱|包]+$', caseSensitive: false), '');
  return t;
}

/// Parse free-form OCR / pasted invoice text into draft lines (best-effort).
///
/// Looks for rows like:
///   螺丝M6  10  1.50
///   水泥钉 x20 RM2.30
///   NAME  qty  price
/// Does **not** invent accuracy — low-confidence lines still returned for review.
class PurchaseInvoiceTextParser {
  static final _money = RegExp(
    r'(?:rm\s*)?(\d+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );
  static final _qtyHint = RegExp(
    r'(?:x|×|\*|qty[:\s]*)\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  );
  static final _barcodeLike = RegExp(r'\b(\d{8,14})\b');

  static List<PurchaseDraftLine> parse(String text) {
    final lines = <PurchaseDraftLine>[];
    final rawLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    for (final row in rawLines) {
      final lower = row.toLowerCase();
      if (_looksLikeHeader(lower)) continue;
      if (row.length < 2) continue;

      final barcode = _barcodeLike.firstMatch(row)?.group(1) ?? '';
      double? qty;
      final qtyM = _qtyHint.firstMatch(row);
      if (qtyM != null) qty = double.tryParse(qtyM.group(1)!);

      // Collect trailing numbers: last = price, previous = qty if not found
      final nums = <double>[];
      for (final m in _money.allMatches(row)) {
        final n = double.tryParse(m.group(1)!);
        if (n != null) nums.add(n);
      }
      // Drop barcode digits mistaken as money when equal to barcode value
      if (barcode.isNotEmpty) {
        nums.removeWhere((n) =>
            n == double.tryParse(barcode) ||
            (n >= 1e7 && n.toStringAsFixed(0) == barcode));
      }

      double price = 0;
      if (nums.length >= 2) {
        qty ??= nums[nums.length - 2];
        price = nums.last;
      } else if (nums.length == 1) {
        // Single number: if qty hint existed treat as price, else qty=1 price=num
        if (qty != null) {
          price = nums.first;
        } else if (barcode.isNotEmpty) {
          // barcode-only row — qty 1, unknown price
          qty = 1;
          price = 0;
        } else {
          // Ambiguous — treat as price with qty 1 (user can edit)
          qty = 1;
          price = nums.first;
        }
      } else {
        qty ??= 1;
      }
      final qtyVal = qty;
      if (qtyVal <= 0) continue;

      var name = row;
      name = name.replaceAll(_barcodeLike, ' ');
      name = name.replaceAll(_qtyHint, ' ');
      name = name.replaceAll(
          RegExp(r'(?:rm\s*)?\d+(?:\.\d{1,2})?', caseSensitive: false), ' ');
      name = name.replaceAll(RegExp(r'[x×*]'), ' ');
      name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
      // Strip common labels
      name = name.replaceAll(
          RegExp(r'^(品名|商品|名称|name)[:：\s]*', caseSensitive: false), '');

      if (name.isEmpty && barcode.isEmpty) continue;
      if (name.isEmpty) name = barcode;

      // Confidence: need name + (qty or price)
      var conf = 0.4;
      if (name.length >= 2) conf += 0.2;
      if (qtyVal > 0) conf += 0.15;
      if (price > 0) conf += 0.15;
      if (barcode.isNotEmpty) conf += 0.1;
      if (nums.length >= 2) conf += 0.1;

      lines.add(PurchaseDraftLine(
        name: name,
        qty: qtyVal,
        unitCostCents: rmToCents(price),
        barcode: barcode,
        confidence: conf.clamp(0, 1),
        matchNote: conf < 0.55 ? '低置信度，请核对' : '',
      ));
    }
    return lines;
  }

  static bool _looksLikeHeader(String lower) {
    const headers = [
      'invoice',
      'receipt',
      'total',
      'subtotal',
      '合计',
      '总计',
      '小计',
      '日期',
      'date',
      'supplier',
      '供应商',
      'qty',
      'quantity',
      '数量',
      '单价',
      '金额',
      '品名',
      'item',
      'description',
      '进货单',
    ];
    // Exact-ish short header rows
    if (lower.length <= 24) {
      for (final h in headers) {
        if (lower == h || lower.replaceAll(' ', '') == h) return true;
      }
      if (RegExp(r'^(qty|数量).*(price|单价|金额)').hasMatch(lower)) return true;
      if (RegExp(r'^(name|品名|商品).*(qty|数量)').hasMatch(lower)) return true;
    }
    if (lower.startsWith('total') || lower.startsWith('合计')) return true;
    return false;
  }
}

/// Resolve draft lines against catalog: barcode/SKU → name; mark create vs existing.
class PurchaseLineMatcher {
  PurchaseLineMatcher(this.repo);
  final PosRepository repo;

  Future<List<PurchaseDraftLine>> resolve(List<PurchaseDraftLine> input) async {
    final out = <PurchaseDraftLine>[];
    // Cache catalog names for name match
    final catalog = await repo.searchProducts('', limit: 5000);
    final byNormName = <String, Product>{};
    for (final p in catalog) {
      final n1 = normalizeProductName(p.nameZh);
      final n2 = normalizeProductName(p.nameEn);
      if (n1.isNotEmpty) byNormName.putIfAbsent(n1, () => p);
      if (n2.isNotEmpty) byNormName.putIfAbsent(n2, () => p);
    }

    for (final raw in input) {
      final line = raw.copy();
      Product? matched;

      final code = line.barcode.trim().isNotEmpty
          ? line.barcode.trim()
          : line.sku.trim();
      if (code.isNotEmpty) {
        matched = await repo.findByBarcodeOrSku(code);
        if (matched != null) {
          line.matchNote = '条码/SKU 匹配';
        }
      }
      if (matched == null && line.sku.trim().isNotEmpty && line.sku != code) {
        matched = await repo.findByBarcodeOrSku(line.sku.trim());
        if (matched != null) line.matchNote = 'SKU 匹配';
      }
      if (matched == null) {
        final key = normalizeProductName(line.name);
        if (key.isNotEmpty) {
          matched = byNormName[key];
          if (matched != null) {
            line.matchNote = '品名匹配';
          } else {
            // Soft contains match (single best)
            Product? soft;
            var softScore = 0;
            for (final e in byNormName.entries) {
              if (e.key.length < 2 || key.length < 2) continue;
              if (e.key.contains(key) || key.contains(e.key)) {
                final score = e.key.length < key.length ? e.key.length : key.length;
                if (score > softScore) {
                  softScore = score;
                  soft = e.value;
                }
              }
            }
            if (soft != null && softScore >= 4) {
              matched = soft;
              line.matchNote = '品名近似匹配（请核对）';
              line.confidence = (line.confidence * 0.85).clamp(0, 1);
            }
          }
        }
      }

      if (matched != null) {
        line.productId = matched.id;
        line.willCreate = false;
        if (line.name.trim().isEmpty) line.name = matched.nameZh;
        if (line.barcode.isEmpty) line.barcode = matched.barcode;
        if (line.sku.isEmpty) line.sku = matched.sku;
        // Keep invoice cost; sell stays catalog unless set
        line.sellPriceCents ??= matched.priceCents;
        if (line.unitCostCents <= 0 && matched.costCents > 0) {
          line.unitCostCents = matched.costCents;
        }
      } else {
        line.productId = null;
        line.willCreate = true;
        line.matchNote =
            line.matchNote.isEmpty ? '将新建商品' : '${line.matchNote} · 将新建';
        line.sellPriceCents ??= line.unitCostCents;
      }
      out.add(line);
    }
    return out;
  }

  /// Create missing products then [PosRepository.createPurchase].
  Future<void> commit({
    required List<PurchaseDraftLine> lines,
    required Supplier supplier,
    required String operator,
    String notes = '',
  }) async {
    final selected = lines.where((l) => l.selected).toList();
    if (selected.isEmpty) {
      throw StateError('请至少勾选一行 / Select at least one line');
    }

    final purchaseLines = <Map<String, Object?>>[];
    var total = 0;

    for (final line in selected) {
      String productId;
      String name;
      if (line.willCreate || line.productId == null) {
        final id = AppDatabase.newId();
        final cost = line.unitCostCents < 0 ? 0 : line.unitCostCents;
        final sell = line.effectiveSellCents < 0 ? cost : line.effectiveSellCents;
        final p = Product(
          id: id,
          nameZh: line.name.trim().isEmpty ? '未命名商品' : line.name.trim(),
          nameEn: '',
          sku: line.sku.trim().isNotEmpty
              ? line.sku.trim()
              : (line.barcode.trim().isNotEmpty
                  ? line.barcode.trim()
                  : id.substring(0, 8)),
          barcode: line.barcode.trim(),
          priceCents: sell,
          costCents: cost,
          stock: 0,
          unit: 'pcs',
          category: '',
        );
        await repo.upsertProduct(p);
        productId = id;
        name = p.nameZh;
        // So subsequent lines in same commit can reuse
        line.productId = id;
        line.willCreate = false;
      } else {
        productId = line.productId!;
        name = line.name;
        // Refresh cost on existing product from invoice unit cost when provided
        if (line.unitCostCents > 0) {
          final existing = await repo.getProduct(productId);
          if (existing != null && existing.costCents != line.unitCostCents) {
            await repo.upsertProduct(
              existing.copyWith(costCents: line.unitCostCents),
            );
          }
        }
      }
      final sub = (line.unitCostCents * line.qty).round();
      total += sub;
      purchaseLines.add({
        'productId': productId,
        'name': name,
        'qty': line.qty,
        'unitCostCents': line.unitCostCents,
        'subtotalCents': sub,
      });
    }

    await repo.createPurchase(
      supplierId: supplier.id,
      supplierName: supplier.name,
      lines: purchaseLines,
      totalCents: total,
      operator: operator,
      notes: notes,
    );
  }
}
