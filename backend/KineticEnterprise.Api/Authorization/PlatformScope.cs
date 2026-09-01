using System.Security.Claims;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Authorization;

/// <summary>
/// حدود حساب المنصّة: أمالكٌ هو أم مهندس بيع، وأيّ العملاء يخصّه.
///
/// <para><b>لماذا صنفٌ واحد لا فحصٌ في كل نقطة:</b> نفس درس
/// [LicenseLimits] و[StockLedger]. سبع نقاط في [PlatformController] تمسّ
/// منظمة بعينها (تعديل، حالة، تحذير، حسابات، إعادة كلمة مرور، حذف،
/// طباعة). حاجزٌ يُكتب في ستٍّ ويُنسى في السابعة ليس حاجزاً — والسابعة هي
/// التي تُسرّب عميل مهندسٍ إلى مهندسٍ آخر.</para>
///
/// <para><b>والعزل هنا ليس عزل الصفوف في القاعدة.</b> ذاك يفصل بين
/// **المنظمات** ويبقى قائماً كما هو. وهذا يفصل بين **بائعي** المنظمات —
/// وكلاهما يقرأ الفهرس العالمي غير المحميّ عمداً، فلا شيء في القاعدة
/// يمنع مهندساً من رؤية عملاء غيره. المنع كلّه هنا.</para>
/// </summary>
public static class PlatformScope
{
    /// <summary>أهذا الطلب من حساب منصّة أصلاً؟</summary>
    public static bool IsPlatformUser(ClaimsPrincipal user) =>
        string.Equals(user.FindFirstValue("is_platform_admin"), "True", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// أمالكُ المنصّة هو؟ — غياب الدعوى يعني نعم.
    ///
    /// <para>توكنٌ أُصدر قبل ترحيل الأدوار يبقى صالحاً ثماني ساعات، وتفسير
    /// غيابه «مهندس» كان يسلب المالك صلاحياته حتى ينتهي — بلا رسالة تدلّه
    /// على السبب.</para>
    /// </summary>
    public static bool IsOwner(ClaimsPrincipal user) =>
        IsPlatformUser(user) && PlatformRoles.IsOwner(user.FindFirstValue("platform_role"));

    /// <summary>معرّف حساب المنصّة الطالب، أو <c>null</c> إن تعذّر.</summary>
    public static Guid? UserId(ClaimsPrincipal user) =>
        Guid.TryParse(user.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    /// <summary>
    /// أيرى هذا الطالبُ منظمةً نُسبت إلى <paramref name="ownerUserId"/>؟
    ///
    /// <para>المالك يرى الكلّ. والمهندس يرى ما نُسب إليه وحده — و<c>null</c>
    /// (منظمة أُنشئت قبل وجود المهندسين) لا تخصّ أحداً منهم: لا أحد باعها
    /// غير المالك، ومنحُها لأول مهندس يفتحها كان يُسلّمه عملاء لم يبعهم.</para>
    /// </summary>
    public static bool CanSee(ClaimsPrincipal user, Guid? ownerUserId)
    {
        if (IsOwner(user)) return true;
        var me = UserId(user);
        return me is not null && ownerUserId == me;
    }
}
