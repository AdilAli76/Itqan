using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record MedicineReferencePageDto(List<MedicineReference> Items, int TotalCount, int Page, int PageSize);

/// <summary>
/// نشرة الدواء — لإصدار الصيدليات وحده.
///
/// <para><b>[RequireModule("pharmacy")] على الصنف كلّه</b>: النظام يُباع
/// لبقالة ومحل قطع غيار ومخزن مواد بناء أيضاً، وحقول «موانع الاستعمال»
/// و«الجرعة» عندهم ضوضاء لا ميزة. إخفاء الشاشة في الواجهة وحده لا يكفي —
/// من يعرف المسار يستطيع استدعاءه مباشرةً، فالحارس هنا على الخادم.</para>
///
/// <para><b>لا Security Policy على هذا الجدول</b> لأنه معرفة عامة على مستوى
/// المنصّة لا بيانات منظمة (راجع [MedicineReference]). ولهذا تحديداً
/// <b>الكتابة محصورة بمالك المنصّة</b>: صفٌّ واحد يراه كل العملاء، فترك
/// تعديله لأي منظمة يعني أن صيدلية تُفسد نشرة تظهر لبقية الصيدليات.
/// القراءة متاحة لكل من يملك الوحدة.</para>
/// </summary>
[ApiController]
[Route("api/medicine-reference")]
[Authorize]
[RequireModule("pharmacy")]
public class MedicineReferenceController : ControllerBase
{
    private readonly AppDbContext _db;
    public MedicineReferenceController(AppDbContext db) => _db = db;

    private bool IsPlatformAdmin() =>
        string.Equals(User.FindFirstValue("is_platform_admin"), "True", StringComparison.OrdinalIgnoreCase);

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }

    /// <summary>
    /// بحث بالاسم أو المادة الفعّالة. المادة الفعّالة مشمولة عمداً: الصيدلي
    /// يبحث عن بديل لدواء ناقص، والبديل يشترك في المادة لا في الاسم التجاري.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<MedicineReferencePageDto>> GetAll(
        [FromQuery] string? search,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = _db.MedicineReferences.Where(m => !m.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(m => m.Name.Contains(search) || m.ActiveIngredient.Contains(search));
        }

        var total = await query.CountAsync();
        var items = await query
            .OrderBy(m => m.Name)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return new MedicineReferencePageDto(items, total, page, pageSize);
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<MedicineReference>> GetById(Guid id)
    {
        var item = await _db.MedicineReferences.FirstOrDefaultAsync(m => m.Id == id && !m.IsDeleted);
        return item is null ? NotFound() : item;
    }

    [HttpPost]
    public async Task<ActionResult<MedicineReference>> Create(MedicineReference request)
    {
        if (!IsPlatformAdmin()) return Forbid();
        if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.ActiveIngredient))
        {
            return BadRequest(new { message = "الاسم والمادة الفعّالة مطلوبان" });
        }

        request.Id = Guid.NewGuid();
        request.IsDeleted = false;
        request.CreatedAt = DateTime.UtcNow;
        request.UpdatedAt = DateTime.UtcNow;
        _db.MedicineReferences.Add(request);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetById), new { id = request.Id }, request);
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, MedicineReference update)
    {
        if (!IsPlatformAdmin()) return Forbid();

        var item = await _db.MedicineReferences.FirstOrDefaultAsync(m => m.Id == id && !m.IsDeleted);
        if (item is null) return NotFound();

        item.Name = update.Name;
        item.ActiveIngredient = update.ActiveIngredient;
        item.Strength = update.Strength;
        item.Form = update.Form;
        item.Indications = update.Indications;
        item.Contraindications = update.Contraindications;
        item.Cautions = update.Cautions;
        item.SideEffects = update.SideEffects;
        item.RequiresPrescription = update.RequiresPrescription;
        item.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// حذف منطقي فقط — الأصناف المرتبطة بالنشرة في كل المنظمات تبقى تشير
    /// إليها، والحذف الفعلي كان يكسر مفتاحاً أجنبياً عند عميل لا علاقة له
    /// بمن طلب الحذف.
    /// </summary>
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        if (!IsPlatformAdmin()) return Forbid();

        var item = await _db.MedicineReferences.FirstOrDefaultAsync(m => m.Id == id && !m.IsDeleted);
        if (item is null) return NotFound();

        item.IsDeleted = true;
        item.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}
