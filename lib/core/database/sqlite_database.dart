// ignore_for_file: avoid_print
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_schema.dart';

/// مدير قاعدة البيانات SQLite
class SqliteDatabase {
  static Database? _database;
  static const String _dbName = 'kinetic_erp.db';
  static const int _dbVersion = 1;

  /// الحصول على قاعدة البيانات (Singleton)
  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// إنشاء وتهيئة قاعدة البيانات
  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// إنشاء الجداول عند إنشاء قاعدة البيانات لأول مرة
  static Future<void> _onCreate(Database db, int version) async {
    try {
      // إنشاء جميع الجداول
      for (final createTableSql in allTables) {
        await db.execute(createTableSql);
      }

      // إنشاء الفهارس
      for (final createIndexSql in createIndexes) {
        await db.execute(createIndexSql);
      }

      // إدراج بيانات ابتدائية
      await _insertInitialData(db);

      print('✅ قاعدة البيانات تم إنشاؤها بنجاح');
    } catch (e) {
      print('❌ خطأ في إنشاء قاعدة البيانات: $e');
      rethrow;
    }
  }

  /// ترقية قاعدة البيانات
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    print('🔄 ترقية قاعدة البيانات من $oldVersion إلى $newVersion');
    // سيتم إضافة منطق الترقية هنا عند الحاجة
  }

  /// إدراج بيانات ابتدائية
  static Future<void> _insertInitialData(Database db) async {
    try {
      // إدراج فرع افتراضي
      await db.insert('branches', {
        'id': 'BRANCH_DEFAULT',
        'code': '001',
        'name': 'الفرع الرئيسي',
        'city': 'الرياض',
        'country': 'السعودية',
        'currency': 'SAR',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // إدراج مستخدم افتراضي (ADMIN)
      await db.insert('users', {
        'id': 'USER_ADMIN',
        'username': 'admin',
        'email': 'admin@kinetic.local',
        'full_name': 'مدير النظام',
        'role': 'ADMIN',
        'branch_id': 'BRANCH_DEFAULT',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('✅ تم إدراج البيانات الابتدائية');
    } catch (e) {
      print('⚠️ خطأ في إدراج البيانات الابتدائية: $e');
    }
  }

  /// تنفيذ استعلام (query) واحد
  static Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return db.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// البحث عن سجل واحد
  static Future<Map<String, dynamic>?> queryOne(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final results = await query(table, where: where, whereArgs: whereArgs);
    return results.isNotEmpty ? results.first : null;
  }

  /// الإدراج
  static Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return db.insert(table, values);
  }

  /// التحديث
  static Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  /// الحذف
  static Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  /// معاملة (Transaction)
  static Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action,
  ) async {
    final db = await database;
    return db.transaction(action);
  }

  /// حذف قاعدة البيانات (للاختبار)
  static Future<void> deleteDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    await sqflite.deleteDatabase(path);
    _database = null;
    print('✅ تم حذف قاعدة البيانات');
  }

  /// إغلاق الاتصال
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// إحصائيات قاعدة البيانات
  static Future<DatabaseStats> getStats() async {
    final db = await database;
    final tables = [
      'products',
      'customers',
      'invoices',
      'purchase_orders',
      'expenses',
      'stock_transfers',
    ];

    final counts = <String, int>{};
    for (final table in tables) {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $table');
      counts[table] = Sqflite.firstIntValue(result) ?? 0;
    }

    return DatabaseStats(counts);
  }
}

/// إحصائيات قاعدة البيانات
class DatabaseStats {
  final Map<String, int> tableCounts;

  DatabaseStats(this.tableCounts);

  int get totalRecords => tableCounts.values.fold(0, (a, b) => a + b);

  @override
  String toString() {
    return 'Products: ${tableCounts['products']}, '
        'Customers: ${tableCounts['customers']}, '
        'Invoices: ${tableCounts['invoices']}, '
        'Total: $totalRecords';
  }
}
