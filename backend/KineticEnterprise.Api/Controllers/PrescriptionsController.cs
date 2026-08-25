using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

public record PrescriptionListItemDto(
    Guid Id, string? PrescriptionNumber, string DoctorName, string? DoctorLicense,
    string PatientName, string? PatientPhone, DateOnly? IssuedOn, string? Notes,
    Guid? InvoiceId, string? InvoiceNumber, string? DispensedBy, DateTime CreatedAt);

public record PrescriptionPageDto(List<PrescriptionListItemDto> Items, int TotalCount, int Page, int PageSize);

/// <summary>
/// دفتر الوصفات — قراءة فقط.
///
/// <para><b>لا إنشاء ولا تعديل ولا حذف عمداً.</b> القيد يُكتب لحظة الصرف مع
/// الفاتورة داخل معاملة واحدة (راجع InvoicesController.Create)، وفتح باب
/// كتابة مستقل كان ينتج دفتراً يمكن ملؤه بقيود لا يقابلها صرف — أي مستنداً
/// لا يُوثَق به. والتعديل بعد الصرف يُفرغ الدفتر من معناه الرقابي: قيمته في
/// أنه أثرٌ لا يُمسّ.</para>
///
/// <para>تصحيح قيد خاطئ يمرّ باسترجاع الفاتورة، فيبقى الخطأ وتصحيحه ظاهرين
/// معاً في السجل.</para>
/// </summary>
[ApiController]
[Route("api/prescriptions")]
[Authorize]
[RequireModule("pharmacy")]
public class PrescriptionsController : ControllerBase
{
    private readonly AppDbContext _db;
    public PrescriptionsController(AppDbContext db) => _db = db;

    /// <summary>
    /// بحث بالمريض أو الطبيب أو رقم الوصفة، مع مدى زمني.
    ///
    /// المدى الزمني أساسي لا ترف: الدفتر يُراجَع شهرياً أو عند تفتيش، والسؤال
    /// دائماً «ماذا صُرف بين تاريخين».
    /// </summary>
    [HttpGet]
    [RequirePermission("prescriptions.dispense")]
    public async Task<ActionResult<PrescriptionPageDto>> GetAll(
        [FromQuery] string? search,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        var query = _db.Prescriptions.AsQueryable();

        if (from.HasValue) query = query.Where(p => p.CreatedAt >= from.Value);
        if (to.HasValue) query = query.Where(p => p.CreatedAt < to.Value.AddDays(1));
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(p =>
                p.PatientName.Contains(search) ||
                p.DoctorName.Contains(search) ||
                (p.PrescriptionNumber != null && p.PrescriptionNumber.Contains(search)));
        }

        var totalCount = await query.CountAsync();
        var rows = await query
            .OrderByDescending(p => p.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        // أسماء الفواتير والصارفين تُجلَب دفعةً واحدة لا صفاً صفاً — الدفتر
        // يُعرض خمسين قيداً في الصفحة، واستعلامٌ لكل قيد يعني مئة استعلام.
        var invoiceIds = rows.Where(r => r.InvoiceId.HasValue).Select(r => r.InvoiceId!.Value).Distinct().ToList();
        var invoiceNumbers = await _db.Invoices
            .Where(i => invoiceIds.Contains(i.Id))
            .ToDictionaryAsync(i => i.Id, i => i.InvoiceNumber);

        var userIds = rows.Where(r => r.CreatedBy.HasValue).Select(r => r.CreatedBy!.Value).Distinct().ToList();
        var userNames = await _db.AppUsers
            .Where(u => userIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName);

        var items = rows.Select(p =>
        {
            invoiceNumbers.TryGetValue(p.InvoiceId ?? Guid.Empty, out var invoiceNumber);
            userNames.TryGetValue(p.CreatedBy ?? Guid.Empty, out var dispensedBy);
            return new PrescriptionListItemDto(
                p.Id, p.PrescriptionNumber, p.DoctorName, p.DoctorLicense,
                p.PatientName, p.PatientPhone, p.IssuedOn, p.Notes,
                p.InvoiceId, invoiceNumber, dispensedBy, p.CreatedAt);
        }).ToList();

        return new PrescriptionPageDto(items, totalCount, page, pageSize);
    }
}
