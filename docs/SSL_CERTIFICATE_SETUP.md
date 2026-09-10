# SSL Certificate Setup — حل مشكلة الشهادة

## المشكلة
ربط الشهادة SSL للدومين في السيرفر يسبب أخطاء في الاتصال.

---

## الحل السريع (Local Development)

### الخطوة 1: تنظيف وإعادة إنشاء الشهادة
```bash
cd backend/KineticEnterprise.Api
dotnet dev-certs https --clean
dotnet dev-certs https --trust
```

### الخطوة 2: تشغيل السيرفر
```bash
dotnet run
```

الآن السيرفر سيعمل على:
- HTTP: `http://localhost:5000`
- HTTPS: `https://localhost:5001` (بدون تحذيرات)

---

## الحل للـ Production (باستخدام Let's Encrypt)

### الخطوة 1: تثبيت Certbot
```bash
# Windows (using Chocolatey)
choco install certbot -y

# أو من الموقع: https://certbot.eff.org/
```

### الخطوة 2: تشغيل Script الإعداد
```powershell
.\tool\ssl-certificate-setup.ps1 -Domain "erp.your-domain.com" -Email "admin@your-domain.com"
```

### الخطوة 3: تحويل الشهادة إلى PFXX
```bash
openssl pkcs12 -export ^
  -in C:\ProgramData\letsencrypt\live\erp.your-domain.com\fullchain.pem ^
  -inkey C:\ProgramData\letsencrypt\live\erp.your-domain.com\privkey.pem ^
  -out C:\ProgramData\letsencrypt\live\erp.your-domain.com\pkcs12\kinetic.pfx ^
  -passout pass:your-secure-password
```

### الخطوة 4: تحديث appsettings.Production.json
```json
{
  "ConnectionStrings": {
    "Default": "Server=localhost\\SQLEXPRESS01;Database=KineticEnterprise;Trusted_Connection=True;TrustServerCertificate=True;"
  },
  "Jwt": {
    "Key": "6D7l3yCEopUPxcGMAkOYfXHoSVYwI1JCaEHbbZL2wadKVgZaS1rhA4pD7zdOYfId"
  },
  "Kestrel": {
    "Certificates": {
      "Default": {
        "Path": "C:\\ProgramData\\letsencrypt\\live\\erp.your-domain.com\\pkcs12\\kinetic.pfx",
        "Password": "your-secure-password"
      }
    },
    "Endpoints": {
      "Http": {
        "Url": "http://0.0.0.0:5000"
      },
      "Https": {
        "Url": "https://0.0.0.0:5001"
      }
    }
  }
}
```

### الخطوة 5: إصلاح صلاحيات الملفات (إذا لزم الأمر)
```bash
icacls "C:\ProgramData\letsencrypt" /grant "IIS_IUSRS:F"
```

### الخطوة 6: تشغيل السيرفر
```bash
dotnet run --configuration Production
```

---

## Flutter التطبيق

### للـ Production (مع شهادة حقيقية):
```bash
flutter run -d chrome --dart-define=API_BASE_URL=https://erp.your-domain.com/api
```

### للـ Local (بدون تحذيرات):
```bash
flutter run -d chrome --dart-define=API_BASE_URL=https://localhost:5001/api
```

---

## Renewal التلقائي (مهم!)

Let's Encrypt تنتهي بعد 90 يوم. أعداد renewal تلقائي:

### Windows Task Scheduler
```powershell
$trigger = New-ScheduledTaskTrigger -Daily -At 3:00AM
$action = New-ScheduledTaskAction -Execute "certbot" -Argument "renew --quiet"
Register-ScheduledTask -TaskName "CertBot Renew" -Trigger $trigger -Action $action -RunLevel Highest
```

### Linux (Cron)
```bash
0 3 * * * certbot renew --quiet
```

---

## Troubleshooting

### 1. خطأ: "The ACME server refused our request"
**الحل:** تحقق من أن الدومين يشير بشكل صحيح إلى خادمك
```bash
nslookup erp.your-domain.com
```

### 2. خطأ: "Port 80 or 443 already in use"
**الحل:** أغلق التطبيقات التي تستخدم هذه المنافذ
```bash
netstat -ano | findstr :80
netstat -ano | findstr :443
```

### 3. عدم الثقة في الشهادة على المتصفح
**الحل:** 
- تأكد من تثبيت الشهادة صحيحة
- امسح Cache المتصفح
- أعد تشغيل المتصفح

---

## الخلاصة

| المرحلة | الطريقة | المميزات |
|--------|--------|---------|
| **Local Dev** | `dotnet dev-certs` | سريع، آمن محلياً |
| **Staging** | Self-signed | اختبار الشهادة بدون تكلفة |
| **Production** | Let's Encrypt | مجاني، موثوق، تلقائي |

**الآن يجب أن يعمل السيرفر بدون تحذيرات شهادة!** ✅
