# =====================================================
# Itqan ERP - IIS Startup Script (PowerShell)
# =====================================================
#
# الغرض: تشغيل موقع الويب في IIS
# الدومين: https://erp.droob-albayan.ly/app
# المسار: C:\kinetic
#
# =====================================================

param(
    [string]$WebsiteName = "Default Web Site",
    [string]$AppPoolName = "DefaultAppPool",
    [string]$LogFile = "C:\temp\iis_startup.log"
)

Clear-Host

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗"
Write-Host "║                                                        ║"
Write-Host "║    Itqan ERP - IIS Startup Script (PowerShell)        ║"
Write-Host "║    سكريبت تشغيل IIS                                    ║"
Write-Host "║                                                        ║"
Write-Host "╚════════════════════════════════════════════════════════╝"
Write-Host ""

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Add-Content -Path $LogFile
    Write-Host "   [$timestamp] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
    Write-Log "✓ $Message"
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
    Write-Log "❌ $Message"
}

# =====================================================
# التحقق من صلاحيات Admin
# =====================================================

$isAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
if (-not $isAdmin) {
    Write-Host "❌ خطأ: يجب تشغيل السكريبت كمسؤول!" -ForegroundColor Red
    Write-Host ""
    Write-Host "الحل:"
    Write-Host "1. افتح PowerShell كمسؤول"
    Write-Host "2. شغّل السكريبت"
    Write-Host ""
    pause
    exit 1
}

Write-Success "صلاحيات Admin موجودة"
Write-Host ""

# =====================================================
# الخطوة 1: التحقق من وجود مجلد الموقع
# =====================================================

Write-Host "1️⃣  التحقق من مجلد الموقع..." -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path "C:\kinetic")) {
    Write-Error-Custom "لم يتم العثور على المجلد C:\kinetic"
    Write-Host ""
    Write-Host "الحل:"
    Write-Host "1. تأكد من نشر الملفات على C:\kinetic"
    Write-Host "2. شغّل deploy.bat أولاً"
    Write-Host ""
    pause
    exit 1
}

Write-Success "المجلد موجود: C:\kinetic"

if (-not (Test-Path "C:\kinetic\index.html")) {
    Write-Error-Custom "لم يتم العثور على index.html"
    pause
    exit 1
}

Write-Success "ملف index.html موجود"
Write-Host ""

# =====================================================
# الخطوة 2: التحقق من تثبيت IIS
# =====================================================

Write-Host "2️⃣  التحقق من تثبيت IIS..." -ForegroundColor Cyan
Write-Host ""

try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Success "وحدة IIS مثبتة"
} catch {
    Write-Error-Custom "خطأ: وحدة IIS غير مثبتة"
    Write-Host ""
    Write-Host "الحل:"
    Write-Host "1. افتح Control Panel → Programs → Programs and Features"
    Write-Host "2. اختر 'Turn Windows features on or off'"
    Write-Host "3. قم بتفعيل 'Internet Information Services (IIS)'"
    Write-Host ""
    pause
    exit 1
}

Write-Host ""

# =====================================================
# الخطوة 3: إعادة تشغيل IIS
# =====================================================

Write-Host "3️⃣  إعادة تشغيل IIS..." -ForegroundColor Cyan
Write-Host ""

try {
    iisreset /restart /noforce
    if ($LASTEXITCODE -eq 0) {
        Write-Success "تم إعادة تشغيل IIS بنجاح"
    } else {
        Write-Error-Custom "قد يكون هناك خطأ في إعادة التشغيل"
    }
} catch {
    Write-Error-Custom "خطأ في إعادة تشغيل IIS: $_"
    pause
    exit 1
}

Write-Host ""

# =====================================================
# الخطوة 4: فتح الموقع في المتصفح
# =====================================================

Write-Host "4️⃣  فتح الموقع في المتصفح..." -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 2

try {
    Start-Process "https://erp.droob-albayan.ly/app"
    Write-Success "تم فتح الموقع في المتصفح"
} catch {
    Write-Host "⚠️  لم يتمكن من فتح المتصفح تلقائياً" -ForegroundColor Yellow
    Write-Host "   يمكنك فتح الرابط يدويًا:"
    Write-Host "   https://erp.droob-albayan.ly/app"
}

Write-Host ""

# =====================================================
# ملخص البدء
# =====================================================

Write-Host "╔════════════════════════════════════════════════════════╗"
Write-Host "║               ✅ تم التشغيل بنجاح!                     ║"
Write-Host "╚════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "🌐 الموقع متاح على:"
Write-Host "   https://erp.droob-albayan.ly/app"
Write-Host ""
Write-Host "📂 مسار الملفات:"
Write-Host "   C:\kinetic"
Write-Host ""
Write-Host "🔍 للتحقق من الحالة:"
Write-Host "   iisreset /status"
Write-Host ""
Write-Host "🛑 لإيقاف الموقع:"
Write-Host "   iisreset /stop"
Write-Host ""
Write-Host "🚀 لإعادة التشغيل:"
Write-Host "   iisreset /restart"
Write-Host ""
Write-Host "📝 السجل مسجل في:"
Write-Host "   $LogFile"
Write-Host ""

Write-Log "════════════════════════════════════════════════════════"
Write-Log "✅ تم البدء بنجاح"

Write-Host "اضغط أي زر للإغلاق..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
