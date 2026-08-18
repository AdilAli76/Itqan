import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// هياكل التحميل (Skeletons) — بديل دوّار الانتظار في الشاشات التي يُعرف
/// شكل محتواها مسبقاً (جدول، بطاقات إحصاء، نموذج).
///
/// لماذا لا نكتفي بـ CircularProgressIndicator: الدوّار يقول «انتظر» ولا
/// يقول ماذا تنتظر، فتبدو الشاشة فارغة ثم تقفز دفعة واحدة. الهيكل يرسم
/// تخطيط المحتوى القادم فوراً، فيبقى الإطار ثابتاً ولا يحدث ارتجاج تخطيط
/// (layout shift) عند وصول البيانات، ويُقلّل الإحساس بالبطء دون تسريع فعلي.
///
/// الاستخدام: كل الهياكل هنا تُغلَّف تلقائياً بحركة اللمعان، فلا حاجة
/// لإضافة [ShimmerEffect] يدوياً إلا عند بناء هيكل مخصّص من [SkeletonBox].

// ═══════════════════════════════════════════════ حركة اللمعان ════════════

/// يمرّر لمعاناً متحرّكاً فوق كامل الشجرة التي يغلّفها.
///
/// متحكّم واحد لكل هيكل مهما بلغ عدد مستطيلاته — البديل (متحكّم داخل كل
/// مستطيل) يعني عشرين متحكّماً في جدول واحد، وهو هدر ملحوظ على أجهزة
/// نقاط البيع الضعيفة.
class ShimmerEffect extends StatefulWidget {
  const ShimmerEffect({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final direction = Directionality.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // القيمة تنتقل من -1 إلى 2 لا من 0 إلى 1: اللمعان يجب أن يبدأ خارج
        // الحافة وينتهي خارجها، وإلا ظهر ينبثق ويختفي في منتصف المحتوى.
        final slide = -1.0 + _controller.value * 3.0;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [
              AppColors.surfaceAlt,
              AppColors.paper,
              AppColors.surfaceAlt,
            ],
            stops: [
              (slide - 0.3).clamp(0.0, 1.0),
              slide.clamp(0.0, 1.0),
              (slide + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(bounds, textDirection: direction),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// مستطيل رمادي يمثّل نصاً أو عنصراً قادماً. يُستخدم داخل [ShimmerEffect].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ═══════════════════════════════════════════════ هياكل جاهزة ═════════════

/// هيكل جدول مطابق لإطار [AppDataTable] — نفس الحافة ونفس الحشوة ونفس
/// ارتفاع الصف، حتى لا تتزحزح الصفحة لحظة وصول البيانات.
class TableSkeleton extends StatelessWidget {
  const TableSkeleton({super.key, this.rows = 6, this.columns = 5, this.showHeader = true});

  final int rows;
  final int columns;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return _LoadingSemantics(child: _build(context));
  }

  Widget _build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ShimmerEffect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.all(16),
                // عرضان ثابتان (140 + 200) مع الحشوة يتجاوزان عرض الهاتف
                // فيفيض الصف. الهيكل يحاكي AppDataTable الذي يلتفّ عند الضيق
                // (راجع Wrap فيه)، فيجب أن يضيق مثله لا أن ينكسر — وإلا كان
                // هيكل التحميل نفسه أول ما يظهر معطوباً على الشاشة الصغيرة.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final searchWidth =
                        constraints.maxWidth < 420 ? constraints.maxWidth * 0.4 : 200.0;
                    return Row(
                      children: [
                        const Flexible(child: SkeletonBox(width: 140, height: 20)),
                        const Spacer(),
                        SkeletonBox(width: searchWidth, height: 36, radius: 8),
                      ],
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            for (var r = 0; r < rows; r++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    for (var c = 0; c < columns; c++)
                      Expanded(
                        // أعرض قليلاً في العمود الأول (اسم/وصف) وأضيق في
                        // البقية (أرقام وحالات) — التفاوت يجعل الهيكل يشبه
                        // بيانات فعلية بدل أشرطة متطابقة تبدو زخرفة.
                        flex: c == 0 ? 2 : 1,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SkeletonBox(width: c == 0 ? 160 : 72),
                        ),
                      ),
                  ],
                ),
              ),
              if (r < rows - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

/// هيكل صفّ بطاقات الإحصاء في لوحة التحكم.
class StatCardsSkeleton extends StatelessWidget {
  const StatCardsSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _LoadingSemantics(child: _build(context));
  }

  Widget _build(BuildContext context) {
    return ShimmerEffect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // البطاقات تلتفّ بدل أن تفيض على الشاشات الضيقة — نفس سلوك
          // الشبكة الفعلية في لوحة التحكم.
          final perRow = constraints.maxWidth > 900 ? count : (constraints.maxWidth > 520 ? 2 : 1);
          final width = (constraints.maxWidth - (perRow - 1) * 16) / perRow;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (var i = 0; i < count; i++)
                Container(
                  width: width,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 36, height: 36, radius: 8),
                      SizedBox(height: 16),
                      SkeletonBox(width: 110, height: 28),
                      SizedBox(height: 8),
                      SkeletonBox(width: 80),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// هيكل قائمة بسيطة (إشعارات، سجل عمليات، عناصر فاتورة).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.items = 5, this.showAvatar = true});

  final int items;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return _LoadingSemantics(child: _build(context));
  }

  Widget _build(BuildContext context) {
    return ShimmerEffect(
      child: Column(
        children: [
          for (var i = 0; i < items; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  if (showAvatar) ...[
                    const SkeletonBox(width: 40, height: 40, radius: 8),
                    const SizedBox(width: 12),
                  ],
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: double.infinity, height: 14),
                        SizedBox(height: 8),
                        SkeletonBox(width: 180, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// يُعلن الهيكل كحالة انتظار لقارئ الشاشة، ويُخفي مستطيلاته.
///
/// الهيكل حلٌّ بصري بحت: المستطيلات الرمادية لا تعني شيئاً لمن لا يراها،
/// وتركها مكشوفة ينتج ضجيجاً من عُقَد فارغة. البديل الصحيح إعلان واحد
/// («جارٍ تحميل البيانات») يقابل ما تقوله الحركة للمُبصِر.
class _LoadingSemantics extends StatelessWidget {
  const _LoadingSemantics({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'جارٍ تحميل البيانات',
      liveRegion: true,
      child: ExcludeSemantics(child: child),
    );
  }
}
