using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Authorization;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

public record CreateStockCountRequest(
    Guid BranchId,
    /// periodic (افتراضي) أو initial — راجع StockCount.Kind.
    string? Kind = null,
    /// لا يُدرَج إلا ما لم يُعدّ منذ هذا التاريخ. NULL = كل الأصناف.
    /// هو ما يجعل الجرد الموزَّع ممكناً بدل إغلاق المحل يوماً كاملاً.
    DateTime? NotCountedSince = null);
public record UpdateCountedQuantityRequest(decimal CountedQuantity);

public record StockCountListItemDto(
    Guid Id, Guid BranchId, string BranchName, string Status, string Kind,
    int ItemCount, int VarianceCount, DateTime CreatedAt, DateTime? ClosedAt,
    /// كم سطراً مُسَّ فعلاً — منه تُحسب نسبة التقدّم في القائمة.
    ///
    /// <para><b>ولماذا في القائمة لا في التفصيل وحده:</b> «كم بقي» سؤال
    /// المشرف الدائم أثناء جردٍ موزَّع، وكان يلزمه فتح كل جرد ليعرف. وجردٌ
    /// مفتوح منذ أسبوع عند 3% ليس جرداً بطيئاً بل جردٌ **متروك** — ولا
    /// يُرى ذلك في قائمة تعرض عدد الأصناف وحده.</para>
    int CountedCount);

public record StockCountItemDto(
    Guid Id, Guid ProductId, string ProductName, decimal SystemQuantity, decimal CountedQuantity, decimal Variance,
    /// NULL = لم يُمَسّ بعد. راجع StockCountItem.CountedAt — الكمية وحدها لا
    /// تفرّق بين «عُدَّ وطابق» و«لم يُنظَر إليه».
    DateTime? CountedAt,
    bool AddedDuringCount,
    string? Barcode, string Sku, string UnitBase,
    /// قيمة الفرق بالعملة — الكمية مضروبةً في تكلفة الصنف.
    ///
    /// <para>هي الرقم الذي يُقرَّر عليه: «ناقص 15» لا تقول شيئاً حتى يُعرف
    /// أهي خمسة عشر كيس ملح أم خمس عشرة علبة دواء.</para>
    decimal VarianceValue,
    /// شدّة الفرق — راجع [VarianceSeverity].
    string Severity);

/// <summary>
/// شدّة فرق الجرد: ما الذي يستحقّ أن يُنظر فيه أولاً.
///
/// <para><b>سبب وجودها:</b> جردٌ بمئتي صنف يخرج بأربعين فرقاً، ومن يعتمد
/// الفروقات يقرأ قائمةً كل سطورها متساوية في الشكل. فيُعتمَد الكلّ دفعةً —
/// وفيها سطرٌ واحد يساوي راتب شهر.</para>
///
/// <para><b>وبمحورين لا محور:</b> القيمة أولاً — صنفٌ غالٍ ينقص واحدةً
/// أخطر من رخيصٍ ينقص عشرين، وهي القاعدة المحاسبية. لكن القيمة وحدها
/// تُخفي **السرقة الصغيرة المتكرّرة**: نصف رفٍّ من صنفٍ رخيص اختفى إشارةٌ
/// لا يجوز أن تُصنَّف «منخفضة» لأن ثمنه زهيد. فالشدّة أعلى الاثنتين.</para>
///
/// <para><b>والمرجع الجردُ نفسه لا رقمٌ ثابت:</b> «مئة دينار» فرقٌ جسيم
/// عند بقّالة وتافهٌ عند مخزن جملة، وثابتٌ في الكود يعني إعداداً يضبطه كل
/// عميل — أو لا يضبطه أحد فيبقى بلا معنى. فتُقاس قيمة الفرق **نسبةً إلى
/// قيمة المخزون المعدود**: صنفٌ وحده يمثّل 2% من قيمة الجرد خطأً هو حدثٌ
/// جسيم في أي نشاط مهما كان حجمه.</para>
/// </summary>
public static class VarianceSeverity
{
    public const string None = "none";
    public const string Low = "low";
    public const string Medium = "medium";
    public const string High = "high";

    /// <param name="varianceValue">قيمة الفرق المطلقة بالعملة.</param>
    /// <param name="countValue">قيمة المخزون النظامية للجرد كلّه.</param>
    /// <param name="systemQuantity">الكمية النظامية للصنف — مقام نسبة الكمية.</param>
    /// <param name="variance">فرق الكمية بإشارته.</param>
    public static string Of(decimal varianceValue, decimal countValue, decimal systemQuantity, decimal variance)
    {
        if (variance == 0) return None;

        // قيمة الجرد صفر (كتالوجٌ بلا تكاليف مُدخَلة) تُسقط محور القيمة
        // كلَّه إلى القسمة على صفر. فيبقى محور الكمية وحده — وهو خيرٌ من
        // تصنيفٍ كاذب أو استثناءٍ يُسقط الشاشة.
        var valueShare = countValue > 0 ? varianceValue / countValue : 0m;
        var quantityShare = systemQuantity > 0 ? Math.Abs(variance) / systemQuantity : 1m;

        if (valueShare >= 0.02m || quantityShare >= 0.5m) return High;
        if (valueShare >= 0.005m || quantityShare >= 0.2m) return Medium;
        return Low;
    }
}

public record StockCountDetailDto(
    Guid Id, Guid BranchId, string BranchName, string Status,
    DateTime CreatedAt, DateTime? ClosedAt, List<StockCountItemDto> Items,
    // خطوة اعتماد الفروقات — راجع StockCount.Status.
    string? SubmittedByName, DateTime? SubmittedAt,
    string? ReviewedByName, DateTime? ReviewedAt,
    string? RecountReason, int RecountRounds,
    /// كم سطراً لم يُمَسّ بعد — سؤال الشاشة الميدانية الدائم «كم بقي».
    int UncountedCount,
    /// <summary>
    /// نسبة السطور **المعدودة** التي طابقت النظام — دقّة سجلّ المخزون.
    ///
    /// <para><b>ولماذا من المعدود لا من الكل:</b> الجرد يبدأ بـ
    /// <c>CountedQuantity = SystemQuantity</c>، فسطرٌ لم يره أحد يُحسب
    /// «مطابقاً» — وجردٌ مُسّ فيه عشرة سطور من ثلاثمئة كان سيخرج بدقّة
    /// 97% وهي في الحقيقة دقّة **الجهل**. راجع [StockCountItem.CountedAt].
    /// وNULL حين لا سطر مُسَّ بعد: لا دقّة تُحسَب من لا شيء.</para>
    ///
    /// <para>وتُقرأ مع [UncountedCount] لا وحدها: دقّةٌ 100% على عشرة
    /// سطور ليست جرداً ناجحاً بل جرداً لم يبدأ.</para>
    /// </summary>
    decimal? AccuracyPercent,
    /// قيمة النقص (ما نقص عن النظام) — خسارةٌ مالية معلومة.
    decimal ShortageValue,
    /// قيمة الزيادة — بضاعة ظهرت بلا مستند.
    decimal SurplusValue,
    /// قيمة المخزون النظامية للجرد كلّه — مرجع النسب.
    decimal SystemValue);

public record RecountRequest(string Reason);

/// <param name="Force">
/// إنهاء العدّ رغم بقاء سطور لم تُمَسّ. بلا هذا العلم يُرفض الإنهاء —
/// راجع Submit.
/// </param>
public record SubmitCountRequest(bool Force = false);

/// نتيجة مسح رمز داخل جرد — راجع [ScanCodes] لمعاني Outcome.
public record ScanResultDto(string Outcome, StockCountItemDto? Item, string? Message);

public record AddUnlistedItemRequest(Guid ProductId);

/// <summary>
/// نتائج مسح رمز في الشاشة الميدانية.
///
/// <para>الأربعة مسمّاة صراحةً لأن **شاشات الاستثناء هي المنتج** لا المسار
/// الناجح: العامل الواقف أمام رفّ يحمل ما ليس في قائمته يحتاج زرّاً يقول
/// ذلك، وإلا خرج من النظام وكتب على ورقة — وانتهت صلاحية النظام كلّه.</para>
/// </summary>
public static class ScanCodes
{
    /// الرمز وجد سطره في هذا الجرد — المسار الناجح.
    public const string Found = "found";

    /// عُدَّ في هذه الجولة من قبل. لا يُكتَب فوقه صامتاً: تكرار المسح غالباً
    /// خطأٌ (صنف مُرّ عليه مرّتين)، وأحياناً تصحيح مقصود — والفرق بينهما
    /// يقرّره من يقف أمام الرفّ لا الخادم.
    public const string AlreadyCounted = "already_counted";

    /// الصنف موجود في الكتالوج ولا سطر له في هذا الجرد — حالة الجرد الموزَّع
    /// حين يستبعد NotCountedSince ما عُدَّ حديثاً.
    public const string Unlisted = "unlisted";

    /// لا صنف بهذا الرمز إطلاقاً — باركود غريب أو صنف لم يُسجَّل بعد.
    public const string Unknown = "unknown";
}

/// <summary>
/// راجع DATABASE_TABLES_GUIDE.md §5.7. stock_counts يحمل branch_id واحداً
/// فعلياً (على عكس stock_transfers)، فـ StockCountsPolicy تعزل تلقائياً حسب
/// فرع المستخدم — لا فلترة يدوية مطلوبة هنا.
///
/// <para><b>ولا يُقيَّد بوحدة inventory</b> — وكان مقيَّداً بها. الجرد
/// يُطلَب في كل إصدار: من يمسك عهدةً يُسأل عنها، ولو لم يكن يبيع بضاعة.
/// وتقييده كان يعني أن جهةً على إصدار المحفظة لا تجد الشاشة أصلاً ولا
/// تعرف أنها موجودة في المنتج.</para>
///
/// <para>وما يُعَدّ هو ما في الكتالوج: منظمةٌ لا أصناف عندها تفتح الشاشة
/// فتجدها فارغة — وهو الصحيح، لا خطأ. أما ما لا يُعَدّ هنا فأرصدة
/// البطاقات: مطابقتها شيء آخر لأن رصيد البطاقة التزامٌ في الدفتر لا قطعةٌ
/// على رفّ.</para>
/// </summary>
[ApiController]
[Route("api/stock-counts")]
[Authorize]
public class StockCountsController : ControllerBase
{
    private readonly AppDbContext _db;
    public StockCountsController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<StockCountListItemDto>>> GetAll([FromQuery] string? status)
    {
        var query = _db.StockCounts.Include(c => c.Items).AsQueryable();
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(c => c.Status == status);

        var counts = await query.OrderByDescending(c => c.CreatedAt).ToListAsync();
        var branchIds = counts.Select(c => c.BranchId).Distinct().ToList();
        var branchNames = await _db.Branches.Where(b => branchIds.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name);

        return counts.Select(c => new StockCountListItemDto(
            c.Id, c.BranchId, branchNames.GetValueOrDefault(c.BranchId, "-"), c.Status, c.Kind,
            c.Items.Count, c.Items.Count(i => i.Variance != 0), c.CreatedAt, c.ClosedAt,
            c.Items.Count(i => i.CountedAt != null))).ToList();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<StockCountDetailDto>> GetById(Guid id)
    {
        var count = await _db.StockCounts.Include(c => c.Items).FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        return await ToDetailDto(count);
    }

    /// <summary>
    /// ينشئ جرداً جديداً ويُثبِّت الكمية النظامية الحالية (مجموع كل الدفعات)
    /// لكل صنف في الكتالوج كنقطة بداية — الكمية المعدودة تبدأ مساوية لها،
    /// فيُعدِّل الموظف فقط الأصناف التي يجد فرقاً فيها بدل إعادة إدخال الكل.
    /// </summary>
    [HttpPost]
    [RequirePermission("stock_count.manage")]
    public async Task<ActionResult<StockCountDetailDto>> Create(CreateStockCountRequest request)
    {
        var kind = request.Kind == StockCountKinds.Initial
            ? StockCountKinds.Initial
            : StockCountKinds.Periodic;

        var query = _db.Products.Where(p => !p.IsDeleted);

        // المعيار: ما لم يُعدّ منذ تاريخ كذا — وما لم يُعدّ قطّ يدخل دائماً.
        // استثناؤه كان سيُبقي الأصناف التي لم تُعدّ أبداً خارج كل جرد موزَّع،
        // وهي أولى الأصناف بالعدّ لا آخرها.
        if (request.NotCountedSince is { } since)
        {
            query = query.Where(p => p.LastCountedAt == null || p.LastCountedAt < since);
        }

        var products = await query.ToListAsync();
        if (products.Count == 0)
        {
            return BadRequest(new { message = "لا أصناف تطابق المعيار — لا شيء يُعدّ" });
        }

        var stockByProduct = (await _db.StockLevels.Where(s => s.BranchId == request.BranchId).ToListAsync())
            .GroupBy(s => s.ProductId)
            .ToDictionary(g => g.Key, g => g.Sum(s => s.Quantity));

        var count = new StockCount
        {
            OrganizationId = Guid.Parse(User.FindFirstValue("organization_id")!),
            BranchId = request.BranchId,
            Kind = kind,
            CreatedBy = CurrentUserId(),
        };
        foreach (var product in products)
        {
            var systemQuantity = stockByProduct.GetValueOrDefault(product.Id, 0);
            count.Items.Add(new StockCountItem
            {
                ProductId = product.Id,
                SystemQuantity = systemQuantity,
                // الابتدائي يبدأ بصفر: قبول الافتراضي فيه يجب أن يعني «لا شيء
                // على الرفّ» لا «النظام محقّ» — والنظام لا يعرف شيئاً بعد.
                CountedQuantity = kind == StockCountKinds.Initial ? 0 : systemQuantity,
            });
        }

        _db.StockCounts.Add(count);
        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.created", "stock_counts", count.Id,
            newValues: new { count.BranchId, ItemCount = count.Items.Count });
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetById), new { id = count.Id }, await ToDetailDto(count));
    }

    [HttpPut("{id:guid}/items/{itemId:guid}")]
    [RequirePermission("stock_count.manage")]
    public async Task<IActionResult> UpdateCountedQuantity(Guid id, Guid itemId, UpdateCountedQuantityRequest request)
    {
        var count = await _db.StockCounts.FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "open")
        {
            return BadRequest(new { message = "لا يمكن تعديل جرد ليس قيد العد" });
        }

        var item = await _db.StockCountItems.FirstOrDefaultAsync(i => i.Id == itemId && i.StockCountId == id);
        if (item is null) return NotFound();

        item.CountedQuantity = request.CountedQuantity;
        // الختم هنا لا في الشاشة: سطرٌ مرّ من هذا الطريق **رآه إنسان**،
        // وهذه هي الحقيقة الوحيدة التي تميّزه عمّا لم يُنظَر إليه.
        item.CountedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// يحلّ رمزاً ممسوحاً داخل جرد مفتوح — أساس الشاشة الميدانية.
    ///
    /// <para><b>لماذا على الخادم لا في التطبيق:</b> الحلّ محلياً يستلزم
    /// تحميل كل سطور الجرد إلى الهاتف — آلاف الصفوف على شبكة متجر — ويجعل
    /// الجواب رهناً بحداثة ما حُمِّل. وجهازان يعدّان معاً لا يرى أحدهما ما
    /// سجّله الآخر، فيصير <c>already_counted</c> مستحيل الاكتشاف.</para>
    ///
    /// <para>يبحث بالباركود ثم بالـSKU: القارئ الضوئي يُرسل الباركود، ومن
    /// يكتب بيده يكتب رمز الصنف غالباً. والمطابقة تامّة لا جزئية — جزئيةٌ
    /// قد تُرجع صنفاً آخر يحتوي المُدخَل فيُعدّ في مكان غيره.</para>
    /// </summary>
    [HttpGet("{id:guid}/scan/{code}")]
    [RequirePermission("stock_count.manage")]
    public async Task<ActionResult<ScanResultDto>> Scan(Guid id, string code)
    {
        var count = await _db.StockCounts.FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "open")
        {
            return BadRequest(new { message = "هذا الجرد ليس قيد العدّ" });
        }

        var normalized = (code ?? "").Trim();
        if (normalized.Length == 0)
        {
            return BadRequest(new { message = "لا رمز" });
        }

        // RLS تحصر البحث في منظمة المستخدم.
        var product = await _db.Products.FirstOrDefaultAsync(p =>
            !p.IsDeleted && (p.Barcode == normalized || p.Sku == normalized));

        if (product is null)
        {
            return new ScanResultDto(ScanCodes.Unknown, null,
                $"لا صنف بالرمز {normalized}. تأكّد من المسح، أو سجّل الصنف في الكتالوج أولاً.");
        }

        var item = await _db.StockCountItems
            .FirstOrDefaultAsync(i => i.StockCountId == id && i.ProductId == product.Id);

        if (item is null)
        {
            return new ScanResultDto(ScanCodes.Unlisted, null,
                $"«{product.Name}» موجود على الرفّ وليس في قائمة هذا الجرد.");
        }

        var varianceValue = Math.Abs(item.Variance) * product.CostPrice;
        var dto = new StockCountItemDto(
            item.Id, item.ProductId, product.Name, item.SystemQuantity, item.CountedQuantity,
            item.Variance, item.CountedAt, item.AddedDuringCount, product.Barcode, product.Sku, product.UnitBase,
            varianceValue,
            VarianceSeverity.Of(varianceValue, await CountValueAsync(id), item.SystemQuantity, item.Variance));

        return new ScanResultDto(
            item.CountedAt is null ? ScanCodes.Found : ScanCodes.AlreadyCounted,
            dto,
            item.CountedAt is null
                ? null
                : $"عُدَّ هذا الصنف في هذه الجولة بكمية {item.CountedQuantity:0.###}.");
    }

    /// <summary>
    /// يُضيف صنفاً وُجد على الرفّ ولم يكن في قائمة الجرد.
    ///
    /// <para>هي حالة <c>ConfirmUnexpectedUnitLoad</c> في myWMS، وتقع عندنا
    /// في الجرد الموزَّع: <c>NotCountedSince</c> يستبعد ما عُدَّ حديثاً،
    /// فيقف العامل أمام صنف موجود لا يجده في قائمته. بلا هذا الطريق يخرج من
    /// النظام ويكتب على ورقة.</para>
    ///
    /// <para>الكمية النظامية تُقرأ من الرصيد الحالي لا تُفترض صفراً: الصنف
    /// قد يكون له رصيد ولم يدخل القائمة إلا لأنه عُدَّ حديثاً. وافتراضُ
    /// الصفر يجعل كل إضافة تبدو فرقاً هائلاً فيُغرق مراجعَ الفروقات.</para>
    ///
    /// <para>ويبدأ بكمية معدودة صفراً وبلا ختم عدّ: الإضافة ليست عدّاً —
    /// العامل يسجّل أنه وجد شيئاً، ثم يعدّه في الخطوة التالية.</para>
    /// </summary>
    [HttpPost("{id:guid}/items")]
    [RequirePermission("stock_count.manage")]
    public async Task<ActionResult<StockCountItemDto>> AddUnlistedItem(Guid id, AddUnlistedItemRequest request)
    {
        var count = await _db.StockCounts.FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "open")
        {
            return BadRequest(new { message = "لا يمكن الإضافة إلى جرد ليس قيد العدّ" });
        }

        var product = await _db.Products.FirstOrDefaultAsync(p => p.Id == request.ProductId && !p.IsDeleted);
        if (product is null) return BadRequest(new { message = "صنف غير موجود أو محذوف" });

        var exists = await _db.StockCountItems.AnyAsync(i => i.StockCountId == id && i.ProductId == product.Id);
        if (exists) return BadRequest(new { message = "الصنف موجود في هذا الجرد أصلاً" });

        var systemQuantity = await _db.StockLevels
            .Where(sl => sl.BranchId == count.BranchId && sl.ProductId == product.Id)
            .SumAsync(sl => (decimal?)sl.Quantity) ?? 0;

        var item = new StockCountItem
        {
            StockCountId = id,
            ProductId = product.Id,
            SystemQuantity = systemQuantity,
            CountedQuantity = 0,
            AddedDuringCount = true,
        };
        _db.StockCountItems.Add(item);

        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.item_added", "stock_counts", count.Id,
            newValues: new { product.Name, product.Sku, SystemQuantity = systemQuantity });
        await _db.SaveChangesAsync();

        var addedValue = systemQuantity * product.CostPrice;
        return new StockCountItemDto(item.Id, product.Id, product.Name, systemQuantity, 0, -systemQuantity,
            null, true, product.Barcode, product.Sku, product.UnitBase,
            addedValue,
            VarianceSeverity.Of(addedValue, await CountValueAsync(id), systemQuantity, -systemQuantity));
    }

    /// <summary>
    /// قيمة المخزون النظامية لجردٍ كامل — مقام نسبة القيمة في تصنيف الشدّة.
    ///
    /// <para>استعلامٌ مجمَّع واحد على مفتاحٍ مفهرس. وحسابه في الشاشة
    /// الميدانية بدل تمرير صفر مقصود: صفرٌ يُسقط محور القيمة صامتاً فيصير
    /// كل فرقٍ «منخفضاً»، وشاشةٌ تكذب أسوأ من شاشةٍ تتأخّر ميلي ثانية.</para>
    /// </summary>
    private async Task<decimal> CountValueAsync(Guid countId) =>
        await _db.StockCountItems
            .Where(i => i.StockCountId == countId)
            .Join(_db.Products, i => i.ProductId, p => p.Id, (i, p) => i.SystemQuantity * p.CostPrice)
            .SumAsync(v => (decimal?)v) ?? 0m;

    /// <summary>
    /// إنهاء العدّ. إن وُجد فرقٌ واحد على الأقل ينتقل الجرد إلى
    /// <c>pending_review</c> بانتظار قرار بشري، وإلا اعتُمد فوراً — راجع
    /// StockCount.Status.
    /// </summary>
    [HttpPost("{id:guid}/submit")]
    [RequirePermission("stock_count.manage")]
    public async Task<ActionResult<object>> Submit(Guid id, [FromBody] SubmitCountRequest? request = null)
    {
        var count = await _db.StockCounts.Include(c => c.Items).FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "open")
        {
            return BadRequest(new { message = "لا يمكن إنهاء عدّ جرد ليس قيد العد" });
        }

        // سطورٌ لم يُمَسّ منها شيء تُنهي الجرد بكذبة: الدوري يبدأ بكمية معدودة
        // مساوية للنظامية، فما لم يره أحد يُحسَب «طابق». إنهاءٌ هكذا يقول
        // «صفر فروقات» عن رفوف لم يقف أمامها إنسان — وهو أسوأ من غياب الجرد،
        // لأنه يمنح ثقةً لا سند لها.
        //
        // ولا يُرفض إلى الأبد: قد يقرّر المسؤول أن الباقي خارج نطاق هذه
        // الجولة. لكن القرار يكون **صريحاً** لا افتراضاً صامتاً، ويُسجَّل.
        var uncounted = count.Items.Count(i => i.CountedAt is null);
        if (uncounted > 0 && request?.Force != true)
        {
            return BadRequest(new
            {
                message = $"بقي {uncounted} صنفاً لم يُعدّ. أكمل العدّ، أو أنهِ صراحةً مع تسجيل ذلك.",
                uncountedCount = uncounted,
            });
        }

        count.SubmittedBy = CurrentUserId();
        count.SubmittedAt = DateTime.UtcNow;

        if (uncounted > 0)
        {
            // يُسجَّل باسمه: من راجع الفروقات لاحقاً يجب أن يعرف أن جزءاً من
            // الرفوف لم يُنظَر إليه أصلاً، وإلا قرأ «صفر فروقات» على أنه شهادة.
            _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.submitted_incomplete",
                "stock_counts", count.Id, newValues: new { UncountedItems = uncounted });
        }

        var varianceCount = count.Items.Count(i => i.Variance != 0);
        if (varianceCount == 0)
        {
            await ApplyVariances(count);
            _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.reconciled", "stock_counts", count.Id,
                newValues: new { AdjustedItems = 0, Note = "بلا فروقات — اعتُمد مباشرةً" });
            await _db.SaveChangesAsync();
            return Ok(new { status = count.Status, varianceCount = 0 });
        }

        count.Status = "pending_review";
        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.submitted", "stock_counts", count.Id,
            newValues: new { VarianceItems = varianceCount });
        await _db.SaveChangesAsync();
        return Ok(new { status = count.Status, varianceCount });
    }

    /// <summary>
    /// إعادة العدّ: يعيد الجرد إلى <c>open</c> بسبب مكتوب.
    ///
    /// <para>الكميات المعدودة تُعاد إلى النظامية بدل تركها كما هي: تركُها
    /// يجعل «إعادة العدّ» نظرةً على أرقام سابقة يؤكّدها العادّ بضغطة، وهو
    /// نقيض الغرض. الرقم يُدخَل من الرفّ من جديد.</para>
    /// </summary>
    [HttpPost("{id:guid}/recount")]
    [RequirePermission("stock_count.manage")]
    public async Task<IActionResult> Recount(Guid id, RecountRequest request)
    {
        var reason = (request.Reason ?? "").Trim();
        if (reason.Length == 0)
        {
            return BadRequest(new { message = "سبب إعادة العدّ إلزامي" });
        }

        var count = await _db.StockCounts.Include(c => c.Items).FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "pending_review")
        {
            return BadRequest(new { message = "لا يمكن طلب إعادة عدّ لجرد ليس قيد المراجعة" });
        }

        // الختم يُمحى مع الكمية: إعادة العدّ تعني أن ما سُجِّل لا يُوثَق به،
        // فإبقاء «عُدَّ» عليها يجعل الجولة الثانية تُنهى فوراً بلا أن يقف أحد
        // أمام رفّ — وهو نقيض الغرض من طلب الإعادة.
        foreach (var item in count.Items)
        {
            item.CountedQuantity = item.SystemQuantity;
            item.CountedAt = null;
        }

        count.Status = "open";
        count.RecountReason = reason;
        count.RecountRounds++;
        count.ReviewedBy = CurrentUserId();
        count.ReviewedAt = DateTime.UtcNow;
        count.SubmittedBy = null;
        count.SubmittedAt = null;

        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.recount_requested", "stock_counts", count.Id,
            newValues: new { Reason = reason, count.RecountRounds });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>
    /// اعتماد الفروقات: يطبّق الفرق (Variance) فعلياً على stock_levels لكل
    /// صنف مختلف — دفعة عامة بلا رقم دفعة (نفس القيد المتّبع في تعديل المخزون
    /// اليدوي واسترجاع الفواتير)، لأن الجرد على مستوى الصنف لا الدفعة.
    /// </summary>
    [HttpPost("{id:guid}/approve")]
    [RequirePermission("stock_count.manage")]
    public async Task<IActionResult> Approve(Guid id)
    {
        var count = await _db.StockCounts.Include(c => c.Items).FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        if (count.Status != "pending_review")
        {
            return BadRequest(new { message = "لا يمكن اعتماد جرد ليس قيد المراجعة" });
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();

        count.ReviewedBy = CurrentUserId();
        count.ReviewedAt = DateTime.UtcNow;
        await ApplyVariances(count);

        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.reconciled", "stock_counts", count.Id,
            newValues: new { AdjustedItems = count.Items.Count(i => i.Variance != 0), count.RecountRounds });
        await _db.SaveChangesAsync();
        await transaction.CommitAsync();
        return NoContent();
    }

    /// <summary>
    /// يطبّق الفروقات ويغلق الجرد. لا يحفظ ولا يفتح معاملة — المستدعي يفعل،
    /// فمسار «بلا فروقات» لا يحتاج معاملة أصلاً (لا صفّ مخزون يُمسّ).
    /// </summary>
    private async Task ApplyVariances(StockCount count)
    {

        var costs = await _db.Products
            .Where(p => count.Items.Select(i => i.ProductId).Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.CostPrice);

        foreach (var item in count.Items.Where(i => i.Variance != 0))
        {
            if (item.Variance > 0)
            {
                // زيادة الجرد إدخالٌ بتكلفة الصنف: بضاعة ظهرت على الرفّ بلا
                // مستند شراء، ولا سعر أدقّ منه متاح. والجرد الابتدائي كلّه
                // يمرّ من هنا — فيصبح مخزون الافتتاح مُقيَّداً في الدفتر لا
                // ظاهراً من العدم.
                await StockLedger.ReceiveAsync(
                    _db, count.OrganizationId, count.BranchId, warehouseId: null,
                    productId: item.ProductId,
                    quantity: item.Variance,
                    unitCost: costs.GetValueOrDefault(item.ProductId, 0m),
                    sourceType: StockSourceTypes.StockCount, sourceId: count.Id,
                    userId: CurrentUserId(),
                    // دفعة جرد بلا صلاحية: تُختَم بتاريخ اليوم فتدخل طابور
                    // FIFO في موضعها الصحيح — آخره، فهي أحدث ما ظهر.
                    trackExpiry: false);
            }
            else
            {
                // النقص صرفٌ بقاعدة الصرف نفسها: يُقسَّم على الإدخالات فتُعرف
                // **تكلفة ما نقص** لا كميته وحدها — وهو الرقم الذي يجعل فرق
                // الجرد خسارةً مالية معلومة لا عدداً في تقرير.
                //
                // والمتاح قد يقلّ عن النقص المُعلن (بضاعة موقوفة مثلاً)، فيُصرَف
                // ما أمكن ولا يُوقَف اعتماد الجرد كلّه على سطر واحد.
                var shortage = -item.Variance;
                var onHand = await _db.StockLevels
                    .Where(s => s.BranchId == count.BranchId && s.ProductId == item.ProductId
                             && s.WarehouseId == null && !s.IsLocked)
                    .SumAsync(s => (decimal?)s.Quantity) ?? 0;
                var issue = Math.Min(shortage, onHand);
                if (issue > 0)
                {
                    await StockLedger.IssueAsync(
                        _db, count.OrganizationId, count.BranchId, warehouseId: null,
                        productId: item.ProductId,
                        quantity: issue,
                        sourceType: StockSourceTypes.StockCount, sourceId: count.Id,
                        userId: CurrentUserId());
                }
            }
        }

        // آخر عدّ يُختَم على **كل** أصناف الجرد لا على ذوات الفرق وحدها:
        // صنفٌ عُدّ فطابق هو صنف عُدّ — واستثناؤه يجعله يظهر في كل جرد موزَّع
        // تالٍ بلا سبب.
        var now = DateTime.UtcNow;
        var countedIds = count.Items.Select(i => i.ProductId).ToList();
        await _db.Products
            .Where(p => countedIds.Contains(p.Id))
            .ExecuteUpdateAsync(setters => setters.SetProperty(p => p.LastCountedAt, now));

        count.Status = "reconciled";
        count.ClosedAt = now;
    }

    [HttpPost("{id:guid}/cancel")]
    [RequirePermission("stock_count.manage")]
    public async Task<IActionResult> Cancel(Guid id)
    {
        var count = await _db.StockCounts.FirstOrDefaultAsync(c => c.Id == id);
        if (count is null) return NotFound();
        // ومن المراجعة أيضاً: جردٌ تبيّن أن عدّه كلّه خطأ يُلغى ولا يُعتمد،
        // وحصرُ الإلغاء في حالة العدّ كان يترك الخيارين الوحيدين أمام
        // المراجع: اعتماد فرق يعرف أنه خاطئ، أو إعادة عدّ لا معنى لها.
        if (count.Status is not ("open" or "pending_review"))
        {
            return BadRequest(new { message = "لا يمكن إلغاء جرد مُعتمَد أو ملغى" });
        }

        count.Status = "cancelled";
        count.ClosedAt = DateTime.UtcNow;
        _db.LogAudit(count.OrganizationId, CurrentUserId(), "stock_count.cancelled", "stock_counts", count.Id, null);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    private async Task<StockCountDetailDto> ToDetailDto(StockCount count)
    {
        var branchName = await _db.Branches.Where(b => b.Id == count.BranchId).Select(b => b.Name).FirstOrDefaultAsync() ?? "-";
        var productIds = count.Items.Select(i => i.ProductId).ToList();
        // الباركود والرمز والوحدة تُجلَب معها: الشاشة الميدانية تعرض الوحدة
        // بجانب الكمية («12 علبة» لا «12»)، وبلاها يُدخل العادّ حبّات مكان علب.
        // والتكلفة معها: بها تُحسب قيمة الفرق وشدّته — راجع [VarianceSeverity].
        var products = await _db.Products.Where(p => productIds.Contains(p.Id))
            .Select(p => new { p.Id, p.Name, p.Barcode, p.Sku, p.UnitBase, p.CostPrice })
            .ToDictionaryAsync(p => p.Id, p => p);

        // قيمة الجرد النظامية — مقام نسبة القيمة في تصنيف الشدّة.
        var countValue = count.Items.Sum(
            i => i.SystemQuantity * (products.GetValueOrDefault(i.ProductId)?.CostPrice ?? 0m));

        // الدقّة من السطور التي مُسَّت وحدها — راجع [StockCountDetailDto].
        var counted = count.Items.Where(i => i.CountedAt is not null).ToList();
        var matched = counted.Count(i => i.Variance == 0);
        decimal? accuracy = counted.Count == 0
            ? null
            : Math.Round(matched * 100m / counted.Count, 1);

        // النقص والزيادة منفصلان لا صافياً: زيادةٌ في صنف لا تعوّض نقصاً في
        // آخر، وطرحُهما يُخفي خسارةً حقيقية تحت رقمٍ صغير — وهو أوّل ما
        // يفعله من يريد إخفاء عجز.
        var shortage = count.Items.Where(i => i.Variance < 0)
            .Sum(i => -i.Variance * (products.GetValueOrDefault(i.ProductId)?.CostPrice ?? 0m));
        var surplus = count.Items.Where(i => i.Variance > 0)
            .Sum(i => i.Variance * (products.GetValueOrDefault(i.ProductId)?.CostPrice ?? 0m));

        // اسم من عدّ ومن راجع: الشاشة تعرضهما جنباً إلى جنب، فتطابقهما ظاهر
        // لمن ينظر بلا حاجة إلى فتح سجلّ التدقيق.
        var userIds = new[] { count.SubmittedBy, count.ReviewedBy }
            .Where(u => u.HasValue).Select(u => u!.Value).Distinct().ToList();
        var userNames = userIds.Count == 0
            ? new Dictionary<Guid, string>()
            : await _db.AppUsers.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.FullName);

        return new StockCountDetailDto(
            count.Id, count.BranchId, branchName, count.Status, count.CreatedAt, count.ClosedAt,
            count.Items
                .Select(i =>
                {
                    var p = products.GetValueOrDefault(i.ProductId);
                    var varianceValue = Math.Abs(i.Variance) * (p?.CostPrice ?? 0m);
                    return new StockCountItemDto(
                        i.Id, i.ProductId, p?.Name ?? "-", i.SystemQuantity, i.CountedQuantity, i.Variance,
                        i.CountedAt, i.AddedDuringCount, p?.Barcode, p?.Sku ?? "-", p?.UnitBase ?? "piece",
                        varianceValue,
                        VarianceSeverity.Of(varianceValue, countValue, i.SystemQuantity, i.Variance));
                })
                .OrderBy(i => i.ProductName)
                .ToList(),
            count.SubmittedBy is null ? null : userNames.GetValueOrDefault(count.SubmittedBy.Value),
            count.SubmittedAt,
            count.ReviewedBy is null ? null : userNames.GetValueOrDefault(count.ReviewedBy.Value),
            count.ReviewedAt,
            count.RecountReason, count.RecountRounds,
            count.Items.Count(i => i.CountedAt is null),
            accuracy, shortage, surplus, countValue);
    }

    private Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(JwtRegisteredClaimNames.Sub) ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }
}
