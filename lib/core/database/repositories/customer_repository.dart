import 'base_repository.dart';

/// نموذج الزبون
class Customer {
  final String id;
  final String code;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? country;
  final double creditLimit;
  final double creditUsed;
  final String? taxId;
  final String? customerType;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool synced;

  const Customer({
    required this.id,
    required this.code,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.country,
    this.creditLimit = 0,
    this.creditUsed = 0,
    this.taxId,
    this.customerType,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.synced = false,
  });

  double get creditAvailable => creditLimit - creditUsed;
  bool get creditOverflow => creditUsed > creditLimit;

  Customer copyWith({
    String? id,
    String? code,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? country,
    double? creditLimit,
    double? creditUsed,
    String? taxId,
    String? customerType,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return Customer(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      city: city ?? this.city,
      country: country ?? this.country,
      creditLimit: creditLimit ?? this.creditLimit,
      creditUsed: creditUsed ?? this.creditUsed,
      taxId: taxId ?? this.taxId,
      customerType: customerType ?? this.customerType,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }
}

/// Repository للزبائن
class CustomerRepository extends BaseRepository<Customer> {
  @override
  String get tableName => 'customers';

  @override
  Customer fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      address: json['address'],
      city: json['city'],
      country: json['country'],
      creditLimit: (json['credit_limit'] ?? 0).toDouble(),
      creditUsed: (json['credit_used'] ?? 0).toDouble(),
      taxId: json['tax_id'],
      customerType: json['customer_type'],
      isActive: (json['is_active'] ?? 1) == 1,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      synced: (json['synced'] ?? 0) == 1,
    );
  }

  @override
  Map<String, dynamic> toJson(Customer entity) {
    return {
      'id': entity.id,
      'code': entity.code,
      'name': entity.name,
      'email': entity.email,
      'phone': entity.phone,
      'address': entity.address,
      'city': entity.city,
      'country': entity.country,
      'credit_limit': entity.creditLimit,
      'credit_used': entity.creditUsed,
      'tax_id': entity.taxId,
      'customer_type': entity.customerType,
      'is_active': entity.isActive ? 1 : 0,
      'created_at': entity.createdAt?.toIso8601String(),
      'updated_at': entity.updatedAt?.toIso8601String(),
      'synced': entity.synced ? 1 : 0,
    };
  }

  /// البحث عن الزبائن بالاسم أو البريد
  Future<List<Customer>> searchByNameOrEmail(String query) async {
    final lowerQuery = query.toLowerCase();
    return search(
      where: 'LOWER(name) LIKE ? OR LOWER(email) LIKE ? OR code LIKE ?',
      whereArgs: ['%$lowerQuery%', '%$lowerQuery%', '%$query%'],
    );
  }

  /// الحصول على الزبائن الفعالين فقط
  Future<List<Customer>> getActive() async {
    return search(where: 'is_active = 1');
  }

  /// الحصول على الزبائن الذين تجاوزوا الحد الائتماني
  Future<List<Customer>> getCreditOverflow() async {
    return search(where: 'credit_used > credit_limit');
  }

  /// الحصول على الكود التالي للزبون
  Future<String> getNextCode() async {
    final all = await getAll();
    if (all.isEmpty) return 'CUST-0001';

    final maxCode = all
        .map((c) => int.tryParse(c.code.replaceFirst('CUST-', '')) ?? 0)
        .reduce((a, b) => a > b ? a : b);

    return 'CUST-${(maxCode + 1).toString().padLeft(4, '0')}';
  }

  /// تحديث الرصيد المستخدم
  Future<int> updateCreditUsed(String id, double newCreditUsed) async {
    final customer = await getById(id);
    if (customer == null) return 0;
    return update(id, customer.copyWith(creditUsed: newCreditUsed));
  }

  /// تقليل الرصيد المستخدم (عند الدفع)
  Future<int> decreaseCreditUsed(String id, double amount) async {
    final customer = await getById(id);
    if (customer == null) return 0;

    final newCreditUsed = (customer.creditUsed - amount);
    final clampedValue = newCreditUsed < 0 ? 0.0 : newCreditUsed;
    return updateCreditUsed(id, clampedValue);
  }

  /// زيادة الرصيد المستخدم (عند الفاتورة)
  Future<int> increaseCreditUsed(String id, double amount) async {
    final customer = await getById(id);
    if (customer == null) return 0;

    return updateCreditUsed(id, customer.creditUsed + amount);
  }

  /// الحصول على إجمالي الرصيد المستخدم
  Future<double> getTotalCreditUsed() async {
    final all = await getAll();
    double total = 0.0;
    for (final customer in all) {
      total += customer.creditUsed;
    }
    return total;
  }
}
