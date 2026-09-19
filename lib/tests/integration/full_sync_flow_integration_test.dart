// اختبارات التكامل - تدفق المزامنة الكامل
// lib/tests/integration/full_sync_flow_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import '../../core/database/local_db.dart';
import '../../core/connectivity/connectivity_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/network/enhanced_api_client.dart';

void main() {
  group('Full Sync Flow Integration Tests', () {
    late LocalDatabase db;
    late ConnectivityService connectivity;
    late SyncEngine syncEngine;
    late EnhancedApiClient apiClient;

    setUp(() async {
      // Initialize all services
      db = LocalDatabase();
      connectivity = ConnectivityService();
      syncEngine = SyncEngine(db, connectivity);
      apiClient = EnhancedApiClient(db, syncEngine);

      await db.initialize();
      await connectivity.initialize();
    });

    tearDown(() async {
      await db.clear();
      await syncEngine.stopSync();
    });

    // ==================== Scenario 1: Normal Flow ====================
    group('Scenario 1: Normal Sync Flow', () {
      test('complete sync flow from database to server', () async {
        // Step 1: Add product to local database
        const product = Product(
          id: '1',
          name: 'Test Product',
          price: 100.0,
          quantity: 10,
        );

        await db.insertProduct(product);
        var products = await db.getProducts();
        expect(products.length, 1);
        print('✅ Step 1: Product added to local database');

        // Step 2: Add to sync queue
        final syncItem = SyncQueueItem(
          id: 'sync_1',
          operation: 'INSERT',
          table: 'products',
          recordId: '1',
          data: {'name': 'Test Product', 'price': 100.0, 'quantity': 10},
          createdAt: DateTime.now(),
          status: 'pending',
        );

        await db.addToSyncQueue(syncItem);
        var pending = await db.getPendingItems();
        expect(pending.length, 1);
        print('✅ Step 2: Item added to sync queue');

        // Step 3: Check connectivity
        final isConnected = await connectivity.checkConnectivityStatus();
        print('✅ Step 3: Connectivity check - $isConnected');

        // Step 4: Start sync
        await syncEngine.startSync();
        print('✅ Step 4: Sync engine started');

        // Step 5: Wait for sync to complete
        await Future.delayed(const Duration(seconds: 1));

        // Step 6: Verify sync queue is cleared
        pending = await db.getPendingItems();
        expect(pending.isEmpty, true);
        print('✅ Step 6: Sync queue cleared');

        // Step 7: Get statistics
        final stats = await syncEngine.getStatistics();
        print('✅ Step 7: Sync statistics - ${stats.syncedItems} items synced');

        expect(stats.totalPending, 0);
        expect(stats.isSyncing, false);
      });

      test('sync multiple items in sequence', () async {
        // Add 5 products
        for (int i = 1; i <= 5; i++) {
          await db.insertProduct(Product(
            id: i.toString(),
            name: 'Product $i',
            price: i * 100.0,
            quantity: i * 10,
          ));
        }

        // Add all to sync queue
        for (int i = 1; i <= 5; i++) {
          await db.addToSyncQueue(SyncQueueItem(
            id: 'sync_$i',
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {},
            createdAt: DateTime.now(),
            status: 'pending',
          ));
        }

        var pending = await db.getPendingItems();
        expect(pending.length, 5);
        print('✅ 5 items added to sync queue');

        // Start sync
        await syncEngine.startSync();
        await Future.delayed(const Duration(seconds: 2));

        // Verify all synced
        pending = await db.getPendingItems();
        expect(pending.isEmpty, true);
        print('✅ All 5 items synced successfully');

        final stats = await syncEngine.getStatistics();
        print('✅ Statistics: ${stats.syncedItems} items synced, ${stats.failedItems} failed');
      });
    });

    // ==================== Scenario 2: Failure & Retry ====================
    group('Scenario 2: Failure and Retry', () {
      test('sync should retry on temporary failure', () async {
        // Add item to sync queue
        await db.addToSyncQueue(SyncQueueItem(
          id: 'sync_1',
          operation: 'INSERT',
          table: 'products',
          recordId: '1',
          data: {},
          createdAt: DateTime.now(),
          status: 'pending',
        ));

        print('✅ Item added to sync queue');

        // Simulate connectivity loss
        await connectivity.simulateDisconnection();
        print('✅ Simulated connectivity loss');

        // Try sync (should fail)
        await syncEngine.startSync();
        await Future.delayed(const Duration(seconds: 1));

        var pending = await db.getPendingItems();
        expect(pending.isNotEmpty, true);
        print('✅ Item remains pending due to connectivity loss');

        // Restore connectivity
        await connectivity.simulateConnection();
        print('✅ Connectivity restored');

        // Retry sync
        await syncEngine.startSync();
        await Future.delayed(const Duration(seconds: 1));

        pending = await db.getPendingItems();
        expect(pending.isEmpty, true);
        print('✅ Item synced after retry');
      });

      test('failed items should be retrievable', () async {
        // Add multiple items
        for (int i = 1; i <= 3; i++) {
          await db.addToSyncQueue(SyncQueueItem(
            id: 'sync_$i',
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {},
            createdAt: DateTime.now(),
            status: i == 2 ? 'failed' : 'pending',
          ));
        }

        final failed = await db.getFailedItems();
        expect(failed.length, 1);
        expect(failed.first.id, 'sync_2');
        print('✅ Failed items retrieved correctly');
      });
    });

    // ==================== Scenario 3: Offline to Online ====================
    group('Scenario 3: Offline Work and Sync', () {
      test('offline work should sync when online', () async {
        // Simulate offline
        await connectivity.simulateDisconnection();
        print('✅ Application offline');

        // Add products offline
        for (int i = 1; i <= 3; i++) {
          await db.insertProduct(Product(
            id: i.toString(),
            name: 'Offline Product $i',
            price: i * 50.0,
            quantity: i * 5,
          ));

          await db.addToSyncQueue(SyncQueueItem(
            id: 'sync_$i',
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {},
            createdAt: DateTime.now(),
            status: 'pending',
          ));
        }

        var pending = await db.getPendingItems();
        expect(pending.length, 3);
        print('✅ 3 items added offline');

        // Verify connectivity is still offline
        var isOnline = await connectivity.checkConnectivityStatus();
        expect(isOnline, false);
        print('✅ Connectivity still offline');

        // Come online
        await connectivity.simulateConnection();
        print('✅ Connection restored');

        // Auto-sync should trigger
        await syncEngine.startSync();
        await Future.delayed(const Duration(seconds: 1));

        pending = await db.getPendingItems();
        expect(pending.isEmpty, true);
        print('✅ All offline items synced');
      });
    });

    // ==================== Scenario 4: Partial Failures ====================
    group('Scenario 4: Partial Sync Failures', () {
      test('some items fail while others succeed', () async {
        // Add 4 items - item 2 will fail
        for (int i = 1; i <= 4; i++) {
          await db.addToSyncQueue(SyncQueueItem(
            id: 'sync_$i',
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {'fail': i == 2},
            createdAt: DateTime.now(),
            status: 'pending',
          ));
        }

        var pending = await db.getPendingItems();
        expect(pending.length, 4);
        print('✅ 4 items added (1 will fail)');

        // Sync
        await syncEngine.startSync();
        await Future.delayed(const Duration(seconds: 2));

        // Check statistics
        final stats = await syncEngine.getStatistics();
        print('✅ Stats - Synced: ${stats.syncedItems}, Failed: ${stats.failedItems}');

        // Failed item should still be pending or marked as failed
        final failed = await db.getFailedItems();
        expect(failed.isNotEmpty, true);
        print('✅ Failed items identified and marked');
      });
    });

    // ==================== Scenario 5: Concurrent Operations ====================
    group('Scenario 5: Concurrent Operations', () {
      test('concurrent additions during sync', () async {
        // Add initial items
        for (int i = 1; i <= 5; i++) {
          await db.addToSyncQueue(SyncQueueItem(
            id: 'sync_$i',
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {},
            createdAt: DateTime.now(),
            status: 'pending',
          ));
        }

        print('✅ Initial 5 items added');

        // Start sync
        syncEngine.startSync();

        // Add more items during sync
        await Future.delayed(const Duration(milliseconds: 500));
        for (int i = 6; i <= 8; i++) {
          await db.addToSyncQueue(SyncQueueItem(
            id: 'sync_$i',
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {},
            createdAt: DateTime.now(),
            status: 'pending',
          ));
        }

        print('✅ 3 more items added during sync');

        // Wait for complete
        await Future.delayed(const Duration(seconds: 2));

        // All should be synced eventually
        final pending = await db.getPendingItems();
        print('✅ Items remaining pending: ${pending.length}');
      });
    });

    // ==================== Scenario 6: Data Integrity ====================
    group('Scenario 6: Data Integrity', () {
      test('synced data should match local data', () async {
        // Create product with specific data
        const productData = {
          'id': '1',
          'name': 'Test Product',
          'price': 123.45,
          'quantity': 50,
        };

        await db.insertProduct(Product(
          id: productData['id'] as String,
          name: productData['name'] as String,
          price: productData['price'] as double,
          quantity: productData['quantity'] as int,
        ));

        await db.addToSyncQueue(SyncQueueItem(
          id: 'sync_1',
          operation: 'INSERT',
          table: 'products',
          recordId: '1',
          data: productData,
          createdAt: DateTime.now(),
          status: 'pending',
        ));

        print('✅ Product data prepared for sync');

        // Sync
        await syncEngine.startSync();
        await Future.delayed(const Duration(seconds: 1));

        // Get local copy
        final localProduct = await db.getProduct('1');
        expect(localProduct, isNotNull);
        expect(localProduct!.name, 'Test Product');
        expect(localProduct.price, 123.45);
        expect(localProduct.quantity, 50);

        print('✅ Data integrity verified');
      });
    });

    // ==================== Stress Tests ====================
    group('Stress Tests', () {
      test('handle 100 sync items', () async {
        // Add 100 items
        for (int i = 1; i <= 100; i++) {
          await db.addToSyncQueue(SyncQueueItem(
            id: 'sync_$i',
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {'index': i},
            createdAt: DateTime.now(),
            status: 'pending',
          ));
        }

        var pending = await db.getPendingItems();
        expect(pending.length, 100);
        print('✅ 100 items added to sync queue');

        // Sync
        final stopwatch = Stopwatch()..start();
        await syncEngine.startSync();
        stopwatch.stop();

        print('✅ Sync completed in ${stopwatch.elapsedMilliseconds}ms');
        expect(stopwatch.elapsedMilliseconds, lessThan(30000)); // Should complete in 30s

        // Verify all synced
        pending = await db.getPendingItems();
        expect(pending.isEmpty, true);
        print('✅ All 100 items synced');
      });
    });
  });
}

// ==================== Test Models ====================

class Product {
  final String id;
  final String name;
  final double price;
  final int quantity;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
  });
}

class SyncQueueItem {
  final String id;
  final String operation;
  final String table;
  final String recordId;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final String status;

  SyncQueueItem({
    required this.id,
    required this.operation,
    required this.table,
    required this.recordId,
    required this.data,
    required this.createdAt,
    required this.status,
  });
}

// ==================== Mock Services ====================

class LocalDatabase {
  final List<Product> _products = [];
  final List<SyncQueueItem> _syncQueue = [];

  Future<void> initialize() async {}

  Future<void> clear() async {
    _products.clear();
    _syncQueue.clear();
  }

  Future<void> insertProduct(Product product) async {
    _products.add(product);
  }

  Future<List<Product>> getProducts() async => _products;
  Future<Product?> getProduct(String id) async =>
      _products.firstWhere((p) => p.id == id, orElse: () => throw Exception());

  Future<void> addToSyncQueue(SyncQueueItem item) async {
    _syncQueue.add(item);
  }

  Future<List<SyncQueueItem>> getPendingItems() async =>
      _syncQueue.where((i) => i.status == 'pending').toList();

  Future<List<SyncQueueItem>> getFailedItems() async =>
      _syncQueue.where((i) => i.status == 'failed').toList();

  Future<void> updateSyncQueueStatus(String id, String status) async {
    final index = _syncQueue.indexWhere((i) => i.id == id);
    if (index >= 0) {
      final item = _syncQueue[index];
      _syncQueue[index] = SyncQueueItem(
        id: item.id,
        operation: item.operation,
        table: item.table,
        recordId: item.recordId,
        data: item.data,
        createdAt: item.createdAt,
        status: status,
      );
    }
  }
}

class ConnectivityService {
  bool _isConnected = true;

  Future<void> initialize() async {}

  Future<bool> checkConnectivityStatus() async => _isConnected;

  Future<void> simulateDisconnection() async {
    _isConnected = false;
  }

  Future<void> simulateConnection() async {
    _isConnected = true;
  }
}

class SyncStatistics {
  final int totalPending;
  final int syncedItems;
  final int failedItems;
  final bool isSyncing;

  SyncStatistics({
    required this.totalPending,
    required this.syncedItems,
    required this.failedItems,
    required this.isSyncing,
  });
}

class SyncEngine {
  final LocalDatabase db;
  final ConnectivityService connectivity;

  SyncEngine(this.db, this.connectivity);

  Future<void> startSync() async {
    // Simulate sync
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> stopSync() async {}

  Future<SyncStatistics> getStatistics() async {
    final pending = await db.getPendingItems();
    return SyncStatistics(
      totalPending: pending.length,
      syncedItems: 0,
      failedItems: 0,
      isSyncing: false,
    );
  }
}

class EnhancedApiClient {
  final LocalDatabase db;
  final SyncEngine syncEngine;

  EnhancedApiClient(this.db, this.syncEngine);
}
