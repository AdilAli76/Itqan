#!/bin/bash

# Server Health Check Script
# يفحص صحة السيرفر والخدمات

# الألوان
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENVIRONMENT="${1:-staging}"
HEALTH_ENDPOINT="http://localhost/health"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Server Health Check${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# عداد الفحوصات
PASSED=0
FAILED=0

# دالة للفحص
check_service() {
    local service_name="$1"
    local display_name="$2"

    if systemctl is-active --quiet "$service_name"; then
        echo -e "${GREEN}✓${NC} $display_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $display_name"
        ((FAILED++))
    fi
}

check_port() {
    local port="$1"
    local name="$2"

    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $name (port $port)"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $name (port $port)"
        ((FAILED++))
    fi
}

# فحوصات الخدمات
echo -e "${YELLOW}فحص الخدمات:${NC}"
check_service "nginx" "Nginx Web Server"

# فحص GitHub Runner إذا كان موجوداً
if [ "$ENVIRONMENT" != "dev" ]; then
    RUNNER_SERVICE="actions.runner.AdilAli76-Itqan.${ENVIRONMENT}-runner.service"
    if systemctl list-units --all | grep -q "$RUNNER_SERVICE"; then
        check_service "$RUNNER_SERVICE" "GitHub Actions Runner"
    fi
fi
echo ""

# فحوصات المنافذ
echo -e "${YELLOW}فحص المنافذ:${NC}"
check_port "80" "HTTP"
check_port "443" "HTTPS"
check_port "22" "SSH"
echo ""

# فحص الاتصال
echo -e "${YELLOW}فحص الاتصال:${NC}"
if curl -s -f "$HEALTH_ENDPOINT" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Health Endpoint ($HEALTH_ENDPOINT)"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠${NC} Health Endpoint (قد تحتاج تطبيق)"
fi
echo ""

# فحوصات النظام
echo -e "${YELLOW}فحص النظام:${NC}"

# المساحة الحرة
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "${GREEN}✓${NC} Disk Space: ${DISK_USAGE}%"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Disk Space: ${DISK_USAGE}% (تحذير!)"
    ((FAILED++))
fi

# الذاكرة
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", ($3/$2) * 100)}')
if [ "$MEMORY_USAGE" -lt 80 ]; then
    echo -e "${GREEN}✓${NC} Memory: ${MEMORY_USAGE}%"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Memory: ${MEMORY_USAGE}% (تحذير!)"
    ((FAILED++))
fi

# عدد العمليات
PROCESS_COUNT=$(ps aux | wc -l)
echo -e "${GREEN}✓${NC} Processes: $PROCESS_COUNT"
((PASSED++))

echo ""

# فحوصات الملفات والمجلدات
echo -e "${YELLOW}فحص الملفات والمجلدات:${NC}"

DEPLOY_DIR="/opt/itqan/${ENVIRONMENT}"
if [ -d "$DEPLOY_DIR" ]; then
    echo -e "${GREEN}✓${NC} Deploy Directory: $DEPLOY_DIR"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Deploy Directory: $DEPLOY_DIR"
    ((FAILED++))
fi

CURRENT_LINK="$DEPLOY_DIR/current"
if [ -L "$CURRENT_LINK" ]; then
    CURRENT_TARGET=$(readlink -f "$CURRENT_LINK")
    echo -e "${GREEN}✓${NC} Current Deployment: $CURRENT_TARGET"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠${NC} Current Deployment: لم يتم نشر أي نسخة بعد"
fi

BACKUPS_DIR="/opt/itqan/backups/${ENVIRONMENT}"
if [ -d "$BACKUPS_DIR" ]; then
    BACKUP_COUNT=$(ls -d "$BACKUPS_DIR"/backup_* 2>/dev/null | wc -l)
    echo -e "${GREEN}✓${NC} Backups: $BACKUP_COUNT نسخة احتياطية"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠${NC} Backups: لم يتم إنشاء backups بعد"
fi

echo ""

# الملخص
echo -e "${BLUE}========================================${NC}"
TOTAL=$((PASSED + FAILED))
PERCENTAGE=$((PASSED * 100 / TOTAL))

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✅ جميع الفحوصات نجحت${NC}"
else
    echo -e "${YELLOW}⚠️  بعض الفحوصات فشلت${NC}"
fi

echo -e "الفحوصات: ${GREEN}$PASSED نجح${NC} / ${RED}$FAILED فشل${NC} (${PERCENTAGE}%)"
echo -e "${BLUE}========================================${NC}"
echo ""

# توصيات
if [ "$DISK_USAGE" -gt 70 ]; then
    echo -e "${YELLOW}💡 توصية:${NC} قم بتنظيف مساحة القرص"
fi

if [ "$MEMORY_USAGE" -gt 70 ]; then
    echo -e "${YELLOW}💡 توصية:${NC} الذاكرة قيد الاستخدام، راقب العمليات"
fi

if [ -z "$(ls -d $BACKUPS_DIR/backup_* 2>/dev/null)" ]; then
    echo -e "${YELLOW}💡 توصية:${NC} قم بأول نشر لإنشاء نسخة احتياطية"
fi

echo ""

# رمز الخروج
if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
