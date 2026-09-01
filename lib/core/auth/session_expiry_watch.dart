import 'dart:async';

import 'package:flutter/material.dart';

import '../network/api_client.dart';
import 'current_user.dart';

/// إنذارٌ قبل انتهاء الجلسة، وزرٌّ يمدّها.
///
/// <para><b>العطب الذي يصلحه:</b> الجلسة ثماني ساعات ثابتة بلا تجديد، فكان
/// أوّل نداء بعدها يردّ 401 فيُمحى التوكن ويُقذف المستخدم إلى شاشة الدخول
/// **بلا إنذار** — في منتصف فاتورة أحياناً. والاعتراض في [ApiClient] يمنع
/// الأسوأ (شاشةٌ عالقة تقول «تعذّر التحميل» بلا مخرج) ولا يُنذر.</para>
///
/// <para><b>ولا تمديد صامت بالنشاط:</b> جهاز كاشير في محلّ يجب أن تنتهي
/// جلسته فعلاً في آخر الوردية. والتمديد فعلٌ يُتخذ لا حقٌّ يُكتسب بالحركة —
/// فمن يمدّ يعرف أنه مدّ، ومن يترك الجهاز يخرج.</para>
///
/// <para><b>والمدّة تُقرأ من <c>exp</c> في التوكن نفسه لا من رقمٍ في
/// الواجهة:</b> رقمٌ مكتوب هنا يفترق عن <c>SessionLifetime</c> في الخادم
/// أوّل مرّة يُغيَّر أحدهما، فيُنذر قبل ساعة أو بعد الانتهاء — وكلاهما أسوأ
/// من ألّا يُنذر.</para>
class SessionExpiryWatch {
  SessionExpiryWatch({required this.onWarn});

  /// كم قبل الانتهاء يُنذَر.
  ///
  /// خمس دقائق: تكفي لإنهاء فاتورةٍ في اليد، ولا تطول فتُنسى النافذة
  /// مفتوحةً حتى تنتهي الجلسة تحتها.
  static const warnBefore = Duration(minutes: 5);

  /// يُستدعى مرّةً عند بلوغ لحظة الإنذار.
  final VoidCallback onWarn;

  Timer? _timer;

  /// يقرأ انتهاء التوكن الحالي ويجدول الإنذار.
  ///
  /// يُستدعى عند الإقلاع وبعد كل تجديد. واستدعاؤه مرّتين لا يضرّ: المؤقّت
  /// السابق يُلغى أوّلاً.
  Future<void> schedule() async {
    _timer?.cancel();
    _timer = null;

    final expiry = await _expiry();
    if (expiry == null) return;

    final until = expiry.difference(DateTime.now().toUtc()) - warnBefore;

    // انتهت أو أوشكت: لا مؤقّتَ بمدّةٍ سالبة (Timer ينطلق فوراً عندها،
    // فيومض الإنذار في وجه من فتح التطبيق للتوّ بتوكنٍ ميت أصلاً — و
    // اعتراضُ 401 هو من يتولّى تلك الحالة، لا هذا).
    if (until.isNegative) return;

    _timer = Timer(until, onWarn);
  }

  /// يمدّ الجلسة ويعيد الجدولة على التوكن الجديد.
  ///
  /// <para>يُعيد الخادم قراءة الحساب من القاعدة قبل الإصدار، فحسابٌ عُطِّل
  /// أو سُحبت صلاحيته لا يمدّ جلسته — راجع <c>AuthController.Refresh</c>.
  /// </para>
  Future<bool> extend() async {
    try {
      final response = await ApiClient.instance.dio.post('/auth/refresh');
      final token = (response.data as Map)['token'] as String?;
      if (token == null) return false;
      await ApiClient.instance.saveToken(token);
      await schedule();
      return true;
    } catch (_) {
      // فشل التمديد ليس خروجاً: التوكن القديم ما زال صالحاً خمس دقائق،
      // ومحوُه هنا يقطع على المستخدم ما كان يستطيع إنهاءه. واعتراض 401
      // يتولّاه حين ينتهي فعلاً.
      return false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// لحظة انتهاء التوكن الحالي بالتوقيت العالمي.
  static Future<DateTime?> _expiry() async {
    final claims = await readJwtClaims();
    final exp = claims?['exp'];
    if (exp is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  }
}
