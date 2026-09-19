import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/local_database/local_db.dart';

class InvoicesTestScreen extends ConsumerStatefulWidget {
  const InvoicesTestScreen({super.key});

  @override
  ConsumerState<InvoicesTestScreen> createState() => _InvoicesTestScreenState();
}

class _InvoicesTestScreenState extends ConsumerState<InvoicesTestScreen> {
  String _testLog = '📋 اختبار الفواتير (Invoices)\n\n';
  List<String> _createdInvoiceIds = [];

  void _addLog(String message) {
    setState(() {
      _testLog += '$message\n';
    });
    print(message);
  }

  void _clearLog() {
    setState(() {
      _testLog = '📋 اختبار الفواتير (Invoices)\n\n';
      _createdInvoiceIds = [];
    });
  }

  Future<void> _testCreateInvoices() async {
    try {
      _addLog('━━━ اختبار: إنشاء فواتير متعددة ━━━');

      final db = LocalDatabase();
      await db.initialize();

      // إنشاء فاتورة 1
      _addLog('📝 إنشاء فاتورة 1...');
      final invoiceId1 = await db.createInvoice(
        customerId: 'cust-001',
        customerName: 'محمد أحمد',
        subtotal: 500.0,
        tax: 50.0,
        discount: 25.0,
        total: 525.0,
        paymentMethod: 'cash',
        notes: 'فاتورة البيع رقم 1',
      );
      _createdInvoiceIds.add(invoiceId1);
      _addLog('✅ تم إنشاء فاتورة 1: $invoiceId1');

      // إنشاء فاتورة 2
      _addLog('📝 إنشاء فاتورة 2...');
      final invoiceId2 = await db.createInvoice(
        customerId: 'cust-002',
        customerName: 'فاطمة محمود',
        subtotal: 1000.0,
        tax: 100.0,
        discount: 50.0,
        total: 1050.0,
        paymentMethod: 'card',
        notes: 'فاتورة البيع رقم 2',
      );
      _createdInvoiceIds.add(invoiceId2);
      _addLog('✅ تم إنشاء فاتورة 2: $invoiceId2');

      // إنشاء فاتورة 3
      _addLog('📝 إنشاء فاتورة 3...');
      final invoiceId3 = await db.createInvoice(
        customerId: 'cust-003',
        customerName: 'علي سالم',
        subtotal: 200.0,
        tax: 20.0,
        discount: 10.0,
        total: 210.0,
        paymentMethod: 'check',
        notes: 'فاتورة البيع رقم 3',
      );
      _createdInvoiceIds.add(invoiceId3);
      _addLog('✅ تم إنشاء فاتورة 3: $invoiceId3');

      _addLog('✅ تم إنشاء 3 فواتير بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testAddInvoiceItems() async {
    try {
      _addLog('━━━ اختبار: إضافة عناصر للفواتير ━━━');

      final db = LocalDatabase();
      await db.initialize();

      if (_createdInvoiceIds.isEmpty) {
        _addLog('⚠️ لا توجد فواتير! أنشئ فواتير أولاً');
        return;
      }

      // إضافة عناصر للفاتورة الأولى
      _addLog('📝 إضافة عناصر للفاتورة 1...');
      final invoiceId1 = _createdInvoiceIds[0];

      await db.addInvoiceItem(
        invoiceId: invoiceId1,
        productId: 'prod-001',
        productName: 'جهاز كمبيوتر محمول',
        quantity: 2,
        unitPrice: 200.0,
      );
      _addLog('✅ تمت إضافة عنصر 1');

      await db.addInvoiceItem(
        invoiceId: invoiceId1,
        productId: 'prod-002',
        productName: 'فأرة لاسلكية',
        quantity: 5,
        unitPrice: 30.0,
      );
      _addLog('✅ تمت إضافة عنصر 2');

      // إضافة عناصر للفاتورة الثانية
      if (_createdInvoiceIds.length > 1) {
        _addLog('📝 إضافة عناصر للفاتورة 2...');
        final invoiceId2 = _createdInvoiceIds[1];

        await db.addInvoiceItem(
          invoiceId: invoiceId2,
          productId: 'prod-003',
          productName: 'شاشة 4K',
          quantity: 1,
          unitPrice: 500.0,
        );
        _addLog('✅ تمت إضافة عنصر 1 للفاتورة 2');

        await db.addInvoiceItem(
          invoiceId: invoiceId2,
          productId: 'prod-004',
          productName: 'لوحة مفاتيح ميكانيكية',
          quantity: 3,
          unitPrice: 150.0,
        );
        _addLog('✅ تمت إضافة عنصر 2 للفاتورة 2');
      }

      _addLog('✅ تمت إضافة جميع العناصر بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testGetInvoiceItems() async {
    try {
      _addLog('━━━ اختبار: جلب عناصر الفاتورة ━━━');

      final db = LocalDatabase();
      await db.initialize();

      if (_createdInvoiceIds.isEmpty) {
        _addLog('⚠️ لا توجد فواتير!');
        return;
      }

      for (int i = 0; i < _createdInvoiceIds.length; i++) {
        final invoiceId = _createdInvoiceIds[i];
        _addLog('📝 جلب عناصر الفاتورة ${i + 1}...');

        final items = await db.getInvoiceItems(invoiceId);
        _addLog('✅ عدد العناصر: ${items.length}');

        for (final item in items) {
          final name = item['product_name'];
          final qty = item['quantity'];
          final price = item['unit_price'];
          final total = item['total_price'];
          _addLog('   • $name: $qty × $price = $total ريال');
        }
      }
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testGetAllInvoices() async {
    try {
      _addLog('━━━ اختبار: جلب جميع الفواتير ━━━');

      final db = LocalDatabase();
      await db.initialize();

      final invoices = await db.getInvoices();
      _addLog('✅ عدد الفواتير: ${invoices.length}');

      for (final inv in invoices) {
        final number = inv['invoice_number'];
        final customer = inv['customer_name'];
        final total = inv['total'];
        final status = inv['status'];
        _addLog('   • $number ($customer): $total ريال - $status');
      }
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testInvoiceSummary() async {
    try {
      _addLog('━━━ اختبار: ملخص الفواتير ━━━');

      final db = LocalDatabase();
      await db.initialize();

      final invoices = await db.getInvoices();

      double totalAmount = 0;
      double totalTax = 0;
      double totalDiscount = 0;

      for (final inv in invoices) {
        totalAmount += (inv['total'] as num).toDouble();
        totalTax += (inv['tax'] as num).toDouble();
        totalDiscount += (inv['discount'] as num).toDouble();
      }

      _addLog('📊 ملخص المبيعات:');
      _addLog('   • عدد الفواتير: ${invoices.length}');
      _addLog('   • إجمالي المبيعات: $totalAmount ريال');
      _addLog('   • إجمالي الضرائب: $totalTax ريال');
      _addLog('   • إجمالي الخصومات: $totalDiscount ريال');
      _addLog('   • الصافي: ${totalAmount - totalTax - totalDiscount} ريال');

      _addLog('✅ تم حساب الملخص بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testInvoiceWithItems() async {
    try {
      _addLog('━━━ اختبار: الفاتورة مع العناصر (تفصيلي) ━━━');

      final db = LocalDatabase();
      await db.initialize();

      final invoices = await db.getInvoices();

      for (int i = 0; i < invoices.length; i++) {
        final inv = invoices[i];
        _addLog('📄 الفاتورة ${i + 1}: ${inv['invoice_number']}');
        _addLog('   👤 العميل: ${inv['customer_name']}');
        _addLog('   💰 الإجمالي: ${inv['total']} ريال');

        final items = await db.getInvoiceItems(inv['id']);
        _addLog('   📦 العناصر (${items.length}):');

        for (final item in items) {
          _addLog('      • ${item['product_name']}: ${item['quantity']} × ${item['unit_price']} = ${item['total_price']}');
        }

        _addLog('');
      }
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار الفواتير (Invoices)'),
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
                border: Border.all(color: Colors.amber),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _testLog,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: Colors.amber,
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
                    label: '💰 إنشاء فواتير',
                    onPressed: _testCreateInvoices,
                    color: Colors.purple,
                  ),
                  _testButton(
                    label: '📦 إضافة عناصر',
                    onPressed: _testAddInvoiceItems,
                    color: Colors.deepOrange,
                  ),
                  _testButton(
                    label: '📋 جلب العناصر',
                    onPressed: _testGetInvoiceItems,
                    color: Colors.cyan,
                  ),
                  _testButton(
                    label: '📄 جميع الفواتير',
                    onPressed: _testGetAllInvoices,
                    color: Colors.green,
                  ),
                  _testButton(
                    label: '📊 ملخص البيانات',
                    onPressed: _testInvoiceSummary,
                    color: Colors.blue,
                  ),
                  _testButton(
                    label: '🔍 التفاصيل الكاملة',
                    onPressed: _testInvoiceWithItems,
                    color: Colors.pink,
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
