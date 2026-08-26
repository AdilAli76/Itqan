using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record ExpenseDto(
    Guid Id, Guid BranchId, string BranchName, string Category, decimal Amount,
    string? Note, Guid? AccountId, string? AccountName,
    DateTime SpentOn,
    string? CreatedByName, DateTime CreatedAt);

public record CreateExpenseRequest(
    Guid BranchId, string Category, decimal Amount, string? Note, Guid? AccountId,
    /// تاريخ الصرف الفعلي. NULL = اليوم. راجع Expense.SpentOn.
    DateTime? SpentOn = null);

public record ExpensePageDto(List<ExpenseDto> Items, decimal Total, int TotalCount, int Page, int PageSize);

/// <summary>
/// المصروفات — إيجار، رواتب، كهرباء، نقل.
///
/// <para><b>جدول ميّت أُحيي:</b> <c>expenses</c> كان في المخطّط منذ اليوم
/// الأول بلا كيان ولا وحدة تحكّم ولا شاشة. أي أن «المالية المبسّطة» الموعودة
/// في ARCHITECTURE.md §2.8 لم تُبنَ. والتاجر الذي يدفع إيجاراً من درج الكاشير
/// لا يجد له مكاناً، فيُسجّله على ورقة أو لا يسجّله — وحينها يقول تقرير
/// الأرباح ربحاً ليس ربحاً.</para>
///
/// <para><b>ولا حذف ولا تعديل:</b> المصروف حركة مالية وقعت. تصحيحه بمصروف
/// عكسي لا بمحوه — نفس حرمة القيد في الدفاتر الأخرى. ولو حُذف بعد ترحيله
/// لبقي قيده في دفتر اليومية بلا مستند يفسّره.</para>
/// </summary>
[ApiController]
[Route("api/expenses")]
[Authorize]
public class ExpensesController : ControllerBase
{
    private readonly AppDbContext _db;
    public ExpensesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<ExpensePageDto>> GetAll(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] Guid? branchId,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);

        // سياسة العزل تحصر الصفوف في منظمة الطالب وفرعه.
        var query = _db.Expenses.AsQueryable();
        // بتاريخ الصرف لا الإدخال: من يفلتر بشهرٍ يريد مصروف ذلك الشهر،
        // لا ما أُدخل فيه من مصروفات شهور أخرى.
        if (from is { } f) query = query.Where(e => e.SpentOn >= f.Date);
        if (to is { } t) query = query.Where(e => e.SpentOn < t.Date.AddDays(1));
        if (branchId is { } b) query = query.Where(e => e.BranchId == b);

        var totalCount = await query.CountAsync();
        // الإجمالي على الفلتر كلّه لا على الصفحة: من يفلتر بشهرٍ يريد مصروف
        // الشهر، ومجموع خمسين صفاً من ثلاثمئة رقمٌ لا معنى له.
        var total = await query.SumAsync(e => (decimal?)e.Amount) ?? 0;

        var items = await query
            .OrderByDescending(e => e.SpentOn)
            .ThenByDescending(e => e.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var branchIds = items.Select(e => e.BranchId).Distinct().ToList();
        var branches = await _db.Branches.Where(br => branchIds.Contains(br.Id))
            .ToDictionaryAsync(br => br.Id, br => br.Name);

        var accountIds = items.Where(e => e.AccountId.HasValue).Select(e => e.AccountId!.Value).Distinct().ToList();
        var accounts = accountIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.Accounts.Where(a => accountIds.Contains(a.Id))
                .ToDictionaryAsync(a => a.Id, a => $"{a.Code} — {a.Name}");

        var userIds = items.Where(e => e.CreatedBy.HasValue).Select(e => e.CreatedBy!.Value).Distinct().ToList();
        var users = userIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        return new ExpensePageDto(
            items.Select(e => new ExpenseDto(
                e.Id, e.BranchId, branches.GetValueOrDefault(e.BranchId, "-"),
                e.Category, e.Amount, e.Note, e.AccountId,
                e.AccountId is null ? null : accounts.GetValueOrDefault(e.AccountId.Value),
                e.SpentOn,
                e.CreatedBy is null ? null : users.GetValueOrDefault(e.CreatedBy.Value),
                e.CreatedAt)).ToList(),
            total, totalCount, page, pageSize);
    }

    /// <summary>
    /// تسجيل مصروف، وترحيله محاسبياً إن كانت الوحدة مفعّلة.
    ///
    /// <para><b>القيد:</b></para>
    /// <code>
    ///   من ح/ المصروف   (الحساب المختار أو «مصروفات عمومية»)
    ///       إلى ح/ الصندوق
    /// </code>
    ///
    /// <para><b>والدفع من الصندوق افتراضٌ مقصود:</b> لا حسابات بنكية مربوطة
    /// في النظام بعد. ومصروفٌ دُفع بحوالة سيُقيَّد على الصندوق خطأً — وهذا
    /// أهون من ألّا يُقيَّد أصلاً، ويُصحَّح بقيد يدوي. لكنه يبقى نقصاً
    /// معلوماً لا مفاجأة.</para>
    /// </summary>
    [HttpPost]
    [RequirePermission("expenses.manage")]
    public async Task<ActionResult<ExpenseDto>> Create(CreateExpenseRequest request)
    {
        var category = (request.Category ?? "").Trim();
        if (category.Length == 0)
        {
            return BadRequest(new { message = "بند المصروف إلزامي" });
        }
        if (request.Amount <= 0)
        {
            return BadRequest(new { message = "المبلغ يجب أن يكون أكبر من صفر" });
        }

        var branch = await _db.Branches.FirstOrDefaultAsync(b => b.Id == request.BranchId);
        if (branch is null) return BadRequest(new { message = "الفرع غير موجود" });

        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        Account? account = null;
        if (request.AccountId is { } accountId)
        {
            account = await _db.Accounts.FirstOrDefaultAsync(a => a.Id == accountId);
            if (account is null) return BadRequest(new { message = "الحساب غير موجود" });

            // حسابٌ من غير «الاستخدامات» يُفسد قائمة الدخل بصمت: مصروفٌ
            // مُقيَّد على أصلٍ يجعل المصروفات أقلّ والأصول أكبر، ولا يظهر
            // الخلل إلا في الميزانية بعد أشهر.
            if (account.Type != AccountTypes.Expense)
            {
                return BadRequest(new { message = "اختر حساباً من «الاستخدامات» — هذا الحساب من نوع آخر" });
            }
            if (!account.IsPostable)
            {
                return BadRequest(new { message = "هذا حساب تجميعي — اختر حساباً فرعياً تحته" });
            }
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        var expense = new Expense
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            BranchId = request.BranchId,
            Category = category,
            Amount = request.Amount,
            Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim(),
            AccountId = account?.Id,
            SpentOn = request.SpentOn?.Date ?? DateTime.UtcNow.Date,
            CreatedBy = CurrentUserId(),
        };
        _db.Expenses.Add(expense);
        _db.LogAudit(expense.OrganizationId, CurrentUserId(), "expense.created", "expenses", expense.Id,
            newValues: new { expense.Category, expense.Amount, expense.BranchId });
        await _db.SaveChangesAsync();

        await PostExpenseAsync(expense, org, account);

        await transaction.CommitAsync();

        return new ExpenseDto(expense.Id, branch.Id, branch.Name, expense.Category, expense.Amount,
            expense.Note, expense.AccountId,
            account is null ? null : $"{account.Code} — {account.Name}",
            expense.SpentOn, null, expense.CreatedAt);
    }

    /// <summary>
    /// قيد المصروف — داخل معاملة المصروف نفسه.
    ///
    /// <para>مصروفٌ بلا قيده ثقبٌ في الدفتر، ومصروفٌ سُجّل ثم فشل قيده يجعل
    /// الدفتر يقول ربحاً أعلى من الحقيقة. فإمّا يقعان معاً أو لا يقع
    /// شيء.</para>
    /// </summary>
    private async Task PostExpenseAsync(Expense expense, Organization org, Account? account)
    {
        var license = await _db.Licenses.FirstOrDefaultAsync();
        if (!Ledger.IsEnabled(org, license)) return;

        var cashSide = new[] { new PostingLine(AccountRoles.Cash, 0, expense.Amount, expense.Category) };

        if (account is null)
        {
            // بلا حساب مختار: الدور العامّ «مصروفات عمومية» — يقول الحقيقة
            // صراحةً بأن المصروف لم يُبوَّب، بدل أن يُنسَب إلى بندٍ بعينه ظنّاً.
            await Ledger.PostAsync(_db, expense.OrganizationId, expense.BranchId,
                JournalSources.Expense, expense.Id,
                $"مصروف: {expense.Category}",
                cashSide.Prepend(new PostingLine(AccountRoles.GeneralExpense, expense.Amount, 0, expense.Category)),
                CurrentUserId(), expense.SpentOn);
        }
        else
        {
            // حسابٌ بعينه لا دور: المصروف يختار حسابه لحظة تسجيله (إيجار على
            // «إيجارات»، راتب على «رواتب»)، ولا دور ثابتاً لكلٍّ منهما.
            await Ledger.PostToAccountsAsync(_db, expense.OrganizationId, expense.BranchId,
                JournalSources.Expense, expense.Id,
                $"مصروف: {expense.Category}",
                new[] { (account.Id, expense.Amount, 0m, (string?)expense.Category) },
                cashSide,
                CurrentUserId(), expense.SpentOn);
        }

        await _db.SaveChangesAsync();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
