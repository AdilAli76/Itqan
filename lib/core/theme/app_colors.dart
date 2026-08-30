import 'package:flutter/material.dart';

/// هوية ألوان "Kinetic Ink & Amber" — لوحة مصمَّمة يدوياً، وليست ناتج
/// خوارزمية Material 3 Tonal Palette (التي تعطي شكل "تصميم الذكاء الاصطناعي"
/// النمطي بنفسجي/فيروزي المتكرر في كل التصاميم الجاهزة).
///
/// هذه القيم هي اللوحة "الافتراضية" فقط. كل منظمة (زبون) يمكنها استبدال
/// [primary] و [secondary] من لوحة الإعدادات دون المساس بألوان الحالات
/// الدلالية (نجاح/تحذير/خطر) التي تبقى ثابتة دائماً لضمان وضوح المعنى.
class AppColors {
  const AppColors({
    this.primary = const Color(0xFF0B2540),
    this.primaryDark = const Color(0xFF123554),
    this.secondary = const Color(0xFFC8952B),
    this.secondaryLight = const Color(0xFFF3E3C2),
  });

  /// يبني نسخة ألوان مخصّصة لمنظمة معيّنة بناءً على القيم المخزَّنة في
  /// جدول organizations (primary_color / secondary_color) — انظر
  /// BrandingProvider. أي قيمة hex غير صالحة تسقط تلقائياً للّون الافتراضي.
  factory AppColors.fromHex({String? primaryHex, String? secondaryHex}) {
    Color? parse(String? hex) {
      if (hex == null || hex.isEmpty) return null;
      final cleaned = hex.replaceAll('#', '');
      final value = int.tryParse('FF$cleaned', radix: 16);
      return value != null ? Color(value) : null;
    }

    const defaults = AppColors();
    return AppColors(
      primary: parse(primaryHex) ?? defaults.primary,
      secondary: parse(secondaryHex) ?? defaults.secondary,
    );
  }

  final Color primary;
  final Color primaryDark;
  final Color secondary;
  final Color secondaryLight;

  // ---- محايدة (لا تتغير مع هوية الزبون، وتتغير مع السطوع) ----
  //
  // هذه القيم كانت ثوابت static const، وهو ما جعل الوضع الليلي مستحيلاً:
  // لون ثابت لا يمكن أن يكون أبيض نهاراً وداكناً ليلاً. تحويلها إلى getters
  // تقرأ من [_active] يفتح الوضعين بلا لمس 504 موضع استخدام في 44 ملفاً —
  // وهو ما كانت ستكلّفه الهجرة إلى ThemeExtension واستدعاء context في كل
  // موضع، بلا مكسب حقيقي في نظام له ثيم واحد فعّال في كل لحظة.
  //
  // الثمن المقبول: حالة عامة قابلة للتغيير. وهي آمنة هنا لسببين محدَّدين:
  //  1) تُضبط في builder داخل MaterialApp قبل أن تُبنى أي شاشة (راجع
  //     main.dart)، فلا يقرأها أحد قبل ضبطها.
  //  2) صيرورتها getters تمنع بالبناء أن يلتقطها ودجت const ويحتفظ بها
  //     عبر تبديل السمة — لأن getter لا يصلح في تعبير const أصلاً، فيرفضه
  //     المترجم. أي أن نوع الخطأ الوحيد الخطير هنا غير قابل للتعبير.

  static _Neutrals _active = _Neutrals.light;

  /// لوح خلفية الفرع الحالي — راجع [BranchPalettes].
  static String _palette = BranchPalettes.defaultPalette;

  /// تُستدعى من MaterialApp.builder عند كل تغيّر في السمة.
  static void applyBrightness(Brightness brightness) {
    final base = brightness == Brightness.dark ? _Neutrals.dark : _Neutrals.light;
    _active = BranchPalettes._tint(base, _palette);
  }

  /// يضبط لوح الفرع ويُعيد بناء الألوان المحايدة عليه.
  ///
  /// <para>يُستدعى بعد تسجيل الدخول حين يُعرَف فرع المستخدم.</para>
  static void applyBranchPalette(String? palette) {
    _palette = BranchPalettes.normalize(palette);
    applyBrightness(_active.brightness);
  }

  static String get branchPalette => _palette;

  static Brightness get brightness => _active.brightness;

  static Color get paper => _active.paper;
  static Color get surface => _active.surface;
  static Color get surfaceAlt => _active.surfaceAlt;
  static Color get border => _active.border;
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textMuted => _active.textMuted;

  /// اللوحة الجاهزة التي يختار منها العميل هوية منظمته (شاشة الفروع
  /// والهوية). موضعها هنا لا في الشاشة: هذه ألوان علامة تجارية تُخزَّن في
  /// جدول organizations ثم يُبنى منها الثيم عبر [AppColors.fromHex]، فهي
  /// جزء من نظام الألوان نفسه لا تنسيق شاشة بعينها. وبقاؤها في الشاشة كان
  /// يعني أن إضافة لون مقترح جديد تتطلّب تعديل ملف عرض.
  static const List<Color> presetPrimaries = [
    Color(0xFF0B2540), // الافتراضي - Kinetic Ink
    Color(0xFF1E3A2E), // أخضر مؤسسي غامق
    Color(0xFF5C1A1A), // عنابي
    Color(0xFF3A2E1E), // بني بن
    Color(0xFF1E293B), // كحلي رمادي
  ];

  /// ألوان ثانوية مقترحة — تُقرأ مع [presetPrimaries] في الشاشة نفسها.
  static const List<Color> presetSecondaries = [
    Color(0xFFC8952B), // الافتراضي - ذهبي
    Color(0xFF2A9D6F),
    Color(0xFFB23A2E),
    Color(0xFF2A5F82),
  ];

  // ---- دلالية (لا تتأثر بالعلامة التجارية، وتتأثر بالسطوع) ----
  //
  // المعنى ثابت — أخضر نجاح وأحمر خطر في الوضعين — لكن الدرجة تتغيّر:
  // أخضر 0xFF1E7F4F على خلفية داكنة يهبط تباينه تحت الحد المقروء، وخلفيات
  // الحالات الفاتحة (successBg وأخواتها) تتحوّل إلى بقع بيضاء ساطعة تُبطل
  // الغرض من الوضع الليلي. لذلك للوضع الداكن درجات أفتح وخلفيات شفافة.
  static Color get success => _active.success;
  static Color get successBg => _active.successBg;
  static Color get warning => _active.warning;
  static Color get warningBg => _active.warningBg;
  static Color get danger => _active.danger;
  static Color get dangerBg => _active.dangerBg;
  static Color get info => _active.info;
  static Color get infoBg => _active.infoBg;
}

/// مجموعة الألوان غير المرتبطة بالعلامة التجارية، بنسختَي السطوع.
@immutable
class _Neutrals {
  const _Neutrals({
    required this.brightness,
    required this.paper,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
  });

  final Brightness brightness;
  final Color paper, surface, surfaceAlt, border;
  final Color textPrimary, textSecondary, textMuted;
  final Color success, successBg, warning, warningBg;
  final Color danger, dangerBg, info, infoBg;

  static const light = _Neutrals(
    brightness: Brightness.light,
    paper: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0F2F5),
    border: Color(0xFFE1E4E9),
    textPrimary: Color(0xFF1A2027),
    textSecondary: Color(0xFF5B6472),
    textMuted: Color(0xFF8A93A2),
    // 0xFF1C774A لا 0xFF1E7F4F: الأصل يعطي تبايناً 4.35:1 على خلفيته
    // successBg، أي دون حدّ WCAG AA (4.5:1) — وهو اللون الوحيد في اللوحة
    // الذي كان تحته. كشفه اختبار التباين في test/dark_mode_test.dart.
    // التغميق طفيف يحفظ الدرجة اللونية ويرفع التباين إلى 4.83:1.
    success: Color(0xFF1C774A),
    successBg: Color(0xFFE3F3EA),
    // 0xFF8C5C14 لا 0xFFB9791A: الأصل كان الأسوأ في اللوحة كلها بتباين
    // 3.15:1 على خلفيته — أي أن نصّ التحذير، وهو أكثر ما يجب أن يُقرأ،
    // كان أقلّها وضوحاً. التغميق يحفظ الدرجة الكهرمانية ويرفعه إلى 5.01:1.
    warning: Color(0xFF8C5C14),
    warningBg: Color(0xFFFAEEDB),
    danger: Color(0xFFB23A2E),
    dangerBg: Color(0xFFF8E4E1),
    info: Color(0xFF2A5F82),
    infoBg: Color(0xFFE2EDF3),
  );

  /// الوضع الليلي ليس عكساً حسابياً للنهاري.
  ///
  /// الأسطح رمادية مزرقّة لا سوداء خالصة: الأسود التام مع نص أبيض يُنتج
  /// تباينًا يُجهد العين في جلسة عمل طويلة، ويُظهر «تلطّخ الهالة» حول
  /// الحروف العربية الرفيعة تحديداً. والحدود أفتح من الأسطح لا أغمق —
  /// في الظلام يُرسَم الفصل بالضوء لا بالعتمة.
  static const dark = _Neutrals(
    brightness: Brightness.dark,
    paper: Color(0xFF12171F),
    surface: Color(0xFF1A212B),
    surfaceAlt: Color(0xFF222B37),
    border: Color(0xFF303B4A),
    textPrimary: Color(0xFFE8ECF1),
    textSecondary: Color(0xFFA8B3C1),
    textMuted: Color(0xFF7A8695),
    // درجات أفتح وأكثر تشبّعاً لتبقى مقروءة على خلفية داكنة.
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF17301F),
    warning: Color(0xFFF0B152),
    warningBg: Color(0xFF33260F),
    danger: Color(0xFFF07167),
    dangerBg: Color(0xFF351A17),
    info: Color(0xFF6FB3DE),
    infoBg: Color(0xFF152833),
  );
}

/// ألواح خلفية الفروع.
///
/// **ما تغيّره وما لا تغيّره:** تُزيح الأسطح والحدود نحو لون خفيف، وتُبقي
/// **ألوان العلامة التجارية كما هي**. فرعٌ يختار لوحاً دافئاً يظلّ يعرض
/// هوية شركته لا هوية أخرى — وإلا صار لكل فرع علامة، وهو نقيض
/// White-Labeling الذي بُني عليه النظام (ARCHITECTURE.md §2.1).
///
/// **ولماذا على الفرع لا على المستخدم:** تفضيل السطوع (نهاري/ليلي) شخصيٌّ
/// ويُحفَظ محلياً (راجع ThemeModeNotifier). أما اللوح فيميّز **المكان**:
/// موظف ينتقل بين فرعين يعرف من اللون أين هو الآن، وهو ما يمنع إدخال بيانات
/// في الفرع الخطأ — الخطأ الأشيع في الأنظمة متعدّدة الفروع.
class BranchPalettes {
  static const defaultPalette = 'default';

  /// المعرّف ← (الاسم المعروض، اللون المُزيح).
  static const options = <String, (String, Color)>{
    defaultPalette: ('محايد', Color(0x00000000)),
    'warm': ('دافئ', Color(0xFFB07D3A)),
    'cool': ('بارد', Color(0xFF3A6FB0)),
    'green': ('أخضر', Color(0xFF3A8F6A)),
    'slate': ('رمادي', Color(0xFF5B6472)),
  };

  static String normalize(String? value) =>
      value != null && options.containsKey(value) ? value : defaultPalette;

  static String labelOf(String? value) => options[normalize(value)]!.$1;

  /// شدّة الإزاحة صغيرة عمداً (7٪ نهاراً و12٪ ليلاً).
  ///
  /// لوحٌ يصبغ الشاشة يُتعب العين في وردية كاملة ويُضعف تباين النصّ المضبوط
  /// بعناية. المطلوب تمييز لا تلوين — يُلاحَظ عند الانتقال بين فرعين ولا
  /// يُلاحَظ بعد دقيقة عمل.
  static _Neutrals _tint(_Neutrals base, String palette) {
    final key = normalize(palette);
    if (key == defaultPalette) return base;

    final tint = options[key]!.$2;
    final strength = base.brightness == Brightness.dark ? 0.12 : 0.07;
    Color mix(Color c) => Color.lerp(c, tint, strength) ?? c;

    return _Neutrals(
      brightness: base.brightness,
      paper: mix(base.paper),
      surface: mix(base.surface),
      surfaceAlt: mix(base.surfaceAlt),
      border: mix(base.border),
      // النصوص وألوان الحالة (نجاح/تحذير/خطر) لا تُمسّ: تباين النصّ مضبوط،
      // والأحمر الذي يميل إلى الأخضر يفقد معناه قبل أن يكسب جمالاً.
      textPrimary: base.textPrimary,
      textSecondary: base.textSecondary,
      textMuted: base.textMuted,
      success: base.success,
      successBg: base.successBg,
      warning: base.warning,
      warningBg: base.warningBg,
      danger: base.danger,
      dangerBg: base.dangerBg,
      info: base.info,
      infoBg: base.infoBg,
    );
  }
}
