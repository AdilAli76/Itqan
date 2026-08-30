using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CustomerImportRowResult(
    int Row, string Name, string? Phone, string? Category, string Action, string? Error);

public record CustomerImportSummary(
    int TotalRows, int WillCreate, int WillUpdate, int WithErrors, bool Committed,
    List<CustomerImportRowResult> Rows,
    /// فئاتٌ ذُكرت في الملف ولا وجود لها — تُعرَض قبل التأكيد.
    List<string> UnknownCategories);

/// <summary>
/// استيراد العملاء من ملف إكسل أو CSV.
///
/// <para><b>سبب وجوده:</b> جهةٌ تصرف على ألف منتسب لا تُدخلهم واحداً واحداً.
/// وإدخال ألف اسمٍ بأربعة حقول يدوياً أربعة آلاف إدخال — وهو وحده كان يمنع
/// تسليم النظام لجهةٍ عندها كشفُ منتسبين قائم.</para>
///
/// <para><b>ومرحلتان إلزاميتان</b> كما في استيراد الأصناف: معاينةٌ تقرأ
/// وتتحقّق وتُعيد التقرير **بلا كتابة**، ثم تنفيذ. وملفٌ فيه عمود هاتفٍ
/// مكان عمود الاسم يزرع ألف عميل بأسماء أرقام — واكتشافه بعد الكتابة يعني
/// استرجاع نسخة احتياطية.</para>
///
/// <para><b>ولا يُنشئ فئةً لم تُعرَّف</b> — بخلاف استيراد الأصناف الذي
/// يُنشئ تصنيفات وموردين. الفئة هنا تحمل **مرتَّباً**، وإنشاؤها ضمناً
/// بصفر يُنتج منتسبين لا يقبضون شيئاً ولا يعرف أحدٌ لماذا. فتُذكَر الفئة
/// المجهولة في التقرير ويُرفض صفُّها.</para>
/// </summary>
[ApiController]
[Route("api/customers/import")]
[Authorize]
public class CustomerImportController : ControllerBase
{
    private readonly AppDbContext _db;
    public CustomerImportController(AppDbContext db) => _db = db;

    const long MaxFileBytes = 5 * 1024 * 1024;

    [HttpPost]
    [RequirePermission("customers.manage")]
    [RequestSizeLimit(MaxFileBytes)]
    public async Task<ActionResult<CustomerImportSummary>> Import(
        IFormFile file,
        [FromQuery] bool dryRun = true)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { message = "لم يُرفَق ملف" });
        if (file.Length > MaxFileBytes)
            return BadRequest(new { message = "حجم الملف يتجاوز 5 ميغابايت" });

        List<Dictionary<string, string>> rows;
        try
        {
            await using var stream = file.OpenReadStream();
            rows = SpreadsheetReader.Read(stream, file.FileName);
        }
        catch (NotSupportedException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception)
        {
            return BadRequest(new { message = "تعذّرت قراءة الملف — تأكد أنه ‎.xlsx أو ‎.csv سليم" });
        }

        if (rows.Count == 0)
            return BadRequest(new { message = "الملف فارغ أو لا يحوي سطر عناوين وصفوف بيانات" });

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);

        // القوائم الحالية مرّةً واحدة — ملفٌ بألف صفّ كان سيُنتج ألفَي استعلام.
        var existingByPhone = await _db.Customers
            .Where(c => !c.IsDeleted && c.Phone != null && c.Phone != "")
            .ToDictionaryAsync(c => c.Phone!, c => c);

        var categories = await _db.CustomerCategories
            .Where(c => c.IsActive)
            .ToDictionaryAsync(c => c.Name.Trim().ToLower(), c => c);

        var branches = await _db.Branches
            .ToDictionaryAsync(b => b.Name.Trim().ToLower(), b => b.Id);

        var unknownCategories = new List<string>();
        var results = new List<CustomerImportRowResult>();
        var toCreate = new List<Customer>();
        var toUpdate = new List<Customer>();
        var seenPhones = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < rows.Count; i++)
        {
            var row = rows[i];
            var rowNumber = i + 2; // +1 لسطر العناوين، +1 لأن الترقيم يبدأ من 1

            var name = SpreadsheetReader.Value(row, "الاسم", "اسم العميل", "الاسم الكامل", "المنتسب", "name", "full_name");
            var phone = SpreadsheetReader.Value(row, "الهاتف", "رقم الهاتف", "الجوال", "phone", "mobile");
            var categoryName = SpreadsheetReader.Value(row, "الفئة", "التصنيف", "category", "grade");
            var branchName = SpreadsheetReader.Value(row, "الفرع", "branch");
            var note = SpreadsheetReader.Value(row, "ملاحظات", "ملاحظة", "notes", "note");
            var overrideRaw = SpreadsheetReader.Value(row, "المبلغ", "مبلغ خاص", "المرتب", "amount", "override");

            if (string.IsNullOrWhiteSpace(name))
            {
                results.Add(new CustomerImportRowResult(rowNumber, "", phone, categoryName, "خطأ", "الاسم مطلوب"));
                continue;
            }

            // الهاتف مفتاح المطابقة — وتكراره داخل الملف نفسه يجعل الصفّ
            // الثاني يمحو الأوّل بلا أن يلاحظ أحد.
            if (!string.IsNullOrWhiteSpace(phone) && !seenPhones.Add(phone))
            {
                results.Add(new CustomerImportRowResult(
                    rowNumber, name, phone, categoryName, "خطأ", $"الهاتف {phone} مكرَّر في الملف"));
                continue;
            }

            CustomerCategory? category = null;
            if (!string.IsNullOrWhiteSpace(categoryName))
            {
                if (!categories.TryGetValue(categoryName.Trim().ToLower(), out category))
                {
                    if (!unknownCategories.Contains(categoryName)) unknownCategories.Add(categoryName);
                    results.Add(new CustomerImportRowResult(
                        rowNumber, name, phone, categoryName, "خطأ",
                        $"الفئة «{categoryName}» غير معرَّفة — أنشئها بمرتَّبها أولاً"));
                    continue;
                }
            }

            Guid? branchId = null;
            if (!string.IsNullOrWhiteSpace(branchName))
            {
                if (!branches.TryGetValue(branchName.Trim().ToLower(), out var found))
                {
                    results.Add(new CustomerImportRowResult(
                        rowNumber, name, phone, categoryName, "خطأ", $"الفرع «{branchName}» غير موجود"));
                    continue;
                }
                branchId = found;
            }

            decimal? entitlementOverride = null;
            if (!string.IsNullOrWhiteSpace(overrideRaw))
            {
                var parsed = SpreadsheetReader.Number(overrideRaw);
                if (parsed is null || parsed < 0)
                {
                    results.Add(new CustomerImportRowResult(
                        rowNumber, name, phone, categoryName, "خطأ", $"مبلغ غير صالح: {overrideRaw}"));
                    continue;
                }
                entitlementOverride = parsed;
            }

            var isEntitlement = category is not null;

            if (!string.IsNullOrWhiteSpace(phone) && existingByPhone.TryGetValue(phone, out var existing))
            {
                existing.FullName = name;
                existing.CategoryId = category?.Id ?? existing.CategoryId;
                existing.BranchId = branchId ?? existing.BranchId;
                if (entitlementOverride is not null) existing.EntitlementOverride = entitlementOverride;
                if (!string.IsNullOrWhiteSpace(note)) existing.Notes = note;
                // نموذج الحساب لا يُقلَب على من له رصيدٌ مدفوع: قلبُه إلى
                // استحقاق يُعرّض رصيده للإسقاط عند انتهاء الفترة.
                if (isEntitlement && existing.AccountModel == AccountModels.Entitlement)
                {
                    existing.AccountModel = AccountModels.Entitlement;
                }

                toUpdate.Add(existing);
                results.Add(new CustomerImportRowResult(rowNumber, name, phone, categoryName, "تحديث", null));
            }
            else
            {
                toCreate.Add(new Customer
                {
                    OrganizationId = orgId,
                    FullName = name,
                    Phone = string.IsNullOrWhiteSpace(phone) ? null : phone,
                    Notes = string.IsNullOrWhiteSpace(note) ? null : note,
                    BranchId = branchId,
                    CategoryId = category?.Id,
                    EntitlementOverride = entitlementOverride,
                    AccountModel = isEntitlement ? AccountModels.Entitlement : AccountModels.Prepaid,
                });
                results.Add(new CustomerImportRowResult(rowNumber, name, phone, categoryName, "إنشاء", null));
            }
        }

        var withErrors = results.Count(r => r.Error is not null);
        var willCreate = results.Count(r => r.Action == "إنشاء");
        var willUpdate = results.Count(r => r.Action == "تحديث");

        // لا يُكتب شيء ما دام في الملف خطأ — ولو صفٌّ واحد. استيرادٌ جزئي
        // يترك المستخدم لا يعرف من دخل ومن لم يدخل، فيُعيد الملف كلّه
        // فيتضاعف من دخل.
        var commit = !dryRun && withErrors == 0;
        if (commit)
        {
            _db.Customers.AddRange(toCreate);
            _db.LogAudit(orgId, CurrentUserId(), "customers.imported", "customers", null,
                newValues: new { Created = willCreate, Updated = willUpdate, File = file.FileName });
            await _db.SaveChangesAsync();
        }

        return new CustomerImportSummary(
            results.Count, willCreate, willUpdate, withErrors, commit, results, unknownCategories);
    }

    /// <summary>
    /// قالب الاستيراد — بصفٍّ مثال لا بعناوين فارغة.
    ///
    /// <para>عناوين وحدها تترك المستخدم يخمّن صيغة كل عمود، فيكتب الفئة
    /// «أ» بينما اسمها «فئة أ» ويفشل ألف صفّ دفعةً واحدة.</para>
    /// </summary>
    [HttpGet("template")]
    [RequirePermission("customers.manage")]
    public IActionResult Template()
    {
        var csv = "الاسم,الهاتف,الفئة,الفرع,المبلغ,ملاحظات\n"
                + "محمد علي,0910000000,فئة أ,الفرع الرئيسي,,\n"
                + "فاطمة أحمد,0920000000,فئة ب,الفرع الرئيسي,250,مبلغ خاص يَجُبّ الفئة\n";

        // BOM إلزامي: إكسل يقرأ CSV بلا علامة ترتيب بايتات بترميز النظام
        // فتظهر العربية طلاسم — وهو أوّل ما يشتكي منه من يفتح القالب.
        var bytes = new byte[] { 0xEF, 0xBB, 0xBF }
            .Concat(System.Text.Encoding.UTF8.GetBytes(csv)).ToArray();
        return File(bytes, "text/csv", "قالب-استيراد-العملاء.csv");
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
