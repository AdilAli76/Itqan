# ⚡ مرجع الأوامر السريعة

## 🚀 التشغيل السريع

### التطبيق الديسكتوب فقط
```powershell
.\build\windows\x64\runner\Release\kinetic_enterprise.exe
```

### التطبيق + Backend معاً
```powershell
# نافذة 1: Backend
cd backend\KineticEnterprise.Api
dotnet run

# نافذة 2: Desktop (في مجلد المشروع الرئيسي)
.\build\windows\x64\runner\Release\kinetic_enterprise.exe
```

### الويب في المتصفح
```powershell
flutter run -d chrome
```

### استخدام السكربت التفاعلي (موصى به)
```powershell
.\run-itqan.ps1
# ثم اختر من القائمة
```

---

## 🔨 البناء والتطوير

### البناء الكامل (Windows Desktop)
```powershell
flutter build windows --release
```

### البناء الكامل (Web)
```powershell
flutter build web --release
```

### التطوير المحلي (Debug مع Hot Reload)
```powershell
flutter run -d windows  # اضغط 'r' لإعادة التحميل السريع
```

### تحديث التبعيات
```powershell
flutter pub get
cd backend\KineticEnterprise.Api
dotnet restore
```

---

## 🗄️ قاعدة البيانات

### إنشاء قاعدة جديدة
```sql
CREATE DATABASE kinetic_erp;
```

### تنفيذ المخطط
```powershell
sqlcmd -S localhost -d kinetic_erp -i docs\DATABASE_SCHEMA_SQLSERVER.sql
```

### حذف قاعدة وإعادة إنشاء (إذا حدثت مشاكل)
```sql
DROP DATABASE IF EXISTS kinetic_erp;
CREATE DATABASE kinetic_erp;
```

### فحص قوائم الجداول
```sql
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'dbo' ORDER BY TABLE_NAME;
```

---

## 🔐 شهادات HTTPS (للتطوير)

### إنشاء/تثبيت الشهادة
```powershell
dotnet dev-certs https --trust
```

### حذف والإنشاء من جديد
```powershell
dotnet dev-certs https --clean
dotnet dev-certs https --trust
```

---

## 🧪 الاختبار

### تشغيل جميع الاختبارات
```powershell
flutter test
```

### اختبار ملف معين
```powershell
flutter test test\features\auth\auth_test.dart
```

### اختبار تطبيق الويب
```powershell
flutter test -d chrome
```

### اختبار البناء
```powershell
flutter build apk --debug --analyze-size
```

---

## 📱 نسخة Android

### بناء APK Debug
```powershell
flutter build apk --debug
```

### بناء APK Release
```powershell
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-server.com/api
```

### تثبيت على الهاتف
```powershell
flutter install
```

---

## 🌐 Backend API

### تشغيل Backend
```powershell
cd backend\KineticEnterprise.Api
dotnet run
```

### تشغيل في وضع Release
```powershell
cd backend\KineticEnterprise.Api
dotnet run --configuration Release
```

### الوصول إلى Swagger API
```
https://localhost:5001/swagger/index.html
```

### اختبار API بـ curl

```bash
# تسجيل الدخول
curl -k -X POST https://localhost:5001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@itqan.com","password":"Admin@123456"}'

# الحصول على المنتجات
curl -k -H "Authorization: Bearer <token>" \
  https://localhost:5001/api/products
```

---

## 🔧 الأدوات والبرامج

### DevTools (أدوات Dart)
```powershell
flutter pub global activate devtools
flutter pub global run devtools
```

### Analyzer (فحص الكود)
```powershell
flutter analyze
```

### Format Code (تنسيق الكود)
```powershell
dart format lib/
dart format test/
```

---

## 📂 ملاحة المشروع

### الملفات المهمة
```
itqan_erp/
├── lib/main.dart                  ← نقطة الدخول
├── lib/core/router/app_router.dart ← المسارات
├── lib/core/network/api_client.dart ← الاتصال بـ API
├── lib/core/theme/app_theme.dart  ← النمط والألوان
├── pubspec.yaml                   ← التبعيات (Flutter)
├── backend/KineticEnterprise.Api/Program.cs ← Backend
├── windows/runner/main.cpp        ← Windows Desktop
└── web/index.html                 ← صفحة الويب
```

### فتح الملفات المهمة
```powershell
# فتح في VSCode
code .

# فتح الملف الرئيسي
code lib\main.dart

# فتح الإعدادات
code pubspec.yaml
```

---

## 🔍 استكشاف الأخطاء

### عرض السجلات (Logs)
```powershell
# في نفس نافذة flutter run
# اضغط 'L' لعرض السجلات

# أو اعرض السجلات في الوقت الفعلي
flutter logs
```

### تصحيح الأخطاء (Debug)
```powershell
# شغّل مع إمكانية التصحيح
flutter run --debug

# في VSCode: F5 أو Debug → Start Debugging
```

### حل مشاكل البناء
```powershell
# تنظيف ملفات البناء
flutter clean
flutter pub get
flutter build windows --release

# أو للويب:
flutter clean
flutter pub get
flutter build web --release
```

---

## 📊 معلومات النسخة

### إصدار Flutter والـ SDK
```powershell
flutter --version
flutter doctor
```

### معلومات المشروع
```powershell
cat pubspec.yaml | grep "version:"
cd backend
dotnet --version
```

---

## 🔄 Git وإدارة الكود

### مشاهدة حالة المستودع
```bash
git status
git log --oneline -10
```

### إنشاء فرع جديد
```bash
git checkout -b feature/your-feature-name
```

### دفع التغييرات
```bash
git add .
git commit -m "your message"
git push
```

---

## 🌐 النشر والبيئات

### قائمة البيئات
```
المحلية (Local):      http://localhost:5001
التطوير (Dev):       https://dev-api.itqan.com
الاختبار (Staging):  https://staging-api.itqan.com
الإنتاج (Prod):      https://api.itqan.com
```

### تغيير البيئة في البناء
```powershell
# بيئة Staging
flutter build web --dart-define=API_BASE_URL=https://staging-api.itqan.com/api

# بيئة الإنتاج
flutter build web --dart-define=API_BASE_URL=https://api.itqan.com/api
```

---

## 📈 مراقبة الأداء

### قياس سرعة الحزم
```powershell
flutter build apk --analyze-size
flutter build web --dart-define=API_BASE_URL=... --analyze-size
```

### فحص الأداء
```powershell
flutter run --profile
# ثم استخدم Performance Monitor في DevTools
```

---

## ✅ قائمة فحص سريعة

قبل دفع الكود:
```bash
[ ] flutter analyze        # بدون تحذيرات
[ ] flutter test          # جميع الاختبارات تنجح
[ ] dart format lib/      # الكود منسق
[ ] git diff              # لا توجد ملفات حساسة
[ ] flutter build web     # يبني بدون أخطاء
```

---

## 💡 نصائح سريعة

1. **لا تحفظ كلمات المرور:** استخدم آمن (مثل Secure Storage)
2. **استخدم المتغيرات:** بدل الأرقام والنصوص الثابتة
3. **اختبر دائماً:** قبل دفع الكود
4. **وثّق الكود:** خاصة الأجزاء المعقدة
5. **اسأل قبل الحذف:** قد يكون هناك سبب للكود

---

## 🆘 الدعم والمراجع

```
📧 البريد: alfawares085@gmail.com
📚 الملفات الإرشادية:
   - ITQAN_DESKTOP_SETUP.md
   - BUILD_COMPLETION_REPORT.md
   - BACKEND_SETUP_QUICK_START.md
   - NEXT_STEPS.md

🔗 الموارد:
   - https://flutter.dev/docs
   - https://docs.microsoft.com/aspnet
   - https://dart.dev/guides
```

---

**حفظ هذا الملف كمرجع دائم! 📌**
