import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/core/network/api_client.dart';
import 'package:kinetic_enterprise/core/shell/screen_registry.dart';
import 'package:kinetic_enterprise/core/theme/app_theme.dart';
import 'package:kinetic_enterprise/core/theme/app_colors.dart';
import 'package:kinetic_enterprise/core/time/app_clock.dart';
import 'support/tour_data.dart';

/// ============================================================================
///  فحص بصري آلي لكل شاشات النظام
///
///  ما يفحصه فعلاً — لا آراء بل قياسات:
///
///  ١. **الفيض (Overflow):** Flutter يرمي استثناءً عند تجاوز المحتوى حدوده،
///     فيلتقطه الاختبار. هذا ما كشف خللين حقيقيين في شاشة الدخول سابقاً.
///  ٢. **أهداف اللمس:** كل زر/أيقونة قابلة للنقر تُقاس فعلياً بعد الرسم،
///     ويُبلَّغ عن كل ما هو أصغر من 44 نقطة (أدنى ما توصي به إرشادات
///     Material و Apple معاً). هذا هو الفرق بين نظام يُستعمل بالإصبع
///     ونظام يحتاج فأرة.
///  ٣. **ثلاثة أحجام شاشة:** هاتف وجهاز لوحي وسطح مكتب — نظام يُباع
///     للاستخدام على شاشات كاشير لمس وأجهزة مكتبية معاً.
///
///  الشبكة والتخزين الآمن كلاهما محاكى، فلا يحتاج الفحص سيرفراً ولا حساباً
///  ولا اتصالاً — يعمل في أي وقت وعلى أي جهاز، وهذا شرط أن يبقى مُستخدَماً.
/// ============================================================================

/// مقاسات حقيقية لا أرقام مختارة عشوائياً.
const _viewports = <String, Size>{
  'هاتف (Galaxy A36)': Size(1080, 2340),
  'جهاز لوحي': Size(1600, 2560),
  'سطح مكتب': Size(1920, 1080),
};

const _pixelRatios = <String, double>{
  'هاتف (Galaxy A36)': 2.8,
  'جهاز لوحي': 2.0,
  'سطح مكتب': 1.0,
};

/// من قائمة الجولة نفسها لا قائمة ثانية.
///
/// **العطب الذي يصلحه:** كانت هنا قائمة مكتوبة باليد **ثالثة** (بعد
/// screen_registry وkTourScreens)، فتخلّفت عن الاثنتين. وشاشةٌ خارج القوائم
/// لا يفتحها اختبار قطّ — فبقيت المصروفات والمحاسبة والشركات المشترَكة بلا
/// أي فحص، وواحدة منها تطلب مساراً خاطئاً من الخادم.
///
/// وقائمةٌ واحدة محروسة بـtour_covers_registry_test خيرٌ من ثلاث تتفرّق.
final _routes = kTourScreens.map((s) => s.route).toList();

/// أصغر هدف لمس موصى به. القيمة من إرشادات Material (48dp) و Apple (44pt)؛
/// أخذنا الأصغر لتفادي بلاغات لا تنتهي على تصميم مبني للفأرة أصلاً.
const _minTapTarget = 44.0;

final _findings = <String>[];

void main() {
  setUpAll(() {
    // تخزين آمن محاكى + توكن وهمي بادّعاءات مدير عام. الكود يفكّ الحمولة
    // ولا يتحقق من التوقيع (يتحقق منه السيرفر)، فتوكن مُركَّب يكفي هنا.
    AppClock.freeze(DateTime(2026, 8, 25, 12));

    FlutterSecureStorage.setMockInitialValues({
      'kinetic_jwt_token': _fakeJwt({
        'organization_id': '00000000-0000-0000-0000-000000000001',
        'role': 'super_admin',
        'branch_id': null,
      }),
    });

    // اعتراض الشبكة على مستوى المحوّل: لا تعديل في كود الإنتاج، ولا طلب
    // حقيقي يخرج من الاختبار.
    ApiClient.instance.dio.httpClientAdapter = _MockAdapter();
  });

  tearDownAll(() {
    if (_findings.isEmpty) {
      debugPrint('\n=== لا ملاحظات ===\n');
      return;
    }
    debugPrint('\n${'=' * 78}');
    debugPrint('ملاحظات الفحص البصري (${_findings.length})');
    debugPrint('=' * 78);
    for (final f in _findings) {
      debugPrint(f);
    }
    debugPrint('${'=' * 78}\n');
  });

  for (final entry in _viewports.entries) {
    group(entry.key, () {
      for (final route in _routes) {
        testWidgets('$route يُرسَم دون فيض', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = _pixelRatios[entry.key]!;
          addTearDown(tester.view.reset);

          await _pumpScreen(tester, route);

          // أي فيض أو استثناء أثناء الرسم يظهر هنا.
          final error = tester.takeException();
          if (error != null) {
            _findings.add('[فيض/استثناء] ${entry.key} ← $route\n    $error');
          }
          expect(error, isNull, reason: 'الشاشة $route تفيض على ${entry.key}');
        });

        testWidgets('$route أهداف اللمس', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = _pixelRatios[entry.key]!;
          addTearDown(tester.view.reset);

          await _pumpScreen(tester, route);
          tester.takeException(); // الأخطاء يُبلَّغ عنها في الاختبار الآخر

          final small = _smallTapTargets(tester);
          if (small.isNotEmpty) {
            final sample = small.take(4).join('، ');
            _findings.add('[هدف لمس صغير] ${entry.key} ← $route: '
                '${small.length} عنصر أصغر من ${_minTapTarget.toInt()} نقطة ($sample)');
          }
        });
      }
    });
  }
}

Future<void> _pumpScreen(WidgetTester tester, String route) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.build(const AppColors()),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: buildScreenForRoute(route),
      ),
    ),
  );

  // إطارات إضافية لتصل المزوّدات غير المتزامنة إلى حالتها النهائية.
  // pumpAndSettle يتعطّل على الشاشات ذات المؤشرات الدائمة الدوران.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// يقيس كل عنصر قابل للنقر بعد الرسم فعلياً — لا بالاعتماد على ما هو مكتوب
/// في الكود، بل على حجمه الحقيقي على الشاشة.
List<String> _smallTapTargets(WidgetTester tester) {
  final results = <String>[];
  final seen = <String>{};

  for (final type in [IconButton, InkWell, OutlinedButton, TextButton, ElevatedButton, FilledButton]) {
    for (final element in find.byType(type).evaluate()) {
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final size = _effectiveTapSize(element, renderObject);
      if (size.isEmpty) continue;
      if (size.width >= _minTapTarget && size.height >= _minTapTarget) continue;

      // اسم الودجت المحيط: بلاغ "زر صغير" بلا موضعه لا يُصلَح. نصعد في
      // الشجرة حتى أول ودجت من كود المشروع (تبدأ أسماؤه الخاصة بشرطة
      // سفلية، أو ينتهي اسمه بـ Screen/Card/Tile) ونذكره في البلاغ.
      final owner = _nearestProjectWidget(element);
      final label = '$type ${size.width.toStringAsFixed(0)}×${size.height.toStringAsFixed(0)}'
          '${owner == null ? '' : ' في $owner'}';
      if (seen.add(label)) results.add(label);
    }
  }
  return results;
}

/// حجم هدف اللمس **الفعّال** لا حجم صندوق الحبر.
///
/// Material يلفّ المفاتيح ومربّعات الاختيار وأزرار الأيقونات بغلاف
/// (_InputPadding وأمثاله) يوسّع منطقة النقر إلى 48 بينما يبقى الشكل
/// المرسوم أصغر. قياس الصندوق الداخلي وحده كان يُنتج بلاغات كاذبة عن
/// عناصر هدفها سليم أصلاً — والأداة التي تُنذر كذباً يتوقف الناس عن
/// تصديقها، فتصبح أسوأ من عدمها.
Size _effectiveTapSize(Element element, RenderBox self) {
  var best = self.size;
  var hops = 0;

  element.visitAncestorElements((ancestor) {
    if (hops++ > 3) return false;
    final parent = ancestor.renderObject;
    if (parent is! RenderBox || !parent.hasSize) return true;

    final name = ancestor.widget.runtimeType.toString();
    // أغلفة التوسيع المعروفة في Material فقط — لا أي أب أكبر مصادفةً،
    // وإلا ابتلع الغلافُ الخارجي كلَّ بلاغ حقيقي.
    const padders = ['_InputPadding', 'ConstrainedBox', 'Padding', 'IconButton', 'Tooltip'];
    if (!padders.any(name.startsWith)) return true;

    final size = parent.size;
    if (size.width > best.width || size.height > best.height) {
      best = Size(
        size.width > best.width ? size.width : best.width,
        size.height > best.height ? size.height : best.height,
      );
    }
    return true;
  });

  return best;
}

/// يصعد في شجرة الودجتات بحثاً عن أقرب ودجت من كود المشروع — لتحديد موضع
/// العنصر المُبلَّغ عنه بدل ترك المطوّر يبحث عنه في عشرين ملفاً.
String? _nearestProjectWidget(Element element) {
  String? found;
  var hops = 0;

  element.visitAncestorElements((ancestor) {
    if (hops++ > 25) return false;
    final name = ancestor.widget.runtimeType.toString();
    // ودجتات إطار Flutter الخاصة تبدأ بشرطة سفلية أيضاً، فتُستبعَد صراحةً
    // وإلا صار كل بلاغ يشير إلى _InheritedTheme بلا فائدة.
    const frameworkPrefixes = [
      '_Inherited', '_SingleChild', '_Render', '_Effective', '_Body',
      '_Modal', '_Theme', '_Focus', '_Scroll', '_Material', '_Ink',
      '_ShapeBorder', '_Exclusive', '_Gesture', '_Selection', '_Actions',
      '_Semantics', '_Parent', '_Layout',
    ];
    if (frameworkPrefixes.any(name.startsWith)) return true;

    // ودجتات المشروع: الخاصة تبدأ بشرطة سفلية، والعامة تنتهي بلاحقة معروفة.
    if (name.startsWith('_') ||
        name.endsWith('Screen') ||
        name.endsWith('Card') ||
        name.endsWith('Table') ||
        name.endsWith('Sidebar') ||
        name.endsWith('Navbar')) {
      found = name;
      return false;
    }
    return true;
  });

  return found;
}

String _fakeJwt(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');
  return '${seg({'alg': 'none', 'typ': 'JWT'})}.${seg(claims)}.signature';
}

/// محوّل شبكة محاكى — يردّ حمولات معقولة الشكل لكل نقطة نهاية يستدعيها
/// النظام. الهدف رسم الشاشات لا محاكاة منطق السيرفر، فالقوائم تُردّ فارغة
/// أو بعنصر واحد يكفي لظهور الجدول ورأسه وحالته الفارغة.
class _MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final body = _bodyFor(path);

    return ResponseBody.fromString(
      json.encode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Object _bodyFor(String path) {
    if (path.contains('/organizations/me/settings')) {
      return {
        'currencyCode': 'LYD',
        'currencySymbol': 'د.ل',
        'locale': 'ar',
        'taxRate': 0,
        'passwordMinLength': 8,
        'receiptWidthMm': 80,
        'posAllowOpenProduct': true,
      };
    }
    if (path.contains('/organizations/me/barcode-template')) {
      return {'widthMm': 40, 'heightMm': 25, 'showName': true, 'showPrice': true, 'showSku': false};
    }
    if (path.contains('/organizations/me')) {
      return {
        'displayName': 'منظمة الاختبار',
        'logoUrl': null,
        'primaryColor': '#0B2540',
        'secondaryColor': '#C8952B',
        'currencySymbol': 'د.ل',
        'navLayout': 'sidebar',
      };
    }
    if (path.contains('/licenses')) {
      return {
        'planTier': 'standard',
        'status': 'active',
        'expiresAt': '2027-01-01T00:00:00Z',
        'maxBranches': 3,
        'maxUsers': 10,
        'currentBranches': 1,
        'currentUsers': 2,
        'enabledModules': ['inventory', 'pos'],
      };
    }
    if (path.contains('/permissions')) {
      return [
        {'code': 'inventory.manage', 'labelAr': 'إدارة المنتجات', 'module': 'inventory'},
        {'code': 'pos.price_override', 'labelAr': 'البيع بسعر مخالف', 'module': 'pos'},
      ];
    }
    if (path.contains('/reports')) {
      return {'totalSales': 0, 'invoiceCount': 0, 'items': [], 'branches': [], 'cashiers': []};
    }
    // بقية النقاط قوائم — الحالة الفارغة هي أكثر ما يُرى فعلياً عند
    // التسليم، وهي أكثر ما يُنسى تصميمه.
    return <dynamic>[];
  }

  @override
  void close({bool force = false}) {}
}
