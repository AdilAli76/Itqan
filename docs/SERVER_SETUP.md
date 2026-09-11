# دليل إعداد الخوادم

## نظرة عامة
يحتوي هذا الدليل على خطوات إعداد Staging و Production servers لتطبيق Itqan ERP.

## المتطلبات

### أولاً: الخادم نفسه
- **OS:** Ubuntu 20.04 LTS أو أحدث
- **RAM:** 4GB حد أدنى (8GB موصى به)
- **CPU:** 2 cores حد أدنى (4 cores موصى به)
- **Storage:** 20GB حد أدنى (50GB موصى به)

## خطوات الإعداد

### المرحلة الأولى: إعداد السيرفر (15-20 دقيقة)

```bash
# تحميل سكريبت الإعداد
cd /tmp
wget https://raw.githubusercontent.com/AdilAli76/Itqan/main/scripts/server-setup.sh
chmod +x server-setup.sh

# تشغيل للتجريب
./server-setup.sh staging

# أو للإنتاج
./server-setup.sh production
```

**ما يفعله:**
- تحديث النظام
- تثبيت المتطلبات
- إنشاء مستخدم deploy
- إنشاء مجلدات النشر
- إعداد Firewall
- إعداد Nginx

### المرحلة الثانية: إعداد SSL (5-10 دقائق)

```bash
./setup-ssl.sh staging
```

**للإنتاج: استخدم Let's Encrypt**

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot certonly --nginx -d erp.itqan.local
sudo systemctl enable certbot.timer
```

### المرحلة الثالثة: إعداد GitHub Runner (10-15 دقيقة)

```bash
# الحصول على توكن من GitHub Settings
./setup-runner.sh staging <TOKEN>
```

## اختبار الإعداد

```bash
# فحص شامل
./server-health-check.sh staging

# فحص الخدمات
sudo systemctl status nginx
sudo systemctl status actions.runner.*

# اختبار الاتصال
curl -k https://localhost/health
```

## مجلدات مهمة

```
/opt/itqan/
├── staging/
│   └── current → symlink للنسخة الحالية
├── production/
│   └── current
└── backups/
    ├── staging/
    └── production/

/var/log/itqan/
└── deployment_*.log
```

## استكشاف المشاكل

### Runner لا يعمل

```bash
sudo systemctl status actions.runner.*
sudo journalctl -u actions.runner.* -f
```

### الاتصال بـ HTTPS

```bash
sudo openssl x509 -in /etc/ssl/certs/itqan.crt -text -noout
sudo nginx -t
sudo systemctl reload nginx
```

## الأمان

- استخدم SSH keys فقط
- فعّل 2FA على GitHub
- قيّد الـ Firewall
- راقب السجلات بانتظام

