# 🛠️ خطوات تطبيق Offline Mode — خطوة بخطوة

## 📌 الملخص السريع

| المكون | الحالة | الملف |
|--------|--------|------|
| SQLite Local DB | ⏳ مطلوب | `lib/core/local_database/local_db.dart` |
| Connectivity Monitor | ⏳ مطلوب | `lib/core/connectivity/connectivity_service.dart` |
| Sync Engine | ⏳ مطلوب | `lib/core/sync/sync_engine.dart` |
| Providers | ⏳ مطلوب | `lib/providers/offline_providers.dart` |
| Backend Sync API | ⏳ مطلوب | `backend/Controllers/SyncController.cs` |

---

## 🔧 الخطوة 1: إنشاء LocalDatabase (4 ساعات)

### 1.1 إنشاء الملف الأساسي

```bash
cd lib/core
mkdir -p local_database/{models,services}
touch local_database/local_db.dart
```

### 1.2 كود LocalDatabase الكامل

```dart
// lib/core/local_database/local_db.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class LocalDatabase {
  static const String dbName = 'itqan_offline.db';
  static const int version = 1;
  
  late Database _db;
  
  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, dbName),
      version: version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    print('✅ LocalDatabase initialized');
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
    
    print('✅ Tables created');
  }
  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('📦 Upgrading database from $oldVersion to $newVersion');
    // أضف logic للـ migration هنا
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
      
      // أضف إلى Sync Queue
      await addToSyncQueue(
        'products',
        'INSERT',
        product['id'],
        product,
      );
      
      print('✅ Product inserted: ${product['id']}');
    } catch (e) {
      print('❌ Error inserting product: $e');
      rethrow;
    }
  }
  
  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      return await _db.query(
        'products',
        where: 'is_active = 1',
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
      
      await addToSyncQueue('products', 'UPDATE', id, data);
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
      
      await addToSyncQueue('products', 'DELETE', id, {'id': id});
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
      
      print('✅ Invoice created: $invoiceId');
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
  
  Future<void> clearOldData({int daysOld = 90}) async {
    try {
      final cutoffTime = DateTime.now()
          .subtract(Duration(days: daysOld))
          .millisecondsSinceEpoch;
      
      await _db.delete(
        'invoices',
        where: 'created_at < ? AND status = "completed"',
        whereArgs: [cutoffTime],
      );
      
      print('✅ Old data cleared');
    } catch (e) {
      print('❌ Error clearing old data: $e');
    }
  }
  
  Future<void> close() async {
    await _db.close();
  }
}
```

### 1.3 اختبر LocalDatabase

```dart
// في main.dart أو test
final db = LocalDatabase();
await db.initialize();

// تجربة إضافة منتج
await db.insertProduct({
  'id': 'prod-001',
  'code': 'P001',
  'name': 'منتج تجريبي',
  'price': 100.0,
  'quantity': 10,
});

// جلب المنتجات
final products = await db.getProducts();
print(products);
```

---

## 🔌 الخطوة 2: إنشاء ConnectivityService (2 ساعة)

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
    
    // Listen to connectivity changes
    _connectivity.onConnectivityChanged.listen((result) {
      final isConnected = !result.contains(ConnectivityResult.none);
      _connectionStatusController.add(isConnected);
      
      if (isConnected) {
        print('🌐 Connected to internet');
        // ابدأ المزامنة هنا
      } else {
        print('🔌 Disconnected from internet');
      }
    });
    
    // Check initial status
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

---

## ⚙️ الخطوة 3: إنشاء SyncEngine (6 ساعات)

```dart
// lib/core/sync/sync_engine.dart

import 'package:dio/dio.dart';

class SyncEngine {
  final LocalDatabase _localDb;
  final Dio _apiClient;
  final String _baseUrl;
  
  SyncEngine({
    required LocalDatabase localDb,
    required Dio apiClient,
    required String baseUrl,
  })  : _localDb = localDb,
        _apiClient = apiClient,
        _baseUrl = baseUrl;
  
  Future<void> synchronize() async {
    print('🔄 Starting synchronization...');
    
    try {
      // 1. إرسال البيانات المعلقة
      await _syncPendingData();
      
      // 2. جلب البيانات الجديدة
      await _pullRemoteData();
      
      print('✅ Synchronization completed');
    } catch (e) {
      print('❌ Sync error: $e');
    }
  }
  
  Future<void> _syncPendingData() async {
    print('📤 Syncing pending data...');
    
    final pendingItems = await _localDb.getPendingSyncItems();
    
    for (final item in pendingItems) {
      try {
        final data = jsonDecode(item['data']);
        final operation = item['operation'];
        final tableName = item['table_name'];
        
        // اختر العملية
        switch (operation) {
          case 'INSERT':
            await _apiClient.post(
              '$_baseUrl/api/$tableName',
              data: data,
            );
            break;
          case 'UPDATE':
            await _apiClient.put(
              '$_baseUrl/api/$tableName/${item['record_id']}',
              data: data,
            );
            break;
          case 'DELETE':
            await _apiClient.delete(
              '$_baseUrl/api/$tableName/${item['record_id']}',
            );
            break;
        }
        
        // حذف من Sync Queue عند النجاح
        await _localDb.markSyncItemAsSuccess(item['id']);
        print('✅ Synced: ${item['table_name']} - ${item['operation']}');
        
      } catch (e) {
        // أضف إلى retry count
        await _localDb.incrementSyncRetry(
          item['id'],
          e.toString(),
        );
        print('⚠️ Sync failed (will retry): $e');
      }
    }
  }
  
  Future<void> _pullRemoteData() async {
    print('📥 Pulling remote data...');
    
    try {
      // جلب المنتجات الحديثة
      final response = await _apiClient.get(
        '$_baseUrl/api/products',
      );
      
      final products = List<Map<String, dynamic>>.from(
        response.data ?? [],
      );
      
      for (final product in products) {
        await _localDb.insertProduct(product);
      }
      
      print('✅ ${products.length} products synced');
      
      // يمكن فعل الشيء نفسه للفواتير والعملاء
      
    } catch (e) {
      print('❌ Error pulling remote data: $e');
    }
  }
}
```

---

## 📦 الخطوة 4: ربط المكونات مع Riverpod

```dart
// lib/providers/offline_providers.dart

final localDatabaseProvider = Provider((ref) {
  return LocalDatabase();
});

final connectivityServiceProvider = Provider((ref) {
  return ConnectivityService();
});

final syncEngineProvider = Provider((ref) {
  final localDb = ref.watch(localDatabaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  
  return SyncEngine(
    localDb: localDb,
    apiClient: apiClient,
    baseUrl: 'https://localhost:5001',
  );
});

// Stream للمراقبة
final connectionStatusProvider = StreamProvider((ref) async* {
  final connectivity = ref.watch(connectivityServiceProvider);
  await connectivity.initialize();
  
  yield* connectivity.connectionStatusStream;
});

// Auto-sync عند الاتصال
final autoSyncProvider = FutureProvider((ref) async {
  final isConnected = await ref.watch(connectionStatusProvider).when(
    data: (connected) => connected,
    loading: () => false,
    error: (err, stack) => false,
  );
  
  if (isConnected) {
    final syncEngine = ref.watch(syncEngineProvider);
    await syncEngine.synchronize();
  }
});

// Products من Local أو Remote
final productsProvider = FutureProvider((ref) async {
  final localDb = ref.watch(localDatabaseProvider);
  
  try {
    // حاول جلب من Remote
    final isConnected = await ref.watch(connectionStatusProvider).when(
      data: (connected) => connected,
      loading: () => false,
      error: (err, stack) => false,
    );
    
    if (isConnected) {
      final apiClient = ref.watch(apiClientProvider);
      final response = await apiClient.get('/api/products');
      
      // احفظ في Local
      for (final product in response.data) {
        await localDb.insertProduct(product);
      }
      
      return List<Map<String, dynamic>>.from(response.data ?? []);
    }
  } catch (e) {
    print('Failed to fetch remote: $e');
  }
  
  // استخدم Local كـ fallback
  return await localDb.getProducts();
});
```

---

## 🔗 الخطوة 5: استخدم في الشاشات

```dart
// في أي شاشة

class ProductsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final isConnected = ref.watch(connectionStatusProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتجات'),
        actions: [
          isConnected.when(
            data: (connected) => Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  connected ? '🌐 متصل' : '🔌 بدون انترنت',
                  style: TextStyle(
                    color: connected ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ),
            loading: () => const SizedBox(),
            error: (err, stack) => const SizedBox(),
          ),
        ],
      ),
      body: products.when(
        data: (productList) => ListView.builder(
          itemCount: productList.length,
          itemBuilder: (context, index) {
            final product = productList[index];
            return ListTile(
              title: Text(product['name']),
              subtitle: Text('${product['price']} ريال'),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('خطأ: $err')),
      ),
    );
  }
}
```

---

## 💾 الخطوة 6: Backend Sync API (.NET)

```csharp
// backend/Controllers/SyncController.cs

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class SyncController : ControllerBase
{
    private readonly IDbContextFactory<KineticContext> _contextFactory;
    private readonly ILogger<SyncController> _logger;
    
    [HttpPost("products")]
    public async Task<IActionResult> SyncProducts(
        [FromBody] List<ProductSyncDto> products)
    {
        try
        {
            using var context = _contextFactory.CreateDbContext();
            
            foreach (var product in products)
            {
                var existing = await context.Products
                    .FirstOrDefaultAsync(p => p.Id == product.Id);
                
                if (existing == null)
                {
                    context.Products.Add(new Product
                    {
                        Id = product.Id,
                        Name = product.Name,
                        Price = product.Price,
                        // ... باقي الحقول
                    });
                }
                else
                {
                    existing.Name = product.Name;
                    existing.Price = product.Price;
                    // ... تحديث الحقول
                    context.Products.Update(existing);
                }
            }
            
            await context.SaveChangesAsync();
            
            // إنشاء Backup
            await _backupService.CreateBackup("products");
            
            return Ok(new { message = "Sync successful" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Sync error");
            return BadRequest(new { error = ex.Message });
        }
    }
    
    [HttpPost("invoices")]
    public async Task<IActionResult> SyncInvoices(
        [FromBody] List<InvoiceSyncDto> invoices)
    {
        // نفس النمط أعلاه
        // ...
        return Ok();
    }
}
```

---

## ✅ قائمة التحقق النهائية

```
الخطوة 1: LocalDatabase
  [ ] إنشاء الملفات
  [ ] تطبيق جميع الدوال
  [ ] اختبار إدراج/تحديث/حذف
  [ ] اختبار Sync Queue

الخطوة 2: ConnectivityService
  [ ] مراقبة الاتصال
  [ ] إرسال البيانات عند الاتصال
  [ ] اختبار في بيئة بدون انترنت

الخطوة 3: SyncEngine
  [ ] إرسال البيانات المعلقة
  [ ] جلب البيانات الجديدة
  [ ] معالجة الأخطاء والـ Retry

الخطوة 4: Providers
  [ ] دمج جميع المكونات
  [ ] Auto-sync عند الاتصال

الخطوة 5: الشاشات
  [ ] استخدام البيانات المحلية
  [ ] عرض حالة الاتصال
  [ ] اختبار offline/online

الخطوة 6: Backend
  [ ] API للمزامنة
  [ ] Backup تلقائي
  [ ] استعادة البيانات
```

---

**هل تريد تطبيق أي من هذه الخطوات الآن؟** 🚀
