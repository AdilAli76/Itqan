using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>دَين عميل واحد موزَّعاً على شرائح العمر.</summary>
public record CustomerDebtAging(
    Guid CustomerId, string CustomerName, string? Phone,
    decimal TotalOutstanding,
    decimal NotYetDue, decimal Days1To30, decimal Days31To60, decimal Days61To90, decimal Over90,
    DateTime? OldestDueDate, int DaysOverdue, int Stage);

/// <summary>
/// أعمار الديون — الطريق الوحيد لحسابها، يستدعيه التقرير والمهمة اليومية معاً.
///
/// <para><b>لماذا الحساب لا التخزين:</b> الدَّين رصيدٌ مشتقّ من دفتر المحفظة
/// (راجع [WalletBalances])، ولا عمود رصيد مخزَّناً في النظام كلّه. وتخزين
/// شرائح العمر كان سيُنتج أرقاماً تتقادم بين ليلة وضحاها — عمر الدَّين
/// يتغيّر كل يوم بلا أي حركة.</para>
///
/// <para><b>قاعدة التوزيع:</b> السداد يُطفئ الأقدم أولاً (FIFO)، فما يتبقّى
/// من الدَّين يقع على **الأحدث** من الفواتير. هذا هو العرف المحاسبي، وهو
/// أيضاً الأصدق: العميل الذي يسدّد شيئاً يسدّد عن أقدم ما عليه.</para>
///
/// <para>والبديل — ربط كل سداد بفاتورته — يحتاج أن يختار الكاشير الفاتورة
/// عند كل تعبئة رصيد، وهو ما لا يفعله أحد في متجر. فالتوزيع يُشتقّ ولا
/// يُطلَب من المستخدم.</para>
/// </summary>
public static class DebtAging
{
    public static async Task<List<CustomerDebtAging>> ComputeAsync(AppDbContext db, DateTime today)
    {
        var day = today.Date;

        // الفواتير الآجلة وحدها: ما دُفع كاملاً لا يدخل الحساب أصلاً.
        // PaidAmount = NULL تعني دفعاً كاملاً (راجع Invoice.PaidAmount).
        var creditInvoices = await db.Invoices
            .Where(i => i.CustomerId != null
                     && i.InvoiceType == "sale"
                     && i.PaidAmount != null
                     && i.PaidAmount < i.TotalAmount)
            .Select(i => new
            {
                CustomerId = i.CustomerId!.Value,
                Credit = i.TotalAmount - i.PaidAmount!.Value,
                i.DueDate,
                i.CreatedAt,
            })
            .ToListAsync();

        if (creditInvoices.Count == 0) return new List<CustomerDebtAging>();

        var customerIds = creditInvoices.Select(i => i.CustomerId).Distinct().ToList();

        var customers = await db.Customers
            .Where(c => customerIds.Contains(c.Id) && !c.IsDeleted)
            .Select(c => new { c.Id, c.FullName, c.Phone })
            .ToDictionaryAsync(c => c.Id, c => c);

        // الأرصدة دفعةً واحدة لا استدعاءً لكل عميل: قائمة من مئة مدين كانت
        // ستُنتج مئة استعلام في كل فتح للتقرير.
        var balances = await db.CustomerWalletTransactions
            .Where(t => customerIds.Contains(t.CustomerId))
            .GroupBy(t => t.CustomerId)
            .Select(g => new
            {
                CustomerId = g.Key,
                In = g.Where(t => WalletKinds.InKinds.Contains(t.Kind)).Sum(t => (decimal?)t.Amount) ?? 0,
                Out = g.Where(t => WalletKinds.OutKinds.Contains(t.Kind)).Sum(t => (decimal?)t.Amount) ?? 0,
            })
            .ToDictionaryAsync(x => x.CustomerId, x => x.In - x.Out);

        var result = new List<CustomerDebtAging>();

        foreach (var group in creditInvoices.GroupBy(i => i.CustomerId))
        {
            if (!customers.TryGetValue(group.Key, out var customer)) continue;

            var balance = balances.GetValueOrDefault(group.Key, 0m);
            var outstanding = balance < 0 ? -balance : 0m;
            if (outstanding <= 0) continue;   // سدّد كل ما عليه

            // من الأحدث إلى الأقدم: نملأ المتبقّي بالأحدث أوّلاً، لأن السداد
            // أطفأ الأقدم. وما لم يبلغه المتبقّي من الفواتير القديمة يُعدّ
            // مسدَّداً فلا يُحتسب.
            var ordered = group
                .OrderByDescending(i => i.DueDate ?? i.CreatedAt)
                .ToList();

            decimal notYetDue = 0, d1 = 0, d2 = 0, d3 = 0, over = 0;
            var remaining = outstanding;
            DateTime? oldestDue = null;

            foreach (var invoice in ordered)
            {
                if (remaining <= 0) break;
                var portion = Math.Min(remaining, invoice.Credit);
                remaining -= portion;

                // بلا تاريخ استحقاق (فاتورة تسبق هذه الميزة) تُعامَل بتاريخ
                // إصدارها: افتراض «مستحقّ فوراً» أصدق من افتراض «غير مستحقّ»،
                // فالأخير يُخفي ديناً قديماً في خانة «لم يحن بعد».
                var due = (invoice.DueDate ?? invoice.CreatedAt).Date;
                if (oldestDue is null || due < oldestDue) oldestDue = due;

                var overdueDays = (day - due).Days;
                if (overdueDays < 0) notYetDue += portion;
                else if (overdueDays <= 30) d1 += portion;
                else if (overdueDays <= 60) d2 += portion;
                else if (overdueDays <= 90) d3 += portion;
                else over += portion;
            }

            var daysOverdue = oldestDue is null ? 0 : Math.Max(0, (day - oldestDue.Value).Days);

            result.Add(new CustomerDebtAging(
                customer.Id, customer.FullName, customer.Phone,
                outstanding, notYetDue, d1, d2, d3, over,
                oldestDue, daysOverdue,
                // المرحلة تُشتقّ من أقدم دَين متأخّر لا من مجموعه: من عليه
                // دينار متأخّر شهرين أولى بالمطالبة ممّن عليه ألف حلّ أمس.
                notYetDue >= outstanding ? 0 : DebtReminderPolicy.StageFor(daysOverdue)));
        }

        // الأقدم تأخّراً أولاً، ثم الأكبر مبلغاً — ترتيب أولوية التحصيل.
        return result
            .OrderByDescending(r => r.DaysOverdue)
            .ThenByDescending(r => r.TotalOutstanding)
            .ToList();
    }
}
