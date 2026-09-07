/// توزيع مصاريف الشحنة على أصنافها — **بالقيمة**.
///
/// <para><b>سبب وجوده في الواجهة أيضاً:</b> الحساب الرسمي في الخادم
/// (`Data/LandedCost.cs`) وهو مصدر الحقيقة. لكن التسعير يقع **قبل الحفظ**:
/// من يكتب مصاريف الشحنة ثم يضغط «سعّر بهامش ٢٥٪» يجب أن يرى التكلفة
/// المحمَّلة في اللحظة، لا بعد رحلةٍ إلى الخادم وعودة. وهامشٌ يُحسب على سعر
/// المورّد وحده خسارةٌ مقنّعة — وهو بالضبط ما تمنعه هذه الشاشة.</para>
///
/// <para>والصيغة نفسها في الملفّين، ويحرسهما اختبارٌ بالأرقام ذاتها
/// (`test/landed_cost_test.dart`) — فانحرافُ أحدهما يسقط الفحص.</para>
class LandedCost {
  const LandedCost._();

  /// نصيب الوحدة من المصاريف لكل سطر، بمفتاح ترتيب السطر في القائمة.
  ///
  /// <para>القسمة بالقيمة ثم على الكميّة. والكسور تُجمَع ولا تُهمَل: ثلاثة
  /// أسطر ومصاريف عشرة تُنتج ٣٫٣٣ ثلاث مرّات = ٩٫٩٩، فيضيع قرشٌ من قيمة
  /// المخزون في كل شحنة — فيُعطى الفرق لأكبر السطور قيمةً، أقلِّها تأثّراً
  /// بالقرش في تكلفة وحدته.</para>
  static List<double> perUnitShares({
    required List<({double quantity, double unitCost})> lines,
    required double totalCharges,
  }) {
    final shares = List<double>.filled(lines.length, 0);
    if (totalCharges <= 0 || lines.isEmpty) return shares;

    final values = lines.map((l) => l.quantity * l.unitCost).toList();
    final totalValue = values.fold<double>(0, (a, b) => a + b);
    if (totalValue <= 0) return shares;

    final assigned = List<double>.filled(lines.length, 0);
    var running = 0.0;
    for (var i = 0; i < lines.length; i++) {
      assigned[i] = _round2(totalCharges * (values[i] / totalValue));
      running += assigned[i];
    }

    final remainder = _round2(totalCharges - running);
    if (remainder != 0) {
      var biggest = 0;
      for (var i = 1; i < values.length; i++) {
        if (values[i] > values[biggest]) biggest = i;
      }
      assigned[biggest] = _round2(assigned[biggest] + remainder);
    }

    for (var i = 0; i < lines.length; i++) {
      shares[i] = lines[i].quantity > 0 ? assigned[i] / lines[i].quantity : 0;
    }
    return shares;
  }

  /// تقريبٌ إلى قرشين بعيداً عن الصفر — مطابقٌ لـ`MidpointRounding.AwayFromZero`
  /// في الخادم. وتقريبُ دارت الافتراضي إلى الزوجي يُنتج فرقاً بالقرش بين
  /// ما تراه الشاشة وما يحفظه الخادم.
  static double _round2(double value) {
    final scaled = value * 100;
    final rounded = scaled < 0 ? -(scaled.abs() + 0.5).floorToDouble() : (scaled + 0.5).floorToDouble();
    return rounded / 100;
  }
}
