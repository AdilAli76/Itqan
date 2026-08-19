using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record AttachmentDto(
    Guid Id, string FileName, string ContentType, long SizeBytes, DateTime CreatedAt, string Url);

/// <summary>
/// رفع الملفات وتنزيلها — شعار المنظمة وصور فواتير الموردين.
///
/// الملفات تُخدَم عبر وحدة تحكّم لا كملفات ثابتة، وهذا مقصود: فاتورة مورّد
/// تكشف أسعار الشراء، وهي أكثر ما يهمّ منافساً. لو خُدمت من مجلد ثابت لكان
/// من يعرف الرابط — أو يخمّنه — يقرؤها بلا توكن ومن أي منظمة. المرور عبر
/// المتحكّم يجعل كل تنزيل يمرّ بالمصادقة وبسياسة العزل على القاعدة.
///
/// والتخزين خارج مجلد النشر (Storage:Path): كل ترقية تستبدل مجلد backend
/// كاملاً، فملف مرفوع بداخله يُمحى مع أول تحديث.
/// </summary>
[ApiController]
[Route("api/files")]
[Authorize]
public class FilesController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly string _root;

    // أنواع مسموحة بالقائمة البيضاء لا بالسوداء: الغرض صور ومستندات، وأي
    // امتداد آخر على قرص خادم ويب مخاطرة بلا فائدة.
    private static readonly Dictionary<string, string> Allowed = new(StringComparer.OrdinalIgnoreCase)
    {
        [".png"] = "image/png",
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".webp"] = "image/webp",
        [".pdf"] = "application/pdf",
    };

    private const long MaxBytes = 8 * 1024 * 1024;

    public FilesController(AppDbContext db, IConfiguration config, IWebHostEnvironment env)
    {
        _db = db;
        // الافتراضي بجانب مجلد النشر لا بداخله — راجع تعليق الصنف.
        var configured = config["Storage:Path"];
        _root = string.IsNullOrWhiteSpace(configured)
            ? Path.Combine(Directory.GetParent(env.ContentRootPath)?.FullName ?? env.ContentRootPath, "uploads")
            : configured;
        Directory.CreateDirectory(_root);
    }

    private Guid OrgId() => Guid.Parse(User.FindFirstValue("organization_id")!);
    private Guid? CurrentUserId() =>
        Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub"), out var id)
            ? id : null;

    [HttpGet]
    public async Task<ActionResult<List<AttachmentDto>>> List(
        [FromQuery] string entityType, [FromQuery] Guid? entityId)
    {
        var rows = await _db.Attachments
            .Where(a => a.EntityType == entityType && (entityId == null || a.EntityId == entityId))
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();
        return rows.Select(ToDto).ToList();
    }

    [HttpPost]
    [RequirePermission("inventory.manage")]
    public async Task<ActionResult<AttachmentDto>> Upload(
        IFormFile file, [FromQuery] string entityType, [FromQuery] Guid? entityId)
    {
        if (file is null || file.Length == 0) return BadRequest(new { message = "لا ملف مرفوع" });
        if (file.Length > MaxBytes)
            return BadRequest(new { message = $"حجم الملف يتجاوز {MaxBytes / (1024 * 1024)} ميغابايت" });

        var ext = Path.GetExtension(file.FileName);
        if (!Allowed.TryGetValue(ext, out var contentType))
            return BadRequest(new { message = "نوع الملف غير مسموح — الصور وملفات PDF فقط" });

        // الاسم على القرص يُولَّد ولا يُشتقّ من اسم المستخدم للملف: اسم مثل
        // ‎..\..\web.config يكتب خارج المجلد، وهي أقدم ثغرة رفع ملفات.
        var storedName = $"{Guid.NewGuid():N}{ext.ToLowerInvariant()}";
        var fullPath = Path.Combine(_root, storedName);
        await using (var stream = System.IO.File.Create(fullPath))
        {
            await file.CopyToAsync(stream);
        }

        var row = new Attachment
        {
            OrganizationId = OrgId(),
            EntityType = entityType,
            EntityId = entityId,
            FileName = Path.GetFileName(file.FileName),
            ContentType = contentType,
            SizeBytes = file.Length,
            StoredName = storedName,
            UploadedBy = CurrentUserId(),
        };
        _db.Attachments.Add(row);
        _db.LogAudit(row.OrganizationId, CurrentUserId(), "attachment.uploaded", "attachments", row.Id,
            newValues: new { row.EntityType, row.EntityId, row.FileName, row.SizeBytes });
        await _db.SaveChangesAsync();

        return ToDto(row);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Download(Guid id)
    {
        // سياسة العزل على القاعدة تُخفي مرفقات المنظمات الأخرى، فالبحث
        // بالمعرّف وحده كافٍ ولا يحتاج شرط منظمة في الكود.
        var row = await _db.Attachments.FirstOrDefaultAsync(a => a.Id == id);
        if (row is null) return NotFound();

        var path = Path.Combine(_root, row.StoredName);
        if (!System.IO.File.Exists(path))
            return NotFound(new { message = "الملف مفقود من مجلد التخزين" });

        return PhysicalFile(path, row.ContentType, row.FileName);
    }

    [HttpDelete("{id:guid}")]
    [RequirePermission("inventory.manage")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var row = await _db.Attachments.FirstOrDefaultAsync(a => a.Id == id);
        if (row is null) return NotFound();

        var path = Path.Combine(_root, row.StoredName);
        // الصف يُحذف حتى لو غاب الملف: صف يشير إلى ملف غير موجود لا فائدة
        // منه، وبقاؤه يجعل القائمة تعرض مرفقاً لا يُفتح.
        if (System.IO.File.Exists(path))
        {
            try { System.IO.File.Delete(path); } catch (IOException) { /* مقفول — يُنظَّف لاحقاً */ }
        }

        _db.Attachments.Remove(row);
        _db.LogAudit(row.OrganizationId, CurrentUserId(), "attachment.deleted", "attachments", row.Id,
            oldValues: new { row.EntityType, row.EntityId, row.FileName });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private static AttachmentDto ToDto(Attachment a) =>
        new(a.Id, a.FileName, a.ContentType, a.SizeBytes, a.CreatedAt, $"/api/files/{a.Id}");
}
