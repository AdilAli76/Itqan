# قائمة التحقق - إعداد الخوادم ✅

## Staging Server

### المتطلبات الأساسية
- [ ] خادم Ubuntu 20.04 LTS
- [ ] تسجيل دخول SSH بـ root أو sudo
- [ ] اتصال إنترنت مستقر
- [ ] IP ثابت للخادم

### الخطوة 1: إعداد النظام (15 دقيقة)

```bash
# 1. تحميل الـ scripts
mkdir -p /opt/scripts
cd /opt/scripts
wget https://raw.githubusercontent.com/AdilAli76/Itqan/main/scripts/server-setup.sh
wget https://raw.githubusercontent.com/AdilAli76/Itqan/main/scripts/setup-ssl.sh
wget https://raw.githubusercontent.com/AdilAli76/Itqan/main/scripts/setup-runner.sh
chmod +x *.sh

# 2. تشغيل إعداد النظام
./server-setup.sh staging
```

- [ ] اكتمل بدون أخطاء
- [ ] تم إنشاء مستخدم deploy
- [ ] تم إنشاء مجلدات /opt/itqan/staging
- [ ] Firewall مفعل

### الخطوة 2: إعداد SSL (5 دقائق)

```bash
./setup-ssl.sh staging
```

- [ ] تم إنشاء الشهادة
- [ ] تم إعداد Nginx بـ HTTPS

### الخطوة 3: إعداد GitHub Runner (10 دقائق)

```bash
# احصل على TOKEN من:
# GitHub → Settings → Actions → Runners → New

./setup-runner.sh staging <TOKEN>
```

- [ ] تم تثبيت Runner
- [ ] Runner يظهر في GitHub settings
- [ ] الخدمة تعمل

### الخطوة 4: الاختبار

```bash
./server-health-check.sh staging
```

- [ ] جميع الفحوصات نجحت
- [ ] Nginx يعمل
- [ ] Runner يعمل

---

## Production Server

### المتطلبات الإضافية
- [ ] Ubuntu 20.04 LTS (متطابق مع Staging)
- [ ] تخزين إضافي (50GB+ موصى به)
- [ ] Backup system مجهز
- [ ] Monitoring configured

### الخطوة 1: إعداد النظام

```bash
mkdir -p /opt/scripts
cd /opt/scripts
wget https://raw.githubusercontent.com/AdilAli76/Itqan/main/scripts/server-setup.sh
chmod +x server-setup.sh
./server-setup.sh production
```

- [ ] اكتمل بدون أخطاء

### الخطوة 2: إعداد SSL بـ Let's Encrypt

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot certonly --nginx -d erp.itqan.local

# التجديد التلقائي
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

- [ ] شهادة Let's Encrypt حصلنا عليها
- [ ] التجديد التلقائي مفعل

### الخطوة 3: إعداد GitHub Runner

```bash
./setup-runner.sh production <TOKEN>
```

- [ ] تم تثبيت Runner
- [ ] Runner متصل بـ GitHub

### الخطوة 4: الاختبار

```bash
./server-health-check.sh production
```

- [ ] جميع الفحوصات نجحت

---

## GitHub Configuration

### 1. إنشاء Environments

```
Settings → Environments
  ↓ New environment
  ↓ Name: staging
  ↓ Add secrets
  ↓ STAGING_DEPLOY_KEY

  ↓ New environment
  ↓ Name: production
  ↓ Add secrets
  ↓ PRODUCTION_DEPLOY_KEY
```

- [ ] environment `staging` تم إنشاؤه
- [ ] environment `production` تم إنشاؤه

### 2. إضافة Secrets

```
Settings → Secrets and variables → Actions
  ↓ New repository secret
```

- [ ] `STAGING_DEPLOY_KEY` = (SSH private key)
- [ ] `PRODUCTION_DEPLOY_KEY` = (SSH private key)
- [ ] `GITHUB_TOKEN` = (automatic)

### 3. حماية Branch

```
Settings → Branches
  ↓ Add rule
  ↓ Branch name: main
  ↓ Require status checks
  ↓ Select workflows
```

- [ ] main branch محمي
- [ ] Require CI checks تم تفعيله

---

## الاختبار النهائي

### اختبار CI/CD

```bash
# 1. افعل commit صغير
echo "# Test" >> README.md
git add .
git commit -m "test: CI/CD test"
git push

# 2. تابع الـ workflow
# GitHub → Actions
```

- [ ] Build workflow نجح
- [ ] Tests نجحت

### اختبار النشر على Staging

```
GitHub → Actions → Deploy - Auto
  ↓ Run workflow
  ↓ Tag: v1.7.2 (موجود بالفعل)
  ↓ Target: staging
  ↓ Run
```

- [ ] Artifacts تم تحميلها
- [ ] النشر اكتمل
- [ ] Deployment Status ظهر

### الاتصال والتحقق

```bash
# من جهازك المحلي
curl -k https://staging.itqan.local/health

# يجب أن ترى: OK
```

- [ ] Health endpoint يستجيب
- [ ] الـ web app يعمل

### اختبار Rollback

```bash
# من الخادم
./scripts/deploy-staging.sh artifacts/

# إذا فشل أو أردت الرجوع:
ln -sf /opt/itqan/backups/staging/latest /opt/itqan/staging/current
systemctl restart nginx
```

- [ ] Rollback يعمل
- [ ] النسخة السابقة تعود

---

## المراقبة والصيانة

### يومي
- [ ] افحص السجلات: `tail -f /var/log/itqan/deployment_*.log`
- [ ] تحقق من الصحة: `./server-health-check.sh staging`

### أسبوعي
- [ ] تحقق من الـ backups
- [ ] راجع السجلات للأخطاء
- [ ] اختبر النشر

### شهري
- [ ] اختبر Disaster Recovery
- [ ] حدّث النظام: `sudo apt update && apt upgrade`
- [ ] راجع الأمان

---

## الأوامر المفيدة

```bash
# عرض حالة الخدمات
sudo systemctl status nginx
sudo systemctl status actions.runner.*

# عرض السجلات
sudo journalctl -u actions.runner.* -f
tail -f /var/log/itqan/*.log

# إعادة تشغيل
sudo systemctl restart nginx
sudo systemctl restart actions.runner.AdilAli76-Itqan.staging.service

# التحقق من SSL
curl -v https://localhost/health

# فحص استخدام الموارد
df -h
free -h
top
```

---

## الدعم والمساعدة

إذا حدثت مشاكل:

1. **تحقق من السجلات:**
   ```bash
   sudo journalctl -xe
   tail -f /var/log/nginx/error.log
   tail -f /var/log/itqan/deployment_*.log
   ```

2. **اختبر الاتصال:**
   ```bash
   curl -v http://localhost
   curl -v https://localhost
   ```

3. **تحقق من الخوادم:**
   ```bash
   sudo systemctl status nginx
   sudo systemctl status actions.runner.*
   ```

4. **راجع الأخطاء:**
   ```bash
   sudo nginx -t
   sudo systemctl restart nginx
   ```

---

## الحالة الأخيرة

| البند | Staging | Production |
|------|---------|------------|
| **النظام** | ✅ | ✅ |
| **SSL/TLS** | ✅ | ✅ |
| **Runner** | ✅ | ✅ |
| **Nginx** | ✅ | ✅ |
| **الفحوصات** | ✅ | ✅ |
| **CI/CD** | ✅ | ✅ |
| **النشر** | ✅ | ✅ |

---

**آخر تحديث:** 2026-09-11
**الحالة:** جاهز للإنتاج 🚀
