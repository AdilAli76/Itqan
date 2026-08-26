using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>سطرُ قيدٍ قبل حفظه — دورٌ ومبلغ، لا معرّف حساب.</summary>
/// <param name="Role">دور من [AccountRoles] — يُحلّ إلى حساب عبر الربط.</param>
public record PostingLine(string Role, decimal Debit, decimal Credit, string? Note = null);

/// <summary>
/// دفتر اليومية — **الطريق الوحيد** لكتابة قيد.
///
/// <para><b>لماذا طريق واحد:</b> نفس درس [StockLedger] بالضبط. مسار كتابة
/// ثانٍ يعني قيداً غير متوازن أو بلا مصدر، ودفترٌ به سطرٌ واحد خاطئ لا يصلح
/// لإثبات شيء — والفرق بين دفتر ودفتر هو أنه لا يُخترق من الجانب.</para>
///
/// <para><b>وحرمة القيد:</b> ما كُتب لا يُعدَّل ولا يُحذف. التصحيح بقيد عكسي
/// يشير إلى أصله — راجع <see cref="ReverseAsync"/>.</para>
/// </summary>
public static class Ledger
{
    /// <summary>
    /// هل وحدة المحاسبة مفعَّلة لهذه المنظمة.
    ///
    /// <para>الترحيل يقع فقط حين تكون مفعَّلة. ومنظمةٌ بإصدار قياسي لا تُنشأ
    /// لها قيود إطلاقاً — لا قيود فارغة ولا جداول تنتفخ بلا قارئ.</para>
    /// </summary>
    public static bool IsEnabled(Organization org, License? license) =>
        LicenseLimits.EffectiveModules(org.Edition, license?.EnabledModulesJson).Contains("accounting");

    /// <summary>
    /// يكتب قيداً متوازناً من أدوار محاسبية.
    ///
    /// <para><b>يُستدعى داخل معاملة المستند نفسه.</b> فاتورةٌ بلا قيدها ثقبٌ
    /// في الدفتر لا يُكتشف إلا عند المراجعة، ومحاولة الترحيل لاحقاً بمهمّة
    /// خلفية تعني دفتراً يتخلّف عن الواقع بمقدار ما تعطّلت المهمّة.</para>
    ///
    /// <para><b>ولا يُبتلع فشله:</b> إن تعذّر الترحيل تسقط العملية كلّها.
    /// قد يبدو هذا قاسياً — بيعٌ يفشل لعلّة محاسبية — لكن البديل بيعٌ ينجح
    /// وحسابٌ لا يعلم به، وهو ما تُشترى الأنظمة المحاسبية لمنعه. والحالة لا
    /// تقع من سوء إعداد أصلاً: الربط يُبذَر كاملاً مع الدليل ويُتحقَّق منه
    /// عند البذر (راجع [ChartOfAccounts]).</para>
    /// </summary>
    public static async Task<JournalEntry> PostAsync(
        AppDbContext db,
        Guid organizationId,
        Guid? branchId,
        string source,
        Guid? sourceId,
        string description,
        IEnumerable<PostingLine> lines,
        Guid? createdBy,
        DateTime? entryDate = null)
    {
        var material = lines.Where(l => l.Debit != 0 || l.Credit != 0).ToList();
        if (material.Count == 0)
        {
            // الرسالة تحمل مصدرها ووصفها: «قيد بلا سطور» وحدها لا تقول عن أي
            // مستند، فيبقى من يقرأ السجلّ يبحث في كل فواتير الدقيقة.
            throw new InvalidOperationException(
                $"قيد بلا سطور — لا شيء يُرحَّل. المصدر {source}، الوصف «{description}».");
        }

        var debit = material.Sum(l => l.Debit);
        var credit = material.Sum(l => l.Credit);

        // التوازن يُفحَص هنا قبل أي كتابة.
        //
        // القيد غير المتوازن يُفسد ميزان المراجعة **إلى الأبد**: لا يظهر في
        // أي شاشة بيع، ولا يُكتشف إلا يوم يُقفل الحساب فلا يُعرف أي قيدٍ من
        // آلاف القيود سببه. والمقارنة على قرشين لا على المساواة التامّة،
        // لأن decimal مضروبة في نسب (ضريبة، خصم) تُقرَّب.
        if (Math.Abs(debit - credit) > 0.01m)
        {
            throw new InvalidOperationException(
                $"قيد غير متوازن: مدين {debit:0.##} ودائن {credit:0.##} — لم يُكتب شيء. " +
                $"المصدر {source}، الوصف «{description}».");
        }

        var mappings = await EnsureChartAsync(db, organizationId);

        var entry = new JournalEntry
        {
            OrganizationId = organizationId,
            BranchId = branchId,
            Number = await NextNumberAsync(db),
            EntryDate = entryDate ?? DateTime.UtcNow.Date,
            Source = source,
            SourceId = sourceId,
            Description = description,
            CreatedBy = createdBy,
        };

        foreach (var line in material)
        {
            if (!mappings.TryGetValue(line.Role, out var accountId))
            {
                throw new InvalidOperationException(
                    $"لا حساب مربوط بالدور «{line.Role}» — راجع ربط الحسابات.");
            }
            entry.Lines.Add(new JournalEntryLine
            {
                AccountId = accountId,
                Debit = line.Debit,
                Credit = line.Credit,
                Note = line.Note,
            });
        }

        db.JournalEntries.Add(entry);
        return entry;
    }

    /// <summary>
    /// قيدٌ يخلط حسابات بأعيانها مع أدوار محاسبية.
    ///
    /// <para><b>لماذا يلزم:</b> معظم القيود تُبنى من أدوار ثابتة (الصندوق،
    /// المبيعات) لأن النظام هو من يقرّرها. لكن **المصروف يختار حسابه لحظة
    /// تسجيله** — الإيجار على «إيجارات» والراتب على «رواتب وأجور» — ولا دور
    /// ثابتاً لكلٍّ منهما، ولا يصحّ اختراع دور لكل حساب مصروف يُنشئه محاسب.
    /// </para>
    ///
    /// <para>ويمرّ بنفس فحص التوازن ونفس مولّد الرقم: طريقٌ ثانٍ يلتفّ عليهما
    /// يُبطل معنى الطريق الواحد.</para>
    /// </summary>
    /// <param name="direct">سطور بحسابات بأعيانها: (الحساب، مدين، دائن، ملاحظة).</param>
    /// <param name="byRole">سطور بأدوار — تُحلّ من الربط.</param>
    public static async Task<JournalEntry> PostToAccountsAsync(
        AppDbContext db,
        Guid organizationId,
        Guid? branchId,
        string source,
        Guid? sourceId,
        string description,
        IEnumerable<(Guid AccountId, decimal Debit, decimal Credit, string? Note)> direct,
        IEnumerable<PostingLine> byRole,
        Guid? createdBy,
        DateTime? entryDate = null)
    {
        var directLines = direct.Where(l => l.Debit != 0 || l.Credit != 0).ToList();
        var roleLines = byRole.Where(l => l.Debit != 0 || l.Credit != 0).ToList();

        if (directLines.Count + roleLines.Count == 0)
        {
            throw new InvalidOperationException("قيد بلا سطور — لا شيء يُرحَّل.");
        }

        var debit = directLines.Sum(l => l.Debit) + roleLines.Sum(l => l.Debit);
        var credit = directLines.Sum(l => l.Credit) + roleLines.Sum(l => l.Credit);
        if (Math.Abs(debit - credit) > 0.01m)
        {
            throw new InvalidOperationException(
                $"قيد غير متوازن: مدين {debit:0.##} ودائن {credit:0.##} — لم يُكتب شيء. " +
                $"المصدر {source}، الوصف «{description}».");
        }

        var mappings = await EnsureChartAsync(db, organizationId);

        var entry = new JournalEntry
        {
            OrganizationId = organizationId,
            BranchId = branchId,
            Number = await NextNumberAsync(db),
            EntryDate = entryDate ?? DateTime.UtcNow.Date,
            Source = source,
            SourceId = sourceId,
            Description = description,
            CreatedBy = createdBy,
        };

        foreach (var (accountId, d, c, note) in directLines)
        {
            entry.Lines.Add(new JournalEntryLine { AccountId = accountId, Debit = d, Credit = c, Note = note });
        }

        foreach (var line in roleLines)
        {
            if (!mappings.TryGetValue(line.Role, out var accountId))
            {
                throw new InvalidOperationException(
                    $"لا حساب مربوط بالدور «{line.Role}» — راجع ربط الحسابات.");
            }
            entry.Lines.Add(new JournalEntryLine
            {
                AccountId = accountId,
                Debit = line.Debit,
                Credit = line.Credit,
                Note = line.Note,
            });
        }

        db.JournalEntries.Add(entry);
        return entry;
    }

    /// <summary>
    /// يعكس قيداً — التصحيح الوحيد المسموح.
    ///
    /// <para>يُنشئ قيداً بنفس السطور مقلوبةً، ويشير إلى الأصل. فيبقى الخطأ
    /// مرئياً وتصحيحُه مرئياً معه — وهو المطلوب: من راجع الدفتر يرى ما حدث
    /// فعلاً، لا ما أُريد له أن يراه.</para>
    /// </summary>
    public static async Task<JournalEntry> ReverseAsync(
        AppDbContext db, Guid entryId, string reason, Guid? createdBy)
    {
        var original = await db.JournalEntries
            .Include(e => e.Lines)
            .FirstOrDefaultAsync(e => e.Id == entryId)
            ?? throw new InvalidOperationException("القيد غير موجود.");

        // عكسُ العكس يُنتج دورةً لا نهاية لها من التصحيحات المتقابلة، ولا
        // يزيد الدفتر إلا ضجيجاً — الحساب عاد إلى ما كان بعد أول عكس.
        var alreadyReversed = await db.JournalEntries.AnyAsync(e => e.ReversesEntryId == entryId);
        if (alreadyReversed)
        {
            throw new InvalidOperationException("هذا القيد معكوس أصلاً.");
        }

        var reversal = new JournalEntry
        {
            OrganizationId = original.OrganizationId,
            BranchId = original.BranchId,
            Number = await NextNumberAsync(db),
            // تاريخ اليوم لا تاريخ الأصل: العكس حدثٌ وقع اليوم، وتأريخه
            // بالماضي يغيّر أرقام شهرٍ أُقفل وصدرت عنه تقارير.
            EntryDate = DateTime.UtcNow.Date,
            Source = JournalSources.Reversal,
            SourceId = original.SourceId,
            Description = $"عكس القيد {original.Number} — {reason}",
            ReversesEntryId = original.Id,
            CreatedBy = createdBy,
        };

        foreach (var line in original.Lines)
        {
            reversal.Lines.Add(new JournalEntryLine
            {
                AccountId = line.AccountId,
                Debit = line.Credit,
                Credit = line.Debit,
            });
        }

        db.JournalEntries.Add(reversal);
        return reversal;
    }

    /// <summary>
    /// يضمن وجود دليل حسابات مربوط قبل أي ترحيل.
    ///
    /// <para><b>الفخّ الذي يُغلقه:</b> منظمةٌ بإصدار المؤسسات تُنشأ ووحدة
    /// المحاسبة مفعَّلة، لكن الدليل لا يُبذَر إلا بطلب صريح من الشاشة. وبين
    /// الأمرين **لا تستطيع المنظمة أن تبيع إطلاقاً**: كل فاتورة تصطدم بـ«لا
    /// حساب مربوط بالدور cash» وتعود 500 غامضاً عند الكاشير.</para>
    ///
    /// <para>وهذا أسوأ ما يمكن أن تفعله وحدة محاسبة: أن تُعطّل البيع.</para>
    ///
    /// <para><b>ولماذا البذر هنا لا تخطّي الترحيل:</b> التخطّي يعني فاتورة
    /// بلا قيدها — وهو الثقب الصامت الذي بُني هذا الدفتر لمنعه. والبذر
    /// حتميّ وآمن للتكرار: لا يلمس دليلاً موجوداً، ولا ربطاً قائماً.</para>
    /// </summary>
    private static async Task<Dictionary<string, Guid>> EnsureChartAsync(
        AppDbContext db, Guid organizationId)
    {
        var mappings = await db.AccountMappings.ToDictionaryAsync(m => m.Role, m => m.AccountId);
        if (mappings.Count > 0) return mappings;

        // بذرٌ كامل إن لم يكن ثمّة دليل، وإكمالُ ربطٍ ناقص إن كان.
        if (!await ChartOfAccounts.SeedAsync(db, organizationId))
        {
            await ChartOfAccounts.RepairMappingsAsync(db, organizationId);
        }

        return await db.AccountMappings.ToDictionaryAsync(m => m.Role, m => m.AccountId);
    }

    /// <summary>
    /// الرقم التالي لدفتر هذه المنظمة، بقفل نطاق.
    ///
    /// <para><b>لماذا ليس IDENTITY:</b> يترك فجوات عند أي تراجع، وفجوةٌ في
    /// تسلسل دفتر اليومية سؤالٌ يطرحه كل مراجع — «أين القيد رقم ٤١٧؟».</para>
    ///
    /// <para><b>ولماذا HOLDLOCK:</b> بدونه تقرأ عمليتان متزامنتان نفس
    /// الأقصى فتطلبان نفس الرقم، فتفشل إحداهما على فهرس التفرّد — أي بيعٌ
    /// يُرفض عند الكاشير لأن بيعاً آخر وقع في اللحظة نفسها. القفل يمنع
    /// إدراج صفٍّ جديد في النطاق حتى نهاية المعاملة، وهو نفس نمط
    /// [WalletBalances].</para>
    /// </summary>
    private static async Task<long> NextNumberAsync(AppDbContext db)
    {
        var connection = db.Database.GetDbConnection();
        if (connection.State != System.Data.ConnectionState.Open)
        {
            await connection.OpenAsync();
        }

        await using var cmd = connection.CreateCommand();
        if (db.Database.CurrentTransaction?.GetDbTransaction() is { } tx)
        {
            cmd.Transaction = tx;
        }
        // سياسة العزل تحصر الصفوف في منظمة الطالب، فلا شرط organization_id.
        cmd.CommandText =
            "SELECT ISNULL(MAX(number), 0) + 1 FROM dbo.journal_entries WITH (UPDLOCK, HOLDLOCK);";

        var result = await cmd.ExecuteScalarAsync();
        var fromDatabase = result is null or DBNull ? 1L : Convert.ToInt64(result);

        // ورقمُ ما لم يُحفَظ بعد.
        //
        // <para><b>العطب الذي يصلحه:</b> الفاتورة تكتب **قيدين** في نداء
        // واحد (إثبات الإيراد ثم نقل التكلفة)، وكلاهما يستدعي هذه الدالة
        // قبل أن يُحفظ الأول — فتقرأ القاعدة نفس الأقصى فيأخذان الرقم نفسه،
        // ويسقط الحفظ على UQ_journal_entries_number. أي أن **كل بيع في
        // منظمة مفعَّلة المحاسبة يفشل**.</para>
        //
        // <para>ولا يكفي الحفظ بين النداءين: يبقى الاعتماد على انتباه من
        // يكتب المسار التالي، وهو ما يهدم معنى الطريق الواحد.</para>
        var staged = db.ChangeTracker.Entries<JournalEntry>()
            .Where(e => e.State == EntityState.Added)
            .Select(e => e.Entity.Number)
            .DefaultIfEmpty(0)
            .Max();

        return Math.Max(fromDatabase, staged + 1);
    }
}
