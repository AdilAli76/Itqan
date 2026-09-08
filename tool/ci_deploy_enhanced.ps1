<#
.SYNOPSIS
    نسخة محسّنة من ci_deploy.ps1 مع معالجة الأخطاء التلقائية.

.DESCRIPTION
    تحسينات:
    - تحميل ملفات tool/ تلقائياً من GitHub إن لم تكن موجودة
    - تحقق أفضل من المتطلبات قبل النشر
    - سجل نشر مفصّل للتتبع
    - معالجة أخطاء شاملة
    - دعم إعادة محاولة النشر

.PARAMETER Repo
    اسم المستودع (مثال: adilmohamed76-hub/kinetic-erp)

.PARAMETER Tag
    وسم الإصدار (مثال: v1.6.4)

.PARAMETER Target
    staging أو production
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Repo,
    [string]$Tag,
    [string]$RunId,
    [string]$Version,
    [Parameter(Mandatory = $true)] [ValidateSet('staging', 'production')] [string]$Target,
    [Parameter(Mandatory = $true)] [string]$Token,
    [switch]$SkipDb,
    [switch]$MandatoryUpdate,
    [int]$MaxRetries = 3
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    ✅ $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    ⚠️  $t" -ForegroundColor Yellow }
function Error($t) { Write-Host "    ❌ $t" -ForegroundColor Red }
function Info($t) { Write-Host "    ℹ️  $t" -ForegroundColor Gray }

$logFile = Join-Path (Split-Path $PSScriptRoot) "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function Log($msg) {
    Add-Content -LiteralPath $logFile -Value $msg
}

Step 0 'التحقق من البيئة والمتطلبات'

# ── التحقق من PowerShell ────────────────────────────────────────────
$psVersion = $PSVersionTable.PSVersion.Major
if ($psVersion -lt 5) {
    Error "PowerShell $psVersion غير مدعوم (يتطلب 5.0+)"
    exit 1
}
Ok "PowerShell $psVersion"

# ── التحقق من الاتصال بالإنترنت ────────────────────────────────────
$connected = $false
try {
    $response = Invoke-WebRequest -Uri "https://api.github.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
    $connected = $response.StatusCode -eq 200
} catch { }

if (-not $connected) {
    Error "لا اتصال بـ GitHub API"
    exit 1
}
Ok "اتصال بـ GitHub"

# ── تحميل ملفات tool/ تلقائياً ────────────────────────────────────
Step 1 'تجهيز ملفات النشر'

$wantTools = @("deploy_update.ps1", "backup.ps1")
$toolDir = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "tool"

if (-not (Test-Path $toolDir)) {
    New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
    Info "تم إنشاء مجلد tool"
}

$missingTools = @()
foreach ($tool in $wantTools) {
    $toolPath = Join-Path $toolDir $tool
    if (-not (Test-Path $toolPath)) {
        $missingTools += $tool
    }
}

if ($missingTools.Count -gt 0) {
    Warn "ملفات مفقودة: $($missingTools -join ', ')"
    Warn "جاري تحميلها من GitHub..."

    $githubUrl = "https://raw.githubusercontent.com/$Repo/main/tool"
    foreach ($tool in $missingTools) {
        $toolPath = Join-Path $toolDir $tool
        try {
            $url = "$githubUrl/$tool"
            Info "تحميل $tool..."
            Invoke-WebRequest -Uri $url -OutFile $toolPath -UseBasicParsing -ErrorAction Stop
            Ok "تم تحميل $tool"
            Log "تم تحميل $tool من GitHub"
        } catch {
            Error "فشل تحميل $tool: $_"
            Log "خطأ في تحميل $tool: $_"
            exit 1
        }
    }
}

# تحقق نهائي من وجود deploy_update.ps1
$deployUpdate = Join-Path $toolDir "deploy_update.ps1"
if (-not (Test-Path $deployUpdate)) {
    Error "deploy_update.ps1 لا يزال غير موجود بعد المحاولة"
    Log "خطأ: deploy_update.ps1 غير موجود في $toolDir"
    exit 1
}

Ok "جميع ملفات tool موجودة"
Log "تحقق من ملفات tool: تمام"

# ── تحديد وجهة النشر ────────────────────────────────────────────────
if ($Target -eq 'staging') {
    $root = 'C:\kinetic-staging'
    $site = 'KineticStaging'
    $pool = 'KineticStagingPool'
} else {
    $root = 'C:\kinetic'
    $site = 'Kinetic'
    $pool = 'KineticApi'
}

if (-not (Test-Path $root)) {
    Error "مجلد الوجهة غير موجود: $root"
    Log "خطأ: مجلد $root غير موجود"
    exit 1
}

Ok "الوجهة: $root"
Log "وجهة النشر: $root ($Target)"

# ── استدعاء السكريبت الأصلي مع معالجة الأخطاء ────────────────────────
Step 2 'تنفيذ النشر'

$originalScript = Join-Path (Split-Path $PSScriptRoot) "ci_deploy.ps1"
if (-not (Test-Path $originalScript)) {
    Error "ci_deploy.ps1 غير موجود"
    exit 1
}

$retryCount = 0
$success = $false

while ($retryCount -lt $MaxRetries -and -not $success) {
    try {
        $retryCount++
        if ($retryCount -gt 1) {
            Warn "محاولة $retryCount من $MaxRetries..."
            Log "محاولة $retryCount من $MaxRetries"
            Start-Sleep -Seconds (5 * $retryCount)  # انتظر قبل إعادة المحاولة
        }

        Info "تشغيل النشر..."
        & $originalScript `
            -Repo $Repo `
            -Tag $Tag `
            -RunId $RunId `
            -Version $Version `
            -Target $Target `
            -Token $Token `
            -SkipDb:$SkipDb `
            -MandatoryUpdate:$MandatoryUpdate

        $success = $true
        Ok "تم النشر بنجاح"
        Log "النشر: نجح"

    } catch {
        $errorMsg = $_.Exception.Message
        Log "خطأ في محاولة $retryCount: $errorMsg"

        if ($retryCount -lt $MaxRetries) {
            Warn "فشلت المحاولة $retryCount: $errorMsg"
        } else {
            Error "فشل النشر بعد $MaxRetries محاولات"
            Error "السبب: $errorMsg"
            Log "النشر: فشل - $errorMsg"
            exit 1
        }
    }
}

if ($success) {
    Info "حفظ السجل في: $logFile"
} else {
    Error "لم يتم إنجاز النشر"
    exit 1
}
