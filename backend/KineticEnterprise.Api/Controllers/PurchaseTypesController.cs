using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;
using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// إدارة أنواع المشتريات والتسليمات المرنة
/// - مشتريات تقليدية (مورد → مستودع → عميل)
/// - تسليم مباشر (مورد → عميل مباشرة)
/// </summary>
[ApiController]
[Route("api/purchase-types")]
[Authorize]
public class PurchaseTypesController : ControllerBase
{
    private readonly AppDbContext _db;

    public PurchaseTypesController(AppDbContext db)
    {
        _db = db;
    }

    /// <summary>
    /// الحصول على جميع أنواع المشتريات المتاحة
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<IEnumerable<PurchaseType>>> GetPurchaseTypes()
    {
        var organizationId = GetOrganizationIdFromToken();
        if (organizationId == Guid.Empty)
            return Unauthorized();

        var types = await _db.PurchaseTypes
            .Where(pt => pt.OrganizationId == organizationId && pt.IsActive)
            .OrderBy(pt => pt.DisplayOrder)
            .ToListAsync();

        return Ok(types);
    }

    /// <summary>
    /// الحصول على نوع مشتريات محدد
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<PurchaseType>> GetPurchaseType(Guid id)
    {
        var type = await _db.PurchaseTypes.FindAsync(id);
        if (type == null)
            return NotFound(new { message = "نوع المشتريات غير موجود" });

        return Ok(type);
    }

    /// <summary>
    /// إنشاء نوع مشتريات جديد
    /// </summary>
    [HttpPost]
    public async Task<ActionResult> CreatePurchaseType([FromBody] CreatePurchaseTypeRequest request)
    {
        try
        {
            var organizationId = GetOrganizationIdFromToken();
            if (organizationId == Guid.Empty)
                return Unauthorized();

            var type = new PurchaseType
            {
                OrganizationId = organizationId,
                TypeName = request.TypeName,
                Description = request.Description,
                Route = request.Route, // "traditional" أو "direct"
                IsActive = true,
                DisplayOrder = request.DisplayOrder ?? 0
            };

            _db.PurchaseTypes.Add(type);
            await _db.SaveChangesAsync();

            return CreatedAtAction(nameof(GetPurchaseType), new { id = type.Id }, type);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// تحديث نوع مشتريات
    /// </summary>
    [HttpPut("{id}")]
    public async Task<ActionResult> UpdatePurchaseType(Guid id, [FromBody] UpdatePurchaseTypeRequest request)
    {
        try
        {
            var type = await _db.PurchaseTypes.FindAsync(id);
            if (type == null)
                return NotFound(new { message = "نوع المشتريات غير موجود" });

            type.TypeName = request.TypeName ?? type.TypeName;
            type.Description = request.Description ?? type.Description;
            type.Route = request.Route ?? type.Route;
            type.DisplayOrder = request.DisplayOrder ?? type.DisplayOrder;

            await _db.SaveChangesAsync();

            return Ok(new { message = "تم التحديث بنجاح", type });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// تفعيل/تعطيل نوع مشتريات
    /// </summary>
    [HttpPatch("{id}/toggle")]
    public async Task<ActionResult> TogglePurchaseType(Guid id)
    {
        try
        {
            var type = await _db.PurchaseTypes.FindAsync(id);
            if (type == null)
                return NotFound(new { message = "نوع المشتريات غير موجود" });

            type.IsActive = !type.IsActive;
            await _db.SaveChangesAsync();

            return Ok(new {
                message = type.IsActive ? "تم التفعيل" : "تم التعطيل",
                isActive = type.IsActive
            });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    // ── التسليمات المباشرة ────────────────────────────────────────

    /// <summary>
    /// الحصول على التسليمات المباشرة
    /// </summary>
    [HttpGet("direct-deliveries")]
    public async Task<ActionResult<IEnumerable<DirectDelivery>>> GetDirectDeliveries()
    {
        var deliveries = await _db.DirectDeliveries
            .OrderByDescending(d => d.DeliveryDate)
            .ToListAsync();

        return Ok(deliveries);
    }

    /// <summary>
    /// إنشاء تسليم مباشر جديد
    /// </summary>
    [HttpPost("direct-deliveries")]
    public async Task<ActionResult> CreateDirectDelivery([FromBody] DirectDeliveryRequest request)
    {
        try
        {
            // التحقق من وجود الفاتورة
            var purchase = await _db.Invoices.FindAsync(request.PurchaseId);
            if (purchase == null)
                return BadRequest(new { message = "الفاتورة غير موجودة" });

            var delivery = new DirectDelivery
            {
                PurchaseId = request.PurchaseId,
                CustomerId = request.CustomerId,
                SupplierId = request.SupplierId,
                DeliveryDate = request.DeliveryDate,
                DeliveryStatus = "pending"
            };

            _db.DirectDeliveries.Add(delivery);
            await _db.SaveChangesAsync();

            return CreatedAtAction(nameof(GetDirectDeliveries), delivery);
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// تحديث حالة التسليم المباشر
    /// </summary>
    [HttpPatch("direct-deliveries/{id}/status")]
    public async Task<ActionResult> UpdateDirectDeliveryStatus(Guid id, [FromBody] UpdateDeliveryStatusRequest request)
    {
        try
        {
            var delivery = await _db.DirectDeliveries.FindAsync(id);
            if (delivery == null)
                return NotFound(new { message = "التسليم غير موجود" });

            delivery.DeliveryStatus = request.Status;
            if (request.Status == "received")
                delivery.ReceivedDate = DateTime.UtcNow;

            await _db.SaveChangesAsync();

            return Ok(new { message = "تم تحديث الحالة بنجاح", delivery });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { message = $"خطأ: {ex.Message}" });
        }
    }

    // ── Helper Methods ─────────────────────────────────────────────

    private Guid GetOrganizationIdFromToken()
    {
        var claim = User.FindFirst("organization_id");
        if (claim != null && Guid.TryParse(claim.Value, out var id))
            return id;
        return Guid.Empty;
    }
}

// ── Request/Response Models ────────────────────────────────────────

public record CreatePurchaseTypeRequest(
    string TypeName,
    string Description,
    string Route,  // "traditional" أو "direct"
    int? DisplayOrder = 0
);

public record UpdatePurchaseTypeRequest(
    string? TypeName = null,
    string? Description = null,
    string? Route = null,
    int? DisplayOrder = null
);

public record UpdateDeliveryStatusRequest(
    string Status  // "pending", "delivered", "received"
);
