import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import '../auth/current_user.dart';

/// طابور البيع دون اتصال — يُبقي نقطة البيع عاملة أثناء انقطاع الشبكة.
///
/// ## ما يُسمح به دون اتصال، ولماذا هذا الحدّ تحديداً
///
/// **البيع النقدي فقط.** الدفع من محفظة العميل ممنوع دون اتصال بلا استثناء،
/// لأنه يتطلّب أمرين لا يمكن تحقيقهما محلياً: التحقّق من الرصيد، والتحقّق من
/// الرقم السري عبر عدّاد المحاولات المخزَّن على الخادم. السماح به كان سيعني
/// إما صرفاً من رصيد لا يكفي، أو قبول رقم سري بلا حدّ لمحاولات التخمين —
/// وكلاهما ثغرة مالية لا «تنازل عن راحة».
///
/// **لا أرقام فواتير محلية.** الرقم يولّده الخادم عند المزامنة. توليده على
/// الجهاز يعني تصادماً محتّماً بين جهازين يعملان دون اتصال في نفس المتجر —
/// ورقم فاتورة مكرَّر خطأ محاسبي لا يُصلَح لاحقاً بسهولة.
///
/// **مفتاح لكل عملية.** يُولَّد مرّة عند البيع ويُعاد إرساله مع كل محاولة.
/// انقطاع الشبكة بعد وصول الطلب وقبل وصول الرد حالة شائعة جداً، وبدونه تُنشأ
/// الفاتورة مرّتين ويُخصَم المخزون مرّتين.
///
/// ## ما يبقى مقبولاً بوعي
///
/// قد يُباع صنف نفد فعلياً في الفرع أثناء الانقطاع، فيُسجَّل عجز عند
/// المزامنة. هذا سلوك أي نظام بيع دون اتصال، والبديل — رفض البيع — يوقف
/// المتجر وهو ما جاءت الميزة أصلاً لمنعه.
class OfflineSale {
  const OfflineSale({
    required this.clientRequestId,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  factory OfflineSale.fromJson(Map<String, dynamic> json) => OfflineSale(
        clientRequestId: json['clientRequestId'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['lastError'] as String?,
      );

  final String clientRequestId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'clientRequestId': clientRequestId,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        if (lastError != null) 'lastError': lastError,
      };

  OfflineSale copyWith({int? attempts, String? lastError}) => OfflineSale(
        clientRequestId: clientRequestId,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  double get total {
    final lines = payload['lines'] as List? ?? const [];
    return lines.fold<double>(0, (sum, l) {
      final m = l as Map;
      final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
      final price = (m['unitPrice'] as num?)?.toDouble() ?? 0;
      return sum + qty * price;
    });
  }
}

@immutable
class QueueState {
  const QueueState({this.pending = const [], this.syncing = false});

  final List<OfflineSale> pending;
  final bool syncing;

  bool get isEmpty => pending.isEmpty;
  int get count => pending.length;
}

class OfflineQueueNotifier extends StateNotifier<QueueState> {
  OfflineQueueNotifier() : super(const QueueState()) {
    _restore();
  }

  /// مفتاح الطابور — **بمعرّف المنظمة**.
  ///
  /// <para><b>العطب الذي يصلحه:</b> كان مفتاحاً عالمياً واحداً
  /// (<c>kinetic_offline_sales</c>) لكل من يستعمل الجهاز. فمنظمةٌ باعت بلا
  /// إنترنت تترك طابورها، ثم يدخل مستخدم منظمة أخرى على الجهاز نفسه فيرى
  /// **عدّاد المزامنة قائماً** لعمليات ليست له. وأسوأ من العرض: المزامنة
  /// تحاول إرسالها بتوكنه هو، فيرفضها الخادم (معرّفات أصناف وفروع من منظمة
  /// أخرى) — فتبقى معلّقة بلا تفسير.</para>
  ///
  /// <para>ولا يُمحى المفتاح القديم: قد يحمل مبيعات حقيقية لم تصل بعد.
  /// يُهاجَر مرّةً إلى مفتاح المنظمة الحالية — راجع [_restore].</para>
  static const _legacyKey = 'kinetic_offline_sales';
  static String _keyFor(String? organizationId) =>
      organizationId == null || organizationId.isEmpty
          ? _legacyKey
          : 'kinetic_offline_sales_$organizationId';

  static const _storage = FlutterSecureStorage();

  /// المنظمة التي يخصّها الطابور المُحمَّل الآن.
  String? _organizationId;

  /// سقف الطابور. انقطاع يتجاوز مئتَي فاتورة يعني عطلاً ممتداً يحتاج تدخّلاً
  /// لا تكديساً صامتاً — وامتلاء الطابور يجب أن يُبلَّغ به لا أن يُبتلع.
  static const maxQueued = 200;

  Future<void> _restore() async {
    try {
      final claims = await readJwtClaims();
      _organizationId = claims?['organization_id'] as String?;

      // بلا توكن لا طابور يُعرَض: عدّادٌ يظهر قبل الدخول لا يخصّ أحداً بعد.
      if (_organizationId == null) {
        state = const QueueState();
        return;
      }

      final key = _keyFor(_organizationId);
      var raw = await _storage.read(key: key);

      // هجرة الطابور القديم مرّةً واحدة إلى مفتاح هذه المنظمة.
      //
      // **ولمن يُهاجَر؟** لأول منظمة تفتح التطبيق بعد الترقية. وهذا ليس
      // دقيقاً بالضرورة — قد يكون الطابور لمنظمة أخرى استعملت الجهاز — لكنه
      // أفضل من الخيارين الآخرين: محوُه يُضيّع مبيعات حقيقية لم تصل، وتركُه
      // يُبقي العطب الأصلي قائماً لكل من يدخل. والخادم هو الحكم أخيراً:
      // فاتورةٌ من منظمة أخرى يرفضها بـ400 فتسقط من الطابور.
      if (raw == null || raw.isEmpty) {
        final legacy = await _storage.read(key: _legacyKey);
        if (legacy != null && legacy.isNotEmpty) {
          raw = legacy;
          await _storage.write(key: key, value: legacy);
          await _storage.delete(key: _legacyKey);
        }
      }

      if (raw == null || raw.isEmpty) {
        state = const QueueState();
        return;
      }
      final list = (json.decode(raw) as List)
          .map((e) => OfflineSale.fromJson(e as Map<String, dynamic>))
          .toList();
      state = QueueState(pending: list);
    } catch (_) {
      // ملف تالف لا يجوز أن يمنع إقلاع نقطة البيع؛ يبدأ الطابور فارغاً.
    }
  }

  /// يُعيد تحميل الطابور لمنظمة المستخدم الحالي — يُستدعى بعد الدخول.
  ///
  /// بلا هذا يبقى الطابور المُحمَّل وقت الإقلاع (أو الفارغ) معروضاً حتى
  /// إعادة تشغيل التطبيق، فيرى الداخلُ الجديد عدّاد من قبله.
  Future<void> reloadForCurrentUser() => _restore();

  Future<void> _persist(List<OfflineSale> sales) async {
    state = QueueState(pending: sales, syncing: state.syncing);
    try {
      await _storage.write(
          key: _keyFor(_organizationId), value: json.encode(sales.map((s) => s.toJson()).toList()));
    } catch (_) {
      // فشل الكتابة يعني ضياع الطابور عند إعادة التشغيل — نتركه في الذاكرة
      // على الأقل ليُزامَن في هذه الجلسة.
    }
  }

  /// يولّد مفتاحاً فريداً للعملية. الوقت وحده لا يكفي: جهازان يبيعان في
  /// المللي ثانية نفسها ممكن، فيُضاف جزء عشوائي.
  static String newRequestId() {
    final rnd = Random.secure();
    final suffix = List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  /// يضيف عملية بيع إلى الطابور. يُعيد false إذا امتلأ.
  Future<bool> enqueue(Map<String, dynamic> payload) async {
    if (state.pending.length >= maxQueued) return false;

    final sale = OfflineSale(
      clientRequestId: payload['clientRequestId'] as String,
      payload: payload,
      createdAt: DateTime.now(),
    );
    await _persist([...state.pending, sale]);
    return true;
  }

  /// يحاول إرسال ما في الطابور بالترتيب.
  ///
  /// الترتيب مهم لا تجميلي: الفواتير تُرقَّم عند وصولها، فإرسالها بترتيب
  /// وقوعها يُبقي تسلسل الأرقام موافقاً لتسلسل البيع الفعلي.
  Future<int> sync() async {
    if (state.syncing || state.pending.isEmpty) return 0;
    state = QueueState(pending: state.pending, syncing: true);

    final remaining = <OfflineSale>[];
    var sent = 0;

    for (final sale in state.pending) {
      try {
        await ApiClient.instance.dio.post('/invoices', data: sale.payload);
        sent++;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        // خطأ 4xx يعني رفضاً دائماً (صنف محذوف، فرع مغلق) — إعادة المحاولة
        // إلى الأبد لن تُصلحه، وإبقاؤه يعطّل مزامنة ما بعده. يُسقَط من
        // الطابور بعد ثلاث محاولات ويبقى أثره في lastError للمراجعة.
        final permanent = status != null && status >= 400 && status < 500 && status != 429;
        final attempts = sale.attempts + 1;
        if (permanent && attempts >= 3) continue;
        remaining.add(sale.copyWith(attempts: attempts, lastError: _message(e)));
      } catch (e) {
        remaining.add(sale.copyWith(attempts: sale.attempts + 1, lastError: e.toString()));
      }
    }

    state = QueueState(pending: remaining, syncing: false);
    await _persist(remaining);
    return sent;
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    return e.message ?? 'تعذّر الإرسال';
  }

  Future<void> clear() => _persist(const []);
}

final offlineQueueProvider =
    StateNotifierProvider<OfflineQueueNotifier, QueueState>((ref) => OfflineQueueNotifier());
