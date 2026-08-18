import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/shared/widgets/numeric_keypad.dart';

/// يبني اللوحة مع حالة حقيقية، فالقيمة تصعد إلى الأب وتعود كما يحدث في
/// نقطة البيع — اختبار اللوحة معزولة عن الحالة كان سيخفي أخطاء التزامن.
Future<String Function()> _pumpKeypad(
  WidgetTester tester, {
  bool allowDecimal = true,
  int decimalPlaces = 2,
  int maxIntegerDigits = 9,
}) async {
  var value = '';
  late StateSetter setState;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setter) {
            setState = setter;
            return SingleChildScrollView(
              child: NumericKeypad(
                value: value,
                onChanged: (v) => setState(() => value = v),
                allowDecimal: allowDecimal,
                decimalPlaces: decimalPlaces,
                maxIntegerDigits: maxIntegerDigits,
              ),
            );
          },
        ),
      ),
    ),
  );

  return () => value;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(OutlinedButton, label));
  await tester.pump();
}

void main() {
  testWidgets('إدخال أرقام متتالية', (tester) async {
    final value = await _pumpKeypad(tester);
    await tester.pump();

    await _tap(tester, '1');
    await _tap(tester, '2');
    await _tap(tester, '5');

    expect(value(), '125');
  });

  testWidgets('لا صفر بادئ بلا معنى', (tester) async {
    final value = await _pumpKeypad(tester);
    await tester.pump();

    await _tap(tester, '0');
    await _tap(tester, '5');

    // "05" ليست قيمة يكتبها أحد، والكاشير الذي بدأ بصفر بالخطأ لا يجب أن
    // يُجبر على المسح.
    expect(value(), '5');
  });

  testWidgets('الفاصلة العشرية لا تتكرر', (tester) async {
    final value = await _pumpKeypad(tester);
    await tester.pump();

    await _tap(tester, '3');
    await _tap(tester, '.');
    await _tap(tester, '.');
    await _tap(tester, '5');

    expect(value(), '3.5');
  });

  testWidgets('الفاصلة أولاً تصبح صفراً وفاصلة', (tester) async {
    final value = await _pumpKeypad(tester);
    await tester.pump();

    await _tap(tester, '.');
    await _tap(tester, '7');

    expect(value(), '0.7');
  });

  testWidgets('حد الخانات بعد الفاصلة يُحترَم', (tester) async {
    final value = await _pumpKeypad(tester, decimalPlaces: 2);
    await tester.pump();

    await _tap(tester, '9');
    await _tap(tester, '.');
    await _tap(tester, '9');
    await _tap(tester, '9');
    await _tap(tester, '9'); // يُهمَل — قيمة نقدية بفلسين لا أكثر

    expect(value(), '9.99');
  });

  testWidgets('حد خانات العدد الصحيح يُحترَم', (tester) async {
    final value = await _pumpKeypad(tester, maxIntegerDigits: 3);
    await tester.pump();

    for (final d in ['1', '2', '3', '4']) {
      await _tap(tester, d);
    }

    expect(value(), '123');
  });

  testWidgets('المسح يفرّغ القيمة كلها والحذف حرفاً واحداً', (tester) async {
    final value = await _pumpKeypad(tester);
    await tester.pump();

    await _tap(tester, '4');
    await _tap(tester, '5');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(value(), '4');

    await _tap(tester, '7');
    await _tap(tester, 'مسح');
    expect(value(), '');
  });

  testWidgets('مفتاح 00 يضيف صفرين دفعة واحدة عند منع الكسور', (tester) async {
    // بلا كسور تظهر '00' مكان '.' — تُستخدم للمبالغ الكبيرة (500، 1000).
    final value = await _pumpKeypad(tester, allowDecimal: false);
    await tester.pump();

    await _tap(tester, '5');
    await _tap(tester, '00');

    // النداء المزدوج على الإضافة كان يقرأ قيمة قديمة فينتج "50" لا "500".
    expect(value(), '500');
  });

  testWidgets('00 بعد صفر وحده لا تنتج أصفاراً متراكمة', (tester) async {
    final value = await _pumpKeypad(tester, allowDecimal: false);
    await tester.pump();

    await _tap(tester, '0');
    await _tap(tester, '00');

    expect(value(), '0');
  });

  testWidgets('الكسور ممنوعة تعني عدم وجود مفتاح فاصلة', (tester) async {
    await _pumpKeypad(tester, allowDecimal: false);
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, '.'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '00'), findsOneWidget);
  });
}
