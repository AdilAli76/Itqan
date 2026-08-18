// ignore_for_file: avoid_print
//
// ux_audit.dart — مدقّق جماليات وتجربة المستخدم لنظام Kinetic Enterprise ERP
//
// الغرض: قياس آلي — لا انطباعي — لمدى استيفاء واجهة النظام لشروط منظومة ERP
// حديثة: هوية بصرية متّسقة، تخطيط مستجيب، حالات واجهة كاملة، سهولة استخدام،
// وصولية، حوكمة وتحكّم، ملامح "عصر الذكاء الاصطناعي"، ودعم عربي/RTL سليم.
//
// التشغيل:
//   dart run tool/ux_audit.dart                  تقرير في الطرفية
//   dart run tool/ux_audit.dart --md             + كتابة docs/UX_AUDIT_REPORT.md
//   dart run tool/ux_audit.dart --json           إخراج JSON للأتمتة
//   dart run tool/ux_audit.dart --details        عرض كل المخالفات لا أول أربع
//   dart run tool/ux_audit.dart --pillar=rtl     تدقيق محور واحد فقط
//   dart run tool/ux_audit.dart --fail-under=75  خروج بكود 1 إذا قلّت الدرجة
//
// ملاحظة منهجية: هذه أداة استدلالية (heuristics) على النص المصدري. النتيجة
// مؤشّر توجيهي يحدّد أين تنظر، وليست حكماً نهائياً على جودة التصميم — بعض
// المخالفات المعلن عنها قد تكون مقصودة، ولذلك يطبع التقرير الموقع والسطر
// دائماً حتى تُراجَع يدوياً.

import 'dart:convert';
import 'dart:io';

const String kVersion = '1.0.0';

// ═══════════════════════════════════════════ نموذج البيانات ══════════════

class SourceFile {
  SourceFile(this.rel, this.text) : lines = const LineSplitter().convert(text);

  final String rel;
  final String text;
  final List<String> lines;

  /// نصّ الملف بلا أسطر التعليقات والاستيراد.
  ///
  /// كل قواعد «الحضور» و«القدرة» تقرأ هذا لا [text]: التعليق الذي يشرح لماذا
  /// يجب طلب تأكيد قبل الحذف ليس تنفيذاً لتأكيد، وشرحُ ميزةٍ غائبة ليس
  /// وجوداً لها. الخلط بينهما يجعل الملف الموثَّق جيداً يبدو أفضل من الملف
  /// الذي ينفّذ الشيء فعلاً — وهو أسوأ حافز يمكن أن تخلقه أداة قياس.
  late final String code = [
    for (var i = 0; i < lines.length; i++)
      if (!isNoise(i)) lines[i],
  ].join('\n');

  bool get isScreen => rel.endsWith('_screen.dart');
  bool get isDialog => rel.contains('dialog') || code.contains('AlertDialog');
  bool get isTheme => rel.contains('core/theme');
  bool get isUi =>
      rel.contains('/presentation/') ||
      rel.contains('shared/widgets') ||
      rel.contains('core/shell') ||
      rel.contains('core/responsive') ||
      rel.contains('core/theme');
  /// نموذج فعلي = يحوي TextFormField.
  ///
  /// اشتراط TextFormField وحده (لا TextField) مقصود: TextField المجرّد هو
  /// حقل بحث في الغالب الأعم — في الجدول المشترك، وفي لوحة الأوامر، وفي
  /// شريط نقطة البيع — وحقل البحث لا يُصادَق عليه ولا يُرفَض إدخاله. عدّه
  /// نموذجاً كان يُنتج مطالبة بـ validator لحقل لا معنى للتحقّق فيه، وهي
  /// إيجابية كاذبة تُفقد القاعدة مصداقيتها. وTextFormField موجود في Flutter
  /// لهذا الغرض بالذات: الحقل المشارك في Form وتحقّقه.
  bool get isForm => code.contains('TextFormField');
  bool get isDataScreen =>
      isScreen &&
      (code.contains('.when(') || code.contains('FutureBuilder') || code.contains('ref.watch'));
  /// شاشة قائمة سجلات = تعرض جدولاً. وجود ListView وحده لا يكفي.
  ///
  /// الفرق ليس شكلياً: نقطة البيع ومصمّم الباركود يستعملان ListView لعرض
  /// «سلّة عمل» — أصناف الفاتورة الجارية، أو أسطر الملصق المُختارة. هذه
  /// قوائم يبنيها المستخدم بنفسه في الجلسة الحالية، لا أرشيف سجلات يبحث
  /// فيه ويصفّيه ويتصفّحه صفحات. مطالبتها ببحث وترشيح وترقيم كانت مطالبة
  /// بحلٍّ لمشكلة غير موجودة.
  bool get hasTable => code.contains('AppDataTable') || code.contains('DataTable');

  /// أسطر التعليقات والاستيراد تُستثنى من فحص المخالفات: تعليق يشرح لوناً
  /// ليس استخداماً للون.
  bool isNoise(int i) {
    final t = lines[i].trimLeft();
    return t.startsWith('//') || t.startsWith('*') || t.startsWith('import ') || t.startsWith('/*');
  }

  /// استثناء صريح لقاعدة بعينها على سطر بعينه، بصيغة:
  ///
  ///     // ux-audit: ignore AC-02 — معاينة ملصق مطبوع بحجمه الحقيقي
  ///
  /// يُكتب على السطر نفسه أو على السطر السابق له.
  ///
  /// وجود هذه الآلية ضروري لأداة استدلالية: بدونها يتعلّم الفريق تجاهل
  /// التقرير كله بسبب بضع مخالفات مقصودة، وهي أسوأ نتيجة ممكنة لمدقّق.
  /// واشتراط ذكر السبب بعد الشرطة يجعل الاستثناء قراراً موثّقاً لا تهرّباً
  /// صامتاً — والمراجع يرى السبب في مكانه بلا رجوع لأحد.
  bool isSuppressed(int i, String ruleId) {
    final marker = 'ux-audit: ignore $ruleId';
    if (lines[i].contains(marker)) return true;
    // يصعد عبر كتلة التعليق الملاصقة كاملةً لا سطراً واحداً: السبب الجيد
    // نادراً ما يسع سطراً، والاكتفاء بسطر كان يعاقب من شرح استثناءه جيداً.
    for (var j = i - 1; j >= 0; j--) {
      final t = lines[j].trimLeft();
      if (t.isEmpty) return false;
      if (!t.startsWith('//')) return false;
      if (t.contains(marker)) return true;
    }
    return false;
  }
}

class Finding {
  Finding(this.rel, this.line, this.snippet);
  final String rel;
  final int line;
  final String snippet;
}

class RuleResult {
  RuleResult({
    required this.id,
    required this.title,
    required this.pillar,
    required this.weight,
    required this.score,
    required this.hint,
    required this.detail,
    this.findings = const [],
  });

  final String id;
  final String title;
  final String pillar;
  final double weight;
  final double score; // 0..100
  final String hint;
  final String detail; // مثل «14/22 شاشة»
  final List<Finding> findings;
}

// ═══════════════════════════════════════════ محرّك القواعد ═══════════════

typedef Scope = bool Function(SourceFile f);

/// فهرس الودجت المشتركة: اسم الصنف ← نصّ ملفه.
///
/// بدونه يعطي المدقّق إنذارات كاذبة كثيرة: شاشة تستخدم DataTableWidget لا
/// تكتب بنفسها حالة فارغة ولا تمريراً أفقياً ولا تحقّقاً من عرض الشاشة —
/// لأن الودجت المشتركة تفعل ذلك نيابةً عنها، وهذا هو السلوك الصحيح لا
/// مخالفة. تُبنى مرّة واحدة وتُستشار عند كل قاعدة «حضور».
class SharedIndex {
  SharedIndex(List<SourceFile> files) {
    final decl = RegExp(r'class\s+(\w+)');
    for (final f in files) {
      if (!f.rel.contains('shared/widgets') &&
          !f.rel.contains('core/responsive') &&
          !f.rel.contains('core/shell')) {
        continue;
      }
      for (final m in decl.allMatches(f.code)) {
        _byClass[m.group(1)!] = f.code;
      }
    }
  }

  final _byClass = <String, String>{};

  /// هل يفي الملف بالنمط عبر ودجت مشتركة يستدعيها؟
  bool satisfiedByDelegate(SourceFile f, RegExp needle) {
    for (final e in _byClass.entries) {
      if (f.code.contains(e.key) && needle.hasMatch(e.value)) return true;
    }
    return false;
  }
}

/// هل يتحقّق الشرط في طبقة بيانات الوحدة (features/<x>/data/) بدل شاشتها؟
///
/// الترقيم مثال مباشر: شاشة سجل التدقيق لا تحوي كلمة page ولا pageSize،
/// لأن الترقيم كله في audit_log_providers.dart — وهذا هو الفصل الصحيح بين
/// العرض والبيانات، لا نقصاً يُعاقَب عليه. الحكم على الوحدة بملف واحد من
/// ملفاتها كان يعاقب البنية المعمارية السليمة تحديداً.
bool satisfiedByFeatureData(SourceFile f, List<SourceFile> all, RegExp needle) {
  final marker = RegExp(r'features/([^/]+)/').firstMatch(f.rel);
  if (marker == null) return false;
  final feature = marker.group(1);
  return all.any((o) =>
      o.rel.contains('features/$feature/data/') && needle.hasMatch(o.code));
}

abstract class Rule {
  Rule({
    required this.id,
    required this.title,
    required this.pillar,
    required this.hint,
    this.weight = 1.0,
  });

  final String id;
  final String title;
  final String pillar;
  final String hint;
  final double weight;

  RuleResult run(List<SourceFile> files);
}

/// قاعدة «حضور»: كم نسبة الملفات المعنيّة التي تطبّق النمط المطلوب.
class PresenceRule extends Rule {
  PresenceRule({
    required super.id,
    required super.title,
    required super.pillar,
    required super.hint,
    super.weight,
    required this.scope,
    required this.needle,
    this.unit = 'ملف',
    this.allowDelegate = true,
  });

  final Scope scope;
  final RegExp needle;
  final String unit;

  /// هل يُقبل تحقّق الشرط عبر ودجت مشتركة؟ يُعطَّل للقواعد التي يجب أن
  /// تتحقّق في الشاشة نفسها (مثل فحص الصلاحية قبل إظهار زر).
  final bool allowDelegate;

  @override
  RuleResult run(List<SourceFile> files) {
    final applicable = files.where(scope).toList();
    if (applicable.isEmpty) {
      return RuleResult(
        id: id, title: title, pillar: pillar, weight: weight,
        score: 100, hint: hint, detail: 'لا ينطبق',
      );
    }
    final shared = _sharedIndex ??= SharedIndex(files);
    final misses = applicable
        .where((f) =>
            !needle.hasMatch(f.code) &&
            !f.text.contains('ux-audit: ignore $id') &&
            !(allowDelegate && shared.satisfiedByDelegate(f, needle)) &&
            !(allowDelegate && satisfiedByFeatureData(f, files, needle)))
        .toList();
    final pass = applicable.length - misses.length;
    return RuleResult(
      id: id, title: title, pillar: pillar, weight: weight,
      score: pass / applicable.length * 100,
      hint: hint,
      detail: '$pass/${applicable.length} $unit',
      findings: [for (final f in misses) Finding(f.rel, 0, 'النمط المطلوب غير موجود')],
    );
  }
}

SharedIndex? _sharedIndex;

/// قاعدة «مخالفة»: كل تطابق خصم. الخصم نسبي حتى لا يُعاقَب المشروع لحجمه.
class ViolationRule extends Rule {
  ViolationRule({
    required super.id,
    required super.title,
    required super.pillar,
    required super.hint,
    super.weight,
    required this.scope,
    required this.pattern,
    this.accept,
    this.tolerance = 0,
    this.penaltyPerHit = 6,
  });

  final Scope scope;
  final RegExp pattern;

  /// مرشّح إضافي: يعيد true إذا كان التطابق مخالفة فعلية.
  final bool Function(Match m, SourceFile f)? accept;

  /// عدد المخالفات المسموح بها قبل بدء الخصم.
  final int tolerance;
  final double penaltyPerHit;

  @override
  RuleResult run(List<SourceFile> files) {
    final applicable = files.where(scope).toList();
    final findings = <Finding>[];
    for (final f in applicable) {
      for (var i = 0; i < f.lines.length; i++) {
        if (f.isNoise(i) || f.isSuppressed(i, id)) continue;
        for (final m in pattern.allMatches(f.lines[i])) {
          if (accept != null && !accept!(m, f)) continue;
          findings.add(Finding(f.rel, i + 1, f.lines[i]));
        }
      }
    }
    final over = (findings.length - tolerance).clamp(0, 1 << 30);
    final score = (100 - over * penaltyPerHit).clamp(0, 100).toDouble();
    return RuleResult(
      id: id, title: title, pillar: pillar, weight: weight,
      score: score, hint: hint,
      detail: findings.isEmpty ? 'نظيف' : '${findings.length} مخالفة',
      findings: findings,
    );
  }
}

/// قاعدة «قدرة»: هل الميزة موجودة في المنتج ككل؟ تُستخدم للحوكمة والحداثة
/// حيث المطلوب وجود القدرة مرّة واحدة، لا تغطية كل شاشة.
class CapabilityRule extends Rule {
  CapabilityRule({
    required super.id,
    required super.title,
    required super.pillar,
    required super.hint,
    super.weight,
    required this.pattern,
    this.searchAll = false,
  });

  final RegExp pattern;
  final bool searchAll;

  @override
  RuleResult run(List<SourceFile> files) {
    final hits = files.where((f) => (searchAll || f.isUi) && pattern.hasMatch(f.code)).toList();
    return RuleResult(
      id: id, title: title, pillar: pillar, weight: weight,
      score: hits.isEmpty ? 0 : 100,
      hint: hint,
      detail: hits.isEmpty ? 'غير موجود' : 'موجود (${hits.length} ملف)',
      findings: hits.take(3).map((f) => Finding(f.rel, 0, 'المصدر')).toList(),
    );
  }
}

/// قاعدة «سلّم»: بدل فرض سلّم رقمي من عندنا (وهو ما يُنتج ضجيجاً حين يكون
/// للمشروع سلّم خاص سليم)، تستخرج القاعدة توزيع القيم الفعلي، تعتبر القيم
/// الشائعة هي السلّم السائد، وتُبلّغ فقط عن القيم النادرة — وهي بالضبط
/// «الرقم الذي كتبه أحدهم مرّة واحدة» الذي يكسر الاتساق البصري.
class ScaleRule extends Rule {
  ScaleRule({
    required super.id,
    required super.title,
    required super.pillar,
    required super.hint,
    super.weight,
    required this.pattern,
    required this.unit,
    this.maxValue = 1 << 30,
    this.rarityPct = 4,
  });

  final RegExp pattern;
  final String unit;

  /// القيم الأكبر من هذا الحد ليست «مسافة» بل أبعاد مقصودة (عرض عمود مثلاً).
  final int maxValue;

  /// القيمة التي تقلّ حصّتها عن هذه النسبة تُعتبر شاذّة لا جزءاً من السلّم.
  final double rarityPct;

  @override
  RuleResult run(List<SourceFile> files) {
    final hits = <int, List<Finding>>{};
    var total = 0;
    for (final f in files.where((f) => f.isUi)) {
      for (var i = 0; i < f.lines.length; i++) {
        if (f.isNoise(i) || f.isSuppressed(i, id)) continue;
        for (final m in pattern.allMatches(f.lines[i])) {
          final v = int.tryParse(m.group(1) ?? '');
          if (v == null || v > maxValue) continue;
          total++;
          hits.putIfAbsent(v, () => []).add(Finding(f.rel, i + 1, f.lines[i]));
        }
      }
    }
    if (total == 0) {
      return RuleResult(
          id: id, title: title, pillar: pillar, weight: weight,
          score: 100, hint: hint, detail: 'لا ينطبق');
    }
    // وحدة السلّم تُستنتج من الاستخدام: أكبر وحدة من 8/4/2 تكون أغلبية
    // القيم من مضاعفاتها. بدونها كانت العتبة النسبية وحدها تُخطئ خطأً
    // منهجياً على القواعد الكودية الكبيرة: قيمة سليمة تماماً مثل 24 أو 48
    // تظهر ثلاث عشرة مرّة بين أربعمئة، فتقلّ حصّتها عن 4% وتُصنَّف «شاذّة»
    // رغم أنها درجة أصيلة في السلّم. الندرة وحدها ليست دليل خطأ؛ الدليل
    // هو الندرة مع الخروج عن الشبكة.
    var gridUnit = 1;
    for (final candidate in const [8, 4, 2]) {
      final onGrid = hits.entries
          .where((e) => e.key % candidate == 0)
          .fold<int>(0, (a, e) => a + e.value.length);
      if (onGrid / total >= 0.8) {
        gridUnit = candidate;
        break;
      }
    }

    final odd = <Finding>[];
    final oddValues = <int>[];
    for (final e in hits.entries) {
      final rare = e.value.length / total * 100 < rarityPct;
      // القيم الصغيرة (أقل من وحدتين) خارج الشبكة ليست انزلاقاً: هي ضبط
      // بصري دقيق — فجوة بين أيقونة ونصّها، حشوة داخل شارة حالة. المسافة
      // التي تُبنى عليها إيقاع التخطيط تبدأ فوق ذلك، وهناك وحدها يصبح
      // الخروج عن الشبكة خطأً مرئياً.
      //
      // الفرق عملياً: 6 بين أيقونة ونص ضبط مقصود، بينما 14 قيمة وقعت بين
      // 12 و16 بلا سبب فتُنتج تفاوتاً بين صفّين متجاورين.
      final offGrid = gridUnit > 1 && e.key % gridUnit != 0 && e.key > gridUnit * 2;
      if (rare && offGrid) {
        odd.addAll(e.value);
        oddValues.add(e.key);
      }
    }
    oddValues.sort();
    final scale = (hits.keys.toList()..sort()).where((v) => !oddValues.contains(v)).join('/');
    return RuleResult(
      id: id, title: title, pillar: pillar, weight: weight,
      score: (total - odd.length) / total * 100,
      hint: hint,
      detail: odd.isEmpty
          ? 'سلّم متّسق (شبكة $gridUnit: $scale)'
          : 'شبكة $gridUnit · ${odd.length} $unit شاذّة عن الشبكة '
              '(${oddValues.join('، ')})',
      findings: odd,
    );
  }
}


/// أيقونة اتجاه تُعاكس معنى وظيفتها.
///
/// القاعدة السابقة كانت مبنية على مقدّمة خاطئة: أنها تُطالب باستبدال
/// arrow_back وchevron_left بـ«نسخ اتجاهية». والحقيقة أن هذه الأيقونات في
/// Material معرَّفة أصلاً بـ matchTextDirection: true — أي أن Flutter يعكسها
/// تلقائياً في الواجهة العربية. القاعدة كانت تُبلّغ عن شيفرة سليمة.
///
/// الخطأ الحقيقي عكس ذلك تماماً: أن يعرف المطوّر أن العربية من اليمين
/// لليسار فيختار arrow_forward لزر «رجوع» تعويضاً يدوياً — فينعكس السهم
/// مرّتين ويشير إلى جهة التقدّم لا الرجوع. وقع هذا فعلاً في زر الرجوع في
/// بوابة العميل وفي شريط ترقيم سجل التدقيق.
///
/// لذلك تفحص القاعدة التناقض بين اتجاه الأيقونة ومعنى تلميحها العربي، لا
/// اسم الأيقونة وحده.
class DirectionIconRule extends Rule {
  DirectionIconRule()
      : super(
          id: 'RT-04',
          title: 'أيقونة اتجاه تعاكس معنى وظيفتها',
          pillar: 'rtl',
          hint: 'اختر الأيقونة بمعناها الإنجليزي (back للرجوع، forward للتقدّم) '
              'ودع الإطار يعكسها؛ التعويض اليدوي يقلبها مرّتين.',
        );

  static final _backWords = RegExp(r'رجوع|السابق|سابقة|السابقة|عودة|للخلف');
  static final _forwardWords = RegExp(r'التالي|التالية|متابعة|للأمام');

  @override
  RuleResult run(List<SourceFile> files) {
    final findings = <Finding>[];
    var checked = 0;

    for (final f in files.where((f) => f.isUi)) {
      for (var i = 0; i < f.lines.length; i++) {
        if (f.isNoise(i) || f.isSuppressed(i, id)) continue;
        if (!f.lines[i].contains('tooltip:')) continue;

        // الأيقونة تُكتب عادةً في السطر المجاور للتلميح صعوداً أو هبوطاً.
        final from = i - 3 < 0 ? 0 : i - 3;
        final to = i + 4 > f.lines.length ? f.lines.length : i + 4;
        final window = f.lines.sublist(from, to).join('\n');
        if (!window.contains('Icons.')) continue;

        final hasForwardIcon =
            RegExp(r'Icons\.(arrow_forward|chevron_right)').hasMatch(window);
        final hasBackIcon =
            RegExp(r'Icons\.(arrow_back|chevron_left)').hasMatch(window);
        if (!hasForwardIcon && !hasBackIcon) continue;
        checked++;

        final saysBack = _backWords.hasMatch(f.lines[i]);
        final saysForward = _forwardWords.hasMatch(f.lines[i]);

        if ((saysBack && hasForwardIcon) || (saysForward && hasBackIcon)) {
          findings.add(Finding(f.rel, i + 1, f.lines[i]));
        }
      }
    }

    if (checked == 0) {
      return RuleResult(
          id: id, title: title, pillar: pillar, weight: weight,
          score: 100, hint: hint, detail: 'لا ينطبق');
    }
    return RuleResult(
      id: id, title: title, pillar: pillar, weight: weight,
      score: (checked - findings.length) / checked * 100,
      hint: hint,
      detail: findings.isEmpty
          ? '$checked زر اتجاه متّسق'
          : '${findings.length} من $checked زر اتجاه معكوس',
      findings: findings,
    );
  }
}

/// IconButton بلا tooltip — يحتاج فحص نافذة أسطر لا سطراً واحداً، لأن
/// tooltip غالباً يُكتب بعد سطرين من الاستدعاء.
class IconTooltipRule extends Rule {
  IconTooltipRule()
      : super(
          id: 'AC-01',
          title: 'أزرار أيقونات بلا tooltip',
          pillar: 'a11y',
          weight: 1.4,
          hint: 'الأيقونة وحدها لغز؛ الـtooltip يشرحها للفأرة ولقارئ الشاشة معاً.',
        );

  @override
  RuleResult run(List<SourceFile> files) {
    final findings = <Finding>[];
    var total = 0;
    for (final f in files.where((f) => f.isUi)) {
      for (var i = 0; i < f.lines.length; i++) {
        if (f.isNoise(i) || f.isSuppressed(i, id) || !f.lines[i].contains('IconButton(')) continue;
        total++;
        final end = (i + 8) < f.lines.length ? i + 8 : f.lines.length;
        if (!f.lines.sublist(i, end).join('\n').contains('tooltip:')) {
          findings.add(Finding(f.rel, i + 1, f.lines[i]));
        }
      }
    }
    if (total == 0) {
      return RuleResult(
          id: id, title: title, pillar: pillar, weight: weight,
          score: 100, hint: hint, detail: 'لا ينطبق');
    }
    final ok = total - findings.length;
    return RuleResult(
      id: id, title: title, pillar: pillar, weight: weight,
      score: ok / total * 100,
      hint: hint,
      detail: '$ok/$total زر موصوف',
      findings: findings,
    );
  }
}

// ═══════════════════════════════════════════ المحاور ═════════════════════

class Pillar {
  const Pillar(this.key, this.name, this.weight, this.question);
  final String key;
  final String name;
  final double weight;
  final String question;
}

const pillars = <Pillar>[
  Pillar('identity', 'الهوية البصرية والاتساق', 1.2,
      'هل يبدو النظام مصمَّماً بيد واحدة، أم شاشات كتبها أشخاص مختلفون؟'),
  Pillar('layout', 'التخطيط والاستجابة', 1.1,
      'هل يعمل على شاشة كاشير وجهاز لوحي وشاشة مكتب بنفس الجودة؟'),
  Pillar('states', 'اكتمال حالات الواجهة', 1.3,
      'ماذا يرى المستخدم أثناء التحميل، وعند الخطأ، وحين لا توجد بيانات؟'),
  Pillar('usability', 'سهولة الاستخدام والإنتاجية', 1.3,
      'هل يُنجز المحاسب مهمته بأقل عدد نقرات، ومع أمان من الخطأ؟'),
  Pillar('a11y', 'الوصولية ووضوح العرض', 1.0,
      'هل يستطيع مستخدم بضعف بصر أو بلا فأرة تشغيل النظام؟'),
  Pillar('governance', 'الحوكمة والتحكم والصلاحيات', 1.3,
      'هل تظهر الحوكمة في الواجهة نفسها، لا في قاعدة البيانات فقط؟'),
  Pillar('modern', 'الحداثة وعصر الذكاء الاصطناعي', 1.1,
      'هل يبدو النظام من 2026 أم من 2010؟'),
  Pillar('rtl', 'العربية والاتجاه من اليمين', 1.2,
      'هل الواجهة عربية أصلاً، أم إنجليزية معكوسة؟'),
];

// ═══════════════════════════════════════════ تعريف القواعد ═══════════════

List<Rule> buildRules() => [
      // ─────────────────────────── 1. الهوية البصرية ───────────────────────
      ViolationRule(
        id: 'ID-01',
        title: 'ألوان مكتوبة يدوياً خارج نظام الألوان',
        pillar: 'identity',
        weight: 1.5,
        scope: (f) => f.isUi && !f.isTheme,
        pattern: RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)'),
        penaltyPerHit: 4,
        tolerance: 2,
        hint: 'انقل اللون إلى AppColors؛ اللون المكتوب داخل الشاشة لا يتغيّر مع '
            'هوية الزبون، فيكسر خاصية العلامة التجارية لكل منظمة.',
      ),
      ViolationRule(
        id: 'ID-02',
        title: 'استخدام ألوان Flutter الجاهزة (Colors.grey وأخواتها)',
        pillar: 'identity',
        scope: (f) => f.isUi && !f.isTheme,
        pattern: RegExp(r'Colors\.(grey|blue|red|green|orange|purple|teal|amber|indigo|pink|cyan)\b'),
        penaltyPerHit: 3,
        tolerance: 3,
        hint: 'لوحة Material الافتراضية هي بالضبط ما يجعل كل الأنظمة تتشابه؛ '
            'استخدم AppColors.textMuted / success / warning / danger.',
      ),
      ViolationRule(
        id: 'ID-03',
        title: 'أحجام خط مكتوبة يدوياً بدل AppTextStyles',
        pillar: 'identity',
        weight: 1.2,
        scope: (f) => f.isUi && !f.isTheme,
        pattern: RegExp(r'fontSize:\s*\d+'),
        // كما في AC-02: pw.* مجال طباعة له سلّمه الخاص المحكوم بمقاس الورق
        // لا بسلّم الشاشة، فلا معنى لمطالبته بـ AppTextStyles.
        accept: (m, f) => !m.input.contains('pw.'),
        penaltyPerHit: 3,
        tolerance: 4,
        hint: 'سلّم طباعي واحد (displayLg…labelMd) يمنع تدرّج الأحجام العشوائي '
            'الذي يجعل الشاشات تبدو غير متجانسة.',
      ),
      ScaleRule(
        id: 'ID-04',
        title: 'اتساق أنصاف أقطار الحواف',
        pillar: 'identity',
        pattern: RegExp(r'BorderRadius\.circular\((\d+)\)'),
        unit: 'قيمة',
        hint: 'اختلاف نصف القطر بين بطاقتين متجاورتين تلتقطه العين حتى لو لم '
            'يُسمَّ؛ وحّد القيمة النادرة مع السلّم السائد.',
      ),
      ScaleRule(
        id: 'ID-05',
        title: 'اتساق سلّم المسافات',
        pillar: 'identity',
        pattern: RegExp(r'(?:SizedBox\((?:height|width):\s*|EdgeInsets\.all\()(\d+)'),
        unit: 'مسافة',
        maxValue: 48, // ما فوق ذلك أبعاد مقصودة (عرض عمود مثلاً) لا مسافة إيقاع
        hint: 'المسافة الشاذّة تُنتج «اهتزازاً» في المحاذاة يلاحظه المستخدم دون '
            'أن يعرف سببه؛ أعدها إلى أقرب درجة في السلّم السائد.',
      ),
      PresenceRule(
        id: 'ID-06',
        title: 'الشاشات تستهلك نظام التصميم (AppColors/AppTextStyles/Theme)',
        pillar: 'identity',
        weight: 1.3,
        scope: (f) => f.isScreen,
        needle: RegExp(r'AppColors|AppTextStyles|Theme\.of\(context\)'),
        unit: 'شاشة',
        hint: 'شاشة لا تستورد نظام التصميم هي شاشة ستنحرف عن الهوية أول تعديل.',
      ),

      // ─────────────────────────── 2. التخطيط والاستجابة ──────────────────
      PresenceRule(
        id: 'LY-01',
        title: 'الشاشات تستخدم AdaptiveScaffold الموحّد',
        pillar: 'layout',
        weight: 1.5,
        scope: (f) => f.isScreen,
        needle: RegExp(r'AdaptiveScaffold'),
        unit: 'شاشة',
        hint: 'الهيكل الموحّد يضمن أن الشريط الجانبي والعلوي وأزرار الإجراءات '
            'تتصرّف بنفس الطريقة في كل الوحدات.',
      ),
      ViolationRule(
        id: 'LY-05',
        title: 'عارض كسول داخل قياس أبعاد جوهرية',
        pillar: 'layout',
        weight: 1.4,
        // الاجتماع وحده هو المخالفة، لا أيٌّ منهما منفرداً: IntrinsicHeight
        // سليم بذاته (مصمّم الباركود يستعمله بأمان)، وshrinkWrap سليم بذاته.
        // ولا يمكن التمييز نصّياً بين عارض محصور في ارتفاع محدَّد وآخر طليق —
        // SizedBox(height:) فاصلٌ شائع في كل ملف تقريباً، فاشتراط وجوده
        // يجعل القاعدة تمرّ على الملف المعطوب (جُرّب فعلاً ومرّ). لذلك
        // يُبلَّغ عن الاجتماع ويُترك الاستثناء الموثَّق لمن تحقّق من الحصر.
        scope: (f) => f.isUi && f.code.contains('shrinkWrap: true'),
        pattern: RegExp(r'Intrinsic(Height|Width)\('),
        penaltyPerHit: 50,
        hint: 'IntrinsicHeight يقيس أبعاداً جوهرية، والعارض الكسول (ListView '
            'أو GridView بـ shrinkWrap) يرفضها صراحةً فينهار التخطيط كاملاً — '
            'لا يفيض بل يتوقّف عن الرسم. إمّا إزالة القياس الجوهري، أو حصر '
            'العارض في ارتفاع محدَّد ثم توثيق الاستثناء.',
      ),
      ViolationRule(
        id: 'LY-02',
        title: 'نقاط توقف سحرية بدل Breakpoints',
        pillar: 'layout',
        weight: 1.3,
        scope: (f) => f.isUi && !f.rel.contains('breakpoints'),
        pattern: RegExp(r'(size|width)\s*[<>]=?\s*\d{3,4}'),
        penaltyPerHit: 8,
        hint: 'كل رقم عرض مكتوب داخل شاشة هو نقطة انهيار مستقبلية؛ استخدم '
            'Breakpoints.isMobile/isTablet/isDesktop.',
      ),
      PresenceRule(
        id: 'LY-03',
        title: 'الشاشات ذات الجداول تتعامل مع الشاشات الضيقة',
        pillar: 'layout',
        scope: (f) => f.isScreen && f.hasTable,
        needle: RegExp(r'Breakpoints|ResponsiveBuilder|LayoutBuilder|isMobile'),
        unit: 'شاشة جدول',
        hint: 'الجدول العريض على الموبايل يجب أن يتحوّل إلى بطاقات أو تمرير أفقي '
            'صريح، لا أن يفيض.',
      ),
      PresenceRule(
        id: 'LY-04',
        title: 'حماية من فيضان المحتوى الطولي',
        pillar: 'layout',
        scope: (f) => f.isScreen,
        needle: RegExp(r'SingleChildScrollView|ListView|CustomScrollView|Scrollable'),
        unit: 'شاشة',
        hint: 'شاشة بلا تمرير تنكسر على أول جهاز أقصر، أو عند تكبير خط النظام.',
      ),

      // ─────────────────────────── 3. حالات الواجهة ───────────────────────
      PresenceRule(
        id: 'ST-01',
        title: 'حالة التحميل معروضة',
        pillar: 'states',
        weight: 1.3,
        scope: (f) => f.isDataScreen,
        needle: RegExp(r'CircularProgressIndicator|LinearProgressIndicator|loading:|Skeleton|Shimmer'),
        unit: 'شاشة بيانات',
        hint: 'شاشة تنتظر بلا مؤشّر تبدو معطّلة، فيعيد المستخدم النقر ويولّد '
            'طلبات مكرّرة.',
      ),
      PresenceRule(
        id: 'ST-02',
        title: 'حالة الخطأ معالَجة ومعروضة للمستخدم',
        pillar: 'states',
        weight: 1.5,
        scope: (f) => f.isDataScreen,
        needle: RegExp(r'error:|catch\s*\(|onError|DioException'),
        unit: 'شاشة بيانات',
        hint: 'الخطأ الصامت أسوأ من الخطأ الظاهر: يظنّ المستخدم أن البيانات فارغة '
            'فعلاً، فيتّخذ قراراً خاطئاً.',
      ),
      PresenceRule(
        id: 'ST-03',
        title: 'حالة «لا توجد بيانات» مصمَّمة',
        pillar: 'states',
        weight: 1.4,
        scope: (f) => f.isDataScreen && f.hasTable,
        needle: RegExp(r'لا توجد|لا يوجد|لم يتم العثور|فارغ|EmptyState'),
        unit: 'شاشة قائمة',
        hint: 'الحالة الفارغة أول ما يراه زبون جديد؛ اجعلها تشرح الخطوة التالية '
            '(«أضف أول صنف») لا مجرد فراغ أبيض.',
      ),
      PresenceRule(
        id: 'ST-04',
        title: 'إمكانية إعادة المحاولة/التحديث بعد الفشل',
        pillar: 'states',
        scope: (f) => f.isDataScreen,
        needle: RegExp(r'invalidate\(|refresh\(|إعادة المحاولة|onRefresh|RefreshIndicator'),
        unit: 'شاشة بيانات',
        hint: 'بدون زر تحديث، علاج أي خطأ شبكة عابر يصبح إعادة تشغيل التطبيق.',
      ),
      PresenceRule(
        id: 'ST-05',
        title: 'تأكيد نجاح العملية للمستخدم',
        pillar: 'states',
        scope: (f) => f.isScreen && RegExp(r'\.post\(|\.put\(|\.delete\(').hasMatch(f.code),
        needle: RegExp(r'SnackBar|تم '),
        unit: 'شاشة كتابة',
        hint: 'كل عملية تغيّر البيانات تحتاج ردّ فعل مرئي، وإلا كرّرها المستخدم.',
      ),

      // ─────────────────────────── 4. سهولة الاستخدام ─────────────────────
      PresenceRule(
        id: 'UX-01',
        title: 'بحث داخل الشاشات ذات القوائم',
        pillar: 'usability',
        weight: 1.4,
        scope: (f) => f.isScreen && f.hasTable,
        needle: RegExp(r'بحث|search|Search'),
        unit: 'شاشة قائمة',
        hint: 'قائمة أصناف بلا بحث تصبح غير قابلة للاستخدام عند 500 صنف — وهو حجم '
            'متجر صغير.',
      ),
      PresenceRule(
        id: 'UX-02',
        title: 'ترشيح/فرز للقوائم الطويلة',
        pillar: 'usability',
        scope: (f) => f.isScreen && f.hasTable,
        needle: RegExp(r'FilterChip|filter|Filter|sort|Sort|DropdownButton|تصفية|فرز'),
        unit: 'شاشة قائمة',
        hint: 'الترشيح يحوّل الجدول من أرشيف إلى أداة عمل يومية.',
      ),
      PresenceRule(
        id: 'UX-03',
        title: 'ترقيم صفحات أو تحميل تدريجي',
        pillar: 'usability',
        weight: 1.2,
        scope: (f) => f.isScreen && f.hasTable,
        needle: RegExp(r"'page'|page:|limit|offset|pagination|ترقيم|ListView\.builder"),
        unit: 'شاشة قائمة',
        hint: 'تحميل كل السجلات دفعة واحدة يقتل الأداء ويجمّد الواجهة عند التوسّع؛ '
            'وهو أشهر سبب لشكوى «النظام بطيء».',
      ),
      PresenceRule(
        id: 'UX-04',
        title: 'تأكيد قبل العمليات المدمِّرة',
        pillar: 'usability',
        weight: 1.6,
        scope: (f) => f.isUi && RegExp(r'\.delete\(|حذف').hasMatch(f.code),
        needle: RegExp(r'AlertDialog|تأكيد|هل أنت متأكد|confirm'),
        unit: 'شاشة حذف',
        allowDelegate: false,
        hint: 'الحذف بنقرة واحدة في نظام محاسبي كارثة تدقيقية؛ اطلب تأكيداً يذكر '
            'اسم السجل المحذوف.',
      ),
      PresenceRule(
        id: 'UX-05',
        title: 'تحقّق من صحة الإدخال في النماذج',
        pillar: 'usability',
        weight: 1.3,
        scope: (f) => f.isForm,
        needle: RegExp(r'validator:|autovalidate|errorText|Form\('),
        unit: 'نموذج',
        hint: 'التحقّق عند الإدخال أرخص بكثير من تصحيح قيد مالي خاطئ لاحقاً.',
      ),
      PresenceRule(
        id: 'UX-06',
        title: 'نصوص إرشادية داخل الحقول (hint/label)',
        pillar: 'usability',
        scope: (f) => f.isForm,
        needle: RegExp(r'hintText|labelText|helperText'),
        unit: 'نموذج',
        hint: 'الحقل بلا عنوان يجبر المستخدم على التخمين — أو على سؤال الدعم.',
      ),
      PresenceRule(
        id: 'UX-07',
        title: 'تركيز تلقائي في الحوارات لتسريع الإدخال',
        pillar: 'usability',
        scope: (f) => f.isDialog && f.isForm,
        needle: RegExp(r'autofocus|requestFocus|FocusNode'),
        unit: 'حوار',
        hint: 'الكاشير لا يستخدم الفأرة؛ فتح الحوار يجب أن يضع المؤشّر في أول حقل '
            'فوراً.',
      ),
      CapabilityRule(
        id: 'UX-08',
        title: 'اختصارات لوحة مفاتيح للعمليات المتكرّرة',
        pillar: 'usability',
        weight: 1.2,
        pattern: RegExp(r'Shortcuts\(|CallbackAction|LogicalKeyboardKey|KeyboardListener'),
        hint: 'في نقطة البيع، الفرق بين نظام محبوب ومكروه هو مفاتيح F وEnter؛ '
            'الاعتماد على النقر يُبطئ كل فاتورة.',
      ),
      CapabilityRule(
        id: 'UX-09',
        title: 'قارئ باركود / إدخال سريع',
        pillar: 'usability',
        pattern: RegExp(r'barcode|Barcode'),
        searchAll: true,
        hint: 'الإدخال بالباركود هو المسار الطبيعي في التجزئة والمخزون.',
      ),

      // ─────────────────────────── 5. الوصولية ────────────────────────────
      IconTooltipRule(),
      ViolationRule(
        id: 'AC-02',
        title: 'نصوص أصغر من 12 نقطة',
        pillar: 'a11y',
        scope: (f) => f.isUi,
        pattern: RegExp(r'(?<!pw\.TextStyle\()fontSize:\s*(\d+)'),
        // أنماط pw.* تخصّ مستنداً مطبوعاً لا شاشة: 8 نقاط في جدول PDF على
        // ورق A4 مقروءة تماماً، وتكبيرها يُفسد التقرير. الحكم على قياسات
        // الشاشة بمقاييس الشاشة وحدها.
        accept: (m, f) {
          final line = m.input;
          if (line.contains('pw.TextStyle') || line.contains('pw.Text')) return false;
          return (int.tryParse(m.group(1) ?? '99') ?? 99) < 12;
        },
        penaltyPerHit: 10,
        hint: 'أقل من 12 نقطة غير مقروء على شاشة كاشير في إضاءة متجر؛ والأرقام '
            'المالية تحديداً يجب ألّا تُصغَّر أبداً.',
      ),
      CapabilityRule(
        id: 'AC-03',
        title: 'وسوم دلالية لقارئ الشاشة (Semantics)',
        pillar: 'a11y',
        pattern: RegExp(r'Semantics\(|semanticLabel|semanticsLabel'),
        hint: 'بدون Semantics تصبح الأيقونات صامتة تماماً لقارئ الشاشة؛ وهذا شرط '
            'متكرّر في المناقصات الحكومية والمؤسسية.',
      ),
      CapabilityRule(
        id: 'AC-04',
        title: 'أهداف لمس كبيرة مضبوطة مركزياً',
        pillar: 'a11y',
        weight: 1.2,
        pattern: RegExp(r'materialTapTargetSize|MaterialTapTargetSize\.padded|minimumSize'),
        hint: 'ضبط 48 نقطة على مستوى الثيم أفضل من إصلاح كل ودجت على حدة.',
      ),
      CapabilityRule(
        id: 'AC-05',
        title: 'إمكانية نسخ القيم الحسّاسة (SelectableText)',
        pillar: 'a11y',
        pattern: RegExp(r'SelectableText'),
        hint: 'أرقام الفواتير والمعرّفات تُنسخ يومياً؛ منع النسخ يجبر على إعادة '
            'الكتابة يدوياً وما يتبعها من أخطاء.',
      ),
      ViolationRule(
        id: 'AC-06',
        title: 'أيقونات أصغر من 16 نقطة',
        pillar: 'a11y',
        scope: (f) => f.isUi,
        pattern: RegExp(r'Icon\([^)]*size:\s*(\d+)'),
        accept: (m, f) {
          if (m.input.contains('pw.')) return false;
          return (int.tryParse(m.group(1) ?? '99') ?? 99) < 16;
        },
        penaltyPerHit: 8,
        hint: 'الأيقونة الصغيرة تفقد معناها قبل أن تفقد وضوحها.',
      ),

      // ─────────────────────────── 6. الحوكمة والتحكم ─────────────────────
      CapabilityRule(
        id: 'GV-01',
        title: 'مصفوفة صلاحيات مرئية للمدير',
        pillar: 'governance',
        weight: 1.5,
        pattern: RegExp(r'permissions_matrix|PermissionsMatrix|مصفوفة الصلاحيات'),
        searchAll: true,
        hint: 'الحوكمة التي لا يستطيع المدير رؤيتها وتعديلها بنفسه ليست حوكمة، بل '
            'اعتماد دائم على المطوّر.',
      ),
      PresenceRule(
        id: 'GV-02',
        title: 'إخفاء/تعطيل الإجراءات حسب صلاحية المستخدم',
        pillar: 'governance',
        weight: 1.6,
        scope: (f) => f.isScreen,
        // is_platform_admin آلية صلاحيات مشروعة لا تقلّ عن مصفوفة الأدوار:
        // هي البوابة بين بائع النظام وعملائه، ومقصودٌ إبقاؤها خارج المصفوفة
        // (وإلا منح مدير منظمة نفسه صلاحيات على المنصّة كلها). القاعدة كانت
        // تجهلها فتُرسّب شاشة تحرس نفسها بها فعلاً.
        needle: RegExp(
            r'can\(|hasPermission|[Pp]ermission|role|Role|صلاحية|is_platform_admin|isPlatformAdmin'),
        unit: 'شاشة',
        allowDelegate: false,
        hint: 'زر يظهر ثم يفشل بـ403 تجربة سيئة؛ الصلاحية يجب أن تُقرأ في الواجهة '
            'أيضاً لا في الخادم وحده.',
      ),
      CapabilityRule(
        id: 'GV-03',
        title: 'سجل تدقيق (Audit Log) في الواجهة',
        pillar: 'governance',
        weight: 1.4,
        pattern: RegExp(r'audit_log|AuditLog|سجل التدقيق|سجل العمليات'),
        searchAll: true,
        hint: 'من غيّر السعر ومتى — سؤال يُطرح في كل نزاع محاسبي.',
      ),
      CapabilityRule(
        id: 'GV-04',
        title: 'عزل متعدّد المنظمات والفروع في الواجهة',
        pillar: 'governance',
        weight: 1.4,
        pattern: RegExp(r'organizationId|organization_id|branchId|branch_id'),
        searchAll: true,
        hint: 'اختيار الفرع/المنظمة يجب أن يكون ظاهراً دائماً، وإلا أدخل المستخدم '
            'بيانات في الفرع الخطأ.',
      ),
      CapabilityRule(
        id: 'GV-05',
        title: 'تخصيص هوية العميل (ألوان/شعار) من الإعدادات',
        pillar: 'governance',
        weight: 1.2,
        pattern: RegExp(r'BrandingProvider|primary_color|branding'),
        searchAll: true,
        hint: 'المرونة المؤسسية تبدأ من قدرة الزبون على رؤية علامته هو.',
      ),
      CapabilityRule(
        id: 'GV-06',
        title: 'إدارة مستخدمين وأدوار من داخل النظام',
        pillar: 'governance',
        pattern: RegExp(r'users_screen|UsersScreen|إدارة المستخدمين'),
        searchAll: true,
        hint: 'إضافة موظف جديد يجب ألّا تمرّ عبر الدعم الفني.',
      ),
      CapabilityRule(
        id: 'GV-07',
        title: 'قوالب/تخصيص المستندات (فواتير، باركود)',
        pillar: 'governance',
        pattern: RegExp(r'barcode_designer|template|قالب'),
        searchAll: true,
        hint: 'كل زبون يريد فاتورته بشكله؛ التخصيص بلا كود شرط في السوق المؤسسي.',
      ),

      // ─────────────────────────── 7. الحداثة والذكاء ─────────────────────
      CapabilityRule(
        id: 'MD-01',
        title: 'لوحة تحكم تحليلية بالرسوم البيانية',
        pillar: 'modern',
        weight: 1.3,
        pattern: RegExp(r'fl_chart|LineChart|BarChart|PieChart'),
        searchAll: true,
        hint: 'المدير يريد إجابة بصرية في ثانيتين، لا جدولاً يقرأه.',
      ),
      CapabilityRule(
        id: 'MD-02',
        title: 'تحديث لحظي (Realtime) بدل التحديث اليدوي',
        pillar: 'modern',
        weight: 1.2,
        pattern: RegExp(r'signalr|SignalR|HubConnection|WebSocket'),
        searchAll: true,
        hint: 'المخزون الذي لا يتحدّث لحظياً يبيع صنفاً نفد فعلاً.',
      ),
      CapabilityRule(
        id: 'MD-03',
        title: 'مركز إشعارات موحّد',
        pillar: 'modern',
        pattern: RegExp(r'notifications_screen|NotificationsScreen'),
        searchAll: true,
        hint: 'الإشعارات تحوّل النظام من أداة تُفتح إلى نظام يبلّغك.',
      ),
      CapabilityRule(
        id: 'MD-04',
        title: 'انتقالات وحركات دقيقة (Micro-interactions)',
        pillar: 'modern',
        weight: 1.2,
        pattern: RegExp(r'Animated[A-Z]\w+|Hero\(|TweenAnimationBuilder|FadeTransition'),
        hint: 'الحركة القصيرة الهادفة (150–250 مللي) هي أرخص فرق بين واجهة تبدو '
            'حديثة وأخرى تبدو ثابتة وقديمة.',
      ),
      CapabilityRule(
        id: 'MD-05',
        title: 'هياكل تحميل (Skeleton) بدل دوّار الانتظار',
        pillar: 'modern',
        pattern: RegExp(r'Skeleton|Shimmer|shimmer'),
        hint: 'الهيكل يُشعِر المستخدم أن المحتوى «قادم»، ويُقلّل الإحساس بالبطء دون '
            'تسريع فعلي.',
      ),
      CapabilityRule(
        id: 'MD-06',
        title: 'الوضع الليلي / تبديل السمة',
        pillar: 'modern',
        weight: 1.1,
        pattern: RegExp(r'ThemeMode|Brightness\.dark|darkTheme'),
        searchAll: true,
        hint: 'الوضع الليلي صار توقّعاً افتراضياً، خصوصاً لورديات المساء.',
      ),
      CapabilityRule(
        id: 'MD-07',
        title: 'لوحة أوامر / بحث شامل (Ctrl+K)',
        pillar: 'modern',
        weight: 1.2,
        pattern: RegExp(r'CommandPalette|GlobalSearch|بحث شامل|showSearch'),
        searchAll: true,
        hint: 'البحث الشامل أوضح إشارة على واجهة من هذا العقد: تكتب اسم الزبون '
            'فتصل إليه من أي شاشة.',
      ),
      CapabilityRule(
        id: 'MD-08',
        title: 'ذكاء اصطناعي/مساعد أو اقتراحات ذكية',
        pillar: 'modern',
        weight: 1.4,
        pattern: RegExp(r'\bAI\b|assistant|مساعد ذكي|توصيات|forecast|توقّع|anomaly|insight|رؤى'),
        searchAll: true,
        hint: 'أوضح فرصة متاحة: توقّع نفاد المخزون، كشف الفواتير الشاذة، وتلخيص '
            'التقارير بالعربية. غيابها اليوم أبرز فجوة تسويقية.',
      ),
      CapabilityRule(
        id: 'MD-09',
        title: 'تصدير التقارير (PDF/Excel)',
        pillar: 'modern',
        pattern: RegExp(r'pdf|Pdf|excel|Excel|xlsx|تصدير'),
        searchAll: true,
        hint: 'التقرير غير القابل للتصدير لا يصل إلى مجلس الإدارة.',
      ),
      CapabilityRule(
        id: 'MD-10',
        title: 'عمل دون اتصال / تخزين محلي',
        pillar: 'modern',
        pattern: RegExp(r'offline|sqflite|hive|isar|طابور'),
        searchAll: true,
        hint: 'انقطاع الإنترنت في متجر لا يجب أن يوقف البيع؛ ميزة حاسمة في السوق '
            'المحلي.',
      ),

      // ─────────────────────────── 8. العربية والاتجاه ────────────────────
      CapabilityRule(
        id: 'RT-01',
        title: 'ضبط الاتجاه واللغة العربية مركزياً',
        pillar: 'rtl',
        weight: 1.5,
        pattern: RegExp(r"TextDirection\.rtl|Locale\('ar|supportedLocales|flutter_localizations"),
        searchAll: true,
        hint: 'الاتجاه يُضبط مرّة واحدة في جذر التطبيق، لا في كل شاشة.',
      ),
      ViolationRule(
        id: 'RT-02',
        title: 'حشوات يمين/يسار ثابتة بدل الاتجاهية',
        pillar: 'rtl',
        weight: 1.4,
        scope: (f) => f.isUi,
        pattern: RegExp(r'EdgeInsets\.only\([^)]*\b(left|right):'),
        penaltyPerHit: 4,
        tolerance: 3,
        hint: 'استخدم EdgeInsetsDirectional.only(start/end) — الحشوة الثابتة لا '
            'تنقلب مع الاتجاه فتُنتج محاذاة معكوسة في العربية.',
      ),
      ViolationRule(
        id: 'RT-03',
        title: 'محاذاة ثابتة بدل AlignmentDirectional',
        pillar: 'rtl',
        weight: 1.2,
        scope: (f) => f.isUi,
        pattern: RegExp(r'Alignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)'),
        // pw.Alignment نوع مستقل في حزمة PDF لا يملك نظيراً اتجاهياً أصلاً،
        // واتجاه المستند يُدار هناك عبر مغلِّفات pdfLtr/pdfAutoDir. مطالبته
        // بـ AlignmentDirectional مطالبة بشيء غير موجود.
        accept: (m, f) => !m.input.contains('pw.'),
        penaltyPerHit: 5,
        tolerance: 2,
        hint: 'AlignmentDirectional.centerStart تعمل صحيحاً في الاتجاهين؛ '
            'centerLeft لا.',
      ),
      DirectionIconRule(),
      ViolationRule(
        id: 'RT-05',
        title: 'نصوص واجهة إنجليزية ظاهرة للمستخدم',
        pillar: 'rtl',
        weight: 1.3,
        scope: (f) => f.isUi,
        pattern: RegExp(r"""(?:Text\(|hintText:\s*|labelText:\s*)['"]([A-Za-z][A-Za-z ]{3,})['"]"""),
        penaltyPerHit: 4,
        tolerance: 4,
        hint: 'أي نص إنجليزي متسرّب يكسر الانطباع بأن النظام عربي أصلاً، لا مترجَم.',
      ),
      PresenceRule(
        id: 'RT-06',
        title: 'تنسيق الأرقام والتواريخ والعملة موضعياً',
        pillar: 'rtl',
        // معرِّفات إنجليزية فقط لا كلمات عربية: «سعر» و«مبلغ» تردان في نصوص
        // شرح داخل الواجهة («الكاشير يكتب قيمة الصنف بدل سعر ثابت») فتُدخِل
        // شاشة الإعدادات في نطاق قاعدة مالية لا تعرض رقماً مالياً واحداً.
        // أسماء الحقول في الشيفرة هي الدليل على وجود قيمة مالية معروضة.
        scope: (f) => f.isScreen && RegExp(r'\b(price|amount|total|balance)\b').hasMatch(f.code),
        needle: RegExp(r'NumberFormat|DateFormat|CurrencyBadge|intl'),
        unit: 'شاشة مالية',
        hint: 'الأرقام المالية بلا تنسيق موحّد (فواصل، خانتان عشريتان، د.ل) تبدو غير '
            'احترافية وتُقرأ خطأً.',
      ),
    ];

// ═══════════════════════════════════════════ التشغيل والإخراج ════════════

void main(List<String> args) {
  final flags = args.toSet();
  final wantJson = flags.contains('--json');
  final wantMd = flags.contains('--md');
  final details = flags.contains('--details');
  final pillarFilter = args
      .firstWhere((a) => a.startsWith('--pillar='), orElse: () => '')
      .replaceFirst('--pillar=', '');
  final failUnder = double.tryParse(args
      .firstWhere((a) => a.startsWith('--fail-under='), orElse: () => '')
      .replaceFirst('--fail-under=', ''));

  // يُشغَّل السكربت أحياناً من داخل مجلد فرعي (أو من الـIDE)، فنصعد حتى نجد
  // جذر المشروع بدل أن نفشل بخطأ يربك المستخدم.
  var dir = Directory.current;
  while (!Directory('${dir.path}/lib').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('خطأ: لم يُعثر على جذر المشروع (مجلد lib) من ${Directory.current.path}');
      exit(2);
    }
    dir = parent;
  }
  Directory.current = dir;
  final root = Directory('lib');

  final files = <SourceFile>[];
  for (final e in root.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    if (e.path.contains('.g.dart') || e.path.contains('.freezed.dart')) continue;
    files.add(SourceFile(e.path.replaceAll(r'\', '/'), e.readAsStringSync()));
  }

  var rules = buildRules();
  if (pillarFilter.isNotEmpty) {
    rules = rules.where((r) => r.pillar == pillarFilter).toList();
    if (rules.isEmpty) {
      stderr.writeln('محور غير معروف: $pillarFilter');
      stderr.writeln('المحاور المتاحة: ${pillars.map((p) => p.key).join(', ')}');
      exit(2);
    }
  }

  final results = [for (final r in rules) r.run(files)];

  // درجة كل محور = متوسط مرجّح لقواعده.
  final byPillar = <String, List<RuleResult>>{};
  for (final r in results) {
    byPillar.putIfAbsent(r.pillar, () => []).add(r);
  }
  final pillarScores = <String, double>{};
  for (final entry in byPillar.entries) {
    final w = entry.value.fold<double>(0, (a, r) => a + r.weight);
    final s = entry.value.fold<double>(0, (a, r) => a + r.score * r.weight);
    pillarScores[entry.key] = w == 0 ? 0 : s / w;
  }
  final active = pillars.where((p) => pillarScores.containsKey(p.key)).toList();
  final totalW = active.fold<double>(0, (a, p) => a + p.weight);
  final overall = active.fold<double>(0, (a, p) => a + pillarScores[p.key]! * p.weight) / totalW;

  if (wantJson) {
    print(const JsonEncoder.withIndent('  ').convert({
      'version': kVersion,
      'generatedAt': DateTime.now().toIso8601String(),
      'filesScanned': files.length,
      'overall': double.parse(overall.toStringAsFixed(1)),
      'grade': _grade(overall),
      'pillars': {
        for (final p in active)
          p.key: {'name': p.name, 'score': double.parse(pillarScores[p.key]!.toStringAsFixed(1))}
      },
      'rules': [
        for (final r in results)
          {
            'id': r.id,
            'title': r.title,
            'pillar': r.pillar,
            'score': double.parse(r.score.toStringAsFixed(1)),
            'detail': r.detail,
            'findings': [for (final f in r.findings.take(50)) '${f.rel}:${f.line}'],
          }
      ],
    }));
  } else {
    _printReport(files.length, results, pillarScores, active, overall, details);
  }

  if (wantMd) {
    Directory('docs').createSync(recursive: true);
    File('docs/UX_AUDIT_REPORT.md')
        .writeAsStringSync(_markdown(files.length, results, pillarScores, active, overall));
    if (!wantJson) print('📄 كُتب التقرير المفصّل في docs/UX_AUDIT_REPORT.md\n');
  }

  if (failUnder != null && overall < failUnder) {
    stderr.writeln('✗ الدرجة ${overall.toStringAsFixed(1)} أقل من الحد المطلوب $failUnder');
    exit(1);
  }
}

String _grade(double s) {
  if (s >= 90) return 'ممتاز — جاهز للعرض التجاري';
  if (s >= 80) return 'جيد جداً — فجوات محدودة';
  if (s >= 70) return 'جيد — يحتاج جولة تحسين قبل البيع المؤسسي';
  if (s >= 60) return 'مقبول — فجوات ملموسة في تجربة المستخدم';
  return 'ضعيف — يحتاج إعادة نظر في طبقة الواجهة';
}

String _bar(double score, {int width = 24}) {
  final filled = (score / 100 * width).round();
  return '${'#' * filled}${'.' * (width - filled)}';
}

String _mark(double s) => s >= 90 ? '[v]' : (s >= 70 ? '[~]' : '[x]');

void _printReport(
  int fileCount,
  List<RuleResult> results,
  Map<String, double> pillarScores,
  List<Pillar> active,
  double overall,
  bool details,
) {
  final line = '=' * 74;
  print('\n$line');
  print('  تدقيق جماليات وتجربة المستخدم — Kinetic Enterprise ERP   (v$kVersion)');
  print('  $fileCount ملف Dart · ${results.length} قاعدة · '
      '${DateTime.now().toString().split('.').first}');
  print(line);

  print('\n  الدرجة الإجمالية: ${overall.toStringAsFixed(1)}/100   ${_grade(overall)}');
  print('  ${_bar(overall, width: 50)}\n');

  print('  المحاور');
  print('  ${'-' * 70}');
  for (final p in active) {
    final s = pillarScores[p.key]!;
    print('  ${_mark(s)} ${p.name.padRight(28)} ${_bar(s)} ${s.toStringAsFixed(0).padLeft(3)}');
  }

  for (final p in active) {
    final rs = results.where((r) => r.pillar == p.key).toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    print('\n  ${'-' * 70}');
    print('  > ${p.name} — ${pillarScores[p.key]!.toStringAsFixed(0)}/100');
    print('    ${p.question}');
    print('  ${'-' * 70}');
    for (final r in rs) {
      print('  ${_mark(r.score)} [${r.id}] ${r.title}');
      print('        النتيجة ${r.score.toStringAsFixed(0)}  ·  ${r.detail}');
      if (r.score < 100 && r.hint.isNotEmpty) {
        for (final l in _wrap(r.hint, 62)) {
          print('        - $l');
        }
      }
      if (r.score < 100 && r.findings.isNotEmpty) {
        final show = details ? r.findings : r.findings.take(4).toList();
        for (final f in show) {
          print('          • ${f.line > 0 ? '${f.rel}:${f.line}' : f.rel}');
        }
        if (!details && r.findings.length > show.length) {
          print('          • … و${r.findings.length - show.length} أخرى (شغّل --details)');
        }
      }
    }
  }

  // أولويات العمل: الأثر = وزن القاعدة × وزن المحور × حجم الفجوة.
  final pw = {for (final p in pillars) p.key: p.weight};
  double impact(RuleResult r) => (100 - r.score) * r.weight * (pw[r.pillar] ?? 1);
  final ranked = results.where((r) => r.score < 95).toList()
    ..sort((a, b) => impact(b).compareTo(impact(a)));

  print('\n$line');
  print('  أولويات التحسين — مرتّبة حسب الأثر على التجربة');
  print(line);
  if (ranked.isEmpty) {
    print('  لا توجد فجوات ذات أثر — النظام مستوفٍ لكل القواعد.');
  }
  var i = 1;
  for (final r in ranked.take(10)) {
    final p = pillars.firstWhere((x) => x.key == r.pillar);
    print('  ${i.toString().padLeft(2)}. [${r.id}] ${r.title}');
    print('      ${r.score.toStringAsFixed(0)}/100 · ${p.name} · ${r.detail}');
    i++;
  }
  print('');
}

List<String> _wrap(String text, int width) {
  final out = <String>[];
  var cur = '';
  for (final w in text.split(' ')) {
    if ((cur + w).length > width) {
      out.add(cur.trim());
      cur = '';
    }
    cur += '$w ';
  }
  if (cur.trim().isNotEmpty) out.add(cur.trim());
  return out;
}

String _markdown(
  int fileCount,
  List<RuleResult> results,
  Map<String, double> pillarScores,
  List<Pillar> active,
  double overall,
) {
  final b = StringBuffer();
  b.writeln('# تقرير تدقيق تجربة المستخدم والجماليات');
  b.writeln();
  b.writeln('> مُولَّد آلياً بـ `dart run tool/ux_audit.dart --md` — إصدار $kVersion  ');
  b.writeln('> التاريخ: ${DateTime.now().toString().split('.').first}  ');
  b.writeln('> الملفات المفحوصة: $fileCount · القواعد: ${results.length}');
  b.writeln();
  b.writeln('## الخلاصة');
  b.writeln();
  b.writeln('**${overall.toStringAsFixed(1)}/100 — ${_grade(overall)}**');
  b.writeln();
  b.writeln('| المحور | الدرجة | السؤال الذي يجيب عنه |');
  b.writeln('|---|---:|---|');
  for (final p in active) {
    b.writeln('| ${p.name} | ${pillarScores[p.key]!.toStringAsFixed(0)} | ${p.question} |');
  }
  b.writeln();

  for (final p in active) {
    b.writeln('## ${p.name} — ${pillarScores[p.key]!.toStringAsFixed(0)}/100');
    b.writeln();
    final rs = results.where((r) => r.pillar == p.key).toList()
      ..sort((a, c) => a.score.compareTo(c.score));
    for (final r in rs) {
      b.writeln('### ${_mark(r.score)} ${r.id} — ${r.title}');
      b.writeln();
      b.writeln('- **النتيجة:** ${r.score.toStringAsFixed(0)}/100 (${r.detail})');
      if (r.hint.isNotEmpty) b.writeln('- **لماذا يهم:** ${r.hint}');
      if (r.score < 100 && r.findings.isNotEmpty) {
        b.writeln('- **المواقع:**');
        for (final f in r.findings.take(20)) {
          b.writeln('  - `${f.rel}${f.line > 0 ? ':${f.line}' : ''}`');
        }
        if (r.findings.length > 20) {
          b.writeln('  - … و${r.findings.length - 20} موقعاً آخر');
        }
      }
      b.writeln();
    }
  }
  return b.toString();
}
