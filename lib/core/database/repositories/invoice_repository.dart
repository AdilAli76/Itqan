import '../sqlite_database.dart';
import 'base_repository.dart';

/// نموذج الفاتورة
class Invoice {
  final String id;
  final String code;
  final String customerId;
  final String branchId;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final double totalAmount;
  final double discountAmount;
  final double taxAmount;
  final double netAmount;
  final String paymentStatus;
  final String invoiceStatus;
  final String? notes;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool synced;

  const Invoice({
    required this.id,
    required this.code,
    required this.customerId,
    required this.branchId,
    required this.invoiceDate,
    this.dueDate,
    this.totalAmount = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.netAmount = 0,
    this.paymentStatus = 'PENDING',
    this.invoiceStatus = 'DRAFT',
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.synced = false,
  });

  Invoice copyWith({
    String? id,
    String? code,
    String? customerId,
    String? branchId,
    DateTime? invoiceDate,
    DateTime? dueDate,
    double? totalAmount,
    double? discountAmount,
    double? taxAmount,
    double? netAmount,
    String? paymentStatus,
    String? invoiceStatus,
    String? notes,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? synced,
  }) {
    return Invoice(
      id: id ?? this.id,
      code: code ?? this.code,
      customerId: customerId ?? this.customerId,
      branchId: branchId ?? this.branchId,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      totalAmount: totalAmount ?? this.totalAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      netAmount: netAmount ?? this.netAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      invoiceStatus: invoiceStatus ?? this.invoiceStatus,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
    );
  }
}

/// نموذج بند الفاتورة
class InvoiceItem {
  final String id;
  final String invoiceId;
  final String productId;
  final double quantity;
  final double unitPrice;
  final double discountPercent;
  final double lineTotal;
  final DateTime? createdAt;

  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.discountPercent = 0,
    this.lineTotal = 0,
    this.createdAt,
  });
}

/// Repository للفواتير
class InvoiceRepository extends BaseRepository<Invoice> {
  @override
  String get tableName => 'invoices';

  @override
  Invoice fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      customerId: json['customer_id'] ?? '',
      branchId: json['branch_id'] ?? '',
      invoiceDate: DateTime.parse(json['invoice_date'] ?? DateTime.now().toString()),
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      discountAmount: (json['discount_amount'] ?? 0).toDouble(),
      taxAmount: (json['tax_amount'] ?? 0).toDouble(),
      netAmount: (json['net_amount'] ?? 0).toDouble(),
      paymentStatus: json['payment_status'] ?? 'PENDING',
      invoiceStatus: json['invoice_status'] ?? 'DRAFT',
      notes: json['notes'],
      createdBy: json['created_by'],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      synced: (json['synced'] ?? 0) == 1,
    );
  }

  @override
  Map<String, dynamic> toJson(Invoice entity) {
    return {
      'id': entity.id,
      'code': entity.code,
      'customer_id': entity.customerId,
      'branch_id': entity.branchId,
      'invoice_date': entity.invoiceDate.toIso8601String(),
      'due_date': entity.dueDate?.toIso8601String(),
      'total_amount': entity.totalAmount,
      'discount_amount': entity.discountAmount,
      'tax_amount': entity.taxAmount,
      'net_amount': entity.netAmount,
      'payment_status': entity.paymentStatus,
      'invoice_status': entity.invoiceStatus,
      'notes': entity.notes,
      'created_by': entity.createdBy,
      'created_at': entity.createdAt?.toIso8601String(),
      'updated_at': entity.updatedAt?.toIso8601String(),
      'synced': entity.synced ? 1 : 0,
    };
  }

  /// الحصول على الفواتير حسب الزبون
  Future<List<Invoice>> getByCustomer(String customerId) async {
    return search(
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'invoice_date DESC',
    );
  }

  /// الحصول على الفواتير المعلقة الدفع
  Future<List<Invoice>> getPending() async {
    return search(
      where: 'payment_status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'due_date ASC',
    );
  }

  /// الحصول على الكود التالي للفاتورة
  Future<String> getNextCode() async {
    final all = await getAll();
    if (all.isEmpty) return 'INV-0001';

    final maxCode = all
        .map((i) => int.tryParse(i.code.replaceFirst('INV-', '')) ?? 0)
        .reduce((a, b) => a > b ? a : b);

    return 'INV-${(maxCode + 1).toString().padLeft(4, '0')}';
  }

  /// إنشاء فاتورة مع البنود
  Future<String> createWithItems(
    Invoice invoice,
    List<InvoiceItem> items,
  ) async {
    return withTransaction((txn) async {
      // إنشاء الفاتورة
      final json = toJson(invoice);
      json['id'] ??= '';
      json['created_at'] ??= DateTime.now().toIso8601String();
      json['updated_at'] ??= DateTime.now().toIso8601String();

      await txn.insert('invoices', json);
      final invoiceId = json['id'];

      // إدراج البنود
      for (final item in items) {
        await txn.insert(
          'invoice_items',
          {
            'id': item.id,
            'invoice_id': invoiceId,
            'product_id': item.productId,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'discount_percent': item.discountPercent,
            'line_total': item.lineTotal,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
      }

      return invoiceId;
    });
  }

  /// الحصول على بنود الفاتورة
  Future<List<InvoiceItem>> getItems(String invoiceId) async {
    final results = await SqliteDatabase.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );

    return results
        .map((json) => InvoiceItem(
              id: json['id'] ?? '',
              invoiceId: json['invoice_id'] ?? '',
              productId: json['product_id'] ?? '',
              quantity: (json['quantity'] ?? 0).toDouble(),
              unitPrice: (json['unit_price'] ?? 0).toDouble(),
              discountPercent: (json['discount_percent'] ?? 0).toDouble(),
              lineTotal: (json['line_total'] ?? 0).toDouble(),
              createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
            ))
        .toList();
  }

  /// الحصول على إجمالي الفواتير حسب الحالة
  Future<double> getTotalByStatus(String status) async {
    final invoices = await search(where: 'payment_status = ?', whereArgs: [status]);
    double total = 0.0;
    for (final invoice in invoices) {
      total += invoice.netAmount;
    }
    return total;
  }

  /// الحصول على إجمالي الفواتير اليومية
  Future<double> getTodayTotal() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

    final invoices = await search(
      where: 'invoice_date >= ? AND invoice_date <= ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
    );

    double total = 0.0;
    for (final invoice in invoices) {
      total += invoice.netAmount;
    }
    return total;
  }
}
