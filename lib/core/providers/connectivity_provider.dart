import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../connectivity/connectivity_service.dart';
import '../connectivity/connectivity_state.dart';

/// Singleton instance من ConnectivityService
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// Stream provider للاستماع لتغييرات الاتصال
final connectivityStreamProvider = StreamProvider<ConnectivityInfo>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.connectivityStream;
});

/// Provider للحصول على حالة الاتصال الحالية
final isOnlineProvider = Provider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.isOnline;
});

/// Provider للحصول على معلومات الاتصال الكاملة
final connectivityInfoProvider = Provider<ConnectivityInfo>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.currentInfo;
});

/// Provider لكشف الاتصال
final isConnectedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(connectivityServiceProvider);
  // انتظر أول تحديث
  await Future.delayed(const Duration(milliseconds: 100));
  return service.isOnline;
});

/// Provider لمحاكاة الاتصال/القطع (للاختبار)
final connectivitySimulatorProvider = StateNotifierProvider<
    ConnectivitySimulator,
    ConnectivitySimulatorState>((ref) {
  return ConnectivitySimulator(ref.watch(connectivityServiceProvider));
});

/// محاكي الاتصال للاختبار
class ConnectivitySimulatorState {
  const ConnectivitySimulatorState({
    required this.isSimulating,
    required this.simulatedStatus,
  });

  final bool isSimulating;
  final ConnectivityStatus simulatedStatus;

  ConnectivitySimulatorState copyWith({
    bool? isSimulating,
    ConnectivityStatus? simulatedStatus,
  }) {
    return ConnectivitySimulatorState(
      isSimulating: isSimulating ?? this.isSimulating,
      simulatedStatus: simulatedStatus ?? this.simulatedStatus,
    );
  }
}

/// State notifier لمحاكي الاتصال
class ConnectivitySimulator extends StateNotifier<ConnectivitySimulatorState> {
  ConnectivitySimulator(this._service)
      : super(
          const ConnectivitySimulatorState(
            isSimulating: false,
            simulatedStatus: ConnectivityStatus.connected,
          ),
        );

  final ConnectivityService _service;

  /// محاكاة فقدان الاتصال
  void simulateDisconnection() {
    _service.simulateDisconnection();
    state = state.copyWith(
      isSimulating: true,
      simulatedStatus: ConnectivityStatus.disconnected,
    );
  }

  /// محاكاة استعادة الاتصال
  void simulateConnection() {
    _service.simulateConnection();
    state = state.copyWith(
      isSimulating: true,
      simulatedStatus: ConnectivityStatus.connected,
    );
  }

  /// إنهاء المحاكاة
  void stopSimulation() {
    _service.reset();
    state = state.copyWith(isSimulating: false);
  }
}
