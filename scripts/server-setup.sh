#!/bin/bash

# Server Setup Script for Itqan ERP
# يعد الخادم للنشر التلقائي

set -e

# الألوان
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# الإعدادات
ENVIRONMENT="${1:-staging}"
DEPLOY_USER="deploy"
DEPLOY_DIR="/opt/itqan/${ENVIRONMENT}"
RUNNER_DIR="/opt/itqan/runners/${ENVIRONMENT}"
BACKUPS_DIR="/opt/itqan/backups/${ENVIRONMENT}"
LOGS_DIR="/var/log/itqan"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Server Setup - Itqan ERP${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 1. تحديث النظام
echo -e "${YELLOW}[1/6] تحديث النظام...${NC}"
sudo apt-get update
sudo apt-get upgrade -y
echo -e "${GREEN}✓ تم تحديث النظام${NC}"
echo ""

# 2. تثبيت المتطلبات
echo -e "${YELLOW}[2/6] تثبيت المتطلبات...${NC}"
sudo apt-get install -y \
    curl wget git unzip zip \
    build-essential libssl-dev libffi-dev python3-dev \
    nginx ufw \
    jq htop tmux
echo -e "${GREEN}✓ تم تثبيت المتطلبات${NC}"
echo ""

# 3. إنشاء مستخدم النشر
echo -e "${YELLOW}[3/6] إنشاء مستخدم النشر...${NC}"
if ! id "$DEPLOY_USER" &>/dev/null; then
    sudo useradd -m -s /bin/bash "$DEPLOY_USER"
    echo -e "${GREEN}✓ تم إنشاء مستخدم: $DEPLOY_USER${NC}"
else
    echo -e "${GREEN}✓ المستخدم موجود بالفعل: $DEPLOY_USER${NC}"
fi
echo ""

# 4. إنشاء مجلدات النشر
echo -e "${YELLOW}[4/6] إنشاء مجلدات النشر...${NC}"
sudo mkdir -p "$DEPLOY_DIR"
sudo mkdir -p "$BACKUPS_DIR"
sudo mkdir -p "$RUNNER_DIR"
sudo mkdir -p "$LOGS_DIR"

sudo chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_DIR"
sudo chown "$DEPLOY_USER:$DEPLOY_USER" "$BACKUPS_DIR"
sudo chown "$DEPLOY_USER:$DEPLOY_USER" "$RUNNER_DIR"
sudo chown root:root "$LOGS_DIR"
sudo chmod 755 "$DEPLOY_DIR" "$BACKUPS_DIR" "$RUNNER_DIR" "$LOGS_DIR"

echo -e "${GREEN}✓ تم إنشاء المجلدات:${NC}"
echo "  - $DEPLOY_DIR"
echo "  - $BACKUPS_DIR"
echo "  - $RUNNER_DIR"
echo "  - $LOGS_DIR"
echo ""

# 5. إعداد Firewall
echo -e "${YELLOW}[5/6] إعداد Firewall...${NC}"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw enable -y
echo -e "${GREEN}✓ تم إعداد Firewall${NC}"
echo ""

# 6. إعداد Nginx (Reverse Proxy)
echo -e "${YELLOW}[6/6] إعداد Nginx...${NC}"
sudo tee /etc/nginx/sites-available/itqan-${ENVIRONMENT} > /dev/null <<EOF
server {
    listen 443 ssl http2;
    server_name ${ENVIRONMENT}.itqan.local erp.itqan.local;

    ssl_certificate /etc/ssl/certs/itqan.crt;
    ssl_certificate_key /etc/ssl/private/itqan.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root $DEPLOY_DIR/current/web;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
        expires 1h;
    }

    location /api/ {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /health {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }
}

server {
    listen 80;
    server_name ${ENVIRONMENT}.itqan.local erp.itqan.local;
    return 301 https://\$server_name\$request_uri;
}
EOF

# تفعيل الموقع
if [ -f /etc/nginx/sites-available/itqan-${ENVIRONMENT} ]; then
    sudo ln -sf /etc/nginx/sites-available/itqan-${ENVIRONMENT} /etc/nginx/sites-enabled/ 2>/dev/null || true
    sudo nginx -t && sudo systemctl restart nginx
    echo -e "${GREEN}✓ تم إعداد Nginx${NC}"
else
    echo -e "${RED}✗ فشل إعداد Nginx${NC}"
fi
echo ""

# ملخص
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ اكتمل إعداد السيرفر${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}معلومات الإعداد:${NC}"
echo "  Environment: $ENVIRONMENT"
echo "  Deploy User: $DEPLOY_USER"
echo "  Deploy Dir: $DEPLOY_DIR"
echo "  Runner Dir: $RUNNER_DIR"
echo "  Logs Dir: $LOGS_DIR"
echo ""
echo -e "${YELLOW}الخطوات التالية:${NC}"
echo "  1. إعداد SSL Certificates"
echo "  2. تثبيت GitHub Actions Runner"
echo "  3. إنشاء SSH keys"
echo "  4. اختبار الاتصال"
echo ""
echo -e "${YELLOW}الأوامر المفيدة:${NC}"
echo "  # عرض حالة النظام"
echo "  systemctl status nginx"
echo ""
echo "  # عرض السجلات"
echo "  tail -f $LOGS_DIR/*.log"
echo ""
echo "  # اختبار الصحة"
echo "  curl http://localhost/health"
echo ""
