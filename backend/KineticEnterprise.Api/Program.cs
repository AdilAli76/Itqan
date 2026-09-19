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

// ÃæÇãÑ ÇáÕíÇäÉ ÊõäİóøĞ æÊÎÑÌ ŞÈá ÈäÇÁ ÇáÓíÑİÑ — áÇ ÊİÊÍ ãäİĞÇğ æáÇ ÊÔÛøá
// ÇáãåÇã ÇáÎáİíÉ. ÑÇÌÚ PlatformOwnerBootstrap áÓÈÈ ßæä ÅäÔÇÁ Ãæá ÍÓÇÈ ÃãÑÇğ
// Úáì ÇáÓíÑİÑ áÇ äŞØÉ äåÇíÉ HTTP.
// ÖÛØ ÃÕæá ÇáæíÈ — ÃãÑ ÈäÇÁ áÇ ÊÔÛíá: íõÓÊÏÚì ãä publish.ps1 æíÎÑÌ İæÑÇğ.
// ãäİÕá Úä ÇáßÊáÉ ÇáÊÇáíÉ áÃäå áÇ íÍÊÇÌ ÅÚÏÇÏÇÊ æáÇ ŞÇÚÏÉ ÈíÇäÇÊ ÅØáÇŞÇğ.
if (args.Length > 0 && args[0] == KineticEnterprise.Api.Data.WebAssetCompressor.CommandName)
{
    return KineticEnterprise.Api.Data.WebAssetCompressor.Run(args);
}

// ÃæÇãÑ ÇáÊÑÎíÕ — ÇáÊæŞíÚ íÍÊÇÌ ÇáãİÊÇÍ ÇáÎÇÕø¡ æåæ áÇ íæÖÚ Úáì ÎÇÏã Úãíá
// ÅØáÇŞÇğ. ÑÇÌÚ LicenseCommands.
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
    opt.UseSqlite(builder.Configuration.GetConnectionString("Default"))
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

        // SignalR ÚÈÑ WebSocket áÇ íÓÊØíÚ ÅÑÓÇá ÊÑæíÓÉ Authorization: æÇÌåÉ
        // WebSocket İí ÇáãÊÕİÍ áÇ ÊÓãÍ ÈÊÑæíÓÇÊ ãÎÕøÕÉ İí ÇáãÕÇİÍÉ ÅØáÇŞÇğ¡
        // İíãÑøÑ ÇáÚãíá ÇáÊæßä İí ÓáÓáÉ ÇáÇÓÊÚáÇã (æåæ ãÇ íİÚáå
        // signalr_netcore ÚÈÑ accessTokenFactory).
        //
        // ÈáÇ åĞÇ ÇáãÚÇáÌ íİÔá ÇáÇÊÕÇá ÈÜ"HTTP Authentication failed" æíÈŞì
        // ãÄÔøÑ «ÛíÑ ãÊÕá» ÙÇåÑÇğ ÃÈÏÇğ — æåæ ãÇ ßÇä íÍÏË İÚáÇğ.
        //
        // ÇáŞÑÇÁÉ ãŞÕæÑÉ Úáì ãÓÇÑ /hubs: ŞÈæá ÇáÊæßä ãä ÓáÓáÉ ÇáÇÓÊÚáÇã Úáì
        // äŞÇØ ÇáÜAPI ÇáÚÇÏíÉ íÚäí ÊÓÑøÈå Åáì ÓÌáÇÊ ÇáÎÇÏã æÊÇÑíÎ ÇáãÊÕİÍ¡
        // æåí ÃãÇßä áÇ ÊõÍãì ßãÇ ÊõÍãì ÇáÊÑæíÓÇÊ.
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

            // ?? ÍÓÇÈñ ÚõØöøá íÎÑÌ ÇáÂä áÇ ÈÚÏ ËáÇËíä íæãÇğ ????????????????
            //
            // <para><b>ÓÈÈ æÌæÏå:</b> «ÇÈŞäí ãÓÌóøáÇğ» íõÕÏÑ ÊæßäÇğ áËáÇËíä
            // íæãÇğ (ÑÇÌÚ [AuthController.RememberLifetime])¡ æÇáÊæßä
            // ãõæŞóøÚ áÇ ãõÎÒóøä — İáÇ ÓÈíá áÅÈØÇáå. æãæÙøİñ ÓõÑöøÍ ÕÈÇÍÇğ
            // ßÇä íÈŞì íÈíÚ ãä åÇÊİå ÔåÑÇğ ßÇãáÇğ: ÇáäÙÇã áÇ íÓÃá Úä ÍÓÇÈå
            // ÈÚÏ ÇáÏÎæá ÅØáÇŞÇğ.</para>
            //
            // <para><b>æĞÇßÑÉñ áÏŞíŞÊíä áÇ ÇÓÊÚáÇãñ áßá ØáÈ:</b> äŞØÉ ÇáÈíÚ
            // ÊäÇÏí ÇáÎÇÏã ÚÔÑÇÊ ÇáãÑøÇÊ İí ÇáÏŞíŞÉ¡ æÇÓÊÚáÇãñ ÅÖÇİí Úáì ßá
            // äÏÇÁ Ëãäñ íõÏİÚ İí ÃÓÎä ãÓÇÑ İí ÇáäÙÇã. æÏŞíŞÊÇä ÃŞÕì ãÇ íÈŞÇå
            // ÍÓÇÈñ ÚõØöøá ÚÇãáÇğ — æåæ ãŞÈæá áŞÑÇÑò ÅÏÇÑí¡ ÈÎáÇİ ËáÇËíä
            // íæãÇğ.</para>
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
                    // AsNoTracking æÚãæÏñ æÇÍÏ: åĞÇ ÇáãÓÇÑ íõäİóøĞ ŞÈá ßá
                    // ØáÈ¡ İáÇ íõÍãóøá ßíÇäñ ßÇãá æáÇ íõÊÊÈóøÚ.
                    return await db.AppUsers.AsNoTracking()
                        .Where(u => u.Id == id)
                        .Select(u => (bool?)u.IsActive)
                        .FirstOrDefaultAsync();
                });

                // NULL = ÍÓÇÈñ ÍõĞİ ãä ÇáŞÇÚÏÉ. æÛíÇÈõ ÇáÕİø áÇ íŞáø Úä
                // ÊÚØíáå ÏáÇáÉğ.
                if (active != true)
                {
                    context.Fail("ÇáÍÓÇÈ ãÚØóøá");
                }
            },
        };
    });

// ĞÇßÑÉñ ŞÕíÑÉ áİÍÕ «ÇáÍÓÇÈ ãÇ ÒÇá ãİÚóøáÇğ» İí ßá ØáÈ — ÑÇÌÚ
// OnTokenValidated ÃÚáÇå.
builder.Services.AddMemoryCache();

builder.Services.AddAuthorization();
builder.Services.AddControllers(options =>
{
    // ÈæøÇÈÉ ÍÇáÉ ÇáÊÑÎíÕ ÚÇãøÉ áÇ Úáì ßá æÍÏÉ ÊÍßøã: ÈæøÇÈÉ ÊõÖÇİ íÏæíÇğ
    // ÊõäÓì İí Ãæá æÍÏÉ ÌÏíÏÉ. ÑÇÌÚ [LicenseGateAttribute].
    options.Filters.Add<KineticEnterprise.Api.Authorization.LicenseGateAttribute>();

    // æŞİá ÇáßáãÉ ÇáãÄŞøÊÉ ÚÇãñø áäİÓ ÇáÓÈÈ: ÃÑÈÚæä æÍÏÉ ÊÍßøã¡ æÓãÉñ
    // ÊõäÓì Úáì æÇÍÏÉ ÊÊÑß ÇáÍÓÇÈ íÚãá ÈßáãÉò ÃãáÇåÇ ÛíÑõ ÕÇÍÈå åÇÊİíÇğ.
    // ÑÇÌÚ [MustChangePasswordFilter] — æŞÇÆãÉ ÇáãõÚİóíä İíå.
    //
    // **æÊÑÊíÈå ÈÚÏ ÈæøÇÈÉ ÇáÊÑÎíÕ ãŞÕæÏ**: ãäÙãÉñ ãäÊåí ÊÑÎíÕåÇ ÊõŞÇÈóá
    // ÈÑÓÇáÉ ÇáÊÑÎíÕ áÇ ÈÑÓÇáÉ ßáãÉ ÇáãÑæÑ — ÇáÃæáì ÊŞæá áÕÇÍÈåÇ ãÇ íİÚá¡
    // æÇáËÇäíÉ ÊõÑÓáå İí ØÑíŞò áÇ íÍáø ãÔßáÊå.
    options.Filters.Add<KineticEnterprise.Api.Authorization.MustChangePasswordFilter>();
});
builder.Services.AddSignalR();

// ÅÓŞÇØ ÇáÇÓÊÍŞÇŞÇÊ ÇáãäÊåíÉ íæãíÇğ — ÑÇÌÚ EntitlementSweeper áÓÈÈ ßæäå
// ãåãÉ ÎáİíÉ áÇ ÍÓÇÈÇğ æŞÊ ÇáŞÑÇÁÉ.
// builder.Services.AddHostedService<EntitlementSweepService>();

// ÅäĞÇÑ ÇáÕáÇÍíÉ íæãíÇğ — äæÚ expiry ßÇä ãÚÑóøİÇğ İí ÇáãÎØØ æáÇ íßÊÈå ÃÍÏ¡
// Ãí Ãä ÇáÈÖÇÚÉ ßÇäÊ ÊÊáİ ÈáÇ ÅÔÚÇÑ. ÑÇÌÚ ExpirySweeper.
builder.Services.AddHostedService<ExpirySweepService>();

// ÅäĞÇÑ ÇáÏíæä ÇáãÊÃÎøÑÉ íæãíÇğ — ÇáÂÌá ßÇä ÏóíäÇğ ÈáÇ ãæÚÏ æáÇ ÊĞßíÑ æáÇ
// ÊÕäíİ ÊÃÎøÑ. ÑÇÌÚ DebtReminderSweeper.
builder.Services.AddHostedService<DebtReminderSweepService>();

// ÇáäÓÎÉ ÇááíáíÉ Åáì ÏÑÇíİ ÇáãäÙãÉ — ÇáäÓÎÉ ÇáíÏæíÉ ÊÚÊãÏ Úáì Ãä íÊĞßøÑåÇ
// ÅäÓÇä¡ æÇáÅäÓÇä íäÓì æáÇ íßÊÔİ äÓíÇäå ÅáÇ íæã íÍÊÇÌåÇ. ÑÇÌÚ BackupSweeper.
//
// æÊÏæÑ ßá ÓÇÚÉ áÇ ßá íæã: ÇáÓÇÚÉ ãÖÈæØÉ ÈÊæŞíÊ ßá ãäÙãÉ Úáì ÍÏÉ.
builder.Services.AddHttpClient();
builder.Services.AddHostedService<BackupSweepService>();
// ÖÛØ ÇáÇÓÊÌÇÈÇÊ — ÃßÈÑ ãßÓÈ ÓÑÚÉ İí ÇáäÙÇã ßáøå.
//
// web.config íãÑøÑ **ßá** ØáÈ Åáì ASP.NET Core (ıpath="*"ı)¡ İÇáãáİÇÊ ÇáÓÇßäÉ
// ÊõÎÏóã ãä Kestrel áÇ ãä IIS¡ æÖÛØ IIS ÇáÓÇßä áÇ íãÓøåÇ. ÇáäÊíÌÉ Ãä ßá
// ÒÇÆÑ ßÇä íäÒøá main.dart.js ÈÍÌãå ÇáÎÇã (~5.5 ãíÛÇÈÇíÊ) æãáİÇÊ canvaskit
// ãÚå — Úáì ÇÊÕÇá áíÈí ãÊæÓØ åĞå ÚÔÑÇÊ ÇáËæÇäí ŞÈá ÙåæÑ Ãæá ÔÇÔÉ.
//
// Brotli ŞÈá Gzip: íÖÛØ ãáİÇÊ JavaScript ÃßËÑ ÈäÍæ 15?¡ æßá ÇáãÊÕİøÍÇÊ
// ÇáÍÏíËÉ ÊÏÚãå. æGzip íÈŞì ááŞÏíãÉ.
builder.Services.AddResponseCompression(options =>
{
    // Úáì HTTPS ÃíÖÇğ: åÌæã BREACH ÇáäÙÑí íÎÕø ÇÓÊÌÇÈÇÊ ÊÍãá ÃÓÑÇÑÇğ
    // æÊÚßÓ ãÏÎáÇÊ ÇáãÓÊÎÏã¡ áÇ ãáİÇÊ ÓÇßäÉ íÊÔÇÑßåÇ ßá ÇáÒæøÇÑ.
    options.EnableForHttps = true;
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
    options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(new[]
    {
        "application/javascript",
        "text/javascript",
        // wasm ÃËŞá ãáİ İí ÇáÍÒãÉ æáíÓ İí ÇáŞÇÆãÉ ÇáÇİÊÑÇÖíÉ ÅØáÇŞÇğ.
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

// ?? ÎÏãÇÊ ãÎÕÕÉ ??????????????????????????????????????????????????????
// ÎÏãÉ ÍÓÇÈ ÇáÇåáÇß æÇáÃÕæá ÇáËÇÈÊÉ.
builder.Services.AddScoped<KineticEnterprise.Api.Services.DepreciationService>();

// ÎÏãÇÊ äÙÇã ÅÏÇÑÉ ÇáãÎÒæä ÇáãÊŞÏã.
builder.Services.AddScoped<KineticEnterprise.Api.Services.InventoryAlertService>();
builder.Services.AddScoped<KineticEnterprise.Api.Services.InventoryService>();

// íÓãÍ áÊØÈíŞ Flutter Web (Úáì ãäİĞ ãÎÊáİ ÃËäÇÁ ÇáÊØæíÑ) ÈÇáÇÊÕÇá ÈÇáÜ API.
// İí ÇáÅäÊÇÌ Úáì IIS: íõŞíóøÏ Origin ááäØÇŞ ÇáİÚáí İŞØ.
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        // ÇáäØÇŞÇÊ ÇáãÓãæÍÉ ãä ÇáÅÚÏÇÏ áÇ "ßá äØÇŞ": ãÚ AllowCredentials
        // íÚäí ÇáÓãÇÍ ÇáãİÊæÍ Ãä Ãí ãæŞÚ Úáì ÇáÅäÊÑäÊ íÓÊØíÚ ãäÇÏÇÉ ÇáÜAPI
        // ÈÇÚÊãÇÏíÇÊ ÇáãÓÊÎÏã ÇáãÓÌóøá — æåæ ÊÚÑíİ CSRF.
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

// ÎÏãÉ ÊØÈíŞ ÇáæíÈ ãä ÇáÎÇÏã äİÓå.
//
// ÇáÈÏíá — ãæŞÚ IIS ááæíÈ æÊØÈíŞ İÑÚí ááÜAPI ÊÍÊ /api — íÈÏæ ÃäÙİ æíİÔá
// İÚáíÇğ: æÍÏÇÊ ÇáÊÍßã ÊÍãá ÈÇÏÆÉ api/ İí ãÓÇÑÇÊåÇ ÃÕáÇğ
// ([Route("api/platform-settings")])¡ İÊÑßíÈåÇ ÊÍÊ /api íÌÚá ÇáãÓÇÑ
// ÇáäåÇÆí /api/api/platform-settings æíÑÏø ßá ØáÈ ÈÜ404. ÍÏË Ğáß Úáì ÎÇÏã
// ÇáÅäÊÇÌ.
//
// æãÕÏÑ æÇÍÏ ááÇËäíä íõáÛí CORS ãä ÇáãÚÇÏáÉ ßáíÇğ: áÇ äØÇŞÇÊ ãÓãæÍÉ ÊõÖÈØ
// æáÇ ØáÈ ãÈÏÆí (preflight) æáÇ ÎØÃ ÕÇãÊ Ííä íõäÓì ÊÍÏíË AllowedOrigins.
// ÊÍæíá HTTP Åáì HTTPS — ãÖÈæØ ÈãİÊÇÍ áÇ ãİÑæÖ ÏÇÆãÇğ.
//
// İÑÖå ÈáÇ ÔÑØ íŞØÚ ÇáäÔÑ Úáì ÚäæÇä IP ÈáÇ ÔåÇÏÉ (ÊÌÑÈÉ Ãæáì ãÔÑæÚÉ):
// ßá ØáÈ íõÍæóøá Åáì https Úáì ÎÇÏã áÇ íãáß ÔåÇÏÉ İíİÔá ÇáÇÊÕÇá ÊãÇãÇğ.
// æÊÑßå ãØİÃğ Úáì äØÇŞ ÍŞíŞí íÊÑß ßáãÇÊ ÇáãÑæÑ ÊãÑø äÕÇğ æÇÖÍÇğ.
//
// ÇáãİÊÇÍ íÌÚá ÇáŞÑÇÑ ÕÑíÍÇğ İí ãáİ ÇáÅÚÏÇÏÇÊ: íõÔÛóøá ãÚ ÇáÔåÇÏÉ¡ æíõØİÃ
// İí ÇáÊÌÑÈÉ Úáì IP. ÇáÇİÊÑÇÖí ãØİÃ ÍÊì áÇ íßÓÑ äÔÑÇğ ŞÇÆãÇğ ÚäÏ ÇáÊÑŞíÉ.
if (builder.Configuration.GetValue<bool>("UseHttpsRedirection"))
{
    // HSTS íÎÈÑ ÇáãÊÕİÍ ÃáøÇ íÍÇæá HTTP ÃÕáÇğ İí ÇáÒíÇÑÇÊ ÇáÊÇáíÉ — íãäÚ
    // äÇİĞÉ ÇáÇÚÊÑÇÖ İí Ãæá ØáÈ ãä ßá ÌáÓÉ.
    app.UseHsts();
    app.UseHttpsRedirection();
}

// ?? ÇáÃÕæá ÇáãÖÛæØÉ ãÓÈŞÇğ ???????????????????????????????????????????????
//
// publish.ps1 íÖÛØ ÃÕæá ÇáæíÈ ãÑøÉ æÇÍÏÉ æŞÊ ÇáÈäÇÁ ÈÃŞÕì ÌæÏÉ¡ æåĞÇ ÇáæÓíØ
// íŞÏøãåÇ áãä íŞÈáåÇ. ÇáŞíÇÓ åæ ãÇ İÑÖ åĞÇ ÇáÍáø:
//
//   main.dart.js   ÎÇã 5476 KB
//                  ÖÛØ áÍÙí (Fastest)  1949 KB
//                  ÖÛØ ÈäÇÁ (ÃŞÕì)     ~1100 KB
//
// æÇáÖÛØ ÇááÍÙí ÈÃŞÕì ÌæÏÉ ÛíÑ æÇÑÏ: íÓÊÛÑŞ ËæÇäíó Úáì ãáİ ÈåĞÇ ÇáÍÌã **İí
// ßá ØáÈ**. İÇáÎíÇÑ Èíä ÌæÏÉ ÑÏíÆÉ ÇáÂä Ãæ ÌæÏÉ ÚÇáíÉ ãÑøÉ æÇÍÏÉ — æÇáËÇäí
// ÃÑÎÕ Úáì ÇáÎÇÏã ÃíÖÇğ¡ ÅĞ áÇ ãÚÇáÌÉ ÅØáÇŞÇğ æŞÊ ÇáØáÈ.
//
// æíÈŞì UseResponseCompression ÈÚÏå ááãáİÇÊ ÇáÊí áÇ äÓÎÉ ãÖÛæØÉ áåÇ
// (ÑÏæÏ ÇáÜAPI ãËáÇğ¡ æåí ÕÛíÑÉ İáÇ ÊõËŞá).
app.Use(async (context, next) =>
{
    var path = context.Request.Path.Value;
    if (path is not null && !path.StartsWith("/api", StringComparison.OrdinalIgnoreCase))
    {
        var accept = context.Request.Headers.AcceptEncoding.ToString();
        // br ÃæáÇğ: äÓÎÉ ÇáÈäÇÁ ÈÃŞÕì ÌæÏÉ ÊÊİæøŞ Úáì gzip ÈİÇÑŞ æÇÖÍ¡
        // ÈÎáÇİ ÇáÖÛØ ÇááÍÙí ÍíË ßÇä ÇáÚßÓ.
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
                // Vary ÅáÒÇãí: ÈÏæäå íÎÒøä Ãí æÓíØ Èíä ÇáãÓÊÎÏã æÇáÎÇÏã äÓÎÉ
                // ãÖÛæØÉ æíŞÏøãåÇ áãÊÕİøÍ áÇ íŞÈáåÇ¡ İÊÕá ÈÇíÊÇÊ ÛíÑ ãİåæãÉ.
                context.Response.Headers.Vary = "Accept-Encoding";
                context.Request.Path = path + suffix;
            }
        }
    }

    await next();
});

// ÈÚÏ ÇáÃÕæá ÇáãÖÛæØÉ ãÓÈŞÇğ: íÖÛØ ãÇ áã ÊõÛØöøå (ÑÏæÏ ÇáÜAPI ÃÓÇÓÇğ).
app.UseResponseCompression();

app.UseDefaultFiles();
// ServeUnknownFileTypes ÖÑæÑí áÃä ÇáãÓÇÑ ÃõÚíÏÊ ßÊÇÈÊå Åáì ı.br/.gzı æåãÇ
// ÇãÊÏÇÏÇä ÛíÑ ãÚÑæİíä — æäæÚ ÇáãÍÊæì ÇáÕÍíÍ ãÖÈæØ ÓáİÇğ İí ÇáæÓíØ ÃÚáÇå.
app.UseStaticFiles(new StaticFileOptions
{
    ServeUnknownFileTypes = true,
    DefaultContentType = "application/octet-stream",
    OnPrepareResponse = ctx =>
    {
        // ? ßÇä åäÇ ÊÎÒíäñ áÓäÉ ßÇãáÉ áßá ÔíÁ ÚÏÇ ËáÇËÉ ãáİÇÊ¡ ÈÇİÊÑÇÖ Ãä
        // «ÃÕæá Flutter ÊÍãá ÈÕãÉ İí ÇÓãåÇ Ãæ ÊõäŞóÖ ÈÚÇãá ÇáÎÏãÉ».
        // **æÇáÇİÊÑÇÖ ÎÇØÆ**¡ æßáøİäÇ äÔÑÉğ ßÇãáÉ:
        //
        // `flutter_bootstrap.js` íÍãøá `main.dart.js` **ÈåĞÇ ÇáÇÓã ÍÑİíÇğ**
        // ÈáÇ ÈÕãÉ æáÇ ÇÓÊÚáÇã äÓÎÉ — æßáÇåãÇ íÊÛíøÑ İí ßá ÈäÇÁ. İãÊÕİøÍñ
        // ÒÇÑ ÇáãæŞÚ ãÑøÉğ íÍÊİÙ ÈÊØÈíŞ ÇáÔåÑ ÇáãÇÖí ÓäÉğ ßÇãáÉ æáÇ íÓÃá
        // ÇáÎÇÏã Úäå ÃÕáÇğ (max-age íãäÚ ÍÊì ØáÈ ÇáÊÍŞøŞ). İäõÔÑÊ ÇáäÓÎÉ
        // ÇáÌÏíÏÉ Úáì ÇáÎÇÏã — ãáİÇÊåÇ åäÇß İÚáÇğ — æáÇ íÑÇåÇ ÃÍÏ¡ İíÈÏæ
        // ÇáäÔÑ æßÃäå äÔÑ «äÓÎÉ ŞÏíãÉ ÌÏÇğ».
        //
        // æáÇ ÚÇãá ÎÏãÉ íõäŞĞ: index.html áã íÚÏ íÓÌøáå (íİÚá Ğáß
        // flutter_bootstrap.js ÇáãÎÒóøä åæ ÇáÂÎÑ ÓäÉ).
        //
        // İÇáŞÇÚÏÉ ÇáÂä **ÊÍŞõøŞñ ÏÇÆã áßá ÔíÁ**: ÇáãáİÇÊ ÊÈŞì İí ĞÇßÑÉ
        // ÇáãÊÕİøÍ¡ æíÑÏø ÇáÎÇÏã 304 áãÇ áã íÊÛíøÑ — İáÇ ÊÊÛíøÑ ÇáÈÇíÊÇÊ
        // ÇáãäŞæáÉ¡ æíõÏİÚ Ëãäõ ØáÈò ÔóÑØí æÇÍÏ áßá ãáİ. æĞÇß Ëãäñ ÒåíÏ
        // ãŞÇÈá äÔÑÉò ÊÕá İÚáÇğ.
        //
        // æÃí ÃÕáò íÍãá ÈÕãÉğ ÍŞíŞíÉ İí ÇÓãå ãÓÊŞÈáÇğ íõÓÊËäì åäÇ ÕÑÇÍÉğ.
        // ÇáÇÓã ŞÏ íÍãá ı.br/.gzı ÈÚÏ ÅÚÇÏÉ ÇáßÊÇÈÉ¡ İíõÌÑóøÏ ŞÈá ÇáãŞÇÑäÉ.
        var path = ctx.File.Name;
        if (path.EndsWith(".br") || path.EndsWith(".gz"))
        {
            path = path[..^3];

            // äæÚ ÇáãÍÊæì ãä ÇáÇÓã ÇáÃÕáí¡ **åäÇ** áÇ İí æÓíØ ÅÚÇÏÉ ÇáßÊÇÈÉ:
            // ãáİÇÊ ÇáÓÇßäÉ ÊßÊÈ ÇáäæÚ ÈäİÓåÇ ÈÚÏ ÇáæÓíØ İÊÏåÓ ãÇ ÖÈØå.
            //
            // æáíÓÊ ÊİÕíáÇğ ÊÌãíáíÇğ: ãÊÕİøÍ íÓÊŞÈá ÓßÑÈÊÇğ ÈäæÚ
            // application/octet-stream íÑİÖ ÊäİíĞå (İÍÕ MIME ÇáÕÇÑã ááæÍÏÇÊ)
            // İáÇ íÚãá ÇáÊØÈíŞ ÅØáÇŞÇğ.
            if (new FileExtensionContentTypeProvider().TryGetContentType(path, out var mime))
            {
                ctx.Context.Response.Headers.ContentType = mime;
            }
        }

        // no-cache áÇ no-store: ÇáİÑŞ ÈíäåãÇ åæ ßá ÇáãßÓÈ. no-store íãäÚ
        // ÇáÍİÙ İíõÚÇÏ ÊäÒíá ÓÊøÉ ãíÛÇÈÇíÊ ÚäÏ ßá İÊÍº æno-cache íÍİÙ
        // æíÓÃá «ÃÊÛíøÑ¿» İíÑÏø ÇáÎÇÏã 304 ÈáÇ ÌÓã.
        ctx.Context.Response.Headers["Cache-Control"] = "no-cache, must-revalidate";
    },
});

// ŞÈá ßá ãÇ íáãÓ ŞÇÚÏÉ ÇáÈíÇäÇÊ — ÈãÇ İíå TenantContextMiddleware — ÍÊì áÇ
// íİáÊ ÇäÊåÇß ŞíÏ ãä Ãí ãÓÇÑ. íÊÑÌã ÑÓÇáÉ SQL Server Åáì ÚÑÈíÉ ãİåæãÉ ÈÏá
// ÎØÃ ÎÇÏã 500 Ãæ äÕø ÅäÌáíÒí ÎÇã ÃãÇã ÇáßÇÔíÑ.
app.UseMiddleware<DbConstraintMessageMiddleware>();

app.UseCors();
app.UseAuthentication();

// íÌÈ Ãä íßæä ÈÚÏ UseAuthentication ãÈÇÔÑÉ æŞÈá Ãí Controller — áÃäå
// íÚÊãÏ Úáì context.User ÇáĞí íãáÄå JwtBearer İŞØ ÈÚÏ åĞå ÇáäŞØÉ.
app.UseMiddleware<TenantContextMiddleware>();

app.UseAuthorization();

app.MapControllers();
app.MapHub<NotificationsHub>("/hubs/notifications");

// Ãí ãÓÇÑ ÛíÑ ãÚÑæİ íÚæÏ Åáì index.html — ÊØÈíŞ Flutter íæÌøå ÏÇÎáíÇğ¡
// İØáÈ /app?route=/pos ãÈÇÔÑÉğ íÌÈ ÃáøÇ íÚØí 404. æíÃÊí ÈÚÏ MapControllers
// ÍÊì áÇ íÈÊáÚ ãÓÇÑÇÊ ÇáÜAPI.
app.MapFallbackToFile("index.html");

app.Run();

// äŞØÉ ÇáÏÎæá ÊõÑÌÚ int ÇáÂä (ÃæÇãÑ ÇáÕíÇäÉ ÃÚáÇå ÊÑÌÚ ÑãÒ ÎÑæÌåÇ)¡ İíáÒã
// ÅÑÌÇÚ ÕÑíÍ åäÇ ÃíÖÇğ.
return 0;
