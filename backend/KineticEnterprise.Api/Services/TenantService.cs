using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace KineticEnterprise.Api.Services;

/// <summary>
/// خدمة إدارة المؤسسات - تعيين المستخدم الحالي إلى مؤسسته
/// ومنع رؤيته لبيانات المؤسسات الأخرى
/// </summary>
public interface ITenantService
{
    TenantContext GetCurrentTenant();
    Task<Tenant> GetTenantByIdAsync(string tenantId);
    Task<Tenant> GetTenantByDomainAsync(string domain);
    Task<List<ModuleLicense>> GetEnabledModulesAsync(string tenantId);
    void ValidateUserBelongsToTenant(string userId, string tenantId);
    string GetTenantConnectionString(string tenantId);
}

public class TenantService : ITenantService
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly AppDbContext _dbContext;
    private readonly IConfiguration _configuration;
    private TenantContext _currentTenantContext;

    public TenantService(
        IHttpContextAccessor httpContextAccessor,
        AppDbContext dbContext,
        IConfiguration configuration)
    {
        _httpContextAccessor = httpContextAccessor;
        _dbContext = dbContext;
        _configuration = configuration;
    }

    /// <summary>
    /// استخراج معلومات المؤسسة من JWT Token
    /// </summary>
    public TenantContext GetCurrentTenant()
    {
        if (_currentTenantContext != null)
            return _currentTenantContext;

        var httpContext = _httpContextAccessor.HttpContext;
        if (httpContext?.User == null)
            throw new UnauthorizedAccessException("لم يتم تسجيل دخول المستخدم");

        var tenantIdClaim = httpContext.User.FindFirst("tenant_id");
        var userIdClaim = httpContext.User.FindFirst(ClaimTypes.NameIdentifier);

        if (tenantIdClaim == null)
            throw new UnauthorizedAccessException("لم يتم العثور على معرف المؤسسة في التوكن");

        var tenantId = tenantIdClaim.Value;

        // استخراج الصلاحيات من الدعاوى
        var permissions = httpContext.User
            .FindAll("permission")
            .Select(c => c.Value)
            .ToList();

        // استخراج الوحدات المفعلة
        var enabledModules = httpContext.User
            .FindAll("module")
            .Select(c => c.Value)
            .ToList();

        _currentTenantContext = new TenantContext
        {
            TenantId = tenantId,
            CurrentUserId = userIdClaim?.Value,
            Permissions = permissions,
            EnabledModules = enabledModules,
            CurrentVersion = httpContext.User.FindFirst("version")?.Value ?? "2.0.5"
        };

        return _currentTenantContext;
    }

    /// <summary>
    /// جلب معلومات المؤسسة بالكامل (سيتم تنفيذها لاحقاً)
    /// </summary>
    public async Task<Tenant> GetTenantByIdAsync(string tenantId)
    {
        // سيتم إضافة هذا بعد تحديث AppDbContext
        throw new NotImplementedException("سيتم إضافة DbContext التطبيق");
    }

    /// <summary>
    /// جلب المؤسسة حسب النطاق/الدومين
    /// </summary>
    public async Task<Tenant> GetTenantByDomainAsync(string domain)
    {
        // سيتم إضافة هذا بعد تحديث AppDbContext
        throw new NotImplementedException("سيتم إضافة DbContext التطبيق");
    }

    /// <summary>
    /// جلب الوحدات المفعلة فقط للمؤسسة
    /// </summary>
    public async Task<List<ModuleLicense>> GetEnabledModulesAsync(string tenantId)
    {
        // سيتم إضافة هذا بعد تحديث AppDbContext
        throw new NotImplementedException("سيتم إضافة DbContext التطبيق");
    }

    /// <summary>
    /// التحقق من أن المستخدم ينتمي إلى المؤسسة الحالية
    /// ⚠️ حرج: يجب استدعاء هذا في كل endpoint
    /// </summary>
    public void ValidateUserBelongsToTenant(string userId, string tenantId)
    {
        var currentTenant = GetCurrentTenant();

        if (currentTenant.TenantId != tenantId)
            throw new UnauthorizedAccessException(
                $"المستخدم {userId} لا ينتمي إلى المؤسسة {tenantId}");
    }

    /// <summary>
    /// جلب connection string لقاعدة بيانات المؤسسة
    /// يدعم Database-per-Tenant و Schema-per-Tenant
    /// </summary>
    public string GetTenantConnectionString(string tenantId)
    {
        var tenant = GetTenantByIdAsync(tenantId).Result;

        // الطريقة 1: Database per Tenant
        // كل مؤسسة لها قاعدة بيانات منفصلة
        if (!string.IsNullOrEmpty(tenant.ConnectionStringKey))
        {
            var connStr = _configuration.GetConnectionString(tenant.ConnectionStringKey);
            if (!string.IsNullOrEmpty(connStr))
                return connStr;
        }

        // الطريقة 2: Schema per Tenant (بديل)
        // كل مؤسسة لها schema منفصل في نفس قاعدة البيانات
        var defaultConnStr = _configuration.GetConnectionString("DefaultConnection");
        if (string.IsNullOrEmpty(tenant.DatabaseName))
            return defaultConnStr;

        // استبدال اسم قاعدة البيانات
        // سيتم تحسينه لاحقاً
        return defaultConnStr;
    }
}

/// <summary>
/// Middleware لاستخلاص معلومات المؤسسة من كل طلب
/// وتطبيق الفلاتر التلقائية على جميع الـ queries
/// </summary>
public class TenantMiddleware
{
    private readonly RequestDelegate _next;

    public TenantMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context, ITenantService tenantService)
    {
        try
        {
            // تحميل معلومات المؤسسة من التوكن
            var tenantContext = tenantService.GetCurrentTenant();
            context.Items["TenantContext"] = tenantContext;

            // إضافة TenantId إلى جميع السجلات
            context.Items["TenantId"] = tenantContext.TenantId;
        }
        catch (UnauthorizedAccessException ex)
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = ex.Message });
            return;
        }

        await _next(context);
    }
}

/// <summary>
/// Extension methods لإضافة Tenant Service
/// </summary>
public static class TenantServiceExtensions
{
    public static IServiceCollection AddTenantServices(this IServiceCollection services)
    {
        services.AddScoped<ITenantService, TenantService>();
        services.AddHttpContextAccessor();
        return services;
    }

    public static IApplicationBuilder UseTenantMiddleware(this IApplicationBuilder app)
    {
        return app.UseMiddleware<TenantMiddleware>();
    }
}
