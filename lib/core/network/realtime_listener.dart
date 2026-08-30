import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/data/dashboard_providers.dart';
import '../../features/inventory/data/inventory_providers.dart';
import '../../features/invoices/data/invoices_providers.dart';
import '../../features/notifications/data/notifications_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'offline_queue.dart';
import 'realtime_service.dart';

/// يفتح الاتصال اللحظي ويترجم أحداثه إلى تحديث فعلي في الشاشات.
///
/// يُركَّب مرّة واحدة داخل AppShell — أي فوق كل التبويبات وتحت جذر التطبيق:
/// فوقها لأن التحديث يجب أن يصل شاشةً مفتوحة في تبويب خلفي أيضاً، وتحته لأن
/// الاتصال بلا توكن بلا معنى (الـ Hub محمي، وشاشة الدخول خارج الغلاف).
///
/// إبطال المزوّد (invalidate) بدل تعديل الحالة يدوياً: الخادم هو مصدر
/// الحقيقة، والحدث إشارة «تغيّر شيء» لا حمولة كاملة يُبنى عليها. حقن حمولة
/// الحدث مباشرة في القائمة كان سيُنتج صفاً بشكل مختلف عن الصفوف القادمة من
/// الـ API عند أول تحديث تالٍ.
class RealtimeListener extends ConsumerStatefulWidget {
  const RealtimeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RealtimeListener> createState() => _RealtimeListenerState();
}

class _RealtimeListenerState extends ConsumerState<RealtimeListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(realtimeServiceProvider).connect();
    });

    // تفريغ الطابور عند الإقلاع أيضاً، لا عند انتقال الحالة وحده.
    //
    // **العطب الذي يصلحه:** المزامنة كانت تقع فقط عند الانتقال من «غير
    // متصل» إلى «متصل». والحالة الغالبة أن يُفتح التطبيق **وهو متصل
    // أصلاً** — فلا انتقال يقع ولا تُستدعى المزامنة أبداً، فيبقى الطابور
    // المستعاد من التخزين معروضاً إلى الأبد رغم وجود الإنترنت. وهو ما
    // يظهر للمستخدم كعدّاد «يحتاج مزامنة» لا يتحدّث مهما فعل.
    //
    // ويُعاد تحميل الطابور أولاً: التوكن قد يكون قُرئ بعد إنشاء المزوّد،
    // ومنظمة الطابور تُعرَف منه.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(offlineQueueProvider.notifier).reloadForCurrentUser();
      if (mounted) await _drainQueue();
    });
  }

  /// ما الذي يبطُل عند كل حدث. الإبطال ضيّق عمداً: إبطال كل شيء عند أي حدث
  /// يعني أن فاتورة واحدة تُعيد تحميل الجرد والتقارير والعملاء بلا سبب —
  /// وهذا يحوّل ميزة اللحظية إلى ضغط دائم على الخادم.
  void _apply(RealtimeEvent event) {
    switch (event.name) {
      case 'LowStockAlert':
        ref.invalidate(productsInventoryProvider);
        ref.invalidate(notificationsProvider);
        ref.invalidate(dashboardInventoryProvider);
        _toast(
          'نقص مخزون: ${event.payload['Name'] ?? event.payload['name'] ?? 'صنف'}'
          ' — المتبقي ${event.payload['Quantity'] ?? event.payload['quantity'] ?? '؟'}',
          AppColors.warning,
          Icons.warning_amber_outlined,
        );
      case 'InvoiceCreated':
        ref.invalidate(invoicesProvider);
        ref.invalidate(dashboardSalesProvider);
      case 'NotificationCreated':
        ref.invalidate(notificationsProvider);
    }
  }

  /// تنبيه غير معطِّل: شريط سفلي يختفي وحده، لا حوار يوقف الكاشير في منتصف
  /// فاتورة. الحدث اللحظي لا يجوز أن يقاطع عملاً جارياً.
  void _toast(String message, Color color, IconData icon) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: AppColors.surface,
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: AppTextStyles.bodyMd(color: AppColors.textPrimary))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      final event = next.valueOrNull;
      if (event != null) _apply(event);
    });

    // عودة الاتصال اللحظي أدقّ إشارة متاحة على عودة الشبكة فعلياً: هي تعني
    // أن مصافحة كاملة مع الخادم نجحت، لا مجرّد وجود واجهة شبكة نشطة كما
    // يخبر فحص الاتصال العادي. عندها يُفرَّغ طابور البيع المؤجَّل.
    ref.listen<AsyncValue<RealtimeStatus>>(realtimeStatusProvider, (previous, next) {
      final was = previous?.valueOrNull;
      final now = next.valueOrNull;
      if (now == RealtimeStatus.connected && was != RealtimeStatus.connected) {
        _drainQueue();
      }
    });

    return widget.child;
  }


  Future<void> _drainQueue() async {
    final queue = ref.read(offlineQueueProvider);
    if (queue.isEmpty) return;

    final sent = await ref.read(offlineQueueProvider.notifier).sync();
    if (sent == 0 || !mounted) return;

    // القوائم المتأثّرة تُبطَل بعد المزامنة لا قبلها: الفواتير المُرسَلة
    // خصمت مخزوناً وأنشأت سجلات لم تكن الشاشات تعرف بها.
    ref.invalidate(invoicesProvider);
    ref.invalidate(productsInventoryProvider);
    ref.invalidate(dashboardSalesProvider);

    _toast('عاد الاتصال — أُرسلت $sent عملية بيع مؤجَّلة',
        AppColors.success, Icons.cloud_done_outlined);
  }
}

/// مؤشّر حالة الاتصال اللحظي في الشريط العلوي.
///
/// يظهر فقط حين ينقطع الاتصال أو يُعاد: النقطة الخضراء الدائمة تصبح جزءاً من
/// الخلفية البصرية خلال يوم واحد فيتوقّف المستخدم عن رؤيتها أصلاً، بينما
/// التحذير عند الانقطاع هو المعلومة التي تُغيّر سلوكه فعلاً (يحدّث يدوياً).
class RealtimeIndicator extends ConsumerWidget {
  const RealtimeIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeStatusProvider).valueOrNull;
    if (status == null || status == RealtimeStatus.connected) {
      return const SizedBox.shrink();
    }

    final connecting = status == RealtimeStatus.connecting;

    // أيقونةٌ وحدها لا شارةٌ بنصّ.
    //
    // <para><b>لماذا تغيّرت:</b> الشارة النصّية تظهر ما دام الاتصال اللحظي
    // منقطعاً — وقد يبقى كذلك ساعات. فتصير تحذيراً دائماً لا يُغيّر سلوكاً،
    // وهو تعريف الضجيج: ما يُرى دائماً يُهمَل دائماً. وعلى الهاتف كانت
    // تسرق عرض شريط العنوان فيُقصّ اسم الشاشة («الخصم م...»).</para>
    //
    // <para>والمعلومة تبقى كاملة عند النقر — لمن أرادها حين يريدها.</para>
    return Tooltip(
      message: connecting
          ? 'جارٍ استعادة الاتصال اللحظي…'
          : 'الاتصال اللحظي منقطع — البيانات قد لا تكون محدَّثة، استخدم زر التحديث',
      child: Semantics(
        button: true,
        label: connecting ? 'جارٍ استعادة الاتصال اللحظي' : 'الاتصال اللحظي منقطع',
        child: InkWell(
          onTap: () => _explain(context, connecting),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              connecting ? Icons.sync : Icons.cloud_off_outlined,
              size: 18,
              color: connecting ? AppColors.info : AppColors.warning,
            ),
          ),
        ),
      ),
    );
  }

  void _explain(BuildContext context, bool connecting) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(connecting
          ? 'جارٍ استعادة الاتصال اللحظي…'
          : 'الاتصال اللحظي منقطع — البيانات قد لا تكون محدَّثة. '
              'البيع يعمل كالمعتاد، واستخدم زرّ التحديث لأحدث الأرقام.'),
      duration: const Duration(seconds: 5),
    ));
  }
}

/// عدّاد عمليات البيع المؤجَّلة.
///
/// ظاهر دائماً ما دام الطابور غير فارغ، لا لحظة واحدة عند الحفظ: الكاشير
/// الذي باع عشر فواتير أثناء انقطاع يحتاج أن يرى أنها ما زالت غير مرسَلة
/// قبل أن يُغلق المحل ويطفئ الجهاز. رسالة عابرة عند كل عملية كانت ستُنسى.
class OfflineQueueIndicator extends ConsumerWidget {
  const OfflineQueueIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(offlineQueueProvider);
    if (queue.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: 'عمليات بيع محفوظة على الجهاز لم تصل الخادم بعد. '
          'ستُرسَل تلقائياً عند عودة الاتصال — لا تُطفئ الجهاز قبل ذلك.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              queue.syncing ? Icons.sync : Icons.cloud_upload_outlined,
              size: 14,
              color: AppColors.warning,
            ),
            const SizedBox(width: 6),
            Text(
              queue.syncing
                  ? 'جارٍ الإرسال…'
                  : '${queue.count} عملية بانتظار الإرسال',
              style: AppTextStyles.labelMd(color: AppColors.warning),
            ),
          ],
        ),
      ),
    );
  }
}
