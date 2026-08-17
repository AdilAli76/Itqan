using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// "غرفة إشعارات مركزية" (ARCHITECTURE.md §2.10) — is_read حالة مشتركة على
/// مستوى المنظمة/الفرع (عمود واحد في notifications، وليس جدول تتبّع لكل
/// مستخدم على حدة)، فمن يقرأ إشعاراً يعلّمه مقروءاً للجميع. هذا قرار
/// تصميمي من المخطط نفسه (غرفة واحدة مشتركة) وليس تبسيطاً مؤقتاً.
/// </summary>
[ApiController]
[Route("api/notifications")]
[Authorize]
public class NotificationsController : ControllerBase
{
    private readonly AppDbContext _db;
    public NotificationsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<NotificationItem>>> GetAll([FromQuery] bool? isRead)
    {
        var query = _db.Notifications.AsQueryable();

        // branch_id وصفي فقط على مستوى قاعدة البيانات (راجع NotificationsPolicy
        // في DATABASE_SCHEMA_SQLSERVER.sql) — الفلترة الفعلية هنا: تنبيهات
        // المنظمة كاملة (BranchId == null) + تنبيهات فرع المستخدم تحديداً.
        // مدير عام بلا branch_id في التوكن يرى كل التنبيهات.
        if (Guid.TryParse(User.FindFirstValue("branch_id"), out var branchId))
        {
            query = query.Where(n => n.BranchId == null || n.BranchId == branchId);
        }

        if (isRead.HasValue) query = query.Where(n => n.IsRead == isRead.Value);

        return await query.OrderByDescending(n => n.CreatedAt).Take(200).ToListAsync();
    }

    [HttpPost("{id:guid}/read")]
    public async Task<IActionResult> MarkRead(Guid id)
    {
        var notification = await _db.Notifications.FindAsync(id);
        if (notification is null) return NotFound();

        notification.IsRead = true;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("mark-all-read")]
    public async Task<IActionResult> MarkAllRead()
    {
        var query = _db.Notifications.Where(n => !n.IsRead);
        if (Guid.TryParse(User.FindFirstValue("branch_id"), out var branchId))
        {
            query = query.Where(n => n.BranchId == null || n.BranchId == branchId);
        }

        await query.ExecuteUpdateAsync(s => s.SetProperty(n => n.IsRead, true));
        return NoContent();
    }
}
