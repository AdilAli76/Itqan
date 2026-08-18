import 'package:flutter/material.dart';

/// حركات دقيقة (Micro-interactions) موحّدة للنظام.
///
/// القاعدة المتّبعة هنا: الحركة تخدم الفهم أو لا توجد. كل حركة في هذا الملف
/// تجيب عن سؤال يطرحه المستخدم ضمنياً — «هل استجاب النقر؟»، «من أين جاء هذا
/// المحتوى؟»، «أي صف أنا واقف عليه؟». الحركة الزخرفية (ارتداد، دوران،
/// انزلاق طويل) مستبعدة عمداً: في شاشة يستعملها المحاسب ثماني ساعات يومياً
/// تتحوّل المتعة البصرية إلى تأخير متكرّر يُشعِر بالبطء.
///
/// المدد كلها ضمن 120–260 مللي ثانية: أقلّ من ذلك لا يُدرَك كحركة، وأكثر منه
/// يُدرَك كانتظار.

/// مدد موحّدة — أي حركة جديدة تستعمل إحداها بدل رقم مخترَع.
class AppMotion {
  /// استجابة فورية للمس/التحويم: تغيّر لون أو ظل.
  static const fast = Duration(milliseconds: 120);

  /// انتقال عنصر داخل الشاشة.
  static const normal = Duration(milliseconds: 180);

  /// دخول محتوى الشاشة كاملاً.
  static const slow = Duration(milliseconds: 260);

  /// منحنى الخروج القياسي — سريع في البداية وهادئ في النهاية، وهو ما يجعل
  /// الحركة تبدو «واثقة» لا متثاقلة.
  static const curve = Curves.easeOutCubic;
}

/// ظهور تدريجي مع انزلاق بسيط لأعلى — يُشغَّل مرّة واحدة عند أول بناء ولا
/// يُعاد مع كل setState.
///
/// هذا التمييز جوهري: لو كان الظهور مربوطاً بدالة build لأعادت كل عملية
/// بحث أو تصفية تشغيل الحركة، فيرمش الجدول كلّما كتب المستخدم حرفاً — وهي
/// أسوأ من غياب الحركة أصلاً.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
  });

  final Widget child;

  /// تأخير البدء — يُستعمل لتتابع العناصر (stagger) في الشبكات والقوائم.
  final Duration delay;

  /// مسافة الانزلاق بالنقاط. صغيرة عمداً: الانزلاق الطويل يلفت الانتباه
  /// إلى الحركة نفسها بدل المحتوى.
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.slow);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.curve);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// رفع بطاقة عند التحويم — يجعل البطاقة القابلة للنقر تُعلن عن نفسها قبل
/// النقر، بدل أن يكتشف المستخدم قابليتها بالتجربة.
///
/// على اللمس لا يوجد تحويم أصلاً، فلا يكلّف شيئاً هناك.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.onTap, this.enabled = true});

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          transform: Matrix4.translationValues(0, _hovering ? -2 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovering ? 0.08 : 0.0),
                blurRadius: _hovering ? 16 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// يوزّع تأخيراً متتابعاً على عناصر قائمة/شبكة.
///
/// السقف عند [maxIndex] مقصود: لو تتابعت مئة صف بفاصل 40 مللي لانتظر آخر صف
/// أربع ثوانٍ كاملة. بعد العنصر الثامن تدخل البقية معاً — العين لا تميّز
/// التتابع بعد ذلك على أي حال.
Duration staggerDelay(int index, {int maxIndex = 8, int stepMs = 40}) {
  final capped = index > maxIndex ? maxIndex : index;
  return Duration(milliseconds: capped * stepMs);
}
