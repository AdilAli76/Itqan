using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>كمية صُرفت من إدخال بعينه — ناتج [StockLedger.IssueAsync].</summary>
public record IssuedLot(Guid SourceEntryId, decimal Quantity, decimal UnitCost, string BatchNumber, DateTime? ExpiryDate);

/// <summary>
/// **الطريق الوحيد** لتغيير المخزون في النظام كلّه.
///
/// <para>كل مسار — بيع، مرتجع، استلام، تحويل، جرد، تعديل يدوي — يمرّ من هنا.
/// وهذه ليست توصية أسلوبية: القاعدة الحاكمة للدفتر أن **لا مسار يُعدّل الرصيد
/// بلا سطر دفتر**، ونقطة اختناق واحدة هي ما يجعل ذلك مضموناً هندسياً بدل أن
/// يكون رهاناً على انتباه من يكتب المسار السابع.</para>
///
/// <para><b>الرصيد يبقى في stock_levels</b> ولا يُحذف — لكنه يتحوّل من مصدر
/// حقيقة إلى **ذاكرة مشتقّة**: يُكتب هنا مع سطر الدفتر في المعاملة نفسها،
/// فتبقى كل شاشة قائمة تقرأه كما كانت.</para>
///
/// <para><b>لا يحفظ ولا يفتح معاملة:</b> المستدعي يملك المعاملة، لأن حركة
/// المخزون جزء من عملية أكبر (فاتورة، مستند استلام) تنجح أو تفشل كاملةً.</para>
/// </summary>
public static class StockLedger
{
    /// <summary>
    /// إدخال: يزيد الرصيد ويكتب سطر دفتر موجباً.
    ///
    /// <para><see cref="StockLedgerEntry.RemainingQuantity"/> يبدأ بالكمية
    /// كاملةً — منه تُصرَف الحركات التالية، وبه يُعرف ما بقي من كل شحنة.</para>
    /// </summary>
    public static async Task<StockLedgerEntry> ReceiveAsync(
        AppDbContext db,
        Guid organizationId, Guid branchId, Guid? warehouseId, Guid productId,
        decimal quantity, decimal unitCost,
        string sourceType, Guid? sourceId, Guid? userId,
        string batchNumber = "", DateTime? expiryDate = null, bool trackExpiry = false,
        DateTime? postedAt = null)
    {
        if (quantity <= 0) throw new ArgumentOutOfRangeException(nameof(quantity), "الإدخال يجب أن يكون موجباً");

        var level = await LevelAsync(db, branchId, warehouseId, productId, batchNumber);
        if (level is null)
        {
            level = new StockLevel
            {
                OrganizationId = organizationId,
                BranchId = branchId,
                WarehouseId = warehouseId,
                ProductId = productId,
                BatchNumber = batchNumber,
                ExpiryDate = expiryDate,
                Quantity = 0,
            };
            level.StampStrategyDate(trackExpiry);
            db.StockLevels.Add(level);
        }
        else if (expiryDate.HasValue && level.ExpiryDate != expiryDate)
        {
            level.ExpiryDate = expiryDate;
            level.StampStrategyDate(trackExpiry);
        }

        level.Quantity += quantity;

        // متوسط التكلفة المتحرك على الدفعة: قيمة ما كان زائد قيمة ما دخل،
        // مقسومةً على المجموع. FIFO الدقيق يأتي من SourceEntryId عند الصرف —
        // وهذا الرقم للعرض والتقييم الإجمالي.
        var previousValue = await ValueOfAsync(db, branchId, warehouseId, productId, batchNumber);
        var valueChange = quantity * unitCost;

        var entry = new StockLedgerEntry
        {
            OrganizationId = organizationId,
            BranchId = branchId,
            WarehouseId = warehouseId,
            ProductId = productId,
            BatchNumber = batchNumber,
            ExpiryDate = expiryDate,
            PostedAt = postedAt ?? DateTime.UtcNow,
            QuantityChange = quantity,
            BalanceAfter = level.Quantity,
            UnitCost = unitCost,
            ValueChange = valueChange,
            ValueAfter = previousValue + valueChange,
            SourceType = sourceType,
            SourceId = sourceId,
            RemainingQuantity = quantity,
            CreatedBy = userId,
        };
        db.StockLedgerEntries.Add(entry);
        return entry;
    }

    /// <summary>
    /// صرف: يخصم من الرصيد ويكتب سطر دفتر لكل **إدخال** استُهلك منه.
    ///
    /// <para>الصرف يُقسَّم على الإدخالات بترتيب <c>strategy_date</c> — أي
    /// FEFO للصنف المتتبَّع وFIFO لغيره، بقاعدة واحدة (راجع
    /// StockLevel.StrategyDate). فبيع خمس قطع من إدخالين يكتب **سطري صرف**
    /// لا سطراً واحداً: كل سطر يعرف تكلفته الحقيقية ومن أين جاء.</para>
    ///
    /// <para>الموقوف مستبعَد: قفلُه قرارٌ بأنه لا يُصرَف (راجع StockLevel.IsLocked).</para>
    /// </summary>
    public static async Task<List<IssuedLot>> IssueAsync(
        AppDbContext db,
        Guid organizationId, Guid branchId, Guid? warehouseId, Guid productId,
        decimal quantity,
        string sourceType, Guid? sourceId, Guid? userId,
        DateTime? postedAt = null)
    {
        if (quantity <= 0) throw new ArgumentOutOfRangeException(nameof(quantity), "الصرف يجب أن يكون موجباً");

        // الإدخالات التي بقي فيها شيء، مرتّبةً بأولوية الصرف. الترتيب على
        // strategy_date الخاص بالرصيد لا على تاريخ الإدخال: الأول يعرف
        // الصلاحية، والثاني لا.
        var lots = await db.StockLedgerEntries
            .Where(e => e.BranchId == branchId
                     && e.ProductId == productId
                     && e.WarehouseId == warehouseId
                     && e.RemainingQuantity > 0
                     && !e.IsCancelled)
            .OrderBy(e => e.ExpiryDate == null ? 1 : 0)
            .ThenBy(e => e.ExpiryDate)
            .ThenBy(e => e.PostedAt)
            .ToListAsync();

        var levels = await db.StockLevels
            .Where(s => s.BranchId == branchId && s.ProductId == productId && s.WarehouseId == warehouseId)
            .ToListAsync();
        var lockedBatches = levels.Where(l => l.IsLocked).Select(l => l.BatchNumber).ToHashSet();

        var usable = lots.Where(l => !lockedBatches.Contains(l.BatchNumber)).ToList();
        var available = usable.Sum(l => l.RemainingQuantity);
        if (available < quantity)
        {
            throw new InvalidOperationException(
                $"الكمية المتاحة ({available:0.###}) أقلّ من المطلوب ({quantity:0.###})");
        }

        var issued = new List<IssuedLot>();
        var remaining = quantity;

        foreach (var lot in usable)
        {
            if (remaining <= 0) break;
            var take = Math.Min(lot.RemainingQuantity, remaining);
            remaining -= take;
            lot.RemainingQuantity -= take;

            var level = levels.FirstOrDefault(l => l.BatchNumber == lot.BatchNumber);
            if (level is null) continue;
            level.Quantity -= take;

            var previousValue = ValueOf(levels, lot.BatchNumber, lot.UnitCost);
            var valueChange = -take * lot.UnitCost;

            db.StockLedgerEntries.Add(new StockLedgerEntry
            {
                OrganizationId = organizationId,
                BranchId = branchId,
                WarehouseId = warehouseId,
                ProductId = productId,
                BatchNumber = lot.BatchNumber,
                ExpiryDate = lot.ExpiryDate,
                PostedAt = postedAt ?? DateTime.UtcNow,
                QuantityChange = -take,
                BalanceAfter = level.Quantity,
                UnitCost = lot.UnitCost,
                ValueChange = valueChange,
                ValueAfter = previousValue + valueChange,
                SourceType = sourceType,
                SourceId = sourceId,
                // الرابط الذي يعطي التكلفة الدقيقة والتتبّع العكسي معاً.
                SourceEntryId = lot.Id,
                CreatedBy = userId,
            });

            issued.Add(new IssuedLot(lot.Id, take, lot.UnitCost, lot.BatchNumber, lot.ExpiryDate));
        }

        return issued;
    }

    private static async Task<StockLevel?> LevelAsync(
        AppDbContext db, Guid branchId, Guid? warehouseId, Guid productId, string batchNumber) =>
        await db.StockLevels.FirstOrDefaultAsync(
            s => s.BranchId == branchId
              && s.WarehouseId == warehouseId
              && s.ProductId == productId
              && s.BatchNumber == batchNumber);

    /// <summary>قيمة آخر سطر دفتر لهذه الدفعة — نقطة البداية لقيمة السطر التالي.</summary>
    private static async Task<decimal> ValueOfAsync(
        AppDbContext db, Guid branchId, Guid? warehouseId, Guid productId, string batchNumber)
    {
        var last = await db.StockLedgerEntries
            .Where(e => e.BranchId == branchId
                     && e.WarehouseId == warehouseId
                     && e.ProductId == productId
                     && e.BatchNumber == batchNumber
                     && !e.IsCancelled)
            .OrderByDescending(e => e.PostedAt)
            .ThenByDescending(e => e.CreatedAt)
            .Select(e => (decimal?)e.ValueAfter)
            .FirstOrDefaultAsync();
        return last ?? 0;
    }

    private static decimal ValueOf(List<StockLevel> levels, string batchNumber, decimal unitCost)
    {
        var level = levels.FirstOrDefault(l => l.BatchNumber == batchNumber);
        return level is null ? 0 : (level.Quantity + 0) * unitCost;
    }
}
