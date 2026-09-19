import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/local_database/local_db.dart';

final localDatabaseProvider = FutureProvider<LocalDatabase>((ref) async {
  final db = LocalDatabase();
  await db.initialize();
  return db;
});

final localDatabaseSyncProvider = Provider<LocalDatabase>((ref) {
  return LocalDatabase();
});
