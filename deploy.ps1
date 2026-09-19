# =====================================================
# Itqan ERP - Web Deployment Script (PowerShell)
# =====================================================
#
# الغرض: فك ضغط ملف الويب ونسخه إلى مجلد الإنتاج
# المصدر: C:\temp\ItqanERP-Web-v1.0.0.zip
# الهدف: C:\kinetic
#
# =====================================================

param(
    [string]$SourceZip = "C:\temp\ItqanERP-Web-v1.0.0.zip",
    [string]$TargetDir = "C:\kinetic",
    [string]$TempExtract = "C:\temp\extract_temp",
    [string]$LogFile = "C:\temp\deployment.log"
)

# =====================================================
# الدوال المساعدة
# =====================================================

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Add-Content -Path $LogFile
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $Title" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

# =====================================================
# البداية
# =====================================================

Clear-Host

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗"
Write-Host "║                                                        ║"
Write-Host "║    Itqan ERP - Web Deployment Script (PowerShell)     ║"
Write-Host "║    نسخة الويب - سكريبت النشر                           ║"
Write-Host "║                                                        ║"
Write-Host "╚════════════════════════════════════════════════════════╝"
Write-Host ""

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "الوقت: $timestamp"
Write-Host ""

# إنشاء ملف السجل
if (-not (Test-Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
}

Write-Log "بدء النشر..."

# =====================================================
# الخطوة 1: التحقق من الملف
# =====================================================

Write-Section "1️⃣  التحقق من ملف ZIP"

if (-not (Test-Path $SourceZip)) {
    Write-Error-Custom "لم يتم العثور على الملف: $SourceZip"
    Write-Log "❌ خطأ: ملف ZIP غير موجود"
    pause
    exit 1
} else {
    Write-Success "ملف ZIP موجود: $SourceZip"
    $fileSize = (Get-Item $SourceZip).Length / 1MB
    Write-Host "   حجم الملف: $([math]::Round($fileSize, 2)) MB"
    Write-Log "✓ ملف ZIP موجود"
}

# =====================================================
# الخطوة 2: فك الضغط
# =====================================================

Write-Section "2️⃣  فك ضغط الملف"

if (Test-Path $TempExtract) {
    Write-Host "   حذف المجلد المؤقت السابق..."
    Remove-Item -Path $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $TempExtract -Force | Out-Null

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($SourceZip, $TempExtract)
    Write-Success "تم فك الضغط بنجاح"
    Write-Log "✓ تم فك الضغط"
} catch {
    Write-Error-Custom "خطأ في فك الضغط: $_"
    Write-Log "❌ خطأ في فك الضغط: $_"
    pause
    exit 1
}

# =====================================================
# الخطوة 3: حذف المجلد القديم
# =====================================================

Write-Section "3️⃣  حذف النسخة القديمة"

if (Test-Path $TargetDir) {
    Write-Host "   حذف: $TargetDir"
    Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "تم حذف المجلد القديم"
    Write-Log "✓ حذف النسخة القديمة"
} else {
    Write-Host "   المجلد الهدف غير موجود (أول نشر)"
}

# =====================================================
# الخطوة 4: نسخ الملفات الجديدة
# =====================================================

Write-Section "4️⃣  نسخ الملفات الجديدة"

New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

try {
    Copy-Item -Path "$TempExtract\*" -Destination $TargetDir -Recurse -Force
    Write-Success "تم نسخ الملفات بنجاح"
    Write-Host "   الهدف: $TargetDir"
    Write-Log "✓ تم نسخ الملفات"
} catch {
    Write-Error-Custom "خطأ في نسخ الملفات: $_"
    Write-Log "❌ خطأ في نسخ الملفات: $_"
    pause
    exit 1
}

# =====================================================
# الخطوة 5: تعيين الصلاحيات
# =====================================================

Write-Section "5️⃣  تعيين الصلاحيات"

try {
    $acl = Get-Acl $TargetDir
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($accessRule)
    Set-Acl -Path $TargetDir -AclObject $acl
    Write-Success "تم تعيين الصلاحيات"
    Write-Log "✓ تم تعيين الصلاحيات"
} catch {
    Write-Warning-Custom "قد تحتاج صلاحيات أعلى: $_"
    Write-Log "⚠️  تحذير في تعيين الصلاحيات"
}

# =====================================================
# الخطوة 6: التنظيف
# =====================================================

Write-Section "6️⃣  التنظيف"

if (Test-Path $TempExtract) {
    Remove-Item -Path $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
    Write-Success "تم حذف الملفات المؤقتة"
    Write-Log "✓ تم التنظيف"
}

# =====================================================
# الخطوة 7: التحقق النهائي
# =====================================================

Write-Section "7️⃣  التحقق النهائي"

$indexPath = Join-Path -Path $TargetDir -ChildPath "index.html"

if (Test-Path $indexPath) {
    Write-Success "تم العثور على index.html"
    Write-Success "النشر نجح بنجاح!"

    # عد الملفات
    $fileCount = (Get-ChildItem -Path $TargetDir -Recurse -File | Measure-Object).Count
    Write-Host "   عدد الملفات: $fileCount"

    Write-Log "✓ النشر مكتمل بنجاح"
} else {
    Write-Error-Custom "لم يتم العثور على index.html"
    Write-Log "❌ خطأ: index.html غير موجود"
    pause
    exit 1
}

# =====================================================
# ملخص النشر
# =====================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗"
Write-Host "║                   ✅ النشر مكتمل!                      ║"
Write-Host "╚════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "📊 الملخص:"
Write-Host "   ✓ ملف المصدر: $SourceZip"
Write-Host "   ✓ مجلد الهدف: $TargetDir"
Write-Host "   ✓ الحالة: نجح بنجاح"
Write-Host "   ✓ السجل: $LogFile"
Write-Host ""
Write-Host "🌐 للوصول للموقع:"
Write-Host "   http://localhost (محلياً)"
Write-Host "   أو: عنوان IP السيرفر"
Write-Host ""
Write-Host "📝 تم تسجيل العملية في:"
Write-Host "   $LogFile"
Write-Host ""

Write-Log "════════════════════════════════════════════════════════"

Write-Host "اضغط أي زر للإغلاق..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
