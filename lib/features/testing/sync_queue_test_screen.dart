import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/local_database/local_db.dart';

class SyncQueueTestScreen extends ConsumerStatefulWidget {
  const SyncQueueTestScreen({super.key});

  @override
  ConsumerState<SyncQueueTestScreen> createState() => _SyncQueueTestScreenState();
}

class _SyncQueueTestScreenState extends ConsumerState<SyncQueueTestScreen> {
  String _testLog = '🔄 اختبار Sync Queue\n\n';

  void _addLog(String message) {
    setState(() {
      _testLog += '$message\n';
    });
    print(message);
  }

  void _clearLog() {
    setState(() {
      _testLog = '🔄 اختبار Sync Queue\n\n';
    });
  }

  Future<void> _testGetPendingItems() async {
    try {
      _addLog('━━━ اختبار: جلب العناصر المعلقة ━━━');

      final db = LocalDatabase();
      await db.initialize();

      final items = await db.getPendingSyncItems();
      _addLog('✅ عدد العناصر المعلقة: ${items.length}');

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final table = item['table_name'];
        final op = item['operation'];
        final recordId = item['record_id'];
        final retryCount = item['retry_count'];

        _addLog('   $i. $table - $op (ID: $recordId, Retries: $retryCount)');
      }

      if (items.isEmpty) {
        _addLog('ℹ️ لا توجد عناصر معلقة حالياً');
      }
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testAddToQueue() async {
    try {
      _addLog('━━━ اختبار: إضافة عناصر لـ Sync Queue ━━━');

      final db = LocalDatabase();
      await db.initialize();

      // أضف عنصر INSERT
      _addLog('📝 إضافة عنصر INSERT...');
      await db.addToSyncQueue(
        'products',
        'INSERT',
        'prod-test-001',
        {
          'id': 'prod-test-001',
          'name': 'منتج تجريبي للمزامنة',
          'price': 100.0,
        },
      );
      _addLog('✅ تم إضافة عنصر INSERT');

      // أضف عنصر UPDATE
      _addLog('📝 إضافة عنصر UPDATE...');
      await db.addToSyncQueue(
        'products',
        'UPDATE',
        'prod-001',
        {
          'id': 'prod-001',
          'price': 150.0,
        },
      );
      _addLog('✅ تم إضافة عنصر UPDATE');

      // أضف عنصر DELETE
      _addLog('📝 إضافة عنصر DELETE...');
      await db.addToSyncQueue(
        'products',
        'DELETE',
        'prod-old-001',
        {
          'id': 'prod-old-001',
        },
      );
      _addLog('✅ تم إضافة عنصر DELETE');

      _addLog('✅ تم إضافة جميع العناصر بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testSyncStatistics() async {
    try {
      _addLog('━━━ اختبار: إحصائيات المزامنة ━━━');

      final db = LocalDatabase();
      await db.initialize();

      final items = await db.getPendingSyncItems();

      // تحليل العناصر
      int insertCount = 0;
      int updateCount = 0;
      int deleteCount = 0;
      int totalRetries = 0;

      for (final item in items) {
        final op = item['operation'];
        if (op == 'INSERT') insertCount++;
        if (op == 'UPDATE') updateCount++;
        if (op == 'DELETE') deleteCount++;
        totalRetries += (item['retry_count'] as int);
      }

      _addLog('📊 إحصائيات المزامنة:');
      _addLog('   • العناصر المعلقة: ${items.length}');
      _addLog('   • العمليات:');
      _addLog('      - INSERT: $insertCount');
      _addLog('      - UPDATE: $updateCount');
      _addLog('      - DELETE: $deleteCount');
      _addLog('   • إجمالي محاولات الإعادة: $totalRetries');

      _addLog('✅ تم حساب الإحصائيات بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testMarkAsSuccess() async {
    try {
      _addLog('━━━ اختبار: وضع علامة النجاح ━━━');

      final db = LocalDatabase();
      await db.initialize();

      final items = await db.getPendingSyncItems();

      if (items.isEmpty) {
        _addLog('⚠️ لا توجد عناصر معلقة');
        return;
      }

      // وضع علامة على أول عنصر
      final firstItem = items.first;
      final syncId = firstItem['id'];

      _addLog('📝 وضع علامة النجاح على أول عنصر...');
      await db.markSyncItemAsSuccess(syncId);
      _addLog('✅ تم وضع علامة النجاح');

      // جلب العناصر المتبقية
      final remainingItems = await db.getPendingSyncItems();
      _addLog('✅ العناصر المتبقية: ${remainingItems.length}');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testSimulateSync() async {
    try {
      _addLog('━━━ اختبار: محاكاة عملية مزامنة كاملة ━━━');

      final db = LocalDatabase();
      await db.initialize();

      // الخطوة 1: جلب العناصر المعلقة
      _addLog('1️⃣ جلب العناصر المعلقة...');
      final items = await db.getPendingSyncItems();
      _addLog('✅ وجدنا ${items.length} عناصر معلقة');

      if (items.isEmpty) {
        _addLog('⚠️ لا توجد عناصر للمزامنة');
        return;
      }

      // الخطوة 2: محاكاة الإرسال
      _addLog('2️⃣ محاكاة الإرسال للخادم...');
      await Future.delayed(const Duration(seconds: 1));
      _addLog('✅ تم الإرسال بنجاح (محاكاة)');

      // الخطوة 3: وضع علامة النجاح
      _addLog('3️⃣ وضع علامات النجاح...');
      for (int i = 0; i < items.length && i < 3; i++) {
        await db.markSyncItemAsSuccess(items[i]['id']);
        _addLog('✅ تم وضع علامة ${i + 1}');
      }

      // الخطوة 4: جلب العناصر المتبقية
      _addLog('4️⃣ جلب العناصر المتبقية...');
      final remainingItems = await db.getPendingSyncItems();
      _addLog('✅ بقي ${remainingItems.length} عنصر');

      _addLog('✅ اكتملت عملية المزامنة المحاكاة');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار Sync Queue'),
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
                border: Border.all(color: Colors.teal),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _testLog,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: Colors.teal,
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
                    label: '📋 جلب المعلقات',
                    onPressed: _testGetPendingItems,
                    color: Colors.blue,
                  ),
                  _testButton(
                    label: '➕ إضافة للطابور',
                    onPressed: _testAddToQueue,
                    color: Colors.green,
                  ),
                  _testButton(
                    label: '📊 الإحصائيات',
                    onPressed: _testSyncStatistics,
                    color: Colors.orange,
                  ),
                  _testButton(
                    label: '✅ وضع علامة نجاح',
                    onPressed: _testMarkAsSuccess,
                    color: Colors.purple,
                  ),
                  _testButton(
                    label: '🔄 محاكاة مزامنة',
                    onPressed: _testSimulateSync,
                    color: Colors.red,
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
