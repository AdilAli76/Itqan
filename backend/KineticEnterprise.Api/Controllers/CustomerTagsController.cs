using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CustomerTagDto(Guid Id, Guid CustomerId, string TagName, string? Color);
public record CreateCustomerTagRequest(string TagName, string? Color = null);

/// <summary>
/// أوسمُ تصنيف العملاء — لكل عميلٍ عدّة أوسمٍ حسب احتياجات الإدارة.
/// مثلاً: VIP، مشترٍ متكرّر، الجملة، إلخ.
/// </summary>
[ApiController]
[Route("api/customer-tags")]
[Authorize]
public class CustomerTagsController : ControllerBase
{
    private readonly AppDbContext _db;
    public CustomerTagsController(AppDbContext db) => _db = db;

    /// <summary>
    /// جميع الأوسمِ لعميل محدّد.
    /// </summary>
    [HttpGet("customer/{customerId:guid}")]
    public async Task<ActionResult<List<CustomerTagDto>>> GetTagsForCustomer(Guid customerId)
    {
        var tags = await _db.CustomerTags
            .Where(t => t.CustomerId == customerId)
            .OrderBy(t => t.TagName)
            .Select(t => new CustomerTagDto(t.Id, t.CustomerId, t.TagName, t.Color))
            .ToListAsync();

        return Ok(tags);
    }

    /// <summary>
    /// قائمة جميع الأوسمِ المستعملة في المنظمة — للاستكمال الآلي في الواجهة.
    /// </summary>
    [HttpGet("autocomplete")]
    public async Task<ActionResult<List<string>>> GetAvailableTags()
    {
        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var tags = await _db.CustomerTags
            .Where(t => t.OrganizationId == orgId)
            .Select(t => t.TagName)
            .Distinct()
            .OrderBy(t => t)
            .ToListAsync();

        return Ok(tags);
    }

    /// <summary>
    /// إضافة وسمٍ لعميل.
    /// </summary>
    [HttpPost]
    [Authorize(Roles = "super_admin,branch_manager,cashier")]
    public async Task<ActionResult<CustomerTagDto>> AddTag(Guid customerId, CreateCustomerTagRequest request)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == customerId && !c.IsDeleted);
        if (customer is null) return NotFound(new { message = "العميل غير موجود" });

        if (string.IsNullOrWhiteSpace(request.TagName))
            return BadRequest(new { message = "اسم الوسم إلزامي" });

        // تفادي الأوسمِ المكررة للعميل نفسه.
        var exists = await _db.CustomerTags
            .AnyAsync(t => t.CustomerId == customerId && t.TagName == request.TagName.Trim());
        if (exists)
            return Conflict(new { message = $"العميل لديه الوسم «{request.TagName}» بالفعل" });

        var tag = new CustomerTag
        {
            OrganizationId = customer.OrganizationId,
            CustomerId = customerId,
            TagName = request.TagName.Trim(),
            Color = request.Color?.Trim(),
        };

        _db.CustomerTags.Add(tag);
        _db.LogAudit(customer.OrganizationId, CurrentUserId(), "customer_tag.added", "customer_tags",
            tag.Id, newValues: new { tag.TagName, tag.Color });
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetTagsForCustomer), new { customerId },
            new CustomerTagDto(tag.Id, tag.CustomerId, tag.TagName, tag.Color));
    }

    /// <summary>
    /// حذف وسمٍ من عميل.
    /// </summary>
    [HttpDelete("{tagId:guid}")]
    [Authorize(Roles = "super_admin,branch_manager")]
    public async Task<IActionResult> RemoveTag(Guid tagId)
    {
        var tag = await _db.CustomerTags.FirstOrDefaultAsync(t => t.Id == tagId);
        if (tag is null) return NotFound();

        _db.CustomerTags.Remove(tag);
        _db.LogAudit(tag.OrganizationId, CurrentUserId(), "customer_tag.removed", "customer_tags", tagId,
            oldValues: new { tag.TagName });
        await _db.SaveChangesAsync();

        return NoContent();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
