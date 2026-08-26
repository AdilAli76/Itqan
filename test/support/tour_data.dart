import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:kinetic_enterprise/core/network/api_client.dart';

/// مقاس جهاز في جولة اللقطات.
class TourDevice {
  const TourDevice(this.label, this.slug, this.size);
  final String label;
  final String slug;
  final Size size;
}

/// شاشة في الجولة.
class TourScreen {
  const TourScreen(this.route, this.label);
  final String route;
  final String label;
}

const kTourDevices = [
  TourDevice('سطح مكتب', 'desktop', Size(1600, 1100)),
  TourDevice('جهاز لوحي', 'tablet', Size(1024, 1366)),
  TourDevice('هاتف', 'phone', Size(430, 932)),
];

/// كل ما يسجّله screen_registry — بالترتيب الذي يراه المستخدم في القائمة.
const kTourScreens = [
  TourScreen('/dashboard', 'لوحة التحكم'),
  TourScreen('/pos', 'نقطة البيع'),
  TourScreen('/invoices', 'الفواتير'),
  TourScreen('/customers', 'العملاء'),
  TourScreen('/wallet-cards', 'بطاقات المحفظة'),
  TourScreen('/inventory', 'المخزون والموردون'),
  TourScreen('/purchasing', 'المشتريات'),
  TourScreen('/stock-transfer', 'تحويل المخزون'),
  TourScreen('/stock-count', 'الجرد الدوري'),
  TourScreen('/barcode-designer', 'مصمّم الباركود'),
  TourScreen('/reports', 'التقارير'),
  TourScreen('/audit-log', 'سجل التدقيق'),
  TourScreen('/notifications', 'الإشعارات'),
  TourScreen('/users', 'المستخدمون'),
  TourScreen('/permissions', 'مصفوفة الصلاحيات'),
  TourScreen('/branches', 'الفروع والهوية'),
  TourScreen('/settings', 'الإعدادات'),
  TourScreen('/license', 'الترخيص'),
  TourScreen('/support', 'الدعم الفني'),
  // شاشة مالك المنصّة لإدارة نشرات الأدوية (إصدار الصيدليات).
  TourScreen('/medicine-reference', 'نشرات الأدوية'),
  TourScreen('/prescriptions', 'دفتر الوصفات'),
  TourScreen('/reorder', 'إعادة الطلب'),
];

/// استثناءات رُصدت أثناء الجولة — تُجمَع ولا تُفشل، فتُصوَّر الشاشة بعطبها.
final List<String> kTourFindings = [];

/// يستبدل طبقة نقل Dio بمُعترِض يخدم العيّنات الملتقطة.
///
/// اعتراض النقل لا حقن المزوّدات: هكذا تمرّ الاستجابة بمسار التحليل الحقيقي
/// في كل مزوّد — وهو المسار الذي انكسر فعلاً حين تغيّر عقد نقاط النهاية إلى
/// مغلَّف صفحات. حقن المزوّدات كان سيتجاوز ذلك المسار تماماً فيُخفي الصنف
/// نفسه من الأعطال الذي جاءت الجولة لتكشفه.
class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this._dir) {
    final indexFile = File('${_dir.path}/_index.json');
    if (indexFile.existsSync()) {
      final raw = json.decode(indexFile.readAsStringSync()) as Map<String, dynamic>;
      _index = raw.map((k, v) => MapEntry(k, v as String));
    }
  }

  final Directory _dir;
  Map<String, String> _index = {};

  /// المسارات التي طُلبت ولا عيّنة لها — تُطبع في نهاية الجولة.
  final Set<String> missing = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // المسار بلا معاملات الاستعلام: العيّنة واحدة لكل نقطة نهاية، والترقيم
    // أو البحث لا يغيّر شكل الرد بل محتواه.
    final path = options.path.split('?').first;
    final key = path.startsWith('/') ? path : '/$path';

    final fileName = _index[key];
    if (fileName != null) {
      final file = File('${_dir.path}/$fileName');
      if (file.existsSync()) {
        return ResponseBody.fromString(
          file.readAsStringSync(),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }

    missing.add('${options.method} $key');
    // 404 لا خطأ شبكة: الشاشة تعرض حالة خطأ مفهومة بدل أن تعلق في التحميل
    // إلى الأبد، فتظهر في اللقطة كما يراها المستخدم عند فشل حقيقي.
    return ResponseBody.fromString(
      json.encode({'message': 'لا عيّنة لهذا المسار'}),
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

FixtureAdapter? _adapter;

/// يُركِّب المُعترِض على عميل الشبكة المشترك. يُستدعى مرّة قبل الجولة.
FixtureAdapter installFixtureAdapter() {
  final dir = Directory('test/support/fixtures');
  if (!dir.existsSync()) {
    throw StateError(
      'لا عيّنات في ${dir.path} — شغّل: python tool/capture_fixtures.py '
      'والخادم يعمل على المنفذ 5000',
    );
  }
  final adapter = FixtureAdapter(dir);

  // عنوان وهمي: العميل يبدأ بعنوان فارغ خارج الويب حتى يضبطه المستخدم
  // (راجع ApiClient.needsSetup)، وDio بعنوان فارغ يبني URI نسبياً فيسلك
  // مساراً مختلفاً قبل أن يصل المُعترِض. والعيّنات تُطابَق بالمسار وحده،
  // فأي مضيف يفي بالغرض.
  ApiClient.instance.dio.options.baseUrl = 'http://fixtures.test/api';
  ApiClient.instance.dio.httpClientAdapter = adapter;
  _adapter = adapter;
  return adapter;
}

FixtureAdapter? get fixtureAdapter => _adapter;
