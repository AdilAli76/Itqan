using Microsoft.EntityFrameworkCore;

namespace KineticEnterprise.Api.Data;

/// <summary>نتيجة التحقّق من ترخيص منظمة.</summary>
/// <param name="Valid">هل يُسمح بالكتابة.</param>
/// <param name="Message">سبب المنع، معروضاً للمستخدم كما هو.</param>
/// <param name="Payload">الحمولة الموقَّعة حين تكون صالحة.</param>
public record LicenseCheck(bool Valid, string? Message, LicensePayload? Payload);

/// <summary>
/// التحقّق من مفتاح الترخيص الموقَّع — الطريق الوحيد لتقرير صلاحيته.
///
/// <para><b>لماذا الاستنتاج من المفتاح لا من الجدول:</b> العميل في التركيب
/// المحلّي يملك القاعدة، فأعمدة <c>expires_at</c> و<c>max_branches</c>
/// و<c>status</c> بيانات عرض لا أدلّة. المفتاح الموقَّع وحده لا يُعدَّل بلا
/// المفتاح الخاصّ. راجع [LicenseSigning].</para>
///
/// <para><b>التخزين المؤقّت ضرورة لا تحسين:</b> التحقّق يقع على كل طلب
/// كتابة، والتحقّق من توقيع ECDsa عملية معالِج ملموسة. النتيجة تُحفَظ خمس
/// دقائق: قصيرة بما يكفي لأن يسري إلغاء ترخيص في اليوم نفسه، وطويلة بما
/// يكفي لألّا تُثقل نقطة بيع مزدحمة.</para>
/// </summary>
public static class LicenseVerification
{
    private static readonly Dictionary<Guid, (DateTime At, LicenseCheck Result)> _cache = new();
    private static readonly TimeSpan CacheFor = TimeSpan.FromMinutes(5);
    private static readonly object _gate = new();

    /// <summary>
    /// مهلة سماح بعد الانتهاء قبل منع الكتابة.
    ///
    /// <para>ARCHITECTURE.md §2.2: «قراءة فقط عند الانتهاء بدل توقّف مفاجئ
    /// يفقد ثقة الزبون». والسبعة أيام تكفي لتجديدٍ تأخّر لعطلة أو حوالة
    /// بنكية، ولا تكفي لأن تصبح عرفاً.</para>
    /// </summary>
    public const int GraceDays = 7;

    public static async Task<LicenseCheck> CheckAsync(AppDbContext db, IConfiguration config)
    {
        // سياسة العزل تُرجع ترخيص منظمة الطالب وحده.
        var license = await db.Licenses
            .Select(l => new { l.OrganizationId, l.LicenseKey, l.ExpiresAt, l.Status })
            .FirstOrDefaultAsync();

        // بلا ترخيص = بلا حاجز: تركيب لم يُرخَّص بعد (أثناء الإعداد الأول)
        // يجب ألّا يتوقّف قبل أن يُنشأ ترخيصه.
        if (license is null) return new LicenseCheck(true, null, null);

        lock (_gate)
        {
            if (_cache.TryGetValue(license.OrganizationId, out var hit) &&
                DateTime.UtcNow - hit.At < CacheFor)
            {
                return hit.Result;
            }
        }

        var result = Evaluate(license.OrganizationId, license.LicenseKey, config);

        lock (_gate)
        {
            _cache[license.OrganizationId] = (DateTime.UtcNow, result);
        }
        return result;
    }

    /// <summary>يُنسي النتيجة المحفوظة — يُستدعى بعد تجديد ترخيص أو تغييره.</summary>
    public static void Forget(Guid organizationId)
    {
        lock (_gate) { _cache.Remove(organizationId); }
    }

    /// <summary>
    /// يفحص مفتاحاً **قبل** حفظه — بلا لمس القاعدة ولا التخزين المؤقّت.
    ///
    /// <para>شاشة التفعيل تحتاجها: حفظُ مفتاح فاسد ثم اكتشافُ ذلك عند أوّل
    /// كتابة يترك العميل بنظامٍ للقراءة فقط ورسالةٍ يظنّها عطباً في الحفظ.
    /// وهي نفس [Evaluate] لا نسخةٌ ثانية منها — فحصٌ يُكتب مرّتين يفترق
    /// أوّل مرّة يُشدَّد أحدهما.</para>
    /// </summary>
    public static LicenseCheck Inspect(Guid organizationId, string licenseKey, IConfiguration config) =>
        Evaluate(organizationId, licenseKey, config);

    private static LicenseCheck Evaluate(Guid organizationId, string? licenseKey, IConfiguration config)
    {
        var publicKey = config["License:PublicKey"];

        // بلا مفتاح عامّ مضبوط لا يُفرَض شيء.
        //
        // **قرار مقصود:** الفشل هنا مفتوح لا مغلق. تركيبٌ قائم عند عميل
        // يعمل اليوم يجب ألّا يتوقّف لأن ترقيةً أضافت فحصاً ونسي أحدٌ ضبط
        // مفتاح. الحارس يُفعَّل بضبط المفتاح — وهو ما تفعله أداة التركيب
        // المحلّي — لا بمجرّد نشر نسخة.
        if (string.IsNullOrWhiteSpace(publicKey)) return new LicenseCheck(true, null, null);

        var payload = LicenseSigning.Verify(licenseKey, publicKey);
        if (payload is null)
        {
            return new LicenseCheck(false,
                "مفتاح الترخيص غير صالح أو عُدِّل. تواصل مع الدعم لإصدار مفتاح جديد.", null);
        }

        if (payload.OrganizationId != organizationId)
        {
            // مفتاح صحيح التوقيع لكنه لمنظمة أخرى: نسخُ قاعدة عميل إلى عميل
            // آخر. التوقيع وحده لا يكشفه — الربط بالمنظمة هو ما يكشفه.
            return new LicenseCheck(false,
                "مفتاح الترخيص صادر لمنظمة أخرى. تواصل مع الدعم.", null);
        }

        if (!string.IsNullOrWhiteSpace(payload.HardwareFingerprint) &&
            payload.HardwareFingerprint != HardwareFingerprint.Current())
        {
            return new LicenseCheck(false,
                "هذا الترخيص مرتبط بجهاز آخر. إن نُقل النظام إلى جهاز جديد فتواصل مع الدعم لإصدار مفتاح له.",
                payload);
        }

        var expiredFor = (DateTime.UtcNow.Date - payload.ExpiresAt.Date).Days;
        if (expiredFor > GraceDays)
        {
            return new LicenseCheck(false,
                $"انتهى الترخيص في {payload.ExpiresAt:yyyy-MM-dd} وانقضت مهلة السماح. " +
                "النظام في وضع القراءة فقط — بياناتك كاملة ولم يُحذف شيء.", payload);
        }

        return new LicenseCheck(true, null, payload);
    }
}
