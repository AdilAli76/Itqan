import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kinetic_enterprise/shared/widgets/filter_chip_button.dart';

/// شريحة الفلترة يجب أن تأخذ عرض محتواها لا عرض السطر.
///
/// العيب الذي يحرسه هذا الاختبار كان مرئياً في الإنتاج: Container مع
/// `alignment` وبلا عرض محدَّد يتمدّد ليملأ قيود أبيه. وداخل Wrap تكون تلك
/// القيود عرض السطر كاملاً، فتصبح كل شريحة بعرض الشاشة وتنزل وحدها في سطر —
/// فتظهر فلاتر المشتريات والتقارير قائمةً رأسية لا صفَّ شرائح.
///
/// الاختبار يقيس العرض ولا يفحص وجود ودجت: العيب لم يكن في الشجرة بل في
/// القياس، والشجرة كانت صحيحة تماماً وهي معطوبة بصرياً.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpChips(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChipButton(label: 'الكل', selected: true, onTap: () {}),
                  FilterChipButton(label: 'مسودة', selected: false, onTap: () {}),
                  FilterChipButton(label: 'مُرسَل للموّرد', selected: false, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('الشريحة تأخذ عرض محتواها لا عرض السطر', (tester) async {
    const lineWidth = 600.0;
    await pumpChips(tester, lineWidth);

    final widths = tester
        .widgetList<FilterChipButton>(find.byType(FilterChipButton))
        .map((w) => tester.getSize(find.byWidget(w)).width)
        .toList();

    for (final w in widths) {
      expect(w, lessThan(lineWidth / 2),
          reason: 'الشريحة تتمدّد لتملأ السطر — عودة عيب alignment');
    }

    // شريحتان مختلفتا النصّ يجب أن تختلفا عرضاً؛ التساوي دليل تمدّد.
    expect(widths[0], isNot(closeTo(widths[2], 1)),
        reason: 'كل الشرائح بعرض واحد رغم اختلاف نصوصها');
  });

  testWidgets('الشرائح الثلاث تقع في سطر واحد على عرض كافٍ', (tester) async {
    await pumpChips(tester, 600);

    final tops = tester
        .widgetList<FilterChipButton>(find.byType(FilterChipButton))
        .map((w) => tester.getTopLeft(find.byWidget(w)).dy)
        .toSet();

    expect(tops.length, 1, reason: 'الشرائح موزَّعة على أكثر من سطر بلا داعٍ');
  });

  testWidgets('هدف اللمس لا يقلّ عن 44 نقطة', (tester) async {
    await pumpChips(tester, 600);

    for (final w in tester.widgetList<FilterChipButton>(find.byType(FilterChipButton))) {
      final size = tester.getSize(find.byWidget(w));
      expect(size.height, greaterThanOrEqualTo(FilterChipButton.minTouchHeight));
    }
  });
}
