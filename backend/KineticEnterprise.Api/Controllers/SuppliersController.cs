using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record SupplierPaymentDto(
    Guid Id, decimal Amount, string Method, string? Reference, string? Note,
    DateTime PaidOn, string? CreatedByName, DateTime CreatedAt);

public record CreateSupplierPaymentRequest(
    Guid BranchId, decimal Amount, string Method, DateTime? PaidOn,
    string? Reference, string? Note);

/// كشف حساب مورّد — الرصيد مُشتقّ لا مخزَّن.
public record SupplierStatementDto(
    Guid SupplierId, string SupplierName,
    /// ما أدخله المستخدم يدوياً عند إنشاء المورّد — دَينٌ سابق للنظام.
    decimal OpeningBalance,
    /// إجمالي ما استُلم منه فعلاً (من مستندات الاستلام).
    decimal Received,
    /// ما أُعيد إليه.
    decimal Returned,
    /// ما سُدِّد له.
    decimal Paid,
    /// الافتتاحي + المستلَم − المُعاد − المسدَّد. موجب = عليك له.
    decimal Balance,
    List<SupplierPaymentDto> Payments);

/// <summary>
/// نفس نمط ProductsController بالضبط — Security Policy على جدول suppliers
/// (fn_OrgOnlyPredicate) تتكفّل بعزل المنظمة تلقائياً.
/// </summary>
[RequireModule("inventory")]
[ApiController]
[Route("api/suppliers")]
[Authorize]
public class SuppliersController : ControllerBase
{
    private readonly AppDbContext _db;
    public SuppliersController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<Supplier>>> GetAll([FromQuery] string? search)
    {
        var query = _db.Suppliers.Where(s => !s.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(s => s.Name.Contains(search) || (s.Phone != null && s.Phone.Contains(search)));
        }
        return await query.OrderBy(s => s.Name).ToListAsync();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<Supplier>> GetById(Guid id)
    {
        var supplier = await _db.Suppliers.FindAsync(id);
        return supplier is null ? NotFound() : supplier;
    }

    /// <summary>
    /// كشف حساب المورّد — الرصيد **مُشتقّ لا مخزَّن**.
    ///
    /// <para><b>العطب الذي يصلحه:</b> <c>suppliers.balance</c> رقمٌ يكتبه
    /// المستخدم بيده في نموذج المورّد **ولا يحدّثه شيء**. فيبقى كما كُتب
    /// مهما اشتُري وسُدِّد — رقمٌ يبدو رصيداً وليس رصيداً. وهو نفس عطب رصيد
    /// المحفظة الذي عُولج بجعله مجموع دفتره.</para>
    ///
    /// <para>فصار يُقرأ **رصيداً افتتاحياً** (دَينٌ سابق للنظام)، والرصيد
    /// الحالي يُحسَب: الافتتاحي + ما استُلم − ما أُعيد − ما سُدِّد.</para>
    /// </summary>
    [HttpGet("{id:guid}/statement")]
    public async Task<ActionResult<SupplierStatementDto>> GetStatement(Guid id)
    {
        var supplier = await _db.Suppliers.FirstOrDefaultAsync(s => s.Id == id && !s.IsDeleted);
        if (supplier is null) return NotFound();

        // ما استُلم فعلاً — من مستندات الاستلام لا من أوامر الشراء: الأمر
        // قد يبقى مفتوحاً بلا بضاعة، وقيدُه ديناً يجعلك مديناً بما لم يصل.
        var received = await _db.PurchaseReceiptItems
            .Where(ri => _db.PurchaseReceipts.Any(r => r.Id == ri.PurchaseReceiptId
                && _db.PurchaseOrders.Any(o => o.Id == r.PurchaseOrderId && o.SupplierId == id)))
            .SumAsync(ri => (decimal?)(ri.Quantity * ri.UnitCost)) ?? 0;

        // ما أُعيد إليه — من دفتر المخزون، فهو المصدر الوحيد لما خرج فعلاً.
        var returned = await _db.StockLedgerEntries
            .Where(e => e.SourceType == StockSourceTypes.PurchaseReturn
                     && _db.PurchaseOrders.Any(o => o.Id == e.SourceId && o.SupplierId == id))
            .SumAsync(e => (decimal?)(-e.QuantityChange * e.UnitCost)) ?? 0;

        var payments = await _db.SupplierPayments
            .Where(p => p.SupplierId == id)
            .OrderByDescending(p => p.PaidOn)
            .ToListAsync();

        var userIds = payments.Where(p => p.CreatedBy.HasValue).Select(p => p.CreatedBy!.Value).Distinct().ToList();
        var users = userIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        var paid = payments.Sum(p => p.Amount);

        return new SupplierStatementDto(
            supplier.Id, supplier.Name,
            supplier.Balance, received, returned, paid,
            supplier.Balance + received - returned - paid,
            payments.Select(p => new SupplierPaymentDto(
                p.Id, p.Amount, p.Method, p.Reference, p.Note, p.PaidOn,
                p.CreatedBy is null ? null : users.GetValueOrDefault(p.CreatedBy.Value),
                p.CreatedAt)).ToList());
    }

    /// <summary>
    /// سداد لمورّد.
    ///
    /// <code>
    ///   من ح/ الموردون
    ///       إلى ح/ الصندوق
    /// </code>
    ///
    /// <para>ولا يُمنع السداد الزائد عن الرصيد: دفعةٌ مقدَّمة على شحنة قادمة
    /// حالة واقعية، والرصيد السالب يقولها بوضوح (المورّد مدينٌ لك). ومنعُه
    /// يدفع المحاسب إلى تسجيله خارج النظام.</para>
    /// </summary>
    [HttpPost("{id:guid}/payments")]
    [RequirePermission("purchasing.manage")]
    public async Task<ActionResult<SupplierPaymentDto>> AddPayment(
        Guid id, CreateSupplierPaymentRequest request)
    {
        if (request.Amount <= 0)
        {
            return BadRequest(new { message = "المبلغ يجب أن يكون أكبر من صفر" });
        }
        var method = SupplierPaymentMethods.All.Contains(request.Method)
            ? request.Method
            : SupplierPaymentMethods.Cash;

        var supplier = await _db.Suppliers.FirstOrDefaultAsync(s => s.Id == id && !s.IsDeleted);
        if (supplier is null) return NotFound();

        var branch = await _db.Branches.FirstOrDefaultAsync(b => b.Id == request.BranchId);
        if (branch is null) return BadRequest(new { message = "الفرع غير موجود" });

        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        await using var transaction = await _db.Database.BeginTransactionAsync();

        var payment = new SupplierPayment
        {
            OrganizationId = supplier.OrganizationId,
            BranchId = request.BranchId,
            SupplierId = id,
            Amount = request.Amount,
            Method = method,
            Reference = string.IsNullOrWhiteSpace(request.Reference) ? null : request.Reference.Trim(),
            Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim(),
            PaidOn = request.PaidOn?.Date ?? DateTime.UtcNow.Date,
            CreatedBy = CurrentUserId(),
        };
        _db.SupplierPayments.Add(payment);
        _db.LogAudit(supplier.OrganizationId, CurrentUserId(), "supplier.payment", "suppliers", id,
            newValues: new { supplier.Name, payment.Amount, payment.Method, payment.PaidOn });
        await _db.SaveChangesAsync();

        var license = await _db.Licenses.FirstOrDefaultAsync();
        if (Ledger.IsEnabled(org, license))
        {
            await Ledger.PostAsync(_db, supplier.OrganizationId, request.BranchId,
                JournalSources.Payment, payment.Id,
                $"سداد للمورّد {supplier.Name}",
                new[]
                {
                    new PostingLine(AccountRoles.Payables, payment.Amount, 0),
                    new PostingLine(AccountRoles.Cash, 0, payment.Amount,
                        method == SupplierPaymentMethods.Bank ? "حوالة" : null),
                },
                CurrentUserId(), payment.PaidOn);
            await _db.SaveChangesAsync();
        }

        await transaction.CommitAsync();

        return new SupplierPaymentDto(payment.Id, payment.Amount, payment.Method,
            payment.Reference, payment.Note, payment.PaidOn, null, payment.CreatedAt);
    }

    [HttpPost]
    [RequirePermission("suppliers.manage")]
    public async Task<ActionResult<Supplier>> Create(Supplier supplier)
    {
        supplier.OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!);
        _db.Suppliers.Add(supplier);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(GetById), new { id = supplier.Id }, supplier);
    }

    [HttpPut("{id:guid}")]
    [RequirePermission("suppliers.manage")]
    public async Task<IActionResult> Update(Guid id, Supplier update)
    {
        var supplier = await _db.Suppliers.FindAsync(id);
        if (supplier is null) return NotFound();

        supplier.Name = update.Name;
        supplier.Phone = update.Phone;
        supplier.Balance = update.Balance;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // حذف فعلي غير مسموح به (راجع ARCHITECTURE.md §3.2) — منتجات قديمة قد
    // تشير لهذا المورّد، فالحذف الفعلي يكسر سجلها التاريخي. فقط Soft Delete.
    [HttpDelete("{id:guid}")]
    [RequirePermission("suppliers.delete")]
    public async Task<IActionResult> SoftDelete(Guid id)
    {
        var supplier = await _db.Suppliers.FindAsync(id);
        if (supplier is null) return NotFound();

        supplier.IsDeleted = true;
        _db.LogAudit(supplier.OrganizationId, CurrentUserId(), "supplier.deleted", "suppliers", supplier.Id,
            oldValues: new { supplier.Name });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
