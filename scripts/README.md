# Scripts - نصوص النشر 📜

## المحتويات

- `deploy-staging.sh` - نشر على Staging
- `deploy-production.sh` - نشر على Production

## الاستخدام

### deploy-staging.sh

```bash
./deploy-staging.sh <artifacts_dir> [skip_db]
```

**المثال:**

```bash
./deploy-staging.sh ./artifacts false
```

**المعاملات:**
- `<artifacts_dir>` - مجلد يحتوي على: kinetic-web.zip, kinetic-app.apk, kinetic-app.aab
- `[skip_db]` - اختياري: true/false (افتراضي: false)

**ما يفعله:**
1. ✓ ينشئ backup للنسخة الحالية
2. ✓ يفك ضغط الـ web artifacts
3. ✓ ينسخ ملفات APK و AAB
4. ✓ يحدّث symbolic link للنسخة الحالية
5. ✓ يشغّل database migrations (إذا لم يتم تجاوزه)
6. ✓ يعيد تشغيل الخدمات
7. ✓ يفحص صحة النشر

### deploy-production.sh

```bash
./deploy-production.sh <artifacts_dir> [skip_db] [mandatory_update]
```

**المثال:**

```bash
./deploy-production.sh ./artifacts false false
```

**المعاملات:**
- `<artifacts_dir>` - مجلد الـ artifacts
- `[skip_db]` - تجاوز database migrations (افتراضي: false)
- `[mandatory_update]` - تحديث إلزامي للتطبيقات (افتراضي: false)

**الفرقات عن Staging:**
- يحتاج إلى فحص إضافي
- يحتفظ بـ 5 backups سابقة
- يكتب تقرير تفصيلي للسجلات
- يتحقق من المساحة الحرة
- rollback تلقائي عند الفشل

## هيكل الـ Artifacts

```
artifacts/
├── kinetic-web.zip           # تطبيق الويب
├── kinetic-app.apk          # تطبيق Android (APK)
└── kinetic-app.aab          # تطبيق Android (App Bundle)
```

## الملفات والمجلدات

### على Staging:

```
/opt/itqan/staging/
├── 20240911_100000/         # نسخة قديمة
│   ├── web/                 # ملفات الويب
│   ├── kinetic-app.apk
│   ├── kinetic-app.aab
│   └── DEPLOYMENT_INFO
├── current → 20240911_100000 # الرابط إلى النسخة النشطة
```

### Backups:

```
/opt/itqan/backups/staging/
├── backup_20240911_100000/
├── backup_20240911_120000/
└── latest → backup_20240911_120000
```

## السجلات

```bash
# Staging deployment log
/var/log/itqan/deployment_YYYYMMDD_HHMMSS.log

# Example:
tail -f /var/log/itqan/deployment_*.log
```

## المتطلبات

- `unzip` - لفك ضغط الملفات
- `bash` 4.0+
- `mkdir`, `ln`, `cp` - أدوات أساسية
- صلاحيات كتابة على `/opt/itqan/`

## الخطأ: Permission Denied

```bash
# تأكد من أن الـ scripts قابل للتنفيذ
chmod +x deploy-*.sh

# تأكد من صلاحيات المجلد
chmod 755 /opt/itqan/staging
chmod 755 /opt/itqan/production
```

## الخطأ: Artifacts not found

```bash
# تأكد من وجود الملفات
ls -la artifacts/

# تأكد من المسار
./deploy-staging.sh $(pwd)/artifacts
```

## Rollback اليدوي

```bash
# عرض النسخ السابقة
ls -la /opt/itqan/backups/staging/

# الرجوع إلى نسخة سابقة
ln -sf /opt/itqan/backups/staging/backup_YYYYMMDD_HHMMSS \
       /opt/itqan/staging/current

# إعادة تشغيل الخدمة
systemctl restart itqan-staging
```

## Tips

- استخدم `&&` لربط الـ scripts: `build.sh && deploy-staging.sh artifacts`
- احفظ النسخ القديمة: backups تُحذف تلقائياً (آخر 5 فقط)
- قلّل الـ downtime: استخدم zero-downtime deployment إذا أمكن
- تحقق من السجلات بعد كل نشر

## المراجع

- [دليل النشر الكامل](../docs/DEPLOYMENT.md)
- [البدء السريع](../docs/QUICK_START.md)
