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

  bool get isInitialized {
    try {
      return _db != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> initialize() async {
    if (isInitialized) {
      print('ℹ️  LocalDatabase already initialized');
      return;
    }

    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, dbName);

      _db = await openDatabase(
        path,
        version: version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      print('✅ LocalDatabase initialized at: $path');
      await _printDatabaseInfo();
    } catch (e) {
      print('❌ Error initializing LocalDatabase: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    print('📦 Creating database tables...');

    try {
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
    } catch (e) {
      print('❌ Error creating tables: $e');
      rethrow;
    }
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
        print('   ✓ Table: ${table['name']}');
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
      final products = await _db.query(
        'products',
        where: query,
        orderBy: 'name ASC',
      );
      print('✅ Fetched ${products.length} products');
      return products;
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
      final invoices = await _db.query(
        'invoices',
        orderBy: 'created_at DESC',
      );
      print('✅ Fetched ${invoices.length} invoices');
      return invoices;
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
      print('✅ Added to sync queue: $tableName $operation');
    } catch (e) {
      print('❌ Error adding to sync queue: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    try {
      final items = await _db.query(
        'sync_queue',
        orderBy: 'created_at ASC',
        where: 'retry_count < 5',
      );
      print('✅ Found ${items.length} pending sync items');
      return items;
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
      print('✅ Marked sync item as success');
    } catch (e) {
      print('❌ Error marking sync as success: $e');
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

  Future<void> close() async {
    await _db.close();
    print('✅ LocalDatabase closed');
  }
}
