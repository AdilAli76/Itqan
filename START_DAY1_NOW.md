# 🚀 ابدأ اليوم الأول الآن!

## ⏰ اليوم: الاثنين

## 🎯 الهدف اليومي
```
بحلول نهاية اليوم:
✅ LocalDatabase مُنشأة
✅ الجداول موجودة
✅ insertProduct يعمل
✅ getProducts يعمل
```

---

## 📝 الخطوات الفعلية

### الخطوة 1: فتح المشروع (5 دقائق)

```bash
# افتح Terminal
cd C:\Users\F\Downloads\itqan_erp

# افتح IDE
code .
```

أو استخدم Visual Studio Code:
```
File → Open Folder → اختر C:\Users\F\Downloads\itqan_erp
```

### الخطوة 2: إنشاء مجلدات البرنامج (5 دقائق)

في VS Code:
```
1. اضغط Ctrl+Shift+P
2. اكتب: "Terminal: Create New Terminal"
3. انسخ الأوامر التالية:
```

```bash
mkdir -p lib/core/local_database/models
mkdir -p lib/core/local_database/services
```

### الخطوة 3: إنشاء الملف الأول (10 دقائق)

في VS Code:
```
1. كليك يمين على lib/core/local_database
2. New File
3. اسم الملف: local_db.dart
```

### الخطوة 4: انسخ الكود (20 دقيقة)

افتح الملف `local_db.dart` الذي أنشأته:

```dart
// ⬇️ انسخ الكود التالي بالكامل:

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';

class LocalDatabase {
  static const String dbName = 'itqan_offline.db';
  static const int version = 1;
  static final LocalDatabase _instance = LocalDatabase._internal();

  late Database _db;
  bool get isInitialized => _db != null;

  LocalDatabase._internal();

  factory LocalDatabase() {
    return _instance;
  }

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

  Future<void> close() async {
    await _db.close();
  }
}
```

### الخطوة 5: اختبار الكود (15 دقيقة)

في Terminal:
```bash
flutter run
```

في console يجب أن ترى:
```
✅ LocalDatabase initialized at: ...
📊 Database Structure:
   Table: products
   Table: invoices
   Table: invoice_items
   Table: customers
   Table: sync_queue
```

---

## ✅ قائمة التحقق

في نهاية اليوم:

```
[ ] فتح المشروع بنجاح
[ ] إنشاء المجلدات
[ ] إنشاء ملف local_db.dart
[ ] نسخ الكود
[ ] لا توجد أخطاء compilation
[ ] التطبيق يشتغل بدون مشاكل
[ ] رسائل النجاح تظهر في console
```

---

## 📞 إذا واجهت مشكلة

### مشكلة: أخطاء في الاستيراد

```dart
// ❌ خطأ:
import 'package:sqflite/sqflite.dart';

// ✅ الحل:
// تأكد من أن sqflite في pubspec.yaml
flutter pub get
```

### مشكلة: Null safety errors

```dart
// اتأكد من استخدام nullable بشكل صحيح
late Database _db;  // ✅ صحيح
Database? _db;      // أيضاً صحيح
```

### مشكلة: قاعدة البيانات لا تُنشأ

```bash
# احذف النسخة السابقة
flutter clean
flutter pub get

# وأعد التشغيل
flutter run
```

---

## 🎯 الهدف النهائي لليوم

```
في نهاية اليوم يجب أن:

✅ تكون قاعدة البيانات موجودة في الجهاز
✅ تكون جميع الجداول مُنشأة
✅ insertProduct يعمل
✅ getProducts يعمل
✅ لا توجد أخطاء

تصريح النجاح: ✅ اليوم الأول مكتمل!
```

---

**ابدأ الآن! اللحظة الأنسب للبدء هي الآن! 🚀**

```
الخطوة الأولى:
👉 افتح Terminal
👉 cd C:\Users\F\Downloads\itqan_erp
👉 code .
```

**توفيق! 💪**
