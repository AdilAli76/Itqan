using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using KineticEnterprise.Api.Data;
using KineticEnterprise.Api.Hubs;
using KineticEnterprise.Api.Middleware;

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
