#!/bin/bash

# GitHub Actions Runner Setup Script
# يثبت Self-Hosted Runner على الخادم

set -e

# الألوان
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# الإعدادات
ENVIRONMENT="${1:-staging}"
RUNNER_DIR="/opt/itqan/runners/${ENVIRONMENT}"
RUNNER_VERSION="2.308.0"
GITHUB_REPO="AdilAli76/Itqan"
RUNNER_TOKEN="${2:-}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GitHub Actions Runner Setup${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ -z "$RUNNER_TOKEN" ]; then
    echo -e "${YELLOW}⚠️  لم يتم توفير RUNNER_TOKEN${NC}"
    echo ""
    echo "للحصول على TOKEN:"
    echo "1. اذهب إلى: https://github.com/AdilAli76/Itqan/settings/actions/runners"
    echo "2. انقر 'New self-hosted runner'"
    echo "3. انسخ التوكن المعروض"
    echo ""
    echo "ثم شغّل:"
    echo "  $0 $ENVIRONMENT <TOKEN>"
    exit 1
fi

echo -e "${YELLOW}[1/4] تحميل Runner...${NC}"
cd "$RUNNER_DIR"
rm -f actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

curl -L -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

echo -e "${GREEN}✓ تم تحميل Runner${NC}"
echo ""

echo -e "${YELLOW}[2/4] فك الضغط...${NC}"
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
echo -e "${GREEN}✓ تم فك الضغط${NC}"
echo ""

echo -e "${YELLOW}[3/4] تكوين Runner...${NC}"
./config.sh \
    --url https://github.com/${GITHUB_REPO} \
    --token "$RUNNER_TOKEN" \
    --name "${ENVIRONMENT}-runner" \
    --labels "$ENVIRONMENT" \
    --runnergroup "Default" \
    --unattended \
    --replace

echo -e "${GREEN}✓ تم تكوين Runner${NC}"
echo ""

echo -e "${YELLOW}[4/4] تثبيت كخدمة...${NC}"
sudo ./svc.sh install
sudo ./svc.sh start

# التحقق من حالة الخدمة
sleep 2
if sudo systemctl is-active --quiet actions.runner.${GITHUB_REPO/\//-}.${ENVIRONMENT}-runner.service; then
    echo -e "${GREEN}✓ الخدمة تعمل بنجاح${NC}"
else
    echo -e "${YELLOW}⚠️  الخدمة قد تحتاج إلى وقت للبدء${NC}"
fi
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ اكتمل إعداد Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}معلومات الخدمة:${NC}"
echo "  Service: actions.runner.${GITHUB_REPO/\//-}.${ENVIRONMENT}-runner.service"
echo "  Directory: $RUNNER_DIR"
echo "  Environment: $ENVIRONMENT"
echo ""

echo -e "${YELLOW}الأوامر المفيدة:${NC}"
echo "  # عرض حالة الخدمة"
echo "  sudo systemctl status actions.runner.${GITHUB_REPO/\//-}.${ENVIRONMENT}-runner.service"
echo ""
echo "  # عرض السجلات"
echo "  sudo journalctl -u actions.runner.${GITHUB_REPO/\//-}.${ENVIRONMENT}-runner.service -f"
echo ""
echo "  # إيقاف الخدمة"
echo "  sudo ./svc.sh stop"
echo ""
echo "  # إعادة تشغيل"
echo "  sudo ./svc.sh restart"
echo ""
echo -e "${YELLOW}الخطوات التالية:${NC}"
echo "  1. تحقق من Runner على GitHub"
echo "  2. اختبر workflow عليه"
echo "  3. راقب السجلات"
echo ""
