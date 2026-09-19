# 📅 الأسبوع الأول — خطة التطبيق

## 🎯 الهدف الأسبوعي

```
في نهاية الأسبوع سيكون لدينا:

✅ قاعدة بيانات محلية (SQLite) تعمل بالكامل
✅ كشف الاتصال بالانترنت يعمل
✅ Backend محلي يعمل
✅ الاختبار الأول على الديسكتوب
```

---

## 📊 توزيع الأيام

```
اليوم 1-2: LocalDatabase + SQLite (16 ساعة)
اليوم 3-4: ConnectivityService (8 ساعات)
اليوم 5: Backend Setup + Integration (12 ساعة)
اليوم 6-7: Testing + Refinement (8 ساعات)

المجموع: 44 ساعة = 11 ساعة يومياً
```

---

## 🔥 اليوم 1-2: LocalDatabase Implementation

### الصباح (اليوم 1)

#### 1. إنشاء البنية الأساسية (ساعة واحدة)

```bash
# 1. انتقل للمشروع
cd C:\Users\F\Downloads\itqan_erp

# 2. أنشئ المجلدات
mkdir -p lib/core/local_database/{models,services}
mkdir -p lib/core/local_database/migrations

# 3. تحقق من التبعيات (موجودة بالفعل)
flutter pub get
```

#### 2. إنشاء ملف LocalDatabase الرئيسي (3 ساعات)

```dart
// lib/core/local_database/local_db.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';

class LocalDatabase {
  static const String dbName = 'itqan_offline.db';
  static const int version = 1;
  static final LocalDatabase _instance = LocalDatabase._internal();

  late Database _db;

  LocalDatabase._internal();

  factory LocalDatabase() {
    return _instance;
  }

  // فحص إذا كانت معلّمة
  bool get isInitialized => _db != null;

  Future<void> initialize() async {
    if (isInitialized) return;

    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, dbName),
      version: version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    print('✅ LocalDatabase initialized at: ${join(dbPath, dbName)}');
    
    // طباعة بيانات الجداول
    await _printDatabaseInfo();
  }

  Future<void> _onCreate(Database db, int version) async {
    print('📦 Creating database tables...');

    // Products Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        code TEXT UNIQUE,
        name TEXT NOT NULL,
        category TEXT,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        min_quantity INTEGER DEFAULT 0,
        description TEXT,
        image_url TEXT,
        is_active INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    print('   ✓ products table created');

    // Invoices Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id TEXT PRIMARY KEY,
        invoice_number TEXT UNIQUE NOT NULL,
        customer_id TEXT,
        customer_name TEXT,
        subtotal REAL NOT NULL,
        tax REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        total REAL NOT NULL,
        payment_method TEXT,
        notes TEXT,
        status TEXT DEFAULT 'pending',
        sync_status TEXT DEFAULT 'pending',
        last_synced INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    print('   ✓ invoices table created');

    // Invoice Items Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id TEXT PRIMARY KEY,
        invoice_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        created_at INTEGER NOT NULL,
        FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');
    print('   ✓ invoice_items table created');

    // Customers Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        address TEXT,
        balance REAL DEFAULT 0,
        credit_limit REAL,
        is_active INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    print('   ✓ customers table created');

    // Sync Queue Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        record_id TEXT NOT NULL,
        data TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        INDEX idx_table_op(table_name, operation)
      )
    ''');
    print('   ✓ sync_queue table created');

    print('✅ All tables created successfully');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('📦 Upgrading database from $oldVersion to $newVersion');
    // سيتم إضافة logic للـ migration لاحقاً
  }

  Future<void> _printDatabaseInfo() async {
    try {
      final tables = await _db.query(
        'sqlite_master',
        where: "type = 'table' AND name NOT LIKE 'sqlite_%'",
      );

      print('\n📊 Database Structure:');
      for (final table in tables) {
        print('   Table: ${table['name']}');
      }
      print('');
    } catch (e) {
      print('Error printing database info: $e');
    }
  }

  // ============ PRODUCTS ============

  Future<void> insertProduct(Map<String, dynamic> product) async {
    try {
      await _db.insert(
        'products',
        {
          ...product,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'sync_status': 'pending',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('✅ Product inserted: ${product['id']}');
    } catch (e) {
      print('❌ Error inserting product: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getProducts({
    bool activeOnly = true,
  }) async {
    try {
      final query = activeOnly ? 'is_active = 1' : null;
      return await _db.query(
        'products',
        where: query,
        orderBy: 'name ASC',
      );
    } catch (e) {
      print('❌ Error fetching products: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getProduct(String id) async {
    try {
      final result = await _db.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return result.isNotEmpty ? result.first : null;
    } catch (e) {
      print('❌ Error fetching product: $e');
      return null;
    }
  }

  Future<void> updateProduct(String id, Map<String, dynamic> data) async {
    try {
      await _db.update(
        'products',
        {
          ...data,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      print('✅ Product updated: $id');
    } catch (e) {
      print('❌ Error updating product: $e');
      rethrow;
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _db.delete(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
      print('✅ Product deleted: $id');
    } catch (e) {
      print('❌ Error deleting product: $e');
      rethrow;
    }
  }

  // ============ INVOICES ============

  Future<String> createInvoice({
    required String customerId,
    required String customerName,
    required double subtotal,
    required double tax,
    required double discount,
    required double total,
    required String paymentMethod,
    String? notes,
  }) async {
    try {
      final invoiceId = const Uuid().v4();
      final invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';

      await _db.insert('invoices', {
        'id': invoiceId,
        'invoice_number': invoiceNumber,
        'customer_id': customerId,
        'customer_name': customerName,
        'subtotal': subtotal,
        'tax': tax,
        'discount': discount,
        'total': total,
        'payment_method': paymentMethod,
        'notes': notes,
        'status': 'pending',
        'sync_status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      print('✅ Invoice created: $invoiceId ($invoiceNumber)');
      return invoiceId;
    } catch (e) {
      print('❌ Error creating invoice: $e');
      rethrow;
    }
  }

  Future<void> addInvoiceItem({
    required String invoiceId,
    required String productId,
    required String productName,
    required int quantity,
    required double unitPrice,
  }) async {
    try {
      final itemId = const Uuid().v4();
      final totalPrice = quantity * unitPrice;

      await _db.insert('invoice_items', {
        'id': itemId,
        'invoice_id': invoiceId,
        'product_id': productId,
        'product_name': productName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total_price': totalPrice,
        'sync_status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      print('✅ Invoice item added: $itemId');
    } catch (e) {
      print('❌ Error adding invoice item: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getInvoices() async {
    try {
      return await _db.query(
        'invoices',
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('❌ Error fetching invoices: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getInvoiceItems(String invoiceId) async {
    try {
      return await _db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
    } catch (e) {
      print('❌ Error fetching invoice items: $e');
      return [];
    }
  }

  // ============ SYNC QUEUE ============

  Future<void> addToSyncQueue(
    String tableName,
    String operation,
    String recordId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _db.insert('sync_queue', {
        'id': const Uuid().v4(),
        'table_name': tableName,
        'operation': operation,
        'record_id': recordId,
        'data': jsonEncode(data),
        'retry_count': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('❌ Error adding to sync queue: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    try {
      return await _db.query(
        'sync_queue',
        orderBy: 'created_at ASC',
        where: 'retry_count < 5',
      );
    } catch (e) {
      print('❌ Error fetching sync queue: $e');
      return [];
    }
  }

  Future<void> markSyncItemAsSuccess(String syncId) async {
    try {
      await _db.delete(
        'sync_queue',
        where: 'id = ?',
        whereArgs: [syncId],
      );
    } catch (e) {
      print('❌ Error marking sync as success: $e');
    }
  }

  Future<void> incrementSyncRetry(String syncId, String? error) async {
    try {
      await _db.rawUpdate(
        'UPDATE sync_queue SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
        [error, syncId],
      );
    } catch (e) {
      print('❌ Error incrementing retry: $e');
    }
  }

  // ============ UTILITY ============

  Future<int> getLocalDataCount(String table) async {
    try {
      final result = await _db.rawQuery('SELECT COUNT(*) as count FROM $table');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> clearSyncQueue() async {
    try {
      await _db.delete('sync_queue');
      print('✅ Sync queue cleared');
    } catch (e) {
      print('❌ Error clearing sync queue: $e');
    }
  }

  Future<void> close() async {
    await _db.close();
  }
}
```

#### 3. اختبر LocalDatabase (2 ساعة)

```dart
// في main.dart أو ملف اختبار جديد

Future<void> testLocalDatabase() async {
  final db = LocalDatabase();
  await db.initialize();

  // اختبر إضافة منتج
  await db.insertProduct({
    'id': 'prod-001',
    'code': 'P001',
    'name': 'منتج تجريبي',
    'category': 'أجهزة',
    'price': 100.0,
    'quantity': 10,
  });

  // اختبر جلب المنتجات
  final products = await db.getProducts();
  print('Products: ${products.length}');
  for (final p in products) {
    print('  - ${p['name']}: ${p['price']}');
  }

  // اختبر إنشاء فاتورة
  final invoiceId = await db.createInvoice(
    customerId: 'cust-001',
    customerName: 'محمد أحمد',
    subtotal: 500.0,
    tax: 50.0,
    discount: 25.0,
    total: 525.0,
    paymentMethod: 'cash',
  );

  // اختبر إضافة عنصر فاتورة
  await db.addInvoiceItem(
    invoiceId: invoiceId,
    productId: 'prod-001',
    productName: 'منتج تجريبي',
    quantity: 5,
    unitPrice: 100.0,
  );

  // اختبر جلب الفواتير
  final invoices = await db.getInvoices();
  print('Invoices: ${invoices.length}');

  // طباعة Sync Queue
  final queue = await db.getPendingSyncItems();
  print('Pending Sync Items: ${queue.length}');
}

// في main():
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await testLocalDatabase();
  runApp(const KineticApp());
}
```

### المساء (اليوم 1)

#### 4. إضافة Providers (2 ساعة)

```dart
// lib/providers/database_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/local_database/local_db.dart';

final localDatabaseProvider = FutureProvider<LocalDatabase>((ref) async {
  final db = LocalDatabase();
  await db.initialize();
  return db;
});

// استخدام:
// final dbAsync = ref.watch(localDatabaseProvider);
// final products = await db.getProducts();
```

#### 5. مراجعة واختبار (1 ساعة)

```bash
# تشغيل التطبيق مع الاختبارات
flutter run -v

# يجب أن ترى في الـ console:
# ✅ LocalDatabase initialized at: ...
# 📊 Database Structure:
#    Table: products
#    Table: invoices
#    Table: invoice_items
#    Table: customers
#    Table: sync_queue
```

---

## 📱 اليوم 3-4: ConnectivityService Implementation

### اليوم 3 الصباح (3 ساعات)

#### 1. إنشاء ConnectivityService

```dart
// lib/core/connectivity/connectivity_service.dart

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final _instance = ConnectivityService._internal();

  factory ConnectivityService() {
    return _instance;
  }

  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  late StreamController<bool> _connectionStatusController;

  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  Future<void> initialize() async {
    _connectionStatusController = StreamController<bool>.broadcast();

    // الاستماع للتغييرات
    _connectivity.onConnectivityChanged.listen((result) {
      final isConnected = !result.contains(ConnectivityResult.none);
      _connectionStatusController.add(isConnected);

      if (isConnected) {
        print('🌐 Connected to internet');
        // سيتم تفعيل المزامنة هنا لاحقاً
      } else {
        print('🔌 Disconnected from internet');
      }
    });

    // فحص الحالة الأولية
    await checkConnection();
  }

  Future<bool> checkConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final isConnected = !result.contains(ConnectivityResult.none);
      _connectionStatusController.add(isConnected);
      return isConnected;
    } catch (e) {
      print('Error checking connectivity: $e');
      return false;
    }
  }

  void dispose() {
    _connectionStatusController.close();
  }
}
```

#### 2. دمج مع Riverpod (2 ساعة)

```dart
// lib/providers/connectivity_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/connectivity/connectivity_service.dart';

final connectivityServiceProvider = Provider((ref) {
  return ConnectivityService();
});

final connectionStatusProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  await service.initialize();
  
  yield* service.connectionStatusStream;
});
```

### اليوم 3 المساء + اليوم 4 (5 ساعات)

#### 3. إنشاء شاشة اختبار

```dart
// lib/features/testing/connectivity_test_screen.dart

class ConnectivityTestScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(connectionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('اختبار الاتصال')),
      body: Center(
        child: connectionStatus.when(
          data: (isConnected) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // أيقونة الاتصال
              Icon(
                isConnected ? Icons.cloud_done : Icons.cloud_off,
                size: 100,
                color: isConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 20),
              // نص الحالة
              Text(
                isConnected ? '🌐 متصل بالانترنت' : '🔌 بدون انترنت',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 40),
              // أزرار الاختبار
              ElevatedButton(
                onPressed: () async {
                  final service = ref.read(connectivityServiceProvider);
                  final isConnected = await service.checkConnection();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isConnected
                            ? 'متصل بالانترنت ✅'
                            : 'بدون انترنت ❌',
                      ),
                    ),
                  );
                },
                child: const Text('فحص الاتصال'),
              ),
            ],
          ),
          loading: () => const CircularProgressIndicator(),
          error: (err, stack) => Text('خطأ: $err'),
        ),
      ),
    );
  }
}
```

#### 4. اختبر على الجهاز (2 ساعة)

```bash
# 1. شغّل التطبيق
flutter run

# 2. اختبر بـ WiFi شغيل
# يجب أن تراه يعرض: 🌐 متصل بالانترنت

# 3. أطفئ WiFi
# يجب أن يتحول إلى: 🔌 بدون انترنت

# 4. اختبر الزر "فحص الاتصال"
# يجب أن يظهر رسالة التأكيد
```

---

## ⚙️ اليوم 5: Backend Setup

### الصباح (4 ساعات)

#### 1. إعداد SQL Server

```bash
# 1. تحقق من تشغيل SQL Server
Get-Service -Name "MSSQLSERVER" | Select-Object Status

# 2. إنشاء قاعدة البيانات
sqlcmd -S localhost -Q "CREATE DATABASE kinetic_erp;"

# 3. تشغيل المخطط
sqlcmd -S localhost -d kinetic_erp -i docs\DATABASE_SCHEMA_SQLSERVER.sql

# 4. تحقق من الجداول
sqlcmd -S localhost -d kinetic_erp -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES;"
```

#### 2. إعداد Backend

```bash
# 1. انتقل للمجلد
cd backend\KineticEnterprise.Api

# 2. حمّل التبعيات
dotnet restore

# 3. عدّل appsettings.json
# (استبدل بيانات الاتصال الفعلية)

# 4. شغّل الـ Migrations (إن وجدت)
dotnet ef database update

# 5. شغّل البرنامج
dotnet run

# يجب أن تراه يعرض:
# info: Microsoft.AspNetCore.Hosting.Diagnostics[1]
#       Request starting HTTP/2 GET https://localhost:5001/swagger
```

### المساء (5 ساعات)

#### 3. اختبر الاتصال من التطبيق

```dart
// lib/core/network/api_client.dart

import 'package:dio/dio.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late Dio _dio;

  factory ApiClient() {
    return _instance;
  }

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://localhost:5001',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    // أضف Interceptor للـ logging
    _dio.interceptors.add(
      LoggingInterceptor(),
    );
  }

  Future<Response> get(String path) async {
    try {
      final response = await _dio.get(path);
      print('✅ GET $path: ${response.statusCode}');
      return response;
    } catch (e) {
      print('❌ GET $path failed: $e');
      rethrow;
    }
  }

  Future<Response> post(String path, {required dynamic data}) async {
    try {
      final response = await _dio.post(path, data: data);
      print('✅ POST $path: ${response.statusCode}');
      return response;
    } catch (e) {
      print('❌ POST $path failed: $e');
      rethrow;
    }
  }
}

class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print('📤 [${options.method}] ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('📥 Response: ${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('❌ Error: ${err.message}');
    handler.next(err);
  }
}
```

#### 4. شاشة اختبار الـ Backend

```dart
// lib/features/testing/backend_test_screen.dart

class BackendTestScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار Backend')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                try {
                  final apiClient = ApiClient();
                  final response = await apiClient.get('/api/products');
                  print('✅ Backend reachable');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ متصل بـ Backend')),
                  );
                } catch (e) {
                  print('❌ Backend unreachable: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('❌ Backend غير متاح: $e')),
                  );
                }
              },
              child: const Text('اختبر الاتصال بـ Backend'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 🧪 اليوم 6-7: Testing & Refinement

### اليوم 6 (4 ساعات)

#### اختبر جميع المكونات:

```bash
# 1. تشغيل جميع الاختبارات
flutter test

# 2. تحليل الكود
flutter analyze

# 3. تشغيل التطبيق
flutter run
```

#### اختبر السيناريوهات:

```
✅ اختبار LocalDatabase:
   - إضافة منتجات
   - تحديث المنتجات
   - حذف المنتجات
   - إنشاء فاتورات
   - جلب البيانات

✅ اختبار Connectivity:
   - تشغيل WiFi ✓
   - إطفاء WiFi ✓
   - تشغيل مرة أخرى ✓

✅ اختبار Backend:
   - Backend مشغّل ✓
   - اتصال الـ API ✓
```

### اليوم 7 (4 ساعات)

#### تحسينات وإصلاحات

```dart
// 1. أضف error handling أفضل
// 2. أضف loading indicators
// 3. أضف success messages
// 4. تحسين الـ UI
// 5. تحسين الأداء
```

---

## 📋 قائمة التحقق — نهاية الأسبوع

```
LocalDatabase:
[ ] الجداول مُنشأة بنجاح
[ ] إضافة المنتجات يعمل
[ ] جلب المنتجات يعمل
[ ] تحديث المنتجات يعمل
[ ] حذف المنتجات يعمل
[ ] إنشاء الفواتير يعمل
[ ] Sync Queue يعمل

ConnectivityService:
[ ] يكتشف الاتصال بالانترنت
[ ] يعطي notifications عند التغيير
[ ] يعمل مع WiFi و Mobile Data

Backend:
[ ] SQL Server يعمل
[ ] قاعدة البيانات مُنشأة
[ ] API يستقبل الطلبات
[ ] التطبيق يتصل بـ Backend

Tests:
[ ] لا توجد أخطاء compilation
[ ] flutter analyze نظيف
[ ] tests تمر جميعها
[ ] التطبيق يعمل بدون مشاكل
```

---

## 🎯 النتيجة النهائية

في نهاية الأسبوع سيكون لدينا:

```
✅ قاعدة بيانات محلية تعمل 100%
✅ كشف الاتصال يعمل
✅ Backend محلي يعمل
✅ الاتصال بين التطبيق والـ Backend يعمل
✅ Sync Queue جاهز للمزامنة

الأسبوع التالي:
└─ سننطلق مباشرة لـ SyncEngine
```

---

## 🚀 ابدأ الآن!

```bash
# الخطوة 1: انتقل للمشروع
cd C:\Users\F\Downloads\itqan_erp

# الخطوة 2: افتح IDE
code .
# أو
"C:\Program Files\JetBrains\IntelliJ IDEA\bin\idea.exe" .

# الخطوة 3: أنشئ الملفات الأولى
mkdir -p lib/core/local_database

# الخطوة 4: ابدأ بالكود
# انسخ code LocalDatabase من هذا الملف
```

---

**توفيق! ابدأ من اليوم الأول! 💪**
