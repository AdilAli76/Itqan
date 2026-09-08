# Kinetic ERP v1.6.6 - Build & Deployment Instructions

## 📋 Pre-Build Checklist

- [ ] نسخة Windows Server أو Linux للـ backend
- [ ] .NET 8.0 SDK مثبت
- [ ] Flutter 3.3.0+ مثبت
- [ ] SQL Server 2019+ أو PostgreSQL
- [ ] Node.js 18+ للـ web assets
- [ ] PowerShell 5.0+ (للـ Windows deployment)
- [ ] حوالي 10 GB مساحة حرة على القرص

## 🔨 خطوات البناء (Build Steps)

### 1️⃣ التحضيرات الأولية

```bash
# انسخ الفرع الجديد
cd /home/user/kinetic-erp
git fetch origin claude/comprehensive-features-1.6.6
git checkout claude/comprehensive-features-1.6.6

# تحقق من الملفات الجديدة
git log --oneline | head -5
```

### 2️⃣ تطبيق الهجرة (Database Migration)

**على SQL Server:**
```powershell
# من PowerShell على الخادم
sqlcmd -S YOUR_SERVER -U sa -P YOUR_PASSWORD -d kinetic_erp -i .\docs\MIGRATIONS_1.6.6.sql

# تحقق من الجداول الجديدة
sqlcmd -S YOUR_SERVER -U sa -P YOUR_PASSWORD -d kinetic_erp -Q "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME IN ('customer_tags', 'entitlement_deduction_schedules', 'print_audit_logs')"
```

**أو على MySQL/PostgreSQL:**
```bash
# قم بتحويل SQL Migration حسب نوع قاعدة البيانات الخاصة بك
# أو استخدم Entity Framework migrations
cd backend/KineticEnterprise.Api
dotnet ef database update
```

### 3️⃣ البناء (Backend Build)

```bash
# انتقل لمجلد Backend
cd /home/user/kinetic-erp/backend/KineticEnterprise.Api

# استعيد الحزم
dotnet restore

# بناء Release
dotnet build --configuration Release

# اختبار
dotnet test

# نشر
dotnet publish --configuration Release --output ../../bin/publish/backend
```

### 4️⃣ البناء (Frontend Build)

```bash
# انتقل لمجلد الـ root
cd /home/user/kinetic-erp

# استعيد الحزم
flutter pub get

# بناء Web
flutter build web --release --build-name=1.6.6 --build-number=1660

# بناء Windows (Desktop)
flutter build windows --release

# بناء Android (اختياري)
flutter build apk --release --build-name=1.6.6 --build-number=1660
```

### 5️⃣ الحزم (Packaging)

استخدم السكريبت الموجود:

```powershell
# على Windows
cd C:\kinetic-erp
.\tool\publish.ps1 -Version "1.6.6"

# سيقوم بـ:
# ✓ مسح الـ output القديم
# ✓ dart analyze
# ✓ بناء backend
# ✓ بناء frontend (web)
# ✓ بناء desktop (windows)
# ✓ ضغط SQL files
# ✓ حزم كل شيء في ZIP

# النتيجة: kinetic_pkg_YYYY-MM-DD_HHMM.zip (~50-100 MB)
```

أو يدويًا:

```bash
# إنشاء مجلد الحزمة
mkdir -p build/package/1.6.6

# نسخ Backend
cp -r bin/publish/backend/* build/package/1.6.6/

# نسخ Frontend (Web)
cp -r build/web build/package/1.6.6/wwwroot

# نسخ Desktop
cp -r build/windows/x64/runner/Release build/package/1.6.6/desktop

# نسخ SQL
cp docs/MIGRATIONS_1.6.6.sql build/package/1.6.6/

# ضغط
cd build/package
zip -r kinetic_pkg_1.6.6.zip 1.6.6/
```

## 🚀 خطوات النشر (Deployment)

### على الخادم:

```powershell
# 1. انسخ الملف المضغوط
Copy-Item .\kinetic_pkg_1.6.6.zip \\SERVER\c$\publish\

# 2. من على الخادم
cd C:\publish
Expand-Archive kinetic_pkg_1.6.6.zip -DestinationPath .\extracted

# 3. نطبق الهجرة
sqlcmd -S . -U sa -P PASSWORD -d kinetic_erp -i .\extracted\1.6.6\MIGRATIONS_1.6.6.sql

# 4. نوقف IIS
iisreset /stop

# 5. ننسخ الملفات
robocopy .\extracted\1.6.6\ C:\kinetic\ /MIR

# 6. نشغل IIS
iisreset /start

# 7. نتحقق
# الذهاب إلى https://kinetic-erp.example.com
```

## ✅ التحقق (Verification)

بعد النشر مباشرة:

```powershell
# 1. التحقق من الخدمات
Get-Service | grep -i "kinetic\|iis"

# 2. التحقق من قاعدة البيانات
sqlcmd -S . -U sa -P PASSWORD -d kinetic_erp -Q "SELECT COUNT(*) FROM customer_tags; SELECT COUNT(*) FROM entitlement_deduction_schedules; SELECT COUNT(*) FROM print_audit_logs;"

# 3. اختبر الـ API
curl -X GET https://kinetic-erp.example.com/api/health -v

# 4. تسجيل الدخول واختبر:
# - إضافة وسم للعميل ✓
# - اختيار فئة العميل ✓
# - الطباعة مع التبديل ✓
# - خيارات الدفع في POS ✓
```

## 🧪 قائمة الاختبار (Testing Checklist)

قبل الإطلاق للإنتاج:

### Customer Tags
- [ ] يمكن إضافة وسم للعميل
- [ ] الأوسام تعرض كـ badges
- [ ] البحث بالوسم يعمل
- [ ] الحذف يعمل

### Category Field
- [ ] القائمة المنسدلة تظهر
- [ ] الاختيار يحفظ
- [ ] الفلترة تعمل

### Print Control
- [ ] زر التبديل يظهر
- [ ] إيقاف الطباعة يعمل
- [ ] السجل يسجل الطباعات

### Enhanced POS
- [ ] خيارات الدفع تظهر
- [ ] اختيار Cash يعمل
- [ ] اختيار Wallet يعمل
- [ ] اختيار Split يعمل

### Entitlements (إذا طبقت الخدمة)
- [ ] الجدول ينشأ
- [ ] الحسم الشهري يعمل
- [ ] السجل يسجل

## 📊 معلومات الإطلاق

```
Version: 1.6.6
Release Date: 2026-09-09
Database: Updated (3 new tables)
Features: 7 new major features
Compatibility: 1.6.5 → 1.6.6 (forward compatible)
Rollback: See V1.6.6_MIGRATION_GUIDE.md
```

## ⚠️ ملاحظات مهمة

1. **النسخ الاحتياطية**: عمل نسخة احتياطية من قاعدة البيانات قبل الهجرة
2. **الاختبارات**: اختبر كل ميزة على Staging قبل Production
3. **الأداء**: قد تحتاج لإعادة إنشاء الفهارس بعد النشر
4. **السجلات**: راجع Logs في مجلد Backend لتتبع المشاكل

## 📞 استكشاف الأخطاء

### الخطأ: جدول غير موجود
```sql
-- تحقق من الجداول
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_NAME IN ('customer_tags', 'entitlement_deduction_schedules', 'print_audit_logs');

-- إذا لم تظهر، طبق الهجرة يدويًا
sqlcmd -S . -U sa -P PASSWORD -d kinetic_erp -i MIGRATIONS_1.6.6.sql
```

### الخطأ: الـ API لا يرد
```bash
# تحقق من IIS
iisreset

# تحقق من logs
tail -f C:\kinetic\logs\*.log

# تحقق من الـ connection string
# في appsettings.json
```

### الخطأ: Frontend لا يحمل
```bash
# امسح الـ cache
rm -rf ~/.flutter
flutter clean
flutter pub get
flutter build web --release
```

## 🎉 عند النجاح

```
✓ Database migrated (3 new tables created)
✓ Backend deployed (all endpoints active)
✓ Frontend deployed (all widgets loaded)
✓ Print system enhanced (caching, error handling)
✓ POS improved (payment methods, print toggle)
✓ Customer tags working (add/remove tags)
✓ Category field active (in forms)
✓ All features tested and verified

🚀 v1.6.6 is now LIVE!
```

---

**Time to build**: ~30-45 minutes
**Time to deploy**: ~15-30 minutes (excluding testing)
**Time to test**: ~1-2 hours
**Total**: ~2-3 hours

**Ready to build? Run**: `.\tool\publish.ps1 -Version "1.6.6"`
