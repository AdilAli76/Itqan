# نشر Itqan ERP 🚀

دليل شامل لنشر تطبيق Itqan على بيئات التجريب والإنتاج.

## سير العمل

```
Code → Tests → Build → Release → Staging → Production
```

## الأتمتة

### 1️⃣ البناء التلقائي
- عند كل push إلى main/develop
- يبني Web + Android (APK + AAB)
- يرفع الـ artifacts

### 2️⃣ نشر الإصدارات
- عند إنشاء tag (v1.7.3)
- ينشئ GitHub Release تلقائياً
- يرفع جميع الـ artifacts

### 3️⃣ نشر على Staging
```bash
# من GitHub Actions UI
Run workflow: Deploy - Auto to Staging/Production
- Tag: v1.7.3
- Target: staging
```

### 4️⃣ نشر على Production
```bash
# نفس الخطوات لكن مع Production
```

## النشر اليدوي

### على Staging:
```bash
./scripts/deploy-staging.sh ./artifacts false
```

### على Production:
```bash
./scripts/deploy-production.sh ./artifacts false false
```

## الملفات المهمة

- `.github/workflows/ci-build.yml` - بناء تلقائي
- `.github/workflows/release-publish.yml` - نشر الإصدارات
- `.github/workflows/deploy-auto.yml` - نشر على البيئات
- `scripts/deploy-staging.sh` - نشر على التجريب
- `scripts/deploy-production.sh` - نشر على الإنتاج

## قائمة التحقق

- [ ] Tests passed
- [ ] Build successful
- [ ] Release created
- [ ] Staging deployment successful
- [ ] Production deployment ready
