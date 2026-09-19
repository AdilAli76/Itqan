# Backend Setup — البدء السريع

## 🚀 الخطوة 1: التحقق من المتطلبات

```powershell
# تحقق من .NET SDK
dotnet --version

# تحقق من SQL Server
# يجب أن يكون مثبتاً وقيد التشغيل
# إذا لم يكن مثبتاً، حمّل SQL Server 2022 Express (مجاني):
# https://www.microsoft.com/en-us/sql-server/sql-server-express
```

## 📋 الخطوة 2: تحضير قاعدة البيانات

### أ) إنشاء قاعدة جديدة
```powershell
# استخدم SQL Server Management Studio أو الأمر التالي:
sqlcmd -S localhost -Q "CREATE DATABASE kinetic_erp;"
```

### ب) تشغيل مخطط قاعدة البيانات
```powershell
# من مجلد المشروع الرئيسي:
cd itqan_erp
sqlcmd -S localhost -d kinetic_erp -i docs\DATABASE_SCHEMA_SQLSERVER.sql
```

## 🔧 الخطوة 3: تكوين Backend

### 1. اذهب لمجلد Backend
```powershell
cd backend\KineticEnterprise.Api
```

### 2. عدّل `appsettings.json`
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Database=kinetic_erp;Trusted_Connection=true;"
  },
  "Jwt": {
    "SecretKey": "your-super-secret-key-min-32-chars",
    "Issuer": "https://localhost:5001",
    "Audience": "kinetic-app",
    "ExpirationMinutes": 480
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning"
    }
  }
}
```

## ▶️ الخطوة 4: تشغيل Backend

### الطريقة الأولى: التشغيل المباشر
```powershell
cd backend\KineticEnterprise.Api
dotnet run

# سيشتغل على: https://localhost:5001
```

### الطريقة الثانية: البناء والتشغيل
```powershell
cd backend\KineticEnterprise.Api
dotnet build
dotnet run --configuration Release
```

### الطريقة الثالثة: في Visual Studio
```
File → Open Folder → اختر itqan_erp
Debug → Start Debugging (F5)
```

## ✅ التحقق من التشغيل

### فتح متصفح:
```
https://localhost:5001/swagger/index.html
```

يجب أن تظهر واجهة Swagger API

### أو اختبر عبر curl:
```bash
# اختبر الاتصال
curl -k https://localhost:5001/health

# يجب أن ترى: "OK" أو رسالة صحة
```

## 🔐 بيانات المستخدم الافتراضية

**بريد:** admin@itqan.com  
**كلمة المرور:** Admin@123456

```powershell
# إذا كنت تريد تغيير كلمة المرور:
# استخدم البرنامج بعد تسجيل الدخول → الإعدادات
```

## 🔗 ربط Flutter Desktop بـ Backend

التطبيق يبحث عن:
```
https://localhost:5001/api
```

إذا كان على خادم مختلف:
1. افتح شاشة الإعدادات في التطبيق
2. غيّر عنوان API
3. أعد التشغيل

أو **أثناء البناء:**
```powershell
flutter run -d windows --dart-define=API_BASE_URL=https://your-server.com/api
```

## 🧪 اختبار API Endpoints

### 1. تسجيل الدخول
```bash
curl -X POST https://localhost:5001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@itqan.com","password":"Admin@123456"}' \
  -k

# الرد: يحتوي على JWT token
```

### 2. الحصول على المنتجات
```bash
curl -X GET https://localhost:5001/api/products \
  -H "Authorization: Bearer <token>" \
  -k
```

### 3. إنشاء فاتورة
```bash
curl -X POST https://localhost:5001/api/invoices \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"items":[...],"total":0}' \
  -k
```

## ⚠️ حل المشاكل الشائعة

### خطأ: "Access Denied" / "Connection Timeout"
```powershell
# تحقق من تشغيل SQL Server
Get-Service -Name "MSSQLSERVER" | Select-Object Status

# إذا كانت متوقفة:
Start-Service -Name "MSSQLSERVER"
```

### خطأ: "Cannot find Database"
```bash
# تأكد من تنفيذ المخطط:
sqlcmd -S localhost -d kinetic_erp \
  -i docs\DATABASE_SCHEMA_SQLSERVER.sql
```

### خطأ: "Certificate Error"
```powershell
# للتطوير فقط:
dotnet dev-certs https --clean
dotnet dev-certs https --trust
```

### خطأ: "Seed Data Failed"
```powershell
# احذف البيانات الموجودة وأعد التشغيل
# أو غيّر seed data في Program.cs
```

## 📊 مراقبة Backend

### عرض السجلات:
```powershell
# سيظهر في console عند التشغيل
# ابحث عن "Started server" و "Listening on"
```

### قاعدة البيانات:
```powershell
# استخدم SQL Server Management Studio
# أو SQL Server Data Tools في Visual Studio
```

## 🔄 إعادة بناء Backend

إذا أجريت تعديلات على الكود:
```powershell
cd backend\KineticEnterprise.Api

# إعادة تحميل الحزم
dotnet restore

# إعادة البناء
dotnet build

# التشغيل
dotnet run
```

## 🚀 النسخة الإنتاجية

```powershell
cd backend\KineticEnterprise.Api

# بناء Release
dotnet build --configuration Release

# نشر على IIS
dotnet publish -c Release -o ./publish

# ثم انسخ مجلد publish إلى IIS
```

## 📌 الملفات المهمة

| الملف | الوصف |
|------|-------|
| `Program.cs` | نقطة الدخول |
| `appsettings.json` | التكوينات |
| `Controllers/` | API endpoints |
| `Models/` | نماذج البيانات |
| `Services/` | منطق الأعمال |
| `Migrations/` | تحديثات قاعدة البيانات |

---

## ✨ نصائح إضافية

1. **استخدم Postman** لاختبار API بسهولة
2. **فعّل CORS** في appsettings.json للتطوير
3. **استخدم DevTools** من Visual Studio للتصحيح
4. **احفظ JWT** في آمن (لا تحفظه في plain text)
5. **استخدم HTTPS** دائماً في الإنتاج

---

**Backend جاهز للعمل! ✅**
