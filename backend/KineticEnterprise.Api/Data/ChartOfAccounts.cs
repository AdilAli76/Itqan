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
    /// الدليل الافتراضي — موسَّعٌ على الدليل المحاسبي الموحّد.
    ///
    /// <para><b>كان مختصراً عمداً</b> بحجّة أن «كل حساب زائد سطرٌ في شجرة
    /// يقرؤها من لا يعرف المحاسبة». والتجربة قالت العكس: المحاسب يفتح
    /// الدليل فلا يجد «أوراق القبض» ولا «الرواتب المستحقّة» ولا «مجمّع
    /// الإهلاك»، فينشئها واحداً واحداً بترقيمٍ يخترعه — فيختلف دليل كل
    /// عميل عن الآخر، ويصير دعمُ عشرة عملاء عشرة أدلّة لا يعرف أحدٌ
    /// شكلها.</para>
    ///
    /// <para>وما زاد هنا ليس زينة: كلّ حسابٍ منه يقابل حركةً تقع فعلاً في
    /// محلٍّ صغير — سلفة موظّف، إيجار مدفوع مقدماً، ضريبة مشتريات تُستردّ،
    /// سحبٌ شخصي من الصندوق. وغيابُه لا يمنع الحركة بل يدفنها في «مصروفات
    /// عمومية».</para>
    ///
    /// <para>والحسابات الوسيطة تبقى قليلة والأوراق أكثر: الشجرة تُقرأ
    /// مطويّةً على مستواها الأول، فالعمق لا يُزعج من لا يفتحه.</para>
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
        new("1105", "أوراق القبض", AccountTypes.Asset),
        // ضريبة المشتريات أصلٌ لا مصروف: تُستردّ من ضريبة المبيعات
        // المستحقّة، وتسجيلُها مصروفاً يُضخّم التكلفة ويُنقص الربح بمالٍ
        // سيعود.
        new("1106", "ضريبة المشتريات (مدخلات)", AccountTypes.Asset),
        new("1107", "مصروفات مدفوعة مقدماً", AccountTypes.Asset),
        new("1108", "سلف وعُهد الموظفين", AccountTypes.Asset),
        new("12", "الأصول الثابتة", AccountTypes.Asset),
        new("1201", "أثاث ومعدّات", AccountTypes.Asset),
        new("1202", "أجهزة حاسب وبرمجيات", AccountTypes.Asset),
        new("1203", "سيارات ووسائل نقل", AccountTypes.Asset),
        new("1204", "مبانٍ وعقارات", AccountTypes.Asset),
        // مجمّع الإهلاك حسابٌ مقابل: رصيده دائن وهو تحت الأصول، فيُطرح
        // منها في الميزانية. وإبقاؤه هنا يجعل «صافي الأصول الثابتة» يُقرأ
        // من الشجرة مباشرةً.
        new("1205", "مجمّع إهلاك الأصول الثابتة", AccountTypes.Asset),

        // ── 2 الالتزامات وحقوق الملكية ──────────────────────────────────
        new("2", "الالتزامات وحقوق الملكية", AccountTypes.Liability),
        new("21", "الالتزامات المتداولة", AccountTypes.Liability),
        new("2101", "الموردون (ذمم دائنة)", AccountTypes.Liability, AccountRoles.Payables),
        // رصيد العميل المشحون **التزامٌ لا إيراد**: المال قُبض ولم تُسلَّم
        // بضاعة بعد، وللعميل أن يطلبه. تسجيله إيراداً يُضخّم أرباح الشهر
        // بمالٍ ليس ربحاً، ثم يُنقصها حين يُصرف فعلاً.
        new("2102", "أرصدة العملاء (محافظ)", AccountTypes.Liability, AccountRoles.CustomerWallet),
        new("2103", "ضريبة المبيعات المستحقّة", AccountTypes.Liability, AccountRoles.SalesTax),
        // بضاعة في المخزن لم تصل فاتورتها بعد. التزامٌ حقيقي لا حساب وسيط
        // للزينة: البضاعة دخلت والدَّين قائم، وإنما لم تُحدَّد قيمته نهائياً
        // حتى تصل ورقة المورّد.
        new("2104", "بضاعة وردت ولم تُفوتَر", AccountTypes.Liability, AccountRoles.GoodsReceivedNotInvoiced),
        new("2105", "أوراق الدفع", AccountTypes.Liability),
        new("2106", "رواتب وأجور مستحقّة", AccountTypes.Liability),
        new("2107", "مصروفات مستحقّة", AccountTypes.Liability),
        new("2108", "إيرادات مقبوضة مقدماً", AccountTypes.Liability),
        // مصاريف شحنةٍ رُسملت على المخزون ولم تصل فاتورة ناقلها بعد.
        //
        // مستقلٌّ عن 2104: ذاك رصيد ما سيطالب به **المورّد** ويُفرَّغ
        // بفاتورته، وهذا ما يطالب به الناقل والمخلّص — وخلطهما يجعل رصيد
        // «وردت ولم تُفوتَر» لا يطابق كشف أي مورّد فيبطل استعماله للمطابقة.
        //
        // ورمزُه في آخر المجموعة لا في موضعه «المنطقي»: إقحامُه بينها يعني
        // إزاحة أرقام حساباتٍ مبذورة عند عملاء يعملون بها منذ شهور — فيصير
        // 2105 عند القديم «أوراق الدفع» وعند الجديد «مصاريف شحن»، ولا يعود
        // رقمُ الحساب يعني شيئاً واحداً في كل الجهات.
        new("2109", "مصاريف شحن مستحقّة", AccountTypes.Liability, AccountRoles.LandedCostAccrual),
        new("22", "حقوق الملكية", AccountTypes.Equity),
        new("2201", "رأس المال", AccountTypes.Equity),
        new("2202", "الأرباح المحتجزة", AccountTypes.Equity, AccountRoles.RetainedEarnings),
        // جاري الشركاء والمسحوبات: أكثر ما يُخلط في محلّات الأفراد — صاحب
        // المحلّ يأخذ من الصندوق لبيته، فيُقيَّد مصروفاً فيُنقص الربح وهو
        // ليس مصروفاً بل سحبٌ من حقّه.
        new("2203", "جاري الشركاء", AccountTypes.Equity),
        new("2204", "المسحوبات الشخصية", AccountTypes.Equity),
        new("23", "الالتزامات طويلة الأجل", AccountTypes.Liability),
        new("2301", "قروض طويلة الأجل", AccountTypes.Liability),

        // ── 3 الاستخدامات ───────────────────────────────────────────────
        new("3", "الاستخدامات", AccountTypes.Expense),
        new("31", "تكلفة المبيعات", AccountTypes.Expense),
        new("3101", "تكلفة البضاعة المباعة", AccountTypes.Expense, AccountRoles.CostOfGoodsSold),
        // مردودات المشتريات تحت تكلفة المبيعات لا تحت الإيرادات: البضاعة
        // المُعادة إلى المورّد تُنقص التكلفة لا تزيد الدخل.
        new("3102", "مردودات المشتريات", AccountTypes.Expense, AccountRoles.PurchaseReturns),
        // فروق أسعار المشتريات — ظاهرةً لا مدفونة في تكلفة المخزون. رصيدُه
        // المتراكم يقول كم يُكلّف المورّد الذي يرفع سعره بعد الاتفاق.
        new("3103", "فروق أسعار المشتريات", AccountTypes.Expense, AccountRoles.PurchasePriceVariance),
        new("3104", "مصاريف شحن ونقل المشتريات", AccountTypes.Expense),
        // عجز الجرد مصروفٌ مستقلّ لا يُدفن في تكلفة البضاعة المباعة: رقمٌ
        // يُقرأ وحده يقول كم يضيع من الرفّ في السنة.
        new("3105", "عجز وفروق الجرد", AccountTypes.Expense),
        new("32", "المصروفات التشغيلية", AccountTypes.Expense),
        new("3201", "مصروفات عمومية", AccountTypes.Expense, AccountRoles.GeneralExpense),
        new("3202", "رواتب وأجور", AccountTypes.Expense),
        new("3203", "إيجارات", AccountTypes.Expense),
        new("3204", "كهرباء وماء واتصالات", AccountTypes.Expense),
        new("3205", "صيانة وإصلاح", AccountTypes.Expense),
        new("3206", "قرطاسية ومطبوعات", AccountTypes.Expense),
        new("3207", "دعاية وإعلان", AccountTypes.Expense),
        new("3208", "نقل ومواصلات", AccountTypes.Expense),
        new("3209", "رسوم ومصاريف حكومية", AccountTypes.Expense),
        new("3210", "مصاريف مصرفية وعمولات", AccountTypes.Expense),
        new("3211", "إهلاك الأصول الثابتة", AccountTypes.Expense),
        new("33", "مصروفات أخرى", AccountTypes.Expense),
        new("3301", "فوائد وأعباء تمويلية", AccountTypes.Expense),
        new("3302", "ديون معدومة", AccountTypes.Expense),

        // ── 4 الإيرادات ─────────────────────────────────────────────────
        new("4", "الإيرادات", AccountTypes.Revenue),
        new("41", "إيرادات النشاط", AccountTypes.Revenue),
        new("4101", "المبيعات", AccountTypes.Revenue, AccountRoles.SalesRevenue),
        // مردودات المبيعات حسابٌ مستقلّ لا خصمٌ من المبيعات: خصمُها يُخفي
        // حجم المرتجع تماماً، وهو رقمٌ يقول شيئاً عن جودة البضاعة والبيع.
        new("4102", "مردودات المبيعات", AccountTypes.Revenue, AccountRoles.SalesReturns),
        new("4103", "خصم مكتسب من الموردين", AccountTypes.Revenue),
        new("42", "إيرادات أخرى", AccountTypes.Revenue),
        new("4201", "إيرادات متنوّعة", AccountTypes.Revenue),
        new("4202", "أرباح بيع أصول ثابتة", AccountTypes.Revenue),
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

        // ── معاملةٌ تلفّ البذر كلّه ─────────────────────────────────────
        //
        // <para><b>سبب وجودها:</b> البذر صار يُحفَظ على موجات (الآباء ثم
        // الأبناء) ثم يُحفَظ الربط. وبلا معاملة، فشلٌ في الموجة الثالثة
        // يترك دليلاً نصفَ مبذور: أقسامٌ بلا حسابات، وأدوارٌ بلا ربط —
        // ولا يعود البذر يعمل لأنه يرى حساباً موجوداً فيمتنع. وقع ذلك
        // فعلاً في قاعدة اختبار فبقيت أربعة عشر حساباً يتيمة.</para>
        //
        // <para>وتُحترَم معاملة المستدعي إن وُجدت: تأسيس منظمةٍ جديدة يبذر
        // الدليل داخل معاملته الكبرى، ومعاملةٌ ثانية داخلها ليست مدعومة.
        // </para>
        var ownsTransaction = db.Database.CurrentTransaction is null;
        var transaction = ownsTransaction ? await db.Database.BeginTransactionAsync() : null;

        try
        {

        var byCode = new Dictionary<string, Account>();

        // ── الإدراج على موجات: الآباء ثم الأبناء ────────────────────────
        //
        // <para><b>العطب الذي يمنعه:</b> parent_id مفتاحٌ أجنبي على نفس
        // الجدول، ولا خاصية تنقّل بين الحساب وأبيه في النموذج — فـEF لا
        // يعرف الاعتماد ولا يرتّب الإدراج له. وكان يعمل ما دام الدليل
        // ثلاثين حساباً في دفعةٍ واحدة، فلمّا صار ستّين انقسم إلى دفعتين
        // فوقع ابنٌ قبل أبيه: <c>FOREIGN KEY SAME TABLE constraint</c>،
        // وبذرُ الدليل كلّه يفشل — ومعه أوّل تفعيل للمحاسبة.</para>
        //
        // <para>والموجة طول الرمز: الأب أقصر من ابنه في كل دليل متدرّج،
        // وحفظُ كل موجة قبل التالية يجعل الترتيب مضموناً بلا اعتمادٍ على
        // تفصيلٍ داخلي في EF.</para>
        foreach (var wave in Default.GroupBy(x => x.Code.Length).OrderBy(g => g.Key))
        {
        foreach (var seed in wave)
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
                // حسابُ نظامٍ هو **ما يُربَط بدور** لا كل مبذور.
                //
                // كان الكل يُختَم نظاماً بحجّة أن «الترحيل الآلي يعتمد
                // عليها» — وهو صحيحٌ في اثني عشر حساباً مربوطاً بدور
                // (المبيعات، الصندوق، المخزون…) وغيرُ صحيح في البقيّة:
                // «أثاث ومعدّات» و«إيجارات» و«الأصول الثابتة» لا يعتمد
                // عليها ترحيلٌ ولا يمسّها بيع. وختمُها نظاماً منع صاحب
                // المحلّ من إعادة تسميتها أو إعادة ترتيب شجرته على نشاطه،
                // ومنع استيراد دليل بلدٍ آخر فوقها. أي أن الحماية صارت
                // قفلاً على الدليل كلّه.
                IsSystem = seed.Role is not null,
                // يُضبَط بعد بناء الشجرة كاملة — أبٌ لا يُعرف أنه أبٌ إلا
                // بعد أن يُقرأ أبناؤه.
                IsPostable = true,
            };
            byCode[seed.Code] = account;
            db.Accounts.Add(account);
        }

        // الموجة تُحفَظ قبل التي تليها — وإلا وقع ابنٌ قبل أبيه.
        await db.SaveChangesAsync();
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

        if (transaction is not null) await transaction.CommitAsync();
        return true;
        }
        catch
        {
            if (transaction is not null) await transaction.RollbackAsync();
            throw;
        }
        finally
        {
            if (transaction is not null) await transaction.DisposeAsync();
        }
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
