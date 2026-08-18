import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_netcore/signalr_client.dart';

import 'api_client.dart';

/// الاتصال اللحظي بـ SignalR — الطرف المقابل لـ NotificationsHub في الخادم.
///
/// الخادم كان يبثّ فعلاً (راجع InvoicesController: SendAsync("LowStockAlert"))
/// وحزمة signalr_netcore كانت مُعلَنة في pubspec، لكن لا شيء في التطبيق كان
/// يتّصل بالـ Hub — أي أن البثّ كان يذهب إلى لا أحد. هذا الملف يصل الطرفين.
///
/// لماذا يهمّ عملياً: بدون ذلك لا يعرف الكاشير أن صنفاً نفد إلا إذا حدّث
/// الشاشة يدوياً، فيبيع ما ليس موجوداً. ومع فرعين يعملان على نفس المخزون
/// تصبح المشكلة يومية لا نادرة.

/// حدث وارد من الخادم.
class RealtimeEvent {
  const RealtimeEvent(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

/// حالة الاتصال — تُعرَض للمستخدم لأن «لحظي» بلا مؤشّر ثقة لا يُصدَّق:
/// المستخدم الذي لا يرى مؤشّراً سيحدّث الشاشة يدوياً على أي حال.
enum RealtimeStatus { disconnected, connecting, connected }

class RealtimeService {
  RealtimeService();

  HubConnection? _connection;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _status = StreamController<RealtimeStatus>.broadcast();
  RealtimeStatus _current = RealtimeStatus.disconnected;

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<RealtimeStatus> get status => _status.stream;
  RealtimeStatus get currentStatus => _current;

  void _setStatus(RealtimeStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// عنوان الـ Hub مشتقّ من baseUrl نفسه: الأخير ينتهي بـ /api بينما الـ Hub
  /// مُسجَّل على الجذر (app.MapHub("/hubs/notifications")). اشتقاقه هنا يمنع
  /// وجود عنوانين منفصلين ينسى أحدهما عند تغيير بيئة النشر.
  static String get hubUrl {
    const base = ApiClient.baseUrl;
    final root = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
    return '$root/hubs/notifications';
  }

  Future<void> connect() async {
    if (_connection != null) return;
    final token = await ApiClient.instance.readToken();
    // لا اتصال قبل تسجيل الدخول — الـ Hub محمي بـ [Authorize]، ومحاولة
    // الاتصال بلا توكن تُنتج دورة فشل/إعادة محاولة بلا طائل.
    if (token == null || token.isEmpty) return;

    _setStatus(RealtimeStatus.connecting);

    final connection = HubConnectionBuilder()
        .withUrl(
          hubUrl,
          options: HttpConnectionOptions(accessTokenFactory: () async => token),
        )
        .withAutomaticReconnect(retryDelays: [0, 2000, 5000, 10000, 30000])
        .build();

    connection.onclose(({error}) => _setStatus(RealtimeStatus.disconnected));
    connection.onreconnecting(({error}) => _setStatus(RealtimeStatus.connecting));
    connection.onreconnected(({connectionId}) => _setStatus(RealtimeStatus.connected));

    // الأحداث التي يبثّها الخادم حالياً. إضافة حدث جديد = سطر واحد هنا،
    // وحالة مقابلة في RealtimeListener._apply تحدّد ما الذي يُعاد تحميله.
    for (final name in const ['LowStockAlert', 'NotificationCreated', 'InvoiceCreated']) {
      connection.on(name, (args) {
        final first = (args != null && args.isNotEmpty) ? args.first : null;
        _events.add(RealtimeEvent(
          name,
          first is Map ? Map<String, dynamic>.from(first) : const {},
        ));
      });
    }

    try {
      await connection.start();
      _connection = connection;
      _setStatus(RealtimeStatus.connected);
    } catch (_) {
      // فشل الاتصال لا يجوز أن يُعطّل التطبيق: النظام يبقى صالحاً بالكامل
      // بالتحديث اليدوي، واللحظية تحسين فوقه لا شرط لعمله.
      _setStatus(RealtimeStatus.disconnected);
      _connection = null;
    }
  }

  Future<void> disconnect() async {
    await _connection?.stop();
    _connection = null;
    _setStatus(RealtimeStatus.disconnected);
  }

  void dispose() {
    _connection?.stop();
    _events.close();
    _status.close();
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  ref.onDispose(service.dispose);
  return service;
});

/// حالة الاتصال للعرض في الشريط العلوي.
final realtimeStatusProvider = StreamProvider<RealtimeStatus>((ref) {
  final service = ref.watch(realtimeServiceProvider);
  return service.status;
});

/// تيّار الأحداث الخام — لمن يريد الاستماع لحدث بعينه (نافذة منبثقة مثلاً).
final realtimeEventsProvider = StreamProvider<RealtimeEvent>((ref) {
  final service = ref.watch(realtimeServiceProvider);
  return service.events;
});
