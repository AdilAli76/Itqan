import 'package:flutter/material.dart';

import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_text_styles.dart';

/// نموذجٌ يُعرَض حواراً على الشاشات الواسعة، وصفحةً كاملة على الهاتف.
///
/// **العطب الذي يصلحه:** حوار `AlertDialog` على شاشة هاتف يأخذ نحو نصفها،
/// ثم تفتح لوحة المفاتيح فتأخذ نصف ما بقي — فيبقى للنموذج شريطٌ ضيّق
/// يتمرّر فيه المستخدم بين حقلين. وأزرار «حفظ» و«إلغاء» تُدفَع خارج الرؤية،
/// فيظنّ من يملأ النموذج أنه لا سبيل لحفظه.
///
/// وعلى الهاتف تُعرَض صفحةً كاملة: العنوان في شريط علوي، والحقول في كامل
/// العرض، والأزرار مثبَّتة أسفل الشاشة فوق لوحة المفاتيح — لا تختفي مهما
/// طال النموذج.
///
/// **ولماذا لا تُغيَّر الشاشات الواسعة:** الحوار هناك في محلّه — يبقي ما
/// خلفه مرئياً، والسياق جزءٌ من العمل: من يُنشئ أمر شراء يرى قائمة الأوامر
/// خلفه. أمّا على الهاتف فلا شيء مرئي خلفه أصلاً.
class AdaptiveFormDialog extends StatelessWidget {
  const AdaptiveFormDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.maxWidth = 460,
  });

  final String title;

  /// محتوى النموذج. يُمرَّر عمودياً، ويُلَفّ بمُمرِّر هنا — فلا يلفّه
  /// المستدعي مرّة ثانية.
  final Widget body;

  /// أزرار الأسفل، بترتيبها المعتاد: الإلغاء ثم الفعل الرئيسي.
  final List<Widget> actions;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!Breakpoints.isMobile(context)) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: maxWidth,
          child: SingleChildScrollView(child: body),
        ),
        actions: actions,
      );
    }

    // Dialog.fullscreen لا Scaffold داخل حوار: يحمل انتقالاً صحيحاً ويُغلق
    // بزرّ الرجوع في النظام كما يتوقّع مستخدم الأندرويد.
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, style: AppTextStyles.headlineMd()),
          leading: IconButton(
            // arrow_back تنعكس تلقائياً في الاتجاه العربي فتشير يميناً —
            // وهو اتجاه الرجوع الصحيح.
            icon: const Icon(Icons.arrow_back),
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: body,
          ),
        ),
        // الأزرار مثبَّتة لا في آخر التمرير: نموذجٌ طويل يدفعها خارج الرؤية،
        // فيملأ المستخدم الحقول ولا يجد ما يحفظ به.
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final action in actions)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: action,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
