import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kinetic_enterprise/core/theme/app_colors.dart';
import 'package:kinetic_enterprise/core/theme/app_theme.dart';
import 'package:kinetic_enterprise/features/pos/data/pos_providers.dart';
import 'package:kinetic_enterprise/features/pos/presentation/pos_screen.dart';

/// نقطة البيع مع نتائج بحث فعلية.
///
/// العطل الذي يحرسه هذا الاختبار لم يكن فيضاً بل توقّفاً كاملاً عن الرسم:
/// IntrinsicHeight يقيس أبعاداً جوهرية، وشبكة الأصناف عارض كسول يرفض ذلك،
/// فينهار التخطيط ويتبعه سيل من «Cannot hit test a render box that has never
/// been laid out».
///
/// ولم يظهر قط في أي اختبار سابق لسبب واحد: كل الاختبارات تفتح الشاشة
/// بنتائج فارغة. الشبكة لا تُبنى أصلاً فلا يقع التعارض. الاختبار هنا يحقن
/// نتائج حقيقية — وهذا وحده ما يعيد إنتاج ما رآه المستخدم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  /// أصناف بشكل ProductInventoryDto كما يعيده الخادم فعلياً.
  List<Map<String, dynamic>> products(int n) => List.generate(
        n,
        (i) => {
          'id': '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
          'sku': 'SKU-$i',
          'barcode': '600000000$i',
          'name': 'صنف تجريبي $i',
          'unitBase': 'piece',
          'costPrice': 10.0 + i,
          'salePrice': 15.0 + i,
          'trackExpiry': false,
          'reorderLevel': 5,
          'categoryId': null,
          'categoryName': null,
          'supplierId': null,
          'supplierName': null,
          'quantity': 20.0,
          'nearestExpiry': null,
          'tracksStock': true,
        },
      );

  Future<void> pumpPos(WidgetTester tester, Size size, List<Map<String, dynamic>> found) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // حقن النتائج مباشرةً: الغرض فحص التخطيط لا الشبكة.
          posProductResultsProvider.overrideWith((ref) async => found),
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
    // إطاران: الأول للهيكل، والثاني بعد اكتمال المزوّد وبناء الشبكة.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('نقطة البيع ترسم نتائج البحث بلا انهيار', () {
    // سطح المكتب هو المسار الذي كان ينهار: هو وحده يلفّ اللوحتين بصفّ.
    for (final entry in {
      'سطح مكتب': const Size(1600, 1000),
      'جهاز لوحي': const Size(1100, 800),
      'هاتف': const Size(420, 900),
    }.entries) {
      testWidgets('${entry.key}: ستة أصناف', (tester) async {
        await pumpPos(tester, entry.value, products(6));

        final error = tester.takeException();
        expect(error, isNull,
            reason: 'انهار التخطيط عند عرض النتائج على ${entry.key}');
      });
    }

    testWidgets('نتيجة واحدة لا تنهار', (tester) async {
      await pumpPos(tester, const Size(1600, 1000), products(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('قائمة طويلة (٣٠ صنفاً) لا تنهار', (tester) async {
      // الطول هو ما يجعل الشبكة تتجاوز أي ارتفاع مفترض.
      await pumpPos(tester, const Size(1600, 1000), products(30));
      expect(tester.takeException(), isNull);
    });

    testWidgets('بلا نتائج — الحالة التي كانت تُختبَر وحدها فتُخفي العطل',
        (tester) async {
      await pumpPos(tester, const Size(1600, 1000), const []);
      expect(tester.takeException(), isNull);
    });
  });
}
