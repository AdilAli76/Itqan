import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// اختصارٌ واحد: مفتاحُه ووصفُه.
///
/// <para>الوصف جزءٌ من التعريف لا زينة: اختصارٌ بلا اسمٍ يُعرَض هو اختصارٌ
/// لا يعرفه أحد.</para>
class AppShortcut {
  const AppShortcut(this.label, this.keyLabel);

  /// ما يفعله — كما يُعرَض في الشريط.
  final String label;

  /// اسم المفتاح كما يُطبع: F2، Esc.
  final String keyLabel;
}

/// شريط الاختصارات السفلي.
///
/// <para><b>العطب الذي يسدّه:</b> نقطة البيع عندنا فيها ستّة اختصارات
/// وظيفية عاملة منذ زمن (F2 نقدي، F3 خصم من الرصيد، F4 بطاقة العميل،
/// F6 لوحة الكمية، F8 إلغاء، Esc تفريغ البحث) — **ولا يعرفها أحد**. لا
/// شاشة تذكرها ولا دليل يُقرأ. فالكاشير يستعمل الفأرة في كل عملية، وميزةٌ
/// مبنيّة ومُختبَرة لا تُستعمل كأنها غير موجودة.</para>
///
/// <para><b>ولماذا العرض لا الاختصارات:</b> الاختصارات موجودة. المفقود
/// عرضُها. وإضافة مفاتيح جديدة كانت ستُنتج خريطتين متعارضتين — وهو ما وقع
/// فعلاً حين نُقلت خريطة نظامٍ آخر (F1/F2/F9/F12) إلى هذا الملف: كانت
/// ستجعل F2 يطبع بدل أن يُنهي بيعاً نقدياً. ويدُ الكاشير تسبق عينَه.</para>
///
/// <para>يظهر على سطح المكتب وحده: على شاشة اللمس لا لوحة مفاتيح، والشريط
/// يأكل ارتفاعاً هو أثمن ما فيها.</para>
class ShortcutHintBar extends StatelessWidget {
  const ShortcutHintBar({super.key, required this.shortcuts});

  final List<AppShortcut> shortcuts;

  @override
  Widget build(BuildContext context) {
    if (shortcuts.isEmpty) return const SizedBox.shrink();

    return Semantics(
      // قارئ الشاشة يقرؤها جملةً واحدة لا اثني عشر جزءاً متناثراً.
      label: 'اختصارات لوحة المفاتيح: '
          '${shortcuts.map((s) => '${s.keyLabel} ${s.label}').join('، ')}',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final shortcut in shortcuts) ...[
                _Hint(shortcut: shortcut),
                const SizedBox(width: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.shortcut});
  final AppShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            shortcut.keyLabel,
            // اللاتينية دائماً يساراً مهما كان اتجاه الصفحة: «F2» معكوسةً
            // تصير «2F» ولا يجدها من ينظر إلى لوحته.
            textDirection: TextDirection.ltr,
            style: AppTextStyles.caption(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 5),
        Text(shortcut.label, style: AppTextStyles.caption(color: AppColors.textSecondary)),
      ],
    );
  }
}

/// يجعل `Enter` ينتقل إلى الحقل التالي داخل نموذج.
///
/// <para><b>العطب الذي تسدّه:</b> حوارات الإدخال — فاتورة المورّد، أمر
/// الشراء، صنف جديد — تحتاج فأرةً بين كل حقلين. ومن يُدخل عشرين سطراً
/// يمدّ يده إلى الفأرة أربعين مرّة.</para>
///
/// <para><b>⚠ ولا تُلَفّ بها نقطة البيع أبداً:</b> `Enter` هناك مفتاحُ قارئ
/// الباركود — يُرسله بعد كل مسحة — ويعالجه مربع البحث عبر `onSubmitted`.
/// اختطافه يكسر المسح كلّه. ولذلك هذه ودجت **اختيارية تُلَفّ بها النماذج**،
/// لا سلوكٌ عامّ للتطبيق: الفرق بين الاثنين هو الفرق بين ميزة وعطب.</para>
///
/// <para>ولا تعترض الحقول متعدّدة الأسطر: فيها `Enter` سطرٌ جديد، وسلبُه
/// منها يمنع كتابة ملاحظة من سطرين.</para>
class EnterAdvancesFocus extends StatelessWidget {
  const EnterAdvancesFocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: Focus(
        // لا يأخذ التركيز لنفسه — يراقب فقط ما يمرّ عبر أبنائه.
        canRequestFocus: false,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.numpadEnter) {
            return KeyEventResult.ignored;
          }

          final focused = FocusManager.instance.primaryFocus;
          if (focused == null) return KeyEventResult.ignored;

          // الحقل متعدّد الأسطر يحتفظ بـEnter لنفسه.
          if (_isMultiline(focused.context)) return KeyEventResult.ignored;

          focused.nextFocus();
          return KeyEventResult.handled;
        },
        child: child,
      ),
    );
  }

  /// أفي شجرة هذا العنصر حقلُ نصٍّ متعدّد الأسطر؟
  ///
  /// <para>يُفتَّش صعوداً لا هبوطاً: العنصر المركَّز ورقةٌ داخل `EditableText`،
  /// وأبوه هو من يحمل `maxLines`.</para>
  static bool _isMultiline(BuildContext? context) {
    if (context == null) return false;

    var multiline = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditableText) {
        multiline = widget.maxLines != 1;
        return false;
      }
      // لا نصعد إلى ما لا نهاية: `EditableText` قريبٌ جداً من الورقة.
      return true;
    });
    return multiline;
  }
}
