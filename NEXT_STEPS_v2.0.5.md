# خطوات تطوير v2.0.5 - المرحلة التالية

## 🎯 الحالة الحالية
✅ **Backend مكتمل 100%**
- 9 Entities جديدة
- 9 جداول قاعدة بيانات
- 3 Controllers مع 20+ Endpoints
- Migration جاهز للتطبيق

---

## 🚀 الخطوات الفورية (اليوم)

### 1️⃣ تطبيق Migration على قاعدة البيانات
```powershell
# على السيرفر أو محليّاً
cd "C:\Users\F\Downloads\itqan_erp\backend\KineticEnterprise.Api"

# تأكد من أن dotnet-ef مثبت
dotnet tool list --global | findstr dotnet-ef

# إذا لم يكن مثبتاً
dotnet tool install --global dotnet-ef

# طبّق الترحيل
dotnet ef database update `
  --connection "Server=.;Database=ItqanEnterprise;Trusted_Connection=true;Encrypt=false;" `
  --verbose
```

**النتيجة المتوقعة:**
```
Build started...
Build succeeded.
Applying migration '20260914195722_v2_0_5_SalariesLoansFlexiblePurchases'
Done. To undo this action, use Update-Database -Migration <PreviousMigration>.
```

### 2️⃣ بناء Release
```powershell
cd "C:\Users\F\Downloads\itqan_erp\backend\KineticEnterprise.Api"

# بناء Release
dotnet publish -c Release -o "..\publish"

# التحقق من النجاح
ls "..\publish\*.dll" | Select-Object Name
```

### 3️⃣ اختبار API Endpoints الجديدة (اختياري)
```powershell
# تشغيل التطبيق
cd "..\publish"
dotnet KineticEnterprise.Api.dll

# في terminal آخر - اختبر الـ endpoints
Invoke-WebRequest -Uri "http://localhost:5000/swagger" -Method GET
```

---

## 📱 المرحلة 2️⃣: تطوير الواجهات (Flutter)

### التقسيم الزمني المقترح
- **اليوم 1-2:** شاشات Web
- **اليوم 3:** اختبار وتصحيح
- **اليوم 4-5:** شاشات Android

### الشاشات المطلوبة

#### 1. **SalaryManagementScreen**
```dart
📋 العناصر:
  - قائمة المرتبات الشهرية
  - إضافة مرتب جديد
  - تعديل/حذف المرتب
  - تسجيل الدفعات
  - عرض حالة الدفع (pending/paid/partial)

🔗 Endpoints المستخدمة:
  - GET /api/salaries/customer-account/{id}
  - POST /api/salaries
  - POST /api/salaries/{id}/pay
  - DELETE /api/salaries/{id}
```

#### 2. **CustomerLoansScreen**
```dart
📋 العناصر:
  - قائمة السلف النشطة
  - إنشاء قرض جديد
  - تسجيل دفعات
  - ملخص السلف (إجمالي، متبقي، متأخر)
  - سجل الدفعات

🔗 Endpoints المستخدمة:
  - GET /api/customer-loans/customer-account/{id}
  - POST /api/customer-loans
  - POST /api/customer-loans/{id}/payment
  - GET /api/customer-loans/summary/{id}
```

#### 3. **PurchaseTypeSelectionScreen**
```dart
📋 العناصر:
  - اختيار نوع الشراء (تقليدي/مباشر)
  - عرض وصف كل نوع
  - تأثير النوع على العملية
  - حفظ التفضيل

🔗 Endpoints المستخدمة:
  - GET /api/purchase-types
```

#### 4. **DirectDeliveryDashboard**
```dart
📋 العناصر:
  - قائمة التسليمات المباشرة
  - تتبع حالة التسليم (pending/delivered/received)
  - المورد والعميل والمبلغ
  - تحديث الحالة

🔗 Endpoints المستخدمة:
  - GET /api/purchase-types/direct-deliveries
  - PATCH /api/purchase-types/direct-deliveries/{id}/status
```

#### 5. **CustomerAccountsScreen**
```dart
📋 العناصر:
  - قائمة حسابات العملاء
  - معلومات الحساب البنكي
  - الرصيد الحالي
  - سقف الائتمان
  - ربط مع المرتبات والسلف

🔗 تحتاج نقطة نهاية جديدة:
  - GET /api/customer-accounts
  - GET /api/customer-accounts/{id}
```

---

## 🔧 المهام الإضافية المطلوبة

### 1. Controllers إضافية مطلوبة
```csharp
// CustomerAccountsController
GET    /api/customer-accounts
GET    /api/customer-accounts/{id}
POST   /api/customer-accounts
PUT    /api/customer-accounts/{id}
DELETE /api/customer-accounts/{id}

// SettingsController (للإعدادات المتقدمة)
GET    /api/settings/purchase-workflows
POST   /api/settings/purchase-workflows
PATCH  /api/settings/purchase-workflows/{key}
```

### 2. Services مساعدة
```csharp
// SalaryService - حساب الرواتب والبدلات
// LoanService - إدارة السلف والأقساط
// PurchaseService - التحكم في مسارات الشراء
```

### 3. Validations إضافية
```csharp
// التحقق من سقف الائتمان عند إنشاء سلف
// التحقق من عدم تكرار المرتب في نفس الشهر
// التحقق من تواريخ التسليم
```

---

## 📊 تقدير الوقت المتبقي

| المهمة | الوقت | الأولوية |
|-------|-------|---------|
| تطبيق Migration | 15 دقيقة | 🔴 عالي جداً |
| بناء Release | 10 دقائق | 🔴 عالي جداً |
| Controllers إضافية | 2-3 ساعات | 🟡 متوسط |
| Validations | 1 ساعة | 🟡 متوسط |
| شاشات Flutter Web | 8-10 ساعات | 🟡 متوسط |
| اختبار Web | 2-3 ساعات | 🟡 متوسط |
| بناء Android | 4-6 ساعات | 🟢 منخفض |
| اختبار Android | 2-3 ساعات | 🟢 منخفض |
| **المجموع** | **~22-27 ساعة** | |

---

## ✅ Checklist للإكمال

- [ ] تطبيق Migration
- [ ] بناء Release
- [ ] اختبار API endpoints
- [ ] إنشاء CustomerAccountsController
- [ ] إنشاء SettingsController
- [ ] إضافة Validations
- [ ] بناء SalaryManagementScreen
- [ ] بناء CustomerLoansScreen
- [ ] بناء PurchaseTypeSelectionScreen
- [ ] بناء DirectDeliveryDashboard
- [ ] اختبار كامل الواجهات
- [ ] بناء APK للـ Android
- [ ] الاختبار النهائي
- [ ] إنشاء tag v2.0.5

---

## 🎯 الأولويات العاجلة

**يجب إنجازها أولاً:**
1. ✅ تطبيق Migration (15 دقيقة)
2. ✅ بناء Release (10 دقائق)
3. ⏳ Controllers إضافية (اليوم)
4. ⏳ شاشات Flutter الأساسية (غداً)

---

## 📞 النقاط المهمة

- **Database:** تأكد من اتصال SQL Server قبل تطبيق Migration
- **API Testing:** استخدم Postman/Swagger للاختبار
- **Flutter Build:** قد تحتاج `flutter clean && flutter pub get` قبل البناء
- **Android:** تأكد من تثبيت Android SDK

---

**الحالة الحالية:** Backend Complete ✅  
**التاريخ:** 2026-09-14  
**الإصدار:** v2.0.5-beta
