# 🚀 نشر على بيئة التجريب - دليل سريع

**الإصدار:** v2.0.1  
**التاريخ:** 2026-09-13  
**الحالة:** ✅ جاهز للنشر

---

## 🎯 البيئة المستهدفة

```
┌─────────────────────────────────────────────────┐
│ بيئة التجريب (Staging)                         │
├─────────────────────────────────────────────────┤
│ URL:        staging-erp.droob-albayan.ly:8080  │
│ الخادم:     65.21.213.78                      │
│ الموقع IIS: KineticStaging                    │
│ المجلد:     C:\kinetic\staging-erp            │
└─────────────────────────────────────────────────┘
```

---

## 📋 خطوات النشر

### **الطريقة 1: استخدام PowerShell Script (الموصى به)**

#### 1️⃣ فتح PowerShell كـ Administrator

```powershell
# من مجلد المشروع
cd "C:\Users\F\Downloads\kinetic_erp"

# تشغيل السكريبت
.\deploy_staging.ps1
```

#### 2️⃣ السكريبت سيفعل تلقائياً:
- ✅ التحقق من مجلد التجريب
- ✅ تحميل kinetic-web.zip من GitHub
- ✅ عمل backup للملفات القديمة
- ✅ نشر البناء الجديد
- ✅ التحقق من النشر
- ✅ إعادة تشغيل IIS

#### 3️⃣ الانتظار 2-3 دقائق

```
════════════════════════════════════════════════════════
✅ DEPLOYMENT COMPLETE!
════════════════════════════════════════════════════════

📍 Staging URL: http://staging-erp.droob-albayan.ly:8080/
📍 Local Path: C:\kinetic\staging-erp
💾 Backup: C:\kinetic\staging-erp.backup.20260913-143022
```

---

### **الطريقة 2: يدويّة (إذا فشل السكريبت)**

#### 1️⃣ تحميل kinetic-web.zip يدويّاً
- اذهب إلى: https://github.com/AdilAli76/Itqan/actions
- اختر آخر run نجح
- حمّل artifact `build-artifacts`
- استخرج `kinetic-web.zip` منها

#### 2️⃣ نسخ الملفات
```powershell
# 1. Backup القديم
Copy-Item "C:\kinetic\staging-erp\*" "C:\kinetic\staging-erp.backup" -Recurse -Force

# 2. حذف القديم
Remove-Item "C:\kinetic\staging-erp\*" -Recurse -Force

# 3. استخراج الجديد
Expand-Archive -Path "C:\path\to\kinetic-web.zip" -DestinationPath "C:\kinetic\staging-erp" -Force

# 4. إعادة تشغيل IIS
Restart-WebAppPool -Name "KineticStaging"
```

---

## ✅ التحقق من النشر

### 1️⃣ فتح الموقع في المتصفح
```
http://staging-erp.droob-albayan.ly:8080/
```

### 2️⃣ اختبارات سريعة
- [ ] الصفحة تحمّل بدون أخطاء
- [ ] الشعار والألوان صحيحة
- [ ] القوائم تفتح بسلاسة
- [ ] الاتصال بـ API يعمل
- [ ] المصادقة (Login) تعمل

### 3️⃣ فحص الـ Console للأخطاء
- افتح Developer Tools (F12)
- اذهب إلى Tab "Console"
- تأكد من عدم وجود أخطاء حمراء

---

## 🔙 استرجاع النسخة السابقة

إذا حدثت مشكلة:

```powershell
# 1. حذف النسخة الحالية
Remove-Item "C:\kinetic\staging-erp\*" -Recurse -Force

# 2. استرجاع من Backup
Copy-Item "C:\kinetic\staging-erp.backup\*" "C:\kinetic\staging-erp" -Recurse -Force

# 3. إعادة تشغيل
Restart-WebAppPool -Name "KineticStaging"
```

---

## 📊 ملخص البناء

```
════════════════════════════════════════════════════════
Kinetic ERP v2.0.1 - Build Summary
════════════════════════════════════════════════════════

Commit:           b7d65ee (docs: add build status)
Build Time:       ~70 seconds
Output Size:      6.2 MB (compressed)
Web Build:        ✅ SUCCESS
Android Builds:   ⚠️ Optional (skipped)
Tests:            360 passed, 99 screenshot-only failed

════════════════════════════════════════════════════════
```

---

## 🔗 الروابط المهمة

- **GitHub Releases:** https://github.com/AdilAli76/Itqan/releases
- **GitHub Actions:** https://github.com/AdilAli76/Itqan/actions
- **Staging URL:** http://staging-erp.droob-albayan.ly:8080/
- **Production URL:** http://erp.droob-albayan.ly/ (بعد التأكد من التجريب)

---

## ⚠️ ملاحظات مهمة

1. **HTTPS:** بيئة التجريب تعمل على HTTP فقط (المنفذ 8080)
2. **DNS:** السجلات تشير إلى IP 65.21.213.78
3. **IIS:** الموقع باسم `KineticStaging` على المنفذ 8080
4. **API:** التطبيق يستنتج عنوان API من أصل الصفحة (Origin)
5. **Secrets:** لا توجد مفاتيح أو كلمات مرور في البناء

---

## 🎯 الخطوة التالية

بعد التحقق من بيئة التجريب بنجاح:

```
1️⃣ اختبر جميع الميزات على التجريب
2️⃣ أخبر فريق الدعم بالنشر الجديد
3️⃣ اجمع الملاحظات والمشاكل (إن وجدت)
4️⃣ انتظر الموافقة لنشر الإنتاج
5️⃣ استخدم deploy_production.ps1 لنشر الإنتاج
```

---

**تاريخ الإعداد:** 2026-09-13  
**آخر تحديث:** 2026-09-13  
**الحالة:** ✅ جاهز للنشر
