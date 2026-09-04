class Product {
  final String id;
  final String nameZh;
  final String nameEn;
  final String sku;
  final String barcode;
  final int priceCents;
  final int costCents;
  final double stock;
  final String unit;
  final String category;
  final int isDeleted;
  final String imagePath;
  final double reorderLevel;

  const Product({
    required this.id,
    required this.nameZh,
    required this.nameEn,
    required this.sku,
    required this.barcode,
    required this.priceCents,
    this.costCents = 0,
    this.stock = 0,
    this.unit = 'pcs',
    this.category = '',
    this.isDeleted = 0,
    this.imagePath = '',
    this.reorderLevel = 0,
  });

  String get label => '$nameZh / $nameEn';

  bool get hasImage => imagePath.trim().isNotEmpty;

  Product copyWith({
    String? nameZh,
    String? nameEn,
    String? sku,
    String? barcode,
    int? priceCents,
    int? costCents,
    double? stock,
    String? unit,
    String? category,
    int? isDeleted,
    String? imagePath,
    double? reorderLevel,
  }) =>
      Product(
        id: id,
        nameZh: nameZh ?? this.nameZh,
        nameEn: nameEn ?? this.nameEn,
        sku: sku ?? this.sku,
        barcode: barcode ?? this.barcode,
        priceCents: priceCents ?? this.priceCents,
        costCents: costCents ?? this.costCents,
        stock: stock ?? this.stock,
        unit: unit ?? this.unit,
        category: category ?? this.category,
        isDeleted: isDeleted ?? this.isDeleted,
        imagePath: imagePath ?? this.imagePath,
        reorderLevel: reorderLevel ?? this.reorderLevel,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name_zh': nameZh,
        'name_en': nameEn,
        'sku': sku,
        'barcode': barcode,
        'price_cents': priceCents,
        'cost_cents': costCents,
        'stock': stock,
        'unit': unit,
        'category': category,
        'is_deleted': isDeleted,
        'image_path': imagePath,
        'reorder_level': reorderLevel,
      };

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id']! as String,
        nameZh: m['name_zh']! as String,
        nameEn: m['name_en']! as String,
        sku: (m['sku'] as String?) ?? '',
        barcode: (m['barcode'] as String?) ?? '',
        priceCents: m['price_cents']! as int,
        costCents: (m['cost_cents'] as int?) ?? 0,
        stock: (m['stock'] as num?)?.toDouble() ?? 0,
        unit: (m['unit'] as String?) ?? 'pcs',
        category: (m['category'] as String?) ?? '',
        isDeleted: (m['is_deleted'] as int?) ?? 0,
        imagePath: (m['image_path'] as String?) ?? '',
        reorderLevel: (m['reorder_level'] as num?)?.toDouble() ?? 0,
      );

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        nameZh: j['nameZh'] as String,
        nameEn: j['nameEn'] as String,
        sku: j['sku'] as String? ?? '',
        barcode: j['barcode'] as String? ?? '',
        priceCents: j['priceCents'] as int,
        costCents: j['costCents'] as int? ?? 0,
        stock: (j['stock'] as num?)?.toDouble() ?? 0,
        unit: j['unit'] as String? ?? 'pcs',
        category: j['category'] as String? ?? '',
        imagePath: j['imagePath'] as String? ?? j['image_path'] as String? ?? '',
        reorderLevel:
            (j['reorderLevel'] as num?)?.toDouble() ??
            (j['reorder_level'] as num?)?.toDouble() ??
            0,
      );
}

class Category {
  final String id;
  final String name;
  final int isDeleted;
  final String updatedAt;

  const Category({
    required this.id,
    required this.name,
    this.isDeleted = 0,
    this.updatedAt = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'is_deleted': isDeleted,
        'updated_at': updatedAt,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id']! as String,
        name: m['name']! as String,
        isDeleted: (m['is_deleted'] as int?) ?? 0,
        updatedAt: (m['updated_at'] as String?) ?? '',
      );
}
