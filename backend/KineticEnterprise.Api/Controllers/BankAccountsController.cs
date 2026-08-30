using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record BankAccountDto(
    Guid Id, string Name, string? AccountNumber, Guid? LedgerAccountId,
    string? LedgerAccountCode, bool IsActive,
    /// الرصيد من الدفتر لا من عمود — راجع WalletBalances لنفس المبدأ.
    decimal Balance);

public record CreateBankAccountRequest(string Name, string? AccountNumber);
public record UpdateBankAccountRequest(string Name, string? AccountNumber, bool IsActive);

/// <summary>
/// الحسابات المصرفية.
///
/// <para><b>الثقب الذي تسدّه:</b> كل ما يُدفع أو يُقبَض كان يُقيَّد على
/// «الصندوق» — النقد والحوالة سواء. فتظهر النقدية الدفترية أعلى ممّا في
/// الدرج بمقدار كل حوالة، ولا يُعرف رصيد المصرف إطلاقاً.</para>
///
/// <para>مقيَّدة بوحدة <c>accounting</c>: حسابٌ مصرفي بلا دفتر يُقابله ليس
/// إلا اسماً في قائمة.</para>
/// </summary>
[RequireModule("accounting")]
[ApiController]
[Route("api/bank-accounts")]
[Authorize]
public class BankAccountsController : ControllerBase
{
    private readonly AppDbContext _db;
    public BankAccountsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<BankAccountDto>>> GetAll()
    {
        var banks = await _db.BankAccounts.OrderBy(b => b.Name).ToListAsync();
        if (banks.Count == 0) return new List<BankAccountDto>();

        var accountIds = banks.Where(b => b.LedgerAccountId.HasValue)
            .Select(b => b.LedgerAccountId!.Value).ToList();
        var accounts = await _db.Accounts.Where(a => accountIds.Contains(a.Id))
            .Select(a => new { a.Id, a.Code })
            .ToDictionaryAsync(a => a.Id, a => a.Code);

        // الأرصدة من الدفتر — استعلام تجميع واحد لا واحد لكل مصرف.
        var balances = await _db.JournalEntryLines
            .Where(l => accountIds.Contains(l.AccountId))
            .GroupBy(l => l.AccountId)
            .Select(g => new { AccountId = g.Key, Net = g.Sum(l => l.Debit) - g.Sum(l => l.Credit) })
            .ToDictionaryAsync(x => x.AccountId, x => x.Net);

        return banks.Select(b => new BankAccountDto(
            b.Id, b.Name, b.AccountNumber, b.LedgerAccountId,
            b.LedgerAccountId is null ? null : accounts.GetValueOrDefault(b.LedgerAccountId.Value),
            b.IsActive,
            b.LedgerAccountId is null ? 0 : balances.GetValueOrDefault(b.LedgerAccountId.Value))).ToList();
    }

    /// <summary>
    /// مصرف جديد — ويُنشأ له حسابه في الدليل تحت «المصارف».
    ///
    /// <para><b>ولماذا تلقائياً:</b> تركُه للمستخدم يعني حساباً مصرفياً بلا
    /// أثر محاسبي، أو مربوطاً بحسابٍ خاطئ يُفسد الميزانية بصمت. ورمزه يتبع
    /// آخر رمز تحت «المصارف» فلا يتعارض.</para>
    /// </summary>
    [HttpPost]
    [Authorize(Roles = "super_admin")]
    public async Task<ActionResult<BankAccountDto>> Create(CreateBankAccountRequest request)
    {
        var name = (request.Name ?? "").Trim();
        if (name.Length == 0) return BadRequest(new { message = "اسم المصرف إلزامي" });

        var orgId = Guid.Parse(User.FindFirstValue("organization_id")!);

        // الدليل قد لا يكون مبذوراً بعد.
        await ChartOfAccounts.SeedAsync(_db, orgId);

        var parent = await _db.Accounts.FirstOrDefaultAsync(a => a.Code == "1102");
        if (parent is null)
        {
            return BadRequest(new
            {
                message = "لا حساب «المصارف» (1102) في الدليل — أنشئ الدليل الافتراضي أولاً.",
            });
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        // الرمز التالي تحت المصارف: 110201، 110202…
        var siblings = await _db.Accounts.Where(a => a.ParentId == parent.Id).Select(a => a.Code).ToListAsync();
        var next = 1;
        foreach (var code in siblings)
        {
            if (code.Length > 4 && int.TryParse(code[4..], out var n) && n >= next) next = n + 1;
        }

        var ledger = new Account
        {
            OrganizationId = orgId,
            Code = $"1102{next:00}",
            Name = name,
            ParentId = parent.Id,
            Type = parent.Type,
            IsPostable = true,
            // ليس حساب نظام: المستخدم أنشأه ويستطيع إيقافه.
            IsSystem = false,
        };
        _db.Accounts.Add(ledger);

        // الأب يفقد قابلية الترحيل بمجرّد أن يُولَد له ابن — رصيدُه يجب أن
        // يبقى مجموع أبنائه.
        parent.IsPostable = false;
        await _db.SaveChangesAsync();

        var bank = new BankAccount
        {
            OrganizationId = orgId,
            Name = name,
            AccountNumber = string.IsNullOrWhiteSpace(request.AccountNumber)
                ? null : request.AccountNumber.Trim(),
            LedgerAccountId = ledger.Id,
        };
        _db.BankAccounts.Add(bank);
        _db.LogAudit(orgId, CurrentUserId(), "bank_account.created", "bank_accounts", bank.Id,
            newValues: new { bank.Name, LedgerCode = ledger.Code });
        await _db.SaveChangesAsync();

        await transaction.CommitAsync();

        return new BankAccountDto(bank.Id, bank.Name, bank.AccountNumber,
            bank.LedgerAccountId, ledger.Code, bank.IsActive, 0);
    }

    /// <summary>
    /// تعديل الاسم أو الرقم أو الإيقاف.
    ///
    /// <para>ولا يُحذف: قيوده في الدفتر تشير إلى حسابه، وحذفُه يترك قيوداً
    /// بلا حساب. والإيقاف يُخفيه من الاختيار ويُبقي تاريخه.</para>
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Roles = "super_admin")]
    public async Task<IActionResult> Update(Guid id, UpdateBankAccountRequest request)
    {
        var bank = await _db.BankAccounts.FirstOrDefaultAsync(b => b.Id == id);
        if (bank is null) return NotFound();

        var name = (request.Name ?? "").Trim();
        if (name.Length == 0) return BadRequest(new { message = "اسم المصرف إلزامي" });

        bank.Name = name;
        bank.AccountNumber = string.IsNullOrWhiteSpace(request.AccountNumber)
            ? null : request.AccountNumber.Trim();
        bank.IsActive = request.IsActive;

        // الاسم يتبعه في الدليل: اسمان لشيء واحد يُربكان من يقرأ الميزان.
        if (bank.LedgerAccountId is { } ledgerId)
        {
            var ledger = await _db.Accounts.FirstOrDefaultAsync(a => a.Id == ledgerId);
            if (ledger is not null)
            {
                ledger.Name = name;
                ledger.IsActive = request.IsActive;
            }
        }

        _db.LogAudit(bank.OrganizationId, CurrentUserId(), "bank_account.updated", "bank_accounts", id,
            newValues: new { bank.Name, bank.IsActive });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
