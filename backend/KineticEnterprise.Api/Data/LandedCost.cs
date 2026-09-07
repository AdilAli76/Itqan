namespace KineticEnterprise.Api.Data;

/// <summary>
/// توزيع مصاريف الشحنة على أصنافها — **بالقيمة**.
///
/// <para><b>سبب وجوده:</b> صنفٌ بعشرة من المورّد وشحنةٌ بمئة وخمسين ليست
/// تكلفته عشرة. وقبل هذا كان سعر المورّد وحده هو تكلفة الصنف وتكلفة البضاعة
/// المباعة معاً — فالربح يظهر أعلى ممّا هو بمقدار الشحن كلّه، وقد تُباع
/// البضاعة بخسارةٍ والتقرير يقول ربحاً.</para>
///
/// <para><b>ولماذا بالقيمة لا بالكمية:</b> الشحن يُدفع على شحنةٍ فيها ذهبٌ
/// وأكياس. والتوزيع بالكمية يُحمّل الكيس مثل ما يُحمّل الذهب، فيخرج الكيس
/// أغلى من ثمنه ويخرج الذهب بلا شيء. والقيمة أقرب ما يكون إلى ما دُفع
/// فعلاً حين يكون الشحن على القيمة (وهو الغالب في الاستيراد: التأمين
/// والجمارك بالقيمة أصلاً).</para>
///
/// <para><b>والنصيب يُحسب على الكميّة المطلوبة لا المستلَمة:</b> الشحنة قد
/// تصل على دفعات، ونصيبُ الوحدة يجب أن يكون واحداً في الدفعة الأولى
/// والأخيرة — وإلا اختلفت تكلفة الوحدة من نفس الأمر باختلاف يوم وصولها،
/// وهو فرقٌ لا يفسّره شيء في الواقع.</para>
/// </summary>
public static class LandedCost
{
    /// <summary>سطرٌ كما يدخل الحساب: كميّته وسعر المورّد لوحدته.</summary>
    public readonly record struct Line(Guid Id, decimal Quantity, decimal UnitCost)
    {
        public decimal Value => Quantity * UnitCost;
    }

    /// <summary>
    /// نصيب الوحدة من المصاريف لكل سطر.
    ///
    /// <para>القسمة على القيمة، ثم على الكميّة — فيخرج ما يُضاف إلى سعر
    /// المورّد للوحدة الواحدة. والسطر بقيمةٍ صفر (هديّة، أو خطأ إدخال) لا
    /// يأخذ شيئاً: توزيعُ الشحن على ما لا قيمة له يُنتج قسمةً على صفر أو
    /// تحميلاً بلا أساس.</para>
    ///
    /// <para><b>والكسور تُجمَع ولا تُهمَل:</b> ثلاثة أسطر ومصاريف عشرة
    /// دنانير تُنتج ٣٫٣٣ ثلاث مرّات = ٩٫٩٩، فيضيع قرشٌ من قيمة المخزون في
    /// كل شحنة. فيُعطى الفرق لأكبر السطور قيمةً — أقلّها تأثّراً بالقرش في
    /// تكلفة وحدته.</para>
    /// </summary>
    public static Dictionary<Guid, decimal> PerUnitShares(
        IReadOnlyList<Line> lines, decimal totalCharges, int moneyDecimals = 2)
    {
        var shares = lines.ToDictionary(l => l.Id, _ => 0m);
        if (totalCharges <= 0 || lines.Count == 0) return shares;

        var totalValue = lines.Sum(l => l.Value);
        if (totalValue <= 0) return shares;

        // المبلغ المُسنَد لكل سطر أوّلاً (لا نصيب الوحدة): القرش يُجبَر على
        // مستوى السطر، وقسمتُه على الكميّة بعد ذلك تُبقي المجموع مضبوطاً.
        var assigned = new Dictionary<Guid, decimal>();
        var running = 0m;

        foreach (var line in lines)
        {
            var amount = Math.Round(totalCharges * (line.Value / totalValue), moneyDecimals,
                MidpointRounding.AwayFromZero);
            assigned[line.Id] = amount;
            running += amount;
        }

        var remainder = totalCharges - running;
        if (remainder != 0)
        {
            var biggest = lines.OrderByDescending(l => l.Value).First();
            assigned[biggest.Id] += remainder;
        }

        foreach (var line in lines)
        {
            shares[line.Id] = line.Quantity > 0 ? assigned[line.Id] / line.Quantity : 0m;
        }

        return shares;
    }

    /// <summary>
    /// التكلفة المحمَّلة للوحدة: سعر المورّد زائد نصيبها من المصاريف.
    ///
    /// <para>وهي التي تُخزَّن على الدفعة وتُحسب منها تكلفة البضاعة المباعة
    /// وتُقاس عليها الأسعار — لا سعر المورّد.</para>
    /// </summary>
    public static decimal UnitCostOf(LandedCost.Line line, Dictionary<Guid, decimal> shares) =>
        line.UnitCost + shares.GetValueOrDefault(line.Id);
}
