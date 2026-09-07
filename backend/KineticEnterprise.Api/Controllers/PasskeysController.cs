using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Models;

namespace KineticEnterprise.Api.Controllers;

/// <summary>مفتاحٌ مسجَّل كما يراه صاحبه — لا بايتاته.</summary>
public record PasskeySummary(Guid Id, string Label, DateTime CreatedAt, DateTime? LastUsedAt);

/// <summary>ما يحتاجه المتصفّح ليطلب إنشاء مفتاح: تحدٍّ، ونطاق، وهويّة صاحبه.</summary>
public record PasskeyRegisterOptions(
    string Challenge, string RpId, string RpName,
    string UserId, string UserName, string UserDisplayName,
    List<string> ExcludeCredentials);

public record PasskeyRegisterRequest(
    string Label, string CredentialId, string ClientDataJson, string AttestationObject);

/// <summary>ما يحتاجه المتصفّح ليطلب توقيعاً: تحدٍّ، ونطاق، والمفاتيح المقبولة.</summary>
public record PasskeyUnlockOptions(string Challenge, string RpId, List<string> AllowCredentials);

public record PasskeyUnlockRequest(
    string CredentialId, string ClientDataJson, string AuthenticatorData, string Signature);

/// <summary>
/// مفاتيح المرور: تسجيلُها، وفتحُ الجلسة المقفلة بها.
///
/// <para><b>سبب وجودها:</b> الشاشة تبقى مفتوحةً على حساب المدير بينما يقوم
/// من مكتبه. والقفل موجود، لكنّه لا يُستعمل ما دام فتحُه يعني كتابة كلمة
/// مرورٍ طويلة عشرين مرّةً في اليوم — فتُترك الشاشة مفتوحة، أو تُكتب كلمة
/// المرور على ورقةٍ تحت لوحة المفاتيح. وكلاهما أسوأ من غياب القفل، لأن
/// أحداً يظنّ أن هناك قفلاً.</para>
///
/// <para><b>وكل نقاط النهاية هنا خلف [Authorize] — بلا استثناء:</b> المفتاح
/// يفتح جلسةً قائمةً مقفلة، ولا يُصدِر جلسةً من العدم. فلا يُضاف بهذا سطحُ
/// هجومٍ جديد قبل الدخول: من لا توكن معه لا يبلغ هذه النقاط أصلاً. وتوسيعه
/// إلى دخولٍ كاملٍ بلا كلمة مرور قرارُ إدارةٍ يُتخذ على حدة، لا أثرٌ جانبيّ
/// لإضافة قفل.</para>
///
/// <para><b>والتحقّق يُلزم UserVerified لا الحضور وحده:</b> علم الحضور
/// (UP) يعني أن أحداً لمس الجهاز، وهو لا يميّز صاحب الحساب ممّن جلس مكانه.
/// وعلم التحقّق (UV) يعني أن الجهاز استوثق من الشخص — ببصمةٍ أو وجهٍ أو
/// رمز الجهاز. وقفلٌ يفتحه من جلس على الكرسي ليس قفلاً.</para>
/// </summary>
[ApiController]
[Route("api/passkeys")]
[Authorize]
public class PasskeysController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IMemoryCache _cache;
    private readonly IConfiguration _config;

    public PasskeysController(AppDbContext db, IMemoryCache cache, IConfiguration config)
    {
        _db = db;
        _cache = cache;
        _config = config;
    }

    /// <summary>
    /// عمر التحدّي.
    ///
    /// <para>دقيقتان: تكفي لمن يبحث عن إصبعه على القارئ أو يفتح هاتفه،
    /// ولا تطول فيبقى تحدٍّ صالحاً في الذاكرة بعد أن ترك صاحبه المكتب.</para>
    /// </summary>
    static readonly TimeSpan ChallengeLifetime = TimeSpan.FromMinutes(2);

    // ── القراءة ─────────────────────────────────────────────────────────

    [HttpGet]
    public async Task<ActionResult<List<PasskeySummary>>> List()
    {
        var userId = CurrentUserId();
        if (userId is null) return Unauthorized();

        return await _db.UserPasskeys
            .Where(p => p.UserId == userId)
            .OrderByDescending(p => p.CreatedAt)
            .Select(p => new PasskeySummary(p.Id, p.Label, p.CreatedAt, p.LastUsedAt))
            .ToListAsync();
    }

    // ── التسجيل ─────────────────────────────────────────────────────────

    [HttpPost("register/begin")]
    public async Task<ActionResult<PasskeyRegisterOptions>> RegisterBegin()
    {
        var userId = CurrentUserId();
        if (userId is null) return Unauthorized();

        var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null) return Unauthorized();

        var challenge = WebAuthn.NewChallenge();
        _cache.Set(ChallengeKey("register", user.Id), challenge, ChallengeLifetime);

        // المفاتيح القائمة تُستثنى: بلا ذلك يسجّل الجهاز نفسه مفتاحاً ثانياً
        // بلا أن ينبّه صاحبه، فتمتلئ القائمة بأسماء متطابقة لا يعرف أيّها
        // يحذف.
        var existing = await _db.UserPasskeys
            .Where(p => p.UserId == user.Id)
            .Select(p => p.CredentialId)
            .ToListAsync();

        return new PasskeyRegisterOptions(
            Challenge: WebAuthn.ToBase64Url(challenge),
            RpId: RelyingPartyId(),
            RpName: _config["Passkeys:RelyingPartyName"] ?? "Kinetic Enterprise",
            // معرّف المستخدم بايتات معرّفه لا بريده: المواصفة تنصّ على ألّا
            // يحمل معرّف المستخدم بياناتٍ شخصية — وهو يُخزَّن على الجهاز.
            UserId: WebAuthn.ToBase64Url(user.Id.ToByteArray()),
            UserName: string.IsNullOrWhiteSpace(user.Username) ? user.Email : user.Username!,
            UserDisplayName: user.FullName,
            ExcludeCredentials: existing);
    }

    [HttpPost("register/complete")]
    public async Task<IActionResult> RegisterComplete(PasskeyRegisterRequest request)
    {
        var userId = CurrentUserId();
        var orgId = CurrentOrganizationId();
        if (userId is null || orgId is null) return Unauthorized();

        if (!_cache.TryGetValue(ChallengeKey("register", userId.Value), out byte[]? challenge)
            || challenge is null)
            return BadRequest(new { message = "انتهت مهلة التسجيل — أعد المحاولة" });

        // التحدّي يُستهلك مهما كانت النتيجة: بقاؤه بعد محاولةٍ فاشلة يسمح
        // بإعادة استعمال ردٍّ التُقط من محاولةٍ سابقة.
        _cache.Remove(ChallengeKey("register", userId.Value));

        WebAuthn.AuthenticatorData authData;
        try
        {
            var clientDataJson = WebAuthn.FromBase64Url(request.ClientDataJson);
            var clientData = WebAuthn.ParseClientData(clientDataJson);

            if (clientData.Type != "webauthn.create")
                return BadRequest(new { message = "نوع العملية غير متوقَّع" });
            if (!ChallengeMatches(clientData.Challenge, challenge))
                return BadRequest(new { message = "التحدّي لا يطابق — أعد المحاولة" });
            if (!IsOriginAllowed(clientData.Origin))
                return BadRequest(new { message = $"أصلٌ غير مقبول: {clientData.Origin}" });

            authData = WebAuthn.ParseAttestationObject(WebAuthn.FromBase64Url(request.AttestationObject));
        }
        catch (Exception ex) when (ex is FormatException or System.Text.Json.JsonException)
        {
            return BadRequest(new { message = "ردُّ الجهاز غير مقروء — أعد المحاولة" });
        }

        var rejection = VerifyAuthenticatorData(authData);
        if (rejection is not null) return BadRequest(new { message = rejection });

        if (authData.CredentialId is null || authData.CredentialPublicKey is null)
            return BadRequest(new { message = "الجهاز لم يُرسل مفتاحاً — أعد المحاولة" });

        var credentialId = WebAuthn.ToBase64Url(authData.CredentialId);

        // الفهرس الفريد هو الضمانة، وهذا الفحص هو الرسالة: بلا هذا يرى
        // المستخدم «تعذّرت العملية» على قيدٍ في القاعدة.
        if (await _db.UserPasskeys.AnyAsync(p => p.CredentialId == credentialId))
            return BadRequest(new { message = "هذا المفتاح مسجَّل بالفعل" });

        var label = string.IsNullOrWhiteSpace(request.Label)
            ? "مفتاح"
            : request.Label.Trim();
        if (label.Length > 80) label = label[..80];

        _db.UserPasskeys.Add(new UserPasskey
        {
            OrganizationId = orgId.Value,
            UserId = userId.Value,
            CredentialId = credentialId,
            PublicKey = authData.CredentialPublicKey,
            SignCount = authData.SignCount,
            Label = label,
        });

        _db.LogAudit(orgId.Value, userId, "passkey.registered", "user_passkeys", null,
            newValues: new { Label = label });
        await _db.SaveChangesAsync();

        return Ok(new { message = "سُجِّل المفتاح" });
    }

    // ── فتح القفل ───────────────────────────────────────────────────────

    [HttpPost("unlock/begin")]
    public async Task<ActionResult<PasskeyUnlockOptions>> UnlockBegin()
    {
        var userId = CurrentUserId();
        if (userId is null) return Unauthorized();

        var allowed = await _db.UserPasskeys
            .Where(p => p.UserId == userId)
            .Select(p => p.CredentialId)
            .ToListAsync();

        if (allowed.Count == 0)
            return BadRequest(new { message = "لا مفاتيح مسجَّلة لهذا الحساب" });

        var challenge = WebAuthn.NewChallenge();
        _cache.Set(ChallengeKey("unlock", userId.Value), challenge, ChallengeLifetime);

        return new PasskeyUnlockOptions(WebAuthn.ToBase64Url(challenge), RelyingPartyId(), allowed);
    }

    [HttpPost("unlock/complete")]
    public async Task<IActionResult> UnlockComplete(PasskeyUnlockRequest request)
    {
        var userId = CurrentUserId();
        var orgId = CurrentOrganizationId();
        if (userId is null || orgId is null) return Unauthorized();

        if (!_cache.TryGetValue(ChallengeKey("unlock", userId.Value), out byte[]? challenge)
            || challenge is null)
            return BadRequest(new { message = "انتهت مهلة الفتح — أعد المحاولة" });

        _cache.Remove(ChallengeKey("unlock", userId.Value));

        // مفاتيح صاحب الجلسة وحده: بلا شرط UserId يفتح مفتاحُ موظفٍ آخر
        // جلسةَ هذا الحساب لأن التوقيع صحيحٌ في ذاته.
        var passkey = await _db.UserPasskeys
            .FirstOrDefaultAsync(p => p.CredentialId == request.CredentialId && p.UserId == userId);
        if (passkey is null) return BadRequest(new { message = "مفتاح غير معروف لهذا الحساب" });

        bool verified;
        WebAuthn.AuthenticatorData authData;
        try
        {
            var clientDataJson = WebAuthn.FromBase64Url(request.ClientDataJson);
            var clientData = WebAuthn.ParseClientData(clientDataJson);

            if (clientData.Type != "webauthn.get")
                return BadRequest(new { message = "نوع العملية غير متوقَّع" });
            if (!ChallengeMatches(clientData.Challenge, challenge))
                return BadRequest(new { message = "التحدّي لا يطابق — أعد المحاولة" });
            if (!IsOriginAllowed(clientData.Origin))
                return BadRequest(new { message = $"أصلٌ غير مقبول: {clientData.Origin}" });

            var rawAuthData = WebAuthn.FromBase64Url(request.AuthenticatorData);
            authData = WebAuthn.ParseAuthenticatorData(rawAuthData);

            var rejection = VerifyAuthenticatorData(authData);
            if (rejection is not null) return BadRequest(new { message = rejection });

            verified = WebAuthn.VerifySignature(
                passkey.PublicKey,
                WebAuthn.SignedData(rawAuthData, clientDataJson),
                WebAuthn.FromBase64Url(request.Signature));
        }
        catch (NotSupportedException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
        catch (Exception ex) when (ex is FormatException or System.Text.Json.JsonException
                                      or System.Security.Cryptography.CryptographicException)
        {
            return BadRequest(new { message = "ردُّ الجهاز غير مقروء — أعد المحاولة" });
        }

        if (!verified)
        {
            _db.LogAudit(orgId.Value, userId, "passkey.rejected", "user_passkeys", passkey.Id);
            await _db.SaveChangesAsync();
            return BadRequest(new { message = "التوقيع غير صالح" });
        }

        // عدّاد التوقيع: عودتُه إلى الوراء تعني نسخةً ثانية من المفتاح.
        // ولا يُفحص إلا إذا كان الطرفان غير صفرين — مفاتيح المرور المزامَنة
        // تُبقيه صفراً دائماً، ورفضُها بذلك يعطّل الميزة على أشيع الأجهزة.
        if (passkey.SignCount > 0 && authData.SignCount > 0 && authData.SignCount <= passkey.SignCount)
        {
            _db.LogAudit(orgId.Value, userId, "passkey.counter_regressed", "user_passkeys", passkey.Id,
                oldValues: new { Stored = passkey.SignCount }, newValues: new { Received = authData.SignCount });
            await _db.SaveChangesAsync();
            return BadRequest(new { message = "عدّاد المفتاح رجع إلى الوراء — احذف المفتاح وسجّله من جديد" });
        }

        passkey.SignCount = authData.SignCount;
        passkey.LastUsedAt = DateTime.UtcNow;
        _db.LogAudit(orgId.Value, userId, "passkey.unlocked", "user_passkeys", passkey.Id);
        await _db.SaveChangesAsync();

        return Ok(new { message = "فُتح القفل" });
    }

    // ── الحذف ───────────────────────────────────────────────────────────

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Remove(Guid id)
    {
        var userId = CurrentUserId();
        var orgId = CurrentOrganizationId();
        if (userId is null || orgId is null) return Unauthorized();

        var passkey = await _db.UserPasskeys.FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId);
        if (passkey is null) return NotFound(new { message = "المفتاح غير موجود" });

        _db.UserPasskeys.Remove(passkey);
        _db.LogAudit(orgId.Value, userId, "passkey.removed", "user_passkeys", id,
            oldValues: new { passkey.Label });
        await _db.SaveChangesAsync();

        return Ok(new { message = "حُذف المفتاح" });
    }

    // ── المشترك ─────────────────────────────────────────────────────────

    static string ChallengeKey(string purpose, Guid userId) => $"passkey:{purpose}:{userId}";

    /// <summary>
    /// فحوصٌ لازمة على بيانات المُصادِق في التسجيل والفتح معاً.
    /// يُعيد سبب الرفض، و<c>null</c> إن مرّت.
    /// </summary>
    string? VerifyAuthenticatorData(WebAuthn.AuthenticatorData authData)
    {
        if (!WebAuthn.FixedTimeEquals(authData.RpIdHash, WebAuthn.RpIdHash(RelyingPartyId())))
            return "المفتاح صادرٌ لنطاقٍ آخر";
        if (!authData.UserPresent)
            return "لم يؤكّد الجهاز حضور المستخدم";
        if (!authData.UserVerified)
            return "لم يتحقّق الجهاز من هويّة صاحبه — فعّل البصمة أو رمز الجهاز";
        return null;
    }

    bool ChallengeMatches(string received, byte[] expected)
    {
        try
        {
            return WebAuthn.FixedTimeEquals(WebAuthn.FromBase64Url(received), expected);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    /// <summary>
    /// نطاق الاعتماد: من الإعدادات إن ضُبط، وإلا مضيفُ الطلب نفسه.
    ///
    /// <para>الاشتقاق من الطلب ليس تساهلاً: المضيف يضبطه IIS من ربط الموقع
    /// لا العميل. وضبطُه في الإعدادات يلزم من يخدم النظام على أكثر من نطاق
    /// — لأن مفتاحاً سُجِّل على نطاقٍ لا يعمل على غيره بحكم المواصفة.</para>
    /// </summary>
    string RelyingPartyId()
    {
        var configured = _config["Passkeys:RelyingPartyId"];
        return string.IsNullOrWhiteSpace(configured) ? Request.Host.Host : configured.Trim();
    }

    /// <summary>
    /// أيُقبل الأصل الذي وقّع عليه المتصفّح؟
    ///
    /// <para>ثلاثة مقبولة ولا رابع: أصلُ الطلب نفسه، وأصلٌ مذكورٌ صراحةً في
    /// الإعدادات (ومنها أصول أندرويد بصيغة <c>android:apk-key-hash:…</c>)،
    /// وlocalhost للتطوير — وهو الوحيد الذي يعدّه المتصفّح سياقاً آمناً بلا
    /// شهادة، فلا يفتح باباً على خادمٍ حقيقي.</para>
    /// </summary>
    bool IsOriginAllowed(string origin)
    {
        if (string.IsNullOrWhiteSpace(origin)) return false;

        var extra = _config.GetSection("Passkeys:Origins").Get<string[]>() ?? Array.Empty<string>();
        if (extra.Any(o => string.Equals(o.Trim(), origin, StringComparison.OrdinalIgnoreCase)))
            return true;

        if (string.Equals(origin, $"{Request.Scheme}://{Request.Host.Value}", StringComparison.OrdinalIgnoreCase))
            return true;

        return Uri.TryCreate(origin, UriKind.Absolute, out var uri)
            && (uri.Host == "localhost" || uri.Host == "127.0.0.1");
    }

    Guid? CurrentUserId()
    {
        var raw = User.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
                  ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(raw, out var id) ? id : null;
    }

    Guid? CurrentOrganizationId() =>
        Guid.TryParse(User.FindFirstValue("organization_id"), out var id) ? id : null;
}
