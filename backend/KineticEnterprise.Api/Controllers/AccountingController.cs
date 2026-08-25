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
        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);
        var seeded = await ChartOfAccounts.SeedAsync(_db, orgId);
        return Ok(new
        {
            seeded,
            message = seeded ? "بُذر دليل الحسابات الافتراضي" : "الدليل موجود — لم يُغيَّر شيء",
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
        var fromDate = from?.Date ?? new DateTime(DateTime.UtcNow.Year, 1, 1);
        var toDate = to?.Date ?? DateTime.UtcNow.Date;

        var accounts = await _db.Accounts.ToDictionaryAsync(a => a.Id, a => a);

        var sums = await _db.JournalEntryLines
            .Where(l => _db.JournalEntries.Any(e =>
                e.Id == l.JournalEntryId && e.EntryDate >= fromDate && e.EntryDate <= toDate))
            .GroupBy(l => l.AccountId)
            .Select(g => new
            {
                AccountId = g.Key,
                Debit = g.Sum(l => l.Debit),
                Credit = g.Sum(l => l.Credit),
            })
            .ToListAsync();

        var rows = new List<TrialBalanceRow>();
        foreach (var s in sums)
        {
            if (!accounts.TryGetValue(s.AccountId, out var account)) continue;

            // الصافي في عموده الطبيعي: حسابٌ رصيده مدين يُعرض في عمود المدين
            // وحده لا في العمودين معاً. عرض المجموعين الخامين يجعل كل حساب
            // يظهر في العمودين فيصير الميزان غير قابل للقراءة.
            var net = s.Debit - s.Credit;
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

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
