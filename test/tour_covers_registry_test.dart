import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/tour_data.dart';

/// جولة اللقطات تغطّي **كل** شاشة مسجَّلة.
///
/// **العطب الذي يمسكه:** `kTourScreens` قائمة تُكتب باليد، وتعليقها يقول
/// «كل ما يسجّله screen_registry» — ولا شيء كان يفرض ذلك. فأُضيفت شاشات
/// المصروفات والمحاسبة والشركات المشترَكة ولم تدخل الجولة، فبقيت **بلا أي
/// اختبار يفتحها**. وواحدة منها كانت تطلب مساراً خاطئاً من الخادم
/// (`/platform` بدل `/platform/organizations`) ولم يكتشفه شيء حتى فتحها
/// مستخدم على هاتفه.
///
/// <para>وقائمةٌ تُكتب باليد تتخلّف دائماً — الحارس هو ما يجعل التخلّف
/// مستحيلاً. نفس مبرر [StockLedger] و[LicenseLimits]: نقطة اختناق واحدة
/// مضمونة هندسياً، لا رهانٌ على انتباه من يضيف الشاشة القادمة.</para>
void main() {
  test('كل مسار في screen_registry موجود في جولة اللقطات', () {
    final source = File('lib/core/shell/screen_registry.dart').readAsStringSync();

    // `case '/x':` — الشكل الوحيد الذي يسجّل به الملف شاشةً.
    final registered = RegExp(r"case\s+'(/[^']+)'\s*:")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    expect(registered, isNotEmpty,
        reason: 'تعذّرت قراءة المسارات من screen_registry — تغيّر شكل الملف؟');

    final toured = kTourScreens.map((s) => s.route).toSet();
    final missing = registered.difference(toured).toList()..sort();

    expect(missing, isEmpty,
        reason: 'شاشات مسجَّلة وخارج الجولة — تُضاف إلى kTourScreens في '
            'test/support/tour_data.dart:\n  ${missing.join('\n  ')}');
  });

  test('لا مسار في الجولة بلا شاشة مسجَّلة', () {
    final source = File('lib/core/shell/screen_registry.dart').readAsStringSync();
    final registered = RegExp(r"case\s+'(/[^']+)'\s*:")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    final toured = kTourScreens.map((s) => s.route).toSet();
    final stale = toured.difference(registered).toList()..sort();

    // مسارٌ حُذف من التسجيل وبقي في الجولة يُنتج لقطةً لشاشة لم تعد موجودة
    // — تمرّ خضراء وتُخفي أن الشاشة اختفت.
    expect(stale, isEmpty,
        reason: 'مسارات في الجولة بلا شاشة مسجَّلة:\n  ${stale.join('\n  ')}');
  });
}
