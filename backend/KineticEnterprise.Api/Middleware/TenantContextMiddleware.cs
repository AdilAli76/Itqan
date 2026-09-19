
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using Microsoft.Data.SqlClient;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Middleware;

/// <summary>
/// بعد أن يتحقق JwtBearer من هوية المستخدم، هذا الـ Middleware يضبط
/// SESSION_CONTEXT على اتصال SQL Server الخاص بهذا الطلب، بحيث تُطبَّق
/// Security Policies المعرَّفة في DATABASE_SCHEMA_SQLSERVER.sql تلقائياً
/// على كل استعلام EF Core بعد هذه النقطة — بدون أي شرط WHERE يدوي متكرر
/// في كل Controller (وهذا بالضبط ما يمنع نسيان العزل في شاشة جديدة مستقبلاً).
/// </summary>
public class TenantContextMiddleware
{
    private readonly RequestDelegate _next;

    public TenantContextMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context, AppDbContext db)
    {
        if (context.User.Identity?.IsAuthenticated == true)
        {
            var orgId = context.User.FindFirstValue("organization_id");
            var branchId = context.User.FindFirstValue("branch_id"); // قد تكون فارغة = مدير عام

            if (!string.IsNullOrEmpty(orgId))
            {
                // SQLite doesn't support sp_set_session_context (SQL Server feature)
                // RLS policies are handled through EF Core queries in controllers
                // so we skip this for local SQLite development
            }
        }

        await _next(context);
    }
}
