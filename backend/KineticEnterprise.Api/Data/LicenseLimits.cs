using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// فرض حدود الترخيص — الطريق الوحيد لقياسها في النظام.
///
/// <para><b>العطب الذي يصلحه:</b> <c>MaxBranches</c> و<c>MaxUsers</c> و
/// <c>EnabledModulesJson</c> كانت **تُعرَض ولا تُفرَض**. عميلٌ بترخيص فرع
/// واحد ينشئ خمسين، وبترخيص خمسة مستخدمين ينشئ مئة — أي أن الترخيص كان
/// وثيقةً لا حاجزاً، ولا شيء يمنع شركةً من بيع النظام تحت اسمها لغيرها.</para>
///
/// <para><b>لماذا نقطة واحدة:</b> نفس درس [StockLedger] — الحدّ الذي
/// يُفحَص في كل وحدة تحكّم على حدة يُنسى في الوحدة التالية. وحاجزٌ ينطبق
/// على تسعة مسارات من عشرة ليس حاجزاً.</para>
/// </summary>
public static class LicenseLimits
{
    /// <summary>
    /// يرمي إن بلغت المنظمة سقف الفروع.
    ///
    /// <para>بلا ترخيص = بلا حدّ: تركيبٌ لم يُرخَّص بعد (أثناء الإعداد
    /// الأول) يجب ألّا يتوقّف. والترخيص يُنشأ مع المنظمة في المسار الطبيعي
    /// فلا تبقى هذه الحالة قائمة.</para>
    /// </summary>
    public static async Task EnsureCanAddBranchAsync(AppDbContext db, Guid organizationId)
    {
        var license = await db.Licenses.FirstOrDefaultAsync(l => l.OrganizationId == organizationId);
        if (license is null || license.MaxBranches <= 0) return;

        var current = await db.Branches.CountAsync(b => b.OrganizationId == organizationId);
        if (current >= license.MaxBranches)
        {
            throw new LicenseLimitException(
                $"بلغت الحدّ الأقصى للفروع في ترخيصك ({license.MaxBranches}). " +
                "لإضافة فرع جديد تواصل مع الدعم لترقية الباقة.");
        }
    }

    /// <summary>
    /// يرمي إن بلغت المنظمة سقف المستخدمين.
    ///
    /// <para>يُحسب **النشطون** وحدهم: تعطيل موظف غادر يجب أن يُفرِج عن مقعده،
    /// وإلا اضطُرّ العميل إلى حذف السجلّ فيفقد أثر من فعل ماذا.</para>
    /// </summary>
    public static async Task EnsureCanAddUserAsync(AppDbContext db, Guid organizationId)
    {
        var license = await db.Licenses.FirstOrDefaultAsync(l => l.OrganizationId == organizationId);
        if (license is null || license.MaxUsers <= 0) return;

        var current = await db.AppUsers.CountAsync(u => u.OrganizationId == organizationId && u.IsActive);
        if (current >= license.MaxUsers)
        {
            throw new LicenseLimitException(
                $"بلغت الحدّ الأقصى للمستخدمين في ترخيصك ({license.MaxUsers}). " +
                "عطّل مستخدماً لم يعد يعمل، أو تواصل مع الدعم لترقية الباقة.");
        }
    }

    /// <summary>
    /// الوحدات المفعَّلة فعلياً = ما يسمح به شكل الإصدار **و** ما اشتراه
    /// الترخيص.
    ///
    /// <para><b>لماذا الاثنان معاً:</b> الإصدار يقول ما **شكل** النظام
    /// (محفظة بلا مخزون، صيدلية بنشرات)، والترخيص يقول ما **دُفع ثمنه**.
    /// الاكتفاء بالإصدار — وهو ما كان — يجعل قائمة وحدات الترخيص زينةً،
    /// فيحصل من اشترى الأدنى على ما لم يشترِه.</para>
    ///
    /// <para><b>وقائمة فارغة تعني «كل وحدات الإصدار» لا «لا شيء»:</b>
    /// تراخيص أُنشئت قبل هذا الفرض قد تحمل قائمة قديمة، وتفسيرها حرفياً
    /// كان يقطع وحدةً يستعملها العميل اليوم — عقوبةٌ على ترقيةٍ لا ذنب له
    /// فيها. راجع تعبئة MIGRATIONS التي تُزامن القوائم مع الإصدارات.</para>
    /// </summary>
    public static string[] EffectiveModules(string edition, string? enabledModulesJson)
    {
        var fromEdition = Editions.ModulesOf(edition);
        if (string.IsNullOrWhiteSpace(enabledModulesJson)) return fromEdition;

        List<string>? licensed;
        try
        {
            licensed = JsonSerializer.Deserialize<List<string>>(enabledModulesJson);
        }
        catch (JsonException)
        {
            // قائمة تالفة لا تُسقط النظام: يُرجَع إلى الإصدار ويُترك
            // التصحيح لمالك المنصّة. الفشل المغلق هنا يمنع عميلاً من العمل
            // بسبب حقل نصّي معطوب.
            return fromEdition;
        }

        if (licensed is null || licensed.Count == 0) return fromEdition;
        return fromEdition.Where(licensed.Contains).ToArray();
    }
}

/// <summary>
/// حدّ ترخيص بُلِغ — رسالتها تُعرض للمستخدم كما هي، فهي مكتوبة له لا
/// للمطوّر (تقول الحدّ، وتقول ما العمل).
/// </summary>
public class LicenseLimitException : Exception
{
    public LicenseLimitException(string message) : base(message) { }
}
