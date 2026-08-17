import 'package:flutter/material.dart';

/// نقاط التوقف الموحّدة لكل الشاشات — أي شاشة جديدة تُبنى مستقبلاً
/// تستخدم هذه القيم فقط، بدل أن يخترع كل مطوّر رقمه الخاص (وهذا بالضبط
/// ما يسبب "ثغرة عدم التوافق" بين الشاشات مع الوقت).
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double desktop = 1440;

  static bool isMobile(BuildContext context) => MediaQuery.of(context).size.width < mobile;
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= mobile && w < tablet;
  }

  // تصحيح لتعديل سابق خاطئ: رفعت العتبة إلى desktop (1440) لحل شكوى ضيق
  // الشريط الجانبي، فإذا بالنتيجة أسوأ بكثير — أي نافذة لابتوب عادية
  // (1366×768 وأمثالها شائعة جداً) أصبحت تُعامَل كموبايل بالكامل: بلا
  // شريط جانبي ولا علوي، فقط قائمة همبرغر، واختفاء كل أزرار الإجراءات لكل
  // شاشة (راجع AdaptiveScaffold — كانت actions تُعرَض فقط داخل header
  // الديسكتوب). العتبة الصحيحة لتخطيط سطح المكتب الثابت هي tablet (1024)
  // كما كانت أصلاً؛ الحل الصحيح لضيق الشريط الجانبي يكون بتضييق الشريط
  // نفسه أو تحسين المحتوى، لا بإخفاء تخطيط سطح المكتب كله عن نوافذ عادية.
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= tablet;
}

/// بديل عن Widget.builder المكرر في كل شاشة — يبني الواجهة المناسبة
/// حسب العرض الحالي مع إعادة بناء تلقائية عند تغيّر حجم النافذة (Web/Desktop).
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder desktop;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= Breakpoints.tablet) return desktop(context);
    if (width >= Breakpoints.mobile) return (tablet ?? desktop)(context);
    return mobile(context);
  }
}
