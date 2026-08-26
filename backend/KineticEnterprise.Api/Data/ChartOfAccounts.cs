using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// بذر دليل الحسابات الافتراضي على الدليل المحاسبي الموحّد.
///
/// <para><b>لماذا يُبذَر ولا يُترك للمستخدم:</b> دليلٌ فارغ يعني أن الترحيل
/// الآلي لا يجد حساباً يرحّل إليه، فيفشل **أول بيع** عند الكاشير. والتاجر
/// الذي اشترى نظاماً ليبيع لا يبدأ ببناء شجرة حسابات من الصفر — ولا يعرف
/// كيف. فيُبذَر دليلٌ عامل يوم تُفعَّل الوحدة، ويوسّعه محاسبه بعد ذلك.</para>
///
/// <para><b>والربط يُبذَر معه في نفس المعاملة</b> (راجع [AccountRoles]):
/// دليلٌ بلا ربط كدليل بلا حسابات سواء — كلاهما يُوقف البيع. وفصلُهما
/// يخلق حالةً وسطى «مفعَّل وناقص» يكتشفها الكاشير لا نحن.</para>
/// </summary>
public static class ChartOfAccounts
{
    /// <param name="Code">رمز الحساب. البادئة تعني الأب: 1101 ابن 11 ابن 1.</param>
    /// <param name="Role">دور الترحيل الذي يُربَط بهذا الحساب، إن كان له دور.</param>
    private record Seed(string Code, string Name, string Type, string? Role = null);

    /// <summary>
    /// الدليل الافتراضي.
    ///
    /// <para>مختصر عمداً: كل حساب زائد هنا سطرٌ في شجرة يقرؤها من لا يعرف
    /// المحاسبة. وما يلزم فعلاً هو ما يرحّل إليه النظام، وما يفهمه التاجر
    /// حين ينظر. والتوسعة بيد محاسبه لأنه يعرف نشاطه.</para>
    /// </summary>
    private static readonly Seed[] Default =
    {
        // ── 1 الأصول ────────────────────────────────────────────────────
        new("1", "الأصول", AccountTypes.Asset),
        new("11", "الأصول المتداولة", AccountTypes.Asset),
        new("1101", "الصندوق", AccountTypes.Asset, AccountRoles.Cash),
        new("1102", "المصارف", AccountTypes.Asset),
        new("1103", "العملاء (ذمم مدينة)", AccountTypes.Asset, AccountRoles.Receivables),
        new("1104", "المخزون", AccountTypes.Asset, AccountRoles.Inventory),
        new("12", "الأصول الثابتة", AccountTypes.Asset),
        new("1201", "أثاث ومعدّات", AccountTypes.Asset),

        // ── 2 الالتزامات وحقوق الملكية ──────────────────────────────────
        new("2", "الالتزامات وحقوق الملكية", AccountTypes.Liability),
        new("21", "الالتزامات المتداولة", AccountTypes.Liability),
        new("2101", "الموردون (ذمم دائنة)", AccountTypes.Liability, AccountRoles.Payables),
        // رصيد العميل المشحون **التزامٌ لا إيراد**: المال قُبض ولم تُسلَّم
        // بضاعة بعد، وللعميل أن يطلبه. تسجيله إيراداً يُضخّم أرباح الشهر
        // بمالٍ ليس ربحاً، ثم يُنقصها حين يُصرف فعلاً.
        new("2102", "أرصدة العملاء (محافظ)", AccountTypes.Liability, AccountRoles.CustomerWallet),
        new("2103", "ضريبة المبيعات المستحقّة", AccountTypes.Liability, AccountRoles.SalesTax),
        new("22", "حقوق الملكية", AccountTypes.Equity),
        new("2201", "رأس المال", AccountTypes.Equity),
        new("2202", "الأرباح المحتجزة", AccountTypes.Equity, AccountRoles.RetainedEarnings),

        // ── 3 الاستخدامات ───────────────────────────────────────────────
        new("3", "الاستخدامات", AccountTypes.Expense),
        new("31", "تكلفة المبيعات", AccountTypes.Expense),
        new("3101", "تكلفة البضاعة المباعة", AccountTypes.Expense, AccountRoles.CostOfGoodsSold),
        // مردودات المشتريات تحت تكلفة المبيعات لا تحت الإيرادات: البضاعة
        // المُعادة إلى المورّد تُنقص التكلفة لا تزيد الدخل.
        new("3102", "مردودات المشتريات", AccountTypes.Expense, AccountRoles.PurchaseReturns),
        new("32", "المصروفات التشغيلية", AccountTypes.Expense),
        new("3201", "مصروفات عمومية", AccountTypes.Expense, AccountRoles.GeneralExpense),
        new("3202", "رواتب وأجور", AccountTypes.Expense),
        new("3203", "إيجارات", AccountTypes.Expense),
        new("3204", "كهرباء وماء واتصالات", AccountTypes.Expense),

        // ── 4 الإيرادات ─────────────────────────────────────────────────
        new("4", "الإيرادات", AccountTypes.Revenue),
        new("41", "إيرادات النشاط", AccountTypes.Revenue),
        new("4101", "المبيعات", AccountTypes.Revenue, AccountRoles.SalesRevenue),
        // مردودات المبيعات حسابٌ مستقلّ لا خصمٌ من المبيعات: خصمُها يُخفي
        // حجم المرتجع تماماً، وهو رقمٌ يقول شيئاً عن جودة البضاعة والبيع.
        new("4102", "مردودات المبيعات", AccountTypes.Revenue, AccountRoles.SalesReturns),
        new("42", "إيرادات أخرى", AccountTypes.Revenue),
    };

    /// <summary>
    /// يبذر الدليل والربط لمنظمة، إن لم يكن مبذوراً.
    ///
    /// <para>لا يُنشئ شيئاً إن وُجد حساب واحد: إعادة البذر فوق دليل عدّله
    /// محاسب تمحو عمله. والدالة آمنة للاستدعاء المتكرّر لذلك.</para>
    /// </summary>
    /// <returns>true إن بُذر الآن، false إن كان موجوداً.</returns>
    public static async Task<bool> SeedAsync(AppDbContext db, Guid organizationId)
    {
        // سياسة العزل تحصر العدّ في منظمة الطالب.
        if (await db.Accounts.AnyAsync()) return false;

        var byCode = new Dictionary<string, Account>();

        foreach (var seed in Default)
        {
            var account = new Account
            {
                OrganizationId = organizationId,
                Code = seed.Code,
                Name = seed.Name,
                Type = seed.Type,
                // الأب رمزُه بادئةُ رمز الابن منقوصةً حرفين: 1101 ← 11 ← 1.
                // والترتيب في المصفوفة يضمن وجود الأب قبل ابنه.
                ParentId = ParentCodeOf(seed.Code) is { } parentCode && byCode.TryGetValue(parentCode, out var parent)
                    ? parent.Id
                    : null,
                // كل المبذورين حسابات نظام: الترحيل الآلي يعتمد عليها،
                // وحذف «المبيعات» يُوقف كل بيع في المحلّ.
                IsSystem = true,
                // يُضبَط بعد بناء الشجرة كاملة — أبٌ لا يُعرف أنه أبٌ إلا
                // بعد أن يُقرأ أبناؤه.
                IsPostable = true,
            };
            byCode[seed.Code] = account;
            db.Accounts.Add(account);
        }

        // الوسيط لا يُرحَّل إليه: قيدٌ على «الأصول» مباشرةً يجعل رصيد الأب
        // لا يساوي مجموع أبنائه.
        foreach (var seed in Default)
        {
            if (ParentCodeOf(seed.Code) is { } parentCode && byCode.TryGetValue(parentCode, out var parent))
            {
                parent.IsPostable = false;
            }
        }

        // الحسابات تُحفَظ **قبل** الربط.
        //
        // <para><b>العطب الذي يصلحه:</b> account_mappings يحمل مفتاحاً
        // خارجياً على accounts، و**EF لا يعرف هذا الاعتماد** لأن لا خاصية
        // تنقّل بينهما (مفتاح مركّب فقط). فيُدرج الربط قبل الحسابات فيرفضه
        // المفتاح الخارجي، ويفشل بذر الدليل كلّه بـ400 — ومعه كل بيع في
        // منظمة مفعَّلة المحاسبة.</para>
        //
        // <para>نفس ما وقع بين prescriptions وinvoices، وعُولج بنفس الترتيب.
        // وكلاهما داخل معاملة المستدعي، فإمّا يمرّان معاً أو لا شيء.</para>
        await db.SaveChangesAsync();

        foreach (var seed in Default.Where(s => s.Role is not null))
        {
            db.AccountMappings.Add(new AccountMapping
            {
                OrganizationId = organizationId,
                Role = seed.Role!,
                AccountId = byCode[seed.Code].Id,
            });
        }

        // حارسٌ على الشيفرة لا على البيانات: دورٌ مطلوب بلا حساب في المصفوفة
        // أعلاه يعني بيعاً يفشل عند الكاشير بعد أشهر من النشر. يُكتشف هنا،
        // في أول تفعيل على جهاز التطوير، لا هناك.
        var missing = AccountRoles.Required
            .Except(Default.Where(s => s.Role is not null).Select(s => s.Role!))
            .ToArray();
        if (missing.Length > 0)
        {
            throw new InvalidOperationException(
                $"الدليل الافتراضي بلا حساب للأدوار: {string.Join(", ", missing)}");
        }

        await db.SaveChangesAsync();
        return true;
    }

    /// <summary>
    /// يُكمل ما نقص من الحسابات والربط في دليلٍ مبذور سابقاً.
    ///
    /// <para><b>لماذا يلزم:</b> الأدوار تنمو مع كل نوع حركة جديد. فحين
    /// أُضيف ترحيل المشتريات لزم دور «الموردون»، ودليلٌ بُذر قبله لا يحمله —
    /// فيفشل أول استلام بضاعة برسالة «لا حساب مربوط بالدور». وترقيةٌ تُعطّل
    /// عملاً كان يعمل هي أسوأ ما يمكن أن تفعله ترقية.</para>
    ///
    /// <para>ويضيف ما نقص فقط: لا يلمس حساباً موجوداً ولا ربطاً قائماً —
    /// محاسبٌ ربط دوراً بحسابٍ من عنده أدرى بنشاطه منّا.</para>
    /// </summary>
    /// <returns>الأدوار التي أُضيفت الآن.</returns>
    public static async Task<List<string>> RepairMappingsAsync(AppDbContext db, Guid organizationId)
    {
        var added = new List<string>();
        if (!await db.Accounts.AnyAsync()) return added;

        var existingRoles = await db.AccountMappings.Select(m => m.Role).ToListAsync();
        var byCode = await db.Accounts.ToDictionaryAsync(a => a.Code, a => a);

        foreach (var seed in Default.Where(s => s.Role is not null))
        {
            if (existingRoles.Contains(seed.Role!)) continue;

            // الحساب نفسه قد يكون ناقصاً أيضاً (أُضيف إلى الدليل الافتراضي
            // بعد بذر هذه المنظمة) — فيُنشأ تحت أبيه.
            if (!byCode.TryGetValue(seed.Code, out var account))
            {
                var parent = ParentCodeOf(seed.Code) is { } pc ? byCode.GetValueOrDefault(pc) : null;
                account = new Account
                {
                    OrganizationId = organizationId,
                    Code = seed.Code,
                    Name = seed.Name,
                    Type = seed.Type,
                    ParentId = parent?.Id,
                    IsSystem = true,
                    IsPostable = true,
                };
                if (parent is not null) parent.IsPostable = false;
                db.Accounts.Add(account);
                byCode[seed.Code] = account;
                // يُحفَظ قبل ربطه — نفس سبب الترتيب في SeedAsync أعلاه.
                await db.SaveChangesAsync();
            }

            db.AccountMappings.Add(new AccountMapping
            {
                OrganizationId = organizationId,
                Role = seed.Role!,
                AccountId = account.Id,
            });
            added.Add(seed.Role!);
        }

        if (added.Count > 0) await db.SaveChangesAsync();
        return added;
    }

    /// <summary>رمز الأب: 1101 ← 11، و11 ← 1، و1 ← لا أب.</summary>
    private static string? ParentCodeOf(string code) =>
        code.Length <= 1 ? null : code[..^(code.Length == 2 ? 1 : 2)];
}
