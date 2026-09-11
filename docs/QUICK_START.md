# البدء السريع 🚀

## إصدار نسخة جديدة

### الخطوة 1: إنشاء Tag

```bash
git tag v1.7.3
git push origin v1.7.3

# ✅ GitHub Actions يبني تلقائياً ويرفع الـ artifacts
# (انتظر 5-10 دقائق)
```

### الخطوة 2: النشر على Staging

```
GitHub → Actions → "Deploy - Auto to Staging/Production"
  ↓ Run workflow
  ↓ Tag: v1.7.3
  ↓ Target: staging
  ↓ Run

✅ سيتم نشر النسخة على https://staging.itqan.local
```

### الخطوة 3: الاختبار

```bash
# اختبر على Staging
curl https://staging.itqan.local/health

# أو من المتصفح
https://staging.itqan.local
```

### الخطوة 4: النشر على Production

```
GitHub → Actions → "Deploy - Auto to Staging/Production"
  ↓ Run workflow
  ↓ Tag: v1.7.3
  ↓ Target: production
  ↓ Run

✅ سيتم نشر النسخة على https://erp.itqan.local
```

## البناء اليدوي

### بناء Web فقط:

```bash
flutter build web --release
```

### بناء Android:

```bash
# APK
flutter build apk --release

# App Bundle
flutter build appbundle --release
```

### بناء الكل:

```bash
flutter build web --release && \
flutter build apk --release && \
flutter build appbundle --release
```

## النشر اليدوي

### تحضير الـ Artifacts:

```bash
mkdir -p artifacts
cd build/web && zip -r ../../artifacts/kinetic-web.zip . && cd ../..
cp build/app/outputs/flutter-app.apk artifacts/
cp build/app/outputs/bundle/release/app-release.aab artifacts/
```

### النشر على Staging:

```bash
./scripts/deploy-staging.sh artifacts/
```

### النشر على Production:

```bash
./scripts/deploy-production.sh artifacts/
```

## استكشاف المشاكل

### النشر فشل؟

```bash
# 1. تحقق من السجلات
tail -f /var/log/itqan/deployment_*.log

# 2. تحقق من الخدمات
systemctl status itqan-staging

# 3. عد إلى النسخة السابقة
ln -sf /opt/itqan/backups/staging/latest /opt/itqan/staging/current
systemctl restart itqan-staging
```

### الاتصال لا يعمل؟

```bash
# تحقق من firewall
sudo ufw status

# تحقق من الخدمة
curl https://staging.itqan.local/health -v
```

## الأوامر المفيدة

```bash
# عرض آخر 5 إصدارات
git tag -l | sort -V | tail -5

# عرض الإصدار الحالي
cat /opt/itqan/staging/current/DEPLOYMENT_INFO

# إعادة تشغيل الخدمة
systemctl restart itqan-staging

# عرض السجلات الحية
journalctl -u itqan-staging -f
```

## المراجع

- [دليل النشر الكامل](./DEPLOYMENT.md)
- [إعداد البيئات](./ENVIRONMENTS_SETUP.md)
- [استكشاف الأخطاء](./TROUBLESHOOTING.md)
