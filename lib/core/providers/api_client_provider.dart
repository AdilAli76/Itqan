import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/enhanced_api_client.dart';

/// Singleton instance من Enhanced API Client
final apiClientProvider = Provider<EnhancedApiClient>((ref) {
  return EnhancedApiClient();
});

/// Provider لمعرفة حالة الاتصال بالخادم
final isServerConnectedProvider = FutureProvider<bool>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  return await apiClient.checkConnection();
});

/// Provider للإحصائيات
final apiStatisticsProvider = Provider<ApiStatistics>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getStatistics();
});

/// Provider لآخر وقت مزامنة
final lastServerSyncProvider = Provider<DateTime?>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.lastSync;
});

/// State notifier للتحكم في المزامنة مع الخادم
final serverSyncControllerProvider = StateNotifierProvider<
    ServerSyncController,
    ServerSyncState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ServerSyncController(apiClient);
});

/// حالة المزامنة مع الخادم
class ServerSyncState {
  const ServerSyncState({
    required this.isSyncing,
    required this.lastSyncTime,
    required this.lastResult,
    required this.serverUrl,
  });

  final bool isSyncing;
  final DateTime? lastSyncTime;
  final SyncResult? lastResult;
  final String serverUrl;

  ServerSyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncTime,
    SyncResult? lastResult,
    String? serverUrl,
  }) {
    return ServerSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastResult: lastResult ?? this.lastResult,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }
}

/// State notifier للتحكم في المزامنة مع الخادم
class ServerSyncController extends StateNotifier<ServerSyncState> {
  ServerSyncController(this._apiClient)
      : super(
          const ServerSyncState(
            isSyncing: false,
            lastSyncTime: null,
            lastResult: null,
            serverUrl: 'https://api.example.com',
          ),
        );

  final EnhancedApiClient _apiClient;

  /// فحص الاتصال بالخادم
  Future<bool> checkConnection() async {
    return await _apiClient.checkConnection();
  }

  /// مزامنة العناصر المعلقة
  Future<void> startServerSync() async {
    state = state.copyWith(isSyncing: true);

    try {
      final result = await _apiClient.syncPendingItems();

      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: DateTime.now(),
        lastResult: result,
      );
    } catch (e) {
      state = state.copyWith(isSyncing: false);
      rethrow;
    }
  }

  /// تعيين عنوان الخادم
  void setServerUrl(String url) {
    _apiClient.setServerUrl(url);
    state = state.copyWith(serverUrl: url);
  }

  /// تعيين التوكن
  void setAuthToken(String token) {
    _apiClient.setAuthToken(token);
  }

  /// جلب البيانات من الخادم
  Future<Map<String, dynamic>> fetchData(String endpoint) async {
    return await _apiClient.fetchData(endpoint);
  }

  /// إرسال بيانات للخادم
  Future<Map<String, dynamic>> postData(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    return await _apiClient.postData(endpoint, data);
  }
}
