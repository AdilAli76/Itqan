import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kinetic_enterprise/core/auth/permissions.dart';
import 'package:kinetic_enterprise/core/theme/app_colors.dart';
import 'package:kinetic_enterprise/core/theme/app_theme.dart';
import 'package:kinetic_enterprise/features/pos/data/pos_providers.dart';
import 'package:kinetic_enterprise/features/pos/presentation/pos_screen.dart';

/// إضافة عميل من داخل شاشة البيع.
///
/// الغرض التجاري وراء الاختبار: العميل يُضاف والزبون واقف أمام الكاشير. لو
/// تطلّبت إضافته مغادرة الشاشة لضاعت السلّة، فيتجاهل الكاشير الخطوة ويبيع
/// لـ«زبون نقدي» دائماً — وتموت قاعدة العملاء عملياً، ومعها المحافظ والرعاة
/// المبنيّة عليها.
///
/// ويحرس شرطاً أمنياً: الخادم يشترط customers.manage على POST /customers،
/// فالزر يجب أن يختفي لمن لا يملكها لا أن يردّ 403 عند كل ضغطة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpPicker(
    WidgetTester tester, {
    required bool canManageCustomers,
  }) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myPermissionsProvider.overrideWith((ref) async => UserPermissions(
                role: canManageCustomers ? 'branch_manager' : 'cashier',
                isSuperAdmin: false,
                codes: canManageCustomers ? {Perm.customersManage} : <String>{},
              )),
          // بلا شبكة: البحث يُرجع لا شيء، وهي الحالة التي يظهر فيها زر
          // الإضافة أصلاً — بحث فاشل ثم إضافة.
          posCustomerResultsProvider.overrideWith((ref) async => []),
          posProductResultsProvider.overrideWith((ref) async => []),
          posQuickPicksProvider.overrideWith((ref) async => []),
          posExpiryAlertProvider.overrideWith((ref, arg) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.build(const AppColors()),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: PosScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // فتح حوار اختيار العميل من أيقونة العميل في بطاقة الفاتورة.
    final personIcon = find.byIcon(Icons.person_outline);
    expect(personIcon, findsWidgets, reason: 'زر اختيار العميل غير موجود على شاشة البيع');
    await tester.tap(personIcon.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('زر «عميل جديد» يظهر لمن يملك customers.manage', (tester) async {
    await pumpPicker(tester, canManageCustomers: true);

    expect(find.text('اختيار عميل'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget,
        reason: 'زر الإضافة السريعة غير ظاهر لمن يملك الصلاحية');
  });

  testWidgets('الزر مخفيّ عمّن لا يملك الصلاحية — لا معطَّلاً', (tester) async {
    await pumpPicker(tester, canManageCustomers: false);

    expect(find.text('اختيار عميل'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1), findsNothing,
        reason: 'الخادم يردّ 403 على POST /customers بلا customers.manage، '
            'فبقاء الزر يعني ضغطة تفشل دائماً');
  });

  testWidgets('الضغط يفتح النموذج ويعبّئ الاسم بما كُتب في البحث', (tester) async {
    await pumpPicker(tester, canManageCustomers: true);

    // الكاشير بحث عن اسم فلم يجده — وهو المسار الذي يقود إلى الإضافة.
    //
    // مقصور على حقل داخل الحوار: شاشة البيع خلفه فيها حقل الباركود، و
    // byType(TextField).first كان يلتقطه هو لا حقل بحث العميل — فيمرّ
    // الاختبار بينما التعبئة المسبقة لا تعمل إطلاقاً.
    final searchField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'سالم أحمد');
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pump();

    expect(find.text('عميل جديد'), findsOneWidget);
    expect(find.text('حفظ واختيار'), findsOneWidget);
    expect(find.text('رجوع'), findsOneWidget);

    // إعادة كتابة الاسم بعد بحث فاشل خطوة ضائعة والزبون واقف.
    //
    // find.text لا widgetWithText: محتوى حقل الإدخال يرسمه EditableText لا
    // ودجت Text، فالبحث عن Text داخل TextFormField لا يجده أبداً. وحقل
    // البحث نفسه اختفى بالانتقال إلى النموذج، فلا التباس في المطابقة.
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('سالم أحمد')),
      findsOneWidget,
      reason: 'اسم العميل لم يُعبَّأ مسبقاً بما كُتب في البحث',
    );
  });

  testWidgets('الاسم حقل مطلوب — الحفظ بلا اسم يُرفض قبل أي طلب شبكة', (tester) async {
    await pumpPicker(tester, canManageCustomers: true);

    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pump();

    await tester.tap(find.text('حفظ واختيار'));
    await tester.pump();

    expect(find.text('الاسم مطلوب'), findsOneWidget);
    // بقي في النموذج ولم يُغلق الحوار.
    expect(find.text('عميل جديد'), findsOneWidget);
  });

  testWidgets('«رجوع» يعيد إلى البحث بلا إغلاق الحوار', (tester) async {
    await pumpPicker(tester, canManageCustomers: true);

    await tester.tap(find.byIcon(Icons.person_add_alt_1));
    await tester.pump();
    expect(find.text('عميل جديد'), findsOneWidget);

    await tester.tap(find.text('رجوع'));
    await tester.pump();

    expect(find.text('اختيار عميل'), findsOneWidget);
    expect(find.text('عميل جديد'), findsNothing);
  });
}
