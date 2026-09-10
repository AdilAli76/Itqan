import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sqlite_database.dart';
import 'repositories/product_repository.dart';
import 'repositories/customer_repository.dart';
import 'repositories/invoice_repository.dart';

// ============= Database =============

/// مزود قاعدة البيانات
final databaseProvider = Provider<SqliteDatabase>((ref) {
  return SqliteDatabase();
});

// ============= Repositories =============

/// مزود Repository المنتجات
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

/// مزود Repository الزبائن
final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository();
});

/// مزود Repository الفواتير
final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepository();
});

// ============= Products State =============

/// حالة قائمة المنتجات
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.getAll(orderBy: 'name ASC');
});

/// حالة المنتجات النشطة فقط
final activeProductsProvider = FutureProvider<List<Product>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.getActive();
});

/// حالة المنتجات ذات المخزون المنخفض
final lowStockProductsProvider = FutureProvider<List<Product>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.getLowStock();
});

/// إجمالي قيمة المخزون
final inventoryValueProvider = FutureProvider<double>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.getTotalInventoryValue();
});

// ============= Customers State =============

/// حالة قائمة الزبائن
final customersProvider = FutureProvider<List<Customer>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getAll(orderBy: 'name ASC');
});

/// حالة الزبائن النشطين فقط
final activeCustomersProvider = FutureProvider<List<Customer>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getActive();
});

/// حالة الزبائن الذين تجاوزوا الحد الائتماني
final creditOverflowCustomersProvider = FutureProvider<List<Customer>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getCreditOverflow();
});

/// إجمالي الرصيد المستخدم
final totalCreditUsedProvider = FutureProvider<double>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getTotalCreditUsed();
});

// ============= Invoices State =============

/// حالة قائمة الفواتير
final invoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final repo = ref.watch(invoiceRepositoryProvider);
  return repo.getAll(orderBy: 'invoice_date DESC');
});

/// حالة الفواتير المعلقة الدفع
final pendingInvoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final repo = ref.watch(invoiceRepositoryProvider);
  return repo.getPending();
});

/// إجمالي الفواتير اليومية
final todayInvoicesProvider = FutureProvider<double>((ref) async {
  final repo = ref.watch(invoiceRepositoryProvider);
  return repo.getTodayTotal();
});

// ============= Search =============

/// البحث عن المنتجات
final searchProductsProvider = FutureProvider.family<List<Product>, String>((ref, query) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.searchByNameOrCode(query);
});

/// البحث عن الزبائن
final searchCustomersProvider = FutureProvider.family<List<Customer>, String>((ref, query) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.searchByNameOrEmail(query);
});

// ============= Database Statistics =============

/// إحصائيات قاعدة البيانات
final databaseStatsProvider = FutureProvider<DatabaseStats>((ref) async {
  return SqliteDatabase.getStats();
});
