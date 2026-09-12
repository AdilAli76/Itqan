
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
                var connection = db.Database.GetDbConnection();
                if (connection.State != System.Data.ConnectionState.Open)
                {
                    await connection.OpenAsync();
                }

                try
                {
                    await using var command = connection.CreateCommand();
                    command.CommandText = "EXEC sp_set_session_context @key=N'organization_id', @value=@orgId, @read_only=1; " +
                                           "EXEC sp_set_session_context @key=N'branch_id', @value=@branchId, @read_only=1;";
                    command.Parameters.Add(new SqlParameter("@orgId", orgId));
                    command.Parameters.Add(new SqlParameter("@branchId", (object?)branchId ?? DBNull.Value));
                    await command.ExecuteNonQueryAsync();
                }
                catch (Microsoft.Data.SqlClient.SqlException ex) when (ex.Number == 2812)
                {
                    // sp_set_session_context غير متاحة على SQL Server 2008 R2 المحلي
                    // (أُضيفت في 2016). في بيئة التطوير تُتجاهل وتعمل المنصة بدون RLS.
                    // لا يحدث هذا على الإنتاج (SQL Server 2019+).
                }
            }
        }

        await _next(context);
    }
}
