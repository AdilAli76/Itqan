import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/features/pos/data/pos_layout.dart';

/// تخطيط نقطة البيع — أنماطُه وأدواته وحساب أعمدته.
///
/// <para><b>لماذا يستحقّ اختباراً:</b> خطأٌ هنا لا يُخرج شاشةً حمراء بل
/// **فاتورةً فيها ما لم يُطلَب**: زرٌّ أضيق من إصبع يُضغط فيُضاف غيرُه،
/// ولا يكتشفه أحد إلا الزبون في الإيصال — إن قرأه. وإعدادٌ لا يُفهم يُغلق
/// نقطة البيع في وجه طابورٍ واقف.</para>
void main() {
  group('لكلّ قطاعٍ ما يحتاجه', () {
    test('الأربعة معرَّفة ولكلٍّ أدواته', () {
      for (final preset in PosLayoutPreset.values) {
        final layout = PosLayout.defaultFor(preset);
        expect(layout.preset, preset);
        expect(layout.tools, isNotEmpty, reason: '$preset بلا أدوات');
      }
    });

    test('المقهى بلا وزن، والسوبرماركت به', () {
      // العطب الذي يمسكه: قائمةٌ واحدة تُنسخ للأنماط كلّها، فيحمل المقهى
      // زرّ وزنٍ لا يُستعمل ويفقد السوبرماركت زرّاً يُستعمل في كل فاتورة.
      expect(PosLayout.defaultFor(PosLayoutPreset.touchGrid).tools, isNot(contains(PosTool.weight)));
      expect(PosLayout.defaultFor(PosLayoutPreset.scanFast).tools, contains(PosTool.weight));
    });

    test('والضيّقة أقلّها أدوات', () {
      // سبع بوصات: كل أداةٍ زائدة تأكل من مساحة السلّة نفسها.
      final compact = PosLayout.defaultFor(PosLayoutPreset.compact).tools.length;
      final wide = PosLayout.defaultFor(PosLayoutPreset.scanFast).tools.length;
      expect(compact, lessThan(wide));
    });

    test('ولا تتبدّل شاشةُ أحدٍ لأنّنا أضفنا أنماطاً', () {
      // الكلاسيكي هو سلوك النظام قبل هذا الملف، وهو ما يقع بلا اختيار.
      expect(PosLayout.autoPresetFor(1440), PosLayoutPreset.classic);
      expect(PosLayout.autoPresetFor(1024), PosLayoutPreset.classic);
    });

    test('إلا الضيّقة فتُفرَض عليها', () {
      expect(PosLayout.autoPresetFor(480), PosLayoutPreset.compact);
    });
  });

  group('أعمدةٌ تُضغط بالإصبع', () {
    test('الشبكة لا تتجاوز ما يتّسع له العرض', () {
      // 600 ÷ 120 = خمسة أزرارٍ لمسية، لا أكثر مهما طُلب.
      expect(PosLayout.gridColumnsFor(width: 600, touch: true), 5);
    });

    test('وبالفأرة تزيد — المؤشّر يصيب نقطةً بعينها', () {
      expect(
        PosLayout.gridColumnsFor(width: 600, touch: false),
        greaterThan(PosLayout.gridColumnsFor(width: 600, touch: true)),
      );
    });

    test('واختيار المالك يُقيَّد بما يتّسع لا يُنفَّذ كما كُتب', () {
      // بيت الداء: ستّة أعمدة على شاشةٍ تحمل ثلاثة تُنتج أزراراً بعرض
      // إصبعٍ ونصف — يضغط الكاشير فيُضاف غيرُ ما أراد.
      final fits = PosLayout.gridColumnsFor(width: 400, touch: true);
      expect(PosLayout.gridColumnsFor(width: 400, touch: true, requested: 6), fits);
    });

    test('وما دون ما يتّسع يُحترم — من أراد أزراراً أكبر فله ذلك', () {
      expect(PosLayout.gridColumnsFor(width: 1200, touch: true, requested: 3), 3);
    });

    test('ولا شبكة بصفر عمود مهما ضاقت الشاشة', () {
      // شبكةٌ بلا أعمدة تعني شاشةً فارغة بلا رسالة تقول لماذا.
      expect(PosLayout.gridColumnsFor(width: 50, touch: true), 1);
      expect(PosLayout.gridColumnsFor(width: 0, touch: true), 1);
    });
  });

  group('الجهاز ثم الفرع ثم المنظمة', () {
    final device = PosLayout.defaultFor(PosLayoutPreset.scanFast);
    final branch = PosLayout.defaultFor(PosLayoutPreset.touchGrid);
    final org = PosLayout.defaultFor(PosLayoutPreset.classic);

    test('اختيار الجهاز يغلب — شاشة الكاشير غير شاشة المدير', () {
      final r = PosLayout.resolve(device: device, branch: branch, organization: org, width: 1400);
      expect(r.preset, PosLayoutPreset.scanFast);
    });

    test('ثم الفرع — فرع المطعم غير فرع البقالة في نفس الشركة', () {
      final r = PosLayout.resolve(branch: branch, organization: org, width: 1400);
      expect(r.preset, PosLayoutPreset.touchGrid);
    });

    test('ثم المنظمة', () {
      final r = PosLayout.resolve(organization: org, width: 1400);
      expect(r.preset, PosLayoutPreset.classic);
    });

    test('وبلا اختيارٍ أصلاً: الافتراضي بحسب العرض', () {
      expect(PosLayout.resolve(width: 1400).preset, PosLayoutPreset.classic);
      expect(PosLayout.resolve(width: 480).preset, PosLayoutPreset.compact);
    });

    test('وضيق الشاشة يغلب الاختيار كلّه', () {
      // شبكة مطعمٍ بأربعة أعمدة على شاشة سبع بوصات أزرارٌ لا تُضغط.
      final r = PosLayout.resolve(device: branch, width: 420);
      expect(r.preset, PosLayoutPreset.compact);
    });

    test('لكنّ أدوات المالك وترتيبها تبقى كما اختارها', () {
      // ما يُفرض هو التخطيط لا الاختيار: من وضع «المعلَّقة» أوّلاً يجدها
      // أوّلاً على الشاشة الصغيرة أيضاً.
      final r = PosLayout.resolve(device: branch, width: 420);
      expect(r.tools, branch.tools);
    });
  });

  group('إعدادٌ يُقرأ على أجهزةٍ نسخُها متفاوتة', () {
    test('يعود كما حُفظ', () {
      final original = PosLayout.defaultFor(PosLayoutPreset.scanFast)
          .copyWith(cartOnLeft: true, gridColumns: 3);
      final back = PosLayout.tryParse(original.encode())!;
      expect(back.preset, original.preset);
      expect(back.tools, original.tools);
      expect(back.cartOnLeft, isTrue);
      expect(back.gridColumns, 3);
    });

    test('وأداةٌ لا يعرفها هذا الإصدار تُتجاهَل ويُفتح الباقي', () {
      // جهاز الكاشير يُحدَّث بعد جهاز المدير بأسبوع. والبديل شاشةُ بيعٍ
      // لا تفتح لأن في إعدادها كلمةً لم تُفهم.
      final layout = PosLayout.tryParse(
        '{"preset":"scanFast","tools":["weight","teleportation","customer"]}',
      )!;
      expect(layout.tools, [PosTool.weight, PosTool.customer]);
    });

    test('والمكرّر يُسقَط بأوّل ظهوره', () {
      final layout = PosLayout.tryParse(
        '{"preset":"classic","tools":["customer","discount","customer"]}',
      )!;
      expect(layout.tools, [PosTool.customer, PosTool.discount]);
    });

    test('وقائمةٌ لم يُفهم منها شيء تعود إلى أدوات النمط لا إلى شريطٍ فارغ', () {
      // شريطٌ فارغ يُخفي الحسم والعميل والإرجاع عن الكاشير بلا سبب ظاهر.
      final layout = PosLayout.tryParse('{"preset":"classic","tools":["xx","yy"]}')!;
      expect(layout.tools, PosLayout.defaultFor(PosLayoutPreset.classic).tools);
    });

    test('ومن أراد شريطاً فارغاً حقاً فله ذلك', () {
      final layout = PosLayout.tryParse('{"preset":"classic","tools":[]}')!;
      expect(layout.tools, isEmpty);
    });

    test('ونمطٌ مجهول يُقرأ كلاسيكياً لا يُسقط الشاشة', () {
      expect(PosLayout.tryParse('{"preset":"hologram"}')!.preset, PosLayoutPreset.classic);
    });

    test('وإعدادٌ تالف لا يُسقط نقطة البيع', () {
      // البيع لا ينتظر إصلاح تفضيل عرض.
      expect(PosLayout.tryParse('{ ليس جيسون'), isNull);
      expect(PosLayout.tryParse('[]'), isNull);
      expect(PosLayout.tryParse(''), isNull);
      expect(PosLayout.tryParse(null), isNull);
    });
  });

  group('حدودٌ تُراجَع معاً', () {
    test('عتبة الضيّق هي عتبة الهاتف نفسها', () {
      // عتبتان لنفس المعنى تفترقان عند أوّل تعديل، فتصير الشاشة عموداً
      // واحداً في تخطيطٍ يظنّ نفسه عمودين.
      expect(PosLayoutSizes.compactWidth, 600);
    });

    test('وزرّ اللمس أكبر من زرّ الفأرة، وكلاهما فوق هدف اللمس الموصى به', () {
      expect(PosLayoutSizes.touchTile, greaterThan(PosLayoutSizes.pointerTile));
      expect(PosLayoutSizes.pointerTile, greaterThanOrEqualTo(44));
    });
  });
}
