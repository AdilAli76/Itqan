using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record AccountDto(
    Guid Id, string Code, string Name, Guid? ParentId, string Type,
    bool IsPostable, bool IsSystem, bool IsActive,
    /// رصيد الحساب شاملاً أبناءه — الشجرة تُقرأ مجمَّعةً ومفصَّلةً معاً.
    decimal Balance);

public record CreateAccountRequest(string Code, string Name, Guid? ParentId);

/// <param name="Code">
/// رمزٌ جديد. يُقبل تغييره ما دام الحساب بلا قيود: الرمز يُقرأ في كل تقرير
/// ويُرتَّب به الدليل، وتغييرُه بعد الترحيل يجعل تقرير الشهر الماضي يذكر
/// رمزاً لا وجود له.
/// </param>
public record UpdateAccountRequest(string Code, string Name, bool IsActive);

/// <param name="Balance">الرصيد قبل الفترة — بإشارة طبيعة الحساب.</param>
public record AccountStatementLine(
    DateTime Date, string Description, string Source, Guid EntryId,
    decimal Debit, decimal Credit, decimal Balance);

public record AccountStatementDto(
    Guid AccountId, string Code, string Name, string Type, bool IsPostable,
    DateTime From, DateTime To,
    decimal OpeningBalance, decimal Debit, decimal Credit, decimal ClosingBalance,
    List<AccountStatementLine> Lines,
    /// حساباتٌ تحته — يُفتح منها ما يُرحَّل إليه فعلاً.
    List<AccountDto> Children);

public record JournalLineDto(Guid AccountId, string AccountCode, string AccountName,
    decimal Debit, decimal Credit, string? Note);

public record JournalEntryDto(
    Guid Id, long Number, DateTime EntryDate, string Source, Guid? SourceId,
    string Description, Guid? ReversesEntryId, bool IsReversed,
    string? CreatedByName, DateTime CreatedAt, List<JournalLineDto> Lines);

public record TrialBalanceRow(string Code, string Name, string Type, decimal Debit, decimal Credit);

public record TrialBalanceDto(DateTime From, DateTime To, List<TrialBalanceRow> Rows,
    decimal TotalDebit, decimal TotalCredit);

public record ReverseEntryRequest(string Reason);

/// <param name="Debit">مدين هذا السطر. صفر إن كان دائناً.</param>
public record ManualEntryLineRequest(Guid AccountId, decimal Debit, decimal Credit, string? Note);

public record CreateManualEntryRequest(
    DateTime EntryDate, string Description, List<ManualEntryLineRequest> Lines, Guid? BranchId);

public record CloseFiscalPeriodRequest(DateTime PeriodEnd);
public record ReopenClosingRequest(string Reason);

public record FiscalClosingDto(
    Guid Id, DateTime PeriodEnd, decimal NetResult, Guid? JournalEntryId,
    string? ClosedByName, DateTime ClosedAt,
    bool IsReopened, string? ReopenReason, string? ReopenedByName, DateTime? ReopenedAt);

public record StatementLine(string Code, string Name, decimal Amount);

/// قائمة الدخل عن مدّة.
public record IncomeStatementDto(
    DateTime From, DateTime To,
    List<StatementLine> Revenues, decimal TotalRevenue,
    List<StatementLine> Expenses, decimal TotalExpense,
    /// الإيرادات ناقص الاستخدامات. سالب = خسارة.
    decimal NetIncome);

/// الميزانية في تاريخ.
public record BalanceSheetDto(
    DateTime AsOf,
    List<StatementLine> Assets, decimal TotalAssets,
    List<StatementLine> Liabilities, decimal TotalLiabilities,
    List<StatementLine> Equity, decimal TotalEquity,
    /// صافي الدخل منذ بداية التشغيل حتى التاريخ — يدخل حقوق الملكية.
    decimal RetainedResult,
    /// الأصول − (الالتزامات + حقوق الملكية + النتيجة). صفرٌ يعني التوازن.
    decimal Difference);

/// <summary>
/// دليل الحسابات ودفتر اليومية.
///
/// <para>مقيَّد بوحدة <c>accounting</c> — إصدار المؤسسات وحده. بقّالة بفرع
/// واحد لا تحتاج ميزان مراجعة، وشجرة حسابات في شاشتها ضوضاء تُربك ولا
/// تُفيد.</para>
/// </summary>
[RequireModule("accounting")]
[ApiController]
[Route("api/accounting")]
[Authorize]
public class AccountingController : ControllerBase
{
    private readonly AppDbContext _db;
    public AccountingController(AppDbContext db) => _db = db;

    /// <summary>
    /// شجرة الحسابات بأرصدتها.
    ///
    /// <para><b>الأرصدة تُجمَّع على الشجرة صعوداً:</b> رصيد «الأصول» مجموع
    /// أبنائه لا رقمٌ مخزَّن. عمودٌ مخزَّن كان سيتعارض مع مجموع سطوره عند
    /// أول قيد يُكتب من مسار نسي تحديثه — نفس درس رصيد المحفظة تماماً.</para>
    /// </summary>
    [HttpGet("accounts")]
    public async Task<ActionResult<List<AccountDto>>> GetAccounts()
    {
        var accounts = await _db.Accounts.OrderBy(a => a.Code).ToListAsync();
        if (accounts.Count == 0) return new List<AccountDto>();

        // أرصدة الحسابات الورقية من الدفتر مباشرة — استعلام تجميع واحد لا
        // استعلام لكل حساب.
        var raw = await _db.JournalEntryLines
            .GroupBy(l => l.AccountId)
            .Select(g => new
            {
                AccountId = g.Key,
                Debit = g.Sum(l => l.Debit),
                Credit = g.Sum(l => l.Credit),
            })
            .ToDictionaryAsync(x => x.AccountId, x => x);

        var own = accounts.ToDictionary(a => a.Id, a =>
        {
            if (!raw.TryGetValue(a.Id, out var v)) return 0m;
            // الرصيد بإشارة طبيعة الحساب: أصلٌ رصيدُه مدين موجب، والتزامٌ
            // رصيدُه دائن موجب. عرضُ الجميع بإشارة المدين يجعل كل الالتزامات
            // سالبة على الشاشة — وهو صحيح حسابياً ومربك لكل من يقرأ.
            return AccountTypes.IsDebitNormal(a.Type) ? v.Debit - v.Credit : v.Credit - v.Debit;
        });

        // التجميع صعوداً: كل حساب يُضيف رصيده إلى كل آبائه.
        var totals = new Dictionary<Guid, decimal>(own);
        var byId = accounts.ToDictionary(a => a.Id);
        foreach (var account in accounts)
        {
            var value = own[account.Id];
            if (value == 0) continue;

            var parentId = account.ParentId;
            // حدٌّ للعمق يحمي من حلقة في البيانات (أبٌ صار ابن ابنه بتعديل
            // خاطئ): بلاه يدور الحلقة إلى الأبد ويُعلّق الطلب.
            for (var depth = 0; parentId is { } pid && depth < 16; depth++)
            {
                if (!byId.TryGetValue(pid, out var parent)) break;
                totals[pid] = totals.GetValueOrDefault(pid) + value;
                parentId = parent.ParentId;
            }
        }

        return accounts.Select(a => new AccountDto(
            a.Id, a.Code, a.Name, a.ParentId, a.Type,
            a.IsPostable, a.IsSystem, a.IsActive,
            totals.GetValueOrDefault(a.Id))).ToList();
    }

    /// <summary>
    /// يبذر الدليل الافتراضي — يُستدعى مرّة عند تفعيل الوحدة.
    ///
    /// <para>آمن للتكرار: لا يفعل شيئاً إن وُجد حساب واحد، فلا يمحو دليلاً
    /// عدّله محاسب.</para>
    /// </summary>
    [HttpPost("accounts/seed")]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<object>> Seed()
    {
        // ── لا دفترَ نصفَ عامل ──────────────────────────────────────────
        //
        // [RequireModule] على هذه الوحدة **يمرّ مالكَ المنصّة بلا فحص** —
        // عمداً، ليدير محتوى المنصّة في منظمته القياسية. لكن الترحيل الآلي
        // (بيع، مرتجع، استلام، سداد) يقيس بـ[Ledger.IsEnabled] وهو لا
        // يستثني أحداً. فالنتيجة دفترٌ يقبل قيوداً يدوية ولا تصله قيود
        // البيع إطلاقاً.
        //
        // وذلك **أسوأ من غياب الدفتر**: ميزان المراجعة يتوازن فيبدو
        // صحيحاً، بينما المبيعات وتكلفتها غائبتان عنه كلّها. اكتُشف حين
        // مرّ فحص الـAPI ببذر الدليل وقيدٍ يدوي ثم فشلت أربع فحوصات ترحيلٍ
        // آلي متتالية بلا سببٍ ظاهر.
        //
        // فيُقاس هنا بنفس ما يقيس به الترحيل، لا بما يقيس به الحاجز.
        if (await LedgerDisabledAsync() is { } refusal) return refusal;

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var seeded = await ChartOfAccounts.SeedAsync(_db, orgId);

        // دليلٌ موجود يُفحَص ربطه: الأدوار تنمو مع كل نوع حركة جديد، ودليلٌ
        // بُذر قبل إضافة دور يفشل عنده أول استلام أو مصروف. راجع
        // ChartOfAccounts.RepairMappingsAsync.
        var repaired = seeded ? new List<string>() : await ChartOfAccounts.RepairMappingsAsync(_db, orgId);

        return Ok(new
        {
            seeded,
            repairedRoles = repaired,
            message = seeded
                ? "بُذر دليل الحسابات الافتراضي"
                : repaired.Count > 0
                    ? $"أُكمل ربط {repaired.Count} دور محاسبي ناقص"
                    : "الدليل موجود ومكتمل — لم يُغيَّر شيء",
        });
    }

    /// <summary>
    /// حساب جديد يضيفه المحاسب تحت أبٍ قائم.
    ///
    /// <para>النوع يُورَّث من الأب ولا يُختار: حسابٌ مصروفات تحت «الأصول»
    /// يُفسد الميزانية وميزان المراجعة معاً، والمستخدم لا يرى الأثر لحظتَها.
    /// </para>
    /// </summary>
    [HttpPost("accounts")]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<AccountDto>> CreateAccount(CreateAccountRequest request)
    {
        var code = (request.Code ?? "").Trim();
        var name = (request.Name ?? "").Trim();
        if (code.Length == 0 || name.Length == 0)
        {
            return BadRequest(new { message = "الرمز والاسم إلزاميان" });
        }

        var parent = request.ParentId is { } pid
            ? await _db.Accounts.FirstOrDefaultAsync(a => a.Id == pid)
            : null;
        if (request.ParentId is not null && parent is null)
        {
            return BadRequest(new { message = "الحساب الأب غير موجود" });
        }
        if (parent is null)
        {
            // جذرٌ جديد يعني قسماً خامساً في الدليل الموحّد — وهو ليس شيئاً
            // يُنشأ من شاشة. الأقسام الأربعة ثابتة.
            return BadRequest(new { message = "اختر حساباً أباً — لا تُنشأ أقسام جديدة في الدليل" });
        }

        if (await _db.Accounts.AnyAsync(a => a.Code == code))
        {
            return BadRequest(new { message = $"الرمز {code} مستعمل في حساب آخر" });
        }

        var account = new Account
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            Code = code,
            Name = name,
            ParentId = parent.Id,
            Type = parent.Type,
            IsPostable = true,
            IsSystem = false,
        };
        _db.Accounts.Add(account);

        // الأب يفقد قابلية الترحيل بمجرّد أن يُولَد له ابن: رصيدٌ على الأب
        // مباشرةً يكسر تساويه مع مجموع أبنائه.
        //
        // والقيود القديمة عليه تبقى — لا تُنقَل ولا تُحذف (حرمة القيد).
        // فرصيده يبقى مجموع أبنائه زائد ما رُحّل إليه قبل أن يصير أباً.
        parent.IsPostable = false;

        _db.LogAudit(account.OrganizationId, CurrentUserId(), "account.created", "accounts", account.Id,
            newValues: new { account.Code, account.Name, account.Type });
        await _db.SaveChangesAsync();

        return new AccountDto(account.Id, account.Code, account.Name, account.ParentId,
            account.Type, account.IsPostable, account.IsSystem, account.IsActive, 0);
    }

    /// <summary>
    /// كشف حساب واحد: رصيدٌ افتتاحي، ثم حركاته سطراً سطراً برصيدٍ متحرّك.
    ///
    /// <para><b>العطب الذي يصلحه:</b> الضغط على «الصندوق» في الشجرة كان
    /// يفتح <b>دفتر اليومية</b> مُرشَّحاً عليه — أي كل القيود التي مسّته
    /// بسطورها الأخرى (المبيعات، الضريبة، المخزون…). ومن يضغط على الصندوق
    /// يسأل سؤالاً واحداً: «كم فيه، ومن أين جاء وإلى أين ذهب؟» — والدفتر
    /// لا يجيبه: لا رصيد فيه ولا تسلسل، وسطور الحسابات الأخرى تُغرق ما
    /// يبحث عنه.</para>
    ///
    /// <para><b>والرصيد المتحرّك هو الفرق كلّه:</b> كشفٌ بلا عمود رصيد
    /// يُلزم قارئه بجمع عمودين بيده ليعرف كم كان في الصندوق يوم الثلاثاء.
    /// </para>
    ///
    /// <para>والحساب الأب — الذي لا يُرحَّل إليه — يُفتح على أبنائه: لا
    /// حركة له ليعرضها، وعرضُ فراغٍ لمن ضغط عليه يبدو عطلاً.</para>
    /// </summary>
    [HttpGet("accounts/{id:guid}/statement")]
    public async Task<ActionResult<AccountStatementDto>> GetAccountStatement(
        Guid id, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var account = await _db.Accounts.FirstOrDefaultAsync(a => a.Id == id);
        if (account is null) return NotFound();

        // الافتراضي هذا الشهر: أكثر سؤالٍ يُسأل عن حسابٍ هو «ماذا جرى فيه
        // هذا الشهر»، وفتحُ العمر كلّه يجعل أوّل عرضٍ آلاف السطور.
        var org = await _db.Organizations.FirstOrDefaultAsync();
        var today = OrgClock.Today(org);
        var start = (from ?? new DateTime(today.Year, today.Month, 1)).Date;
        var end = (to ?? today).Date.AddDays(1).AddTicks(-1);

        var debitNormal = AccountTypes.IsDebitNormal(account.Type);

        // الافتتاحي من كل ما قبل الفترة — استعلامُ تجميعٍ واحد لا قراءةُ
        // سطور عمرٍ كامل في الذاكرة.
        // الانضمام بـ Join لا بخاصية تنقّل: JournalEntryLine بلا مرجع إلى
        // قيدها في النموذج (راجع Entities.cs)، فالربط يُكتب صراحةً — كما
        // في BalancesAsync أدناه.
        var before = await _db.JournalEntryLines
            .Where(l => l.AccountId == id)
            .Join(_db.JournalEntries.Where(e => e.EntryDate < start),
                l => l.JournalEntryId, e => e.Id, (l, e) => l)
            .GroupBy(l => 1)
            .Select(g => new { Debit = g.Sum(x => x.Debit), Credit = g.Sum(x => x.Credit) })
            .FirstOrDefaultAsync();

        var opening = before is null
            ? 0m
            : debitNormal ? before.Debit - before.Credit : before.Credit - before.Debit;

        var lines = await _db.JournalEntryLines
            .Where(l => l.AccountId == id)
            .Join(_db.JournalEntries.Where(e => e.EntryDate >= start && e.EntryDate <= end),
                l => l.JournalEntryId, e => e.Id, (l, e) => new
                {
                    e.EntryDate,
                    e.Description,
                    e.Source,
                    EntryId = e.Id,
                    e.CreatedAt,
                    l.Debit,
                    l.Credit,
                    l.Note,
                })
            // التاريخ ثم لحظة الإنشاء: قيدان في يوم واحد ترتيبُهما هو
            // ترتيب حدوثهما، والرصيد المتحرّك بلا ترتيبٍ ثابت يتغيّر عند
            // كل قراءة.
            .OrderBy(x => x.EntryDate).ThenBy(x => x.CreatedAt)
            .ToListAsync();

        var running = opening;
        var statement = new List<AccountStatementLine>();
        foreach (var line in lines)
        {
            running += debitNormal ? line.Debit - line.Credit : line.Credit - line.Debit;
            statement.Add(new AccountStatementLine(
                line.EntryDate,
                // ملاحظة السطر أدقّ من وصف القيد حين توجد: «إيجار محل
                // فبراير» تقول أكثر من «مصروف».
                string.IsNullOrWhiteSpace(line.Note) ? (line.Description ?? "") : line.Note!,
                line.Source ?? "",
                line.EntryId,
                line.Debit, line.Credit, running));
        }

        var children = await _db.Accounts
            .Where(a => a.ParentId == id)
            .OrderBy(a => a.Code)
            .Select(a => new AccountDto(a.Id, a.Code, a.Name, a.ParentId, a.Type,
                a.IsPostable, a.IsSystem, a.IsActive, 0))
            .ToListAsync();

        return new AccountStatementDto(
            account.Id, account.Code, account.Name, account.Type, account.IsPostable,
            start, end.Date,
            opening,
            statement.Sum(l => l.Debit), statement.Sum(l => l.Credit),
            running,
            statement,
            children);
    }

    /// <summary>
    /// تعديل حساب: اسمه، ورمزه، وتفعيله.
    ///
    /// <para><b>ولماذا لم يكن موجوداً وهو لازم:</b> الدليل المبذور عامٌّ،
    /// ونشاطُ كل جهة يختلف — محلُّ ملابس يريد «مصروفات دعاية» ومخبزٌ يريد
    /// «دقيق وخميرة». وكان النظام يُنشئ ولا يُعدِّل، فاسمٌ كُتب بخطأ يبقى
    /// في كل تقرير إلى الأبد.</para>
    ///
    /// <para><b>والرمز لا يُغيَّر بعد أوّل قيد:</b> يُقرأ في كل تقرير
    /// ويُرتَّب به الدليل، وتغييرُه بعد الترحيل يجعل تقرير الشهر الماضي
    /// يذكر رمزاً لا وجود له. وحسابُ النظام لا يُعطَّل إطلاقاً — تعطيل
    /// «المبيعات» يُوقف كل بيع في المحلّ.</para>
    /// </summary>
    [HttpPut("accounts/{id:guid}")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> UpdateAccount(Guid id, UpdateAccountRequest request)
    {
        var account = await _db.Accounts.FirstOrDefaultAsync(a => a.Id == id);
        if (account is null) return NotFound();

        var code = (request.Code ?? "").Trim();
        var name = (request.Name ?? "").Trim();
        if (code.Length == 0 || name.Length == 0)
            return BadRequest(new { message = "الرمز والاسم إلزاميان" });

        var hasEntries = await _db.JournalEntryLines.AnyAsync(l => l.AccountId == id);

        if (code != account.Code)
        {
            if (account.IsSystem)
                return BadRequest(new { message = "لا يُغيَّر رمز حسابٍ يعتمد عليه الترحيل الآلي" });
            if (hasEntries)
                return BadRequest(new { message = "لا يُغيَّر الرمز بعد أن رُحّل إلى الحساب — غيّر الاسم وحده" });
            if (await _db.Accounts.AnyAsync(a => a.Code == code && a.Id != id))
                return BadRequest(new { message = $"الرمز {code} مستعمل في حساب آخر" });
        }

        if (!request.IsActive && account.IsSystem)
            return BadRequest(new { message = "لا يُعطَّل حسابٌ يعتمد عليه الترحيل الآلي" });

        var old = new { account.Code, account.Name, account.IsActive };
        account.Code = code;
        account.Name = name;
        account.IsActive = request.IsActive;

        _db.LogAudit(account.OrganizationId, CurrentUserId(), "account.updated", "accounts", account.Id,
            oldValues: old, newValues: new { account.Code, account.Name, account.IsActive });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// حذف حساب — أو تعطيله إن كان له تاريخ.
    ///
    /// <para><b>وحسابٌ رُحّل إليه لا يُحذف أبداً:</b> حذفُه يترك قيوداً
    /// تشير إلى لا شيء، فينكسر ميزان المراجعة ولا يُعرف من أين. فيُعطَّل:
    /// يختفي من قوائم الاختيار ويبقى في التقارير التاريخية — وهو ما يريده
    /// من يقول «احذفه» فعلاً.</para>
    ///
    /// <para>وحسابٌ له أبناء لا يُحذف قبلهم: شجرةٌ بأبناءٍ بلا أب لا
    /// تُرسَم.</para>
    /// </summary>
    [HttpDelete("accounts/{id:guid}")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> DeleteAccount(Guid id)
    {
        var account = await _db.Accounts.FirstOrDefaultAsync(a => a.Id == id);
        if (account is null) return NotFound();

        if (account.IsSystem)
            return BadRequest(new { message = "حساب يعتمد عليه الترحيل الآلي — لا يُحذف" });

        if (await _db.Accounts.AnyAsync(a => a.ParentId == id))
            return BadRequest(new { message = "احذف الحسابات التي تحته أولاً" });

        if (await _db.JournalEntryLines.AnyAsync(l => l.AccountId == id))
        {
            account.IsActive = false;
            _db.LogAudit(account.OrganizationId, CurrentUserId(), "account.deactivated", "accounts", account.Id,
                oldValues: new { account.Code, account.Name });
            await _db.SaveChangesAsync();
            return Ok(new
            {
                deactivated = true,
                message = "رُحّل إلى هذا الحساب من قبل، فعُطِّل بدل حذفه — يبقى في التقارير القديمة ولا يظهر في قوائم الاختيار",
            });
        }

        // بلا قيدٍ ولا ابن: يُحذف فعلاً. وأبوه يعود قابلاً للترحيل إن لم
        // يبقَ له ابنٌ آخر — وإلا بقي أباً بلا أبناء لا يُرحَّل إليه.
        var parentId = account.ParentId;
        _db.Accounts.Remove(account);
        _db.LogAudit(account.OrganizationId, CurrentUserId(), "account.deleted", "accounts", account.Id,
            oldValues: new { account.Code, account.Name });
        await _db.SaveChangesAsync();

        if (parentId is { } pid)
        {
            var stillHasChildren = await _db.Accounts.AnyAsync(a => a.ParentId == pid);
            if (!stillHasChildren)
            {
                var parent = await _db.Accounts.FirstOrDefaultAsync(a => a.Id == pid);
                if (parent is not null && !parent.IsPostable)
                {
                    parent.IsPostable = true;
                    await _db.SaveChangesAsync();
                }
            }
        }

        return Ok(new { deactivated = false });
    }

    /// <summary>
    /// دفتر اليومية — القيود بسطورها.
    /// </summary>
    [HttpGet("journal")]
    public async Task<ActionResult<List<JournalEntryDto>>> GetJournal(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] Guid? accountId, [FromQuery] int limit = 100)
    {
        limit = Math.Clamp(limit, 1, 500);

        var query = _db.JournalEntries.Include(e => e.Lines).AsQueryable();
        if (from is { } f) query = query.Where(e => e.EntryDate >= f.Date);
        if (to is { } t) query = query.Where(e => e.EntryDate <= t.Date);
        if (accountId is { } aid)
        {
            query = query.Where(e => e.Lines.Any(l => l.AccountId == aid));
        }

        var entries = await query
            .OrderByDescending(e => e.Number)
            .Take(limit)
            .ToListAsync();

        return await ToDtosAsync(entries);
    }

    /// <summary>
    /// ميزان المراجعة.
    ///
    /// <para><b>ما يقوله فعلاً:</b> مجموع المدين يساوي مجموع الدائن. عدم
    /// تساويهما يعني قيداً غير متوازن دخل الدفتر — وهو ما يمنعه [Ledger]
    /// عند الكتابة، فالميزان هنا **تحقّقٌ مستقلّ** لا عرضٌ فقط: يكشف ما
    /// دخل من خارج الطريق الواحد (تعديل يدوي على القاعدة مثلاً).</para>
    ///
    /// <para>الحسابات الورقية وحدها: إدراج الآباء يحسب كل مبلغ مرّتين
    /// فيتضاعف الميزان بلا معنى.</para>
    /// </summary>
    [HttpGet("trial-balance")]
    public async Task<ActionResult<TrialBalanceDto>> GetTrialBalance(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        var fromDate = from?.Date ?? OrgClock.StartOfYear(org);
        var toDate = to?.Date ?? OrgClock.Today(org);

        var accounts = await _db.Accounts.ToDictionaryAsync(a => a.Id, a => a);

        // نفس الدالة التي تقرأ منها قائمة الدخل والميزانية — راجع
        // [BalancesAsync]. ثلاثة تقارير تقرأ الشيء نفسه، وحسابُه ثلاث مرّات
        // يعني ثلاثة أماكن تنحرف.
        var balances = await BalancesAsync(fromDate, toDate);

        var rows = new List<TrialBalanceRow>();
        foreach (var (accountId, net) in balances)
        {
            if (!accounts.TryGetValue(accountId, out var account)) continue;

            // الصافي في عموده الطبيعي: حسابٌ رصيده مدين يُعرض في عمود المدين
            // وحده لا في العمودين معاً. عرض المجموعين الخامين يجعل كل حساب
            // يظهر في العمودين فيصير الميزان غير قابل للقراءة.
            rows.Add(new TrialBalanceRow(
                account.Code, account.Name, account.Type,
                net > 0 ? net : 0,
                net < 0 ? -net : 0));
        }

        rows = rows.OrderBy(r => r.Code).ToList();
        return new TrialBalanceDto(fromDate, toDate, rows,
            rows.Sum(r => r.Debit), rows.Sum(r => r.Credit));
    }

    /// <summary>
    /// قائمة الدخل — «كم ربحتُ في هذه المدّة».
    ///
    /// <para>الإيرادات ناقص الاستخدامات. و«مردودات المبيعات» حسابٌ من نوع
    /// الإيراد برصيد مدين، فيُنقص الإيراد تلقائياً؛ و«مردودات المشتريات»
    /// حسابٌ من نوع الاستخدام برصيد دائن، فيُنقص التكلفة. لا طرح يدوي.</para>
    ///
    /// <para><b>والحسابات الورقية وحدها:</b> إدراج الآباء يحسب كل مبلغ
    /// مرّتين.</para>
    /// </summary>
    [HttpGet("income-statement")]
    public async Task<ActionResult<IncomeStatementDto>> GetIncomeStatement(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        // الافتراضات بتوقيت المنظمة: تقرير «هذا العام» في أول ساعتين من أول
        // يناير كان يعرض العام السابق.
        var org = await _db.Organizations.FirstOrDefaultAsync();
        var fromDate = from?.Date ?? OrgClock.StartOfYear(org);
        var toDate = to?.Date ?? OrgClock.Today(org);

        var balances = await BalancesAsync(fromDate, toDate);
        var accounts = await _db.Accounts.ToDictionaryAsync(a => a.Id, a => a);

        var revenues = new List<StatementLine>();
        var expenses = new List<StatementLine>();

        foreach (var (accountId, net) in balances)
        {
            if (!accounts.TryGetValue(accountId, out var account)) continue;

            // net = مدين − دائن. والإيراد طبيعته دائنة فيُقلب.
            if (account.Type == AccountTypes.Revenue)
            {
                revenues.Add(new StatementLine(account.Code, account.Name, -net));
            }
            else if (account.Type == AccountTypes.Expense)
            {
                expenses.Add(new StatementLine(account.Code, account.Name, net));
            }
        }

        revenues = revenues.Where(r => r.Amount != 0).OrderBy(r => r.Code).ToList();
        expenses = expenses.Where(e => e.Amount != 0).OrderBy(e => e.Code).ToList();

        var totalRevenue = revenues.Sum(r => r.Amount);
        var totalExpense = expenses.Sum(e => e.Amount);

        return new IncomeStatementDto(fromDate, toDate,
            revenues, totalRevenue, expenses, totalExpense, totalRevenue - totalExpense);
    }

    /// <summary>
    /// الميزانية — «ماذا أملك وماذا عليّ» في تاريخ.
    ///
    /// <para><b>ولماذا تدخل النتيجة في حقوق الملكية:</b> الإقفال السنوي غير
    /// مبنيّ بعد، فأرباح المدّة تبقى في حسابات الإيراد والاستخدام ولا تُرحَّل
    /// إلى «الأرباح المحتجزة». فلو عُرضت الميزانية بأرصدة حقوق الملكية وحدها
    /// **لما توازنت أبداً** — والفرق هو الربح بالضبط. فيُحسَب ويُعرَض صراحةً
    /// بدل أن يُترك فرقاً غامضاً يظنّه القارئ عطباً.</para>
    ///
    /// <para>ومنذ بداية التشغيل لا منذ أول السنة: الميزانية لقطةٌ تراكمية لا
    /// تقريرُ مدّة.</para>
    /// </summary>
    [HttpGet("balance-sheet")]
    public async Task<ActionResult<BalanceSheetDto>> GetBalanceSheet([FromQuery] DateTime? asOf)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        var date = asOf?.Date ?? OrgClock.Today(org);

        // من بداية التشغيل: DateTime.MinValue يغطّي كل قيد مكتوب.
        var balances = await BalancesAsync(DateTime.MinValue, date);
        var accounts = await _db.Accounts.ToDictionaryAsync(a => a.Id, a => a);

        var assets = new List<StatementLine>();
        var liabilities = new List<StatementLine>();
        var equity = new List<StatementLine>();
        decimal revenue = 0, expense = 0;

        foreach (var (accountId, net) in balances)
        {
            if (!accounts.TryGetValue(accountId, out var account)) continue;

            switch (account.Type)
            {
                case AccountTypes.Asset:
                    assets.Add(new StatementLine(account.Code, account.Name, net));
                    break;
                case AccountTypes.Liability:
                    liabilities.Add(new StatementLine(account.Code, account.Name, -net));
                    break;
                case AccountTypes.Equity:
                    equity.Add(new StatementLine(account.Code, account.Name, -net));
                    break;
                case AccountTypes.Revenue:
                    revenue += -net;
                    break;
                case AccountTypes.Expense:
                    expense += net;
                    break;
            }
        }

        assets = assets.Where(a => a.Amount != 0).OrderBy(a => a.Code).ToList();
        liabilities = liabilities.Where(l => l.Amount != 0).OrderBy(l => l.Code).ToList();
        equity = equity.Where(e => e.Amount != 0).OrderBy(e => e.Code).ToList();

        var totalAssets = assets.Sum(a => a.Amount);
        var totalLiabilities = liabilities.Sum(l => l.Amount);
        var totalEquity = equity.Sum(e => e.Amount);
        var retained = revenue - expense;

        return new BalanceSheetDto(date,
            assets, totalAssets,
            liabilities, totalLiabilities,
            equity, totalEquity,
            retained,
            totalAssets - (totalLiabilities + totalEquity + retained));
    }

    /// <summary>
    /// قيد يدوي — ما لا مسار آلياً له.
    ///
    /// <para><b>لماذا يلزم رغم الترحيل الآلي:</b> الدفتر يعرف البيع والشراء
    /// والمصروف والسداد، ولا يعرف إهلاكاً ولا مخصّصاً ولا تسوية جرد نقدية
    /// ولا تصحيح تبويب. وبلا هذا الباب يخرج المحاسب من النظام إلى ملفٍ
    /// جانبي — فيصير الدفتر ناقصاً وهو يبدو كاملاً.</para>
    ///
    /// <para><b>والوصف إلزامي:</b> قيدٌ يدوي بلا شرح يترك من يراجعه بعد
    /// سنة أمام أرقام لا يعرف لماذا كُتبت. والآلي يشرح نفسه بمصدره، واليدوي
    /// لا يشرحه إلا كاتبه.</para>
    ///
    /// <para>ويمرّ بكل حرّاس الدفتر: التوازن، والحساب الورقي، والمدّة
    /// المُقفَلة، وترقيم القيود — لأنه يمرّ من الطريق الواحد نفسه.</para>
    /// </summary>
    [HttpPost("journal")]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<JournalEntryDto>> CreateManualEntry(CreateManualEntryRequest request)
    {
        var description = (request.Description ?? "").Trim();
        if (description.Length == 0)
        {
            return BadRequest(new { message = "وصف القيد إلزامي — قيدٌ بلا شرح لا يُفهَم بعد سنة" });
        }

        var lines = (request.Lines ?? new List<ManualEntryLineRequest>())
            .Where(l => l.Debit != 0 || l.Credit != 0)
            .ToList();

        if (lines.Count < 2)
        {
            // سطرٌ واحد لا يكون قيداً: لكل مدين دائن.
            return BadRequest(new { message = "القيد يحتاج سطرين على الأقل" });
        }

        foreach (var line in lines)
        {
            if (line.Debit < 0 || line.Credit < 0)
            {
                return BadRequest(new { message = "المبالغ لا تكون سالبة — اعكس الجانب بدل ذلك" });
            }
            if (line.Debit > 0 && line.Credit > 0)
            {
                return BadRequest(new { message = "السطر إمّا مدين وإمّا دائن، لا الاثنين" });
            }
        }

        var accountIds = lines.Select(l => l.AccountId).Distinct().ToList();
        var accounts = await _db.Accounts
            .Where(a => accountIds.Contains(a.Id))
            .ToDictionaryAsync(a => a.Id, a => a);

        foreach (var id in accountIds)
        {
            if (!accounts.TryGetValue(id, out var account))
            {
                return BadRequest(new { message = "حساب غير موجود" });
            }
            if (!account.IsPostable)
            {
                // الوسيط لا يُرحَّل إليه: رصيدُه يجب أن يبقى مجموع أبنائه.
                return BadRequest(new
                {
                    message = $"«{account.Code} — {account.Name}» حساب تجميعي، اختر حساباً فرعياً تحته",
                });
            }
            if (!account.IsActive)
            {
                return BadRequest(new { message = $"«{account.Code} — {account.Name}» حساب موقوف" });
            }
        }

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);

        JournalEntry entry;
        try
        {
            entry = await Ledger.PostToAccountsAsync(_db, orgId, request.BranchId,
                JournalSources.Manual, null, description,
                lines.Select(l => (l.AccountId, l.Debit, l.Credit,
                    string.IsNullOrWhiteSpace(l.Note) ? null : l.Note!.Trim())),
                Array.Empty<PostingLine>(),
                CurrentUserId(),
                request.EntryDate.Date);
        }
        catch (LedgerRuleException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        _db.LogAudit(orgId, CurrentUserId(), "journal.manual_created", "journal_entries", entry.Id,
            newValues: new { entry.EntryDate, Description = description, Lines = lines.Count });
        await _db.SaveChangesAsync();

        return (await ToDtosAsync(new List<JournalEntry> { entry })).First();
    }

    /// <summary>
    /// الإقفالات — وتاريخ آخر مدّة مُقفَلة.
    /// </summary>
    [HttpGet("closings")]
    public async Task<ActionResult<List<FiscalClosingDto>>> GetClosings()
    {
        var closings = await _db.FiscalClosings.OrderByDescending(c => c.PeriodEnd).ToListAsync();
        return await ToClosingDtosAsync(closings);
    }

    /// <summary>
    /// إقفال مدّة مالية.
    ///
    /// <para><b>ما يفعله شيئان لا واحد:</b></para>
    /// <code>
    ///   من ح/ الإيرادات        (بأرصدتها الدائنة، فتصفر)
    ///       إلى ح/ الاستخدامات (بأرصدتها المدينة، فتصفر)
    ///       إلى ح/ الأرباح المحتجزة  (الفرق — أو منه إن كانت خسارة)
    /// </code>
    /// <para>ثم **قفلُ المدّة**: لا قيد بتاريخها أو قبله (راجع
    /// <c>Ledger.ClosedThroughAsync</c>). وبلا القفل لا معنى للإقفال.</para>
    ///
    /// <para><b>ولا يُقفَل ما لا حركة فيه:</b> إقفالٌ بقيدٍ فارغ يُنشئ قفلاً
    /// بلا سبب، ويُوهم بأن سنةً روجعت وأُغلقت وهي لم تكن.</para>
    /// </summary>
    [HttpPost("closings")]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<FiscalClosingDto>> Close(CloseFiscalPeriodRequest request)
    {
        var periodEnd = request.PeriodEnd.Date;

        // الحدّ بتوقيت **المنظمة** لا بغرينتش — راجع [OrgClock].
        //
        // كان بـUTC، فمنظمةٌ شرق غرينتش لا تستطيع إقفال «أمسها» حتى يمرّ
        // منتصف ليل غرينتش. والرسالة تُسمّي التاريخ المسموح صراحةً.
        var org = await _db.Organizations.FirstOrDefaultAsync();
        var latestAllowed = OrgClock.Today(org).AddDays(-1);
        if (periodEnd > latestAllowed)
        {
            // إقفال اليوم أو المستقبل يمنع بيع اليوم نفسه.
            return BadRequest(new
            {
                message = $"لا تُقفَل مدّة لم تنتهِ بعد — أقصى تاريخ مسموح {latestAllowed:yyyy-MM-dd}.",
            });
        }

        var already = await _db.FiscalClosings
            .Where(c => !c.IsReopened)
            .Select(c => (DateTime?)c.PeriodEnd)
            .ToListAsync();
        if (already.Count > 0 && already.Max() >= periodEnd)
        {
            return BadRequest(new
            {
                message = $"المدّة حتى {already.Max():yyyy-MM-dd} مُقفَلة أصلاً — اختر تاريخاً بعدها.",
            });
        }

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);

        // من بعد آخر إقفال إلى نهاية المدّة: ما أُقفل لا يُقفَل مرّتين.
        var from = already.Count > 0 ? already.Max()!.Value.AddDays(1) : DateTime.MinValue;
        var balances = await BalancesAsync(from, periodEnd);
        var accounts = await _db.Accounts.ToDictionaryAsync(a => a.Id, a => a);

        var lines = new List<(Guid AccountId, decimal Debit, decimal Credit, string? Note)>();
        decimal revenue = 0, expense = 0;

        foreach (var (accountId, net) in balances)
        {
            if (!accounts.TryGetValue(accountId, out var account)) continue;
            if (net == 0) continue;

            // الرصيد يُقفَل بعكسه: حسابٌ رصيده دائن يُقفَل بمدين ومكسه.
            if (account.Type == AccountTypes.Revenue)
            {
                revenue += -net;
                lines.Add((accountId, net < 0 ? -net : 0, net > 0 ? net : 0, "إقفال"));
            }
            else if (account.Type == AccountTypes.Expense)
            {
                expense += net;
                lines.Add((accountId, net < 0 ? -net : 0, net > 0 ? net : 0, "إقفال"));
            }
        }

        if (lines.Count == 0)
        {
            return BadRequest(new
            {
                message = "لا حركة في هذه المدّة — لا شيء يُقفَل.",
            });
        }

        var net_ = revenue - expense;

        await using var transaction = await _db.Database.BeginTransactionAsync();

        // الأرباح المحتجزة تأخذ الفرق: دائنةً بالربح، مدينةً بالخسارة.
        var closing = new FiscalClosing
        {
            OrganizationId = orgId,
            PeriodEnd = periodEnd,
            NetResult = net_,
            ClosedBy = CurrentUserId(),
        };

        JournalEntry entry;
        try
        {
            entry = await Ledger.PostToAccountsAsync(_db, orgId, null,
                JournalSources.Closing, closing.Id,
                $"إقفال المدّة حتى {periodEnd:yyyy-MM-dd}",
                lines,
                new[]
                {
                    new PostingLine(AccountRoles.RetainedEarnings,
                        net_ < 0 ? -net_ : 0, net_ > 0 ? net_ : 0, "نتيجة المدّة"),
                },
                CurrentUserId(), periodEnd);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        await _db.SaveChangesAsync();

        closing.JournalEntryId = entry.Id;
        _db.FiscalClosings.Add(closing);
        _db.LogAudit(orgId, CurrentUserId(), "fiscal.closed", "fiscal_closings", closing.Id,
            newValues: new { PeriodEnd = periodEnd, NetResult = net_, Lines = lines.Count });
        await _db.SaveChangesAsync();

        await transaction.CommitAsync();

        return (await ToClosingDtosAsync(new List<FiscalClosing> { closing })).First();
    }

    /// <summary>
    /// فتح إقفال — بقرار صريح مسجَّل.
    ///
    /// <para>خطأٌ يُكتشف بعد الإقفال حالة واقعية، ومنعُ الفتح إلى الأبد يدفع
    /// المحاسب إلى تصحيحه في سنةٍ لا يخصّها — فيفسد الاثنتان.</para>
    ///
    /// <para><b>ولا يُحذف الصفّ:</b> من راجع الدفتر يجب أن يرى أن السنة
    /// أُقفلت ثم فُتحت ولماذا، لا أن يجدها مفتوحة كأن شيئاً لم يكن. وقيد
    /// الإقفال يُعكَس فتعود الأرصدة كما كانت.</para>
    /// </summary>
    [HttpPost("closings/{id:guid}/reopen")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Reopen(Guid id, ReopenClosingRequest request)
    {
        var reason = (request.Reason ?? "").Trim();
        if (reason.Length == 0)
        {
            return BadRequest(new { message = "سبب الفتح إلزامي" });
        }

        var closing = await _db.FiscalClosings.FirstOrDefaultAsync(c => c.Id == id);
        if (closing is null) return NotFound();
        if (closing.IsReopened) return BadRequest(new { message = "هذا الإقفال مفتوح أصلاً" });

        await using var transaction = await _db.Database.BeginTransactionAsync();

        // العلم أولاً ثم عكس القيد: العكس يمرّ بحارس المدّة المُقفَلة، ولو
        // بقي القفل قائماً لرفض عكس قيدٍ داخله — فيستحيل الفتح إلى الأبد.
        closing.IsReopened = true;
        closing.ReopenReason = reason;
        closing.ReopenedBy = CurrentUserId();
        closing.ReopenedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        if (closing.JournalEntryId is { } entryId)
        {
            try
            {
                await Ledger.ReverseAsync(_db, entryId, $"فتح إقفال {closing.PeriodEnd:yyyy-MM-dd} — {reason}",
                    CurrentUserId());
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        _db.LogAudit(closing.OrganizationId, CurrentUserId(), "fiscal.reopened",
            "fiscal_closings", closing.Id, newValues: new { closing.PeriodEnd, Reason = reason });
        await _db.SaveChangesAsync();

        await transaction.CommitAsync();
        return NoContent();
    }

    private async Task<List<FiscalClosingDto>> ToClosingDtosAsync(List<FiscalClosing> closings)
    {
        if (closings.Count == 0) return new List<FiscalClosingDto>();

        var userIds = closings
            .SelectMany(c => new[] { c.ClosedBy, c.ReopenedBy })
            .Where(u => u.HasValue).Select(u => u!.Value).Distinct().ToList();
        var users = userIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        return closings.Select(c => new FiscalClosingDto(
            c.Id, c.PeriodEnd, c.NetResult, c.JournalEntryId,
            c.ClosedBy is null ? null : users.GetValueOrDefault(c.ClosedBy.Value),
            c.ClosedAt, c.IsReopened, c.ReopenReason,
            c.ReopenedBy is null ? null : users.GetValueOrDefault(c.ReopenedBy.Value),
            c.ReopenedAt)).ToList();
    }

    /// <summary>
    /// صافي (مدين − دائن) لكل حساب في مدّة.
    ///
    /// <para>مشتركة بين ميزان المراجعة وقائمة الدخل والميزانية: ثلاثة
    /// تقارير تقرأ الشيء نفسه، وحسابُه ثلاث مرّات يعني ثلاثة أماكن تنحرف.
    /// </para>
    /// </summary>
    private async Task<Dictionary<Guid, decimal>> BalancesAsync(DateTime from, DateTime to)
    {
        var rows = await _db.JournalEntryLines
            .Where(l => _db.JournalEntries.Any(e =>
                e.Id == l.JournalEntryId && e.EntryDate >= from && e.EntryDate <= to))
            .GroupBy(l => l.AccountId)
            .Select(g => new
            {
                AccountId = g.Key,
                Net = g.Sum(l => l.Debit) - g.Sum(l => l.Credit),
            })
            .ToListAsync();

        return rows.ToDictionary(r => r.AccountId, r => r.Net);
    }

    /// <summary>
    /// عكس قيد — التصحيح الوحيد المسموح.
    ///
    /// <para>لا تعديل ولا حذف: دفترٌ يُعدَّل ماضيه لا يصلح لإثبات شيء.</para>
    /// </summary>
    [HttpPost("journal/{id:guid}/reverse")]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<JournalEntryDto>> Reverse(Guid id, ReverseEntryRequest request)
    {
        var reason = (request.Reason ?? "").Trim();
        if (reason.Length == 0)
        {
            // السبب إلزامي: قيدٌ عكسي بلا سبب يترك من يراجع الدفتر أمام
            // رقمين متقابلين لا يعرف لماذا كُتبا.
            return BadRequest(new { message = "سبب العكس إلزامي" });
        }

        JournalEntry reversal;
        try
        {
            reversal = await Ledger.ReverseAsync(_db, id, reason, CurrentUserId());
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }

        _db.LogAudit(reversal.OrganizationId, CurrentUserId(), "journal.reversed",
            "journal_entries", id, newValues: new { Reason = reason, reversal.Number });
        await _db.SaveChangesAsync();

        return (await ToDtosAsync(new List<JournalEntry> { reversal })).First();
    }

    private async Task<List<JournalEntryDto>> ToDtosAsync(List<JournalEntry> entries)
    {
        if (entries.Count == 0) return new List<JournalEntryDto>();

        var accountIds = entries.SelectMany(e => e.Lines).Select(l => l.AccountId).Distinct().ToList();
        var accounts = await _db.Accounts
            .Where(a => accountIds.Contains(a.Id))
            .Select(a => new { a.Id, a.Code, a.Name })
            .ToDictionaryAsync(a => a.Id, a => a);

        var userIds = entries.Where(e => e.CreatedBy.HasValue).Select(e => e.CreatedBy!.Value).Distinct().ToList();
        var users = userIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        var ids = entries.Select(e => e.Id).ToList();
        var reversed = await _db.JournalEntries
            .Where(e => e.ReversesEntryId != null && ids.Contains(e.ReversesEntryId!.Value))
            .Select(e => e.ReversesEntryId!.Value)
            .ToListAsync();

        return entries.Select(e => new JournalEntryDto(
            e.Id, e.Number, e.EntryDate, e.Source, e.SourceId, e.Description,
            e.ReversesEntryId, reversed.Contains(e.Id),
            e.CreatedBy is null ? null : users.GetValueOrDefault(e.CreatedBy.Value),
            e.CreatedAt,
            e.Lines.Select(l => new JournalLineDto(
                l.AccountId,
                accounts.GetValueOrDefault(l.AccountId)?.Code ?? "-",
                accounts.GetValueOrDefault(l.AccountId)?.Name ?? "-",
                l.Debit, l.Credit, l.Note)).ToList())).ToList();
    }

    /// <summary>
    /// يرفض حين تكون المحاسبة غير مفعَّلة فعلياً للمنظمة.
    ///
    /// <para>يقيس بـ<see cref="Ledger.IsEnabled"/> لا بـ<c>RequireModule</c>:
    /// الأخير يمرّر مالك المنصّة بلا فحص، والترحيل الآلي لا يمرّره — فيقعان
    /// على حالتين متناقضتين ما لم يُقَس بمقياسٍ واحد.</para>
    /// </summary>
    private async Task<ActionResult?> LedgerDisabledAsync()
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        var license = await _db.Licenses.FirstOrDefaultAsync();
        if (org is not null && Ledger.IsEnabled(org, license)) return null;

        return BadRequest(new
        {
            message = "وحدة المحاسبة غير مفعَّلة لهذه المنظمة — "
                + $"إصدارها «{org?.Edition ?? "غير معروف"}». "
                + "بذرُ دليل هنا يُنشئ دفتراً تصله القيود اليدوية ولا تصله قيود البيع.",
        });
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
