using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// الرقم المرجعيّ لتكلفة الصنف — بالطريقة التي اختارتها المنظمة.
///
/// <para><b>ما لا يفعله هذا الملف:</b> لا يمسّ تكلفة البضاعة المباعة. تلك
/// تُقرأ من الدفعة التي خرجت منها البضاعة فعلاً في
/// <see cref="StockLedger.IssueAsync"/> — دفعةً دفعة وبتكلفتها هي، وهو أدقّ
/// من أي متوسط. وتحويلُها إلى متوسطٍ يُفقد النظام دقّةً يملكها.</para>
///
/// <para><b>وما يفعله:</b> يجيب عن سؤالٍ لا مفرّ منه: صنفٌ في مخزنه شحنتان
/// بسعرين، وبطاقتُه تعرض **رقماً واحداً** يقيس عليه الحدّ الأدنى للسعر
/// ويُعرض به الهامش. فأيّهما يُقال؟ والجواب قرارُ إدارةٍ لا قاعدةٌ واحدة —
/// راجع <see cref="CostingMethods"/>.</para>
/// </summary>
public static class InventoryCosting
{
    /// <summary>
    /// التكلفة المرجعيّة بعد استلام شحنة.
    /// </summary>
    /// <param name="method">اختيار المنظمة — راجع [CostingMethods].</param>
    /// <param name="receivedUnitCost">
    /// تكلفة الوحدة المحمَّلة في هذه الشحنة — جوابُ «آخر شراء»، وهي أيضاً
    /// ما يُرجَع إليه إن لم يكن في الدفتر ما يُحسب عليه.
    /// </param>
    public static async Task<decimal> ReferenceCostAsync(
        AppDbContext db, string? method, Guid productId, decimal receivedUnitCost)
    {
        if (method == CostingMethods.WeightedAverage)
        {
            return await WeightedAverageAsync(db, productId) ?? receivedUnitCost;
        }

        if (method == CostingMethods.Batch)
        {
            return await NextIssueCostAsync(db, productId) ?? receivedUnitCost;
        }

        // آخر شراء — الافتراضي، وسلوك النظام قبل وجود هذا الإعداد.
        return receivedUnitCost;
    }

    /// <summary>
    /// قيمة ما بقي في الدفتر مقسومةً على كميّته.
    ///
    /// <para>على الدفعات المفتوحة لا على كل ما دخل يوماً: بضاعةٌ بيعت
    /// خرجت بتكلفتها، وضمُّها إلى المتوسط يُبقي أثر سعرٍ لم يعد في المخزن
    /// منه شيء.</para>
    ///
    /// <para>وعلى الفروع كلّها: التكلفة حقلٌ على الصنف لا على الفرع، فحصرُها
    /// بفرعٍ يجعل الرقم يتغيّر بحسب أيّ فرعٍ استلم آخر شحنة.</para>
    /// </summary>
    static async Task<decimal?> WeightedAverageAsync(AppDbContext db, Guid productId)
    {
        var lots = await db.StockLedgerEntries
            .Where(e => e.ProductId == productId && e.RemainingQuantity > 0 && !e.IsCancelled)
            .Select(e => new { e.RemainingQuantity, e.UnitCost })
            .ToListAsync();

        var quantity = lots.Sum(l => l.RemainingQuantity);
        if (quantity <= 0) return null;

        return lots.Sum(l => l.RemainingQuantity * l.UnitCost) / quantity;
    }

    /// <summary>
    /// تكلفة الدفعة التي ستخرج في البيع التالي.
    ///
    /// <para>الترتيب هو ترتيب الصرف نفسه — الأقدم صلاحيةً أوّلاً ثم الأقدم
    /// دخولاً (راجع <see cref="StockLedger.IssueAsync"/>). واختيارُ ترتيبٍ
    /// آخر هنا يجعل البطاقة تَعِد بتكلفةٍ والفاتورة تُحمّل غيرها.</para>
    /// </summary>
    static async Task<decimal?> NextIssueCostAsync(AppDbContext db, Guid productId)
    {
        var next = await db.StockLedgerEntries
            .Where(e => e.ProductId == productId && e.RemainingQuantity > 0 && !e.IsCancelled)
            .OrderBy(e => e.ExpiryDate == null ? 1 : 0)
            .ThenBy(e => e.ExpiryDate)
            .ThenBy(e => e.PostedAt)
            .Select(e => (decimal?)e.UnitCost)
            .FirstOrDefaultAsync();

        return next;
    }
}
