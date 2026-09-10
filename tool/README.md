&#65279;# Kinetic ERP - PowerShell Scripts Package
# ملفات النشر والنسخ الاحتياطية والعدّاء

## 📦 محتويات الحزمة:

### 1. tool/deploy_update.ps1
- فكّ حزمة النشر
- نسخ الملفات (backend, sql, tool)
- تنفيذ ترحيلات قاعدة البيانات
- إعادة تشغيل الموقع والمجموعة
- تسجيل البصمة في deploy.log

### 2. tool/backup.ps1
- نسخة احتياطية من قاعدة البيانات
- نسخة احتياطية من مجلد المرفقات
- احتفظ بآخر 7 نسخ ويحذف الأقدم

### 3. tool/runner_setup.ps1
- إعداد عدّاء GitHub Actions
- إنشاء حساب الخدمة
- تثبيت وتشغيل العدّاء
- (اختياري - للعدّاء المستضاف ذاتياً)

---

## 🚀 طريقة الاستخدام:

### على الخادم:

1. فكّ الملف الـ ZIP بحيث ينتهي بك في:
   ```
   C:\kinetic-staging\tool\*.ps1
   C:\kinetic\tool\*.ps1
   ```

2. تحقق من الملفات:
   ```powershell
   Get-ChildItem C:\kinetic-staging\tool\*.ps1
   Get-ChildItem C:\kinetic\tool\*.ps1
   ```

3. لـ الاختبار:
   ```powershell
   # اختبر deploy_update
   C:\kinetic-staging\tool\deploy_update.ps1 -Package "path\to\package.zip" -Target "C:\kinetic-staging" -SiteName "KineticStaging" -PoolName "KineticStagingPool"
   ```

---

**تم إنشاء الحزمة بنجاح! تحميل الملفات جاهز.**
