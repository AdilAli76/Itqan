using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record PlatformEngineerDto(
    Guid Id, string FullName, string Email, string ResellerLicense,
    bool IsActive, string PlatformRole, DateTime CreatedAt,
    /// عدد العملاء المنسوبين إليه — الرقم الذي يقول هل يبيع فعلاً.
    int OrganizationCount);

public record CreateEngineerRequest(string FullName, string Email, string Password);
public record UpdateEngineerRequest(string FullName, bool IsActive, string? ResellerLicense = null);
public record ReassignOrganizationRequest(Guid? EngineerUserId);

/// <summary>
/// مهندسو البيع — وكلاءُ يبيعون النظام تحت ترخيص مالك المنصّة.
///
/// <para><b>ما يفصلهم عن مالك المنصّة:</b> يرون ما باعوه وحدهم (راجع
/// [PlatformScope])، ولا يحذفون منظمة، ولا يُنشئون مهندساً آخر. وما عدا
/// ذلك يملكونه: إنشاء عميل، وتمديد ترخيصه، وبيع الوحدات فوق إصداره —
/// وإلّا كانوا مسوّقين يرجعون إليك في كل تجديد، لا بائعين.
/// </para>
///
/// <para><b>ولماذا لا يُنشئ المهندسُ مهندساً:</b> لصارت لكل واحد شبكتُه
/// تحت ترخيصك بلا علمك، ولا سبيل بعدها إلى معرفة من أدخل من.</para>
///
/// <para><b>ولماذا حسابات المنصّة كلّها في منظمة من أنشأها:</b> حساب
/// المستخدم مرتبطٌ بمنظمة في هذا النظام، ومهندسٌ بمنظمةٍ خاصة به يعني
/// منظمةً وهمية تُحسب في العدّاد وتظهر في قائمة العملاء. و
/// <c>is_platform_admin</c> هو ما يُخرجه من حدود تلك المنظمة لا
/// انتماؤه إليها.</para>
/// </summary>
[ApiController]
[Route("api/platform/engineers")]
[Authorize]
public class PlatformEngineersController : ControllerBase
{
    private readonly AppDbContext _db;
    public PlatformEngineersController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<PlatformEngineerDto>>> GetAll()
    {
        // مالك المنصّة وحده: القائمة تكشف من يبيع وكم يبيع، وهي بيانات
        // منافسين بعضهم لبعض.
        if (!PlatformScope.IsOwner(User)) return Forbid();

        // app_users بلا عزل صفوف عمداً (راجع AppDbContext)، فالفلترة على
        // العلم لا على المنظمة: حسابات المنصّة قد تقع في منظمات مختلفة.
        var users = await _db.AppUsers
            .Where(u => u.IsPlatformAdmin)
            .OrderBy(u => u.CreatedAt)
            .ToListAsync();

        // عدّاد العملاء دفعةً واحدة لا استعلاماً لكل مهندس: عشرون مهندساً
        // يعني عشرين رحلةً إلى القاعدة في نداءٍ يُفتح مع كل شاشة.
        var counts = await _db.PlatformOrganizations
            .Where(o => o.OwnerUserId != null)
            .GroupBy(o => o.OwnerUserId!.Value)
            .Select(g => new { OwnerId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.OwnerId, x => x.Count);

        return users.Select(u => new PlatformEngineerDto(
            u.Id, u.FullName, u.Email,
            u.ResellerLicense ?? "—",
            u.IsActive,
            u.PlatformRole ?? PlatformRoles.Owner,
            u.CreatedAt,
            counts.TryGetValue(u.Id, out var c) ? c : 0)).ToList();
    }

    /// <summary>
    /// إنشاء حساب مهندس بيع.
    ///
    /// <para>كلمة المرور تُدخَل هنا وتُسلَّم للمهندس ولا تُعرض بعدها — نفس
    /// ما يفعله إنشاء المنظمة بحساب مديرها. ورقم الترخيص يولّده النظام.</para>
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<PlatformEngineerDto>> Create(CreateEngineerRequest request)
    {
        if (!PlatformScope.IsOwner(User)) return Forbid();

        if (string.IsNullOrWhiteSpace(request.FullName) || string.IsNullOrWhiteSpace(request.Email)
            || string.IsNullOrWhiteSpace(request.Password))
        {
            return BadRequest(new { message = "الاسم والبريد وكلمة المرور إلزامية" });
        }
        if (request.Password.Length < 8)
        {
            return BadRequest(new { message = "كلمة المرور ثمانية أحرف فأكثر" });
        }

        var email = request.Email.Trim().ToLowerInvariant();

        // التفرّد على مستوى النظام كلّه لا المنظمة: البريد هو ما يُدخَل به،
        // وتكراره بين منظمتين يجعل تسجيل الدخول لا يعرف أيّهما.
        if (await _db.AppUsers.AnyAsync(u => u.Email == email))
        {
            return BadRequest(new { message = "هذا البريد مستعمل بالفعل" });
        }

        var me = PlatformScope.UserId(User);
        var myOrg = await _db.AppUsers
            .Where(u => u.Id == me)
            .Select(u => u.OrganizationId)
            .FirstOrDefaultAsync();
        if (myOrg == Guid.Empty)
        {
            return BadRequest(new { message = "تعذّرت قراءة منظمة حسابك" });
        }

        var user = new AppUser
        {
            OrganizationId = myOrg,
            BranchId = null,
            FullName = request.FullName.Trim(),
            Email = email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            // super_admin داخل منظمة المالك لا يمنحه شيئاً عملياً: كل ما
            // يفعله المهندس يمرّ بنقاط المنصّة المحروسة بـ[PlatformScope]،
            // لا بنقاط المنظمة. والدور مكتوبٌ هنا لأن العمود إلزامي.
            Role = "super_admin",
            IsActive = true,
            IsPlatformAdmin = true,
            PlatformRole = PlatformRoles.Engineer,
            ResellerLicense = await NextLicenseAsync(),
        };

        _db.AppUsers.Add(user);
        await _db.SaveChangesAsync();

        return StatusCode(201, new PlatformEngineerDto(
            user.Id, user.FullName, user.Email, user.ResellerLicense!,
            user.IsActive, user.PlatformRole!, user.CreatedAt, 0));
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, UpdateEngineerRequest request)
    {
        if (!PlatformScope.IsOwner(User)) return Forbid();

        var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == id && u.IsPlatformAdmin);
        if (user is null) return NotFound();

        // ولا يعطّل المالكُ حسابه هو: حسابٌ يُوقف نفسه بضغطة يُغلق المنصّة
        // على صاحبها، ولا نقطةَ تعيده إلا قاعدة البيانات.
        if (user.Id == PlatformScope.UserId(User) && !request.IsActive)
        {
            return BadRequest(new { message = "لا يمكنك تعطيل حسابك أنت" });
        }

        user.FullName = request.FullName.Trim();
        user.IsActive = request.IsActive;
        if (!string.IsNullOrWhiteSpace(request.ResellerLicense))
        {
            user.ResellerLicense = request.ResellerLicense.Trim();
        }

        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// إعادة نسبة عميل إلى مهندس آخر — أو إلى لا أحد.
    ///
    /// <para><b>قرار المالك وحده، ونقطةٌ مستقلّة عن تعديل المنظمة:</b>
    /// النسبةُ هي مدار العزل كلّه، فحقلٌ لها ضمن نموذج التعديل العادي كان
    /// يعني مهندساً ينقل عميل زميله إلى نفسه بتعديل نداء — وهو أخطر من
    /// رؤية عميلٍ ليس له.</para>
    ///
    /// <para>وتُستعمل حين يغادر مهندس، أو حين يتسلّم عميلاً مهندسٌ آخر.</para>
    /// </summary>
    [HttpPost("/api/platform/organizations/{organizationId:guid}/assign")]
    public async Task<IActionResult> Reassign(Guid organizationId, ReassignOrganizationRequest request)
    {
        if (!PlatformScope.IsOwner(User)) return Forbid();

        var index = await _db.PlatformOrganizations.FirstOrDefaultAsync(o => o.Id == organizationId);
        if (index is null) return NotFound();

        if (request.EngineerUserId is not null)
        {
            var exists = await _db.AppUsers.AnyAsync(u =>
                u.Id == request.EngineerUserId && u.IsPlatformAdmin && u.IsActive);
            if (!exists)
            {
                return BadRequest(new { message = "لا حساب منصّة نشط بهذا المعرّف" });
            }
        }

        index.OwnerUserId = request.EngineerUserId;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// رقم ترخيص جديد — <c>KE-0001</c> فصاعداً.
    ///
    /// <para>متسلسلٌ لا عشوائي: يُقرأ في الهاتف ويُكتب على ورقة، ورقمٌ من
    /// اثنتي عشرة خانة عشوائية يُخطئ في نقله من ينقله. ويُشتقّ من أكبر رقمٍ
    /// قائم لا من عدد الحسابات، فحذفُ حساب لا يُعيد رقمه إلى غيره.</para>
    /// </summary>
    private async Task<string> NextLicenseAsync()
    {
        var existing = await _db.AppUsers
            .Where(u => u.ResellerLicense != null)
            .Select(u => u.ResellerLicense!)
            .ToListAsync();

        var max = 0;
        foreach (var raw in existing)
        {
            var digits = new string(raw.Where(char.IsDigit).ToArray());
            if (int.TryParse(digits, out var n) && n > max) max = n;
        }

        return $"KE-{max + 1:D4}";
    }
}
