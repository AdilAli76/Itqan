using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record PlatformSettingsDto(string CompanyName, string OwnerName, string? Phone, string? Whatsapp, string? Email, string? Address);

/// <summary>
/// بيانات تواصل مالك المنصة — القراءة مفتوحة لأي مستخدم مسجَّل دخول في أي
/// منظمة (كل عميل يحتاجها كجهة دعم فني)، والتعديل مقصور على مالك المنصة
/// فقط عبر is_platform_admin (نفس بوابة PlatformController).
/// </summary>
[ApiController]
[Route("api/platform-settings")]
[Authorize]
public class PlatformSettingsController : ControllerBase
{
    private readonly AppDbContext _db;
    public PlatformSettingsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<PlatformSettingsDto>> Get()
    {
        var settings = await _db.PlatformSettings.FirstOrDefaultAsync();
        if (settings is null)
        {
            return new PlatformSettingsDto("", "", null, null, null, null);
        }
        return new PlatformSettingsDto(settings.CompanyName, settings.OwnerName, settings.Phone, settings.Whatsapp, settings.Email, settings.Address);
    }

    [HttpPut]
    public async Task<IActionResult> Update(PlatformSettingsDto request)
    {
        if (User.FindFirstValue("is_platform_admin") != "True")
        {
            return Forbid();
        }

        var settings = await _db.PlatformSettings.FirstOrDefaultAsync();
        if (settings is null)
        {
            settings = new PlatformSettings();
            _db.PlatformSettings.Add(settings);
        }

        settings.CompanyName = request.CompanyName;
        settings.OwnerName = request.OwnerName;
        settings.Phone = request.Phone;
        settings.Whatsapp = request.Whatsapp;
        settings.Email = request.Email;
        settings.Address = request.Address;
        settings.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return NoContent();
    }
}
