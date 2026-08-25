using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record DailyRevenuePoint(DateTime Date, decimal Revenue, int InvoiceCount);
public record ProductSalesPoint(Guid ProductId, string ProductName, decimal QuantitySold, decimal Revenue);
public record BranchSalesPoint(Guid BranchId, string BranchName, decimal Revenue, int InvoiceCount);
public record CashierSalesPoint(Guid? CashierId, string CashierName, decimal Revenue, int InvoiceCount);

public record SalesSummaryDto(
    decimal TotalRevenue, int TotalInvoices, decimal AverageInvoiceValue,
    decimal TotalReturns, int ReturnCount,
    List<DailyRevenuePoint> RevenueByDay,
    List<ProductSalesPoint> TopProducts,
    List<BranchSalesPoint> RevenueByBranch,
    List<CashierSalesPoint> RevenueByCashier);

public record DebtAgingRowDto(
    Guid CustomerId, string CustomerName, string? Phone, decimal TotalOutstanding,
    decimal NotYetDue, decimal Days1To30, decimal Days31To60, decimal Days61To90, decimal Over90,
    DateTime? OldestDueDate, int DaysOverdue, int Stage,
    int? LastReminderStage, DateTime? LastReminderAt);

public record DebtAgingReportDto(
    decimal TotalOutstanding, decimal NotYetDue,
    decimal Days1To30, decimal Days31To60, decimal Days61To90, decimal Over90,
    List<DebtAgingRowDto> Items);

public record InventoryValuationItemDto(
    Guid ProductId, string Sku, string ProductName, string UnitBase,
    decimal Quantity, decimal TotalValue,
    /// متوسط التكلفة الفعلي المحسوب من الدفتر.
    decimal AverageCost,
    /// سعر التكلفة المسجَّل على الصنف — للمقارنة لا للحساب.
    decimal ProductCostPrice,
    int LotCount);

public record InventoryValuationDto(
    decimal TotalValue,
    /// القيمة بالطريقة القديمة (سعر تكلفة الصنف × الكمية) — لإظهار الفارق.
    decimal LegacyValue,
    int ProductCount, List<InventoryValuationItemDto> Items);

public record ItemCardEntryDto(
    DateTime PostedAt, string SourceType, Guid? SourceId,
    string BatchNumber, DateTime? ExpiryDate,
    decimal QuantityChange, decimal BalanceAfter, decimal UnitCost, decimal ValueChange,
    string? UserName, bool IsCancelled);

public record ItemCardDto(
    Guid ProductId, string Sku, string ProductName, string UnitBase,
    List<ItemCardEntryDto> Entries);

public record LowStockItemDto(Guid ProductId, string ProductName, decimal Quantity, decimal ReorderLevel);

/// <summary>صنف بلغ حدّ إعادة الطلب — بما يكفي لاتخاذ قرار الشراء بلا شاشة أخرى.</summary>
public record ReorderItemDto(
    Guid ProductId, string Sku, string ProductName, string UnitBase,
    Guid? SupplierId, string? SupplierName,
    decimal Quantity,
    /// ما صدر به أمر شراء ولم يصل بعد.
    decimal OnOrderQuantity,
    /// الموجود + القادم − المحجوز. عليها يُقاس النقص لا على الموجود وحده.
    decimal ProjectedQuantity,
    /// الحدّ اليدوي المضبوط على الصنف.
    decimal ConfiguredReorderLevel,
    /// متوسط ما يُباع يومياً في نافذة القياس.
    decimal AvgDailyUsage,
    int LeadTimeDays,
    /// الحدّ المقترَح = الاستهلاك اليومي × (مهلة التوريد + أيام الأمان).
    decimal SuggestedReorderLevel,
    /// الكمية المقترَح شراؤها لتغطية المهلة والأمان معاً.
    decimal SuggestedOrderQuantity,
    /// كم يوماً يكفي الرصيد الحالي. null = لا استهلاك في النافذة.
    decimal? DaysOfCover,
    decimal CostPrice);

public record ReorderReportDto(
    int WindowDays, int CoverageDays, DateTime From, DateTime To,
    List<ReorderItemDto> Items);
public record ExpiringItemDto(Guid ProductId, string ProductName, decimal Quantity, DateTime ExpiryDate, decimal EstimatedLossValue);

public record InventorySummaryDto(
    decimal TotalInventoryValue, int TotalProducts,
    int LowStockCount, List<LowStockItemDto> LowStockItems,
    int ExpiredCount, decimal ExpiredLossValue, List<ExpiringItemDto> ExpiredItems,
    int NearExpiryCount, List<ExpiringItemDto> NearExpiryItems);

/// <summary>
/// موديول التقارير (ARCHITECTURE.md §2.9): مبيعات، مخزون، فواقد الصلاحية،
/// أداء الفروع، أداء الكاشير. تصدير PDF/Excel مؤجَّل — هذا الإصدار عرض حي
/// داخل التطبيق فقط. لا حاجة لفلترة organization_id/branch_id يدوياً هنا:
/// InvoicesPolicy وStockLevelsPolicy تُطبَّقان تلقائياً (مدير فرع لا يرى إلا
/// أرقام فرعه، بلا أي كود إضافي في هذا الملف).
/// </summary>
[ApiController]
[Route("api/reports")]
[Authorize]
[RequirePermission("reports.view")]
public class ReportsController : ControllerBase
{
    private readonly AppDbContext _db;
    public ReportsController(AppDbContext db) => _db = db;

    [HttpGet("sales-summary")]
    public async Task<ActionResult<SalesSummaryDto>> SalesSummary([FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var rangeFrom = from ?? DateTime.UtcNow.Date.AddDays(-29);
        var rangeTo = (to ?? DateTime.UtcNow.Date).AddDays(1);

        var invoices = await _db.Invoices
            .Include(i => i.Items)
            .Where(i => i.CreatedAt >= rangeFrom && i.CreatedAt < rangeTo)
            .ToListAsync();

        var sales = invoices.Where(i => i.InvoiceType == "sale").ToList();
        var returns = invoices.Where(i => i.InvoiceType == "return").ToList();
        var totalRevenue = sales.Sum(i => i.TotalAmount);

        var revenueByDay = sales
            .GroupBy(i => i.CreatedAt.Date)
            .Select(g => new DailyRevenuePoint(g.Key, g.Sum(i => i.TotalAmount), g.Count()))
            .OrderBy(p => p.Date)
            .ToList();

        var productIds = sales.SelectMany(i => i.Items).Select(item => item.ProductId).Distinct().ToList();
        var productNames = await _db.Products.Where(p => productIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id, p => p.Name);
        var topProducts = sales.SelectMany(i => i.Items)
            .GroupBy(item => item.ProductId)
            .Select(g => new ProductSalesPoint(g.Key, productNames.GetValueOrDefault(g.Key, "-"), g.Sum(x => x.Quantity), g.Sum(x => x.LineTotal)))
            .OrderByDescending(p => p.Revenue)
            .Take(10)
            .ToList();

        var branchIds = sales.Select(i => i.BranchId).Distinct().ToList();
        var branchNames = await _db.Branches.Where(b => branchIds.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name);
        var revenueByBranch = sales
            .GroupBy(i => i.BranchId)
            .Select(g => new BranchSalesPoint(g.Key, branchNames.GetValueOrDefault(g.Key, "-"), g.Sum(i => i.TotalAmount), g.Count()))
            .OrderByDescending(b => b.Revenue)
            .ToList();

        var cashierIds = sales.Where(i => i.CreatedBy.HasValue).Select(i => i.CreatedBy!.Value).Distinct().ToList();
        var cashierNames = await _db.AppUsers.Where(u => cashierIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);
        var revenueByCashier = sales
            .GroupBy(i => i.CreatedBy)
            .Select(g => new CashierSalesPoint(
                g.Key,
                g.Key.HasValue ? cashierNames.GetValueOrDefault(g.Key.Value, "-") : "غير محدَّد",
                g.Sum(i => i.TotalAmount), g.Count()))
            .OrderByDescending(c => c.Revenue)
            .ToList();

        return new SalesSummaryDto(
            totalRevenue, sales.Count, sales.Count == 0 ? 0 : totalRevenue / sales.Count,
            returns.Sum(i => i.TotalAmount), returns.Count,
            revenueByDay, topProducts, revenueByBranch, revenueByCashier);
    }

    /// <summary>
    /// أعمار الديون — من يدين، بكم، ومنذ متى.
    ///
    /// <para>أهم تقرير مالي لتاجر جملة: الدَّين بلا عمر رقمٌ في كشف، والدَّين
    /// بعمره أولوية تحصيل. راجع [DebtAging] لقاعدة التوزيع.</para>
    /// </summary>
    [HttpGet("debt-aging")]
    public async Task<ActionResult<DebtAgingReportDto>> DebtAging()
    {
        var rows = await Data.DebtAging.ComputeAsync(_db, DateTime.UtcNow);

        // آخر تذكير لكل عميل — يمنع تكرار المطالبة اليوم نفسه، ويُظهر من
        // ذُكِّر ثلاث مرّات ولم يسدّد.
        var customerIds = rows.Select(r => r.CustomerId).ToList();
        var lastReminders = customerIds.Count == 0
            ? new Dictionary<Guid, DebtReminder>()
            : (await _db.DebtReminders.Where(r => customerIds.Contains(r.CustomerId)).ToListAsync())
                .GroupBy(r => r.CustomerId)
                .ToDictionary(g => g.Key, g => g.OrderByDescending(r => r.SentAt).First());

        var items = rows.Select(r =>
        {
            lastReminders.TryGetValue(r.CustomerId, out var last);
            return new DebtAgingRowDto(
                r.CustomerId, r.CustomerName, r.Phone, r.TotalOutstanding,
                r.NotYetDue, r.Days1To30, r.Days31To60, r.Days61To90, r.Over90,
                r.OldestDueDate, r.DaysOverdue, r.Stage,
                last?.Stage, last?.SentAt);
        }).ToList();

        return new DebtAgingReportDto(
            items.Sum(i => i.TotalOutstanding),
            items.Sum(i => i.NotYetDue),
            items.Sum(i => i.Days1To30),
            items.Sum(i => i.Days31To60),
            items.Sum(i => i.Days61To90),
            items.Sum(i => i.Over90),
            items);
    }

    /// <summary>
    /// قيمة المخزون بالتكلفة الحقيقية — من الدفتر لا من سعر تكلفة الصنف.
    ///
    /// <para><b>الفرق ليس دقّةً زائدة:</b> <c>Product.CostPrice</c> رقم واحد
    /// يُكتب فوقه عند كل استلام، فيُقيَّم مخزونٌ اشتُري على ثلاث دفعات بأسعار
    /// مختلفة بسعر آخرها كلّه. الدفتر يحمل تكلفة كل شحنة كما وصلت، فقيمة
    /// المخزون تصبح مجموع ما دُفع فعلاً.</para>
    ///
    /// <para>القراءة من سطور الإدخال التي بقي فيها شيء (<c>remaining_quantity</c>)
    /// لا من كل الدفتر: هي بعينها البضاعة الموجودة الآن على الرفّ.</para>
    /// </summary>
    [RequireModule("valuation")]
    [HttpGet("inventory-valuation")]
    public async Task<ActionResult<InventoryValuationDto>> InventoryValuation([FromQuery] Guid? branchId)
    {
        var lots = _db.StockLedgerEntries.Where(e => e.RemainingQuantity > 0 && !e.IsCancelled);
        if (branchId.HasValue) lots = lots.Where(e => e.BranchId == branchId.Value);

        var rows = await lots
            .Join(_db.Products.Where(p => !p.IsDeleted),
                  e => e.ProductId, p => p.Id,
                  (e, p) => new
                  {
                      e.ProductId, p.Name, p.Sku, p.UnitBase, p.CostPrice,
                      e.BatchNumber, e.RemainingQuantity, e.UnitCost, e.ExpiryDate,
                  })
            .ToListAsync();

        var items = rows
            .GroupBy(r => new { r.ProductId, r.Name, r.Sku, r.UnitBase, r.CostPrice })
            .Select(g =>
            {
                var quantity = g.Sum(x => x.RemainingQuantity);
                var value = g.Sum(x => x.RemainingQuantity * x.UnitCost);
                return new InventoryValuationItemDto(
                    g.Key.ProductId, g.Key.Sku, g.Key.Name, g.Key.UnitBase,
                    quantity, value,
                    // متوسط التكلفة الفعلي مقابل السعر المسجَّل على الصنف —
                    // الفارق بينهما هو حجم الخطأ الذي كان في كل تقرير قيمة.
                    quantity == 0 ? 0 : Math.Round(value / quantity, 3),
                    g.Key.CostPrice,
                    g.Count());
            })
            .OrderByDescending(i => i.TotalValue)
            .ToList();

        return new InventoryValuationDto(
            items.Sum(i => i.TotalValue),
            // القيمة بالطريقة القديمة، للمقارنة: تُظهر للمدير كم كان تقديره
            // منحرفاً — وهو ما يجعل الفرق مفهوماً بدل أن يبدو رقماً تغيّر بلا سبب.
            items.Sum(i => i.Quantity * i.ProductCostPrice),
            items.Count, items);
    }

    /// <summary>
    /// كارت الصنف — كل حركة عليه بترتيب زمني، بالرصيد بعد كلٍّ منها.
    ///
    /// <para>هو الجواب المباشر عن «كم كان الرصيد يوم كذا ولماذا تغيّر»، وهو
    /// السؤال الذي لم يكن له جواب قبل الدفتر إطلاقاً.</para>
    /// </summary>
    [RequireModule("valuation")]
    [HttpGet("item-card/{productId:guid}")]
    public async Task<ActionResult<ItemCardDto>> ItemCard(
        Guid productId, [FromQuery] Guid? branchId, [FromQuery] int limit = 200)
    {
        limit = Math.Clamp(limit, 1, 1000);

        var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == productId);
        if (product is null) return NotFound();

        var query = _db.StockLedgerEntries.Where(e => e.ProductId == productId);
        if (branchId.HasValue) query = query.Where(e => e.BranchId == branchId.Value);

        var entries = await query
            .OrderByDescending(e => e.PostedAt)
            .ThenByDescending(e => e.CreatedAt)
            .Take(limit)
            .ToListAsync();

        var userIds = entries.Where(e => e.CreatedBy.HasValue).Select(e => e.CreatedBy!.Value).Distinct().ToList();
        var userNames = userIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        return new ItemCardDto(
            product.Id, product.Sku, product.Name, product.UnitBase,
            entries.Select(e => new ItemCardEntryDto(
                e.PostedAt, e.SourceType, e.SourceId, e.BatchNumber, e.ExpiryDate,
                e.QuantityChange, e.BalanceAfter, e.UnitCost, e.ValueChange,
                e.CreatedBy is null ? null : userNames.GetValueOrDefault(e.CreatedBy.Value),
                e.IsCancelled)).ToList());
    }

    [HttpGet("inventory-summary")]
    public async Task<ActionResult<InventorySummaryDto>> InventorySummary()
    {
        var products = await _db.Products.Where(p => !p.IsDeleted).ToListAsync();
        var stockByProduct = (await _db.StockLevels.ToListAsync())
            .GroupBy(s => s.ProductId)
            .ToDictionary(g => g.Key, g => g.ToList());

        decimal totalValue = 0;
        var lowStockItems = new List<LowStockItemDto>();
        var expiredItems = new List<ExpiringItemDto>();
        var nearExpiryItems = new List<ExpiringItemDto>();
        var today = DateTime.UtcNow.Date;

        foreach (var product in products)
        {
            var levels = stockByProduct.GetValueOrDefault(product.Id, new List<StockLevel>());

            // قيمة المخزون تشمل الموقوف، وإنذار النقص لا يشمله: الموقوف مالٌ
            // مملوك فعلاً وموجود على الرفّ فيُقيَّم، لكنه ليس بضاعة قابلة
            // للبيع فلا يُسكت إنذار نقصٍ عن صنف لا صالح منه.
            totalValue += levels.Sum(l => l.Quantity) * product.CostPrice;

            var quantity = levels.Where(l => !l.IsLocked).Sum(l => l.Quantity);
            if (quantity <= product.ReorderLevel)
            {
                lowStockItems.Add(new LowStockItemDto(product.Id, product.Name, quantity, product.ReorderLevel));
            }

            foreach (var level in levels.Where(l => l.ExpiryDate.HasValue && l.Quantity > 0))
            {
                var expiryDate = level.ExpiryDate!.Value;
                var lossValue = level.Quantity * product.CostPrice;
                if (expiryDate < today)
                {
                    expiredItems.Add(new ExpiringItemDto(product.Id, product.Name, level.Quantity, expiryDate, lossValue));
                }
                else if (expiryDate <= today.AddDays(7))
                {
                    nearExpiryItems.Add(new ExpiringItemDto(product.Id, product.Name, level.Quantity, expiryDate, lossValue));
                }
            }
        }

        return new InventorySummaryDto(
            totalValue, products.Count,
            lowStockItems.Count, lowStockItems.OrderBy(i => i.Quantity).Take(15).ToList(),
            expiredItems.Count, expiredItems.Sum(i => i.EstimatedLossValue), expiredItems.OrderByDescending(i => i.EstimatedLossValue).Take(15).ToList(),
            nearExpiryItems.Count, nearExpiryItems.OrderBy(i => i.ExpiryDate).Take(15).ToList());
    }

    /// <summary>
    /// تقرير إعادة الطلب — ما يجب شراؤه الآن، ولماذا.
    ///
    /// <para><b>الحدّ اليدوي وحده لا يكفي:</b> رقمٌ يُدخَل مرّة عند إنشاء
    /// الصنف ثم يُنسى، فيبقى على قيمته الأولى بينما يتضاعف الاستهلاك أو
    /// ينهار. النتيجة صنف ينفد قبل أن ينبّه، وآخر يُنبّه وهو راكد منذ شهور.</para>
    ///
    /// <para><b>المعادلة:</b> متوسط الاستهلاك اليومي × (مهلة التوريد + أيام
    /// الأمان). بلا تعلّم آلة ولا انحدار: الاستهلاك الفعلي مقسوماً على أيام
    /// النافذة رقمٌ يفهمه صاحب المتجر ويستطيع مراجعته بنفسه، وهو شرط أن
    /// يثق به.</para>
    ///
    /// <para><b>ولا يُكتب فوق الحدّ اليدوي:</b> يُعرض اقتراحاً بجانبه.
    /// الكتابة الصامتة فوق قرار إداري تُفقد الثقة بالنظام كلّه — وقد يكون
    /// للمدير سبب لا يعرفه النظام (عقد توريد، موسم، حملة).</para>
    /// </summary>
    [RequireModule("inventory")]
    [HttpGet("reorder")]
    public async Task<ActionResult<ReorderReportDto>> Reorder(
        [FromQuery] int windowDays = 90,
        [FromQuery] int coverageDays = 14,
        [FromQuery] bool onlyBelowThreshold = true)
    {
        windowDays = Math.Clamp(windowDays, 7, 365);
        coverageDays = Math.Clamp(coverageDays, 0, 180);

        var to = DateTime.UtcNow.Date.AddDays(1);
        var from = to.AddDays(-windowDays);

        // المبيعات وحدها لا المرتجعات: المرتجع يعيد البضاعة إلى الرفّ، فعدّه
        // استهلاكاً يضخّم الطلب المقترَح مرّتين — مرّة بالبيع ومرّة بالإرجاع.
        var sold = await _db.Invoices
            .Include(i => i.Items)
            .Where(i => i.InvoiceType == "sale" && i.CreatedAt >= from && i.CreatedAt < to)
            .SelectMany(i => i.Items)
            .GroupBy(it => it.ProductId)
            .Select(g => new
            {
                ProductId = g.Key,
                // الكمية بالوحدة الأساسية: سطر بيع بالحبّة يحمل 3 لا 0.3،
                // وجمعه كما هو يضخّم الاستهلاك عشرة أضعاف لصنف يُباع بالتجزئة.
                Quantity = g.Sum(it => it.SoldAsSubUnit && it.SubUnitsPerBase > 0
                    ? it.Quantity / it.SubUnitsPerBase
                    : it.Quantity),
            })
            .ToDictionaryAsync(x => x.ProductId, x => x.Quantity);

        var products = await _db.Products.Where(p => !p.IsDeleted && p.TracksStock).ToListAsync();
        var suppliers = await _db.Suppliers.Where(s => !s.IsDeleted).ToDictionaryAsync(s => s.Id, s => s.Name);

        // المتاح وحده: اقتراح الشراء يقيس ما يمكن بيعه، والموقوف لا يُباع —
        // فعدّه هنا يمنع اقتراح شراء صنفٍ نفد صالحُه كلّه.
        var stockByProduct = (await _db.StockLevels.Where(s => !s.IsLocked).ToListAsync())
            .GroupBy(s => s.ProductId)
            .ToDictionary(g => g.Key, g => g.Sum(x => x.Quantity));

        // القادم في الطريق: ما صدر به أمر ولم يصل. بدونه كان التقرير يقترح
        // شراء صنفٍ **أمر شرائه مُرسَل بالفعل**، فيُكرّر الطلب على المورّد —
        // وهو أكثر أخطاء إعادة الطلب كلفةً لأنه يُنتج مخزوناً راكداً بضعف
        // الحاجة، لا نقصاً.
        //
        // على الأوامر المُرسَلة وحدها: المسودّة قرارٌ لم يُتخذ بعد، وعدّها
        // ضمن القادم يجعل النظام يطمئن إلى بضاعة لم يطلبها أحد.
        var onOrderByProduct = (await _db.PurchaseOrders
                .Where(o => o.Status == "ordered")
                .Include(o => o.Items)
                .SelectMany(o => o.Items)
                .ToListAsync())
            .GroupBy(i => i.ProductId)
            .ToDictionary(g => g.Key, g => g.Sum(i => Math.Max(0, i.RemainingQuantity)));

        var items = new List<ReorderItemDto>();
        foreach (var p in products)
        {
            var quantity = stockByProduct.GetValueOrDefault(p.Id, 0m);
            var onOrder = onOrderByProduct.GetValueOrDefault(p.Id, 0m);
            // الحجز (المخصوم في المعادلة الكاملة) لم يُبنَ بعد — هو بند
            // enterprise مسجَّل في ARCHITECTURE.md §2.15. وغيابه يجعل
            // المتوقَّع **متفائلاً** لا مخطئاً: يُقدّر المتاح أكثر مما هو،
            // فيؤخّر شراءً ولا يُنتج شراءً زائداً.
            var projected = quantity + onOrder;
            var usage = sold.GetValueOrDefault(p.Id, 0m);
            var avgDaily = usage / windowDays;

            var leadTime = p.LeadTimeDays > 0 ? p.LeadTimeDays : 7;
            var suggestedLevel = Math.Round(avgDaily * (leadTime + coverageDays), 2);
            // الاقتراح والتغطية على المتوقَّع لا على الموجود: صنفٌ رصيده صفر
            // وأمر شرائه في الطريق ليس صنفاً ينفد غداً.
            var suggestedOrder = Math.Max(0, Math.Round(suggestedLevel - projected, 2));
            decimal? daysOfCover = avgDaily > 0 ? Math.Round(projected / avgDaily, 1) : null;

            // الحدّ المُعتمَد للفرز هو الأعلى بين اليدوي والمقترَح: الاكتفاء
            // باليدوي يُخفي صنفاً تضاعف استهلاكه، والاكتفاء بالمقترَح يتجاهل
            // حدّاً وضعه المدير عمداً فوق ما يقوله الاستهلاك.
            var threshold = Math.Max(p.ReorderLevel, suggestedLevel);
            if (onlyBelowThreshold && (threshold <= 0 || projected > threshold)) continue;

            suppliers.TryGetValue(p.SupplierId ?? Guid.Empty, out var supplierName);
            items.Add(new ReorderItemDto(
                p.Id, p.Sku, p.Name, p.UnitBase, p.SupplierId, supplierName,
                quantity, onOrder, projected,
                p.ReorderLevel, Math.Round(avgDaily, 3), leadTime,
                suggestedLevel, suggestedOrder, daysOfCover, p.CostPrice));
        }

        // الأقلّ تغطيةً أولاً — ما ينفد غداً قبل ما ينفد بعد شهر. وما بلا
        // استهلاك يُؤخَّر: راكد لا عاجل.
        items = items
            .OrderBy(i => i.DaysOfCover ?? decimal.MaxValue)
            .ThenByDescending(i => i.SuggestedOrderQuantity)
            .ToList();

        return new ReorderReportDto(windowDays, coverageDays, from, to.AddDays(-1), items);
    }

}
