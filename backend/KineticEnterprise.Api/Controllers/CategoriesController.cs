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
/// جدول product_categories لا يحمل is_deleted (راجع
/// DATABASE_TABLES_GUIDE.md §5.2) — ليس جدولاً مالياً/مخزونياً بحد ذاته،
/// فالحذف الفعلي مقبول هنا، ويُمنع فقط إن كان صنف ما لا يزال مرتبطاً به.
/// </summary>
[RequireModule("inventory")]

/// <summary>
/// ما يُقبَل عند إنشاء تصنيف أو تعديله — الاسم وأبوه لا أكثر.
///
/// <para>كان الكيان يُربَط كاملاً فيقبل <c>id</c> من الطلب. راجع
/// <c>SaveCustomerRequest</c> للمبدأ نفسه.</para>
/// </summary>
public record SaveCategoryRequest(string Name, Guid? ParentId);

[ApiController]
[Route("api/categories")]
[Authorize]
public class CategoriesController : ControllerBase
{
    private readonly AppDbContext _db;
    public CategoriesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<ProductCategory>>> GetAll()
    {
        return await _db.ProductCategories.OrderBy(c => c.Name).ToListAsync();
    }

    [HttpPost]
    [RequirePermission("categories.manage")]
    public async Task<ActionResult<ProductCategory>> Create(SaveCategoryRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
            return BadRequest(new { message = "اسم التصنيف إلزامي" });

        var category = new ProductCategory
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            Name = request.Name.Trim(),
            ParentId = request.ParentId,
        };
        _db.ProductCategories.Add(category);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetAll), new { }, category);
    }

    [HttpPut("{id:guid}")]
    [RequirePermission("categories.manage")]
    public async Task<IActionResult> Update(Guid id, SaveCategoryRequest update)
    {
        if (string.IsNullOrWhiteSpace(update.Name))
            return BadRequest(new { message = "اسم التصنيف إلزامي" });

        var category = await _db.ProductCategories.FindAsync(id);
        if (category is null) return NotFound();

        category.Name = update.Name;
        category.ParentId = update.ParentId;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{id:guid}")]
    [RequirePermission("categories.manage")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var category = await _db.ProductCategories.FindAsync(id);
        if (category is null) return NotFound();

        _db.ProductCategories.Remove(category);
        _db.LogAudit(category.OrganizationId, CurrentUserId(), "category.deleted", "product_categories", category.Id,
            oldValues: new { category.Name });
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "لا يمكن حذف فئة مرتبطة بأصناف موجودة" });
        }
        return NoContent();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
