import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_enterprise/shared/widgets/adaptive_dialog.dart';

/// يحرس ما لا يظهر خرقُه في أي لقطة: نموذجٌ طويل على شاشة هاتف.
///
/// تسعة وعشرون حواراً حُوّلت دفعةً واحدة، وجولة اللقطات لا تفتح حواراً —
/// فبلا هذا الملف يمرّ تغييرٌ يمسّ كل نماذج النظام بلا أن يراه أحد.
///
/// والمقيس هنا ليس الشكل بل ما يُعطِّل العمل فعلاً: أن يملأ المستخدم
/// الحقول ثم لا يجد زرّ الحفظ لأن النموذج دفعه خارج الشاشة.
void main() {
  Widget host(Size size, Widget child) => MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          locale: const Locale('ar'),
          home: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      );

  Widget longForm() => AdaptiveDialog(
        title: 'نموذج طويل',
        maxWidth: 420,
        actions: [
          TextButton(onPressed: () {}, child: const Text('إلغاء')),
          FilledButton(onPressed: () {}, child: const Text('حفظ')),
        ],
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 20; i++)
              TextField(decoration: InputDecoration(labelText: 'حقل $i')),
          ],
        ),
      );

  testWidgets('على الهاتف: صفحة كاملة وزرّ الحفظ مرئيّ رغم طول النموذج',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const Size(390, 844), longForm()));
    await tester.pumpAndSettle();

    // ‏AlertDialog لا Dialog: صفحة الهاتف مبنيّة بـDialog.fullscreen وهي
    // Dialog أيضاً — فالمقيس غياب الحوار المحصور لا غياب النوع.
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'الهاتف يعرض صفحةً كاملة لا حواراً محصوراً');
    expect(find.byType(AppBar), findsOneWidget);

    // الزرّ مرئيّ فعلاً لا موجودٌ في الشجرة: عشرون حقلاً كانت تدفعه خارج
    // الشاشة، والمستخدم يملأ النموذج ثم لا يجد ما يحفظ به.
    final save = find.text('حفظ');
    expect(save, findsOneWidget);
    final box = tester.getRect(save);
    expect(box.bottom, lessThanOrEqualTo(844),
        reason: 'زرّ الحفظ خارج الشاشة — النموذج مصيدة لا مخرج منها');
  });

  testWidgets('على سطح المكتب: يبقى حواراً بعرضٍ محدود', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const Size(1400, 900), longForm()));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'ما خلف الحوار مرئيّ، والسياق جزءٌ من العمل على الشاشة الواسعة');
    expect(find.byType(AppBar), findsNothing);
  });
}
