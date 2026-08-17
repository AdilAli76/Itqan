using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// الطريق الوحيد لحساب رصيد محفظة عميل في كامل النظام — لا يوجد عمود رصيد
/// مخزَّن يمكن أن يتعارض معه (راجع libyan_models/ACCOUNTING_RULES.md §3).
/// أي كنترولر يحتاج الرصيد يستدعي هذه الدالة، فيستحيل أن يحسبه موضعان
/// بقاعدتين مختلفتين.
/// </summary>
public static class WalletBalances
{
    public static async Task<decimal> ComputeAsync(AppDbContext db, Guid customerId)
    {
        // الجمع يتم على مستوى SQL (لا تحميل كل الحركات للذاكرة) — التقسيم
        // إلى داخل/خارج عبر WalletKinds.InKinds/OutKinds ضروري لأن EF لا
        // يترجم WalletKinds.SignOf نفسها. الاستعلام يجلب المجموعين فقط،
        // لا صفوف الحركات، ويستفيد من IX_customer_wallet_tx_customer.
        var totals = await db.CustomerWalletTransactions
            .Where(t => t.CustomerId == customerId)
            .GroupBy(t => 1)
            .Select(g => new
            {
                In = g.Where(t => WalletKinds.InKinds.Contains(t.Kind)).Sum(t => (decimal?)t.Amount) ?? 0,
                Out = g.Where(t => WalletKinds.OutKinds.Contains(t.Kind)).Sum(t => (decimal?)t.Amount) ?? 0,
            })
            .FirstOrDefaultAsync();

        return totals is null ? 0 : totals.In - totals.Out;
    }

    /// <summary>
    /// أرصدة مجموعة عملاء في استعلام تجميع واحد بدل استعلام لكل عميل.
    ///
    /// يُرجع القاموس مباشرة فلا يتكرر منطق الجمع في كل كنترولر يعرض قائمة —
    /// وهو ما كان مكرَّراً حرفياً في CustomersController قبل توحيده هنا.
    /// </summary>
    public static async Task<Dictionary<Guid, decimal>> ComputeManyAsync(
        AppDbContext db, IReadOnlyCollection<Guid> customerIds)
    {
        if (customerIds.Count == 0) return new Dictionary<Guid, decimal>();

        return await db.CustomerWalletTransactions
            .Where(t => customerIds.Contains(t.CustomerId))
            .GroupBy(t => t.CustomerId)
            .Select(g => new
            {
                CustomerId = g.Key,
                In = g.Where(t => WalletKinds.InKinds.Contains(t.Kind)).Sum(t => (decimal?)t.Amount) ?? 0,
                Out = g.Where(t => WalletKinds.OutKinds.Contains(t.Kind)).Sum(t => (decimal?)t.Amount) ?? 0,
            })
            .ToDictionaryAsync(x => x.CustomerId, x => x.In - x.Out);
    }

    /// <summary>
    /// مجموع ما مُنح للعميل من استحقاق داخل الفترة الجارية — للتحقق من السقف.
    /// </summary>
    /// <param name="periodStart">
    /// بداية الفترة المُشتقّة من تاريخ الانتهاء. تُستخدَم كحد أدنى فقط: إن وُجد
    /// إسقاطٌ أحدث منها فهو البداية الحقيقية للفترة الجارية.
    /// </param>
    public static async Task<decimal> GrantedInPeriodAsync(
        AppDbContext db, Guid customerId, DateTime periodStart)
    {
        // آخر إسقاط استحقاق يفصل الفترة المنتهية عن الجارية فصلاً قاطعاً.
        //
        // بدون هذا الحد كان تجديد الفترة لا يُصفّر السقف: منحة الشهر الماضي
        // تقع داخل النافذة المُشتقّة من تاريخ الانتهاء الجديد، فتُحتسب مرتين
        // ويرفض النظام منح المستفيد استحقاقه الجديد كاملاً.
        var lastExpiry = await db.CustomerWalletTransactions
            .Where(t => t.CustomerId == customerId && t.Kind == WalletKinds.EntitlementExpiry)
            .MaxAsync(t => (DateTime?)t.CreatedAt);

        var start = lastExpiry is not null && lastExpiry > periodStart ? lastExpiry.Value : periodStart;

        return await db.CustomerWalletTransactions
            .Where(t => t.CustomerId == customerId
                     && t.Kind == WalletKinds.EntitlementGrant
                     && t.CreatedAt >= start)
            .SumAsync(t => (decimal?)t.Amount) ?? 0;
    }
}
