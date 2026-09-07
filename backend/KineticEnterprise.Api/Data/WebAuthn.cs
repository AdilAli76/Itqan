using System.Formats.Cbor;
using System.Security.Cryptography;
using System.Text.Json;

namespace KineticEnterprise.Api.Data;

/// <summary>
/// تحقّقٌ من مفاتيح المرور (WebAuthn/FIDO2) بأدوات المنصّة وحدها.
///
/// <para><b>لماذا بلا مكتبة:</b> مكتبات FIDO2 الجاهزة تجرّ اعتمادياتٍ
/// أصلية (libsodium عبر NSec) إلى خادم IIS يُنشر بحزمة مضغوطة تُفكّ يدوياً،
/// وعطبُ تحميل مكتبةٍ أصلية هناك يظهر خطأً بلا نصّ في سجلّ الحدث. وما
/// نحتاجه من المواصفة قسمٌ صغير محدود: قراءة بنيتين، ثم تحقّق توقيعٍ
/// بـ<see cref="ECDsa"/> و<see cref="RSA"/> من المنصّة نفسها.</para>
///
/// <para><b>وما لا يُفعَل هنا عمداً — التحقّق من شهادة المُصادِق
/// (attestation):</b> فائدته أن تعرف الجهةُ طرازَ الجهاز الذي يحمل المفتاح،
/// وهي تلزم من يشترط أجهزةً معتمدة. وهذا الاستعمال — فتح جلسةٍ مقفلة قائمة
/// أصلاً — لا يشترط طرازاً، فيُقبل «none» وغيره ولا تُقرأ عبارة الشهادة.
/// والأمان لا يقوم عليها بل على أن المفتاح الخاص لا يغادر الجهاز، وأن
/// التوقيع يُفحص على تحدٍّ من عندنا لم يُستعمل قبله.</para>
/// </summary>
public static class WebAuthn
{
    /// <summary>ترميز base64url — صيغة WebAuthn لكل ما هو بايتات.</summary>
    public static string ToBase64Url(ReadOnlySpan<byte> bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    /// <summary>
    /// فكّ base64url. والحشو يُعاد لأن <see cref="Convert.FromBase64String"/>
    /// يرفض نصّاً غير مكتمل الطول — والمتصفّح لا يرسل الحشو أصلاً.
    /// </summary>
    public static byte[] FromBase64Url(string value)
    {
        var s = value.Trim().Replace('-', '+').Replace('_', '/');
        var padding = (4 - (s.Length % 4)) % 4;
        return Convert.FromBase64String(s + new string('=', padding));
    }

    /// <summary>تحدٍّ عشوائي — ٣٢ بايتاً كما توصي المواصفة.</summary>
    public static byte[] NewChallenge() => RandomNumberGenerator.GetBytes(32);

    /// <summary>ما وقّعه المتصفّح عن نفسه: نوع العملية، والتحدّي، والأصل.</summary>
    public sealed record ClientData(string Type, string Challenge, string Origin);

    public static ClientData ParseClientData(byte[] clientDataJson)
    {
        using var doc = JsonDocument.Parse(clientDataJson);
        var root = doc.RootElement;
        return new ClientData(
            root.TryGetProperty("type", out var t) ? t.GetString() ?? "" : "",
            root.TryGetProperty("challenge", out var c) ? c.GetString() ?? "" : "",
            root.TryGetProperty("origin", out var o) ? o.GetString() ?? "" : "");
    }

    /// <summary>
    /// بيانات المُصادِق: بصمة النطاق، وأعلامُ الحضور والتحقّق، وعدّاد
    /// التوقيع، ثم بيانات الاعتماد إن كان هذا تسجيلاً.
    /// </summary>
    public sealed record AuthenticatorData(
        byte[] RpIdHash,
        bool UserPresent,
        bool UserVerified,
        uint SignCount,
        byte[]? CredentialId,
        byte[]? CredentialPublicKey);

    /// <summary>
    /// قراءة بنية authenticatorData الثنائية.
    ///
    /// <para>ترتيبها ثابت: ٣٢ بايت بصمة النطاق، ثم بايت أعلام، ثم أربعة
    /// بايتات للعدّاد بترتيب الشبكة. وإن رُفع علم AT تبعتها بيانات الاعتماد:
    /// ١٦ بايت معرّف الطراز، وطولُ معرّف الاعتماد في بايتين، والمعرّف، ثم
    /// المفتاح العامّ بترميز COSE.</para>
    /// </summary>
    public static AuthenticatorData ParseAuthenticatorData(byte[] data)
    {
        if (data.Length < 37) throw new FormatException("بيانات المُصادِق أقصر من أن تكون صحيحة");

        var rpIdHash = data[..32];
        var flags = data[32];
        var userPresent = (flags & 0x01) != 0;
        var userVerified = (flags & 0x04) != 0;
        var attestedIncluded = (flags & 0x40) != 0;

        // ترتيب الشبكة لا ترتيب المعالج: BitConverter يقرأ بترتيب الجهاز،
        // وعلى x86 يعطي عدّاداً مقلوباً يفشل فحص الاستنساخ بلا سبب ظاهر.
        var signCount = (uint)((data[33] << 24) | (data[34] << 16) | (data[35] << 8) | data[36]);

        if (!attestedIncluded)
            return new AuthenticatorData(rpIdHash, userPresent, userVerified, signCount, null, null);

        if (data.Length < 55) throw new FormatException("بيانات الاعتماد ناقصة");

        var credentialIdLength = (data[53] << 8) | data[54];
        var idStart = 55;
        if (data.Length < idStart + credentialIdLength)
            throw new FormatException("طول معرّف الاعتماد يتجاوز البيانات");

        var credentialId = data[idStart..(idStart + credentialIdLength)];

        // المفتاح قيمةٌ واحدة قد تتبعها امتدادات، فيُقرأ بالقارئ لا بأخذ
        // ما بقي: أخذُ الباقي كان يضمّ الامتدادات إلى المفتاح فيفسد.
        var reader = new CborReader(data.AsMemory(idStart + credentialIdLength));
        var publicKey = reader.ReadEncodedValue().ToArray();

        return new AuthenticatorData(
            rpIdHash, userPresent, userVerified, signCount, credentialId, publicKey);
    }

    /// <summary>
    /// استخراج authenticatorData من غلاف التسجيل (attestationObject).
    /// وهو خريطة CBOR مفاتيحها نصّية: fmt وattStmt وauthData.
    /// </summary>
    public static AuthenticatorData ParseAttestationObject(byte[] attestationObject)
    {
        var reader = new CborReader(attestationObject);
        var count = reader.ReadStartMap();
        byte[]? authData = null;

        for (var i = 0; count is null ? reader.PeekState() != CborReaderState.EndMap : i < count; i++)
        {
            var key = reader.ReadTextString();
            if (key == "authData") authData = reader.ReadByteString();
            else reader.SkipValue();
        }
        reader.ReadEndMap();

        if (authData is null) throw new FormatException("غلاف التسجيل بلا authData");
        return ParseAuthenticatorData(authData);
    }

    /// <summary>
    /// تحقّق التوقيع بالمفتاح العامّ المخزَّن بترميز COSE.
    ///
    /// <para>المدعوم: ES256 (المنحنى P-256) وRS256 — وهما ما تصدره أجهزة
    /// أندرويد وويندوز والمتصفّحات عملياً. وEdDSA يُرفض صراحةً لأن المنصّة
    /// لا تتحقّق منه بلا مكتبة خارجية، ورفضٌ بنصٍّ واضح خيرٌ من قبولٍ
    /// كاذب.</para>
    /// </summary>
    public static bool VerifySignature(byte[] coseKey, byte[] signedData, byte[] signature)
    {
        var key = ReadCoseKey(coseKey);

        // 2 = EC2، 3 = RSA (جدول أنواع مفاتيح COSE)
        if (key.KeyType == 2)
        {
            if (key.Algorithm != -7) throw new NotSupportedException($"خوارزمية غير مدعومة: {key.Algorithm}");
            if (key.X is null || key.Y is null) throw new FormatException("مفتاح EC2 بلا إحداثيات");

            using var ecdsa = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = key.X, Y = key.Y },
            });

            // التوقيع يأتي بصيغة DER من المُصادِق لا بصيغة r‖s الخام —
            // والتحقّق بالصيغة الخاطئة يفشل دائماً بلا خطأ يفسّر.
            return ecdsa.VerifyData(signedData, signature, HashAlgorithmName.SHA256,
                DSASignatureFormat.Rfc3279DerSequence);
        }

        if (key.KeyType == 3)
        {
            if (key.Algorithm != -257) throw new NotSupportedException($"خوارزمية غير مدعومة: {key.Algorithm}");
            if (key.N is null || key.E is null) throw new FormatException("مفتاح RSA ناقص");

            using var rsa = RSA.Create(new RSAParameters { Modulus = key.N, Exponent = key.E });
            return rsa.VerifyData(signedData, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        }

        throw new NotSupportedException($"نوع مفتاح غير مدعوم: {key.KeyType}");
    }

    sealed record CoseKey(int KeyType, int Algorithm, byte[]? X, byte[]? Y, byte[]? N, byte[]? E);

    /// <summary>
    /// قراءة مفتاح COSE: خريطة مفاتيحها أعداد. و‎-1 تعني المنحنى في مفاتيح
    /// EC2 والمُعامل في مفاتيح RSA — فتُقرأ القيم أوّلاً ثم تُفسَّر حسب النوع.
    /// </summary>
    static CoseKey ReadCoseKey(byte[] coseKey)
    {
        var reader = new CborReader(coseKey);
        var count = reader.ReadStartMap();

        var keyType = 0;
        var algorithm = 0;
        byte[]? first = null;   // ‎-2: إحداثي x أو الأس
        byte[]? second = null;  // ‎-3: إحداثي y
        byte[]? modulus = null; // ‎-1 في RSA
        var curve = 0;          // ‎-1 في EC2

        for (var i = 0; count is null ? reader.PeekState() != CborReaderState.EndMap : i < count; i++)
        {
            if (reader.PeekState() is not (CborReaderState.UnsignedInteger or CborReaderState.NegativeInteger))
            {
                reader.SkipValue();
                reader.SkipValue();
                continue;
            }

            var label = reader.ReadInt32();
            switch (label)
            {
                case 1: keyType = reader.ReadInt32(); break;
                case 3: algorithm = reader.ReadInt32(); break;
                case -1:
                    // في EC2 عددٌ (المنحنى)، وفي RSA بايتات (المُعامل).
                    if (reader.PeekState() == CborReaderState.ByteString) modulus = reader.ReadByteString();
                    else curve = reader.ReadInt32();
                    break;
                case -2: first = reader.ReadByteString(); break;
                case -3: second = reader.ReadByteString(); break;
                default: reader.SkipValue(); break;
            }
        }
        reader.ReadEndMap();

        if (keyType == 2 && curve != 1)
            throw new NotSupportedException($"منحنى غير مدعوم: {curve} — المدعوم P-256");

        return keyType == 3
            ? new CoseKey(keyType, algorithm, null, null, modulus, first)
            : new CoseKey(keyType, algorithm, first, second, null, null);
    }

    /// <summary>بصمة النطاق كما يحسبها المُصادِق: SHA-256 لاسم النطاق نصّاً.</summary>
    public static byte[] RpIdHash(string rpId) =>
        SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(rpId));

    /// <summary>
    /// ما يُوقَّع عليه في التحقّق: بيانات المُصادِق موصولةً ببصمة نصّ العميل.
    /// </summary>
    public static byte[] SignedData(byte[] authenticatorData, byte[] clientDataJson)
    {
        var clientDataHash = SHA256.HashData(clientDataJson);
        var signed = new byte[authenticatorData.Length + clientDataHash.Length];
        authenticatorData.CopyTo(signed, 0);
        clientDataHash.CopyTo(signed, authenticatorData.Length);
        return signed;
    }

    /// <summary>
    /// مقارنة بايتات بزمنٍ ثابت — التحدّي والبصمة يُقارَنان بها لا بـ==.
    /// </summary>
    public static bool FixedTimeEquals(byte[] a, byte[] b) =>
        CryptographicOperations.FixedTimeEquals(a, b);
}
