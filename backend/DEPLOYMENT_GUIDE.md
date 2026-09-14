# دليل نشر Kinetic ERP v2.0.3

## المتطلبات
- .NET 8.0 Runtime على الخادم
- SQL Server 2019+ مع Windows Authentication
- قاعدة بيانات `ItqanEnterprise` موجودة

## خطوات النشر

### 1️⃣ نسخ الملفات
انسخ مجلد `publish` من جهازك إلى الخادم:
```
مصدر: C:\Users\F\Downloads\itqan_erp\backend\publish
وجهة على الخادم: C:\Kinetic\v2.0.3
```

### 2️⃣ تطبيق ترحيل قاعدة البيانات
قبل تشغيل التطبيق، طبّق الترحيل على قاعدة البيانات:

```powershell
# على الخادم
cd C:\Kinetic\v2.0.3

# إذا كان dotnet ef مثبت عالمياً
dotnet ef database update `
  --connection "Server=.;Database=ItqanEnterprise;Trusted_Connection=true;Encrypt=false;"
```

**إذا لم يكن dotnet ef مثبت:**
```powershell
# تثبيت أداة EF Core
dotnet tool install --global dotnet-ef

# ثم طبّق الترحيل
dotnet ef database update `
  --connection "Server=.;Database=ItqanEnterprise;Trusted_Connection=true;Encrypt=false;"
```

### 3️⃣ تحديث appsettings.Production.json
تأكد من أن إعدادات الاتصال صحيحة:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=.;Database=ItqanEnterprise;Trusted_Connection=true;Encrypt=false;"
  },
  "Jwt": {
    "SecretKey": "your-secret-key-here",
    "Issuer": "KineticERP",
    "Audience": "KineticERPClients"
  }
}
```

### 4️⃣ تشغيل التطبيق

**للاختبار المباشر:**
```powershell
cd C:\Kinetic\v2.0.3
dotnet KineticEnterprise.Api.dll
```

**على IIS:**
1. افتح IIS Manager
2. أنشئ موقع ويب جديد أو حدّث الموقع الموجود
3. أشر إلى مجلد `C:\Kinetic\v2.0.3`
4. تأكد من تشغيل Application Pool بهوية مناسبة

## التحقق من النجاح

بعد التطبيق، تحقق من:
1. ✅ تطبيق الترحيل بدون أخطاء
2. ✅ التطبيق يبدأ بدون أخطاء
3. ✅ يمكنك تسجيل الدخول بـ Refresh Token الجديد

## اختبار Refresh Token

```bash
# 1. تسجيل الدخول
POST /api/auth/login
{
  "username": "admin",
  "password": "password",
  "rememberMe": true
}

# الاستجابة تتضمن:
{
  "accessToken": "eyJ...",
  "refreshToken": "random-token-string",
  "role": "admin",
  ...
}

# 2. عند انتهاء Access Token (بعد 8 ساعات)
POST /api/auth/refresh
{
  "refreshToken": "random-token-string"
}

# تحصل على Access Token جديد
{
  "accessToken": "eyJ...",
  "refreshToken": "same-token-string",
  ...
}
```

## الملفات الرئيسية المتغيرة

- `Controllers/AuthController.cs` - منطق تحديث الجلسة الجديد
- `Models/Entities.cs` - كلاس RefreshToken الجديد
- `Data/AppDbContext.cs` - جدول refresh_tokens
- `Migrations/20260914092607_AddRefreshTokenTable.cs` - ترحيل الجداول

---
**الإصدار:** v2.0.3  
**التاريخ:** 2026-09-14  
**الحالة:** جاهز للإنتاج
