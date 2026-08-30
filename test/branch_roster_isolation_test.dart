import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic_enterprise/core/network/branch_roster_store.dart';

/// عزل كشف بطاقات الفرع بين المنظمات والفروع.
///
/// <para><b>العطب الذي يمسكه:</b> نفس عطب طابور البيع المؤجَّل بالضبط —
/// مفتاحٌ عامّ واحد على الجهاز يجعل كشف منظمةٍ يظهر لمن يدخل من منظمةٍ
/// أخرى. وهنا الأثر أخطر: الكشف يحمل **أسماء المنتسبين وأرصدتهم**، لا
/// عدّاداً فقط.</para>
///
/// <para>وفرعان في المنظمة نفسها يجب أن يفترقا أيضاً: بطاقةٌ خارج كشف
/// الفرع لا تُسحَب فيه — وهذا هو ما يمنع السحب المزدوج أثناء الانقطاع.</para>
void main() {
  const orgA = '11111111-1111-1111-1111-111111111111';
  const orgB = '22222222-2222-2222-2222-222222222222';
  const branch1 = 'aaaaaaaa-0000-0000-0000-000000000001';
  const branch2 = 'aaaaaaaa-0000-0000-0000-000000000002';

  TestWidgetsFlutterBinding.ensureInitialized();

  RosterCard card(String code, double balance) => RosterCard(
        customerId: 'c-$code',
        fullName: 'منتسب $code',
        cardCode: code,
        balance: balance,
        dailyCap: 0,
      );

  /// يكتب كشفاً مباشرةً بالمفتاح الذي يستعمله المخزن.
  Future<void> seed(String orgId, String branchId, List<RosterCard> cards) async {
    final values = <String, String>{
      'kinetic_jwt_token': _jwt(orgId),
      'branch_roster_${orgId}_$branchId': json.encode({
        'updatedAt': DateTime(2026, 8, 25).toIso8601String(),
        'cards': cards.map((c) => c.toJson()).toList(),
      }),
    };
    FlutterSecureStorage.setMockInitialValues(values);
  }

  test('كشف منظمة لا يظهر لمنظمة أخرى على الجهاز نفسه', () async {
    await seed(orgA, branch1, [card('AAA111', 500)]);

    final storeA = BranchRosterNotifier(const FlutterSecureStorage());
    await storeA.load(branch1);
    expect(storeA.state.cards, hasLength(1));
    expect(storeA.state.byCode('AAA111')?.balance, 500);

    // نفس الجهاز ونفس الفرع، لكن مستخدم منظمة أخرى.
    FlutterSecureStorage.setMockInitialValues({'kinetic_jwt_token': _jwt(orgB)});
    final storeB = BranchRosterNotifier(const FlutterSecureStorage());
    await storeB.load(branch1);

    expect(storeB.state.cards, isEmpty,
        reason: 'أسماء المنتسبين وأرصدتهم لا تُعرَض لمنظمة أخرى');
  });

  test('كشف فرع لا يُقرأ في فرعٍ آخر', () async {
    await seed(orgA, branch1, [card('AAA111', 500)]);

    final store = BranchRosterNotifier(const FlutterSecureStorage());
    await store.load(branch2);

    // البطاقة مربوطة بفرع، والفرع يملك بياناتها وحده — وهذا ما يجعل
    // الكاتب واحداً فلا يُخصَم منها في فرعين معاً أثناء الانقطاع.
    expect(store.state.cards, isEmpty);
    expect(store.state.byCode('AAA111'), isNull);
  });

  test('بلا توكن لا كشف — بيانات قبل الدخول لا تخصّ أحداً', () async {
    FlutterSecureStorage.setMockInitialValues(const {});

    final store = BranchRosterNotifier(const FlutterSecureStorage());
    await store.load(branch1);

    expect(store.state.cards, isEmpty);
  });

  test('السحب المحلّي يُنقص الرصيد ويبقى بعد إعادة التشغيل', () async {
    await seed(orgA, branch1, [card('AAA111', 500), card('BBB222', 80)]);

    final store = BranchRosterNotifier(const FlutterSecureStorage());
    await store.load(branch1);
    await store.debitLocally('c-AAA111', 120);

    expect(store.state.byCode('AAA111')?.balance, 380);
    // والأخرى لم تُمَسّ.
    expect(store.state.byCode('BBB222')?.balance, 80);

    // مثيلٌ جديد يقرأ من التخزين نفسه — كأن التطبيق أُعيد تشغيله.
    //
    // وبلا الحفظ كان سحبان متتاليان بلا اتصال يريان الرصيد الكامل كلاهما،
    // فيخرج ضعف ما في البطاقة.
    final again = BranchRosterNotifier(const FlutterSecureStorage());
    await again.load(branch1);
    expect(again.state.byCode('AAA111')?.balance, 380);
  });

  test('البحث بالرمز لا يتأثّر بحالة الأحرف', () async {
    await seed(orgA, branch1, [card('AbC123', 90)]);

    final store = BranchRosterNotifier(const FlutterSecureStorage());
    await store.load(branch1);

    // الرمز يصل من قارئ باركود أو من كتابةٍ يدوية — والحالة تختلف.
    expect(store.state.byCode('abc123')?.balance, 90);
    expect(store.state.byCode('  ABC123 ')?.balance, 90);
  });

  test('كشف تالف لا يمنع إقلاع نقطة البيع', () async {
    FlutterSecureStorage.setMockInitialValues({
      'kinetic_jwt_token': _jwt(orgA),
      'branch_roster_${orgA}_$branch1': 'ليس JSON',
    });

    final store = BranchRosterNotifier(const FlutterSecureStorage());
    await store.load(branch1);

    // تبدأ بلا سحبٍ غير متّصل — لا تسقط الشاشة.
    expect(store.state.cards, isEmpty);
    expect(store.state.branchId, branch1);
  });
}

String _jwt(String organizationId) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');
  return '${seg({'alg': 'none', 'typ': 'JWT'})}'
      '.${seg({'organization_id': organizationId, 'role': 'super_admin'})}'
      '.signature';
}
