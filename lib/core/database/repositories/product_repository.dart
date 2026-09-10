import 'base_repository.dart';

/// نموذج المنتج
class Product {
  final String id;
  final String code;
  final String name;
  final String? description;
  final String? category;
  final String? unit;
  final double purchasePrice;
  final double sellingPrice;
  final int quantity;
  final int reorderLevel;
  final String? supplierId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool synced;

  const Product({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.category,
    this.unit,
    this.purchasePrice = 0,
    this.sellingPrice = 0,
    this.quantity = 0,
    this.reorderLevel = 10,
    this.supplierId,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.synced = false,
  });

  Product copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    String? category,
    String? unit,
    double? purchasePrice,
    double? sellingPrice,
    int? quantity,
    int? reorderLevel,
    String? supplierId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return Product(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      quantity: quantity ?? this.quantity,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      supplierId: supplierId ?? this.supplierId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }
}

/// Repository للمنتجات
class ProductRepository extends BaseRepository<Product> {
  @override
  String get tableName => 'products';

  @override
  Product fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      category: json['category'],
      unit: json['unit'],
      purchasePrice: (json['purchase_price'] ?? 0).toDouble(),
      sellingPrice: (json['selling_price'] ?? 0).toDouble(),
      quantity: json['quantity'] ?? 0,
      reorderLevel: json['reorder_level'] ?? 10,
      supplierId: json['supplier_id'],
      isActive: (json['is_active'] ?? 1) == 1,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      synced: (json['synced'] ?? 0) == 1,
    );
  }

  @override
  Map<String, dynamic> toJson(Product entity) {
    return {
      'id': entity.id,
      'code': entity.code,
      'name': entity.name,
      'description': entity.description,
      'category': entity.category,
      'unit': entity.unit,
      'purchase_price': entity.purchasePrice,
      'selling_price': entity.sellingPrice,
      'quantity': entity.quantity,
      'reorder_level': entity.reorderLevel,
      'supplier_id': entity.supplierId,
      'is_active': entity.isActive ? 1 : 0,
      'created_at': entity.createdAt?.toIso8601String(),
      'updated_at': entity.updatedAt?.toIso8601String(),
      'synced': entity.synced ? 1 : 0,
    };
  }

  /// البحث عن منتجات بالاسم أو الكود
  Future<List<Product>> searchByNameOrCode(String query) async {
    final lowerQuery = query.toLowerCase();
    return search(
      where: 'LOWER(name) LIKE ? OR LOWER(code) LIKE ? OR LOWER(category) LIKE ?',
      whereArgs: ['%$lowerQuery%', '%$lowerQuery%', '%$lowerQuery%'],
    );
  }

  /// الحصول على المنتجات الفعالة فقط
  Future<List<Product>> getActive() async {
    return search(where: 'is_active = 1');
  }

  /// الحصول على المنتجات التي تحتاج إلى إعادة طلب
  Future<List<Product>> getLowStock() async {
    return search(
      where: 'quantity <= reorder_level',
      orderBy: 'quantity ASC',
    );
  }

  /// الحصول على المنتجات حسب الفئة
  Future<List<Product>> getByCategory(String category) async {
    return search(where: 'category = ?', whereArgs: [category]);
  }

  /// الحصول على الكود التالي للمنتج
  Future<String> getNextCode() async {
    final all = await getAll();
    if (all.isEmpty) return 'PRD-0001';

    final maxCode = all
        .map((p) => int.tryParse(p.code.replaceFirst('PRD-', '')) ?? 0)
        .reduce((a, b) => a > b ? a : b);

    return 'PRD-${(maxCode + 1).toString().padLeft(4, '0')}';
  }

  /// تحديث الكمية
  Future<int> updateQuantity(String id, int newQuantity) async {
    return update(id, (await getById(id))!.copyWith(quantity: newQuantity));
  }

  /// حساب القيمة الإجمالية للمخزون
  Future<double> getTotalInventoryValue() async {
    final all = await getAll();
    double total = 0.0;
    for (final product in all) {
      total += product.quantity * product.sellingPrice;
    }
    return total;
  }
}
