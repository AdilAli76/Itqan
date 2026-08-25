using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// عرض المخزون الموحّد لشاشة "إدارة المخزون والموردين" في Flutter: صنف +
/// اسم الفئة/المورد (بدل المعرّف فقط) + الكمية المتاحة والصلاحية الأقرب،
/// مجمّعة من stock_levels التي تُفلتَر تلقائياً حسب فرع المستخدم عبر
/// StockLevelsPolicy (مدير عام بلا branch_id يرى مجموع كل الفروع).
/// </summary>
public record ProductInventoryDto(
    Guid Id, string Sku, string? Barcode, string Name, string UnitBase,
    decimal CostPrice, decimal SalePrice, bool TrackExpiry, decimal ReorderLevel,
    Guid? CategoryId, string? CategoryName, Guid? SupplierId, string? SupplierName,
    decimal Quantity, DateTime? NearestExpiryDate, bool TracksStock,
    // معرّف النشرة فقط لا محتواها: القائمة قد تحمل مئتَي صنف، وضخّ نصوص
    // موانع الاستعمال لكلٍّ منها في كل فتح للشاشة حِمل بلا مقابل — الكاشير
    // يقرأ نشرة صنف واحد حين يسأل عنه. المحتوى يُجلَب عند الطلب من
    // GET /api/products/{id}/medicine.
    Guid? MedicineRefId,
    // مقيَّد بوصفة — تعرفه شاشة البيع قبل الدفع لا بعد رفض الخادم: مطالبة
    // الكاشير بالوصفة بعد أن يضغط «دفع» والزبون ينتظر أسوأ من مطالبته بها
    // لحظة إضافة الصنف.
    bool RequiresPrescription,
    // البيع بالوحدة الجزئية — تحتاجها شاشة البيع لعرض خيار «حبّة» وسعرها.
    string? SubUnitName, decimal SubUnitsPerBase, decimal SubUnitPrice,
    // الموقوف — منفصل عن Quantity المتاحة. شاشة المخزون تعرضه، وشاشة البيع
    // تتجاهله. راجع StockLevel.IsLocked.
    decimal LockedQuantity);

public record StockAdjustmentRequest(Guid? BranchId, decimal QuantityDelta, string? BatchNumber, DateTime? ExpiryDate);

/// <summary>دفعة واحدة في تقرير الصلاحية — بما يكفي لعرضها وتحديدها على الرفّ.</summary>
public record ExpiringBatchDto(
    Guid ProductId, string ProductName, string Sku, string BatchNumber,
    DateTime ExpiryDate, decimal Quantity, int DaysRemaining);

/// <summary>
/// ملخّص الصلاحية لشريط الإنذار على شاشة البيع.
///
/// منتهية الصلاحية <b>لا تُحتسب ضمن المتاح للبيع</b> (راجع تخصيص الدفعات في
/// InvoicesController)، فعرضها منفصلة عن المقتربة ليس تجميلاً: الأولى بضاعة
/// مجمَّدة تحتاج إتلافاً أو تسوية، والثانية بضاعة ما زال يمكن تصريفها.
/// </summary>
public record ExpirySummaryDto(
    int ExpiredBatches, decimal ExpiredQuantity,
    int ExpiringBatches, decimal ExpiringQuantity,
    int WithinDays, List<ExpiringBatchDto> Batches);

/// صفحة مخزون — نفس شكل بقية صفحات النظام.
public record ProductInventoryPageDto(List<ProductInventoryDto> Items, int TotalCount, int Page, int PageSize);

/// <summary>
/// النمط المرجعي لأي Controller جديد في النظام: لا حاجة لكتابة
/// WHERE organization_id = ... يدوياً — الـ Security Policy على قاعدة
/// البيانات (مفعّلة عبر TenantContextMiddleware) تتكفّل بالعزل تلقائياً.
/// كل Controller جديد لموديول في ARCHITECTURE.md يتبع نفس الشكل بالضبط.
/// </summary>
[ApiController]
[Route("api/products")]
[Authorize]

public class ProductsController : ControllerBase
{
    private readonly AppDbContext _db;
    public ProductsController(AppDbContext db) => _db = db;

    /// <summary>
    /// قائمة الأصناف المسطّحة — يستهلكها البحث في نقطة البيع أساساً.
    ///
    /// تبقى قائمة غير مغلَّفة عمداً (بخلاف /products/inventory): مستهلكها
    /// الوحيد بحثٌ فوري يعرض أول نتائج مطابقة، ولا معنى لصفحات فيه. والسقف
    /// الصلب بدل الترقيم هو الحماية الصحيحة هنا: يمنع تحميل عشرين ألف صنف
    /// حين يمسح الكاشير الحقل ويتركه فارغاً.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<List<Product>>> GetAll([FromQuery] string? search, [FromQuery] int limit = 100)
    {
        limit = Math.Clamp(limit, 1, 500);
        var query = _db.Products.Where(p => !p.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(p => p.Name.Contains(search) || p.Sku.Contains(search) || (p.Barcode != null && p.Barcode.Contains(search)));
        }
        return await query.OrderBy(p => p.Name).Take(limit).ToListAsync();
    }

    /// <summary>
    /// نشرة الدواء المرتبطة بصنف — لإصدار الصيدليات وحده.
    ///
    /// نقطة منفصلة لا حقول على قائمة الأصناف: النشرة نصوص طويلة (دواعي،
    /// موانع، تحذيرات، أعراض جانبية) تخصّ صنفاً واحداً يسأل عنه الكاشير،
    /// وحملها مع كل صنف في كل قائمة يُثقل شاشة تُفتح عشرات المرّات يومياً.
    /// </summary>
    [RequireModule("pharmacy")]
    [HttpGet("{id:guid}/medicine")]
    public async Task<ActionResult<MedicineReference>> GetMedicineInfo(Guid id)
    {
        var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == id && !p.IsDeleted);
        if (product is null) return NotFound();
        if (product.MedicineRefId is null)
        {
            // صنف غير دوائي (مستحضر تجميل، حفاضات) — ليس خطأً، وتمييزه عن
            // «الصنف غير موجود» يمنع الواجهة من عرض رسالة فشل في حالة عادية.
            return NoContent();
        }

        var info = await _db.MedicineReferences
            .FirstOrDefaultAsync(m => m.Id == product.MedicineRefId && !m.IsDeleted);
        return info is null ? NoContent() : info;
    }

    /// <summary>
    /// دفعات منتهية الصلاحية أو مقتربة منها، للفرع الحالي.
    ///
    /// يُستدعى من شاشة نقطة البيع لعرض شريط الإنذار: المعلومة تُعرض حيث يقع
    /// الفعل لا في تقرير يزوره المدير شهرياً. الصيدلية تخسر البضاعة لأن أحداً
    /// لم ينظر إلى التقرير، لا لأن التقرير غير موجود.
    ///
    /// بلا RequirePermission: هذه قراءة تحذيرية يحتاجها كل من يقف على نقطة
    /// البيع، ومنعها عن الكاشير يُفرغ الشريط من غرضه. وسياسة العزل على
    /// stock_levels تحصر النتيجة في منظمة الطالب وفرعه أصلاً.
    /// </summary>
    [RequireModule("inventory")]
    [HttpGet("expiry-alerts")]
    public async Task<ActionResult<ExpirySummaryDto>> GetExpiryAlerts(
        [FromQuery] Guid? branchId,
        [FromQuery] int withinDays = 30,
        [FromQuery] int limit = 20)
    {
        withinDays = Math.Clamp(withinDays, 1, 365);
        limit = Math.Clamp(limit, 1, 200);

        var today = DateTime.UtcNow.Date;
        var horizon = today.AddDays(withinDays);

        // الفرع اختياري: مدير المنظمة بلا branch_id يرى كل الفروع، والفلترة
        // النهائية تقع على قاعدة البيانات عبر StockLevelsPolicy لا هنا.
        var effectiveBranch = branchId ?? ParseBranchClaim();

        var levels = _db.StockLevels.Where(s => s.Quantity > 0 && s.ExpiryDate != null);
        if (effectiveBranch is not null)
        {
            levels = levels.Where(s => s.BranchId == effectiveBranch);
        }

        var rows = await levels
            .Where(s => s.ExpiryDate!.Value <= horizon)
            .Join(_db.Products.Where(p => !p.IsDeleted),
                  s => s.ProductId, p => p.Id,
                  (s, p) => new { s.ProductId, p.Name, p.Sku, s.BatchNumber, s.ExpiryDate, s.Quantity })
            .ToListAsync();

        var expired = rows.Where(r => r.ExpiryDate!.Value.Date < today).ToList();
        var expiring = rows.Where(r => r.ExpiryDate!.Value.Date >= today).ToList();

        // الأقرب انتهاءً أولاً — نفس ترتيب الصرف (FEFO)، فما يظهر في أعلى
        // الشريط هو ما سيُصرَف أو يتلف أوّلاً.
        var batches = rows
            .OrderBy(r => r.ExpiryDate)
            .Take(limit)
            .Select(r => new ExpiringBatchDto(
                r.ProductId, r.Name, r.Sku, r.BatchNumber,
                r.ExpiryDate!.Value,
                r.Quantity,
                (int)(r.ExpiryDate!.Value.Date - today).TotalDays))
            .ToList();

        return new ExpirySummaryDto(
            expired.Count, expired.Sum(r => r.Quantity),
            expiring.Count, expiring.Sum(r => r.Quantity),
            withinDays, batches);
    }

    /// <summary>
    /// مخزون الأصناف مقسَّماً صفحات. جدول الأصناف هو أكبر جدول في نظام
    /// تجزئة عادةً، وكان يُجلَب كاملاً في كل فتح لشاشة المخزون.
    /// </summary>
    [HttpGet("inventory")]
    public async Task<ActionResult<ProductInventoryPageDto>> GetInventory(
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = _db.Products.Where(p => !p.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(p => p.Name.Contains(search) || p.Sku.Contains(search) || (p.Barcode != null && p.Barcode.Contains(search)));
        }

        var totalCount = await query.CountAsync();
        var products = await query.OrderBy(p => p.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        // النشرات المقيَّدة وحدها: قائمة معرّفات صغيرة تكفي لعلَم بولياني،
        // بلا جلب نصوص النشرات مع كل صنف.
        var restrictedRefs = (await _db.MedicineReferences
                .Where(m => !m.IsDeleted && m.RequiresPrescription)
                .Select(m => m.Id)
                .ToListAsync())
            .ToHashSet();

        var categories = await _db.ProductCategories.ToDictionaryAsync(c => c.Id, c => c.Name);
        var suppliers = await _db.Suppliers.Where(s => !s.IsDeleted).ToDictionaryAsync(s => s.Id, s => s.Name);

        // مجموعة صغيرة عادةً (مخزون منشأة واحدة) — التجميع في الذاكرة أبسط
        // وأوضح من محاولة تركيب Sum + Min المشروط في استعلام SQL واحد.
        // quantity هنا هو **المتاح** لا الإجمالي: هذه النقطة يقرأها البيع
        // (شاشة نقطة البيع تستدعي /products/inventory نفسها)، فجعل الرقم
        // الافتراضي هو الإجمالي كان يعرض على الكاشير كميةً لا يستطيع بيعها.
        // والموقوف يُعاد في حقله المستقلّ ليظهر في شاشة المخزون بلا لبس.
        var stockByProduct = (await _db.StockLevels.ToListAsync())
            .GroupBy(s => s.ProductId)
            .ToDictionary(g => g.Key, g => new
            {
                Quantity = g.Where(x => !x.IsLocked).Sum(x => x.Quantity),
                LockedQuantity = g.Where(x => x.IsLocked).Sum(x => x.Quantity),
                // أقرب صلاحية للمتاح وحده: دفعة موقوفة تنتهي غداً ليست تحذيراً
                // للكاشير، فهي لن تُصرَف أصلاً.
                NearestExpiry = g.Where(x => x.ExpiryDate.HasValue && x.Quantity > 0 && !x.IsLocked)
                                  .Select(x => x.ExpiryDate)
                                  .OrderBy(d => d)
                                  .FirstOrDefault(),
            });

        var items = products.Select(p =>
        {
            stockByProduct.TryGetValue(p.Id, out var stock);
            categories.TryGetValue(p.CategoryId ?? Guid.Empty, out var categoryName);
            suppliers.TryGetValue(p.SupplierId ?? Guid.Empty, out var supplierName);
            return new ProductInventoryDto(
                p.Id, p.Sku, p.Barcode, p.Name, p.UnitBase, p.CostPrice, p.SalePrice,
                p.TrackExpiry, p.ReorderLevel, p.CategoryId, categoryName, p.SupplierId, supplierName,
                stock?.Quantity ?? 0, stock?.NearestExpiry, p.TracksStock, p.MedicineRefId,
                p.MedicineRefId.HasValue && restrictedRefs.Contains(p.MedicineRefId.Value),
                p.SubUnitName, p.SubUnitsPerBase, p.SubUnitPrice,
                stock?.LockedQuantity ?? 0);
        }).ToList();

        return new ProductInventoryPageDto(items, totalCount, page, pageSize);
    }

    /// <summary>
    /// تعديل مخزون بصيغة "فرق" (+/-) وليس قيمة مطلقة، حتى يبقى كل تغيير
    /// قابلاً للتدقيق (نفس فلسفة `audit_logs` — لا نكتب فوق الرقم القديم).
    /// </summary>
    [RequireModule("inventory")]
    [HttpPost("{id:guid}/stock-adjustments")]
    [RequirePermission("inventory.manage")]
    public async Task<ActionResult<StockLevel>> AdjustStock(Guid id, StockAdjustmentRequest request)
    {
        var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == id && !p.IsDeleted);
        if (product is null) return NotFound();

        var branchId = request.BranchId ?? ParseBranchClaim();
        if (branchId is null)
        {
            return BadRequest(new { message = "يجب تحديد الفرع لإجراء تعديل على المخزون" });
        }
        if (request.QuantityDelta == 0)
        {
            return BadRequest(new { message = "لا تغيير في الكمية" });
        }

        var batch = request.BatchNumber ?? "";

        // المعاملة تُفتح هنا لا في StockLedger: حركة المخزون وسطر الدفتر
        // ينجحان معاً أو يفشلان معاً — وهو شرط ألّا يُولد نظامان لا يتّفقان.
        await using var transaction = await _db.Database.BeginTransactionAsync();
        try
        {
            if (request.QuantityDelta > 0)
            {
                await StockLedger.ReceiveAsync(
                    _db, product.OrganizationId, branchId.Value, warehouseId: null, productId: id,
                    quantity: request.QuantityDelta,
                    // تكلفة الصنف الحالية: التعديل اليدوي إدخالٌ بلا مستند
                    // شراء، فلا سعر أدقّ منه متاح.
                    unitCost: product.CostPrice,
                    sourceType: StockSourceTypes.ManualAdjustment, sourceId: product.Id,
                    userId: CurrentUserId(),
                    batchNumber: batch, expiryDate: request.ExpiryDate, trackExpiry: product.TrackExpiry);
            }
            else
            {
                // الخصم يمرّ بقاعدة الصرف نفسها التي يمرّ بها البيع: يُقسَّم
                // على الإدخالات بترتيب الاستراتيجية، ويستبعد الموقوف. تعديلٌ
                // يدوي يتجاوزها كان سيُنتج تكلفة خاطئة وتتبّعاً مكسوراً.
                await StockLedger.IssueAsync(
                    _db, product.OrganizationId, branchId.Value, warehouseId: null, productId: id,
                    quantity: -request.QuantityDelta,
                    sourceType: StockSourceTypes.ManualAdjustment, sourceId: product.Id,
                    userId: CurrentUserId());
            }

            _db.LogAudit(product.OrganizationId, CurrentUserId(), "product.stock_adjusted", "stock_levels", product.Id,
                newValues: new { ProductName = product.Name, request.QuantityDelta, Batch = batch });

            await _db.SaveChangesAsync();
            await transaction.CommitAsync();
        }
        catch (InvalidOperationException ex)
        {
            // رسالة StockLedger عربية ومفهومة أصلاً («المتاح أقلّ من المطلوب»)،
            // فتُعاد كما هي بدل نصّ عام يُخفي الرقم.
            await transaction.RollbackAsync();
            return BadRequest(new { message = ex.Message });
        }

        var stock = await _db.StockLevels.FirstOrDefaultAsync(
            s => s.BranchId == branchId && s.ProductId == id && s.BatchNumber == batch);
        return stock ?? new StockLevel
        {
            OrganizationId = product.OrganizationId,
            BranchId = branchId.Value,
            ProductId = id,
            BatchNumber = batch,
        };
    }

    private Guid? ParseBranchClaim()
    {
        var branchIdClaim = User.FindFirstValue("branch_id");
        return Guid.TryParse(branchIdClaim, out var branchId) ? branchId : null;
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<Product>> GetById(Guid id)
    {
        var product = await _db.Products.FindAsync(id);
        return product is null ? NotFound() : product;
    }

    [RequireModule("inventory")]
    [HttpPost]
    [RequirePermission("inventory.manage")]
    public async Task<ActionResult<Product>> Create(Product product)
    {
        // organization_id يُشتق دائماً من التوكن، لا من الطلب — وإلا
        // ترفض BLOCK PREDICATE الخاصة بـ ProductsPolicy العملية بصمت
        // (أو أسوأ: يسمح لعميل خبيث بمحاولة الكتابة بمنظمة أخرى).
        product.OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!);
        _db.Products.Add(product);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetById), new { id = product.Id }, product);
    }

    [RequireModule("inventory")]
    [HttpPut("{id:guid}")]
    [RequirePermission("inventory.manage")]
    public async Task<IActionResult> Update(Guid id, Product update)
    {
        var product = await _db.Products.FindAsync(id);
        if (product is null) return NotFound();

        product.Name = update.Name;
        product.Sku = update.Sku;
        product.Barcode = update.Barcode;
        product.UnitBase = update.UnitBase;
        product.UnitConversionFactor = update.UnitConversionFactor;
        product.CategoryId = update.CategoryId;
        product.SupplierId = update.SupplierId;
        product.SalePrice = update.SalePrice;
        product.CostPrice = update.CostPrice;
        product.ReorderLevel = update.ReorderLevel;
        product.TrackExpiry = update.TrackExpiry;
        product.TracksStock = update.TracksStock;
        product.MedicineRefId = update.MedicineRefId;
        product.SubUnitName = update.SubUnitName;
        product.SubUnitsPerBase = update.SubUnitsPerBase;
        product.SubUnitPrice = update.SubUnitPrice;
        product.LeadTimeDays = update.LeadTimeDays;

        await _db.SaveChangesAsync();
        return NoContent();
    }

    // حذف فعلي غير مسموح به في أي موديول (راجع ARCHITECTURE.md §3.2) —
    // فقط Soft Delete لحفظ سجل التدقيق.
    [RequireModule("inventory")]
    [HttpDelete("{id:guid}")]
    [RequirePermission("inventory.delete")]
    public async Task<IActionResult> SoftDelete(Guid id)
    {
        var product = await _db.Products.FindAsync(id);
        if (product is null) return NotFound();

        product.IsDeleted = true;
        _db.LogAudit(product.OrganizationId, CurrentUserId(), "product.deleted", "products", product.Id,
            oldValues: new { product.Name, product.Sku });
        await _db.SaveChangesAsync();
        return NoContent();
    }
}
