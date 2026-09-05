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

/// القوالب الجاهزة — نقطة بداية تُختار ثم تُعدَّل.
///
/// <para><b>سبب وجودها:</b> «صمّم إيصالك» أمام صاحب محلٍّ يعني عشرين خياراً
/// بلا نقطة بداية، فيخرج بإيصالٍ أسوأ ممّا كان أو يترك الشاشة كما هي. أمّا
/// أربعة قوالب مسمّاة فيختار منها بنظرةٍ واحدة، ثم يغيّر ما لا يعجبه —
/// وهو نفس ما تفعله معالجات النصوص.</para>
///
/// <para>والقالب ليس قفلاً: تطبيقه يضبط حزمة قيم، وكلُّ قيمةٍ بعده قابلة
/// للتغيير على حدة.</para>
class ReceiptPresets {
  const ReceiptPresets._();

  /// أبيض وأسود بخطوط فاصلة — أقرب شيء لإيصال الكاشير المألوف.
  static const classic = 'classic';

  /// شريط ملوّن بالعنوان وصفوفٌ متناوبة التظليل.
  static const modern = 'modern';

  /// بلا خطوط ولا تظليل ومسافات أوسع — للطابعات الحرارية الباهتة.
  static const minimal = 'minimal';

  /// جدولٌ مؤطَّر وإطارٌ للصفحة — للفاتورة الورقية التي تُحفَظ وتُختَم.
  static const formal = 'formal';

  static const all = [classic, modern, minimal, formal];

  static String labelOf(String preset) => switch (preset) {
        modern => 'حديث',
        minimal => 'مبسّط',
        formal => 'رسمي',
        _ => 'كلاسيكي',
      };

  static String describe(String preset) => switch (preset) {
        modern => 'شريط ملوّن وصفوف متناوبة',
        minimal => 'بلا خطوط، مسافات أوسع',
        formal => 'جدول مؤطَّر وإطار للصفحة',
        _ => 'خطوط فاصلة، أبيض وأسود',
      };
}

/// شكل قائمة الأصناف.
class ReceiptTableStyles {
  const ReceiptTableStyles._();

  static const plain = 'plain';
  static const lines = 'lines';
  static const zebra = 'zebra';
  static const grid = 'grid';

  static const all = [plain, lines, zebra, grid];

  static String labelOf(String style) => switch (style) {
        lines => 'خطوط فاصلة',
        zebra => 'صفوف متناوبة',
        grid => 'جدول مؤطَّر',
        _ => 'بلا خطوط',
      };
}

/// قالب الإيصال كما تحفظه المنظمة، ومعه ما يملأه.
class ReceiptTemplate {
  const ReceiptTemplate({
    this.paper = ReceiptPapers.roll80,
    this.preset = ReceiptPresets.classic,
    this.accentColor = '#0B2540',
    this.fontScale = 1.0,
    this.tableStyle = ReceiptTableStyles.lines,
    this.showPageBorder = false,
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

  /// القالب الجاهز الذي بُدئ منه — يُحفظ ليُعرَف المختار عند فتح الشاشة.
  final String preset;

  /// لون الترويسة وسطر الإجمالي، بصيغة ‎#RRGGBB‎.
  ///
  /// <para>واحدٌ لا لوحة ألوان: إيصالٌ بأربعة ألوان يبدو نشرةً إعلانية،
  /// ولون الطباعة الحرارية أسودٌ دائماً على أي حال — فاللون لمن يطبع على
  /// A4 بطابعة ملوّنة.</para>
  final String accentColor;

  /// مضاعِف حجم الخطّ (0.8 – 1.4).
  ///
  /// <para>مضاعِفٌ لا مقاسٌ مطلق: الإيصال الحراري وA4 يختلفان في الأساس،
  /// ورقمٌ واحد لهما يجعل ضبط أحدهما يُفسد الآخر.</para>
  final double fontScale;

  /// شكل قائمة الأصناف — راجع [ReceiptTableStyles].
  final String tableStyle;

  /// إطارٌ حول الصفحة — للورق الرسمي، ولا معنى له على اللفّة.
  final bool showPageBorder;

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
      preset: ReceiptPresets.all.contains(template['preset'])
          ? template['preset'] as String
          : ReceiptPresets.classic,
      accentColor: (template['accentColor'] as String?) ?? '#0B2540',
      // مقيَّدٌ بالحدود عند القراءة أيضاً: قيمةٌ خارجها في قاعدةٍ عُدّلت
      // يدوياً تُنتج إيصالاً بخطٍّ لا يُقرأ أو صفحةً بسطرٍ واحد.
      fontScale: ((template['fontScale'] as num?)?.toDouble() ?? 1.0).clamp(0.8, 1.4),
      tableStyle: ReceiptTableStyles.all.contains(template['tableStyle'])
          ? template['tableStyle'] as String
          : ReceiptTableStyles.lines,
      showPageBorder: template['showPageBorder'] as bool? ?? false,
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
    String? preset,
    String? accentColor,
    double? fontScale,
    String? tableStyle,
    bool? showPageBorder,
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
        preset: preset ?? this.preset,
        accentColor: accentColor ?? this.accentColor,
        fontScale: fontScale ?? this.fontScale,
        tableStyle: tableStyle ?? this.tableStyle,
        showPageBorder: showPageBorder ?? this.showPageBorder,
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

  /// يطبّق قالباً جاهزاً: حزمة قيمٍ تُبدَّل، وما لا يخصّ الشكل يبقى.
  ///
  /// <para>النصوص والشعار والرقم الضريبي **لا تُمسّ**: من اختار «حديث»
  /// بعد أن كتب تذييله لا يقصد محوَه.</para>
  ReceiptTemplate applyPreset(String preset) => switch (preset) {
        ReceiptPresets.modern => copyWith(
            preset: preset,
            tableStyle: ReceiptTableStyles.zebra,
            showPageBorder: false,
            accentColor: '#0B2540',
          ),
        ReceiptPresets.minimal => copyWith(
            preset: preset,
            tableStyle: ReceiptTableStyles.plain,
            showPageBorder: false,
            accentColor: '#4B5563',
          ),
        ReceiptPresets.formal => copyWith(
            preset: preset,
            tableStyle: ReceiptTableStyles.grid,
            showPageBorder: true,
            accentColor: '#1F2937',
          ),
        _ => copyWith(
            preset: ReceiptPresets.classic,
            tableStyle: ReceiptTableStyles.lines,
            showPageBorder: false,
            accentColor: '#0B2540',
          ),
      };

  Map<String, dynamic> toRequest() => {
        'paper': paper,
        'preset': preset,
        'accentColor': accentColor,
        'fontScale': fontScale,
        'tableStyle': tableStyle,
        'showPageBorder': showPageBorder,
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
