import 'package:flutter/widgets.dart';

/// علامة وجود فقط (Marker InheritedWidget) — تخبر AdaptiveScaffold أنه
/// يُرسَم داخل AppShell (نظام النوافذ/التبويبات)، فيكتفي برسم العنوان
/// والمحتوى فقط بلا Scaffold/شريط جانبي خاص به (يوفّرهما AppShell نفسه
/// مرة واحدة لكل التبويبات). بلا هذه العلامة، AdaptiveScaffold يرسم نفسه
/// بشكل مستقل كما كان قبل نظام التبويبات (شبكة أمان، غير مستخدَمة فعلياً
/// الآن لأن كل الشاشات تُفتَح عبر AppShell).
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required super.child});

  static bool isActive(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<ShellScope>() != null;

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}
