import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kinetic_enterprise/core/theme/app_colors.dart';
import 'package:kinetic_enterprise/core/theme/app_theme.dart';

/// ============================================================================
///  اختبار الوضع الليلي
///
///  يفحص الافتراض الذي بُني عليه التصميم كله: أن لوحة الألوان المحايدة
///  (AppColors) تتبع سطوع السمة المطبَّقة فعلياً.
///
///  السبب في وجود هذا الاختبار تحديداً: الوضع الليلي نُفِّذ عبر حالة عامة
///  قابلة للتغيير (_active في AppColors) بدل ThemeExtension، تفادياً لإعادة
///  كتابة 504 موضع استخدام. هذا الاختيار سليم لكنه ليس بديهياً، وأكثر ما
///  يمكن أن ينكسر فيه هو التزامن: أن تُقرأ اللوحة قبل ضبطها، أو أن يلتقطها
///  شيء ويحتفظ بها بعد التبديل. هذه هي الاختبارات أدناه.
/// ============================================================================
void main() {
  // AppTheme.build يستدعي GoogleFonts الذي يقرأ بيان الأصول، وهو يتطلّب
  // ربط اختبار مُهيّأ. بلا هذا السطر تفشل اختبارات السمة بخطأ ربط لا بخطأ
  // منطق، فيبدو الكود معطوباً وهو سليم.
  TestWidgetsFlutterBinding.ensureInitialized();

  // GoogleFonts يحاول جلب الخط من الشبكة وهي محجوبة في بيئة الاختبار،
  // فيرمي استثناءً غير متزامن يُفشل الاختبار بعد اكتماله. تعطيل الجلب
  // يحوّله إلى استثناء متزامن يُلتقط هنا ويُهمَل: هذه اختبارات ألوان لا
  // خطوط، وتحميل الخط ليس جزءاً مما تفحصه.
  // الخط لا يُحمَّل في بيئة الاختبار: المشروع يعتمد على google_fonts بالجلب
  // الشبكي (لا نسخة مضمَّنة في assets)، والشبكة محجوبة هنا. GoogleFonts
  // يجدول محاولة التحميل ثم يرمي استثناءً غير متزامن يُفشل الاختبار بعد
  // اكتماله. [_buildTheme] أدناه يعزل ذلك.
  GoogleFonts.config.allowRuntimeFetching = false;

  // كل اختبار يعيد اللوحة إلى النهارية حتى لا يتسرّب أثره إلى ما بعده.
  tearDown(() => AppColors.applyBrightness(Brightness.light));

  group('لوحة الألوان تتبع السطوع', () {
    test('النهاري: أسطح فاتحة ونص داكن', () {
      AppColors.applyBrightness(Brightness.light);

      expect(AppColors.brightness, Brightness.light);
      expect(_luminance(AppColors.surface), greaterThan(0.8),
          reason: 'سطح الوضع النهاري يجب أن يكون فاتحاً');
      expect(_luminance(AppColors.textPrimary), lessThan(0.2),
          reason: 'نص الوضع النهاري يجب أن يكون داكناً');
    });

    test('الليلي: أسطح داكنة ونص فاتح', () {
      AppColors.applyBrightness(Brightness.dark);

      expect(AppColors.brightness, Brightness.dark);
      expect(_luminance(AppColors.surface), lessThan(0.2),
          reason: 'سطح الوضع الليلي يجب أن يكون داكناً');
      expect(_luminance(AppColors.textPrimary), greaterThan(0.7),
          reason: 'نص الوضع الليلي يجب أن يكون فاتحاً');
    });

    test('الليلي ليس أسود خالصاً', () {
      AppColors.applyBrightness(Brightness.dark);

      // الأسود التام مع نص أبيض يُجهد العين في جلسة طويلة، ويُظهر تلطّخ
      // الهالة حول الحروف العربية الرفيعة.
      expect(_luminance(AppColors.paper), greaterThan(0.0),
          reason: 'خلفية الوضع الليلي لا يجوز أن تكون سوداء خالصة');
    });

    test('الحدود في الليلي أفتح من السطح لا أغمق', () {
      AppColors.applyBrightness(Brightness.dark);

      // في الظلام يُرسَم الفصل بالضوء لا بالعتمة؛ حدّ أغمق من سطحه يختفي.
      expect(_luminance(AppColors.border), greaterThan(_luminance(AppColors.surface)),
          reason: 'حدّ أغمق من السطح غير مرئي في الوضع الليلي');
    });
  });

  group('تباين النص مقروء في الوضعين', () {
    // 4.5:1 هو حدّ WCAG AA للنص العادي.
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final label = brightness == Brightness.dark ? 'الليلي' : 'النهاري';

      test('$label: النص الأساسي على السطح ≥ 4.5:1', () {
        AppColors.applyBrightness(brightness);
        expect(_contrast(AppColors.textPrimary, AppColors.surface), greaterThanOrEqualTo(4.5));
      });

      test('$label: النص الثانوي على السطح ≥ 4.5:1', () {
        AppColors.applyBrightness(brightness);
        expect(_contrast(AppColors.textSecondary, AppColors.surface), greaterThanOrEqualTo(4.5));
      });

      test('$label: ألوان الحالات على خلفياتها ≥ 4.5:1', () {
        AppColors.applyBrightness(brightness);
        // الحالة تُقرأ نصاً على خلفيتها الملوّنة (شارات النجاح والخطر)،
        // فالتباين بينهما هو ما يحدّد قابلية القراءة لا جمال اللون.
        expect(_contrast(AppColors.success, AppColors.successBg), greaterThanOrEqualTo(4.5),
            reason: 'نص النجاح على خلفيته');
        expect(_contrast(AppColors.danger, AppColors.dangerBg), greaterThanOrEqualTo(4.5),
            reason: 'نص الخطر على خلفيته');
        expect(_contrast(AppColors.warning, AppColors.warningBg), greaterThanOrEqualTo(4.5),
            reason: 'نص التحذير على خلفيته');
        expect(_contrast(AppColors.info, AppColors.infoBg), greaterThanOrEqualTo(4.5),
            reason: 'نص المعلومة على خلفيته');
      });
    }
  });

  group('ThemeData يتّسق مع اللوحة', () {
    test('AppTheme.build يضبط اللوحة قبل قراءتها', () {
      // بناء السمة الليلية يجب أن يلتقط ألوان الليل لا النهار: قيم الثيم
      // نفسها (خلفية الصفحة، لون الحدود) تُقرأ من AppColors أثناء البناء.
      AppColors.applyBrightness(Brightness.light);
      final dark = _buildTheme(const AppColors(), Brightness.dark);

      expect(dark.brightness, Brightness.dark);
      expect(_luminance(dark.scaffoldBackgroundColor), lessThan(0.2),
          reason: 'خلفية السمة الليلية التُقطت من لوحة النهار');
    });

    test('لون العلامة الداكن يُرفع سطوعه في الليلي مع حفظ درجته', () {
      // هويات العملاء غالباً داكنة (كحلي، عنابي) فتذوب في خلفية داكنة.
      const navy = AppColors(primary: Color(0xFF0B2540));

      final light = _buildTheme(navy, Brightness.light).colorScheme.primary;
      final dark = _buildTheme(navy, Brightness.dark).colorScheme.primary;

      expect(_luminance(dark), greaterThan(_luminance(light)),
          reason: 'لون العلامة لم يُرفع سطوعه للوضع الليلي');

      // الدرجة اللونية تبقى: يصبح أفتح لا مختلفاً — وإلا تبدّلت هوية العميل.
      final hueLight = HSLColor.fromColor(light).hue;
      final hueDark = HSLColor.fromColor(dark).hue;
      expect((hueDark - hueLight).abs(), lessThan(12),
          reason: 'تبدّلت درجة لون العلامة لا سطوعها فقط');
    });

    test('بناء السمتين تتابعاً لا يترك اللوحة على الخطأ', () {
      // MaterialApp تبني theme وdarkTheme معاً في كل إطار، فآخر بناء يترك
      // أثره في اللوحة. هذا بالضبط ما يعالجه builder في main.dart باستدعاء
      // applyBrightness على السطوع المطبَّق فعلياً — والاختبار يوثّق أن
      // الترتيب وحده غير كافٍ، فلا يُحذف ذلك السطر لاحقاً بحسن نيّة.
      _buildTheme(const AppColors(), Brightness.light);
      _buildTheme(const AppColors(), Brightness.dark);
      expect(AppColors.brightness, Brightness.dark);

      AppColors.applyBrightness(Brightness.light);
      expect(AppColors.brightness, Brightness.light);
      expect(_luminance(AppColors.surface), greaterThan(0.8));
    });
  });
}

/// يبني السمة ويبتلع أخطاء تحميل الخط وحدها.
///
/// الاختبار هنا عن الألوان لا عن الخطوط، وفشل جلب خط من الشبكة في بيئة
/// اختبار معزولة ليس عيباً في الشيفرة. أي خطأ آخر يمرّ كما هو فيُفشل
/// الاختبار — العزل مقصور على السبب المعروف لا مفتوح على كل شيء.
ThemeData _buildTheme(AppColors colors, Brightness brightness) {
  late ThemeData theme;
  runZonedGuarded(
    () => theme = AppTheme.build(colors, brightness: brightness),
    (error, stack) {
      if (!error.toString().contains('GoogleFonts')) throw error;
    },
  );
  return theme;
}

double _luminance(Color c) => c.computeLuminance();

/// نسبة التباين حسب WCAG.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
