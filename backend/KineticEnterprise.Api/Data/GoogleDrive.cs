using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace KineticEnterprise.Api.Data;

/// <summary>بيانات اعتماد التطبيق لدى قوقل — من appsettings لا من الكود.</summary>
public record GoogleOptions(string ClientId, string ClientSecret, string RedirectUri)
{
    /// <summary>هل هُيّئ الخادم أصلاً؟ بلا تسجيلٍ لدى قوقل لا شيء يعمل.</summary>
    public bool Configured =>
        !string.IsNullOrWhiteSpace(ClientId)
        && !string.IsNullOrWhiteSpace(ClientSecret)
        && !string.IsNullOrWhiteSpace(RedirectUri);

    public static GoogleOptions From(IConfiguration config) => new(
        config["GoogleDrive:ClientId"] ?? "",
        config["GoogleDrive:ClientSecret"] ?? "",
        config["GoogleDrive:RedirectUri"] ?? "");
}

/// <summary>
/// رفع النسخة الاحتياطية إلى Google Drive.
///
/// <para><b>النطاق <c>drive.file</c> لا <c>drive</c>:</b> الأوّل يقصر وصول
/// التطبيق على ما ينشئه هو — لا يرى ملفات صاحب الحساب الأخرى ولا يستطيع
/// حذفها. وهو صدقٌ مع العميل قبل أن يكون تسهيلاً لنا: طلبُ الوصول إلى كل
/// الدرايف لرفع ملفٍ واحد يجعل شاشة الموافقة مخيفة بحق، ويجرّ معه مراجعةً
/// أمنية سنوية من قوقل لا داعي لها.</para>
///
/// <para><b>ورمز التحديث هو ما يُخزَّن</b> لا رمز الوصول: الثاني يعيش ساعة،
/// والمهمّة الليلية تعمل بعد شهور. راجع
/// <see cref="Models.Organization.GoogleRefreshToken"/>.</para>
/// </summary>
public static class GoogleDrive
{
    public const string Scope = "https://www.googleapis.com/auth/drive.file";

    const string AuthEndpoint = "https://accounts.google.com/o/oauth2/v2/auth";
    const string TokenEndpoint = "https://oauth2.googleapis.com/token";
    const string UploadEndpoint = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart";
    const string FilesEndpoint = "https://www.googleapis.com/drive/v3/files";

    /// <summary>
    /// رابط شاشة الموافقة.
    ///
    /// <para><c>access_type=offline</c> و<c>prompt=consent</c> معاً: بلا
    /// الأوّل لا يُعطى رمز تحديث أصلاً، وبلا الثاني لا يُعاد إعطاؤه لمن
    /// وافق مرّة — فيربط المالك حسابه ثانيةً بعد استرجاع قاعدة فلا يصل
    /// رمزٌ ويبقى الرفع معطّلاً بلا رسالة.</para>
    /// </summary>
    public static string ConsentUrl(GoogleOptions options, string state)
    {
        var query = new Dictionary<string, string>
        {
            ["client_id"] = options.ClientId,
            ["redirect_uri"] = options.RedirectUri,
            ["response_type"] = "code",
            ["scope"] = Scope,
            ["access_type"] = "offline",
            ["prompt"] = "consent",
            ["include_granted_scopes"] = "true",
            ["state"] = state,
        };
        var encoded = string.Join('&', query.Select(kv => $"{kv.Key}={Uri.EscapeDataString(kv.Value)}"));
        return $"{AuthEndpoint}?{encoded}";
    }

    public record TokenResult(string? RefreshToken, string AccessToken);

    /// <summary>يبدّل رمز الموافقة برمز تحديث دائم.</summary>
    public static async Task<TokenResult> ExchangeCodeAsync(
        HttpClient http, GoogleOptions options, string code, CancellationToken token = default)
    {
        var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["code"] = code,
            ["client_id"] = options.ClientId,
            ["client_secret"] = options.ClientSecret,
            ["redirect_uri"] = options.RedirectUri,
            ["grant_type"] = "authorization_code",
        });

        using var response = await http.PostAsync(TokenEndpoint, form, token);
        var body = await response.Content.ReadAsStringAsync(token);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException(Explain(body));

        using var json = JsonDocument.Parse(body);
        return new TokenResult(
            json.RootElement.TryGetProperty("refresh_token", out var r) ? r.GetString() : null,
            json.RootElement.GetProperty("access_token").GetString()!);
    }

    /// <summary>رمز وصولٍ جديد من رمز التحديث — يُطلب عند كل رفع.</summary>
    public static async Task<string> AccessTokenAsync(
        HttpClient http, GoogleOptions options, string refreshToken, CancellationToken token = default)
    {
        var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["refresh_token"] = refreshToken,
            ["client_id"] = options.ClientId,
            ["client_secret"] = options.ClientSecret,
            ["grant_type"] = "refresh_token",
        });

        using var response = await http.PostAsync(TokenEndpoint, form, token);
        var body = await response.Content.ReadAsStringAsync(token);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException(Explain(body));

        using var json = JsonDocument.Parse(body);
        return json.RootElement.GetProperty("access_token").GetString()!;
    }

    /// <summary>بريد الحساب الموافِق — يُعرَض للمالك ليعرف أين تذهب نسخه.</summary>
    public static async Task<string?> AccountEmailAsync(
        HttpClient http, string accessToken, CancellationToken token = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get,
            "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        using var response = await http.SendAsync(request, token);
        if (!response.IsSuccessStatusCode) return null;

        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
        return json.RootElement.TryGetProperty("user", out var user)
               && user.TryGetProperty("emailAddress", out var email)
            ? email.GetString()
            : null;
    }

    /// <summary>
    /// مجلّد النسخ في درايف المنظمة — يُنشأ مرّة ويُعاد معرّفه.
    ///
    /// <para>مجلّدٌ لا جذرُ الدرايف: نسخةٌ يومية في الجذر تُغرق درايف
    /// صاحبها خلال شهر، فيحذفها كلّها ذات يوم وهو يرتّب ملفاته.</para>
    /// </summary>
    public static async Task<string> EnsureFolderAsync(
        HttpClient http, string accessToken, string name, CancellationToken token = default)
    {
        var payload = JsonSerializer.Serialize(new
        {
            name,
            mimeType = "application/vnd.google-apps.folder",
        });

        using var request = new HttpRequestMessage(HttpMethod.Post, $"{FilesEndpoint}?fields=id");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent(payload, Encoding.UTF8, "application/json");

        using var response = await http.SendAsync(request, token);
        var body = await response.Content.ReadAsStringAsync(token);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException(Explain(body));

        using var json = JsonDocument.Parse(body);
        return json.RootElement.GetProperty("id").GetString()!;
    }

    /// <summary>
    /// يرفع ملفاً واحداً برفعٍ متعدّد الأجزاء (بيانات وصفية + محتوى).
    ///
    /// <para>يكفي للنسخ حتى خمسة ميغابايت بسهولة وأكثر منها بلا مشكلة على
    /// شبكةٍ مستقرّة. والرفعُ المستأنَف (resumable) يلزم حين تصير النسخ
    /// مئات الميغابايتات — ويومها يُبنى فوق نفس هذه النقطة.</para>
    /// </summary>
    public static async Task<string> UploadAsync(
        HttpClient http, string accessToken, string folderId, string fileName, Stream content,
        CancellationToken token = default)
    {
        var metadata = JsonSerializer.Serialize(new
        {
            name = fileName,
            parents = new[] { folderId },
        });

        using var multipart = new MultipartContent("related");
        multipart.Add(new StringContent(metadata, Encoding.UTF8, "application/json"));

        var fileContent = new StreamContent(content);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/zip");
        multipart.Add(fileContent);

        using var request = new HttpRequestMessage(HttpMethod.Post, UploadEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = multipart;

        using var response = await http.SendAsync(request, token);
        var body = await response.Content.ReadAsStringAsync(token);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException(Explain(body));

        using var json = JsonDocument.Parse(body);
        return json.RootElement.GetProperty("id").GetString()!;
    }

    /// <summary>
    /// رسالة قوقل مقروءة.
    ///
    /// <para>ردُّ الخطأ JSON فيه <c>error_description</c> أو
    /// <c>error.message</c>، وتمريرُ الردّ خاماً إلى شاشةٍ عربية يجعل
    /// «فشل الرفع» أشدّ غموضاً ممّا لو لم يُقَل شيء.</para>
    /// </summary>
    static string Explain(string body)
    {
        try
        {
            using var json = JsonDocument.Parse(body);
            if (json.RootElement.TryGetProperty("error_description", out var description))
                return description.GetString() ?? body;
            if (json.RootElement.TryGetProperty("error", out var error))
            {
                if (error.ValueKind == JsonValueKind.String) return error.GetString() ?? body;
                if (error.TryGetProperty("message", out var message)) return message.GetString() ?? body;
            }
        }
        catch (JsonException)
        {
            // ردٌّ ليس JSON (بوابة وسيطة، صفحة خطأ) — يُمرَّر كما هو مقتطعاً.
        }
        return body.Length > 300 ? body[..300] : body;
    }
}
