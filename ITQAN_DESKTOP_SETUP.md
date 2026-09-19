# منظومة إتقان ERP — دليل النسخة الديسكتوب (2026-09-15)

## 🎯 ملخص البناء الناجح

| المكون | الحالة | التفاصيل |
|--------|--------|----------|
| **Flutter Web** | ✅ جاهز | `build/web/` — قابل للنشر على أي خادم ويب |
| **Windows Desktop** | ✅ جاهز | `build/windows/x64/runner/Release/kinetic_enterprise.exe` |
| **Backend (.NET)** | ⏳ مطلوب | `backend/KineticEnterprise.Api/` — يحتاج تشغيل منفصل |
| **قاعدة البيانات** | ⏳ مطلوب | SQL Server — تشغيل المخطط من `docs/DATABASE_SCHEMA_SQLSERVER.sql` |

---

## 🚀 كيفية تشغيل النسخة الديسكتوب

### الخطوة 1: تشغيل Backend (.NET)
```powershell
cd backend\KineticEnterprise.Api
dotnet run
```
يشتغل افتراضياً على: **https://localhost:5001**

> ⚠️ **تنبيه**: قبل تشغيل Backend:
> 1. تأكد من تثبيت SQL Server (2019+)
> 2. نفّذ `docs/DATABASE_SCHEMA_SQLSERVER.sql` على السيرفر
> 3. عدّل `appsettings.json` بسلسلة اتصال الـ Database الفعلية

### الخطوة 2: تشغيل التطبيق الديسكتوب
```powershell
# من مجلد المشروع الرئيسي
cd C:\Users\F\Downloads\itqan_erp

# تشغيل مباشر
.\build\windows\x64\runner\Release\kinetic_enterprise.exe

# أو تشغيل مع وضع التطوير (Debug)
flutter run -d windows
```

---

## 🌐 خيارات التشغيل

### 1️⃣ **خادم محلي + Desktop (التطوير)**
```powershell
# Terminal 1: Backend
cd itqan_erp\backend\KineticEnterprise.Api
dotnet run

# Terminal 2: Desktop App
cd itqan_erp
.\build\windows\x64\runner\Release\kinetic_enterprise.exe
```

### 2️⃣ **Web (في المتصفح)**
```powershell
cd itqan_erp
flutter run -d chrome
# أو فتح build/web/index.html مباشرة في المتصفح
```

### 3️⃣ **Android**
```powershell
cd itqan_erp
flutter build apk --release --dart-define=API_BASE_URL=https://your-server.com/api
```

---

## ⚙️ التكوينات المهمة

### تغيير عنوان الـ API
إذا كان الـ Backend على خادم مختلف:

#### للويب/الديسكتوب:
```bash
flutter run -d chrome --dart-define=API_BASE_URL=https://your-server.com/api
flutter run -d windows --dart-define=API_BASE_URL=https://your-server.com/api
```

#### للـ APK (Android):
```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-server.com/api
```

### الملف البرمجي الذي يتحكم بـ العنوان:
📄 `lib/core/network/api_client.dart`

---

## 📂 بنية المشروع

```
itqan_erp/
├── lib/
│   ├── core/
│   │   ├── constants/      (ثوابت التطبيق)
│   │   ├── network/        (ApiClient للاتصال بـ Backend)
│   │   ├── router/         (المسارات والملاحة)
│   │   ├── theme/          (النمط والألوان الديناميكية)
│   │   └── ...
│   ├── features/           (الشاشات: Auth, Dashboard, POS, Inventory, Branches)
│   ├── shared/             (العناصر المشتركة: Widgets, Helpers)
│   └── main.dart           (نقطة الدخول)
│
├── backend/
│   └── KineticEnterprise.Api/  (ASP.NET Core Backend)
│       ├── Controllers/         (API Endpoints)
│       ├── Models/              (Data Models)
│       ├── Services/            (Business Logic)
│       ├── appsettings.json    (تكوين قاعدة البيانات و JWT)
│       └── Program.cs
│
├── windows/                (كود Windows Desktop)
├── web/                    (تهيئة الويب)
├── build/
│   ├── web/               (نسخة الويب المبنية)
│   └── windows/x64/runner/Release/  (نسخة Windows المبنية)
│
└── docs/
    └── DATABASE_SCHEMA_SQLSERVER.sql  (مخطط قاعدة البيانات)
```

---

## 📋 المتطلبات

### لتشغيل الديسكتوب:
- ✅ Windows 7+ (تم الاختبار على Windows 10)
- ✅ .NET Runtime 8.0+ (مضمّن مع البناء)
- ✅ SQL Server 2019 Express+ (إذا كنت تشغّل Backend محليا)

### للتطوير:
- ✅ Flutter 3.47.4+
- ✅ Dart 3.13.3+
- ✅ .NET 8.0 SDK+
- ✅ Visual Studio Code / Visual Studio / Android Studio

---

## 🎨 الشاشات المبنية

| الشاشة | الحالة | الملف |
|--------|--------|------|
| تسجيل الدخول (Login) | ✅ كامل | `lib/features/auth/` |
| لوحة التحكم (Dashboard) | ✅ كامل | `lib/features/dashboard/` |
| نقطة البيع (POS) | ✅ كامل | `lib/features/pos/` |
| إدارة المخزون (Inventory) | ✅ كامل | `lib/features/inventory/` |
| إدارة الفروع (Branches) | ✅ كامل | `lib/features/branches/` |
| المالية (Accounting) | ⏳ قيد الإنشاء | — |
| التقارير (Reports) | ⏳ قيد الإنشاء | — |
| الإعدادات (Settings) | ⏳ قيد الإنشاء | — |

---

## 🔌 الاتصال بـ Backend

### في الديسكتوب:
1. يبدأ التطبيق بـ `ApiClient.loadSavedServer()`
2. يصل للـ Backend على `https://localhost:5001/api`
3. إذا فشل الاتصال، يعرض شاشة تحرير العنوان
4. بعد الحفظ، يُعاد المحاولة تلقائياً

### طلب API مثال:
```dart
// POST /api/auth/login
final response = await apiClient.post(
  '/auth/login',
  data: {'email': 'user@example.com', 'password': 'pass'},
);
```

---

## 🖥️ الملف المبني (صيغ قابلة للتوزيع)

### Windows Desktop Standalone:
```
kinetic_enterprise.exe + ملفات DLL المساندة
= حزمة كاملة قابلة للتشغيل على أي Windows PC
```

### التشغيل بدون Flutter:
```powershell
# لا حاجة لـ Flutter SDK على الجهاز المستخدم
# فقط تشغيل الـ EXE مباشرة
cd "C:\Program Files\KineticEnterprise"
.\kinetic_enterprise.exe
```

---

## 🐛 استكشاف الأخطاء

### الخطأ: "Cannot connect to API"
**الحل:**
1. تأكد من تشغيل Backend: `dotnet run`
2. تأكد من أن القاعدة موجودة على SQL Server
3. غيّر عنوان API من شاشة الإعدادات

### الخطأ: "Database connection failed"
**الحل:**
1. تحقق من اتصال SQL Server
2. تأكد من تنفيذ `DATABASE_SCHEMA_SQLSERVER.sql`
3. تحقق من `appsettings.json` في Backend

### الخطأ: "HTTPS certificate error"
**الحل:**
```powershell
# للتطوير فقط (غير آمن):
dotnet dev-certs https --clean
dotnet dev-certs https --trust
```

---

## 📦 النشر والتوزيع

### 1. حزمة Windows Installer
```powershell
# بناء installer MSIX (Windows 10+)
flutter build windows --release

# أو استخدم Inno Setup/WiX Toolset لـ MSI
```

### 2. نسخة Portable
```powershell
# انسخ مجلد build\windows\x64\runner\Release بالكامل
xcopy "build\windows\x64\runner\Release" "C:\Portable\KineticERP" /E /I
```

### 3. نسخة الويب على خادم
```bash
# انسخ build/web/ إلى خادم ويب
xcopy build\web C:\inetpub\wwwroot\erp /E /I
```

---

## 🔒 الأمان

- ✅ **HTTPS فقط** في نسخة Release
- ✅ **JWT Authentication** من Backend
- ✅ **Row-Level Security** في SQL Server
- ✅ **CORS محدود** (مفتاح محاول كـ CorsPolicy)

---

## 📞 دعم إضافي

### ملفات توثيق إضافية:
- `DEPLOYMENT.md` — نشر على الإنتاج
- `docs/ARCHITECTURE.md` — البنية الكاملة
- `docs/DATABASE_SCHEMA_SQLSERVER.sql` — مخطط قاعدة البيانات
- `README.md` — نظرة عامة

### الاتصال بـ الدعم:
📧 alfawares085@gmail.com

---

## 📅 سجل البناء

| التاريخ | الإصدار | ملاحظات |
|--------|---------|---------|
| 2026-09-15 | 1.0.0 | نسخة Windows Desktop الأولى |

---

**تم البناء بنجاح ✅ — النسخة جاهزة للاستخدام المحلي والإنتاج**
