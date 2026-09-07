/// شكل شاشة نقطة البيع — نمطُها، وأدواتُها، وترتيبها.
///
/// <para><b>سبب وجود هذا الملف:</b> نقطة بيعٍ واحدة لا تخدم قطاعين. مقهى
/// يبيع عشرين صنفاً بأسمائها وصورها ولا باركود على شيء منها؛ وسوبرماركت
/// يمرّ عليه في الساعة مئتا زبون بباركودٍ على كل قطعة، ما يبطّئه ضغطةٌ
/// زائدة واحدة تُضرب في مئتين؛ ووحدة بيعٍ بشاشة سبع بوصات لا يتّسع فيها
/// عمودان أصلاً. وشاشةٌ واحدة تُرضيهم جميعاً تعني أن كلاً منهم يعمل على
/// شاشةٍ صُمّمت لغيره.</para>
///
/// <para><b>ولماذا منطقٌ في ملفٍّ وحده لا داخل الشاشة:</b> شاشة نقطة البيع
/// اليوم ألفان وأربعمئة سطر، وقرارُ «ما الذي يُعرض» فيها مبثوثٌ في شروطٍ
/// داخل البناء. وما يُبنى داخل `build` لا يُختبر إلا بتصيير الشاشة كاملة —
/// وتصييرها يُغيّر لقطات الجولة. فالقرار هنا: دوالُّ خالصة تأخذ عرضاً
/// وإعداداً وتُعيد تخطيطاً، تُختبر بالأرقام لا بالبكسلات.</para>
library;

import 'dart:convert';

/// نمط الشاشة — أربعةٌ تغطّي ما رأيناه من قطاعات.
enum PosLayoutPreset {
  /// الحالي: بحثٌ ونتائج بجوار السلّة. للمتاجر العامّة ومن اعتاده.
  classic,

  /// شبكة أزرارٍ كبيرة بصور وفئاتٍ جانبية — مطاعم ومقاهٍ.
  ///
  /// <para>لا باركود على كوب قهوة، والكاشير يعرف الصنف بشكله لا باسمه
  /// مكتوباً. والبحث بالكتابة هنا أبطأ من الضغط على صورة.</para>
  touchGrid,

  /// الباركود أوّلاً وقبل كل شيء — سوبرماركت وطابور طويل.
  ///
  /// <para>الشبكة تنكمش والسلّة تتّسع: عين الكاشير على السطور لا على
  /// الأصناف، وما يفعله بيده مسحٌ لا اختيار.</para>
  scanFast,

  /// عمودٌ واحد بأهدافٍ كبيرة — وحدة بيع أو كشك بشاشةٍ صغيرة.
  compact,
}

/// أداةٌ يضعها المالك في شريط نقطة البيع.
///
/// <para><b>ولماذا تُعدّ ولا تُترك حرّة:</b> كلٌّ منها تصل إلى منطقٍ قائم في
/// الشاشة (الحسم، تعليق الفاتورة، الوزن…). وقائمةٌ مفتوحة تعني زرّاً يضعه
/// المالك ولا شيء خلفه.</para>
enum PosTool {
  /// أصناف سريعة: الأكثر مبيعاً في هذا الفرع أمام يد الكاشير.
  quickItems,

  /// حاسبة — للجمع الذي يفعله الكاشير على ورقة اليوم.
  calculator,

  /// وزن الصنف للمُسعَّر بالكيلو.
  weight,

  /// اختيار العميل — للبيع بالحساب أو بالمحفظة.
  customer,

  /// حسم على الفاتورة.
  discount,

  /// الفواتير المعلَّقة: زبونٌ نسي محفظته يُعلَّق طلبه ويُخدَم من خلفه.
  heldInvoices,

  /// الإرجاع من نقطة البيع نفسها.
  returns,

  /// ملاحظة على الطلب — «بلا سكّر»، «تُغلَّف هدية».
  note,

  /// استعلام سعر بلا إضافةٍ إلى السلّة.
  priceCheck,

  /// صنفٌ مفتوح القيمة.
  openProduct,

  /// فتح درج النقد.
  cashDrawer,

  /// الوردية: فتحُها وإغلاقها وتسليم الدرج.
  shift,
}

/// تخطيطُ شاشةٍ واحد: نمطٌ وأدواتٌ مرتَّبة.
class PosLayout {
  const PosLayout({
    required this.preset,
    required this.tools,
    this.cartOnLeft = false,
    this.gridColumns = 0,
  });

  final PosLayoutPreset preset;

  /// الأدوات بترتيب عرضها. الترتيب معنى لا زينة: أوّلها أقربُ إلى اليد.
  final List<PosTool> tools;

  /// جهة السلّة. اليمين افتراضاً — الواجهة عربية والقراءة من اليمين،
  /// فالسلّة (وهي ما يُقرأ آخراً قبل الدفع) تقع حيث تنتهي العين.
  final bool cartOnLeft;

  /// أعمدة الشبكة، وصفرٌ يعني «احسبها من العرض».
  ///
  /// <para>ويُترك للمالك أن يثبّتها: شاشة الكاشير قد تكون بعرضٍ يُنتج ستّة
  /// أعمدة، وهو يريد أربعةً بأزرارٍ أكبر لأن من يبيع عندهم يلبس قفازات.
  /// </para>
  final int gridColumns;

  /// ما تبدأ به كل حالة قبل أن يُعدّله أحد.
  ///
  /// <para><b>وليست القوائم متساوية الطول:</b> أداةٌ زائدة في شاشةٍ ضيّقة
  /// تدفع ما بعدها خارجها، وأداةٌ ناقصة في شاشةٍ واسعة فراغٌ يُهدر. فلكلّ
  /// نمطٍ ما يحتاجه هو.</para>
  static PosLayout defaultFor(PosLayoutPreset preset) {
    switch (preset) {
      case PosLayoutPreset.classic:
        return const PosLayout(
          preset: PosLayoutPreset.classic,
          tools: [PosTool.customer, PosTool.discount, PosTool.returns, PosTool.openProduct],
        );

      case PosLayoutPreset.touchGrid:
        // المقهى: الطلب يُبنى بالضغط، ويُعلَّق حتى يجهز، وعليه ملاحظات.
        // ولا وزن هنا — لا يُباع شيء بالكيلو على طاولة.
        return const PosLayout(
          preset: PosLayoutPreset.touchGrid,
          tools: [
            PosTool.quickItems,
            PosTool.note,
            PosTool.heldInvoices,
            PosTool.customer,
            PosTool.discount,
          ],
          gridColumns: 4,
        );

      case PosLayoutPreset.scanFast:
        // الطابور: ما يُختصر هنا ضغطةٌ تُضرب في مئتين. والوزن ودرج النقد
        // أكثر ما تمسّه اليد بعد الماسح.
        return const PosLayout(
          preset: PosLayoutPreset.scanFast,
          tools: [
            PosTool.weight,
            PosTool.priceCheck,
            PosTool.heldInvoices,
            PosTool.cashDrawer,
            PosTool.customer,
            PosTool.returns,
          ],
          gridColumns: 2,
        );

      case PosLayoutPreset.compact:
        // سبع بوصات: كل أداةٍ زائدة تأكل من مساحة السلّة نفسها.
        return const PosLayout(
          preset: PosLayoutPreset.compact,
          tools: [PosTool.quickItems, PosTool.customer, PosTool.cashDrawer],
          gridColumns: 2,
        );
    }
  }

  /// النمط الذي يليق بعرضٍ بعينه حين لا يختار أحد.
  ///
  /// <para>شاشةٌ دون [PosLayoutSizes.compactWidth] لا يتّسع فيها عمودان مهما
  /// كان النمط المطلوب — فالضيّق يفرض [PosLayoutPreset.compact] ولا يُسأل
  /// عنه أحد. وما فوقها يبقى على الكلاسيكي: هو سلوك النظام قبل هذا الملف
  /// حرفياً، فلا تتبدّل شاشةُ أحدٍ لأنّنا أضفنا أنماطاً.</para>
  static PosLayoutPreset autoPresetFor(double width) =>
      width < PosLayoutSizes.compactWidth ? PosLayoutPreset.compact : PosLayoutPreset.classic;

  /// أعمدة الشبكة الفعليّة بعد حساب العرض ووضع اللمس.
  ///
  /// <para><b>وهو الحساب الذي يمنع زرّاً لا يُضغط:</b> شبكةٌ بستّة أعمدة
  /// على شاشة عشر بوصات تُنتج أزراراً بعرض إصبعٍ ونصف — يضغط الكاشير
  /// فيُضاف غيرُ ما أراد، ولا يكتشفه إلا الزبون في الإيصال. فالعرض الأدنى
  /// للزرّ هو ما يحكم، لا عددٌ يُكتب في إعداد.</para>
  ///
  /// <para>واختيار المالك يُقيَّد ولا يُهمَل: من ثبّت ستّة أعمدة على شاشةٍ
  /// لا تحمل إلا ثلاثة يحصل على ثلاثة — لا على ستّة لا تُضغط.</para>
  static int gridColumnsFor({
    required double width,
    required bool touch,
    int requested = 0,
  }) {
    final minTile = touch ? PosLayoutSizes.touchTile : PosLayoutSizes.pointerTile;
    final fits = (width / minTile).floor();
    // عمودٌ واحد على الأقلّ: شاشةٌ أضيق من زرٍّ واحد لا وجود لها، وصفرٌ
    // هنا يعني شبكةً بلا أعمدة — أي شاشة فارغة بلا رسالة.
    final capacity = fits < 1 ? 1 : fits;
    if (requested <= 0) return capacity;
    return requested < capacity ? requested : capacity;
  }

  PosLayout copyWith({
    PosLayoutPreset? preset,
    List<PosTool>? tools,
    bool? cartOnLeft,
    int? gridColumns,
  }) =>
      PosLayout(
        preset: preset ?? this.preset,
        tools: tools ?? this.tools,
        cartOnLeft: cartOnLeft ?? this.cartOnLeft,
        gridColumns: gridColumns ?? this.gridColumns,
      );

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'tools': tools.map((t) => t.name).toList(),
        'cartOnLeft': cartOnLeft,
        'gridColumns': gridColumns,
      };

  /// يقرأ تخطيطاً محفوظاً، ويصمد أمام ما لا يعرفه.
  ///
  /// <para><b>ولماذا يتساهل:</b> الإعداد يُحفظ على الخادم ويُقرأ على أجهزةٍ
  /// نسخُها متفاوتة — جهاز الكاشير يُحدَّث بعد جهاز المدير بأسبوع. فأداةٌ
  /// أضافها إصدارٌ أحدث تصل جهازاً أقدم لا يعرفها: تُتجاهَل ويُفتح الباقي.
  /// والبديل شاشةُ بيعٍ لا تفتح لأن في إعدادها كلمةً لم تُفهم.</para>
  ///
  /// <para>والمكرّر يُسقَط بأوّل ظهوره: أداةٌ مرّتين في الشريط ضغطتان
  /// لنفس الشيء، وأسوأ منهما ظنُّ الكاشير أنّ الثانية غيرُ الأولى.</para>
  static PosLayout fromJson(Map<String, dynamic> json) {
    final presetName = json['preset'] as String?;
    final preset = PosLayoutPreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => PosLayoutPreset.classic,
    );

    final fallback = defaultFor(preset);
    final rawTools = json['tools'];
    List<PosTool> tools = fallback.tools;
    if (rawTools is List) {
      final seen = <PosTool>{};
      final parsed = <PosTool>[];
      for (final name in rawTools) {
        final match = PosTool.values.where((t) => t.name == name);
        if (match.isEmpty) continue;
        final tool = match.first;
        if (!seen.add(tool)) continue;
        parsed.add(tool);
      }
      // قائمةٌ فارغة بعد الترشيح ليست «بلا أدوات» بل «لم يُفهم منها شيء»،
      // وشريطٌ فارغ يُخفي الحسم والعميل والإرجاع عن الكاشير بلا سبب ظاهر.
      // أمّا من أراد شريطاً فارغاً حقاً فيبقى له [tools] فارغة صراحةً —
      // وهي حالةٌ تُقرأ من مفتاحٍ موجود بقائمةٍ فارغة، لا من غياب المفتاح.
      tools = parsed.isEmpty && rawTools.isNotEmpty ? fallback.tools : parsed;
    }

    final columns = json['gridColumns'];
    return PosLayout(
      preset: preset,
      tools: tools,
      cartOnLeft: json['cartOnLeft'] as bool? ?? false,
      gridColumns: columns is num ? columns.toInt() : 0,
    );
  }

  static PosLayout? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? fromJson(decoded) : null;
    } on FormatException {
      // إعدادٌ تالف لا يُسقط نقطة البيع: تُفتح بالافتراضي ويُصلَح الإعداد
      // من شاشة الإعدادات. والبيع لا ينتظر إصلاح تفضيل عرض.
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  /// أيُّ تخطيطٍ يُعتمد، وبأيّ ترتيب.
  ///
  /// <para><b>الجهاز أوّلاً ثم الفرع ثم المنظمة:</b> شاشة الكاشير اللمسية
  /// وشاشة مكتب المدير على نفس الفرع في اللحظة نفسها — كما هو الحال في
  /// وضع اللمس ذاته. والفرع قبل المنظمة لأن فرع المطعم وفرع البقالة في
  /// نفس الشركة يبيعان بطريقتين.</para>
  ///
  /// <para><b>و`null` تعني «لم يُختَر» لا «الافتراضي»:</b> فلو حُفظ
  /// الافتراضي في مستوى الجهاز لصار تغييرُ المالك على مستوى المنظمة لا
  /// يصل إلى جهازٍ فُتحت فيه الشاشة مرّةً واحدة.</para>
  static PosLayout resolve({
    PosLayout? device,
    PosLayout? branch,
    PosLayout? organization,
    required double width,
  }) {
    final chosen = device ?? branch ?? organization;
    if (chosen == null) return defaultFor(autoPresetFor(width));

    // ضيقُ الشاشة يغلب الاختيار: شبكةُ مطعمٍ بأربعة أعمدة على شاشة سبع
    // بوصات تُنتج أزراراً لا تُضغط. تبقى أدوات المالك وترتيبها، ويُفرض
    // العمود الواحد.
    if (width < PosLayoutSizes.compactWidth && chosen.preset != PosLayoutPreset.compact) {
      return chosen.copyWith(preset: PosLayoutPreset.compact, gridColumns: 2);
    }
    return chosen;
  }
}

/// المقاسات التي تحكم الحساب — مجموعةً في مكانٍ واحد لأنها تُراجَع معاً.
class PosLayoutSizes {
  /// دون هذا العرض لا يتّسع عمودان: تخطيطٌ عمودي مهما طُلب.
  ///
  /// <para>وهي عتبة الهاتف نفسها في [Breakpoints] عمداً: عتبتان لنفس
  /// المعنى تفترقان عند أوّل تعديل، فتصير الشاشة عموداً واحداً في تخطيطٍ
  /// يظنّ نفسه عمودين.</para>
  static const double compactWidth = 600;

  /// أصغر عرضٍ لزرّ صنفٍ يُضغط بالإصبع.
  ///
  /// <para>هدف اللمس الموصى به 44 نقطة، وهذا ضعفه تقريباً: زرّ الصنف يحمل
  /// اسماً وسعراً وصورة، وزرٌّ بعرض 44 يقصّ الاسم فيصير «شاي بالن…» —
  /// ويضغط الكاشير على الظنّ.</para>
  static const double touchTile = 120;

  /// وبالفأرة: المؤشّر يصيب نقطةً بعينها، فالمقاس للقراءة لا للإصابة.
  static const double pointerTile = 96;
}
