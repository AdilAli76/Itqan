/// حالة الاتصال بالانترنت
enum ConnectivityStatus {
  /// متصل بالانترنت
  connected,

  /// منقطع عن الانترنت
  disconnected,

  /// في انتظار التحقق
  loading,
}

/// معلومات تفصيلية عن الاتصال
class ConnectivityInfo {
  const ConnectivityInfo({
    required this.status,
    required this.isOnline,
    required this.connectionType,
    this.lastCheckedAt,
    this.retryCount = 0,
  });

  /// حالة الاتصال الحالية
  final ConnectivityStatus status;

  /// هل النظام متصل بالانترنت؟
  final bool isOnline;

  /// نوع الاتصال (WiFi, Mobile, None)
  final String connectionType;

  /// آخر وقت تم فيه التحقق من الاتصال
  final DateTime? lastCheckedAt;

  /// عدد محاولات إعادة الاتصال
  final int retryCount;

  /// نسخة من حالة الاتصال بقيم مختلفة
  ConnectivityInfo copyWith({
    ConnectivityStatus? status,
    bool? isOnline,
    String? connectionType,
    DateTime? lastCheckedAt,
    int? retryCount,
  }) {
    return ConnectivityInfo(
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      connectionType: connectionType ?? this.connectionType,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  String toString() => 'ConnectivityInfo('
      'status: $status, '
      'isOnline: $isOnline, '
      'type: $connectionType, '
      'retries: $retryCount'
      ')';
}
