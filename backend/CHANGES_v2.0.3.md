# ملخص التغييرات - v2.0.3

## المشكلة المحلولة
- **Remember Me fails**: عندما يعود المستخدم بعد وقت طويل، لا يمكنه البقاء مسجلاً
- **Extend Session fails**: تمديد الجلسة ينتهي بتسجيل خروج نهائي بدلاً من التمديد

**السبب الجذري:** Token واحد بصلاحية ثابتة (8-30 ساعة) لا يمكن تمديده بعد انتهاء صلاحيته.

## الحل: Refresh Token Pattern

### 🔑 نمط التوكن الجديد
```
Access Token (قصير الأجل)
├─ الصلاحية: 8 ساعات
├─ الاستخدام: كل طلب API
├─ المتضمن: JWT مع صلاحيات المستخدم
└─ لا يحفظ في قاعدة البيانات

Refresh Token (طويل الأجل)
├─ الصلاحية: 90 يوم
├─ الاستخدام: تجديد الجلسة فقط
├─ المتضمن: سلسلة عشوائية
└─ محفوظ في قاعدة البيانات (refresh_tokens)
```

## الملفات المُحدّثة

### 1. `Models/Entities.cs`
```csharp
// إضافة كلاس RefreshToken
public class RefreshToken
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Token { get; set; }           // سلسلة عشوائية
    public DateTime ExpiresAt { get; set; }     // 90 يوم
    public DateTime CreatedAt { get; set; }
    public DateTime? RevokedAt { get; set; }    // للإلغاء المبكر
    
    // خصائص محسوبة
    public bool IsExpired => DateTime.UtcNow > ExpiresAt;
    public bool IsRevoked => RevokedAt.HasValue;
    public bool IsValid => !IsExpired && !IsRevoked;
}

// طلب التجديد
public record RefreshTokenRequest(string RefreshToken);
```

### 2. `Data/AppDbContext.cs`
```csharp
public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();

// في OnModelCreating:
modelBuilder.Entity<RefreshToken>().ToTable("refresh_tokens");
modelBuilder.Entity<RefreshToken>().HasIndex(rt => rt.UserId);
```

### 3. `Controllers/AuthController.cs`

#### أ) تحديث Login Response
```csharp
public record LoginResponse(
    string AccessToken,
    string Role,
    Guid OrganizationId,
    Guid? BranchId,
    string FullName,
    string BranchPalette,
    bool MustChangePassword,
    bool IsPlatformAdmin,
    string RefreshToken  // ← جديد
);
```

#### ب) تحديث Login Endpoint
```csharp
[HttpPost("login")]
public async Task<ActionResult<LoginResponse>> Login([FromBody] LoginRequest request)
{
    // ... التحقق من المستخدم ...
    
    // إصدار Access Token (8 ساعات)
    var accessToken = IssueAccessToken(user);
    
    // إصدار Refresh Token (90 يوم، محفوظ في DB)
    var refreshTokenEntity = await IssueRefreshToken(user);
    var refreshToken = refreshTokenEntity.Token;
    
    return new LoginResponse(
        accessToken,
        user.Role, user.OrganizationId, user.BranchId,
        user.FullName, branchPalette, user.MustChangePassword, user.IsPlatformAdmin,
        refreshToken  // ← يُرسل للعميل
    );
}
```

#### ج) دالة IssueAccessToken (جديدة)
```csharp
private string IssueAccessToken(AppUser user)
{
    var claims = new List<Claim>
    {
        new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
        new("org", user.OrganizationId.ToString()),
        new("role", user.Role),
        new("name", user.FullName)
    };
    
    if (user.BranchId.HasValue)
        claims.Add(new("branch", user.BranchId.ToString()));
    
    if (user.IsPlatformAdmin)
        claims.Add(new("platform_admin", "true"));
    
    var token = new JwtSecurityToken(
        issuer: _config["Jwt:Issuer"],
        audience: _config["Jwt:Audience"],
        claims: claims,
        expires: DateTime.UtcNow.AddHours(8),  // ← 8 ساعات فقط
        signingCredentials: new SigningCredentials(key, SecurityAlgorithm.HmacSha256)
    );
    
    return new JwtSecurityTokenHandler().WriteToken(token);
}
```

#### د) دالة IssueRefreshToken (جديدة)
```csharp
private async Task<RefreshToken> IssueRefreshToken(AppUser user)
{
    var token = new RefreshToken
    {
        UserId = user.Id,
        Token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)),
        ExpiresAt = DateTime.UtcNow.AddDays(90),  // ← 90 يوم
        CreatedAt = DateTime.UtcNow
    };
    
    _db.RefreshTokens.Add(token);
    await _db.SaveChangesAsync();
    
    return token;
}
```

#### هـ) تحديث Refresh Endpoint (قديم ← جديد)
```csharp
// الآن: يقبل Refresh Token كـ body parameter
[HttpPost("refresh")]
public async Task<ActionResult<LoginResponse>> Refresh([FromBody] RefreshTokenRequest request)
{
    // ابحث عن Refresh Token في قاعدة البيانات
    var refreshToken = await _db.RefreshTokens
        .FirstOrDefaultAsync(rt => rt.Token == request.RefreshToken 
            && !rt.IsRevoked 
            && rt.ExpiresAt > DateTime.UtcNow);
    
    if (refreshToken is null)
        return Unauthorized("Refresh token غير صالح");
    
    var user = await _db.AppUsers.FirstOrDefaultAsync(u => u.Id == refreshToken.UserId);
    if (user is null || !user.IsActive)
        return Unauthorized();
    
    // إصدار Access Token جديد
    var accessToken = IssueAccessToken(user);
    
    return new LoginResponse(
        accessToken,
        user.Role, user.OrganizationId, user.BranchId,
        user.FullName, branchPalette, user.MustChangePassword, user.IsPlatformAdmin,
        request.RefreshToken  // ← نفس Refresh Token القديم (لم ينته بعد)
    );
}
```

### 4. Migration: `20260914092607_AddRefreshTokenTable.cs`
```csharp
// ينشئ جدول refresh_tokens
// أعمدة: id, user_id, token, expires_at, created_at, revoked_at
// فهرس على user_id للبحث السريع
```

## سلوك التطبيق الجديد

### السيناريو الأول: "Remember Me" (المستخدم يريد البقاء مسجلاً)

```
1️⃣ تسجيل الدخول
   PUT /api/auth/login
   ← يستقبل: accessToken (8h) + refreshToken (90d)

2️⃣ طلب عادي (ضمن 8 ساعات)
   GET /api/invoices
   Header: Authorization: Bearer {accessToken}

3️⃣ بعد 8 ساعات، Access Token انتهى
   GET /api/invoices
   ← خطأ 401 Unauthorized

4️⃣ الواجهة تُحدّث الجلسة
   POST /api/auth/refresh
   Body: { "refreshToken": "..." }
   ← يستقبل: accessToken جديد (8h) + refreshToken نفسه

5️⃣ الآن يستطيع المتابعة
   GET /api/invoices
   Header: Authorization: Bearer {جديد accessToken}
```

### السيناريو الثاني: المستخدم يعود بعد أسبوع

```
⏳ مرّ أسبوع → Access Token انتهى + لم يُطلب تحديث
📱 يفتح الواجهة مرة أخرى
POST /api/auth/refresh (مع Refresh Token المحفوظ محلياً)
← إذا كان Refresh Token صالح: نعم ✅
   يستقبل: accessToken جديد (8h)
← إذا كان Refresh Token منتهي (> 90 يوم): لا ❌
   يجب تسجيل دخول جديد
```

## تأثير على الواجهة (Flutter)

الواجهة يجب أن تحفظ **كلا** التوكنات محلياً:

```dart
// حفظ عند تسجيل الدخول
await storage.write(key: 'access_token', value: response.accessToken);
await storage.write(key: 'refresh_token', value: response.refreshToken);

// عند كل طلب API
void updateHeaders() {
    dio.options.headers['Authorization'] = 'Bearer ${storage.read(key: 'access_token')}';
}

// عند خطأ 401 (انتهى Access Token)
void onUnauthorized() async {
    final refreshToken = await storage.read(key: 'refresh_token');
    final newTokens = await api.refresh(refreshToken);
    
    await storage.write(key: 'access_token', value: newTokens.accessToken);
    // refreshToken لا يتغير، احفظ نفسه
    
    // أعد محاولة الطلب السابق
}
```

## الفوائد

✅ **"Remember Me"** يعمل الآن بدون مشاكل  
✅ **تمديد الجلسة** آمن وموثوق  
✅ **الخروج المبكر** ممكن (revoke refresh token)  
✅ **الأمان** أعلى (access token قصير الأجل)  
✅ **توافق** مع معايير OAuth2/OpenID  

---

**الإصدار:** v2.0.3  
**مرحلة:** جاهز للاختبار والإنتاج
