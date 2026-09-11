#!/bin/bash

# SSL/TLS Certificate Setup Script
# يعد شهادات SSL للخادم

set -e

# الألوان
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENVIRONMENT="${1:-staging}"
DOMAIN="${2:-${ENVIRONMENT}.itqan.local}"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
DAYS_VALID="${3:-365}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SSL Certificate Setup${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}Domain: ${DOMAIN}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# فحص المتطلبات
if ! command -v openssl &> /dev/null; then
    echo -e "${YELLOW}تثبيت openssl...${NC}"
    sudo apt-get install -y openssl
fi

echo -e "${YELLOW}[1/3] إنشاء مفتاح خاص...${NC}"
sudo openssl genrsa -out "${KEY_DIR}/itqan.key" 2048
sudo chmod 600 "${KEY_DIR}/itqan.key"
echo -e "${GREEN}✓ تم إنشاء المفتاح الخاص${NC}"
echo ""

echo -e "${YELLOW}[2/3] إنشاء طلب التوقيع (CSR)...${NC}"
sudo openssl req -new \
    -key "${KEY_DIR}/itqan.key" \
    -out "${CERT_DIR}/itqan.csr" \
    -subj "/C=SA/ST=Riyadh/L=Riyadh/O=Itqan/CN=${DOMAIN}"
echo -e "${GREEN}✓ تم إنشاء طلب التوقيع${NC}"
echo ""

echo -e "${YELLOW}[3/3] إنشاء شهادة موقعة ذاتياً...${NC}"
# للتطوير والاختبار
sudo openssl x509 -req \
    -days "$DAYS_VALID" \
    -in "${CERT_DIR}/itqan.csr" \
    -signkey "${KEY_DIR}/itqan.key" \
    -out "${CERT_DIR}/itqan.crt"

sudo chmod 644 "${CERT_DIR}/itqan.crt"
echo -e "${GREEN}✓ تم إنشاء الشهادة${NC}"
echo ""

# عرض معلومات الشهادة
echo -e "${YELLOW}معلومات الشهادة:${NC}"
sudo openssl x509 -in "${CERT_DIR}/itqan.crt" -text -noout | grep -E "Subject:|Not Before|Not After|Public-Key"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ اكتمل إعداد SSL${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}معلومات الملفات:${NC}"
echo "  Private Key: ${KEY_DIR}/itqan.key"
echo "  Certificate: ${CERT_DIR}/itqan.crt"
echo "  CSR: ${CERT_DIR}/itqan.csr"
echo ""

echo -e "${YELLOW}⚠️  ملاحظة مهمة:${NC}"
echo "  هذه شهادة موقعة ذاتياً للتطوير فقط!"
echo ""
echo "  للإنتاج، استخدم:"
echo "  - Let's Encrypt (مجاني + تجديد تلقائي)"
echo "  - شهادة من مزود موثوق"
echo ""

echo -e "${YELLOW}الخطوات التالية:${NC}"
echo "  1. أعد تشغيل Nginx"
echo "     sudo systemctl restart nginx"
echo ""
echo "  2. اختبر الاتصال"
echo "     curl -k https://localhost/health"
echo ""
echo "  3. للإنتاج، استخدم Let's Encrypt:"
echo "     sudo apt-get install -y certbot python3-certbot-nginx"
echo "     sudo certbot certonly --standalone -d ${DOMAIN}"
echo ""
