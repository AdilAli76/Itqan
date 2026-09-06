import 'receipt_template.dart';

/// تعريف طابعة: ما تطبعه فعلاً، لا ما هو مكتوب على علبتها.
///
/// <para><b>سبب وجوده:</b> «عرض الورق ٨٠ ملم» رقمٌ يضلّل. طابعة NB80 تأخذ
/// لفّةً عرضها ٨٠ ملم وتطبع على **٧٢** منها — والثمانية الباقية حافّتان لا
/// تصلهما رأس الطباعة. فمن ضبط ٨٠ ورسم باركوداً بعرض ٨٠ خرج له باركودٌ
/// مقصوص الطرفين لا يقرؤه شيء، ولا رسالة خطأ ولا سبب ظاهر.</para>
///
/// <para><b>وكثافة النقاط ليست تفصيلاً:</b> الطابعة الحرارية ترسم بنقاطٍ
/// صحيحة لا بأجزائها. فعرض أنحف عمودٍ في الباركود إن لم يكن مضاعفاً صحيحاً
/// لحجم النقطة، قرّبته الطابعة نقطةً كاملة — فتختلف نسب الأعمدة عن
/// المواصفة، ويقرؤه ماسحٌ ولا يقرؤه آخر. لهذا تُحسب المقاسات من
/// <see cref="dotMm"/> لا من أرقامٍ جميلة.</para>
///
/// <para><b>وهو تعريفٌ للجهاز لا للمنظمة:</b> فرعٌ بطابعة ٨٠ وآخر بطابعة ٥٨
/// على المنظمة نفسها وفي اللحظة نفسها. راجع [selectedPrinterProfileProvider].
/// </para>
class PrinterProfile {
  const PrinterProfile({
    required this.id,
    required this.label,
    required this.paper,
    required this.paperWidthMm,
    required this.printableWidthMm,
    required this.dpi,
  });

  final String id;
  final String label;

  /// مقاس الصفحة المقابل في [ReceiptPapers] — الإيصال والقسيمة يُبنيان به.
  final String paper;

  final double paperWidthMm;

  /// ما تصله رأس الطباعة فعلاً — وهو ما يُرسم عليه، لا [paperWidthMm].
  final double printableWidthMm;

  final int dpi;

  /// حجم النقطة الواحدة بالمليمتر — وحدة القياس الحقيقية لهذه الطابعة.
  double get dotMm => 25.4 / dpi;

  /// <summary>
  /// مقاس باركود Code128 لرمزٍ بهذا الطول على هذه الطابعة.
  ///
  /// <para>يُختار أعرض عمودٍ نحيف (module) تتّسع له الورقة، لأن الأعرض
  /// أسهل قراءةً — ثم يُقرَّب **نزولاً** إلى مضاعفٍ صحيح لحجم النقطة: تقريبٌ
  /// صعوداً يعني رمزاً أعرض من الورق فيُقصّ طرفه.</para>
  /// </summary>
  BarcodeLayout code128Layout(int codeLength) {
    // بنية Code128: بادئة + المحارف + رمز تحقّق، كلٌّ منها ١١ عموداً،
    // ثم خاتمةٌ ١٣ عموداً. والمنطقة الهادئة ١٠ أعمدة على كل جانب —
    // وحذفُها هو أشيع سبب لباركودٍ «مطبوع صحيح» لا يُقرأ.
    final symbolModules = 11 * (codeLength + 3) + 13;
    final totalModules = symbolModules + 20;

    final maxModuleMm = printableWidthMm / totalModules;
    final dots = (maxModuleMm / dotMm).floor();
    final moduleMm = dots < 1 ? dotMm : dots * dotMm;

    return BarcodeLayout(
      moduleMm: moduleMm,
      widthMm: moduleMm * totalModules,
      // عتبة الكاميرا ربع المليمتر (١٠ ملّي بوصة) — وهي نقطتان على طابعة
      // ٢٠٣: ماسح الليزر عند الصندوق يقرأ أنحف منها بكثير، أمّا كاميرا
      // الهاتف — وهي القارئ في الميدان — فتتعثّر دونها. والمقارنة بهامشٍ
      // صغير لأن المقاس حاصلُ قسمةٍ عشرية لا رقمٌ مكتوب.
      cameraReadable: moduleMm >= 0.249,
    );
  }

  /// أضيق من أن يُطبع عليه باركودٌ خطّي يقرؤه الهاتف؟ عندها يُطبع QR معه.
  bool needsQrFallback(int codeLength) => !code128Layout(codeLength).cameraReadable;
}

/// نتيجة حساب مقاس الباركود على طابعةٍ بعينها.
class BarcodeLayout {
  const BarcodeLayout({
    required this.moduleMm,
    required this.widthMm,
    required this.cameraReadable,
  });

  /// عرض أنحف عمود — مضاعفٌ صحيح لحجم نقطة الطابعة.
  final double moduleMm;

  /// عرض الرمز كاملاً بمنطقتيه الهادئتين.
  final double widthMm;

  /// أتقرؤه كاميرا هاتف، أم ماسح ليزر وحده؟
  final bool cameraReadable;
}

/// <summary>
/// الطابعات المعروفة.
///
/// <para><b>قائمةٌ مسمّاة لا حقلُ أرقام:</b> من يشتري NB80 يعرف اسمها
/// المكتوب على علبتها، ولا يعرف أن رأسها ٧٢ ملم بكثافة ٢٠٣ نقطة. وسؤالُه عن
/// أرقامٍ لا يملكها يُنتج قيماً مخمَّنة تُقصّ الطباعة.</para>
///
/// <para>و«عامّة» تبقى للطابعة التي ليست في القائمة: قائمةٌ مغلقة بلا مخرج
/// تُوقف من اشترى طرازاً لم نسمع به.</para>
/// </summary>
class PrinterProfiles {
  const PrinterProfiles._();

  /// NB80 وما يوافقها من الطابعات الحرارية ٨٠ ملم (XP-80، RP80…).
  static const nb80 = PrinterProfile(
    id: 'nb80',
    label: 'NB80 — حرارية 80 ملم',
    paper: ReceiptPapers.roll80,
    paperWidthMm: 80,
    printableWidthMm: 72,
    dpi: 203,
  );

  static const nb58 = PrinterProfile(
    id: 'nb58',
    label: 'NB58 — حرارية 58 ملم',
    paper: ReceiptPapers.roll58,
    paperWidthMm: 58,
    printableWidthMm: 48,
    dpi: 203,
  );

  static const generic80 = PrinterProfile(
    id: 'generic80',
    label: 'حرارية 80 ملم (عامّة)',
    paper: ReceiptPapers.roll80,
    paperWidthMm: 80,
    printableWidthMm: 72,
    dpi: 203,
  );

  static const generic58 = PrinterProfile(
    id: 'generic58',
    label: 'حرارية 58 ملم (عامّة)',
    paper: ReceiptPapers.roll58,
    paperWidthMm: 58,
    printableWidthMm: 48,
    dpi: 203,
  );

  /// طابعة مكتبٍ عادية — للبطاقة بوجهين على A4، ولمن لا حرارية عنده.
  static const a4 = PrinterProfile(
    id: 'a4',
    label: 'طابعة مكتب A4',
    paper: ReceiptPapers.a4,
    paperWidthMm: 210,
    printableWidthMm: 182,
    dpi: 300,
  );

  static const all = [nb80, nb58, generic80, generic58, a4];

  static PrinterProfile byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => nb80);

  /// <summary>
  /// التعريف المستنتَج من عرض الإيصال المحفوظ في إعدادات المنظمة.
  ///
  /// <para>يُستعمل قبل أن يختار أحدٌ طابعةً على هذا الجهاز: القيمة موجودة
  /// أصلاً في الإعدادات، وسؤالُ المستخدم عمّا سبق أن أجاب عنه لا يُطاق.</para>
  /// </summary>
  static PrinterProfile fromReceiptWidth(double widthMm) =>
      widthMm <= 68 ? generic58 : generic80;
}
