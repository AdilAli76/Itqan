import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// يحرس تبديل الحساب على نفس الجهاز.
///
/// **العطب الذي يمسكه:** مُوفِّرات الصلاحيات ودعوى مالك المنصّة تُخزَّن
/// لعمر التطبيق، ولا شيء يخبرها أن المستخدم تبدّل. فمن خرج ودخل بحسابٍ
/// آخر يبقى على صلاحيات الأوّل — وقع فعلاً: مدير منظمةٍ عادية رأى بنود
/// المنصّة، ومالك المنصّة لم يرها.
///
/// ولا تمسكه لقطةٌ ولا تحليلٌ ساكن: الشاشة تُبنى صحيحةً في كل الحالات،
/// والخطأ في **ما تقرؤه** لا في كيف تعرضه. فيُقاس هنا بالبطلان نفسه:
/// هل يُعاد حساب المُوفِّر بعد استدعاء الإبطال؟
void main() {
  test('إبطال مُوفِّرات المستخدم يُعيد حسابها', () async {
    var reads = 0;

    // نظير isPlatformAdminProvider: مُوفِّرٌ يقرأ من مصدرٍ خارجي مرّةً
    // ويُخزَّن. المقيس أنّ الإبطال يُجبره على قراءةٍ جديدة.
    final probe = FutureProvider<int>((ref) async => ++reads);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(probe.future), 1);
    // قراءةٌ ثانية بلا إبطال تُرجع المخزَّن — وهذا سبب العطب.
    expect(await container.read(probe.future), 1);

    container.invalidate(probe);
    expect(await container.read(probe.future), 2,
        reason: 'بلا إبطال تبقى قيمة الحساب السابق بعد تبديل المستخدم');
  });

  test('الإبطال يُستدعى في الدخول والخروج معاً', () {
    // يُقرأ من الملفّين لا من نصٍّ مكتوب هنا: اختبارٌ يفحص ثابتاً كتبه
    // كاتبه لا يفحص شيئاً.
    final login = File('lib/features/auth/presentation/login_screen.dart').readAsStringSync();
    final logout = File('lib/core/shell/open_tabs_provider.dart').readAsStringSync();

    expect(login.contains('invalidateUserScopedProviders'), isTrue,
        reason: 'الدخول بلا إبطال يُبقي صلاحيات الحساب السابق');
    expect(logout.contains('invalidateUserScopedProviders'), isTrue,
        reason: 'الخروج بلا إبطال يُبقي صلاحيات الخارج لمن يدخل بعده');
  });

  test('الدالة تُبطل كل مُوفِّر يخصّ المستخدم', () {
    final source = File('lib/core/auth/permissions.dart').readAsStringSync();
    final body = source.substring(source.indexOf('void invalidateUserScopedProviders'));

    // حذفُ أحدها لاحقاً لا يُنتج خطأ ترجمة ولا يُسقط شاشة — يُنتج حساباً
    // يرى صلاحيات غيره. فيُثبَّت هنا.
    for (final p in [
      'myPermissionsProvider',
      'isPlatformAdminProvider',
      // أُضيفا مع مهندسي البيع: مهندسٌ يدخل بعد مالك كان يرى أزرار
      // المالك، ورقم ترخيص سابقه يُطبع في عقد عميله هو.
      'isPlatformOwnerProvider',
      'resellerLicenseProvider',
      'brandingProvider',
    ]) {
      expect(body.contains('ref.invalidate($p)'), isTrue, reason: '$p لا يُبطَل');
    }
  });
}
