import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/local_database/local_db.dart';
import '../../providers/database_provider.dart';

class LocalDbTestScreen extends ConsumerStatefulWidget {
  const LocalDbTestScreen({super.key});

  @override
  ConsumerState<LocalDbTestScreen> createState() => _LocalDbTestScreenState();
}

class _LocalDbTestScreenState extends ConsumerState<LocalDbTestScreen> {
  String _testLog = '📋 اختبار LocalDatabase\n\n';

  void _addLog(String message) {
    setState(() {
      _testLog += '$message\n';
    });
    print(message);
  }

  void _clearLog() {
    setState(() {
      _testLog = '📋 اختبار LocalDatabase\n\n';
    });
  }

  Future<void> _testInsertProduct() async {
    try {
      _addLog('━━━ اختبار: إضافة منتج ━━━');

      final db = LocalDatabase();
      await db.initialize();

      await db.insertProduct({
        'id': 'prod-001',
        'code': 'P001',
        'name': 'منتج تجريبي',
        'category': 'أجهزة',
        'price': 100.0,
        'quantity': 10,
        'min_quantity': 5,
      });

      _addLog('✅ تم إضافة المنتج بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testGetProducts() async {
    try {
      _addLog('━━━ اختبار: جلب المنتجات ━━━');

      final db = LocalDatabase();
      if (!db.isInitialized) {
        await db.initialize();
      }

      final products = await db.getProducts();
      _addLog('✅ تم جلب ${products.length} منتج');

      for (final p in products) {
        _addLog('   • ${p['name']}: ${p['price']} ريال');
      }
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testUpdateProduct() async {
    try {
      _addLog('━━━ اختبار: تحديث منتج ━━━');

      final db = LocalDatabase();
      if (!db.isInitialized) {
        await db.initialize();
      }

      await db.updateProduct('prod-001', {
        'name': 'منتج محدّث',
        'price': 150.0,
        'quantity': 20,
      });

      _addLog('✅ تم تحديث المنتج بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testDeleteProduct() async {
    try {
      _addLog('━━━ اختبار: حذف منتج ━━━');

      final db = LocalDatabase();
      if (!db.isInitialized) {
        await db.initialize();
      }

      await db.deleteProduct('prod-001');
      _addLog('✅ تم حذف المنتج بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testCreateInvoice() async {
    try {
      _addLog('━━━ اختبار: إنشاء فاتورة ━━━');

      final db = LocalDatabase();
      if (!db.isInitialized) {
        await db.initialize();
      }

      final invoiceId = await db.createInvoice(
        customerId: 'cust-001',
        customerName: 'محمد أحمد',
        subtotal: 500.0,
        tax: 50.0,
        discount: 25.0,
        total: 525.0,
        paymentMethod: 'cash',
      );

      _addLog('✅ تم إنشاء الفاتورة: $invoiceId');

      // إضافة عناصر للفاتورة
      await db.addInvoiceItem(
        invoiceId: invoiceId,
        productId: 'prod-001',
        productName: 'منتج تجريبي',
        quantity: 5,
        unitPrice: 100.0,
      );

      _addLog('✅ تم إضافة عنصر للفاتورة');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testGetInvoices() async {
    try {
      _addLog('━━━ اختبار: جلب الفواتير ━━━');

      final db = LocalDatabase();
      if (!db.isInitialized) {
        await db.initialize();
      }

      final invoices = await db.getInvoices();
      _addLog('✅ تم جلب ${invoices.length} فاتورة');

      for (final inv in invoices) {
        _addLog('   • ${inv['invoice_number']}: ${inv['total']} ريال');
      }
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testSyncQueue() async {
    try {
      _addLog('━━━ اختبار: Sync Queue ━━━');

      final db = LocalDatabase();
      if (!db.isInitialized) {
        await db.initialize();
      }

      final items = await db.getPendingSyncItems();
      _addLog('✅ عدد العناصر المعلقة: ${items.length}');

      for (final item in items) {
        _addLog('   • ${item['table_name']}: ${item['operation']}');
      }
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار قاعدة البيانات المحلية'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Log Display
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _testLog,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
          ),
          // Buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _testButton(
                    label: '➕ إضافة منتج',
                    onPressed: _testInsertProduct,
                    color: Colors.blue,
                  ),
                  _testButton(
                    label: '📋 جلب منتجات',
                    onPressed: _testGetProducts,
                    color: Colors.green,
                  ),
                  _testButton(
                    label: '✏️ تحديث منتج',
                    onPressed: _testUpdateProduct,
                    color: Colors.orange,
                  ),
                  _testButton(
                    label: '🗑️ حذف منتج',
                    onPressed: _testDeleteProduct,
                    color: Colors.red,
                  ),
                  _testButton(
                    label: '💰 إنشاء فاتورة',
                    onPressed: _testCreateInvoice,
                    color: Colors.purple,
                  ),
                  _testButton(
                    label: '📄 جلب فواتير',
                    onPressed: _testGetInvoices,
                    color: Colors.teal,
                  ),
                  _testButton(
                    label: '🔄 Sync Queue',
                    onPressed: _testSyncQueue,
                    color: Colors.indigo,
                  ),
                  _testButton(
                    label: '🗑️ مسح السجل',
                    onPressed: _clearLog,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _testButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }
}
