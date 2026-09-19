# 📋 دليل النشر الشامل - Itqan ERP

**النسخة:** 1.0.0  
**التاريخ:** 2026-09-15  
**الدومين:** https://erp.droob-albayan.ly/app

---

## 🎯 نظرة عامة

هذا الدليل يشرح كيفية نشر Itqan ERP على Windows Server وتشغيله عبر IIS.

### المسار الكامل للنشر:

1. التحضير
2. النشر (Extract ZIP)
3. التشغيل (Start IIS)
4. الاختبار
5. الصيانة

---

## 🚀 خطوات النشر السريعة

### الخطوة 1: انسخ الملفات إلى C:\temp

```
C:\temp\ItqanERP-Web-v1.0.0.zip  (ملف الويب)
C:\temp\deploy.bat                (سكريبت النشر)
C:\temp\start-iis.bat             (تشغيل IIS)
C:\temp\test-website.bat          (اختبار)
```

### الخطوة 2: نشر الملفات

```bash
# افتح Command Prompt كمسؤول
# وشغّل:
C:\temp\deploy.bat
```

### الخطوة 3: تشغيل IIS

```bash
# بعد انتهاء النشر، شغّل:
C:\temp\start-iis.bat
```

### الخطوة 4: اختبار الموقع

```bash
# تحقق من أن كل شيء يعمل:
C:\temp\test-website.bat
```

---

## 🌐 الروابط بعد النشر

- **محلي:** http://localhost
- **الإنتاج:** https://erp.droob-albayan.ly/app

---

## 🔧 حل المشاكل

| المشكلة | الحل |
|--------|------|
| فشل فك الضغط | تحقق: `dir C:\temp\ItqanERP-Web-v1.0.0.zip` |
| IIS لا يعمل | أعد التشغيل: `iisreset /restart` |
| خطأ في الصلاحيات | `icacls C:\kinetic /grant Everyone:F /T /Q` |
| الموقع غير متاح | تحقق: `iisreset /status` |

---

**الحالة:** ✅ جاهز للاستخدام
