using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CreateUserRequest(string FullName, string Email, string? Username, string Password, string Role, Guid? BranchId);
public record UpdateUserRequest(string FullName, string? Username, string Role, Guid? BranchId, bool IsActive);
public record ResetPasswordRequest(string NewPassword);
public record LoginHistoryDto(Guid Id, Guid UserId, string UserName, string? IpAddress, string? DeviceInfo, bool Success, DateTime CreatedAt);

/// <summary>
/// لا نُعيد AppUser الخام أبداً من أي Endpoint — يحمل PasswordHash، وتسريب
/// حتى الهاش (وليس كلمة المرور الفعلية) للفرونت إند عبر الشبكة ممارسة
/// أمنية سيئة لا مبرر لها هنا.
/// </summary>
public record UserDto(Guid Id, Guid? BranchId, string FullName, string Email, string? Username, string Role, bool IsActive, DateTime CreatedAt);

/// <summary>
/// app_users استثناء متعمَّد من نمط Security Policy المتّبع في كل مكان
/// آخر: تسجيل الدخول نفسه (AuthController) يُنفَّذ *قبل* وجود أي
/// SESSION_CONTEXT، فأي FILTER/BLOCK PREDICATE هنا كانت ستمنع تسجيل
/// الدخول كلياً لكل مستخدمي النظام. لذلك — وهنا فقط — الفلترة اليدوية
/// بـ organization_id إلزامية في كل استعلام بهذا الكنترولر.
/// </summary>
[ApiController]
[Route("api/users")]
[Authorize(Roles = "super_admin,branch_manager")]
public class UsersController : ControllerBase
{
    private static readonly string[] ValidRoles =
        { "super_admin", "branch_manager", "cashier", "inventory_officer", "accountant", "custom" };

    private readonly AppDbContext _db;
    public UsersController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<UserDto>>> GetAll([FromQuery] string? search)
    {
        var orgId = CurrentOrgId();
        var query = _db.AppUsers.Where(u => u.OrganizationId == orgId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(u => u.FullName.Contains(search) || u.Email.Contains(search)
                || (u.Username != null && u.Username.Contains(search)));
        }
        var users = await query.OrderBy(u => u.FullName).ToListAsync();
        return users.Select(ToDto).ToList();
    }

    [HttpGet("login-history")]
    public async Task<ActionResult<List<LoginHistoryDto>>> GetLoginHistory()
    {
        var orgId = CurrentOrgId();
        var history = await _db.LoginHistories
            .Where(h => h.OrganizationId == orgId)
            .OrderByDescending(h => h.CreatedAt)
            .Take(200)
            .ToListAsync();

        var userIds = history.Select(h => h.UserId).Distinct().ToList();
        var userNames = await _db.AppUsers
            .Where(u => userIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName);

        return history.Select(h => new LoginHistoryDto(
            h.Id, h.UserId, userNames.GetValueOrDefault(h.UserId, "-"), h.IpAddress, h.DeviceInfo, h.Success, h.CreatedAt)).ToList();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<UserDto>> GetById(Guid id)
    {
        var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == id && u.OrganizationId == CurrentOrgId());
        return user is null ? NotFound() : ToDto(user);
    }

    [HttpPost]
    public async Task<ActionResult<UserDto>> Create(CreateUserRequest request)
    {
        if (!ValidRoles.Contains(request.Role))
        {
            return BadRequest(new { message = "دور غير صالح" });
        }
        if (!IsAllowedToAssign(request.Role))
        {
            return Forbid();
        }
        var minLength = await PasswordMinLength();
        if (request.Password.Length < minLength)
        {
            return BadRequest(new { message = $"كلمة المرور يجب أن تكون {minLength} أحرف على الأقل" });
        }

        var user = new AppUser
        {
            OrganizationId = CurrentOrgId(),
            BranchId = request.BranchId,
            FullName = request.FullName,
            Email = request.Email,
            Username = string.IsNullOrWhiteSpace(request.Username) ? null : request.Username.Trim(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            Role = request.Role,
        };
        _db.AppUsers.Add(user);
        _db.LogAudit(user.OrganizationId, CurrentUserId(), "user.created", "app_users", user.Id,
            newValues: new { user.FullName, user.Email, user.Role });

        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "البريد الإلكتروني أو اسم المستخدم مستخدَم بالفعل" });
        }
        return CreatedAtAction(nameof(GetById), new { id = user.Id }, ToDto(user));
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, UpdateUserRequest request)
    {
        var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == id && u.OrganizationId == CurrentOrgId());
        if (user is null) return NotFound();

        if (id == CurrentUserId())
        {
            return BadRequest(new { message = "لا يمكنك تعديل دورك أو حالتك الخاصة" });
        }
        if (!ValidRoles.Contains(request.Role))
        {
            return BadRequest(new { message = "دور غير صالح" });
        }
        if (!IsAllowedToAssign(request.Role))
        {
            return Forbid();
        }

        var roleChanged = user.Role != request.Role;
        var activeChanged = user.IsActive != request.IsActive;

        user.FullName = request.FullName;
        user.Username = string.IsNullOrWhiteSpace(request.Username) ? null : request.Username.Trim();
        user.Role = request.Role;
        user.BranchId = request.BranchId;
        user.IsActive = request.IsActive;

        if (roleChanged)
        {
            _db.LogAudit(user.OrganizationId, CurrentUserId(), "user.role_changed", "app_users", user.Id,
                newValues: new { user.FullName, NewRole = request.Role });
        }
        if (activeChanged)
        {
            _db.LogAudit(user.OrganizationId, CurrentUserId(), request.IsActive ? "user.activated" : "user.deactivated", "app_users", user.Id,
                newValues: new { user.FullName });
        }

        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { message = "اسم المستخدم مستخدَم بالفعل" });
        }
        return NoContent();
    }

    [HttpPost("{id:guid}/reset-password")]
    public async Task<IActionResult> ResetPassword(Guid id, ResetPasswordRequest request)
    {
        var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == id && u.OrganizationId == CurrentOrgId());
        if (user is null) return NotFound();

        var minLength = await PasswordMinLength();
        if (request.NewPassword.Length < minLength)
        {
            return BadRequest(new { message = $"كلمة المرور يجب أن تكون {minLength} أحرف على الأقل" });
        }

        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword);
        _db.LogAudit(user.OrganizationId, CurrentUserId(), "user.password_reset", "app_users", user.Id,
            newValues: new { user.FullName });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// حماية من تصعيد الصلاحيات: فقط super_admin يمنح دور super_admin أو
    /// branch_manager — مدير فرع لا يستطيع ترقية نفسه أو غيره لهذا المستوى.
    /// </summary>
    private bool IsAllowedToAssign(string role)
    {
        if (role is "super_admin" or "branch_manager")
        {
            return User.IsInRole("super_admin");
        }
        return true;
    }

    private static UserDto ToDto(AppUser user) =>
        new(user.Id, user.BranchId, user.FullName, user.Email, user.Username, user.Role, user.IsActive, user.CreatedAt);

    /// <summary>
    /// سياسة كلمة المرور (ARCHITECTURE.md §2.14) — تُقرأ من إعدادات المنظمة
    /// بدل رقم ثابت في الكود، حتى يتحكم كل زبون بحدّه الأدنى الخاص.
    /// </summary>
    private async Task<int> PasswordMinLength()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        return org?.PasswordMinLength ?? 6;
    }

    private Guid CurrentOrgId() => Guid.Parse(User.FindFirstValue("organization_id")!);

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
