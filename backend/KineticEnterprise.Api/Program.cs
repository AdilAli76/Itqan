using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.Caching.Memory;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Hubs;
using KineticEnterprise.Api.Middleware;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.AspNetCore.StaticFiles;

// أوامر الصيانة تُنفَّذ وتخرج قبل بناء السيرفر — لا تفتح منفذاً ولا تشغّل
// المهام الخلفية. راجع PlatformOwnerBootstrap لسبب كون إنشاء أول حساب أمراً
// على السيرفر لا نقطة نهاية HTTP.
// ضغط أصول الويب — أمر بناء لا تشغيل: يُستدعى من publish.ps1 ويخرج فوراً.
// منفصل عن الكتلة التالية لأنه لا يحتاج إعدادات ولا قاعدة بيانات إطلاقاً.
if (args.Length > 0 && args[0] == KineticEnterprise.Api.Data.WebAssetCompressor.CommandName)
{
    return KineticEnterprise.Api.Data.WebAssetCompressor.Run(args);
}

// أوامر الترخيص — التوقيع يحتاج المفتاح الخاصّ، وهو لا يوضع على خادم عميل
// إطلاقاً. راجع LicenseCommands.
if (args.Length > 0 && KineticEnterprise.Api.Data.LicenseCommands.Handles(args[0]))
{
    return KineticEnterprise.Api.Data.LicenseCommands.Run(args);
}

if (args.Length > 0 &&
    (args[0] == KineticEnterprise.Api.Data.PlatformOwnerBootstrap.CommandName ||
     args[0] == KineticEnterprise.Api.Data.PlatformOwnerBootstrap.ResetCommandName ||
     args[0] == KineticEnterprise.Api.Data.PlatformOwnerBootstrap.CreateUserCommandName))
{
    var bootstrapConfig = new ConfigurationBuilder()
        .SetBasePath(Directory.GetCurrentDirectory())
        .AddJsonFile("appsettings.json", optional: true)
        .AddJsonFile($"appsettings.{Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production"}.json", optional: true)
        .AddEnvironmentVariables()
        .Build();

    return args[0] switch
    {
        KineticEnterprise.Api.Data.PlatformOwnerBootstrap.ResetCommandName =>
            await KineticEnterprise.Api.Data.PlatformOwnerBootstrap.ResetPasswordAsync(bootstrapConfig),
        KineticEnterprise.Api.Data.PlatformOwnerBootstrap.CreateUserCommandName =>
            await KineticEnterprise.Api.Data.PlatformOwnerBootstrap.CreateUserAsync(bootstrapConfig),
        _ => await KineticEnterprise.Api.Data.PlatformOwnerBootstrap.RunAsync(args, bootstrapConfig),
    };
}

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseSqlServer(builder.Configuration.GetConnectionString("Default"))
       .UseSnakeCaseNamingConvention());

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"]!)),
        };

        // SignalR عبر WebSocket لا يستطيع إرسال ترويسة Authorization: واجهة
        // WebSocket في المتصفح لا تسمح بترويسات مخصّصة في المصافحة إطلاقاً،
        // فيمرّر العميل التوكن في سلسلة الاستعلام (وهو ما يفعله
        // signalr_netcore عبر accessTokenFactory).
        //
        // بلا هذا المعالج يفشل الاتصال بـ"HTTP Authentication failed" ويبقى
        // مؤشّر «غير متصل» ظاهراً أبداً — وهو ما كان يحدث فعلاً.
        //
        // القراءة مقصورة على مسار /hubs: قبول التوكن من سلسلة الاستعلام على
        // نقاط الـAPI العادية يعني تسرّبه إلى سجلات الخادم وتاريخ المتصفح،
        // وهي أماكن لا تُحمى كما تُحمى الترويسات.
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                if (!string.IsNullOrEmpty(accessToken) &&
                    context.HttpContext.Request.Path.StartsWithSegments("/hubs"))
                {
                    context.Token = accessToken;
                }
                return Task.CompletedTask;
            },

            // ── حسابٌ عُطِّل يخرج الآن لا بعد ثلاثين يوماً ────────────────
            //
            // <para><b>سبب وجوده:</b> «ابقني مسجَّلاً» يُصدر توكناً لثلاثين
            // يوماً (راجع [AuthController.RememberLifetime])، والتوكن
            // مُوقَّع لا مُخزَّن — فلا سبيل لإبطاله. وموظّفٌ سُرِّح صباحاً
            // كان يبقى يبيع من هاتفه شهراً كاملاً: النظام لا يسأل عن حسابه
            // بعد الدخول إطلاقاً.</para>
            //
            // <para><b>وذاكرةٌ لدقيقتين لا استعلامٌ لكل طلب:</b> نقطة البيع
            // تنادي الخادم عشرات المرّات في الدقيقة، واستعلامٌ إضافي على كل
            // نداء ثمنٌ يُدفع في أسخن مسار في النظام. ودقيقتان أقصى ما يبقاه
            // حسابٌ عُطِّل عاملاً — وهو مقبول لقرارٍ إداري، بخلاف ثلاثين
            // يوماً.</para>
            OnTokenValidated = async context =>
            {
                var userId = context.Principal?.FindFirstValue(JwtRegisteredClaimNames.Sub)
                             ?? context.Principal?.FindFirstValue(ClaimTypes.NameIdentifier);
                if (!Guid.TryParse(userId, out var id)) return;

                var cache = context.HttpContext.RequestServices.GetRequiredService<IMemoryCache>();
                var active = await cache.GetOrCreateAsync($"user-active:{id}", async entry =>
                {
                    entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(2);
                    var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                    // AsNoTracking وعمودٌ واحد: هذا المسار يُنفَّذ قبل كل
                    // طلب، فلا يُحمَّل كيانٌ كامل ولا يُتتبَّع.
                    return await db.AppUsers.AsNoTracking()
                        .Where(u => u.Id == id)
                        .Select(u => (bool?)u.IsActive)
                        .FirstOrDefaultAsync();
                });

                // NULL = حسابٌ حُذف من القاعدة. وغيابُ الصفّ لا يقلّ عن
                // تعطيله دلالةً.
                if (active != true)
                {
                    context.Fail("الحساب معطَّل");
                }
            },
        };
    });

// ذاكرةٌ قصيرة لفحص «الحساب ما زال مفعَّلاً» في كل طلب — راجع
// OnTokenValidated أعلاه.
builder.Services.AddMemoryCache();

builder.Services.AddAuthorization();
builder.Services.AddControllers(options =>
{
    // بوّابة حالة الترخيص عامّة لا على كل وحدة تحكّم: بوّابة تُضاف يدوياً
    // تُنسى في أول وحدة جديدة. راجع [LicenseGateAttribute].
    options.Filters.Add<KineticEnterprise.Api.Authorization.LicenseGateAttribute>();

    // وقفل الكلمة المؤقّتة عامٌّ لنفس السبب: أربعون وحدة تحكّم، وسمةٌ
    // تُنسى على واحدة تترك الحساب يعمل بكلمةٍ أملاها غيرُ صاحبه هاتفياً.
    // راجع [MustChangePasswordFilter] — وقائمة المُعفَين فيه.
    //
    // **وترتيبه بعد بوّابة الترخيص مقصود**: منظمةٌ منتهي ترخيصها تُقابَل
    // برسالة الترخيص لا برسالة كلمة المرور — الأولى تقول لصاحبها ما يفعل،
    // والثانية تُرسله في طريقٍ لا يحلّ مشكلته.
    options.Filters.Add<KineticEnterprise.Api.Authorization.MustChangePasswordFilter>();
});
builder.Services.AddSignalR();

// إسقاط الاستحقاقات المنتهية يومياً — راجع EntitlementSweeper لسبب كونه
// مهمة خلفية لا حساباً وقت القراءة.
builder.Services.AddHostedService<EntitlementSweepService>();

// إنذار الصلاحية يومياً — نوع expiry كان معرَّفاً في المخطط ولا يكتبه أحد،
// أي أن البضاعة كانت تتلف بلا إشعار. راجع ExpirySweeper.
builder.Services.AddHostedService<ExpirySweepService>();

// إنذار الديون المتأخّرة يومياً — الآجل كان دَيناً بلا موعد ولا تذكير ولا
// تصنيف تأخّر. راجع DebtReminderSweeper.
builder.Services.AddHostedService<DebtReminderSweepService>();

// النسخة الليلية إلى درايف المنظمة — النسخة اليدوية تعتمد على أن يتذكّرها
// إنسان، والإنسان ينسى ولا يكتشف نسيانه إلا يوم يحتاجها. راجع BackupSweeper.
//
// وتدور كل ساعة لا كل يوم: الساعة مضبوطة بتوقيت كل منظمة على حدة.
builder.Services.AddHttpClient();
builder.Services.AddHostedService<BackupSweepService>();
// ضغط الاستجابات — أكبر مكسب سرعة في النظام كلّه.
//
// web.config يمرّر **كل** طلب إلى ASP.NET Core (‎path="*"‎)، فالملفات الساكنة
// تُخدَم من Kestrel لا من IIS، وضغط IIS الساكن لا يمسّها. النتيجة أن كل
// زائر كان ينزّل main.dart.js بحجمه الخام (~5.5 ميغابايت) وملفات canvaskit
// معه — على اتصال ليبي متوسط هذه عشرات الثواني قبل ظهور أول شاشة.
//
// Brotli قبل Gzip: يضغط ملفات JavaScript أكثر بنحو 15٪، وكل المتصفّحات
// الحديثة تدعمه. وGzip يبقى للقديمة.
builder.Services.AddResponseCompression(options =>
{
    // على HTTPS أيضاً: هجوم BREACH النظري يخصّ استجابات تحمل أسراراً
    // وتعكس مدخلات المستخدم، لا ملفات ساكنة يتشاركها كل الزوّار.
    options.EnableForHttps = true;
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
    options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(new[]
    {
        "application/javascript",
        "text/javascript",
        // wasm أثقل ملف في الحزمة وليس في القائمة الافتراضية إطلاقاً.
        "application/wasm",
        "application/json",
        "image/svg+xml",
        "application/manifest+json",
        "font/ttf",
        "font/woff2",
    });
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// يسمح لتطبيق Flutter Web (على منفذ مختلف أثناء التطوير) بالاتصال بالـ API.
// في الإنتاج على IIS: يُقيَّد Origin للنطاق الفعلي فقط.
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        // النطاقات المسموحة من الإعداد لا "كل نطاق": مع AllowCredentials
        // يعني السماح المفتوح أن أي موقع على الإنترنت يستطيع مناداة الـAPI
        // باعتماديات المستخدم المسجَّل — وهو تعريف CSRF.
        policy.WithOrigins(builder.Configuration["AllowedOrigins"]?.Split(',') ?? Array.Empty<string>())
              .AllowAnyHeader()
              .AllowAnyMethod()
              .AllowCredentials());
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// خدمة تطبيق الويب من الخادم نفسه.
//
// البديل — موقع IIS للويب وتطبيق فرعي للـAPI تحت /api — يبدو أنظف ويفشل
// فعلياً: وحدات التحكم تحمل بادئة api/ في مساراتها أصلاً
// ([Route("api/platform-settings")])، فتركيبها تحت /api يجعل المسار
// النهائي /api/api/platform-settings ويردّ كل طلب بـ404. حدث ذلك على خادم
// الإنتاج.
//
// ومصدر واحد للاثنين يُلغي CORS من المعادلة كلياً: لا نطاقات مسموحة تُضبط
// ولا طلب مبدئي (preflight) ولا خطأ صامت حين يُنسى تحديث AllowedOrigins.
// تحويل HTTP إلى HTTPS — مضبوط بمفتاح لا مفروض دائماً.
//
// فرضه بلا شرط يقطع النشر على عنوان IP بلا شهادة (تجربة أولى مشروعة):
// كل طلب يُحوَّل إلى https على خادم لا يملك شهادة فيفشل الاتصال تماماً.
// وتركه مطفأً على نطاق حقيقي يترك كلمات المرور تمرّ نصاً واضحاً.
//
// المفتاح يجعل القرار صريحاً في ملف الإعدادات: يُشغَّل مع الشهادة، ويُطفأ
// في التجربة على IP. الافتراضي مطفأ حتى لا يكسر نشراً قائماً عند الترقية.
if (builder.Configuration.GetValue<bool>("UseHttpsRedirection"))
{
    // HSTS يخبر المتصفح ألّا يحاول HTTP أصلاً في الزيارات التالية — يمنع
    // نافذة الاعتراض في أول طلب من كل جلسة.
    app.UseHsts();
    app.UseHttpsRedirection();
}

// ── الأصول المضغوطة مسبقاً ───────────────────────────────────────────────
//
// publish.ps1 يضغط أصول الويب مرّة واحدة وقت البناء بأقصى جودة، وهذا الوسيط
// يقدّمها لمن يقبلها. القياس هو ما فرض هذا الحلّ:
//
//   main.dart.js   خام 5476 KB
//                  ضغط لحظي (Fastest)  1949 KB
//                  ضغط بناء (أقصى)     ~1100 KB
//
// والضغط اللحظي بأقصى جودة غير وارد: يستغرق ثوانيَ على ملف بهذا الحجم **في
// كل طلب**. فالخيار بين جودة رديئة الآن أو جودة عالية مرّة واحدة — والثاني
// أرخص على الخادم أيضاً، إذ لا معالجة إطلاقاً وقت الطلب.
//
// ويبقى UseResponseCompression بعده للملفات التي لا نسخة مضغوطة لها
// (ردود الـAPI مثلاً، وهي صغيرة فلا تُثقل).
app.Use(async (context, next) =>
{
    var path = context.Request.Path.Value;
    if (path is not null && !path.StartsWith("/api", StringComparison.OrdinalIgnoreCase))
    {
        var accept = context.Request.Headers.AcceptEncoding.ToString();
        // br أولاً: نسخة البناء بأقصى جودة تتفوّق على gzip بفارق واضح،
        // بخلاف الضغط اللحظي حيث كان العكس.
        var encoding = accept.Contains("br", StringComparison.OrdinalIgnoreCase) ? "br"
                     : accept.Contains("gzip", StringComparison.OrdinalIgnoreCase) ? "gzip"
                     : null;

        if (encoding is not null)
        {
            var suffix = encoding == "br" ? ".br" : ".gz";
            var candidate = Path.Combine(app.Environment.WebRootPath ?? "", path.TrimStart('/') + suffix);
            if (System.IO.File.Exists(candidate))
            {
                context.Response.Headers.ContentEncoding = encoding;
                // Vary إلزامي: بدونه يخزّن أي وسيط بين المستخدم والخادم نسخة
                // مضغوطة ويقدّمها لمتصفّح لا يقبلها، فتصل بايتات غير مفهومة.
                context.Response.Headers.Vary = "Accept-Encoding";
                context.Request.Path = path + suffix;
            }
        }
    }

    await next();
});

// بعد الأصول المضغوطة مسبقاً: يضغط ما لم تُغطِّه (ردود الـAPI أساساً).
app.UseResponseCompression();

app.UseDefaultFiles();
// ServeUnknownFileTypes ضروري لأن المسار أُعيدت كتابته إلى ‎.br/.gz‎ وهما
// امتدادان غير معروفين — ونوع المحتوى الصحيح مضبوط سلفاً في الوسيط أعلاه.
app.UseStaticFiles(new StaticFileOptions
{
    ServeUnknownFileTypes = true,
    DefaultContentType = "application/octet-stream",
    OnPrepareResponse = ctx =>
    {
        // ⚠ كان هنا تخزينٌ لسنة كاملة لكل شيء عدا ثلاثة ملفات، بافتراض أن
        // «أصول Flutter تحمل بصمة في اسمها أو تُنقَض بعامل الخدمة».
        // **والافتراض خاطئ**، وكلّفنا نشرةً كاملة:
        //
        // `flutter_bootstrap.js` يحمّل `main.dart.js` **بهذا الاسم حرفياً**
        // بلا بصمة ولا استعلام نسخة — وكلاهما يتغيّر في كل بناء. فمتصفّحٌ
        // زار الموقع مرّةً يحتفظ بتطبيق الشهر الماضي سنةً كاملة ولا يسأل
        // الخادم عنه أصلاً (max-age يمنع حتى طلب التحقّق). فنُشرت النسخة
        // الجديدة على الخادم — ملفاتها هناك فعلاً — ولا يراها أحد، فيبدو
        // النشر وكأنه نشر «نسخة قديمة جداً».
        //
        // ولا عامل خدمة يُنقذ: index.html لم يعد يسجّله (يفعل ذلك
        // flutter_bootstrap.js المخزَّن هو الآخر سنة).
        //
        // فالقاعدة الآن **تحقُّقٌ دائم لكل شيء**: الملفات تبقى في ذاكرة
        // المتصفّح، ويردّ الخادم 304 لما لم يتغيّر — فلا تتغيّر البايتات
        // المنقولة، ويُدفع ثمنُ طلبٍ شَرطي واحد لكل ملف. وذاك ثمنٌ زهيد
        // مقابل نشرةٍ تصل فعلاً.
        //
        // وأي أصلٍ يحمل بصمةً حقيقية في اسمه مستقبلاً يُستثنى هنا صراحةً.
        // الاسم قد يحمل ‎.br/.gz‎ بعد إعادة الكتابة، فيُجرَّد قبل المقارنة.
        var path = ctx.File.Name;
        if (path.EndsWith(".br") || path.EndsWith(".gz"))
        {
            path = path[..^3];

            // نوع المحتوى من الاسم الأصلي، **هنا** لا في وسيط إعادة الكتابة:
            // ملفات الساكنة تكتب النوع بنفسها بعد الوسيط فتدهس ما ضبطه.
            //
            // وليست تفصيلاً تجميلياً: متصفّح يستقبل سكربتاً بنوع
            // application/octet-stream يرفض تنفيذه (فحص MIME الصارم للوحدات)
            // فلا يعمل التطبيق إطلاقاً.
            if (new FileExtensionContentTypeProvider().TryGetContentType(path, out var mime))
            {
                ctx.Context.Response.Headers.ContentType = mime;
            }
        }

        // no-cache لا no-store: الفرق بينهما هو كل المكسب. no-store يمنع
        // الحفظ فيُعاد تنزيل ستّة ميغابايت عند كل فتح؛ وno-cache يحفظ
        // ويسأل «أتغيّر؟» فيردّ الخادم 304 بلا جسم.
        ctx.Context.Response.Headers["Cache-Control"] = "no-cache, must-revalidate";
    },
});

// قبل كل ما يلمس قاعدة البيانات — بما فيه TenantContextMiddleware — حتى لا
// يفلت انتهاك قيد من أي مسار. يترجم رسالة SQL Server إلى عربية مفهومة بدل
// خطأ خادم 500 أو نصّ إنجليزي خام أمام الكاشير.
app.UseMiddleware<DbConstraintMessageMiddleware>();

app.UseCors();
app.UseAuthentication();

// يجب أن يكون بعد UseAuthentication مباشرة وقبل أي Controller — لأنه
// يعتمد على context.User الذي يملؤه JwtBearer فقط بعد هذه النقطة.
app.UseMiddleware<TenantContextMiddleware>();

app.UseAuthorization();

app.MapControllers();
app.MapHub<NotificationsHub>("/hubs/notifications");

// أي مسار غير معروف يعود إلى index.html — تطبيق Flutter يوجّه داخلياً،
// فطلب /app?route=/pos مباشرةً يجب ألّا يعطي 404. ويأتي بعد MapControllers
// حتى لا يبتلع مسارات الـAPI.
app.MapFallbackToFile("index.html");

app.Run();

// نقطة الدخول تُرجع int الآن (أوامر الصيانة أعلاه ترجع رمز خروجها)، فيلزم
// إرجاع صريح هنا أيضاً.
return 0;
