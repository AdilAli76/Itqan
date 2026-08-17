using System.Text.Json;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// نقطة واحدة يستدعيها أي Controller لتسجيل عملية حساسة (حذف، تعديل يدوي
/// على رصيد/مخزون، استرجاع فاتورة) — راجع ARCHITECTURE.md §2.11. الصف
/// يُضاف إلى الـ DbContext فقط؛ الاستدعاء يبقى مسؤولاً عن SaveChangesAsync
/// (عادة ضمن نفس Transaction للعملية الأصلية) حتى لا يُسجَّل حدث تدقيق
/// لعملية فشلت فعلياً.
/// </summary>
public static class AuditLogExtensions
{
    public static void LogAudit(
        this AppDbContext db,
        Guid organizationId,
        Guid? userId,
        string action,
        string entityTable,
        Guid? entityId,
        object? oldValues = null,
        object? newValues = null)
    {
        db.AuditLogs.Add(new AuditLog
        {
            OrganizationId = organizationId,
            UserId = userId,
            Action = action,
            EntityTable = entityTable,
            EntityId = entityId,
            OldValues = oldValues is null ? null : JsonSerializer.Serialize(oldValues),
            NewValues = newValues is null ? null : JsonSerializer.Serialize(newValues),
        });
    }
}
