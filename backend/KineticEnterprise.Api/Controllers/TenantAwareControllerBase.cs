using System;
using System.Collections.Generic;
using System.Security.Claims;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;
using KineticEnterprise.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace KineticEnterprise.Api.Controllers;

/// <summary>
/// Base Controller يضمن أن جميع العمليات محدودة إلى المؤسسة الحالية
/// ⚠️ جميع Controllers يجب أن ترث من هذا الـ class
/// </summary>
[ApiController]
[Authorize]
public abstract class TenantAwareControllerBase : ControllerBase
{
    protected readonly ITenantService TenantService;
    protected readonly ILogger Logger;

    protected TenantAwareControllerBase(
        ITenantService tenantService,
        ILogger logger)
    {
        TenantService = tenantService;
        Logger = logger;
    }

    /// <summary>
    /// الحصول على معرف المؤسسة الحالية
    /// يجب استخدام هذا في جميع الـ queries
    /// </summary>
    protected string CurrentTenantId => TenantService.GetCurrentTenant().TenantId;

    /// <summary>
    /// الحصول على معرف المستخدم الحالي
    /// </summary>
    protected string CurrentUserId => User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? throw new UnauthorizedAccessException("لم يتم العثور على معرف المستخدم");

    /// <summary>
    /// الحصول على جميع معلومات المؤسسة الحالية
    /// </summary>
    protected TenantContext CurrentTenant => TenantService.GetCurrentTenant();

    /// <summary>
    /// التحقق من أن المستخدم له صلاحية معينة
    /// </summary>
    protected bool HasPermission(string permission)
    {
        return CurrentTenant.Permissions.Contains(permission);
    }

    /// <summary>
    /// التحقق من أن المؤسسة لديها وحدة معينة مفعلة
    /// </summary>
    protected bool HasModule(string moduleName)
    {
        return CurrentTenant.EnabledModules.Contains(moduleName);
    }

    /// <summary>
    /// استجابة خطأ مخصصة
    /// </summary>
    protected IActionResult TenantError(string message, int statusCode = 400)
    {
        Logger.LogWarning($"[{CurrentTenantId}] {message}");
        return StatusCode(statusCode, new { error = message });
    }

    /// <summary>
    /// استجابة نجاح مخصصة
    /// </summary>
    protected IActionResult TenantSuccess<T>(T data, string message = "تم بنجاح", int statusCode = 200)
    {
        Logger.LogInformation($"[{CurrentTenantId}] {message}");
        return StatusCode(statusCode, new { data, message });
    }
}

// ملاحظة: أمثلة Controllers ستُطبق بعد تحديث Customer Model
// مع إضافة TenantId و Tracking Fields من خلال Migration
