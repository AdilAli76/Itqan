using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record LoginRequest(string EmailOrUsername, string Password);
public record LoginResponse(
    string Token, string Role, Guid OrganizationId, Guid? BranchId, string FullName,
    /// لوح خلفية فرع المستخدم — راجع Branch.ThemePalette.
    ///
    /// يُرسَل مع الدخول لا بطلب ثانٍ: الشاشة الأولى يجب أن تظهر بلوحها
    /// الصحيح، لا أن تومض بالمحايد ثم تتبدّل أمام المستخدم.
    string BranchPalette);

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
        }

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_config["Jwt:Key"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            issuer: _config["Jwt:Issuer"],
            audience: _config["Jwt:Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddHours(8),
            signingCredentials: creds
        );

        // لوح الفرع يُقرأ بلا سياق عزل: المستخدم لم يُصادَق بعد في هذه
        // اللحظة، وقراءة صفّ فرعه هو بمعرّفه المعلوم لا تُسرّب شيئاً.
        var branchPalette = user.BranchId.HasValue
            ? await _db.Branches
                .Where(b => b.Id == user.BranchId.Value)
                .Select(b => b.ThemePalette)
                .FirstOrDefaultAsync() ?? "default"
            : "default";

        return new LoginResponse(
            new JwtSecurityTokenHandler().WriteToken(token),
            user.Role,
            user.OrganizationId,
            user.BranchId,
            user.FullName,
            branchPalette
        );
    }
}
