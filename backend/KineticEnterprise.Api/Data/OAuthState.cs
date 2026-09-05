using System.Security.Cryptography;
using System.Text;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// معرّف المنظمة محمولاً في رحلة OAuth وموقَّعاً.
///
/// <para><b>العطب الذي يمنعه:</b> نقطة العودة من قوقل تأتي **بلا توكن** —
/// المتصفّح يعود من نطاق قوقل لا من التطبيق، فلا ترويسة تفويض فيها. ولو
/// حملت الحالةُ معرّف المنظمة نصّاً عارياً لاستطاع أي أحد استدعاء نقطة
/// العودة بمعرّف منظمةٍ ليست له ورمزِ موافقةٍ من حسابه هو — فتصير نسخُ
/// تلك المنظمة تُرفع إلى درايفه.</para>
///
/// <para>والتوقيع بمفتاح JWT نفسه: مفتاحٌ ثانٍ يعني سرّاً ثانياً يُنسى عند
/// النشر، وهذا يكفي — ولا يُوقَّع به إلا ما لا قيمة له بعد دقائق.</para>
/// </summary>
public static class OAuthState
{
    /// <summary>عشر دقائق: مدّة شاشة موافقة، لا مدّة جلسة.</summary>
    static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);

    public static string Sign(Guid organizationId, IConfiguration config)
    {
        var expires = DateTimeOffset.UtcNow.Add(Lifetime).ToUnixTimeSeconds();
        var payload = $"{organizationId}.{expires}";
        return $"{payload}.{Signature(payload, config)}";
    }

    public static bool TryRead(string state, IConfiguration config, out Guid organizationId)
    {
        organizationId = Guid.Empty;

        var parts = state.Split('.');
        if (parts.Length != 3) return false;

        var payload = $"{parts[0]}.{parts[1]}";
        // مقارنة ثابتة الزمن: المقارنة العادية تُسرّب طول البادئة الصحيحة
        // لمن يجرّب مراراً.
        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(Signature(payload, config)),
                Encoding.UTF8.GetBytes(parts[2]))) return false;

        if (!long.TryParse(parts[1], out var expires)) return false;
        if (DateTimeOffset.FromUnixTimeSeconds(expires) < DateTimeOffset.UtcNow) return false;

        return Guid.TryParse(parts[0], out organizationId);
    }

    static string Signature(string payload, IConfiguration config)
    {
        var key = config["Jwt:Key"] ?? "";
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(key));
        return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(payload)));
    }
}
