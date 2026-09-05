using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <param name="RememberMe">
/// «ابقني مسجَّلاً على هذا الجهاز» — جلسةٌ بمدّة
/// [AuthController.RememberLifetime] بدل ثماني ساعات.
///
/// <para><b>سبب وجوده:</b> الجلسة كانت ثماني ساعات لكل حالة، فصاحب المحلّ
/// يفتح النظام كل صباح فيُطالَب بكلمة مروره — كل يوم، بلا استثناء. وما
/// يُطلَب يومياً يُختصر: تصير الكلمة قصيرة، أو مكتوبةً على ورقة تحت لوحة
/// المفاتيح.</para>
///
/// <para><b>واختيارٌ صريح لا افتراض:</b> جهاز كاشير في محلّ تمرّ عليه
/// أيدٍ كثيرة، وجلسةٌ لا تنتهي عليه بابٌ مفتوح. فمن يعلّم الخانة يقرّر
/// لجهازه هو.</para>
/// </param>
public record LoginRequest(string EmailOrUsername, string Password, bool RememberMe = false);
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public record LoginResponse(
    string Token, string Role, Guid OrganizationId, Guid? BranchId, string FullName,
    /// لوح خلفية فرع المستخدم — راجع Branch.ThemePalette.
    ///
    /// يُرسَل مع الدخول لا بطلب ثانٍ: الشاشة الأولى يجب أن تظهر بلوحها
    /// الصحيح، لا أن تومض بالمحايد ثم تتبدّل أمام المستخدم.
    string BranchPalette,
    /// كلمةٌ مؤقّتة تنتظر التغيير — الواجهة تفتح شاشة التغيير فوراً.
    ///
    /// <para>في ردّ الدخول لا بنداءٍ ثانٍ: النداء الثاني قد يفشل، فيدخل
    /// المستخدم إلى نظامٍ يردّ كل طلب بـ403 بلا أن يعرف لماذا.</para>
    bool MustChangePassword);

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _config;

    public AuthController(AppDbContext db, IConfiguration config)
    {
        _db = db;
        _config = config;
    }

    [HttpPost("login")]
    public async Task<ActionResult<LoginResponse>> Login(LoginRequest request)
    {
        var user = await _db.AppUsers
            .FirstOrDefaultAsync(u => u.IsActive
                && (u.Email == request.EmailOrUsername || u.Username == request.EmailOrUsername));

        var passwordOk = user is not null && BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash);

        // login_history كان معرَّفاً في المخطط بلا أي كود يكتب إليه — لا يمكن
        // عزو محاولة ببريد غير موجود أصلاً لأي منظمة، فتُسجَّل فقط المحاولات
        // (ناجحة أو بكلمة مرور خاطئة) المرتبطة بمستخدم فعلي.
        if (user is not null)
        {
            _db.LoginHistories.Add(new LoginHistory
            {
                UserId = user.Id,
                OrganizationId = user.OrganizationId,
                IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
                DeviceInfo = Request.Headers.UserAgent.ToString(),
                Success = passwordOk,
            });
            await _db.SaveChangesAsync();
        }

        if (!passwordOk || user is null)
        {
            // رسالة عامة عمداً لعدم كشف وجود البريد من عدمه. الشرط الثاني
            // زائد منطقياً (passwordOk صحيح فقط إن كان user غير null) لكنه
            // يمنّح المترجم تضييقاً صريحاً لـ nullable بدلاً من تحذير كاذب.
            return Unauthorized(new { message = "بيانات الدخول غير صحيحة" });
        }

        var token = IssueToken(user, request.RememberMe);

        // لوح الفرع يُقرأ بلا سياق عزل: المستخدم لم يُصادَق بعد في هذه
        // اللحظة، وقراءة صفّ فرعه هو بمعرّفه المعلوم لا تُسرّب شيئاً.
        var branchPalette = user.BranchId.HasValue
            ? await _db.Branches
                .Where(b => b.Id == user.BranchId.Value)
                .Select(b => b.ThemePalette)
                .FirstOrDefaultAsync() ?? "default"
            : "default";

        return new LoginResponse(
            token,
            user.Role,
            user.OrganizationId,
            user.BranchId,
            user.FullName,
            branchPalette,
            user.MustChangePassword
        );
    }

    /// <summary>
    /// يغيّر المستخدم كلمة مروره هو.
    ///
    /// <para><b>الفجوة التي تسدّها:</b> لم تكن في النظام كلّه نقطةٌ لهذا.
    /// النقطتان الموجودتان كلتاهما «أعِد تعيين كلمة مرور <b>شخصٍ آخر</b>»:
    /// واحدة لمالك المنصّة على عملائه، وأخرى لمدير المنظمة على موظّفيه.
    /// فكلمةٌ مؤقّتة أُمليت هاتفياً تبقى كلمة الحساب الدائمة، ويعرفها
    /// اثنان.</para>
    ///
    /// <para><b>وهنا لا في <c>UsersController</c>:</b> تلك مقصورة على
    /// <c>super_admin</c> و<c>branch_manager</c>، فكاشيرٌ أُعيدت كلمته لم
    /// يكن يملك تغييرها إطلاقاً. وتغييرُ المرء كلمته حقٌّ لكل حساب لا
    /// صلاحيةٌ تُمنح.</para>
    ///
    /// <para><b>والكلمة القديمة مطلوبة</b> وإن كان التوكن صالحاً: جهازٌ
    /// تُرك مفتوحاً في محلّ يكفي عندها للاستيلاء على الحساب نهائياً — بينما
    /// طلبُها يجعل أسوأ ما يفعله المارّ استعمالَ الجلسة حتى تنتهي.</para>
    ///
    /// <para>ولا تُقصَر على <c>[Authorize]</c> وحدها: <c>Program.cs</c>
    /// يفرض [MustChangePasswordFilter] على كل شيء، وهذه النقطة مُعفاة منه
    /// وإلا صار من يجب أن يغيّر كلمته عاجزاً عن تغييرها.</para>
    /// </summary>
    [Microsoft.AspNetCore.Authorization.Authorize]
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword(ChangePasswordRequest request)
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(raw, out var userId)) return Unauthorized();

        // app_users بلا عزل صفوف عمداً — الشرط على المعرّف من التوكن، وهو
        // ما لا يستطيع المستخدم تزويره.
        var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null) return Unauthorized();

        if (!BCrypt.Net.BCrypt.Verify(request.CurrentPassword ?? "", user.PasswordHash))
        {
            return BadRequest(new { message = "كلمة المرور الحالية غير صحيحة" });
        }

        var org = await _db.Organizations.FirstOrDefaultAsync(o => o.Id == user.OrganizationId);
        var minLength = org?.PasswordMinLength ?? 6;
        if ((request.NewPassword ?? "").Length < minLength)
        {
            return BadRequest(new { message = $"كلمة المرور الجديدة {minLength} أحرف على الأقل" });
        }

        // ورفضُ الكلمة نفسها: «غيّرها» التي تُنفَّذ بإعادة كتابتها لا تغيّر
        // شيئاً، وتُخفض العلم فتظنّ أن المؤقّتة استُبدلت وهي لم تُستبدل.
        if (BCrypt.Net.BCrypt.Verify(request.NewPassword, user.PasswordHash))
        {
            return BadRequest(new { message = "الكلمة الجديدة هي نفسها القديمة" });
        }

        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
        user.MustChangePassword = false;

        // ويُسجَّل: تغيير كلمة مرور حدثٌ يُسأل عنه عند التحقيق في وصولٍ
        // غير مأذون، وسجلٌّ بلا هذا الحدث يترك ثغرةً في السرد.
        _db.LogAudit(user.OrganizationId, user.Id, "user.password_changed", "app_users", user.Id,
            newValues: new { user.FullName });

        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>مدّة الجلسة — رقمٌ واحد يقرؤه الإصدار والتجديد معاً.</summary>
    ///
    /// <para>كان مكتوباً في موضع بناء التوكن وحده. وبإضافة التجديد صار
    /// موضعين، ورقمٌ يُغيَّر في أحدهما يُنتج جلسةً تُجدَّد بمدّةٍ غير التي
    /// بدأت بها — فرقٌ لا يلاحظه أحد حتى يشتكي مستخدم من خروجٍ مبكّر.</para>
    public static readonly TimeSpan SessionLifetime = TimeSpan.FromHours(8);

    /// <summary>
    /// مدّة جلسة «ابقني مسجَّلاً» — ثلاثون يوماً.
    ///
    /// <para><b>ولماذا مدّةٌ لا «إلى الأبد»:</b> توكنٌ بلا انتهاء يبقى صالحاً
    /// على جهازٍ ضاع أو بِيع بعد سنتين. وثلاثون يوماً تكفي ألّا يُسأل أحد عن
    /// كلمته في عملٍ يومي، وتُغلق الباب على جهازٍ نُسي.</para>
    ///
    /// <para><b>وحسابٌ يُعطَّل لا ينتظرها:</b> صلاحية التوكن تُفحَص عند كل
    /// طلب مقابل حالة الحساب — راجع فحص <c>is_active</c> في
    /// <c>Program.cs</c>. وبدونه كان تعطيل موظّفٍ سُرِّح لا يُنفَّذ إلا بعد
    /// ثلاثين يوماً.</para>
    public static readonly TimeSpan RememberLifetime = TimeSpan.FromDays(30);

    /// <summary>
    /// يبني توكن هذا المستخدم — المصدر الوحيد لدعاواه.
    ///
    /// <para>استُخرج حين أُضيف التجديد: نسختان من قائمة الدعاوى تفترقان أوّل
    /// مرّة تُضاف دعوى، فيفقد من جدّد جلسته دعوىً يملكها من دخل للتوّ —
    /// ويظهر ذلك كصلاحيةٍ تختفي بعد ثماني ساعات بلا سبب.</para>
    /// </summary>
    private string IssueToken(AppUser user, bool remember = false)
    {
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new("organization_id", user.OrganizationId.ToString()),
            // ClaimTypes.Role هو الرابط الطويل الفعلي الذي يقرأه [Authorize(Roles=...)]
            // وUser.IsInRole(...) في الباك اند — لا يجوز تغييره. لكن كل شاشة في
            // Flutter كانت تقرأ claims['role'] (مفتاح قصير) ظانّةً أنه نفس الشيء،
            // فكانت تحصل على null دائماً بصمت (كل شاشات super_admin كانت تُعامَل
            // "قراءة فقط" فعلياً طوال الوقت دون أن يظهر خطأ واضح). الحل: إضافة
            // ادّعاء قصير مكرَّر "role" خصيصاً للواجهة، بلا مساس بمنطق التصريح
            // في الباك اند الذي يبقى يعتمد على ClaimTypes.Role كما هو.
            new(ClaimTypes.Role, user.Role),
            // علامة «ابقني مسجَّلاً» في التوكن نفسه: التجديد يقرأها ليُصدر
            // بنفس المدّة. وبدونها كان من يمدّ جلسته الطويلة يسقط إلى ثماني
            // ساعات بلا أن يطلب ذلك — فيُطالَب بكلمته صباح الغد وقد اختار
            // ألّا يُطالَب.
            new("remember", remember ? "1" : "0"),
            // الاسم في التوكن لا في نداء منفصل: يُطبَع على أوامر الشراء
            // تحت خانة «أصدره»، ويُعرض في الواجهة. توقيع بلا اسم مقروء لا
            // يدلّ على أحد بعد شهور.
            new(ClaimTypes.Name, user.FullName),
            new("role", user.Role),
        };
        if (user.BranchId.HasValue)
        {
            claims.Add(new Claim("branch_id", user.BranchId.Value.ToString()));
        }
        if (user.IsPlatformAdmin)
        {
            claims.Add(new Claim("is_platform_admin", "True"));
            // الدور في التوكن لا في نداءٍ ثانٍ: كل نقطة منصّة تفحصه، وقراءته
            // من القاعدة في كل طلب استعلامٌ إضافي على مسارٍ ساخن.
            //
            // والغياب يعني مالكاً — راجع [PlatformRoles.IsOwner]. وتوكن
            // أُصدر قبل هذا الترحيل يبقى صالحاً ثماني ساعات، وتفسيره
            // «مهندس» كان يسلب مالك المنصّة صلاحياته حتى ينتهي.
            claims.Add(new Claim(
                "platform_role",
                user.PlatformRole ?? PlatformRoles.Owner));

            // ورقم ترخيص البائع معه: يُطبع في عقد كل عميل يبيعه صاحب هذا
            // التوكن. وقراءته بنداءٍ ثانٍ عند كل طباعة تعني عقداً يخرج بلا
            // رقم إن تعثّر النداء — وذاك أسوأ من ألّا يُطبع أصلاً، لأنه
            // يخرج موقَّعاً ناقصاً ولا يلاحظه أحد.
            if (!string.IsNullOrWhiteSpace(user.ResellerLicense))
            {
                claims.Add(new Claim("reseller_license", user.ResellerLicense));
            }
        }
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_config["Jwt:Key"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var jwt = new JwtSecurityToken(
            issuer: _config["Jwt:Issuer"],
            audience: _config["Jwt:Audience"],
            claims: claims,
            expires: DateTime.UtcNow.Add(remember ? RememberLifetime : SessionLifetime),
            signingCredentials: creds
        );
        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }

    /// <summary>
    /// يُصدر توكناً جديداً لحاملِ توكنٍ ما زال صالحاً.
    ///
    /// <para><b>لماذا تُوجد أصلاً:</b> الجلسة ثماني ساعات ثابتة بلا تجديد،
    /// فكان أوّل نداء بعدها يردّ 401 ويُقذف المستخدم إلى شاشة الدخول **بلا
    /// إنذار** — في منتصف فاتورة أحياناً. والواجهة تُنذر قبل الانتهاء بخمس
    /// دقائق وتعرض «مدِّد»، وهذه هي النقطة التي يناديها الزرّ.</para>
    ///
    /// <para><b>ولا تمديد صامت بالنشاط:</b> جهاز كاشير في محلّ يجب أن تنتهي
    /// جلسته فعلاً في آخر الوردية. والتمديد فعلٌ يُتخذ لا حقٌّ يُكتسب
    /// بالحركة.</para>
    ///
    /// <para><b>وتُعاد قراءة المستخدم من القاعدة:</b> بناء التوكن الجديد من
    /// دعاوى القديم كان يُخلّد صلاحيةً سُحبت وحساباً عُطِّل — فيمدّد الموقوفُ
    /// جلسته إلى الأبد بضغطة كل ثماني ساعات.</para>
    /// </summary>
    [Microsoft.AspNetCore.Authorization.Authorize]
    [HttpPost("refresh")]
    public async Task<ActionResult<LoginResponse>> Refresh()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(raw, out var userId)) return Unauthorized();

        var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == userId && u.IsActive);
        if (user is null) return Unauthorized();

        var branchPalette = user.BranchId.HasValue
            ? await _db.Branches
                .Where(b => b.Id == user.BranchId.Value)
                .Select(b => b.ThemePalette)
                .FirstOrDefaultAsync() ?? "default"
            : "default";

        return new LoginResponse(
            IssueToken(user, User.FindFirstValue("remember") == "1"),
            user.Role, user.OrganizationId, user.BranchId,
            user.FullName, branchPalette, user.MustChangePassword);
    }

}
