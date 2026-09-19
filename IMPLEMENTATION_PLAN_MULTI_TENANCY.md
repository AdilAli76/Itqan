# 📋 خطة تنفيذ Multi-Tenancy - أولويات فورية

## 🎯 الهدف الأساسي
**منع مستخدم من شركة A من رؤية بيانات شركة B**

---

## 📊 المرحلة 1: إعداد البنية الأساسية (أولويات عالية جداً)

### المهام الفورية (يجب إكمالها الآن):

#### ✅ 1. تحديث Models (جميع الجداول)
**الملف:** `backend/KineticEnterprise.Api/Models/Entities.cs`

```csharp
// أضف هذا الحقل إلى جميع الـ Entities:

public class Customer
{
    public string Id { get; set; }
    public string TenantId { get; set; } // ⚠️ NEW - FK to Tenant
    public Tenant Tenant { get; set; } // Navigation property
    public string FullName { get; set; }
    // ... باقي الحقول
}

public class CustomerAccount
{
    public string Id { get; set; }
    public string TenantId { get; set; } // ⚠️ NEW
    // ...
}

public class SalaryRecord
{
    public string Id { get; set; }
    public string TenantId { get; set; } // ⚠️ NEW
    // ...
}

// تكرار لكل: Invoice, CustomerLoan, PurchaseType, DirectDelivery, etc
```

**الحقول المطلوبة في كل Entity:**
```csharp
public string TenantId { get; set; } // Primary foreign key
public Tenant Tenant { get; set; } // Navigation property

// لتتبع التغييرات (اختياري لكن مهم)
public DateTime CreatedAt { get; set; }
public string CreatedBy { get; set; }
public DateTime? UpdatedAt { get; set; }
public string? UpdatedBy { get; set; }
public bool IsDeleted { get; set; }
public DateTime? DeletedAt { get; set; }
public string? DeletedBy { get; set; }
```

#### ✅ 2. إضافة Tenant و TenantUser Entities
```csharp
public DbSet<Tenant> Tenants { get; set; }
public DbSet<TenantUser> TenantUsers { get; set; }
public DbSet<ModuleLicense> ModuleLicenses { get; set; }
public DbSet<AuditLog> AuditLogs { get; set; }
```

#### ✅ 3. إنشاء Migration
```powershell
# تغيير المسار
cd backend/KineticEnterprise.Api

# إنشاء migration
dotnet ef migrations add AddTenantSupport

# مراجعة الملف المُنشأ:
# Migrations/[timestamp]_AddTenantSupport.cs

# تطبيق التحديثات
dotnet ef database update
```

#### ✅ 4. تحديث AppDbContext
```csharp
// في OnModelCreating:
modelBuilder.Entity<Customer>()
    .HasOne(c => c.Tenant)
    .WithMany()
    .HasForeignKey(c => c.TenantId)
    .OnDelete(DeleteBehavior.Cascade);

// تكرار لكل Entity تحتوي على TenantId
```

---

## 📱 المرحلة 2: تطبيق الفصل الأمني (أولويات عالية)

### المهام الحالية:

#### ✅ 5. تحديث AuthController
**الملف:** `backend/KineticEnterprise.Api/Controllers/AuthController.cs`

```csharp
[HttpPost("login")]
public async Task<IActionResult> Login([FromBody] LoginRequest request)
{
    var user = await _dbContext.Users
        .Include(u => u.TenantUsers)
        .FirstOrDefaultAsync(u => u.Email == request.Email);
    
    if (user == null)
        return Unauthorized(new { error = "البيانات غير صحيحة" });
    
    // التحقق من كلمة المرور
    if (!VerifyPassword(user.PasswordHash, request.Password))
        return Unauthorized(new { error = "البيانات غير صحيحة" });
    
    // استخراج معلومات المؤسسة الأولى للمستخدم
    var tenantUser = user.TenantUsers.FirstOrDefault();
    if (tenantUser == null)
        return Unauthorized(new { error = "لم يتم العثور على مؤسسة مرتبطة" });
    
    var tenant = await _dbContext.Tenants.FindAsync(tenantUser.TenantId);
    var modules = await _dbContext.ModuleLicenses
        .Where(m => m.TenantId == tenantUser.TenantId && m.IsEnabled)
        .Select(m => m.ModuleName)
        .ToListAsync();
    
    // إنشاء JWT Token مع claims
    var token = GenerateJwtToken(user, tenantUser, modules);
    
    return Ok(new
    {
        accessToken = token,
        tenantId = tenantUser.TenantId,
        tenantName = tenant.Name,
        role = tenantUser.Role,
        enabledModules = modules
    });
}

private string GenerateJwtToken(ApplicationUser user, TenantUser tenantUser, List<string> modules)
{
    var claims = new List<Claim>
    {
        new Claim(ClaimTypes.NameIdentifier, user.Id),
        new Claim(ClaimTypes.Email, user.Email),
        new Claim("tenant_id", tenantUser.TenantId), // ⚠️ مهم جداً
        new Claim("role", tenantUser.Role),
        new Claim("version", "2.0.5"),
    };
    
    // إضافة الصلاحيات
    if (tenantUser.Permissions != null)
    {
        foreach (var permission in tenantUser.Permissions)
        {
            claims.Add(new Claim("permission", permission));
        }
    }
    
    // إضافة الوحدات المفعلة
    foreach (var module in modules)
    {
        claims.Add(new Claim("module", module));
    }
    
    var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_configuration["Jwt:Secret"]));
    var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
    
    var token = new JwtSecurityToken(
        issuer: _configuration["Jwt:Issuer"],
        audience: _configuration["Jwt:Audience"],
        claims: claims,
        expires: DateTime.UtcNow.AddHours(8),
        signingCredentials: creds
    );
    
    return new JwtSecurityTokenHandler().WriteToken(token);
}
```

#### ✅ 6. تحديث جميع Controllers
**الأولوية:** ابدأ بـ CustomersController

```csharp
// من:
[ApiController]
public class CustomersController : ControllerBase
{
    private readonly AppDbContext _dbContext;
}

// إلى:
[ApiController]
[Authorize]
public class CustomersController : TenantAwareControllerBase
{
    private readonly AppDbContext _dbContext;
    
    public CustomersController(
        ITenantService tenantService,
        ILogger<CustomersController> logger,
        AppDbContext dbContext)
        : base(tenantService, logger)
    {
        _dbContext = dbContext;
    }
}
```

**تحديث جميع الـ queries:**
```csharp
// من:
var customers = await _dbContext.Customers.ToListAsync();

// إلى:
var customers = await _dbContext.Customers
    .Where(c => c.TenantId == CurrentTenantId)
    .ToListAsync();

// أو (أفضل):
var tenantService = GetService<ITenantService>();
tenantService.SetCurrentTenant(CurrentTenantId);
// الآن Global Filters تعمل تلقائياً
```

---

## 🔧 المرحلة 3: اختبار شامل (أولويات متوسطة)

### اختبارات أمان البيانات:

```bash
# 1. اختبر أن User من Org1 يرى فقط بيانات Org1
GET /api/customers
Headers: { Authorization: "Bearer token_org1" }
Response: ✅ عملاء Org1 فقط

# 2. اختبر أن User من Org2 يرى فقط بيانات Org2
GET /api/customers
Headers: { Authorization: "Bearer token_org2" }
Response: ✅ عملاء Org2 فقط

# 3. حاول استخدام Token من Org1 للوصول إلى بيانات Org2
GET /api/customers/org2_customer_id
Headers: { Authorization: "Bearer token_org1" }
Response: ❌ 401 Unauthorized أو 404 Not Found
```

---

## 🚀 المرحلة 4: Deployment (أولويات منخفضة - تأتي لاحقاً)

### خطوات الـ Deployment:

```bash
# 1. Backup قاعدة البيانات الحالية
# 2. تطبيق Migration على جميع قواعد البيانات
# 3. تحديث API على الـ Server
# 4. تحديث Flutter App
# 5. اختبار نهائي شامل
```

---

## ⏱️ الجدول الزمني المقترح

### الأسبوع الأول (الأولويات العالية):
- ✅ Day 1: تحديث Entities وإضافة TenantId
- ✅ Day 2: إنشاء وتطبيق Migration
- ✅ Day 3: تحديث AuthController وإضافة Claims
- ✅ Day 4-5: تحديث جميع Controllers

### الأسبوع الثاني (الأولويات المتوسطة):
- ✅ Day 6-7: اختبار شامل
- ✅ Day 8-10: إصلاح الأخطاء والـ Edge cases

### الأسبوع الثالث (الأولويات المنخفضة):
- ✅ Deployment على الـ Server
- ✅ تحديث Flutter App
- ✅ اختبار شامل على الإنتاج

---

## 📝 Checklist المراجعة

### Before Merge:
- [ ] جميع Entities تحتوي على TenantId
- [ ] Migration تم إنشاؤها وتطبيقها بنجاح
- [ ] AuthController يوّلد JWT مع tenant_id claim
- [ ] جميع Controllers ترث من TenantAwareControllerBase
- [ ] جميع الـ queries تفلترها حسب CurrentTenantId
- [ ] اختبار الفصل بين البيانات نجح

### Before Deploy:
- [ ] جميع الاختبارات تمرت
- [ ] لا توجد أخطاء في الـ Logs
- [ ] Performance لم ينخفض
- [ ] Audit Logging يعمل
- [ ] Flutter App تحديثت

---

## 🔗 ملفات مرجعية

```
✅ TenantModels.cs - Entities الجديدة
✅ TenantService.cs - خدمة إدارة المؤسسات
✅ TenantAwareControllerBase.cs - Base Controller
✅ MULTI_TENANCY_ARCHITECTURE.md - شرح شامل
```

---

## ❌ الأخطاء الشائعة (تجنبها!)

### ❌ 1: نسيان إضافة TenantId في Query
```csharp
// ❌ خطأ:
var customers = await _dbContext.Customers.ToListAsync();

// ✅ صحيح:
var customers = await _dbContext.Customers
    .Where(c => c.TenantId == CurrentTenantId)
    .ToListAsync();
```

### ❌ 2: عدم تحديث AuthController
```csharp
// ❌ خطأ: Token بدون tenant_id claim
var token = GenerateJwtToken(user); // ناقص TenantId!

// ✅ صحيح:
var token = GenerateJwtToken(user, tenantUser, modules);
```

### ❌ 3: نسيان UpdatedBy عند التعديل
```csharp
// ❌ خطأ:
customer.FullName = request.FullName;
_dbContext.SaveChanges(); // من عدّل؟ متى؟

// ✅ صحيح:
customer.FullName = request.FullName;
customer.UpdatedAt = DateTime.UtcNow;
customer.UpdatedBy = CurrentUserId;
_dbContext.SaveChanges();
```

---

## 📊 النتيجة المتوقعة

بعد اكتمال هذه الخطوات:

```
✅ شركة A → ترى بيانات شركة A فقط
✅ شركة B → ترى بيانات شركة B فقط
✅ شركة C → ترى بيانات شركة C فقط
✅ Admin → يستطيع إدارة جميع الشركات
✅ Audit → تسجيل دقيق لكل تغيير

❌ مستحيل لشركة A رؤية بيانات B
❌ مستحيل للاختراق عبر SQL injection
❌ مستحيل الوصول لبيانات محذوفة
```

---

**آخر تحديث:** 2026-09-15  
**الحالة:** جاهز للتنفيذ الفوري
