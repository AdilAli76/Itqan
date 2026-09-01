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
    /// الوحدات المفعَّلة فعلياً = وحدات الإصدار **زائد ما اشتُري فوقه ناقص
    /// ما سُحب منه**.
    ///
    /// <para><b>الإصدار قالبٌ ابتدائي لا سقف.</b> كانت هذه الدالّة تُرجع
    /// <em>تقاطع</em> وحدات الإصدار مع قائمة الترخيص، فيمكن سحب وحدة ولا
    /// يمكن إضافة واحدة أبداً — وبيعُ وحدةٍ منفردة بعد التسليم (نشرة الدواء
    /// لبقّالة كبرت، المحاسبة لمن بدأ قياسياً) كان يستلزم نقل العميل إلى
    /// إصدارٍ آخر بكامله، فتُغرَق قائمته بمستودعات وتقييمٍ ومشترياتٍ لا
    /// معنى لها عنده — وهو عين ما تتجنّبه [Editions].</para>
    ///
    /// <para><b>والسحب يغلب المنح:</b> اسمٌ ورد في القائمتين معاً صفٌّ
    /// متناقض، وإغلاقه أسلم من فتحه — أسوأ ما يحدث عندها شكوى عميل من وحدة
    /// ناقصة، مقابل عميلٍ يعمل بوحدة لم تُبَع.</para>
    ///
    /// <para><b>ولماذا لا تُقرأ [License.EnabledModulesJson] هنا:</b> هي
    /// مشتقّةٌ تُكتب من هذه الدالّة نفسها لتُعرض في شاشة العميل وعقده.
    /// قراءتها للفرض تجعلها مصدر حقيقةٍ ثانياً يفترق عن الأوّل أوّل مرّة
    /// يُعدَّل صفٌّ من خارج المسار — وقائمةٌ تُفرض ولا يعرف أحد من كتبها
    /// أسوأ من قائمة زينة.</para>
    /// </summary>
    public static string[] EffectiveModules(string edition, string? grantedJson, string? revokedJson)
    {
        var granted = ParseModules(grantedJson);
        var revoked = ParseModules(revokedJson);

        return Editions.ModulesOf(edition)
            .Concat(granted)
            .Distinct(StringComparer.Ordinal)
            .Where(m => !revoked.Contains(m))
            .ToArray();
    }

    /// <summary>
    /// الوحدات الفعّالة لترخيصٍ قد لا يكون موجوداً بعد.
    ///
    /// <para>بلا ترخيص = وحدات الإصدار كما هي: تركيبٌ لم يُرخَّص بعد يجب
    /// ألّا يُحرَم من شكل النظام الذي اختاره — نفس منطق
    /// [EnsureCanAddBranchAsync].</para>
    /// </summary>
    public static string[] EffectiveModules(string edition, License? license) =>
        EffectiveModules(edition, license?.GrantedModulesJson, license?.RevokedModulesJson);

    /// <summary>
    /// قائمة أسماء وحدات من نصّ JSON — التالف والفارغ سواء: لا شيء.
    ///
    /// <para>الفشل المفتوح هنا مقصود وآمن، بخلاف ما كان: الفوارق تبدأ
    /// فارغة، فحقلٌ معطوب يُرجع العميل إلى وحدات إصداره لا إلى نظامٍ
    /// معطَّل.</para>
    /// </summary>
    private static HashSet<string> ParseModules(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new HashSet<string>(StringComparer.Ordinal);
        try
        {
            var list = JsonSerializer.Deserialize<List<string>>(json);
            return new HashSet<string>(list ?? new List<string>(), StringComparer.Ordinal);
        }
        catch (JsonException)
        {
            return new HashSet<string>(StringComparer.Ordinal);
        }
    }

    /// <summary>
    /// يُزامن [License.EnabledModulesJson] المشتقّة مع الإصدار والفوارق.
    ///
    /// <para>تُستدعى من **كل** مسار يُنشئ ترخيصاً أو يُعدّل إصداره أو
    /// فوارقه. تركُها لموضعٍ واحد يعني شاشةَ ترخيصٍ عند العميل تعرض غير ما
    /// يفرضه الخادم فعلاً — وهو أسوأ من ألّا تعرض شيئاً.</para>
    /// </summary>
    public static void MaterializeModules(License license, string edition) =>
        license.EnabledModulesJson = JsonSerializer.Serialize(EffectiveModules(edition, license));

    /// <summary>
    /// يُنقّي قائمة وحدات واردة من الواجهة: المعروف وحده، بلا تكرار.
    ///
    /// <para>اسمٌ مكتوب بخطأ يُقبل صامتاً ثم لا يُطابق أي
    /// [RequireModuleAttribute] — فيدفع العميل ثمن وحدة ولا يراها، ولا شيء
    /// في النظام يقول لماذا.</para>
    /// </summary>
    public static string[] SanitizeModules(IEnumerable<string>? modules) =>
        (modules ?? Enumerable.Empty<string>())
            .Select(m => m?.Trim() ?? "")
            .Where(Editions.AllModules.Contains)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
}

/// <summary>
/// حدّ ترخيص بُلِغ — رسالتها تُعرض للمستخدم كما هي، فهي مكتوبة له لا
/// للمطوّر (تقول الحدّ، وتقول ما العمل).
/// </summary>
public class LicenseLimitException : Exception
{
    public LicenseLimitException(string message) : base(message) { }
}
