import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/connectivity/connectivity_state.dart';

class ConnectivityTestScreen extends ConsumerStatefulWidget {
  const ConnectivityTestScreen({super.key});

  @override
  ConsumerState<ConnectivityTestScreen> createState() =>
      _ConnectivityTestScreenState();
}

class _ConnectivityTestScreenState extends ConsumerState<ConnectivityTestScreen> {
  String _testLog = '🌐 اختبار الاتصال بالانترنت\n\n';

  void _addLog(String message) {
    setState(() {
      _testLog += '$message\n';
    });
    print(message);
  }

  void _clearLog() {
    setState(() {
      _testLog = '🌐 اختبار الاتصال بالانترنت\n\n';
    });
  }

  Future<void> _testCurrentStatus() async {
    try {
      _addLog('━━━ اختبار: حالة الاتصال الحالية ━━━');

      final isOnline = ref.read(isOnlineProvider);
      final info = ref.read(connectivityInfoProvider);

      _addLog('📊 معلومات الاتصال:');
      _addLog('   • الحالة: ${info.status.name}');
      _addLog('   • متصل: ${isOnline ? '✅ نعم' : '❌ لا'}');
      _addLog('   • نوع الاتصال: ${info.connectionType}');
      _addLog('   • محاولات الإعادة: ${info.retryCount}');
      if (info.lastCheckedAt != null) {
        _addLog('   • آخر فحص: ${info.lastCheckedAt}');
      }

      _addLog('✅ تم الفحص بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testStreamListener() async {
    try {
      _addLog('━━━ اختبار: الاستماع لتغييرات الاتصال ━━━');

      final streamAsync = ref.watch(connectivityStreamProvider);

      streamAsync.when(
        data: (info) {
          _addLog('✅ البيانات المستقبلة:');
          _addLog('   • الحالة: ${info.status.name}');
          _addLog('   • متصل: ${info.isOnline ? '✅' : '❌'}');
          _addLog('   • النوع: ${info.connectionType}');
        },
        loading: () {
          _addLog('⏳ في انتظار البيانات...');
        },
        error: (error, stack) {
          _addLog('❌ خطأ: $error');
        },
      );
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  void _testSimulateDisconnection() {
    try {
      _addLog('━━━ اختبار: محاكاة فقدان الاتصال ━━━');

      ref.read(connectivitySimulatorProvider.notifier).simulateDisconnection();
      _addLog('🔴 تم محاكاة: فقدان الاتصال');

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          final info = ref.read(connectivityInfoProvider);
          _addLog('📊 الحالة الحالية:');
          _addLog('   • متصل: ${info.isOnline ? '✅' : '❌'}');
          _addLog('   • نوع الاتصال: ${info.connectionType}');
        }
      });
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  void _testSimulateConnection() {
    try {
      _addLog('━━━ اختبار: محاكاة استعادة الاتصال ━━━');

      ref.read(connectivitySimulatorProvider.notifier).simulateConnection();
      _addLog('🟢 تم محاكاة: استعادة الاتصال');

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          final info = ref.read(connectivityInfoProvider);
          _addLog('📊 الحالة الحالية:');
          _addLog('   • متصل: ${info.isOnline ? '✅' : '❌'}');
          _addLog('   • نوع الاتصال: ${info.connectionType}');
        }
      });
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testScenario1() async {
    try {
      _addLog('━━━ سيناريو 1: تحول من متصل إلى منقطع ━━━');

      // الحالة الأولية
      _addLog('1️⃣ الحالة الأولية:');
      final initialInfo = ref.read(connectivityInfoProvider);
      _addLog('   • متصل: ${initialInfo.isOnline ? '✅' : '❌'}');

      // محاكاة القطع
      _addLog('2️⃣ محاكاة: قطع الاتصال...');
      ref.read(connectivitySimulatorProvider.notifier).simulateDisconnection();
      await Future.delayed(const Duration(seconds: 1));

      // التحقق من الحالة
      _addLog('3️⃣ الحالة بعد القطع:');
      final disconnectedInfo = ref.read(connectivityInfoProvider);
      _addLog('   • متصل: ${disconnectedInfo.isOnline ? '✅' : '❌'}');

      // محاكاة الاستعادة
      _addLog('4️⃣ محاكاة: استعادة الاتصال...');
      ref.read(connectivitySimulatorProvider.notifier).simulateConnection();
      await Future.delayed(const Duration(seconds: 1));

      // التحقق من الحالة النهائية
      _addLog('5️⃣ الحالة بعد الاستعادة:');
      final finalInfo = ref.read(connectivityInfoProvider);
      _addLog('   • متصل: ${finalInfo.isOnline ? '✅' : '❌'}');

      _addLog('✅ اكتمل السيناريو بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  Future<void> _testScenario2() async {
    try {
      _addLog('━━━ سيناريو 2: تتبع محاولات الإعادة ━━━');

      _addLog('1️⃣ بدء الاختبار...');

      for (int i = 0; i < 3; i++) {
        _addLog('${i + 1}️⃣ محاولة الاتصال #${i + 1}...');
        final info = ref.read(connectivityInfoProvider);
        _addLog('   • عدد المحاولات: ${info.retryCount}');
        await Future.delayed(const Duration(seconds: 1));
      }

      _addLog('✅ اكتمل السيناريو بنجاح');
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  void _stopSimulation() {
    try {
      _addLog('━━━ إيقاف المحاكاة ━━━');
      ref.read(connectivitySimulatorProvider.notifier).stopSimulation();
      _addLog('✅ تم إيقاف المحاكاة');

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          final info = ref.read(connectivityInfoProvider);
          _addLog('📊 الحالة الحالية:');
          _addLog('   • متصل: ${info.isOnline ? '✅' : '❌'}');
        }
      });
    } catch (e) {
      _addLog('❌ خطأ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار الاتصال بالانترنت'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // الحالة الحالية
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Consumer(
              builder: (context, ref, child) {
                final info = ref.watch(connectivityInfoProvider);
                final statusColor = info.isOnline ? Colors.green : Colors.red;
                final statusText = info.isOnline ? 'متصل ✅' : 'منقطع ❌';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الحالة الحالية',
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
                      'النوع: ${info.connectionType}',
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
                border: Border.all(color: Colors.cyan),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _testLog,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: Colors.cyan,
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
                    label: '📊 الحالة الحالية',
                    onPressed: _testCurrentStatus,
                    color: Colors.blue,
                  ),
                  _testButton(
                    label: '📡 الاستماع',
                    onPressed: _testStreamListener,
                    color: Colors.green,
                  ),
                  _testButton(
                    label: '🔴 محاكاة قطع',
                    onPressed: _testSimulateDisconnection,
                    color: Colors.red,
                  ),
                  _testButton(
                    label: '🟢 محاكاة اتصال',
                    onPressed: _testSimulateConnection,
                    color: Colors.green,
                  ),
                  _testButton(
                    label: '1️⃣ سيناريو 1',
                    onPressed: _testScenario1,
                    color: Colors.purple,
                  ),
                  _testButton(
                    label: '2️⃣ سيناريو 2',
                    onPressed: _testScenario2,
                    color: Colors.orange,
                  ),
                  _testButton(
                    label: '⏹️ إيقاف',
                    onPressed: _stopSimulation,
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
