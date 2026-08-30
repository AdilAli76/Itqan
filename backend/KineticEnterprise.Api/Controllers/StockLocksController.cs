using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

/// <summary>دفعة واحدة من دفعات صنف في فرع — الوحدة التي يقع عليها القفل.</summary>
public record StockBatchDto(
    Guid ProductId, Guid BranchId, string BranchName, string BatchNumber,
    decimal Quantity, DateTime? ExpiryDate,
    bool IsLocked, string? LockReason, string? LockedByName, DateTime? LockedAt);

/// <summary>صفٌّ في تقرير «المخزون الموقوف» — يضيف اسم الصنف وقيمته.</summary>
public record LockedStockDto(
    Guid ProductId, string ProductName, string Sku, Guid BranchId, string BranchName,
    string BatchNumber, decimal Quantity, DateTime? ExpiryDate, decimal Value,
    string? LockReason, string? LockedByName, DateTime? LockedAt);

public record LockStockRequest(Guid ProductId, Guid? BranchId, string? BatchNumber, string Reason);
public record UnlockStockRequest(Guid ProductId, Guid? BranchId, string? BatchNumber);

/// <summary>
/// قفل المخزون: إيقاف دفعة عن الصرف مع بقائها في مكانها.
///
/// <para>الوحدة هي **الدفعة لا الصنف**: تصل ثلاث شحنات من نفس الدواء
/// فتُشتبَه واحدة، وقفل الصنف كلّه كان يوقف بضاعة سليمة بلا سبب. وجدول
/// stock_levels يحمل صفّاً لكل (فرع، صنف، دفعة) أصلاً، فالقفل يقع على
/// الصفّ بلا جدول جديد.</para>
///
/// <para>ما يخرج منه الموقوف موثَّق عند [KineticEnterprise.Api.Models.StockLevel.IsLocked]:
/// البيع، وإعادة الطلب، والتحويل بين الفروع. وما يبقى فيه: الجرد، وقيمة
/// المخزون، وتقرير الصلاحية.</para>
/// </summary>
[RequireModule("inventory")]
[ApiController]
[Route("api/stock-locks")]
[Authorize]
public class StockLocksController : ControllerBase
{
    private readonly AppDbContext _db;
    public StockLocksController(AppDbContext db) => _db = db;

    /// <summary>
    /// دفعات صنف واحد — المصدر الذي تختار منه شاشة المخزون ما تقفله.
    /// تشمل الموقوف والمتاح معاً: الشاشة تعرض الحالتين في جدول واحد.
    /// </summary>
    [HttpGet("batches/{productId:guid}")]
    public async Task<ActionResult<List<StockBatchDto>>> Batches(Guid productId, [FromQuery] Guid? branchId)
    {
        var query = _db.StockLevels.Where(s => s.ProductId == productId);

        // الفرع اختياري: مدير المنظمة بلا branch_id يرى كل الفروع، والعزل
        // النهائي على قاعدة البيانات عبر StockLevelsPolicy لا هنا.
        var effectiveBranch = branchId ?? ParseBranchClaim();
        if (effectiveBranch is not null) query = query.Where(s => s.BranchId == effectiveBranch);

        var rows = await query.ToListAsync();
        var (branchNames, userNames) = await LookupsFor(rows.Select(r => r.BranchId), rows.Select(r => r.LockedBy));

        return rows
            // الموقوف أولاً — هو سبب فتح الشاشة، ثم الأقرب انتهاءً كترتيب الصرف.
            .OrderByDescending(r => r.IsLocked)
            .ThenBy(r => r.ExpiryDate ?? DateTime.MaxValue)
            .ThenBy(r => r.BatchNumber, StringComparer.Ordinal)
            .Select(r => new StockBatchDto(
                r.ProductId, r.BranchId, branchNames.GetValueOrDefault(r.BranchId, "-"),
                r.BatchNumber, r.Quantity, r.ExpiryDate,
                r.IsLocked, r.LockReason,
                r.LockedBy is null ? null : userNames.GetValueOrDefault(r.LockedBy.Value), r.LockedAt))
            .ToList();
    }

    /// <summary>تقرير «المخزون الموقوف» — كل ما أُوقف في المنظمة وقيمته.</summary>
    [HttpGet]
    public async Task<ActionResult<List<LockedStockDto>>> Locked([FromQuery] Guid? branchId)
    {
        var query = _db.StockLevels.Where(s => s.IsLocked);
        var effectiveBranch = branchId ?? ParseBranchClaim();
        if (effectiveBranch is not null) query = query.Where(s => s.BranchId == effectiveBranch);

        var rows = await query.ToListAsync();
        if (rows.Count == 0) return new List<LockedStockDto>();

        var productIds = rows.Select(r => r.ProductId).Distinct().ToList();
        var products = await _db.Products
            .Where(p => productIds.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => new { p.Name, p.Sku, p.CostPrice });

        var (branchNames, userNames) = await LookupsFor(rows.Select(r => r.BranchId), rows.Select(r => r.LockedBy));

        return rows
            // الأقدم قفلاً أولاً: ما مضى عليه شهرٌ موقوفاً هو المشكلة، لا ما
            // قُفل اليوم. والقفل المنسيّ هو العطب الوحيد لهذه الميزة.
            .OrderBy(r => r.LockedAt ?? DateTime.MaxValue)
            .Select(r =>
            {
                products.TryGetValue(r.ProductId, out var p);
                return new LockedStockDto(
                    r.ProductId, p?.Name ?? "-", p?.Sku ?? "-",
                    r.BranchId, branchNames.GetValueOrDefault(r.BranchId, "-"),
                    r.BatchNumber, r.Quantity, r.ExpiryDate,
                    r.Quantity * (p?.CostPrice ?? 0),
                    r.LockReason,
                    r.LockedBy is null ? null : userNames.GetValueOrDefault(r.LockedBy.Value), r.LockedAt);
            })
            .ToList();
    }

    [HttpPost]
    [RequirePermission("inventory.manage")]
    public async Task<IActionResult> Lock(LockStockRequest request)
    {
        // السبب إلزامي — راجع StockLevel.LockReason: قفلٌ بلا سبب يصبح كميةً
        // مجمَّدة لا يعرف أحد لماذا جُمِّدت.
        var reason = (request.Reason ?? "").Trim();
        if (reason.Length == 0)
        {
            return BadRequest(new { message = "سبب الإيقاف إلزامي" });
        }

        var stock = await FindRow(request.ProductId, request.BranchId, request.BatchNumber);
        if (stock is null) return NotFound(new { message = "لا يوجد رصيد بهذه الدفعة في هذا الفرع" });
        if (stock.IsLocked) return BadRequest(new { message = "هذه الدفعة موقوفة أصلاً" });

        stock.IsLocked = true;
        stock.LockReason = reason;
        stock.LockedBy = CurrentUserId();
        stock.LockedAt = DateTime.UtcNow;

        _db.LogAudit(stock.OrganizationId, CurrentUserId(), "stock.locked", "stock_levels", stock.Id,
            newValues: new { stock.ProductId, stock.BranchId, stock.BatchNumber, stock.Quantity, Reason = reason });

        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// الإفراج. لا يحتاج سبباً — القفل هو الحالة الاستثنائية التي تُبرَّر،
    /// والعودة إلى الأصل ليست كذلك. وأثره كاملٌ في audit_logs على أي حال.
    /// </summary>
    [HttpPost("release")]
    [RequirePermission("inventory.manage")]
    public async Task<IActionResult> Release(UnlockStockRequest request)
    {
        var stock = await FindRow(request.ProductId, request.BranchId, request.BatchNumber);
        if (stock is null) return NotFound(new { message = "لا يوجد رصيد بهذه الدفعة في هذا الفرع" });
        if (!stock.IsLocked) return BadRequest(new { message = "هذه الدفعة غير موقوفة" });

        _db.LogAudit(stock.OrganizationId, CurrentUserId(), "stock.released", "stock_levels", stock.Id,
            oldValues: new { stock.LockReason, stock.LockedAt },
            newValues: new { stock.ProductId, stock.BranchId, stock.BatchNumber, stock.Quantity });

        stock.IsLocked = false;
        stock.LockReason = null;
        stock.LockedBy = null;
        stock.LockedAt = null;

        await _db.SaveChangesAsync();
        return NoContent();
    }

    private async Task<Models.StockLevel?> FindRow(Guid productId, Guid? branchId, string? batchNumber)
    {
        var effectiveBranch = branchId ?? ParseBranchClaim();
        if (effectiveBranch is null) return null;

        var batch = batchNumber ?? "";
        return await _db.StockLevels.FirstOrDefaultAsync(
            s => s.ProductId == productId && s.BranchId == effectiveBranch && s.BatchNumber == batch);
    }

    private async Task<(Dictionary<Guid, string> Branches, Dictionary<Guid, string> Users)> LookupsFor(
        IEnumerable<Guid> branchIds, IEnumerable<Guid?> userIds)
    {
        var branches = branchIds.Distinct().ToList();
        var users = userIds.Where(u => u.HasValue).Select(u => u!.Value).Distinct().ToList();

        var branchNames = await _db.Branches
            .Where(b => branches.Contains(b.Id))
            .ToDictionaryAsync(b => b.Id, b => b.Name);

        var userNames = users.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => users.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        return (branchNames, userNames);
    }

    private Guid? ParseBranchClaim()
    {
        var raw = User.FindFirstValue("branch_id");
        return Guid.TryParse(raw, out var id) ? id : null;
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
