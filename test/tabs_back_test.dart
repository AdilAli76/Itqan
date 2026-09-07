import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/core/shell/open_tabs_provider.dart';

/// زرّ الرجوع في الهاتف.
///
/// <para><b>الشكوى التي يعالجها:</b> «عند الرجوع في الهاتف النظام يُغلق
/// تماماً». وسببها بنيويّ: بعد الدخول لا مسار في الموجّه إلا <c>/app</c>
/// وحده، والتنقّل كلّه بين تبويبات في الذاكرة — فلا يجد النظام ما يرجع
/// إليه، فتذهب الضغطة إلى أندرويد وأندرويد يفهمها «اخرج».</para>
///
/// <para>والاختبار على [OpenTabsNotifier] وحده لا على الشاشة: المنطق كلّه
/// هنا، وضغطة الرجوع لا تُحاكى في اختبار ودجات إلا بتزييفٍ يختبر التزييف.
/// </para>
void main() {
  OpenTabsNotifier notifierWith(List<String> routes) {
    final notifier = OpenTabsNotifier();
    for (final route in routes) {
      notifier.open(route, title: route, icon: Icons.circle);
    }
    return notifier;
  }

  group('الرجوع يمشي في التاريخ', () {
    test('يرجع إلى التبويب السابق لا إلى الأوّل', () {
      final tabs = notifierWith(['/dashboard', '/pos', '/invoices']);
      expect(tabs.state.activeRoute, '/invoices');

      expect(tabs.back(), isTrue);
      expect(tabs.state.activeRoute, '/pos');

      expect(tabs.back(), isTrue);
      expect(tabs.state.activeRoute, '/dashboard');
    });

    test('وينتهي التاريخ فيردّ false — عندها تتولّى القشرة', () {
      // القيمة تُقرأ في [AppShell]: false تعني «لا شيء أرجع إليه»، فتُعرض
      // رسالة الخروج بدل إغلاقٍ صامت.
      final tabs = notifierWith(['/dashboard']);
      expect(tabs.back(), isFalse);
      expect(tabs.state.activeRoute, '/dashboard');
    });
  });

  group('التاريخ لا يتضخّم', () {
    test('التنقّل بين شاشتين مراراً لا يُراكم ضغطات رجوع', () {
      // العطب الذي يمسكه: بلا إسقاط المكرّر، من تنقّل بين شاشتين عشر مرّات
      // يحتاج عشر ضغطات ليخرج من الثانية — فيظنّ الزرّ معطّلاً.
      final tabs = notifierWith(['/dashboard', '/pos']);
      for (var i = 0; i < 5; i++) {
        tabs.activate('/dashboard');
        tabs.activate('/pos');
      }
      expect(tabs.state.history.length, lessThanOrEqualTo(2));

      expect(tabs.back(), isTrue);
      expect(tabs.state.activeRoute, '/dashboard');
    });

    test('وتنشيط التبويب النشط لا يُسجَّل', () {
      final tabs = notifierWith(['/dashboard', '/pos']);
      final before = tabs.state.history.length;
      tabs.activate('/pos');
      expect(tabs.state.history.length, before);
    });
  });

  group('تبويبٌ أُغلق لا يُرجَع إليه', () {
    test('الرجوع يتخطّاه إلى ما قبله', () {
      // فتحُ شاشةٍ أغلقها صاحبها عمداً ليس «رجوعاً» — هو مفاجأة.
      final tabs = notifierWith(['/dashboard', '/pos', '/invoices']);
      tabs.close('/pos');

      expect(tabs.back(), isTrue);
      expect(tabs.state.activeRoute, '/dashboard');
    });

    test('وإغلاق النشط ينقل إلى غيره بلا أن يُفسد التاريخ', () {
      final tabs = notifierWith(['/dashboard', '/pos']);
      tabs.close('/pos');
      expect(tabs.state.activeRoute, '/dashboard');
      expect(tabs.state.history, isNot(contains('/pos')));
    });
  });
}
