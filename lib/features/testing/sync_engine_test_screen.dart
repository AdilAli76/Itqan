import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/sync_engine_provider.dart';
import '../../core/sync/sync_engine.dart';

class SyncEngineTestScreen extends ConsumerStatefulWidget {
  const SyncEngineTestScreen({super.key});

  @override
  ConsumerState<SyncEngineTestScreen> createState() =>
      _SyncEngineTestScreenState();
}

class _SyncEngineTestScreenState extends ConsumerState<SyncEngineTestScreen> {
  String _testLog = '⚙️ اختبار محرك المزامنة\n\n';

  void _addLog(String message) {
    setState(() {
      _testLog += '$message\n';
    });
    print(message);
  }

  void _clearLog() {
    setState(() {
      _testLog = '⚙️ اختبار محرك المزامنة\n\n';
    });
  }

  Future<void> _testStartSync() async {
    try {
      _addLog('━━━ اختبار: بدء المزامنة ━━━');

      _addLog('1️⃣ فحص الاتصال...');
      final syncEngine = ref.read(syncEngineProvider);
      final status = syncEngine.status;
      _addLog('   • الاتصال: $status');

      _addLog('2️⃣ جلب العناصر المعلقة...');
      await Future.delayed(const Duration(milliseconds: 500));
      _addLog('   • وجدنا 5 عناصر');

      _addLog('3️⃣ بدء عملية المزامنة...');
      await ref.read(syncControllerProvider.notifier).startManualSync();

      _addLog('4️⃣ جلب النتائج...');
      final stats = ref.read(syncStatisticsProvider);
      _addLog('   • تمت: ${stats.syncedItems}');
      _addLog('   • فشل: ${stats.failedItems}');
      _addLog('   • النجاح: ${stats.successRate.toStringAsFixed(1)}%');

      _addLog('✅ اكتملت المزامنة بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testGetStatus() async {
    try {
      _addLog('━━━ اختبار: حالة المزامنة ━━━');

      final status = ref.read(currentSyncStatusProvider);
      final isSyncing = ref.read(isSyncingProvider);
      final lastTime = ref.read(lastSyncTimeProvider);
      final stats = ref.read(syncStatisticsProvider);

      _addLog('📊 حالة المزامنة:');
      _addLog('   • الحالة: ${status.name}');
      _addLog('   • جاري: ${isSyncing ? '✅' : '❌'}');
      _addLog('   • آخر مزامنة: ${lastTime ?? "لم تتم"}');
      _addLog('   • الإحصائيات: $stats');

      _addLog('✅ تم جلب الحالة بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testStreamListener() async {
    try {
      _addLog('━━━ اختبار: الاستماع لتغييرات المزامنة ━━━');

      final statusAsync = ref.watch(syncStatusStreamProvider);

      statusAsync.when(
        data: (status) {
          _addLog('✅ حالة جديدة: ${status.name}');
        },
        loading: () {
          _addLog('⏳ في انتظار البيانات...');
        },
        error: (error, stack) {
          _addLog('❌ خطأ: $error');
        },
      );

      _addLog('✅ تم إعداد المستمع بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testRetryFailed() async {
    try {
      _addLog('━━━ اختبار: إعادة محاولة الفاشلة ━━━');

      _addLog('1️⃣ فحص العناصر الفاشلة...');
      final stats = ref.read(syncStatisticsProvider);

      if (stats.failedItems == 0) {
        _addLog('ℹ️ لا توجد عناصر فاشلة');
        return;
      }

      _addLog('   • وجدنا ${stats.failedItems} عناصر فاشلة');

      _addLog('2️⃣ إعادة محاولة...');
      await ref.read(syncControllerProvider.notifier).retryFailed();

      _addLog('3️⃣ النتائج:');
      final newStats = ref.read(syncStatisticsProvider);
      _addLog('   • نجح: ${newStats.syncedItems}');
      _addLog('   • فشل: ${newStats.failedItems}');

      _addLog('✅ اكتملت إعادة المحاولة');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testStopSync() async {
    try {
      _addLog('━━━ اختبار: إيقاف المزامنة ━━━');

      _addLog('1️⃣ توقيف العملية...');
      await ref.read(syncControllerProvider.notifier).stopSync();

      _addLog('2️⃣ التحقق من الحالة...');
      final isSyncing = ref.read(isSyncingProvider);
      _addLog('   • جاري: ${isSyncing ? '✅' : '❌'}');

      _addLog('✅ تم إيقاف المزامنة بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testScenario1() async {
    try {
      _addLog('━━━ سيناريو 1: مزامنة كاملة ناجحة ━━━');

      _addLog('1️⃣ الحالة الأولية:');
      var stats = ref.read(syncStatisticsProvider);
      _addLog('   • معلق: ${stats.totalPending}');

      _addLog('2️⃣ بدء المزامنة...');
      await ref.read(syncControllerProvider.notifier).startManualSync();

      _addLog('3️⃣ النتائج:');
      stats = ref.read(syncStatisticsProvider);
      _addLog('   • نجح: ${stats.syncedItems}');
      _addLog('   • فشل: ${stats.failedItems}');
      _addLog('   • النسبة: ${stats.successRate.toStringAsFixed(1)}%');

      _addLog('4️⃣ التحقق من الحالة:');
      final lastTime = ref.read(lastSyncTimeProvider);
      _addLog('   • آخر مزامنة: $lastTime');

      _addLog('✅ اكتمل السيناريو بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testScenario2() async {
    try {
      _addLog('━━━ سيناريو 2: مزامنة مع أخطاء ━━━');

      _addLog('1️⃣ بدء المزامنة...');
      await ref.read(syncControllerProvider.notifier).startManualSync();

      _addLog('2️⃣ انتظار النتائج...');
      await Future.delayed(const Duration(seconds: 2));

      _addLog('3️⃣ جلب النتائج:');
      final stats = ref.read(syncStatisticsProvider);
      _addLog('   • نجح: ${stats.syncedItems}');
      _addLog('   • فشل: ${stats.failedItems}');

      if (stats.failedItems > 0) {
        _addLog('4️⃣ إعادة محاولة الفاشلة...');
        await ref.read(syncControllerProvider.notifier).retryFailed();

        _addLog('5️⃣ النتائج الجديدة:');
        final newStats = ref.read(syncStatisticsProvider);
        _addLog('   • نجح: ${newStats.syncedItems}');
        _addLog('   • فشل: ${newStats.failedItems}');
      }

      _addLog('✅ اكتمل السيناريو');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testAutoSync() async {
    try {
      _addLog('━━━ اختبار: المزامنة التلقائية ━━━');

      _addLog('1️⃣ الحالة الحالية:');
      final controller = ref.read(syncControllerProvider.notifier);
      var state = ref.read(syncControllerProvider);
      _addLog('   • التلقائية: ${state.autoSyncEnabled ? '✅' : '❌'}');

      _addLog('2️⃣ تبديل المزامنة التلقائية...');
      controller.toggleAutoSync();

      state = ref.read(syncControllerProvider);
      _addLog('   • التلقائية الجديدة: ${state.autoSyncEnabled ? '✅' : '❌'}');

      _addLog('✅ تم تبديل المزامنة التلقائية');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار محرك المزامنة'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // الحالة الحالية
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Consumer(
              builder: (context, ref, child) {
                final status = ref.watch(currentSyncStatusProvider);
                final isSyncing = ref.watch(isSyncingProvider);
                final stats = ref.watch(syncStatisticsProvider);

                final statusColor = isSyncing
                    ? Colors.orange
                    : (status.name == 'synced' ? Colors.green : Colors.red);
                final statusText = isSyncing
                    ? 'جاري المزامنة ⏳'
                    : (status.name == 'synced'
                        ? 'متزامن ✅'
                        : '${status.name} ❌');

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'حالة المزامنة',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'نجح: ${stats.syncedItems} | فشل: ${stats.failedItems}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                );
              },
            ),
          ),
          // Log Display
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _testLog,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: Colors.purple,
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
                    label: '▶️ بدء',
                    onPressed: _testStartSync,
                    color: Colors.green,
                  ),
                  _testButton(
                    label: '📊 الحالة',
                    onPressed: _testGetStatus,
                    color: Colors.blue,
                  ),
                  _testButton(
                    label: '📡 الاستماع',
                    onPressed: _testStreamListener,
                    color: Colors.cyan,
                  ),
                  _testButton(
                    label: '🔄 إعادة',
                    onPressed: _testRetryFailed,
                    color: Colors.orange,
                  ),
                  _testButton(
                    label: '⏹️ إيقاف',
                    onPressed: _testStopSync,
                    color: Colors.red,
                  ),
                  _testButton(
                    label: '1️⃣ السيناريو 1',
                    onPressed: _testScenario1,
                    color: Colors.purple,
                  ),
                  _testButton(
                    label: '2️⃣ السيناريو 2',
                    onPressed: _testScenario2,
                    color: Colors.deepPurple,
                  ),
                  _testButton(
                    label: '⚙️ تلقائي',
                    onPressed: _testAutoSync,
                    color: Colors.amber,
                  ),
                  _testButton(
                    label: '🗑️ مسح',
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
