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
/// نفس نمط ProductsController بالضبط — Security Policy على جدول suppliers
/// (fn_OrgOnlyPredicate) تتكفّل بعزل المنظمة تلقائياً.
/// </summary>
[RequireModule("inventory")]
[ApiController]
[Route("api/suppliers")]
[Authorize]
public class SuppliersController : ControllerBase
{
    private readonly AppDbContext _db;
    public SuppliersController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<Supplier>>> GetAll([FromQuery] string? search)
    {
        var query = _db.Suppliers.Where(s => !s.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(s => s.Name.Contains(search) || (s.Phone != null && s.Phone.Contains(search)));
        }
        return await query.OrderBy(s => s.Name).ToListAsync();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<Supplier>> GetById(Guid id)
    {
        var supplier = await _db.Suppliers.FindAsync(id);
        return supplier is null ? NotFound() : supplier;
    }

    [HttpPost]
    [RequirePermission("suppliers.manage")]
    public async Task<ActionResult<Supplier>> Create(Supplier supplier)
    {
        supplier.OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!);
        _db.Suppliers.Add(supplier);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetById), new { id = supplier.Id }, supplier);
    }

    [HttpPut("{id:guid}")]
    [RequirePermission("suppliers.manage")]
    public async Task<IActionResult> Update(Guid id, Supplier update)
    {
        var supplier = await _db.Suppliers.FindAsync(id);
        if (supplier is null) return NotFound();

        supplier.Name = update.Name;
        supplier.Phone = update.Phone;
        supplier.Balance = update.Balance;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // حذف فعلي غير مسموح به (راجع ARCHITECTURE.md §3.2) — منتجات قديمة قد
    // تشير لهذا المورّد، فالحذف الفعلي يكسر سجلها التاريخي. فقط Soft Delete.
    [HttpDelete("{id:guid}")]
    [RequirePermission("suppliers.delete")]
    public async Task<IActionResult> SoftDelete(Guid id)
    {
        var supplier = await _db.Suppliers.FindAsync(id);
        if (supplier is null) return NotFound();

        supplier.IsDeleted = true;
        _db.LogAudit(supplier.OrganizationId, CurrentUserId(), "supplier.deleted", "suppliers", supplier.Id,
            oldValues: new { supplier.Name });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
