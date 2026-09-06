using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record AccountImportRowResult(
    int Row, string Code, string Name, string Action, string? Error);

public record AccountImportSummary(
    int TotalRows, int WillCreate, int WillUpdate, int WithErrors, bool Committed,
    List<AccountImportRowResult> Rows, int ExampleRowsSkipped = 0);

/// <summary>
/// استيراد دليل الحسابات وتصديره — أي دليل، لأي بلد.
///
/// <para><b>سبب وجوده:</b> الدليل المبذور واحدٌ مختصر على الدليل الموحّد.
/// وكل بلدٍ دليلُه: الفرنسي بأصنافه السبعة، والسعودي، والليبي، وكل مكتب
/// محاسبة له شجرته التي اعتادها. وإضافةُ قالبِ بلدٍ في الكود تعني أن كل
/// عميلٍ جديد ينتظر إصداراً جديداً ليعمل بدليله — وهو ما يجعل النظام
/// «نظامنا» لا «نظامه».</para>
///
/// <para>فالدليل يدخل من ملف: عمودان إلزاميان (الرمز والاسم) وثالثٌ
/// للنوع، ورابعٌ اختياري لرمز الأب. ومكتب المحاسبة يُخرج دليله من نظامه
/// القديم ويُدخله هنا في دقيقة.</para>
///
/// <para><b>ولا يحذف شيئاً أبداً:</b> ملفٌ ناقصٌ سطراً لا يعني «احذف هذا
/// الحساب» — قد يكون المحاسب أرسل جزءاً من دليله. والحذف قرارٌ يُتخذ
/// بحسابٍ واحد أمام عينه، لا بملفٍ يُرفع.</para>
/// </summary>
[ApiController]
[Route("api/accounting/accounts")]
[Authorize(Roles = "super_admin")]
[RequireModule("accounting")]
public class AccountsImportController : ControllerBase
{
    private readonly AppDbContext _db;
    public AccountsImportController(AppDbContext db) => _db = db;

    const long MaxFileBytes = 2 * 1024 * 1024;

    /// <summary>
    /// أسماء الأنواع كما يكتبها محاسب — عربيّها وإنجليزيّها.
    ///
    /// <para>«التزامات» و«خصوم» و«مطلوبات» ثلاثةُ أسماء لشيءٍ واحد، ورفضُ
    /// اثنين منها يجعل المستخدم يصحّح ملفاً كاملاً بلا سبب يفهمه.</para>
    /// </summary>
    static readonly Dictionary<string, string> TypeAliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["أصول"] = AccountTypes.Asset,
        ["اصول"] = AccountTypes.Asset,
        ["أصل"] = AccountTypes.Asset,
        ["asset"] = AccountTypes.Asset,
        ["assets"] = AccountTypes.Asset,

        ["التزامات"] = AccountTypes.Liability,
        ["الترامات"] = AccountTypes.Liability,
        ["خصوم"] = AccountTypes.Liability,
        ["مطلوبات"] = AccountTypes.Liability,
        ["liability"] = AccountTypes.Liability,
        ["liabilities"] = AccountTypes.Liability,

        ["حقوق ملكية"] = AccountTypes.Equity,
        ["حقوق الملكية"] = AccountTypes.Equity,
        ["equity"] = AccountTypes.Equity,

        ["مصروفات"] = AccountTypes.Expense,
        ["استخدامات"] = AccountTypes.Expense,
        ["تكاليف"] = AccountTypes.Expense,
        ["expense"] = AccountTypes.Expense,
        ["expenses"] = AccountTypes.Expense,

        ["إيرادات"] = AccountTypes.Revenue,
        ["ايرادات"] = AccountTypes.Revenue,
        ["مبيعات"] = AccountTypes.Revenue,
        ["revenue"] = AccountTypes.Revenue,
        ["income"] = AccountTypes.Revenue,
    };

    static string TypeLabel(string type) => type switch
    {
        AccountTypes.Liability => "التزامات",
        AccountTypes.Equity => "حقوق ملكية",
        AccountTypes.Expense => "مصروفات",
        AccountTypes.Revenue => "إيرادات",
        _ => "أصول",
    };

    /// <summary>
    /// تصدير الدليل الحالي — ملفّ إكسل يُعدَّل ويُعاد رفعه.
    ///
    /// <para>وهو نصف الميزة: من يريد إعادة تسمية أربعين حساباً لا يفتح
    /// أربعين نافذة، بل يصدّر ويعدّل في إكسل ويرفع.</para>
    /// </summary>
    [HttpGet("export")]
    public async Task<IActionResult> Export()
    {
        var accounts = await _db.Accounts.OrderBy(a => a.Code).ToListAsync();
        var byId = accounts.ToDictionary(a => a.Id, a => a.Code);

        var rows = accounts.Select(a => new[]
        {
            a.Code,
            a.Name,
            TypeLabel(a.Type),
            a.ParentId is { } pid ? byId.GetValueOrDefault(pid, "") : "",
        }).ToList();

        // دليلٌ فارغ يُصدَّر بصفّ مثال لا بورقةٍ بيضاء: من ضغط «تصدير» على
        // نظامٍ جديد يريد أن يعرف شكل الملف المطلوب.
        if (rows.Count == 0)
        {
            rows.Add(new[] { "مثال: 1", "الأصول", "أصول", "" });
            rows.Add(new[] { "مثال: 11", "الأصول المتداولة", "أصول", "1" });
        }

        var bytes = SpreadsheetTemplate.Build(
            sheetName: "دليل الحسابات",
            headers: new[] { "الرمز", "الاسم", "النوع", "رمز الأب" },
            rows: rows,
            // الرمز نصٌّ لا رقم: «01» يفقد صفره، و«1101» يصير رقماً يُنسَّق
            // بفاصلة آلاف فيخرج «1,101».
            textColumns: new[] { 0, 3 });

        return File(bytes, SpreadsheetTemplate.ContentType, "دليل-الحسابات.xlsx");
    }

    /// <summary>
    /// معاينة ثم تنفيذ — كما في استيراد العملاء والأصناف.
    ///
    /// <para>ودليلٌ يُكتب فوق دليلٍ عامل بلا معاينة قد يقلب أنواع الحسابات
    /// كلّها، فينقلب الميزان ولا يُعرف أين الخلل.</para>
    /// </summary>
    [HttpPost("import")]
    [RequestSizeLimit(MaxFileBytes)]
    public async Task<ActionResult<AccountImportSummary>> Import(
        IFormFile file, [FromQuery] bool dryRun = true)
    {
        if (file is null || file.Length == 0)
            return BadRequest(new { message = "لم يُرفَق ملف" });

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
        var existing = await _db.Accounts.ToDictionaryAsync(a => a.Code, a => a);

        // ما رُحّل إليه لا يُغيَّر نوعه: النوع يقرّر إشارة الرصيد وموضع
        // الحساب في الميزانية، وقلبُه بعد الترحيل يقلب تقارير سنةٍ مضت.
        var posted = (await _db.JournalEntryLines
                .Select(l => l.AccountId).Distinct().ToListAsync())
            .ToHashSet();

        var results = new List<AccountImportRowResult>();
        var exampleRowsSkipped = 0;
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // الأب قبل ابنه: ملفٌّ يذكر «1101» قبل «11» صحيحٌ عند من كتبه،
        // والترتيب بطول الرمز يجعله يعمل بلا أن يُطلب منه ترتيبٌ خاص.
        var parsed = new List<(int Row, string Code, string Name, string Type, string ParentCode)>();

        for (var i = 0; i < rows.Count; i++)
        {
            var row = rows[i];
            var rowNumber = i + 2;

            var code = SpreadsheetReader.Value(row, "الرمز", "رمز الحساب", "code", "account_code");
            var name = SpreadsheetReader.Value(row, "الاسم", "اسم الحساب", "name", "account_name");
            var typeRaw = SpreadsheetReader.Value(row, "النوع", "التصنيف", "type");
            var parentCode = SpreadsheetReader.Value(row, "رمز الأب", "الأب", "parent", "parent_code") ?? "";

            if (SpreadsheetReader.IsExampleRow(code) || SpreadsheetReader.IsExampleRow(name))
            {
                exampleRowsSkipped++;
                continue;
            }

            if (string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(name))
            {
                results.Add(new AccountImportRowResult(rowNumber, code ?? "", name ?? "", "خطأ",
                    "الرمز والاسم إلزاميان"));
                continue;
            }

            code = code.Trim();
            if (!seen.Add(code))
            {
                results.Add(new AccountImportRowResult(rowNumber, code, name, "خطأ",
                    $"الرمز {code} مكرَّر في الملف"));
                continue;
            }

            string type;
            if (string.IsNullOrWhiteSpace(typeRaw))
            {
                // بلا نوعٍ مذكور: يُؤخذ من الحساب القائم إن وُجد، وإلا من
                // الأب — ودليلٌ كامل بلا عمود نوع شائع، فالنوع يُورَّث.
                type = existing.TryGetValue(code, out var current)
                    ? current.Type
                    : "";
            }
            else if (TypeAliases.TryGetValue(typeRaw.Trim(), out var mapped))
            {
                type = mapped;
            }
            else
            {
                results.Add(new AccountImportRowResult(rowNumber, code, name, "خطأ",
                    $"نوع غير معروف: {typeRaw} — المقبول: أصول، التزامات، حقوق ملكية، مصروفات، إيرادات"));
                continue;
            }

            parsed.Add((rowNumber, code, name.Trim(), type, parentCode.Trim()));
        }

        // الترتيب بطول الرمز ثم بالرمز: الأب أقصر من ابنه في كل دليل
        // متدرّج، ورمزُ الأب المذكور صراحةً يُفحَص بعده على أي حال.
        parsed = parsed.OrderBy(p => p.Code.Length).ThenBy(p => p.Code, StringComparer.Ordinal).ToList();

        var toAdd = new Dictionary<string, Account>();
        var willCreate = 0;
        var willUpdate = 0;

        foreach (var item in parsed)
        {
            Account? parent = null;
            var parentCode = item.ParentCode;

            // بلا رمز أبٍ مذكور: يُشتقّ من البادئة — أطولُ رمزٍ موجود يسبق
            // هذا الرمز. وهو ما يجعل دليلاً بأربعمئة حساب يدخل بعمودين.
            if (string.IsNullOrWhiteSpace(parentCode) && item.Code.Length > 1)
            {
                for (var len = item.Code.Length - 1; len > 0; len--)
                {
                    var candidate = item.Code[..len];
                    if (existing.ContainsKey(candidate) || toAdd.ContainsKey(candidate))
                    {
                        parentCode = candidate;
                        break;
                    }
                }
            }

            if (!string.IsNullOrWhiteSpace(parentCode))
            {
                if (existing.TryGetValue(parentCode, out var found)) parent = found;
                else if (toAdd.TryGetValue(parentCode, out var pending)) parent = pending;
                else
                {
                    results.Add(new AccountImportRowResult(item.Row, item.Code, item.Name, "خطأ",
                        $"الأب «{parentCode}» غير موجود — أضِفه في الملف أو صحّح الرمز"));
                    continue;
                }
            }

            var type = string.IsNullOrWhiteSpace(item.Type) ? parent?.Type ?? "" : item.Type;
            if (string.IsNullOrWhiteSpace(type))
            {
                results.Add(new AccountImportRowResult(item.Row, item.Code, item.Name, "خطأ",
                    "النوع مطلوب لحسابٍ جذر — لا أبَ يُورَّث منه"));
                continue;
            }

            if (existing.TryGetValue(item.Code, out var account))
            {
                if (account.IsSystem && account.Type != type)
                {
                    results.Add(new AccountImportRowResult(item.Row, item.Code, item.Name, "خطأ",
                        "حساب يعتمد عليه الترحيل الآلي — لا يُغيَّر نوعه"));
                    continue;
                }
                if (posted.Contains(account.Id) && account.Type != type)
                {
                    results.Add(new AccountImportRowResult(item.Row, item.Code, item.Name, "خطأ",
                        "رُحّل إلى هذا الحساب — لا يُغيَّر نوعه بعد الترحيل"));
                    continue;
                }

                if (!dryRun)
                {
                    account.Name = item.Name;
                    account.Type = type;
                    if (parent is not null && parent.Id != account.Id) account.ParentId = parent.Id;
                }
                willUpdate++;
                results.Add(new AccountImportRowResult(item.Row, item.Code, item.Name, "تحديث", null));
            }
            else
            {
                var created = new Account
                {
                    OrganizationId = orgId,
                    Code = item.Code,
                    Name = item.Name,
                    Type = type,
                    ParentId = parent?.Id,
                    IsPostable = true,
                    IsSystem = false,
                };
                toAdd[item.Code] = created;
                if (!dryRun) _db.Accounts.Add(created);

                // الأب يفقد قابلية الترحيل بمجرّد أن يُولَد له ابن: رصيدٌ
                // عليه مباشرةً يكسر تساويه مع مجموع أبنائه.
                if (parent is not null && !dryRun) parent.IsPostable = false;

                willCreate++;
                results.Add(new AccountImportRowResult(item.Row, item.Code, item.Name, "إنشاء", null));
            }
        }

        if (results.Count == 0 && exampleRowsSkipped > 0)
            return BadRequest(new { message = "الملف لا يحوي إلا صفّ المثال — اكتب دليلك مكانه ثم أعد الرفع" });

        var withErrors = results.Count(r => r.Error is not null);

        // لا استيراد جزئي لدليل: شجرةٌ نصفُها دخل ونصفُها رُفض تترك حسابات
        // بلا آباء ومحاسباً لا يعرف أين وقف.
        var commit = !dryRun && withErrors == 0;
        if (commit)
        {
            _db.LogAudit(orgId, CurrentUserId(), "accounts.imported", "accounts", null,
                newValues: new { Created = willCreate, Updated = willUpdate, File = file.FileName });
            await _db.SaveChangesAsync();
        }

        return new AccountImportSummary(
            results.Count, willCreate, willUpdate, withErrors, commit, results, exampleRowsSkipped);
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
