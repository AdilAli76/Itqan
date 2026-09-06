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
    List<string> UnknownCategories,
    /// صفوف المثال التي بقيت في القالب فتُخطَّت — تُعلَن ولا تُحسَب خطأً.
    int ExampleRowsSkipped = 0);

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
        // **لا `ToDictionaryAsync` على الهاتف:** لا قيد فريد عليه في المخطّط،
        // وعميلان بهاتفٍ واحد (أخوان، أو رقم المحلّ أُدخل مرّتين) كانا يرميان
        // استثناءً **قبل قراءة صفٍّ واحد** — فيرى المستخدم «تعذّرت العملية»
        // بلا معاينة ولا سبب. والأقدم يفوز: هو الذي بُنيت عليه الحركات.
        var existingByPhone = new Dictionary<string, Customer>();
        foreach (var c in await _db.Customers
            .Where(c => !c.IsDeleted && c.Phone != null && c.Phone != "")
            .OrderBy(c => c.CreatedAt)
            .ToListAsync())
        {
            existingByPhone.TryAdd(c.Phone!, c);
        }

        // الفئة والفرع يُطابَقان بطيّ العربية لا بـ`ToLower` وحده — راجع
        // [SpreadsheetReader.Fold]. من كتب «فئه أ» أو «الفرع الرئيسى» كان
        // يُرفض صفُّه وهو يرى الاسم نفسه أمامه على الشاشة.
        var categories = new Dictionary<string, CustomerCategory>();
        foreach (var c in await _db.CustomerCategories.Where(c => c.IsActive).ToListAsync())
            categories.TryAdd(SpreadsheetReader.Fold(c.Name), c);

        var branches = new Dictionary<string, Guid>();
        foreach (var b in await _db.Branches.ToListAsync())
            branches.TryAdd(SpreadsheetReader.Fold(b.Name), b.Id);

        // أسماء العرض كما كُتبت في النظام — تُذكَر في رسالة الخطأ ليقارن
        // المستخدم بما في ملفه بدل أن يخمّن الصيغة المقبولة.
        var definedCategoryNames = categories.Values.Select(c => c.Name).OrderBy(n => n).ToList();
        var definedBranchNames = branches.Count == 0
            ? new List<string>()
            : await _db.Branches.OrderBy(b => b.Name).Select(b => b.Name).ToListAsync();

        var unknownCategories = new List<string>();
        var results = new List<CustomerImportRowResult>();
        var toCreate = new List<Customer>();
        var toUpdate = new List<Customer>();
        var seenPhones = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var exampleRowsSkipped = 0;

        for (var i = 0; i < rows.Count; i++)
        {
            var row = rows[i];
            var rowNumber = i + 2; // +1 لسطر العناوين، +1 لأن الترقيم يبدأ من 1

            var name = SpreadsheetReader.Value(row, "الاسم", "اسم العميل", "الاسم الكامل",
                "المنتسب", "اسم المنتسب", "العميل", "الزبون", "الموظف", "اسم", "الاسم الثلاثي",
                "name", "full_name", "customer", "customer_name");
            var phone = SpreadsheetReader.Value(row, "الهاتف", "رقم الهاتف", "الجوال",
                "رقم الجوال", "الموبايل", "التلفون", "هاتف", "phone", "mobile", "phone_number", "tel");
            var categoryName = SpreadsheetReader.Value(row, "الفئة", "التصنيف", "الدرجة",
                "category", "grade", "class");
            var branchName = SpreadsheetReader.Value(row, "الفرع", "branch");
            var note = SpreadsheetReader.Value(row, "ملاحظات", "ملاحظة", "البيان", "notes", "note");
            var overrideRaw = SpreadsheetReader.Value(row, "المبلغ", "مبلغ خاص", "المرتب",
                "الراتب", "الاستحقاق", "amount", "override", "salary");

            // صفّ المثال من القالب يُخطَّى قبل أي تحقّق — راجع
            // [SpreadsheetReader.IsExampleRow]. وفحصُه بعد التحقّق كان يعني
            // أن فئة المثال تُبلَّغ «غير معرَّفة» فتُوقف الملف كلّه.
            if (SpreadsheetReader.IsExampleRow(name))
            {
                exampleRowsSkipped++;
                continue;
            }

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
                if (!categories.TryGetValue(SpreadsheetReader.Fold(categoryName), out category))
                {
                    if (!unknownCategories.Contains(categoryName)) unknownCategories.Add(categoryName);
                    results.Add(new CustomerImportRowResult(
                        rowNumber, name, phone, categoryName, "خطأ",
                        $"الفئة «{categoryName}» غير معرَّفة — أنشئها بمرتَّبها أولاً"
                        + (definedCategoryNames.Count > 0
                            ? $"، أو استعمل إحدى المعرَّفة: {string.Join("، ", definedCategoryNames)}"
                            : "")));
                    continue;
                }
            }

            Guid? branchId = null;
            if (!string.IsNullOrWhiteSpace(branchName))
            {
                if (!branches.TryGetValue(SpreadsheetReader.Fold(branchName), out var found))
                {
                    results.Add(new CustomerImportRowResult(
                        rowNumber, name, phone, categoryName, "خطأ",
                        $"الفرع «{branchName}» غير موجود — الفروع المعرَّفة: {string.Join("، ", definedBranchNames)}"));
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
                // **ونموذج الحساب لا يُمسّ على القائم** — ولو أسند الملف فئة.
                // قلبُ مدفوعٍ مقدماً إلى استحقاق يُعرّض رصيده المدفوع
                // للإسقاط عند انتهاء الفترة، ومَن يريد القلب يفعله من شاشة
                // العميل حيث يرى الرصيد أمامه. (كان هنا شرطٌ يُسند القيمة
                // إلى نفسها، فالحماية المكتوبة في التعليق لم تكن مطبَّقة
                // ولا مخروقة — سطرٌ لا أثر له يوهم القارئ أن الأمر محسوم.)

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

        // **عمود الاسم غير معروف: سببٌ واحد يظهر ألف مرّة.** ملفٌ عنوانه
        // «أسماء المنتسبين» أو فيه سطر عنوانٍ فوق سطر العناوين يُقرأ كلّه
        // بلا اسم، فيخرج كل صفّ أحمرَ بـ«الاسم مطلوب» واسمٍ فارغ — ومن يرى
        // ألف خطأ متطابق لا يستنتج منها أن المشكلة في سطرٍ واحد أعلى الملف.
        // فتُقال المشكلة مرّة، وتُذكر الأعمدة التي قُرئت فعلاً ليقارنها.
        if (results.Count > 0 && results.All(r => r.Error == "الاسم مطلوب"))
        {
            var found = rows[0].Keys.Where(k => !string.IsNullOrWhiteSpace(k)).ToList();
            return BadRequest(new
            {
                message = "لم يُعرَف عمود الأسماء في الملف — سمِّه «الاسم». "
                    + (found.Count > 0
                        ? $"الأعمدة المقروءة: {string.Join(" · ", found)}."
                        : "ولم يُقرأ أي عنوان عمود — تأكّد أن السطر الأول عناوينُ لا عنوانٌ للكشف.")
                    + " والأعمدة المقبولة: الاسم · الهاتف · الفئة · الفرع · المبلغ · ملاحظات."
            });
        }

        // ملفٌ ليس فيه إلا المثال: رسالةٌ تقول ما العمل، لا معاينةٌ فارغة
        // بأصفارٍ يقف عندها المستخدم لا يدري أنجح أم فشل.
        if (results.Count == 0 && exampleRowsSkipped > 0)
            return BadRequest(new { message = "الملف لا يحوي إلا صفّ المثال — اكتب بياناتك مكانه ثم أعد الرفع" });

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
            results.Count, willCreate, willUpdate, withErrors, commit, results, unknownCategories,
            exampleRowsSkipped);
    }

    /// <summary>
    /// قالب الاستيراد — بصفِّ مثالٍ من بيانات الجهة نفسها.
    ///
    /// <para>عناوين وحدها تترك المستخدم يخمّن صيغة كل عمود، فيكتب الفئة
    /// «أ» بينما اسمها «فئة أ» ويفشل ألف صفّ دفعةً واحدة.</para>
    ///
    /// <para><b>ولماذا يُقرأ من قاعدة البيانات لا نصّاً ثابتاً:</b> كان
    /// المثال مكتوباً «فئة أ» و«الفرع الرئيسي» — أسماءٌ لا وجود لها عند
    /// أكثر الجهات. فمن ينزّل القالب ويرفعه ليجرّب يرى خطأين فوراً:
    /// «الفئة غير معرَّفة»، وهما خطأ القالب لا خطؤه — والاستيراد كلّه
    /// يتوقّف لأنه لا يقبل ملفاً فيه خطأ. الآن يحمل المثال فئةً وفرعاً
    /// موجودَين فعلاً، فيصلح نموذجاً يُنسَخ عنه.</para>
    ///
    /// <para>ويبدأ الاسم بـ«مثال:» فيُخطّيه الاستيراد صراحةً — لأن من
    /// يكتب بياناته تحت المثال ولا يحذفه كان يزرع «محمد علي» في كشف
    /// المنتسبين.</para>
    /// </summary>
    [HttpGet("template")]
    [RequirePermission("customers.manage")]
    public async Task<IActionResult> Template()
    {
        // فئتان إن وُجدتا: الأولى مثالٌ لمنتسب على فئته، والثانية لمن
        // له مبلغٌ خاص يَجُبّ الفئة. وفارغةٌ إن لم تُعرَّف فئات بعد —
        // العمود اختياري أصلاً، والفراغ أصدق من اسمٍ لا يوجد.
        var categories = await _db.CustomerCategories
            .Where(c => c.IsActive)
            .OrderBy(c => c.Name)
            .Select(c => c.Name)
            .Take(2)
            .ToListAsync();

        var branch = await _db.Branches.OrderBy(b => b.Name).Select(b => b.Name).FirstOrDefaultAsync() ?? "";

        var first = categories.ElementAtOrDefault(0) ?? "";
        var second = categories.ElementAtOrDefault(1) ?? first;

        var bytes = SpreadsheetTemplate.Build(
            sheetName: "المنتسبون",
            headers: new[] { "الاسم", "الهاتف", "الفئة", "الفرع", "المبلغ", "ملاحظات" },
            rows: new[]
            {
                new[] { SpreadsheetReader.ExamplePrefix + " محمد علي", "0910000000", first, branch, "",
                        "احذف صفوف المثال أو اتركها — تُتجاهَل" },
                new[] { SpreadsheetReader.ExamplePrefix + " فاطمة أحمد", "0920000000", second, branch, "250",
                        "مبلغ خاص يَجُبّ الفئة" },
            },
            // الهاتف نصٌّ لا رقم — راجع [SpreadsheetTemplate].
            textColumns: new[] { 1 });

        return File(bytes, SpreadsheetTemplate.ContentType, "قالب-استيراد-العملاء.xlsx");
    }

    /// <summary>
    /// تهريب خلية CSV — الاسم يأتي من قاعدة البيانات لا من ثابتٍ عندنا،
    /// وفئةٌ اسمها «فئة أ، ب» كانت تكسر أعمدة القالب صامتةً.
    /// </summary>
    static string Csv(string value) =>
        value.Contains(',') || value.Contains('"') || value.Contains('\n')
            ? '"' + value.Replace("\"", "\"\"") + '"'
            : value;

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
