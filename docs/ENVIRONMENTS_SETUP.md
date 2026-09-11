# إعداد البيئات 🏗️

## البيئات

### 1️⃣ Development (المحلية)

```bash
# المجلد: /home/user/kinetic-erp
# الفرع: main/develop
# الخادم: localhost:8080
```

### 2️⃣ Staging (التجريب)

```bash
# المجلد: /opt/itqan/staging
# URL: https://staging.itqan.local
# الخادم: staging-server
# Runner: Self-hosted (staging label)
```

### 3️⃣ Production (الإنتاج)

```bash
# المجلد: /opt/itqan/production
# URL: https://erp.itqan.local
# الخادم: production-server
# Runner: Self-hosted (production label)
```

## إعداد Self-Hosted Runner

### على Staging:

```bash
# 1. تحميل runner
cd /opt/itqan/runners/staging
wget https://github.com/actions/runner/releases/download/v2.308.0/actions-runner-linux-x64-2.308.0.tar.gz
tar xzf actions-runner-linux-x64-2.308.0.tar.gz

# 2. تكوين
# الذهاب إلى: Settings → Actions → Runners → New self-hosted runner
# نسخ التوكن وتشغيل:
./config.sh --url https://github.com/AdilAli76/Itqan \
  --token <TOKEN> \
  --labels staging

# 3. تشغيل كخدمة
sudo ./svc.sh install
sudo ./svc.sh start

# 4. التحقق
sudo systemctl status actions.runner.AdilAli76-Itqan.staging.service
```

### على Production:

```bash
# نفس الخطوات مع "production" بدلاً من "staging"
```

## متغيرات البيئة

### على GitHub (Settings → Secrets and Variables → Actions)

```
GITHUB_TOKEN              # تلقائي
STAGING_DEPLOY_KEY       # SSH private key
PRODUCTION_DEPLOY_KEY    # SSH private key
```

### على الخوادم

#### `/etc/environment.d/itqan.conf`:

```bash
# Staging
ITQAN_VERSION=1.7.3
ITQAN_ENV=staging
ITQAN_LOG_LEVEL=info
DB_HOST=db.itqan.local
DB_NAME=itqan_staging
DB_USER=itqan_app
DB_PASSWORD=***

# Production
ITQAN_VERSION=1.7.3
ITQAN_ENV=production
ITQAN_LOG_LEVEL=warn
DB_HOST=db.itqan.local
DB_NAME=itqan_prod
DB_USER=itqan_app
DB_PASSWORD=***
```

## مجلدات النشر

### Staging:

```
/opt/itqan/staging/
├── 20240911_100000/    # نسخة قديمة
├── 20240911_120000/    # نسخة أخرى
└── current → 20240911_120000  # النسخة النشطة
```

### Production:

```
/opt/itqan/production/
├── 20240911_100000/    # نسخة قديمة
├── 20240911_120000/    # نسخة أخرى
└── current → 20240911_120000  # النسخة النشطة
```

## Backups

```
/opt/itqan/backups/
├── staging/
│   ├── backup_20240911_100000/
│   ├── backup_20240911_120000/
│   └── latest → backup_20240911_120000
└── production/
    ├── backup_20240911_100000/
    ├── backup_20240911_120000/
    └── latest → backup_20240911_120000
```

## Firewall

### على Staging:

```bash
# Allow HTTPS
sudo ufw allow 443/tcp

# Allow SSH (من GitHub Runners)
sudo ufw allow 22/tcp

# Check status
sudo ufw status
```

### على Production:

```bash
# نفس الإعدادات مع تقييد أقسى للوصول
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 443/tcp  # HTTPS فقط
sudo ufw allow from <CI_SERVER_IP> to any port 22  # SSH من CI فقط
sudo ufw enable
```

## Monitoring

### السجلات:

```bash
# Staging deployment log
tail -f /var/log/itqan/deployment_*.log

# Application logs
tail -f /opt/itqan/staging/current/logs/app.log
```

### الخدمات:

```bash
# Check status
systemctl status itqan-staging
systemctl status itqan-production

# View logs
journalctl -u itqan-staging -f
```

## Health Checks

### Staging:

```bash
curl https://staging.itqan.local/health
```

### Production:

```bash
curl https://erp.itqan.local/health
```

## الأمان

⚠️ **تذكر:**
- استخدم SSH keys فقط (بلا كلمات مرور)
- قيّد صلاحيات: `chmod 755 scripts/deploy-*.sh`
- قيّد الوصول إلى الملفات الحساسة
- فعّل 2FA على GitHub
- راقب السجلات بانتظام
