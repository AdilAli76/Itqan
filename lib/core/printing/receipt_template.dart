import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../network/api_client.dart';

/// مقاسات ورق الإيصال — تُطابق `ReceiptPapers` في الخادم.
class ReceiptPapers {
  const ReceiptPapers._();

  static const roll80 = 'roll80';
  static const roll58 = 'roll58';
  static const a4 = 'a4';
  static const a5 = 'a5';

  static const all = [roll80, roll58, a4, a5];

  static String labelOf(String paper) => switch (paper) {
        roll58 => 'لفّة حرارية 58 ملم',
        a4 => 'ورق رسمي A4',
        a5 => 'ورق رسمي A5',
        _ => 'لفّة حرارية 80 ملم',
      };

  /// أبعاد الصفحة لمكتبة الطباعة.
  ///
  /// <para>اللفّة طولها **لا نهائي** لا مقاسٌ ثابت: الإيصال يطول بعدد
  /// الأصناف، وتثبيت الطول يقصّ فاتورة العشرين صنفاً.</para>
  static PdfPageFormat formatOf(String paper) => switch (paper) {
        roll58 => const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity,
            marginAll: 3 * PdfPageFormat.mm),
        a4 => PdfPageFormat(PdfPageFormat.a4.width, PdfPageFormat.a4.height,
            marginAll: 14 * PdfPageFormat.mm),
        a5 => PdfPageFormat(PdfPageFormat.a5.width, PdfPageFormat.a5.height,
            marginAll: 10 * PdfPageFormat.mm),
        _ => const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
            marginAll: 4 * PdfPageFormat.mm),
      };

  /// هل هذا المقاس لفّة حرارية؟
  ///
  /// <para>يقرّر حجم الخطّ والتخطيط: ٥٨ ملم عرضٌ لا يتّسع لجدولٍ بأعمدة،
  /// وA4 صفحةٌ يبدو عليها خطّ الثمانية نقاط ضائعاً.</para>
  static bool isRoll(String paper) => paper == roll80 || paper == roll58;
}

/// قالب الإيصال كما تحفظه المنظمة، ومعه ما يملأه.
class ReceiptTemplate {
  const ReceiptTemplate({
    this.paper = ReceiptPapers.roll80,
    this.showLogo = true,
    this.showTaxNumber = true,
    this.showCommercialRegistry = false,
    this.showQr = false,
    this.headerText,
    this.footerText = 'شكراً لتعاملكم معنا',
    this.taxNumber,
    this.commercialRegistry,
    this.logoUrl,
  });

  final String paper;
  final bool showLogo;
  final bool showTaxNumber;
  final bool showCommercialRegistry;
  final bool showQr;
  final String? headerText;
  final String? footerText;

  /// تُقرأ من المنظمة لا من القالب: القالب يقرّر أتُعرض، لا ما قيمتها.
  final String? taxNumber;
  final String? commercialRegistry;
  final String? logoUrl;

  /// الافتراضي — يُستعمل حين يفشل التحميل، فتبقى الطباعة ممكنة.
  ///
  /// <para>إيصالٌ بلا شعار أهون من كاشيرٍ لا يستطيع الطباعة لأن الشبكة
  /// انقطعت لحظة قراءة القالب.</para>
  static const fallback = ReceiptTemplate();

  factory ReceiptTemplate.fromJson(Map<String, dynamic> json) {
    final template = Map<String, dynamic>.from(
        (json['template'] as Map?) ?? const <String, dynamic>{});
    final paper = template['paper'] as String?;

    return ReceiptTemplate(
      paper: ReceiptPapers.all.contains(paper) ? paper! : ReceiptPapers.roll80,
      showLogo: template['showLogo'] as bool? ?? true,
      showTaxNumber: template['showTaxNumber'] as bool? ?? true,
      showCommercialRegistry: template['showCommercialRegistry'] as bool? ?? false,
      showQr: template['showQr'] as bool? ?? false,
      headerText: template['headerText'] as String?,
      footerText: template['footerText'] as String?,
      taxNumber: json['taxNumber'] as String?,
      commercialRegistry: json['commercialRegistry'] as String?,
      logoUrl: json['logoUrl'] as String?,
    );
  }

  ReceiptTemplate copyWith({
    String? paper,
    bool? showLogo,
    bool? showTaxNumber,
    bool? showCommercialRegistry,
    bool? showQr,
    String? headerText,
    String? footerText,
    String? taxNumber,
    String? commercialRegistry,
  }) =>
      ReceiptTemplate(
        paper: paper ?? this.paper,
        showLogo: showLogo ?? this.showLogo,
        showTaxNumber: showTaxNumber ?? this.showTaxNumber,
        showCommercialRegistry: showCommercialRegistry ?? this.showCommercialRegistry,
        showQr: showQr ?? this.showQr,
        headerText: headerText ?? this.headerText,
        footerText: footerText ?? this.footerText,
        taxNumber: taxNumber ?? this.taxNumber,
        commercialRegistry: commercialRegistry ?? this.commercialRegistry,
        logoUrl: logoUrl,
      );

  Map<String, dynamic> toRequest() => {
        'paper': paper,
        'showLogo': showLogo,
        'showTaxNumber': showTaxNumber,
        'showCommercialRegistry': showCommercialRegistry,
        'showQr': showQr,
        'headerText': headerText,
        'footerText': footerText,
        'taxNumber': taxNumber,
        'commercialRegistry': commercialRegistry,
      };
}

/// قالب الإيصال المُعدّ للمنظمة.
///
/// <para>مفتوح لأي مستخدم مسجَّل: نقطة البيع تحتاجه لتطبع. ويسقط على
/// الافتراضي عند أي فشل بدل أن يمنع الطباعة.</para>
final receiptTemplateProvider = FutureProvider<ReceiptTemplate>((ref) async {
  try {
    final response =
        await ApiClient.instance.dio.get('/organizations/me/receipt-template');
    return ReceiptTemplate.fromJson(Map<String, dynamic>.from(response.data as Map));
  } catch (_) {
    return ReceiptTemplate.fallback;
  }
});


/// بايتات شعار المنظمة للطباعة — أو null.
///
/// <para>الشعار مرفوعٌ خلف مصادقة، فلا يُقرأ برابطٍ مباشر. ويسقط على null
/// عند أي فشل: إيصالٌ بلا شعار يُطبع، وإيصالٌ لا يُطبع لا ينفع أحداً.</para>
final receiptLogoProvider = FutureProvider<Uint8List?>((ref) async {
  final template = await ref.watch(receiptTemplateProvider.future);
  final path = template.logoUrl;
  if (!template.showLogo || path == null || path.isEmpty) return null;

  try {
    final response = await ApiClient.instance.dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    return bytes == null ? null : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
});
