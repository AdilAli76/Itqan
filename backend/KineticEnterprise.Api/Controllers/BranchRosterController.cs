using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <summary>حاملُ بطاقةٍ في فرع، كما يُخزَّن على جهاز الكاشير.</summary>
public record RosterCardDto(
    Guid CustomerId, string FullName, string CardCode,
    /// الرصيد لحظة السحب — يُعاد حسابه على الخادم عند المزامنة.
    decimal Balance,
    /// السقف اليومي الفعّال — يُطبَّق محلياً كما يُطبَّق على الخادم.
    decimal DailyCap,
    string? PhotoUrl);

public record BranchRosterDto(
    Guid BranchId, DateTime GeneratedAt, int Count, List<RosterCardDto> Cards);

/// <summary>
/// كشف بطاقات الفرع — ليعمل السحب حين تنقطع الشبكة.
///
/// <para><b>الفجوة:</b> البيع النقدي يعمل بلا اتصال منذ زمن، أمّا السحب من
/// بطاقة فكان ممنوعاً — لأن الجهاز لا يعرف الرصيد. فيقف المنتسب أمام
/// الكاشير ومعه بطاقة فيها رصيد ولا يستطيع الصرف، والشبكة في ليبيا تنقطع
/// كثيراً.</para>
///
/// <para><b>والحلّ أن يُخزَّن كشف الفرع محلياً</b>: البطاقة مربوطة بفرع،
/// والفرع يملك بياناتها. فالكاتب واحد لا اثنان — ولا يُخصم من بطاقةٍ في
/// فرعين معاً أثناء الانقطاع.</para>
///
/// <para><b>⚠ ولا يُصدَّر إلا ما لا رقم سرّي له.</b> نمط <c>pin</c> يحتاج
/// عدّاد محاولاتٍ على الخادم؛ وبدونه يُجرَّب الرقم بلا حدّ على جهازٍ في يد
/// من وجد البطاقة. وهذا القيد لا يُرفَع بتخزينٍ محلّي ولا بغيره — راجع
/// توثيق <c>OfflineQueue</c>.</para>
///
/// <para>ولا بصمة رقمٍ سرّي في الرد إطلاقاً: كشفٌ يحمل البصمات يُسرّبها
/// كلّها بضياع جهازٍ واحد.</para>
/// </summary>
[RequireModule("customers")]
[ApiController]
[Route("api/branch-roster")]
[Authorize]
public class BranchRosterController : ControllerBase
{
    private readonly AppDbContext _db;
    public BranchRosterController(AppDbContext db) => _db = db;

    /// <summary>
    /// كشف بطاقات فرع — يُطلَب دورياً ما دامت الشبكة موصولة.
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<BranchRosterDto>> Get([FromQuery] Guid branchId)
    {
        var org = await _db.Organizations.FirstOrDefaultAsync();
        if (org is null) return BadRequest(new { message = "تعذّر تحديد المنظمة" });

        var branch = await _db.Branches.FirstOrDefaultAsync(b => b.Id == branchId);
        if (branch is null) return NotFound(new { message = "الفرع غير موجود" });

        // بطاقات هذا الفرع وحده. وعميلٌ بلا فرع لا يدخل الكشف: بطاقةٌ بلا
        // موطن قد تُخصَم في فرعين أثناء الانقطاع، وهو عين ما نتجنّبه.
        var customers = await _db.Customers
            .Where(c => !c.IsDeleted
                     && c.BranchId == branchId
                     && c.CardBarcode != null
                     && c.CardBarcode != "")
            .Select(c => new
            {
                c.Id, c.FullName, c.CardBarcode, c.PhotoUrl,
                c.CardMode, c.DailyCap, c.PinHash,
            })
            .ToListAsync();

        // ما له رقم سرّي يُستبعَد — بالنمط الفعّال لا بالمخزَّن: بطاقةٌ
        // نمطها فارغ تتبع افتراضي المنظمة، وقد يكون pin.
        var exportable = customers
            .Where(c =>
            {
                var mode = c.CardMode ?? org.CardModeDefault;
                return mode != CardModes.Pin && c.PinHash is null;
            })
            .ToList();

        if (exportable.Count == 0)
            return new BranchRosterDto(branchId, DateTime.UtcNow, 0, new List<RosterCardDto>());

        var ids = exportable.Select(c => c.Id).ToList();
        var balances = await WalletBalances.ComputeManyAsync(_db, ids);

        var cards = exportable.Select(c => new RosterCardDto(
            c.Id, c.FullName, c.CardBarcode!,
            balances.GetValueOrDefault(c.Id),
            // السقف الفعّال بعد حدود المنظمة — نفس ما يطبّقه الخادم، فلا
            // يقبل الجهاز ما يرفضه عند المزامنة.
            CardModeGate.EffectiveCap(org, new Customer { DailyCap = c.DailyCap }),
            c.PhotoUrl)).ToList();

        return new BranchRosterDto(branchId, DateTime.UtcNow, cards.Count, cards);
    }
}
