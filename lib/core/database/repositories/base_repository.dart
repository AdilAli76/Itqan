import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../sqlite_database.dart';

/// Base Repository لجميع الكيانات
abstract class BaseRepository<T> {
  String get tableName;

  /// تحويل صف من قاعدة البيانات إلى كائن
  T fromJson(Map<String, dynamic> json);

  /// تحويل كائن إلى خريطة للإدراج
  Map<String, dynamic> toJson(T entity);

  /// الحصول على جميع السجلات
  Future<List<T>> getAll({
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final results = await SqliteDatabase.query(
      tableName,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return results.map((json) => fromJson(json)).toList();
  }

  /// البحث عن سجل بواسطة ID
  Future<T?> getById(String id) async {
    final result = await SqliteDatabase.queryOne(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
    return result != null ? fromJson(result) : null;
  }

  /// البحث عن سجلات
  Future<List<T>> search({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final results = await SqliteDatabase.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return results.map((json) => fromJson(json)).toList();
  }

  /// إدراج سجل جديد
  Future<String> create(T entity) async {
    final json = toJson(entity);
    json['id'] = json['id'] ?? const Uuid().v4();
    json['created_at'] = json['created_at'] ?? DateTime.now().toIso8601String();
    json['updated_at'] = json['updated_at'] ?? DateTime.now().toIso8601String();

    await SqliteDatabase.insert(tableName, json);
    return json['id'];
  }

  /// تحديث سجل
  Future<int> update(String id, T entity) async {
    final json = toJson(entity);
    json['updated_at'] = DateTime.now().toIso8601String();

    return SqliteDatabase.update(
      tableName,
      json,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف سجل
  Future<int> delete(String id) async {
    return SqliteDatabase.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف جميع السجلات
  Future<int> deleteAll() async {
    return SqliteDatabase.delete(tableName);
  }

  /// عدد السجلات
  Future<int> count({String? where, List<Object?>? whereArgs}) async {
    final result = await SqliteDatabase.query(
      tableName,
      columns: ['COUNT(*) as count'],
      where: where,
      whereArgs: whereArgs,
    );
    return result.isNotEmpty ? (result.first['count'] as int?) ?? 0 : 0;
  }

  /// العمليات بالمعاملة
  Future<R> withTransaction<R>(
    Future<R> Function(DatabaseTransaction txn) action,
  ) async {
    final db = await SqliteDatabase.database;
    return db.transaction((txn) => action(DatabaseTransaction(txn)));
  }
}

/// معاملة (Transaction) وسيط للعمليات المعقدة
class DatabaseTransaction {
  final Transaction _transaction;

  DatabaseTransaction(this._transaction);

  Future<List<Map<String, dynamic>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return _transaction.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
    );
  }

  Future<int> insert(String table, Map<String, dynamic> values) async {
    return _transaction.insert(table, values);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return _transaction.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return _transaction.delete(table, where: where, whereArgs: whereArgs);
  }
}
