# النشر المحليّ المباشر

> نشرٌ بدون GitHub Actions — مباشرة من السيرفر

## الخطوات

### 1️⃣ على جهازك (محليّ)

**أ) بناء النسخة:**

```bash
# Backend
cd backend
dotnet publish -c Release

# Frontend (اختياري)
cd ../frontend
flutter build web --release
```

**ب) نسخ المجلد `tool/` كاملاً إلى السيرفر:**

عبر RDP أو SSH، انسخ:
- `tool/local_deploy.ps1`
- `tool/sync_and_deploy.ps1`
- أي أدوات أخرى مطلوبة

### 2️⃣ على السيرفر (Windows)

**اختيار 1: البناء والنشر معاً (مثالي)**

إذا كان مجلد `backend` و `frontend` موجودين على السيرفر:

```powershell
cd C:\kinetic-staging\tool

# بناء ونسخ ونشر دفعة واحدة
.\sync_and_deploy.ps1 -Target staging -Version "1.6.6"

# أو بدون بناء (إذا كانت الملفات المبنيّة موجودة)
.\sync_and_deploy.ps1 -Target staging -Version "1.6.6" -SkipBuild
```

**اختيار 2: النشر فقط (إذا كانت الملفات منسوخة بالفعل)**

```powershell
cd C:\kinetic-staging\tool

# نشرة مباشرة
.\local_deploy.ps1 -Target staging -Version "1.6.6"

# مع تخطّي ترحيلات قاعدة البيانات
.\local_deploy.ps1 -Target staging -Version "1.6.6" -SkipDb
```

## الخيارات

| الخيار | الوصف |
|--------|-------|
| `-Target` | `staging` أو `production` (إجباري) |
| `-Version` | رقم النسخة، مثال `1.6.6` (إجباري) |
| `-SkipBuild` | تخطّي البناء — استخدام الملفات السابقة |
| `-SkipDb` | تخطّي ترحيلات قاعدة البيانات |

## الملفات المطلوبة على السيرفر

```
C:\kinetic-staging\
├── backend\
│   ├── bin\Release\        ← الملفات المبنيّة
│   └── appsettings.json
├── frontend\
│   └── build\web\          ← الملفات المبنيّة
└── tool\
    ├── deploy_update.ps1
    ├── backup.ps1
    ├── local_deploy.ps1
    └── sync_and_deploy.ps1
```

## المثال الكامل

### على جهازك:

```powershell
# 1. بناء Backend
cd backend
dotnet publish -c Release

# 2. بناء Frontend (اختياري)
cd ../frontend
flutter build web --release

# 3. نسخ tool/ إلى السيرفر عبر RDP
# (انسخ كل ملفات tool/ إلى C:\kinetic-staging\tool)
```

### على السيرفر:

```powershell
# فتح PowerShell كمسؤول
cd C:\kinetic-staging\tool

# النشر المباشر
.\sync_and_deploy.ps1 -Target staging -Version "1.6.6"

# بعد النجاح، انتقل للإنتاج
.\sync_and_deploy.ps1 -Target production -Version "1.6.6"
```

## السجلات

كل نشرة تُسجَّل في:
- `C:\kinetic-staging\deploy.log`
- `C:\kinetic\deploy.log`

السطر الأخير يظهر آخر نشرة:
```powershell
Get-Content C:\kinetic-staging\deploy.log -Tail 5
```

## استكشاف الأخطاء

### ❌ "الملف غير موجود"
- تأكد من وجود `deploy_update.ps1` في `C:\kinetic-staging\tool`

### ❌ "فشل البناء"
- تأكد من `.NET SDK 8.0+` على جهازك
- تأكد من مجلد `backend` و `frontend`

### ❌ "Access denied"
- فتح PowerShell **كمسؤول**
- تأكد من حساب خدمة Runner له صلاحيات إدارية

## النسخ الإصدارة الجديدة

```powershell
# إنشاء وسم جديد
git tag v1.6.7

# النشر بالوسم الجديد
.\sync_and_deploy.ps1 -Target staging -Version "1.6.7"
```
