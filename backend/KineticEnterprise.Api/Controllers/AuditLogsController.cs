using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record AuditLogDto(
    Guid Id, Guid? UserId, string UserName, string Action, string EntityTable,
    Guid? EntityId, string? OldValues, string? NewValues, DateTime CreatedAt);

public record AuditLogPageDto(List<AuditLogDto> Items, int TotalCount, int Page, int PageSize);

/// <summary>
/// "من فعل ماذا ومتى" — عرض للقراءة فقط، لا كتابة من هنا. الصفوف تُضاف من
/// الكنترولرات الأخرى عبر AuditLogExtensions.LogAudit عند أي عملية حساسة
/// (حذف، تعديل يدوي على رصيد/مخزون، استرجاع فاتورة).
/// </summary>
[ApiController]
[Route("api/audit-log")]
[Authorize]
[RequirePermission("audit_log.view")]
public class AuditLogsController : ControllerBase
{
    private readonly AppDbContext _db;
    public AuditLogsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<AuditLogPageDto>> GetAll(
        [FromQuery] string? search,
        [FromQuery] string? entityTable,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = await BuildFilteredQuery(search, entityTable, from, to);

        var totalCount = await query.CountAsync();
        var logs = await query.OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var items = await ToDtos(logs);
        return new AuditLogPageDto(items, totalCount, page, pageSize);
    }

    // نفس فلاتر GetAll لكن بلا صفحات — لتصدير/طباعة كل النتائج المطابقة
    // للفلتر الحالي دفعة واحدة (حتى 2000 سجل، حماية من طلب ضخم بالخطأ).
    [HttpGet("export")]
    public async Task<ActionResult<List<AuditLogDto>>> Export(
        [FromQuery] string? search,
        [FromQuery] string? entityTable,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var query = await BuildFilteredQuery(search, entityTable, from, to);
        var logs = await query.OrderByDescending(a => a.CreatedAt).Take(2000).ToListAsync();
        return await ToDtos(logs);
    }

    [HttpGet("entity-tables")]
    public async Task<ActionResult<List<string>>> GetEntityTables()
    {
        return await _db.AuditLogs.Select(a => a.EntityTable).Distinct().OrderBy(t => t).ToListAsync();
    }

    private async Task<IQueryable<AuditLog>> BuildFilteredQuery(
        string? search, string? entityTable, DateTime? from, DateTime? to)
    {
        var query = _db.AuditLogs.AsQueryable();

        if (!string.IsNullOrWhiteSpace(entityTable)) query = query.Where(a => a.EntityTable == entityTable);
        if (from.HasValue) query = query.Where(a => a.CreatedAt >= from.Value);
        if (to.HasValue) query = query.Where(a => a.CreatedAt < to.Value.AddDays(1));

        if (!string.IsNullOrWhiteSpace(search))
        {
            // اسم المستخدم غير مخزَّن مباشرة في audit_logs (فقط user_id)، فيُحلّ
            // أولاً لمعرّفات مطابقة قبل تطبيق البحث في SQL — هذا ما يجعل
            // الصفحات صحيحة فعلياً على *كامل* النتائج المطابقة، لا فقط
            // على آخر دفعة محمَّلة كما كان الحال سابقاً.
            var matchingUserIds = await _db.AppUsers
                .Where(u => u.FullName.Contains(search))
                .Select(u => u.Id)
                .ToListAsync();

            query = query.Where(a =>
                a.Action.Contains(search) ||
                a.EntityTable.Contains(search) ||
                (a.UserId.HasValue && matchingUserIds.Contains(a.UserId.Value)));
        }

        return query;
    }

    private async Task<List<AuditLogDto>> ToDtos(List<AuditLog> logs)
    {
        var userIds = logs.Where(l => l.UserId.HasValue).Select(l => l.UserId!.Value).Distinct().ToList();
        var userNames = await _db.AppUsers
            .Where(u => userIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName);

        return logs.Select(l => new AuditLogDto(
            l.Id, l.UserId, l.UserId.HasValue ? userNames.GetValueOrDefault(l.UserId.Value, "-") : "النظام",
            l.Action, l.EntityTable, l.EntityId, l.OldValues, l.NewValues, l.CreatedAt)).ToList();
    }
}
