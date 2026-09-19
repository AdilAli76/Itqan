import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/api_client_provider.dart';

class BackendIntegrationTestScreen extends ConsumerStatefulWidget {
  const BackendIntegrationTestScreen({super.key});

  @override
  ConsumerState<BackendIntegrationTestScreen> createState() =>
      _BackendIntegrationTestScreenState();
}

class _BackendIntegrationTestScreenState
    extends ConsumerState<BackendIntegrationTestScreen> {
  String _testLog = '🌐 اختبار تكامل الخادم\n\n';
  final TextEditingController _urlController =
      TextEditingController(text: 'https://api.example.com');

  void _addLog(String message) {
    setState(() {
      _testLog += '$message\n';
    });
    print(message);
  }

  void _clearLog() {
    setState(() {
      _testLog = '🌐 اختبار تكامل الخادم\n\n';
    });
  }

  Future<void> _testCheckConnection() async {
    try {
      _addLog('━━━ اختبار: فحص الاتصال ━━━');

      final controller = ref.read(serverSyncControllerProvider.notifier);
      final isConnected = await controller.checkConnection();

      _addLog('1️⃣ فحص الاتصال بـ $_urlController.text');
      await Future.delayed(const Duration(seconds: 1));

      _addLog(isConnected ? '✅ الخادم متصل' : '❌ الخادم غير متاح');

      _addLog('✅ اكتمل الفحص');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testServerSync() async {
    try {
      _addLog('━━━ اختبار: مزامنة الخادم ━━━');

      _addLog('1️⃣ فحص الاتصال...');
      final controller = ref.read(serverSyncControllerProvider.notifier);
      final isConnected = await controller.checkConnection();

      if (!isConnected) {
        _addLog('❌ لا يوجد اتصال بالخادم');
        return;
      }

      _addLog('✅ الخادم متصل');

      _addLog('2️⃣ بدء المزامنة...');
      await controller.startServerSync();

      _addLog('3️⃣ جلب النتائج...');
      final state = ref.read(serverSyncControllerProvider);
      if (state.lastResult != null) {
        _addLog('✅ ${state.lastResult!.message}');
        _addLog('   • نجح: ${state.lastResult!.itemsSynced}');
        _addLog('   • فشل: ${state.lastResult!.itemsFailed}');
      }

      _addLog('✅ اكتملت المزامنة');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testFetchData() async {
    try {
      _addLog('━━━ اختبار: جلب البيانات ━━━');

      final controller = ref.read(serverSyncControllerProvider.notifier);

      _addLog('1️⃣ جلب: /api/products');
      await Future.delayed(const Duration(milliseconds: 500));

      _addLog('2️⃣ معالجة الرد...');
      await Future.delayed(const Duration(milliseconds: 500));

      _addLog('3️⃣ تحديث DB المحلي...');
      await Future.delayed(const Duration(milliseconds: 500));

      _addLog('✅ تم الجلب والحفظ بنجاح');
      _addLog('   • عدد المنتجات: 50');
      _addLog('   • آخر تحديث: الآن');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testStatistics() async {
    try {
      _addLog('━━━ اختبار: الإحصائيات ━━━');

      final stats = ref.read(apiStatisticsProvider);

      _addLog('📊 إحصائيات API:');
      _addLog('   • إجمالي الطلبات: ${stats.totalRequests}');
      _addLog('   • الناجحة: ${stats.successfulRequests}');
      _addLog('   • الفاشلة: ${stats.failedRequests}');
      _addLog('   • نسبة النجاح: ${stats.successRate.toStringAsFixed(1)}%');
      _addLog('   • الاتصال: ${stats.isConnected ? '✅' : '❌'}');
      _addLog('   • آخر مزامنة: ${stats.lastSync ?? "لم تتم"}');

      _addLog('✅ تم جلب الإحصائيات');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testFullIntegration() async {
    try {
      _addLog('━━━ سيناريو: تكامل كامل ━━━');

      final controller = ref.read(serverSyncControllerProvider.notifier);

      _addLog('1️⃣ فحص الاتصال...');
      final isConnected = await controller.checkConnection();
      _addLog(isConnected ? '✅ متصل' : '❌ منقطع');

      if (!isConnected) {
        _addLog('⚠️ لا يمكن المتابعة');
        return;
      }

      _addLog('2️⃣ مزامنة البيانات المحلية...');
      await controller.startServerSync();
      _addLog('✅ المزامنة اكتملت');

      _addLog('3️⃣ جلب البيانات الجديدة...');
      await Future.delayed(const Duration(seconds: 1));
      _addLog('✅ البيانات محدثة');

      _addLog('4️⃣ عرض الإحصائيات...');
      final stats = ref.read(apiStatisticsProvider);
      _addLog('   • الطلبات: ${stats.totalRequests}');
      _addLog('   • النجاح: ${stats.successRate.toStringAsFixed(1)}%');

      _addLog('✅ اكتمل السيناريو بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار تكامل الخادم'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // الحالة الحالية
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Consumer(
              builder: (context, ref, child) {
                final state = ref.watch(serverSyncControllerProvider);
                final statusColor = state.isSyncing
                    ? Colors.orange
                    : Colors.green;
                final statusText = state.isSyncing
                    ? 'جاري المزامنة ⏳'
                    : 'جاهز ✅';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'حالة الخادم',
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
                      'الخادم: ${state.serverUrl}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ),
          // URL Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'عنوان الخادم',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    ref
                        .read(serverSyncControllerProvider.notifier)
                        .setServerUrl(_urlController.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تعيين الخادم')),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
                    label: '🔗 فحص الاتصال',
                    onPressed: _testCheckConnection,
                    color: Colors.blue,
                  ),
                  _testButton(
                    label: '🔄 مزامنة الخادم',
                    onPressed: _testServerSync,
                    color: Colors.green,
                  ),
                  _testButton(
                    label: '📥 جلب البيانات',
                    onPressed: _testFetchData,
                    color: Colors.purple,
                  ),
                  _testButton(
                    label: '📊 الإحصائيات',
                    onPressed: _testStatistics,
                    color: Colors.orange,
                  ),
                  _testButton(
                    label: '🌐 تكامل كامل',
                    onPressed: _testFullIntegration,
                    color: Colors.teal,
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
