using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

/// <param name="Severity">critical | warning | info</param>
/// <param name="Action">مسار الشاشة التي تعالج الحالة، إن وُجدت.</param>
public record InsightDto(
    string Kind,
    string Severity,
    string Title,
    string Detail,
    string? Action,
    decimal? Value);

/// <summary>
/// رؤى تشغيلية مستخرَجة من بيانات المنظمة نفسها.
///
/// لماذا تحليل إحصائي محلي لا نموذج لغوي خارجي:
///
///  1. النشر لدى العميل — خادم ويندوز داخل المتجر (راجع DEPLOYMENT.md).
///     إرسال حركة مبيعات وأسعار تكلفة إلى خدمة خارجية قرارٌ تعاقدي لا
///     تقني، ولا يجوز أن يُتخذ ضمناً بإضافة ميزة.
///  2. هذه الأسئلة الأربعة لها إجابات حسابية دقيقة لا احتمالية. «متى ينفد
///     هذا الصنف» قسمةٌ لا استنتاج، ونموذج لغوي هنا يضيف كلفة وتأخيراً
///     وعدم حتمية مقابل لا شيء.
///  3. تعمل بلا إنترنت وبلا مفتاح API وبلا كلفة لكل طلب.
///
/// النموذج اللغوي يبقى إضافة ممكنة فوق هذه الطبقة — لصياغة ملخّص شهري
/// بالعربية مثلاً — لكنه ليس بديلاً عنها، وهذه هي الطبقة التي تُبنى أولاً.
/// </summary>
[ApiController]
[Route("api/insights")]
[Authorize]
[RequirePermission("reports.view")]
public class InsightsController : ControllerBase
{
    private readonly AppDbContext _db;
    public InsightsController(AppDbContext db) => _db = db;

    /// <param name="windowDays">نافذة حساب متوسط البيع اليومي.</param>
    [HttpGet]
    public async Task<ActionResult<List<InsightDto>>> GetAll([FromQuery] int windowDays = 30)
    {
        windowDays = Math.Clamp(windowDays, 7, 180);
        var since = DateTime.UtcNow.AddDays(-windowDays);

        var insights = new List<InsightDto>();
        insights.AddRange(await StockoutForecast(since, windowDays));
        insights.AddRange(await DeadStock(since));
        insights.AddRange(await NegativeMargin());
        insights.AddRange(await AnomalousInvoices(since));

        // الأخطر أولاً: قائمة رؤى غير مرتّبة بالخطورة تُقرأ من أعلاها فتُهمل
        // الحالة الحرجة إن وقعت في آخرها.
        var order = new Dictionary<string, int> { ["critical"] = 0, ["warning"] = 1, ["info"] = 2 };
        return insights
            .OrderBy(i => order.GetValueOrDefault(i.Severity, 3))
            .ThenByDescending(i => i.Value ?? 0)
            .Take(20)
            .ToList();
    }

    /// <summary>
    /// متى ينفد كل صنف: الرصيد ÷ متوسط البيع اليومي.
    ///
    /// يتجاوز ما يفعله تنبيه «حدّ إعادة الطلب» الثابت: صنفٌ رصيده 40 وحدّه 10
    /// يبدو سليماً، لكنه إن كان يبيع 8 يومياً فسينفد خلال خمسة أيام — قبل أن
    /// يصل أي أمر شراء. الحدّ الثابت يقيس الكمية، وهذا يقيس الزمن، والزمن هو
    /// ما يحتاجه قرار الشراء.
    /// </summary>
    private async Task<List<InsightDto>> StockoutForecast(DateTime since, int windowDays)
    {
        var sold = await _db.InvoiceItems
            .Join(_db.Invoices.Where(v => v.CreatedAt >= since && v.InvoiceType == "sale"),
                  it => it.InvoiceId, v => v.Id, (it, v) => it)
            .GroupBy(it => it.ProductId)
            .Select(g => new { ProductId = g.Key, Qty = g.Sum(x => x.Quantity) })
            .ToListAsync();

        if (sold.Count == 0) return new List<InsightDto>();

        var ids = sold.Select(x => x.ProductId).ToList();
        var stock = await _db.StockLevels
            .Where(s => ids.Contains(s.ProductId))
            .GroupBy(s => s.ProductId)
            .Select(g => new { ProductId = g.Key, Qty = g.Sum(x => x.Quantity) })
            .ToDictionaryAsync(x => x.ProductId, x => x.Qty);

        var names = await _db.Products
            .Where(p => ids.Contains(p.Id) && !p.IsDeleted)
            .ToDictionaryAsync(p => p.Id, p => p.Name);

        var result = new List<InsightDto>();
        foreach (var row in sold)
        {
            if (!names.TryGetValue(row.ProductId, out var name)) continue;
            var perDay = row.Qty / windowDays;
            if (perDay <= 0) continue;

            var onHand = stock.GetValueOrDefault(row.ProductId, 0);
            var days = (int)Math.Floor((double)(onHand / perDay));
            if (days > 14) continue;

            result.Add(new InsightDto(
                "stockout",
                days <= 3 ? "critical" : "warning",
                days <= 0 ? $"نفد المخزون: {name}" : $"ينفد خلال {days} يوم: {name}",
                $"الرصيد {onHand:0.##} ووسطي البيع {perDay:0.##} يومياً خلال آخر {windowDays} يوماً.",
                "/purchasing",
                days));
        }
        return result;
    }

    /// <summary>
    /// بضاعة راكدة: رصيد قائم بلا أي بيع خلال النافذة.
    ///
    /// تُعرض بقيمتها بسعر التكلفة لا بعددها: «120 قطعة راكدة» رقم بلا معنى
    /// قراري، أما «رأس مال مجمَّد 8,400 د.ل» فهو ما يدفع المدير للتخفيض أو
    /// الإرجاع للمورّد.
    /// </summary>
    private async Task<List<InsightDto>> DeadStock(DateTime since)
    {
        var soldIds = await _db.InvoiceItems
            .Join(_db.Invoices.Where(v => v.CreatedAt >= since), it => it.InvoiceId, v => v.Id, (it, v) => it.ProductId)
            .Distinct()
            .ToListAsync();

        var stagnant = await _db.StockLevels
            .Where(s => s.Quantity > 0 && !soldIds.Contains(s.ProductId))
            .GroupBy(s => s.ProductId)
            .Select(g => new { ProductId = g.Key, Qty = g.Sum(x => x.Quantity) })
            .ToListAsync();

        if (stagnant.Count == 0) return new List<InsightDto>();

        var ids = stagnant.Select(x => x.ProductId).ToList();
        var products = await _db.Products
            .Where(p => ids.Contains(p.Id) && !p.IsDeleted)
            .ToDictionaryAsync(p => p.Id, p => p);

        var rows = stagnant
            .Where(x => products.ContainsKey(x.ProductId))
            .Select(x => new { P = products[x.ProductId], x.Qty, Capital = x.Qty * products[x.ProductId].CostPrice })
            .Where(x => x.Capital > 0)
            .OrderByDescending(x => x.Capital)
            .Take(5)
            .ToList();

        return rows.Select(x => new InsightDto(
            "dead_stock",
            "info",
            $"بضاعة راكدة: {x.P.Name}",
            $"{x.Qty:0.##} وحدة بلا أي حركة بيع، رأس مال مجمَّد {x.Capital:0.00}.",
            "/inventory",
            x.Capital)).ToList();
    }

    /// <summary>
    /// أصناف سعر بيعها دون تكلفتها — خسارة مؤكَّدة في كل عملية بيع.
    ///
    /// أشيع أسبابها ارتفاع تكلفة التوريد دون تحديث سعر البيع، وهي تمرّ
    /// صامتة لأن لا شاشة في النظام تقارن الرقمين تلقائياً.
    /// </summary>
    private async Task<List<InsightDto>> NegativeMargin()
    {
        var losing = await _db.Products
            .Where(p => !p.IsDeleted && p.CostPrice > 0 && p.SalePrice > 0 && p.SalePrice < p.CostPrice)
            .OrderBy(p => p.SalePrice - p.CostPrice)
            .Take(5)
            .ToListAsync();

        return losing.Select(p => new InsightDto(
            "negative_margin",
            "critical",
            $"بيع بخسارة: {p.Name}",
            $"سعر البيع {p.SalePrice:0.00} أقل من التكلفة {p.CostPrice:0.00} — خسارة {p.CostPrice - p.SalePrice:0.00} لكل وحدة.",
            "/inventory",
            p.CostPrice - p.SalePrice)).ToList();
    }

    /// <summary>
    /// فواتير شاذّة القيمة: أعلى من المتوسط بأكثر من ثلاثة انحرافات معيارية.
    ///
    /// ليست اتهاماً بل نقطة تدقيق: الفاتورة الشاذّة قد تكون بيعاً بالجملة
    /// مشروعاً، وقد تكون خطأ في الكمية (صفر زائد) أو تلاعباً. القاعدة
    /// الإحصائية تُظهرها للمراجعة البشرية، ولا تحكم عليها.
    ///
    /// عتبة الانحرافات الثلاثة مقصودة: أقل منها يُغرق المدير بتنبيهات عن
    /// فواتير عادية فيتوقّف عن قراءتها كلها — وهو أسوأ من غياب التنبيه.
    /// </summary>
    private async Task<List<InsightDto>> AnomalousInvoices(DateTime since)
    {
        var invoices = await _db.Invoices
            .Where(v => v.CreatedAt >= since && v.InvoiceType == "sale" && v.Status != "refunded")
            .Select(v => new { v.InvoiceNumber, v.TotalAmount, v.CreatedAt })
            .ToListAsync();

        // أقل من ثلاثين فاتورة لا يعطي متوسطاً ولا انحرافاً لهما معنى.
        if (invoices.Count < 30) return new List<InsightDto>();

        var amounts = invoices.Select(v => (double)v.TotalAmount).ToList();
        var mean = amounts.Average();
        var variance = amounts.Sum(a => (a - mean) * (a - mean)) / amounts.Count;
        var sd = Math.Sqrt(variance);
        if (sd <= 0) return new List<InsightDto>();

        var threshold = mean + 3 * sd;
        return invoices
            .Where(v => (double)v.TotalAmount > threshold)
            .OrderByDescending(v => v.TotalAmount)
            .Take(5)
            .Select(v => new InsightDto(
                "anomaly",
                "warning",
                $"فاتورة غير معتادة: {v.InvoiceNumber}",
                $"قيمتها {v.TotalAmount:0.00} مقابل متوسط {mean:0.00} للفترة — تستحق مراجعة.",
                "/invoices",
                v.TotalAmount))
            .ToList();
    }
}
