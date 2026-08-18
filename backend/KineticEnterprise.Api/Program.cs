using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Hubs;
using KineticEnterprise.Api.Middleware;

// أوامر الصيانة تُنفَّذ وتخرج قبل بناء السيرفر — لا تفتح منفذاً ولا تشغّل
// المهام الخلفية. راجع PlatformOwnerBootstrap لسبب كون إنشاء أول حساب أمراً
// على السيرفر لا نقطة نهاية HTTP.
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
            }
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddControllers();
builder.Services.AddSignalR();

// إسقاط الاستحقاقات المنتهية يومياً — راجع EntitlementSweeper لسبب كونه
// مهمة خلفية لا حساباً وقت القراءة.
builder.Services.AddHostedService<EntitlementSweepService>();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// يسمح لتطبيق Flutter Web (على منفذ مختلف أثناء التطوير) بالاتصال بالـ API.
// في الإنتاج على IIS: يُقيَّد Origin للنطاق الفعلي فقط.
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
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

app.UseCors();
app.UseAuthentication();

// يجب أن يكون بعد UseAuthentication مباشرة وقبل أي Controller — لأنه
// يعتمد على context.User الذي يملؤه JwtBearer فقط بعد هذه النقطة.
app.UseMiddleware<TenantContextMiddleware>();

app.UseAuthorization();

app.MapControllers();
app.MapHub<NotificationsHub>("/hubs/notifications");

app.Run();

// نقطة الدخول تُرجع int الآن (أوامر الصيانة أعلاه ترجع رمز خروجها)، فيلزم
// إرجاع صريح هنا أيضاً.
return 0;
