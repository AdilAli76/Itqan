using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;

namespace KineticEnterprise.Api.Controllers;

/// <param name="Key">مفتاحٌ ثابت يُخزَّن مع القيمة — لا يتغيّر بتغيّر العنوان.</param>
/// <param name="Type">text أو number أو date أو select.</param>
public record AccountFieldDef(
    string Key, string Label, string Type, bool Required, List<string> Options);

public record UpdateAccountFieldsRequest(List<AccountFieldDef> Fields);

/// <summary>
/// الحقول الإضافية لحسابات الدليل — يعرّفها مالك المنظمة.
///
/// <para><b>سبب وجودها:</b> ما يحتاجه الحساب يختلف بالنشاط: مقاولاتٌ تريد
/// «مركز التكلفة»، وجهةٌ متعدّدة العملات تريد «عملة الحساب»، ومكتبٌ يريد
/// رقم الحساب في نظامه القديم ليطابق عند التحويل. وإضافةُ عمودٍ لكل واحدة
/// تعني ترقيةً لكل عميل، وانتظارَه إصداراً جديداً ليكتب رقماً.</para>
///
/// <para><b>والمفتاح لا يتغيّر بتغيّر العنوان:</b> من يُعيد تسمية «مركز
/// التكلفة» إلى «المشروع» لا يقصد محو ما كُتب في مئة حساب. فالقيم مرتبطة
/// بمفتاحٍ مولَّد، والعنوان نصٌّ يُعرَض.</para>
/// </summary>
[ApiController]
[Route("api/accounting/account-fields")]
[Authorize]
[RequireModule("accounting")]
public class AccountFieldsController : ControllerBase
{
    private readonly AppDbContext _db;
    public AccountFieldsController(AppDbContext db) => _db = db;

    /// <summary>الأنواع المدعومة — نصّ ورقم وتاريخ وقائمة اختيار.</summary>
    static readonly string[] Types = { "text", "number", "date", "select" };

    /// <summary>
    /// عشرة حقول حدّاً.
    ///
    /// <para>ليس قيداً تقنياً بل قيدُ شاشة: نموذج حسابٍ بعشرين حقلاً إضافياً
    /// لا يملؤه أحد، ويُترك فارغاً فيصير الحقل زينةً تُربك من يقرأ.</para>
    /// </summary>
    const int MaxFields = 10;

    [HttpGet]
    public async Task<ActionResult<List<AccountFieldDef>>> Get()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        return Parse(org?.AccountFieldDefsJson);
    }

    [HttpPut]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Update(UpdateAccountFieldsRequest request)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return NotFound();

        var incoming = request.Fields ?? new List<AccountFieldDef>();
        if (incoming.Count > MaxFields)
            return BadRequest(new { message = $"الحد الأقصى {MaxFields} حقول" });

        var existing = Parse(org.AccountFieldDefsJson);
        var usedKeys = existing.Select(f => f.Key).ToHashSet();
        var result = new List<AccountFieldDef>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var field in incoming)
        {
            var label = (field.Label ?? "").Trim();
            if (label.Length == 0)
                return BadRequest(new { message = "عنوان الحقل إلزامي" });
            if (!seen.Add(label))
                return BadRequest(new { message = $"العنوان «{label}» مكرَّر" });

            var type = Types.Contains(field.Type) ? field.Type : "text";
            var options = (field.Options ?? new List<string>())
                .Select(o => o.Trim()).Where(o => o.Length > 0).Distinct().ToList();

            if (type == "select" && options.Count == 0)
                return BadRequest(new { message = $"«{label}» قائمة اختيار بلا خيارات" });

            // مفتاحٌ قائم يُحفَظ كما هو، والجديد يأخذ رقماً لم يُستعمل —
            // فإعادة الترتيب أو تغيير العنوان لا يُيتّم قيمةً مخزَّنة.
            var key = !string.IsNullOrWhiteSpace(field.Key) && usedKeys.Contains(field.Key)
                ? field.Key
                : NextKey(usedKeys);
            usedKeys.Add(key);

            result.Add(new AccountFieldDef(key, label, type, field.Required, options));
        }

        org.AccountFieldDefsJson = JsonSerializer.Serialize(result);
        _db.LogAudit(org.Id, CurrentUserId(), "account_fields.updated", "organizations", org.Id,
            newValues: new { Count = result.Count, Labels = result.Select(f => f.Label) });
        await _db.SaveChangesAsync();

        // القيم القديمة **لا تُمحى** عند حذف تعريف: من حذف حقلاً بالخطأ
        // يُعيده فيجد ما كُتب. وقيمةٌ بلا تعريف تُتجاهَل عند القراءة.
        return NoContent();
    }

    static List<AccountFieldDef> Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<AccountFieldDef>();
        try
        {
            // غير حسّاس لحالة الأحرف: ما يُكتب هنا بـPascalCase يُقرأ في
            // الواجهة camelCase، ونصٌّ خُزّن بأحدهما لا يجوز أن يُقرأ
            // فارغاً بسبب حرفٍ كبير.
            return JsonSerializer.Deserialize<List<AccountFieldDef>>(json,
                       new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                   ?? new List<AccountFieldDef>();
        }
        catch (JsonException)
        {
            // نصٌّ تالف في عمود إعدادات لا يُسقط شاشة الدليل: يُقرأ فارغاً.
            return new List<AccountFieldDef>();
        }
    }

    static string NextKey(HashSet<string> used)
    {
        for (var i = 1; i <= MaxFields * 4; i++)
        {
            var candidate = $"f{i}";
            if (!used.Contains(candidate)) return candidate;
        }
        return Guid.NewGuid().ToString("N")[..8];
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
