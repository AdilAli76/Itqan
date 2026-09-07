import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/core/purchasing/landed_cost.dart';

/// توزيع مصاريف الشحنة بالقيمة.
///
/// <para><b>لماذا يستحقّ اختباراً:</b> خطأٌ هنا لا يُخرج شاشةً حمراء — يُخرج
/// **ربحاً أعلى ممّا هو**. والبضاعة تُباع بسعرٍ يبدو رابحاً وهو خاسر، ولا
/// يظهر ذلك إلا في جردٍ أو ميزانٍ بعد أشهر.</para>
///
/// <para>ويقارن الملفّين معاً: الصيغة في الخادم (`Data/LandedCost.cs`) هي
/// مصدر الحقيقة، ونسخة الواجهة تُريها قبل الحفظ. وانحرافُ أحدهما يعني
/// شاشةً تَعِد بتكلفةٍ ويحفظ الخادم غيرها.</para>
void main() {
  group('التوزيع بالقيمة', () {
    test('صنفٌ بعشرة وشحنةٌ بمئة وخمسين — مثال الميدان', () {
      // مئة قطعة بعشرة = ١٠٠٠، وشحنة ١٥٠ ← ١٫٥٠ على الوحدة، فالتكلفة ١١٫٥٠.
      // والبيع بـ١٣ ربحه ١٫٥٠ لا ٣ — وهو الفرق الذي كان يضيع كلّه.
      final shares = LandedCost.perUnitShares(
        lines: [(quantity: 100, unitCost: 10)],
        totalCharges: 150,
      );
      expect(shares.single, closeTo(1.50, 0.0001));
    });

    test('الأغلى يحمل أكثر — لا بالكمية', () {
      // العطب الذي يمسكه: التوزيع بالكمية يُحمّل كيساً رخيصاً مثل ما يُحمّل
      // ذهباً، فيخرج الكيس أغلى من ثمنه.
      final shares = LandedCost.perUnitShares(
        lines: [
          (quantity: 10, unitCost: 100), // قيمته 1000
          (quantity: 10, unitCost: 10), //  قيمته 100
        ],
        totalCharges: 110,
      );
      expect(shares[0], closeTo(10.0, 0.01));
      expect(shares[1], closeTo(1.0, 0.01));
    });

    test('مجموع الأنصبة يساوي المصاريف بالضبط — ولا يضيع قرش', () {
      // ثلاثة أسطر متساوية ومصاريف عشرة: ٣٫٣٣ ثلاث مرّات = ٩٫٩٩. القرش
      // الباقي يُعطى لأكبر السطور بدل أن يتبخّر من قيمة المخزون.
      const lines = [
        (quantity: 1.0, unitCost: 100.0),
        (quantity: 1.0, unitCost: 100.0),
        (quantity: 1.0, unitCost: 100.0),
      ];
      final shares = LandedCost.perUnitShares(lines: lines, totalCharges: 10);

      var total = 0.0;
      for (var i = 0; i < lines.length; i++) {
        total += shares[i] * lines[i].quantity;
      }
      expect(total, closeTo(10.0, 0.0001));
    });

    test('بلا مصاريف: لا نصيب ولا تغيّر في التكلفة', () {
      final shares = LandedCost.perUnitShares(
        lines: [(quantity: 5, unitCost: 20)],
        totalCharges: 0,
      );
      expect(shares.single, 0);
    });

    test('سطرٌ بقيمة صفر لا يأخذ شيئاً ولا يُسقط الحساب', () {
      // هديّة من المورّد، أو سعرٌ لم يُكتب بعد: القسمة على قيمةٍ صفر تُنتج
      // NaN تنتشر في كل الأسعار المعروضة.
      final shares = LandedCost.perUnitShares(
        lines: [
          (quantity: 10, unitCost: 0),
          (quantity: 10, unitCost: 10),
        ],
        totalCharges: 50,
      );
      expect(shares[0], 0);
      expect(shares[1], closeTo(5.0, 0.0001));
    });

    test('كلُّ القيمة صفر: لا توزيع بدل قسمةٍ على صفر', () {
      final shares = LandedCost.perUnitShares(
        lines: [(quantity: 3, unitCost: 0)],
        totalCharges: 90,
      );
      expect(shares.single, 0);
    });
  });

  group('الواجهة والخادم يحسبان الشيء نفسه', () {
    final server = File('backend/KineticEnterprise.Api/Data/LandedCost.cs').readAsStringSync();

    test('الخادم يوزّع بالقيمة لا بالكمية', () {
      expect(server, contains('line.Value / totalValue'));
    });

    test('ويجبر الكسر على أكبر السطور — كنسخة الواجهة', () {
      expect(server, contains('OrderByDescending(l => l.Value)'));
      expect(server, contains('remainder'));
    });

    test('ويقرّب بعيداً عن الصفر — وإلا اختلف القرش بين الشاشة والحفظ', () {
      expect(server, contains('MidpointRounding.AwayFromZero'));
    });

    test('وسطرٌ بلا قيمة لا يأخذ شيئاً', () {
      expect(server, contains('if (totalValue <= 0) return shares;'));
    });
  });

  group('المصاريف تدخل التكلفة والدفتر', () {
    final controller =
        File('backend/KineticEnterprise.Api/Controllers/PurchaseOrdersController.cs').readAsStringSync();

    test('الدفعة تدخل بالتكلفة المحمَّلة لا بسعر المورّد', () {
      // وهو بيت الداء: سعر المورّد في الدفعة يعني تكلفة بضاعةٍ مباعة ناقصة
      // أبداً — والربح أعلى ممّا هو بمقدار الشحن كلّه.
      expect(controller, contains('unitCost: landedUnitCost'));
      expect(controller, contains('product.CostPrice = landedUnitCost;'));
    });

    test('ونصيب الوحدة يُحسب على الكميّة المطلوبة قبل الحلقة', () {
      // احتسابُه داخل الحلقة بعد تعديل سعر سطرٍ يجعل مجموع الأنصبة لا
      // يساوي المصاريف؛ وعلى المستلَم يجعل تكلفة الوحدة تختلف باختلاف يوم
      // وصول شحنتها.
      expect(controller, contains('var chargeShares = SharesOf(order, chargesTotal);'));
    });

    test('والقيد يفصل ذمّة المورّد عن مستحقّ الشحن', () {
      // ضمُّ الشحن إلى «بضاعة وردت ولم تُفوتَر» يجعل رصيده لا يطابق كشف أي
      // مورّد، فيبطل استعماله في المطابقة أصلاً.
      expect(controller, contains('AccountRoles.LandedCostAccrual'));
      expect(controller, contains('supplierClaim'));
    });

    test('ومردود الشراء لا يُحمّل المورّد شحناً لم يقبضه', () {
      // المخزون يخرج محمَّلاً، والمورّد يُقيَّد بسعره وحده، والفرق مصروف.
      expect(controller, contains('returnedCharges'));
      expect(controller, contains('new PostingLine(AccountRoles.GeneralExpense, charges, 0)'));
    });
  });
}
