using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

public record DisburseResult(
    int CustomersPaid, decimal TotalPaid, int Skipped,
    /// ما استُردّ من السلف في هذه الدورة — يُعرَض للإدارة مع المصروف.
    decimal AdvancesDeducted = 0);

/// <summary>
/// صرف المرتَّبات الدورية على بطاقات المنتسبين.
///
/// <para><b>الفجوة التي يسدّها:</b> <see cref="EntitlementSweeper"/> يُسقط
/// ما انتهى ولا يُودع شيئاً. فجهةٌ تصرف على ألف منتسب كانت تشحن ألف بطاقة
/// يدوياً كل شهر — عملُ يومٍ كامل يُخطئ فيه إدخالٌ أو اثنان، ولا يُعرف
/// أيّهما إلا حين يشتكي صاحبه.</para>
///
/// <para><b>ونقطة صرفٍ واحدة</b> يستدعيها الزرّ اليدوي والخدمة المجدولة
/// معاً: مسارانِ للصرف يفترقان أوّل مرّة يُعدَّل أحدهما، فيصرف أحدهما بمبلغ
/// والآخر بآخر.</para>
/// </summary>
public static class EntitlementDisburser
{
    /// <summary>
    /// يصرف مرتَّب الدورة لمن يستحقّه في منظمةٍ واحدة.
    ///
    /// <para><paramref name="periodEnd"/> تاريخ انتهاء الدورة. يُكتب على
    /// العميل حين تكون فئته «يسقط ما لم يُصرَف»، ويُترك فارغاً حين لا
    /// يسقط — و<see cref="EntitlementSweeper"/> لا يمسّ إلا من له تاريخ،
    /// فالرصيد المتراكم يعمل بلا سطرٍ واحد يُضاف هناك.</para>
    ///
    /// <para><b>ولا يُصرف مرّتين في الدورة الواحدة:</b> يُفحَص آخر صرفٍ
    /// لكل عميل. زرٌّ يُضغط مرّتين، أو خدمةٌ تعمل على خادمين، كانا سيُضاعفان
    /// المرتَّب — والمال الخارج لا يعود.</para>
    /// </summary>
    public static async Task<DisburseResult> DisburseAsync(
        AppDbContext db,
        Guid organizationId,
        DateOnly periodStart,
        DateOnly? periodEnd,
        Guid? createdBy = null,
        Guid? categoryId = null)
    {
        var categories = await db.CustomerCategories
            .Where(c => c.IsActive && (categoryId == null || c.Id == categoryId))
            .ToDictionaryAsync(c => c.Id, c => c);

        if (categories.Count == 0) return new DisburseResult(0, 0, 0);

        var ids = categories.Keys.ToList();
        var members = await db.Customers
            .Where(c => !c.IsDeleted
                     // الشرط الذي يمنع شحن رصيدٍ دفعه صاحبه: المرتَّب
                     // لحساب الاستحقاق وحده. راجع [AccountModels].
                     && c.AccountModel == AccountModels.Entitlement
                     && c.CategoryId != null
                     && ids.Contains(c.CategoryId.Value))
            .Select(c => new { c.Id, c.OrganizationId, c.FullName, c.CategoryId, c.EntitlementOverride })
            .ToListAsync();

        if (members.Count == 0) return new DisburseResult(0, 0, 0);

        // من قُبض له في هذه الدورة أصلاً — استعلامٌ واحد لا واحدٌ لكل عميل.
        var periodStartUtc = periodStart.ToDateTime(TimeOnly.MinValue);
        var memberIds = members.Select(m => m.Id).ToList();
        var alreadyPaid = await db.CustomerWalletTransactions
            .Where(t => memberIds.Contains(t.CustomerId)
                     && t.Kind == WalletKinds.EntitlementGrant
                     && t.CreatedAt >= periodStartUtc)
            .Select(t => t.CustomerId)
            .Distinct()
            .ToListAsync();
        var paidSet = alreadyPaid.ToHashSet();

        // ── السلف القائمة ومتبقّيها ─────────────────────────────────────
        //
        // المتبقّي محسوبٌ لا مخزَّن: أصل السلفة ناقص مجموع أقساطها في
        // الدفتر — بنفس مبدأ رصيد المحفظة. وعمودُ «متبقٍّ» قابل للكتابة هو
        // أسرع طريق إلى سلفةٍ رقمُها لا يطابق حركاتها.
        var openAdvances = await db.CustomerAdvances
            .Where(a => !a.IsCancelled && memberIds.Contains(a.CustomerId))
            .OrderBy(a => a.IssuedOn)
            .ToListAsync();

        var repaid = new Dictionary<Guid, decimal>();
        if (openAdvances.Count > 0)
        {
            var advanceIds = openAdvances.Select(a => a.Id).ToList();
            repaid = await db.CustomerWalletTransactions
                .Where(t => t.AdvanceId != null
                         && advanceIds.Contains(t.AdvanceId.Value)
                         && t.Kind == WalletKinds.AdvanceRepayment)
                .GroupBy(t => t.AdvanceId!.Value)
                .Select(g => new { AdvanceId = g.Key, Total = g.Sum(t => t.Amount) })
                .ToDictionaryAsync(x => x.AdvanceId, x => x.Total);
        }

        var paid = 0;
        var skipped = 0;
        var total = 0m;
        var deducted = 0m;

        foreach (var member in members)
        {
            if (paidSet.Contains(member.Id)) { skipped++; continue; }

            var category = categories[member.CategoryId!.Value];

            // التعديل الفردي يَجُبّ الفئة، والصفر قرارٌ صريح بالإيقاف —
            // ولذلك NULL هو «اتبع الفئة» لا الصفر.
            var amount = member.EntitlementOverride ?? category.PeriodAmount;
            if (amount <= 0) { skipped++; continue; }

            db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
            {
                OrganizationId = member.OrganizationId,
                CustomerId = member.Id,
                Kind = WalletKinds.EntitlementGrant,
                Amount = amount,
                Note = $"مرتَّب {category.Name} — دورة {periodStart:yyyy-MM}",
                CreatedBy = createdBy,
            });

            paid++;
            total += amount;

            // ── خصم أقساط السلف من هذا المرتَّب ─────────────────────────
            //
            // بعد قيد المرتَّب لا قبله: كشف المنتسب يقرأ سطرين بترتيبٍ
            // مفهوم — «مرتَّب» ثم «خصم سلفة» — لا خصماً يسبق ما يُخصم منه.
            //
            // ولا يتجاوز الخصمُ المرتَّبَ نفسه: قسطٌ أكبر منه كان سيهبط
            // برصيد المنتسب تحت الصفر، فيقف على الصندوق بلا شيء وقد قُبض
            // له. والباقي يُرحَّل إلى الدورة التالية بلا إجراء — لأن
            // المتبقّي محسوب، فما لم يُخصم يبقى ظاهراً من نفسه.
            var budget = amount;
            foreach (var advance in openAdvances.Where(a => a.CustomerId == member.Id))
            {
                if (budget <= 0) break;

                var outstanding = advance.Amount - repaid.GetValueOrDefault(advance.Id);
                if (outstanding <= 0) continue;

                // صفر = كامل المتبقّي دفعةً واحدة.
                var installment = advance.InstallmentAmount > 0
                    ? Math.Min(advance.InstallmentAmount, outstanding)
                    : outstanding;

                var take = Math.Min(installment, budget);
                if (take <= 0) continue;

                db.CustomerWalletTransactions.Add(new CustomerWalletTransaction
                {
                    OrganizationId = member.OrganizationId,
                    CustomerId = member.Id,
                    AdvanceId = advance.Id,
                    Kind = WalletKinds.AdvanceRepayment,
                    Amount = take,
                    Note = $"خصم سلفة — دورة {periodStart:yyyy-MM}",
                    CreatedBy = createdBy,
                });

                repaid[advance.Id] = repaid.GetValueOrDefault(advance.Id) + take;
                budget -= take;
                deducted += take;
            }
        }

        if (paid == 0) return new DisburseResult(0, 0, skipped);

        // تاريخ الانتهاء على العميل: يقرّره **صنف فئته** لا الصرف.
        var paidIds = members
            .Where(m => !paidSet.Contains(m.Id)
                     && (m.EntitlementOverride ?? categories[m.CategoryId!.Value].PeriodAmount) > 0)
            .Select(m => m.Id)
            .ToHashSet();

        var toStamp = await db.Customers.Where(c => paidIds.Contains(c.Id)).ToListAsync();
        foreach (var customer in toStamp)
        {
            var category = categories[customer.CategoryId!.Value];
            customer.EntitlementExpiresOn = category.UnspentExpires ? periodEnd : null;
        }

        db.LogAudit(organizationId, createdBy, "entitlement.disbursed", "customer_categories", null,
            newValues: new
            {
                Period = periodStart.ToString("yyyy-MM"),
                CustomersPaid = paid,
                TotalPaid = total,
                Skipped = skipped,
                AdvancesDeducted = deducted,
            });

        await db.SaveChangesAsync();
        return new DisburseResult(paid, total, skipped, deducted);
    }
}
