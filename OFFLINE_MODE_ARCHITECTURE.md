# 🔌 بنية نمط Offline-First + Cloud Sync

## 📋 الرؤية العامة

```
┌─────────────────────────────────────────────────────────────┐
│ منظومة إتقان ERP — Offline-First Architecture              │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Desktop App (Flutter)                                       │
│  ├─ Local Database (SQLite)                                 │
│  ├─ Sync Queue                                              │
│  └─ Connectivity Monitor                                    │
│       │                                                      │
│       ├─ Offline Mode        ─→ استخدام البيانات المحلية    │
│       │   (بدون انترنت)                                    │
│       │                                                      │
│       └─ Online Mode         ─→ مزامنة مع الـ Backend       │
│           (مع انترنت)                                      │
│                 │                                            │
│                 ▼                                            │
│          Backend API (.NET)                                 │
│          ├─ SQL Server (مركزي)                             │
│          └─ Backup Storage                                 │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 الحالات المستخدمة

### 1️⃣ العامل في المتجر (بدون انترنت)
```
الموقف: متجر في منطقة بدون تغطية انترنت جيدة
الحل:
✅ جميع البيانات محفوظة محليا (SQLite)
✅ البيع والشراء يعملان بدون انترنت
✅ عند الاتصال، تُرسل البيانات تلقائياً للخادم
✅ يتم تحديث البيانات من الخادم
```

### 2️⃣ الإدارة (نسخة مركزية)
```
الموقف: مركز إدارة يريد نسخة احتياطية محلية
الحل:
✅ SQL Server Express محلي (offline)
✅ Backend منفصل يدير النسخة
✅ عند الاتصال، يتم مزامنة البيانات
✅ Backup تلقائي على السيرفر المركزي
```

### 3️⃣ المقر الرئيسي (متصل دائماً)
```
الموقف: مقر رئيسي مع انترنت مستقر
الحل:
✅ نسخة سحابية من البيانات
✅ تحديثات فوري لجميع الفروع
✅ Backup مركزي
```

---

## 🗄️ الهندسة التقنية

### المستوى الأول: قاعدة البيانات المحلية (SQLite)

```dart
// lib/core/local_database/local_db.dart

class LocalDatabase {
  late Database _db;
  
  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'itqan_offline.db'),
      version: 1,
      onCreate: _createTables,
    );
  }
  
  Future<void> _createTables(Database db, int version) async {
    // Products
    await db.execute('''
      CREATE TABLE products(
        id TEXT PRIMARY KEY,
        name TEXT,
        price REAL,
        quantity INTEGER,
        sync_status TEXT DEFAULT 'pending',
        last_synced INTEGER,
        created_at INTEGER,
        UNIQUE(id)
      )
    ''');
    
    // Invoices
    await db.execute('''
      CREATE TABLE invoices(
        id TEXT PRIMARY KEY,
        total REAL,
        status TEXT,
        sync_status TEXT DEFAULT 'pending',
        last_synced INTEGER,
        created_at INTEGER,
        UNIQUE(id)
      )
    ''');
    
    // Invoice Items
    await db.execute('''
      CREATE TABLE invoice_items(
        id TEXT PRIMARY KEY,
        invoice_id TEXT,
        product_id TEXT,
        quantity INTEGER,
        unit_price REAL,
        sync_status TEXT DEFAULT 'pending',
        FOREIGN KEY(invoice_id) REFERENCES invoices(id),
        UNIQUE(id)
      )
    ''');
    
    // Sync Queue (لتتبع البيانات المعلقة)
    await db.execute('''
      CREATE TABLE sync_queue(
        id TEXT PRIMARY KEY,
        table_name TEXT,
        operation TEXT,
        data TEXT,
        created_at INTEGER,
        retry_count INTEGER DEFAULT 0
      )
    ''');
  }
  
  // العمليات الأساسية
  Future<void> insertProduct(Product product) async {
    await _db.insert('products', {
      'id': product.id,
      'name': product.name,
      'price': product.price,
      'sync_status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    
    // أضف إلى Sync Queue
    await _addToSyncQueue('products', 'INSERT', product.toJson());
  }
  
  Future<List<Product>> getProducts() async {
    final maps = await _db.query('products');
    return maps.map((m) => Product.fromJson(m)).toList();
  }
  
  Future<void> _addToSyncQueue(
    String tableName,
    String operation,
    Map<String, dynamic> data,
  ) async {
    await _db.insert('sync_queue', {
      'id': const Uuid().v4(),
      'table_name': tableName,
      'operation': operation,
      'data': jsonEncode(data),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
```

### المستوى الثاني: مراقبة الاتصال (Connectivity)

```dart
// lib/core/connectivity/connectivity_service.dart

class ConnectivityService {
  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  
  Stream<bool> get connectionStream => _controller.stream;
  
  Future<void> initialize() async {
    _connectivity.onConnectivityChanged.listen((result) {
      final isConnected = !result.contains(ConnectivityResult.none);
      _controller.add(isConnected);
      
      if (isConnected) {
        // عند الاتصال، ابدأ المزامنة
        _startSync();
      }
    });
  }
  
  Future<bool> isConnected() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }
  
  void _startSync() {
    // سنشرحه في الخطوة التالية
  }
  
  void dispose() {
    _controller.close();
  }
}
```

### المستوى الثالث: محرك المزامنة (Sync Engine)

```dart
// lib/core/sync/sync_engine.dart

class SyncEngine {
  final LocalDatabase _localDb;
  final ApiClient _apiClient;
  
  Future<void> synchronize() async {
    try {
      // 1. جلب البيانات المعلقة من الـ Sync Queue
      final queue = await _localDb.getSyncQueue();
      
      for (final item in queue) {
        try {
          // 2. محاولة إرسال البيانات للـ Backend
          await _syncItem(item);
          
          // 3. حذف من الـ Sync Queue عند النجاح
          await _localDb.removeSyncQueueItem(item.id);
          
          // 4. تحديث الحالة في قاعدة البيانات المحلية
          await _localDb.updateSyncStatus(
            item.tableName,
            item.id,
            'synced',
          );
        } catch (e) {
          // إذا فشل، زيادة محاولات إعادة المحاولة
          await _localDb.incrementRetryCount(item.id);
          print('Sync failed: $e');
        }
      }
      
      // 5. جلب البيانات الجديدة من السيرفر
      await _pullRemoteData();
      
    } catch (e) {
      print('Sync error: $e');
    }
  }
  
  Future<void> _syncItem(SyncQueueItem item) async {
    final data = jsonDecode(item.data);
    
    switch (item.operation) {
      case 'INSERT':
        await _apiClient.post(
          '/api/${item.tableName}',
          data: data,
        );
        break;
      case 'UPDATE':
        await _apiClient.put(
          '/api/${item.tableName}/${data['id']}',
          data: data,
        );
        break;
      case 'DELETE':
        await _apiClient.delete(
          '/api/${item.tableName}/${data['id']}',
        );
        break;
    }
  }
  
  Future<void> _pullRemoteData() async {
    // جلب آخر التحديثات من السيرفر
    try {
      final remoteProducts = await _apiClient.get('/api/products');
      
      // تحديث البيانات المحلية
      for (final product in remoteProducts) {
        await _localDb.upsertProduct(Product.fromJson(product));
      }
      
      // يمكن فعل الشيء نفسه للفواتير والعناصر الأخرى
    } catch (e) {
      print('Pull failed: $e');
    }
  }
}
```

### المستوى الرابع: الـ Provider (Riverpod)

```dart
// lib/core/providers/offline_providers.dart

final localDatabaseProvider = Provider((ref) {
  return LocalDatabase();
});

final connectivityServiceProvider = Provider((ref) {
  return ConnectivityService();
});

final syncEngineProvider = Provider((ref) {
  final localDb = ref.watch(localDatabaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  return SyncEngine(localDb, apiClient);
});

final syncStatusProvider = StreamProvider((ref) async* {
  final syncEngine = ref.watch(syncEngineProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  
  // مراقبة الاتصال وتشغيل المزامنة تلقائياً
  await for (final isConnected in connectivity.connectionStream) {
    if (isConnected) {
      await syncEngine.synchronize();
      yield SyncStatus.synced;
    } else {
      yield SyncStatus.offline;
    }
  }
});

final productsProvider = FutureProvider((ref) async {
  // محاولة الحصول على البيانات من الإنترنت أولاً
  try {
    final syncStatus = ref.watch(syncStatusProvider);
    if (syncStatus.value == SyncStatus.synced) {
      // متصل بالانترنت، احصل على البيانات من السيرفر
      return await ref.watch(apiClientProvider).get('/api/products');
    }
  } catch (e) {
    // إذا فشل أو بدون انترنت، استخدم البيانات المحلية
  }
  
  // استرجع من قاعدة البيانات المحلية
  return await ref.watch(localDatabaseProvider).getProducts();
});
```

---

## 🔄 مسار البيانات الكامل

```
┌─────────────────────────────────────────────────────────────┐
│ 1. المستخدم ينسخ منتجاً (بدون انترنت)                      │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
    ┌──────────────────────────────────┐
    │ LocalDatabase: حفظ المنتج          │
    │ SyncQueue: تسجيل العملية          │
    └────────────┬─────────────────────┘
                 │
                 ▼
    ┌──────────────────────────────────┐
    │ تحديث الواجهة من البيانات المحلية  │
    └────────────┬─────────────────────┘
                 │
                 ▼
    ┌──────────────────────────────────┐
    │ ConnectivityService: مراقبة ...   │
    │ ...الاتصال                       │
    └────────────┬─────────────────────┘
                 │
                 ├─ لا يوجد انترنت
                 │   └─ انتظر الاتصال
                 │
                 └─ متصل بالانترنت
                    │
                    ▼
        ┌──────────────────────────────────┐
        │ SyncEngine: المزامنة التلقائية  │
        │ 1. إرسال البيانات المعلقة        │
        │ 2. جلب التحديثات من السيرفر     │
        │ 3. تحديث الحالة محلياً           │
        └────────────┬─────────────────────┘
                     │
                     ▼
            ┌──────────────────────────────────┐
            │ Backend API (.NET)               │
            │ ├─ حفظ في SQL Server             │
            │ └─ Backup على الخادم المركزي   │
            └──────────────────────────────────┘
```

---

## 📦 حالات الاستخدام العملية

### حالة 1: بيع منتج بدون انترنت

```dart
// في screens/pos_screen.dart
Future<void> sellProduct(Product product) async {
  final syncEngine = ref.watch(syncEngineProvider);
  
  // 1. حفظ في قاعدة البيانات المحلية
  final invoice = Invoice(
    id: const Uuid().v4(),
    items: [InvoiceItem(product: product)],
    createdAt: DateTime.now(),
  );
  
  await localDb.insertInvoice(invoice);
  
  // 2. تسجيل في Sync Queue
  await localDb.addToSyncQueue('invoices', 'INSERT', invoice.toJson());
  
  // 3. عرض رسالة للمستخدم
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('تم الحفظ محلياً. سيتم المزامنة عند الاتصال.'),
    ),
  );
  
  // 4. إذا تم الاتصال لاحقاً، تُرسل تلقائياً
}
```

### حالة 2: مزامنة عند الاتصال

```dart
// المزامنة تحدث تلقائياً!
// لا حاجة للمستخدم أن يفعل شيء

// في الخلفية:
// ConnectivityService يكتشف الاتصال
// SyncEngine يبدأ المزامنة تلقائياً
// البيانات المعلقة ترسل للسيرفر
// التحديثات تأتي من السيرفر وتُحفظ محلياً
```

### حالة 3: Backup على السيرفر

```dart
// في Backend (.NET Controller)
[HttpPost("api/invoices/sync")]
public async Task<IActionResult> SyncInvoices(
    [FromBody] List<InvoiceSyncDto> invoices)
{
    // 1. حفظ الفواتير في SQL Server المركزي
    foreach (var invoice in invoices)
    {
        var dbInvoice = new Invoice
        {
            Id = invoice.Id,
            // ... باقي البيانات
        };
        
        _context.Invoices.Add(dbInvoice);
    }
    
    await _context.SaveChangesAsync();
    
    // 2. حفظ Backup تلقائي
    await _backupService.CreateBackup("invoices");
    
    // 3. إرسال آخر التحديثات للعميل
    var latestData = await _context.Invoices
        .Where(i => i.ModifiedDate > invoices.Max(x => x.LastSynced))
        .ToListAsync();
    
    return Ok(new { success = true, updates = latestData });
}
```

---

## 🛠️ خطوات التطبيق

### المرحلة 1: البنية الأساسية (1-2 أسبوع)

```
✓ إنشاء LocalDatabase مع SQLite
✓ نقل البيانات من API إلى LocalDB
✓ عرض البيانات من LocalDB
✓ مراقبة الاتصال (ConnectivityService)
```

### المرحلة 2: المزامنة (1-2 أسبوع)

```
✓ Sync Queue لتتبع التغييرات
✓ SyncEngine للمزامنة اليدوية
✓ Conflict Resolution (إذا حدثت تضاربات)
✓ اختبار المزامنة
```

### المرحلة 3: التلقائي (1 أسبوع)

```
✓ مزامنة تلقائية عند الاتصال
✓ Retry Logic مع exponential backoff
✓ مراقبة حالة المزامنة
✓ إشعارات للمستخدم
```

### المرحلة 4: الإنتاج (1 أسبوع)

```
✓ Backup تلقائي على السيرفر
✓ استعادة البيانات (Recovery)
✓ اختبار شامل
✓ توثيق
```

---

## 💻 ملفات المشروع المطلوبة

```
lib/
├── core/
│   ├── local_database/
│   │   ├── local_db.dart          (← جديد)
│   │   └── models/
│   │       ├── sync_queue.dart    (← جديد)
│   │       └── sync_status.dart   (← جديد)
│   │
│   ├── connectivity/
│   │   └── connectivity_service.dart (← جديد)
│   │
│   └── sync/
│       ├── sync_engine.dart       (← جديد)
│       ├── conflict_resolver.dart (← جديد)
│       └── backup_service.dart    (← جديد)
│
└── providers/
    └── offline_providers.dart     (← جديد)
```

---

## 🔐 الأمان والنقاط المهمة

### 1. تشفير البيانات المحلية
```dart
// لا تحفظ كلمات المرور بدون تشفير!
final secureStorage = FlutterSecureStorage();
await secureStorage.write(key: 'password', value: encrypted);
```

### 2. التحقق من الصحة (Conflict Resolution)
```dart
// إذا عدّل المستخدم البيانات محليا
// وعدّلت أيضا على السيرفر
// استخدم timestamp للقرار:
if (local.lastModified > remote.lastModified) {
  // احفظ النسخة المحلية
} else {
  // احفظ النسخة الريموت
}
```

### 3. حجم قاعدة البيانات
```dart
// SQLite صغير جداً (~5-10 MB لآلاف السجلات)
// لكن راقب الحجم:
await localDb.clearOldData(daysOld: 90);
```

---

## 📊 المخطط النهائي

```
المستخدم (بدون انترنت)
    ↓
App يعمل بـ Local Database (SQLite)
    ↓
أثناء العمل، البيانات تُحفظ محليا
    ↓
Sync Queue يتتبع التغييرات
    ↓
عند الاتصال بالانترنت:
    ├─ إرسال البيانات المعلقة للـ Backend
    ├─ Backend يحفظ في SQL Server
    ├─ Backend ينشئ Backup تلقائي
    └─ تحديثات جديدة ترجع للتطبيق
    ↓
قاعدة البيانات المحلية تتحدث
    ↓
الواجهة تعرض أحدث البيانات
```

---

## ✅ الفوائد

```
✅ يعمل 100% بدون انترنت
✅ لا توجد مشاكل تأخير الشبكة
✅ Backup تلقائي على السيرفر
✅ متزامن عند الاتصال
✅ لا فقدان للبيانات
✅ قابل للتوسع بسهولة
```

---

## 🚀 البدء الآن

### الخطوة 1: أضف التبعيات (مُضافة بالفعل ✓)
```yaml
sqflite: ^2.3.0
connectivity_plus: ^5.0.0
workmanager: ^0.10.10
uuid: ^4.0.0
```

### الخطوة 2: أنشئ ملفات BaseCore
```dart
// lib/core/local_database/local_db.dart
// lib/core/connectivity/connectivity_service.dart
// lib/core/sync/sync_engine.dart
```

### الخطوة 3: دمج مع الـ Providers
```dart
// lib/providers/offline_providers.dart
```

### الخطوة 4: استخدم في الشاشات
```dart
// استبدل ApiClient بـ local database + sync
```

---

**هل تريد البدء بتطبيق أحد هذه المكونات الآن؟** 🚀
