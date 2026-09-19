// اختبارات الوحدة - قاعدة البيانات المحلية
// lib/tests/unit/database_unit_tests.dart

import 'package:flutter_test/flutter_test.dart';
import '../../core/database/local_db.dart';

void main() {
  group('LocalDatabase Unit Tests', () {
    late LocalDatabase db;

    setUp(() async {
      db = LocalDatabase();
      await db.initialize();
    });

    tearDown(() async {
      await db.clear();
    });

    // ==================== Product Tests ====================
    group('Products', () {
      test('insertProduct should add product to database', () async {
        final product = Product(
          id: '1',
          name: 'Test Product',
          price: 100.0,
          quantity: 10,
        );

        await db.insertProduct(product);
        final products = await db.getProducts();

        expect(products.length, 1);
        expect(products.first.id, '1');
        expect(products.first.name, 'Test Product');
      });

      test('getProduct should retrieve single product', () async {
        final product = Product(
          id: '1',
          name: 'Test Product',
          price: 100.0,
          quantity: 10,
        );

        await db.insertProduct(product);
        final retrieved = await db.getProduct('1');

        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Test Product');
      });

      test('updateProduct should modify existing product', () async {
        final product = Product(
          id: '1',
          name: 'Original',
          price: 100.0,
          quantity: 10,
        );

        await db.insertProduct(product);

        final updated = Product(
          id: '1',
          name: 'Updated',
          price: 200.0,
          quantity: 20,
        );

        await db.updateProduct(updated);
        final retrieved = await db.getProduct('1');

        expect(retrieved!.name, 'Updated');
        expect(retrieved.price, 200.0);
      });

      test('deleteProduct should remove product from database', () async {
        final product = Product(
          id: '1',
          name: 'To Delete',
          price: 100.0,
          quantity: 10,
        );

        await db.insertProduct(product);
        await db.deleteProduct('1');

        final retrieved = await db.getProduct('1');
        expect(retrieved, isNull);
      });

      test('insertProducts (batch) should add multiple products', () async {
        final products = [
          Product(id: '1', name: 'P1', price: 100.0, quantity: 10),
          Product(id: '2', name: 'P2', price: 200.0, quantity: 20),
          Product(id: '3', name: 'P3', price: 300.0, quantity: 30),
        ];

        await db.insertProducts(products);
        final allProducts = await db.getProducts();

        expect(allProducts.length, 3);
      });

      test('getProducts should return all products', () async {
        final products = [
          Product(id: '1', name: 'P1', price: 100.0, quantity: 10),
          Product(id: '2', name: 'P2', price: 200.0, quantity: 20),
        ];

        await db.insertProducts(products);
        final allProducts = await db.getProducts();

        expect(allProducts.length, 2);
        expect(allProducts.map((p) => p.id).toList(), ['1', '2']);
      });
    });

    // ==================== Customer Tests ====================
    group('Customers', () {
      test('insertCustomer should add customer', () async {
        final customer = Customer(
          id: '1',
          name: 'Test Customer',
          email: 'test@example.com',
          phone: '+201000000000',
        );

        await db.insertCustomer(customer);
        final customers = await db.getCustomers();

        expect(customers.length, 1);
        expect(customers.first.name, 'Test Customer');
      });

      test('updateCustomer should modify customer', () async {
        final customer = Customer(
          id: '1',
          name: 'Original',
          email: 'old@example.com',
          phone: '+201000000000',
        );

        await db.insertCustomer(customer);

        final updated = Customer(
          id: '1',
          name: 'Updated',
          email: 'new@example.com',
          phone: '+201000000000',
        );

        await db.updateCustomer(updated);
        final retrieved = await db.getCustomer('1');

        expect(retrieved!.name, 'Updated');
        expect(retrieved.email, 'new@example.com');
      });

      test('deleteCustomer should remove customer', () async {
        final customer = Customer(
          id: '1',
          name: 'To Delete',
          email: 'delete@example.com',
          phone: '+201000000000',
        );

        await db.insertCustomer(customer);
        await db.deleteCustomer('1');

        final retrieved = await db.getCustomer('1');
        expect(retrieved, isNull);
      });
    });

    // ==================== Invoice Tests ====================
    group('Invoices', () {
      test('insertInvoice should add invoice', () async {
        final invoice = Invoice(
          id: '1',
          customerId: 'cust1',
          total: 1000.0,
          status: 'draft',
          createdAt: DateTime.now(),
        );

        await db.insertInvoice(invoice);
        final invoices = await db.getInvoices();

        expect(invoices.length, 1);
        expect(invoices.first.status, 'draft');
      });

      test('updateInvoice should modify invoice', () async {
        final invoice = Invoice(
          id: '1',
          customerId: 'cust1',
          total: 1000.0,
          status: 'draft',
          createdAt: DateTime.now(),
        );

        await db.insertInvoice(invoice);

        final updated = Invoice(
          id: '1',
          customerId: 'cust1',
          total: 1500.0,
          status: 'posted',
          createdAt: DateTime.now(),
        );

        await db.updateInvoice(updated);
        final retrieved = await db.getInvoice('1');

        expect(retrieved!.total, 1500.0);
        expect(retrieved.status, 'posted');
      });

      test('getInvoicesByStatus should filter by status', () async {
        final invoices = [
          Invoice(
            id: '1',
            customerId: 'cust1',
            total: 1000.0,
            status: 'draft',
            createdAt: DateTime.now(),
          ),
          Invoice(
            id: '2',
            customerId: 'cust2',
            total: 2000.0,
            status: 'posted',
            createdAt: DateTime.now(),
          ),
        ];

        await db.insertInvoices(invoices);
        final drafts = await db.getInvoicesByStatus('draft');

        expect(drafts.length, 1);
        expect(drafts.first.id, '1');
      });
    });

    // ==================== Sync Queue Tests ====================
    group('Sync Queue', () {
      test('addToSyncQueue should add pending item', () async {
        final item = SyncQueueItem(
          id: '1',
          operation: 'INSERT',
          table: 'products',
          recordId: '1',
          data: {'name': 'Test', 'price': 100},
          createdAt: DateTime.now(),
          status: 'pending',
        );

        await db.addToSyncQueue(item);
        final pending = await db.getPendingItems();

        expect(pending.length, 1);
        expect(pending.first.status, 'pending');
      });

      test('getPendingItems should return only pending items', () async {
        final items = [
          SyncQueueItem(
            id: '1',
            operation: 'INSERT',
            table: 'products',
            recordId: '1',
            data: {},
            createdAt: DateTime.now(),
            status: 'pending',
          ),
          SyncQueueItem(
            id: '2',
            operation: 'UPDATE',
            table: 'products',
            recordId: '2',
            data: {},
            createdAt: DateTime.now(),
            status: 'synced',
          ),
        ];

        for (var item in items) {
          await db.addToSyncQueue(item);
        }

        final pending = await db.getPendingItems();
        expect(pending.length, 1);
        expect(pending.first.id, '1');
      });

      test('updateSyncQueueStatus should mark item as synced', () async {
        final item = SyncQueueItem(
          id: '1',
          operation: 'INSERT',
          table: 'products',
          recordId: '1',
          data: {},
          createdAt: DateTime.now(),
          status: 'pending',
        );

        await db.addToSyncQueue(item);
        await db.updateSyncQueueStatus('1', 'synced');

        final pending = await db.getPendingItems();
        expect(pending.isEmpty, true);

        final synced = await db.getSyncQueueItem('1');
        expect(synced!.status, 'synced');
      });

      test('removeSyncQueueItem should delete item', () async {
        final item = SyncQueueItem(
          id: '1',
          operation: 'INSERT',
          table: 'products',
          recordId: '1',
          data: {},
          createdAt: DateTime.now(),
          status: 'pending',
        );

        await db.addToSyncQueue(item);
        await db.removeSyncQueueItem('1');

        final retrieved = await db.getSyncQueueItem('1');
        expect(retrieved, isNull);
      });

      test('getFailedItems should return only failed items', () async {
        final items = [
          SyncQueueItem(
            id: '1',
            operation: 'INSERT',
            table: 'products',
            recordId: '1',
            data: {},
            createdAt: DateTime.now(),
            status: 'pending',
          ),
          SyncQueueItem(
            id: '2',
            operation: 'UPDATE',
            table: 'products',
            recordId: '2',
            data: {},
            createdAt: DateTime.now(),
            status: 'failed',
          ),
        ];

        for (var item in items) {
          await db.addToSyncQueue(item);
        }

        final failed = await db.getFailedItems();
        expect(failed.length, 1);
        expect(failed.first.id, '2');
      });
    });

    // ==================== Edge Cases ====================
    group('Edge Cases', () {
      test('getProduct with invalid id should return null', () async {
        final result = await db.getProduct('invalid_id');
        expect(result, isNull);
      });

      test('updateProduct that does not exist should handle gracefully', () async {
        final product = Product(
          id: 'nonexistent',
          name: 'Test',
          price: 100.0,
          quantity: 10,
        );

        // Should not throw
        expect(
          () => db.updateProduct(product),
          returnsNormally,
        );
      });

      test('deleteProduct twice should handle gracefully', () async {
        final product = Product(
          id: '1',
          name: 'Test',
          price: 100.0,
          quantity: 10,
        );

        await db.insertProduct(product);
        await db.deleteProduct('1');

        // Second delete should not throw
        expect(
          () => db.deleteProduct('1'),
          returnsNormally,
        );
      });

      test('insertProduct with null values should fail or handle', () async {
        // This test depends on validation rules
        // Either should throw or store default values
        expect(
          () => db.insertProduct(Product(
            id: '',
            name: '',
            price: 0,
            quantity: 0,
          )),
          throwsA(isA<Exception>()),
        );
      });

      test('empty database operations should work correctly', () async {
        final products = await db.getProducts();
        final invoices = await db.getInvoices();
        final customers = await db.getCustomers();
        final pending = await db.getPendingItems();

        expect(products.isEmpty, true);
        expect(invoices.isEmpty, true);
        expect(customers.isEmpty, true);
        expect(pending.isEmpty, true);
      });
    });

    // ==================== Performance ====================
    group('Performance', () {
      test('insert 100 products should complete in reasonable time', () async {
        final stopwatch = Stopwatch()..start();

        final products = List.generate(
          100,
          (i) => Product(
            id: i.toString(),
            name: 'Product $i',
            price: i * 10.0,
            quantity: i,
          ),
        );

        await db.insertProducts(products);

        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('retrieve 100 products should complete in reasonable time', () async {
        final products = List.generate(
          100,
          (i) => Product(
            id: i.toString(),
            name: 'Product $i',
            price: i * 10.0,
            quantity: i,
          ),
        );

        await db.insertProducts(products);

        final stopwatch = Stopwatch()..start();
        await db.getProducts();
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      });

      test('update 50 items should complete in reasonable time', () async {
        final items = List.generate(
          50,
          (i) => SyncQueueItem(
            id: i.toString(),
            operation: 'INSERT',
            table: 'products',
            recordId: i.toString(),
            data: {},
            createdAt: DateTime.now(),
            status: 'pending',
          ),
        );

        for (var item in items) {
          await db.addToSyncQueue(item);
        }

        final stopwatch = Stopwatch()..start();

        for (var i = 0; i < 50; i++) {
          await db.updateSyncQueueStatus(i.toString(), 'synced');
        }

        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
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

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
  });
}

class Customer {
  final String id;
  final String name;
  final String email;
  final String phone;

  Customer({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
  });
}

class Invoice {
  final String id;
  final String customerId;
  final double total;
  final String status;
  final DateTime createdAt;

  Invoice({
    required this.id,
    required this.customerId,
    required this.total,
    required this.status,
    required this.createdAt,
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
