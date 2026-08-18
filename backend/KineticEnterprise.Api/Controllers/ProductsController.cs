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
    decimal Quantity, DateTime? NearestExpiryDate, bool TracksStock);

public record StockAdjustmentRequest(Guid? BranchId, decimal QuantityDelta, string? BatchNumber, DateTime? ExpiryDate);

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

        var categories = await _db.ProductCategories.ToDictionaryAsync(c => c.Id, c => c.Name);
        var suppliers = await _db.Suppliers.Where(s => !s.IsDeleted).ToDictionaryAsync(s => s.Id, s => s.Name);

        // مجموعة صغيرة عادةً (مخزون منشأة واحدة) — التجميع في الذاكرة أبسط
        // وأوضح من محاولة تركيب Sum + Min المشروط في استعلام SQL واحد.
        var stockByProduct = (await _db.StockLevels.ToListAsync())
            .GroupBy(s => s.ProductId)
            .ToDictionary(g => g.Key, g => new
            {
                Quantity = g.Sum(x => x.Quantity),
                NearestExpiry = g.Where(x => x.ExpiryDate.HasValue && x.Quantity > 0)
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
                stock?.Quantity ?? 0, stock?.NearestExpiry, p.TracksStock);
        }).ToList();

        return new ProductInventoryPageDto(items, totalCount, page, pageSize);
    }

    /// <summary>
    /// تعديل مخزون بصيغة "فرق" (+/-) وليس قيمة مطلقة، حتى يبقى كل تغيير
    /// قابلاً للتدقيق (نفس فلسفة `audit_logs` — لا نكتب فوق الرقم القديم).
    /// </summary>
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

        var batch = request.BatchNumber ?? "";
        var stock = await _db.StockLevels.FirstOrDefaultAsync(
            s => s.BranchId == branchId && s.ProductId == id && s.BatchNumber == batch);

        if (stock is null)
        {
            if (request.QuantityDelta < 0)
            {
                return BadRequest(new { message = "لا يمكن خصم كمية من رصيد غير موجود" });
            }
            stock = new StockLevel
            {
                OrganizationId = product.OrganizationId,
                BranchId = branchId.Value,
                ProductId = id,
                BatchNumber = batch,
                ExpiryDate = request.ExpiryDate,
                Quantity = request.QuantityDelta,
            };
            _db.StockLevels.Add(stock);
        }
        else
        {
            if (stock.Quantity + request.QuantityDelta < 0)
            {
                return BadRequest(new { message = "الكمية الناتجة سالبة" });
            }
            stock.Quantity += request.QuantityDelta;
            if (request.ExpiryDate.HasValue) stock.ExpiryDate = request.ExpiryDate;
        }

        _db.LogAudit(product.OrganizationId, CurrentUserId(), "product.stock_adjusted", "stock_levels", product.Id,
            newValues: new { ProductName = product.Name, request.QuantityDelta, NewQuantity = stock.Quantity });

        await _db.SaveChangesAsync();
        return stock;
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

    [HttpPost]
    [RequirePermission("inventory.manage")]
    public async Task<ActionResult<Product>> Create(Product product)
    {
        // organization_id يُشتق دائماً من التوكن، لا من الطلب — وإلا
        // ترفض BLOCK PREDICATE الخاصة بـ ProductsPolicy العملية بصمت
        // (أو أسوأ: يسمح لعميل خبيث بمحاولة الكتابة بمنظمة أخرى).
        product.OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!);
        _db.Products.Add(product);
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "رمز الصنف (SKU) مستخدم بالفعل" });
        }
        return CreatedAtAction(nameof(GetById), new { id = product.Id }, product);
    }

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

        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "رمز الصنف (SKU) مستخدم بالفعل" });
        }
        return NoContent();
    }

    // حذف فعلي غير مسموح به في أي موديول (راجع ARCHITECTURE.md §3.2) —
    // فقط Soft Delete لحفظ سجل التدقيق.
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
