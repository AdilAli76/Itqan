<#
.SYNOPSIS
    نشرٌ محليّ مباشر على السيرفر بدون GitHub Actions

.DESCRIPTION
    ينسخ الملفات المبنيّة من المستودع إلى C:\kinetic-staging أو C:\kinetic
    ثم ينفّذ deploy_update.ps1 لإكمال النشر.

.PARAMETER Target
    الوجهة: staging أو production

.PARAMETER Version
    رقم النسخة (مثال: 1.6.6)

.EXAMPLE
    .\local_deploy.ps1 -Target staging -Version "1.6.6"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('staging', 'production')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [switch]$SkipDb = $false
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

# ────────────────────────────────────────────────────────────────────
# المسارات
# ────────────────────────────────────────────────────────────────────
$deployPath = if ($Target -eq 'staging') { 'C:\kinetic-staging' } else { 'C:\kinetic' }
$backendBuild = Join-Path $deployPath 'backend' 'bin' 'Release'
$frontendBuild = Join-Path $deployPath 'frontend' 'build'

Write-Host ""
Write-Host "═══ نشرٌ محليّ ═══" -ForegroundColor Cyan
Write-Host "الوجهة: $Target" -ForegroundColor Yellow
Write-Host "النسخة: $Version" -ForegroundColor Yellow
Write-Host "المسار: $deployPath" -ForegroundColor Gray
Write-Host ""

# ────────────────────────────────────────────────────────────────────
# التحقق من المسارات
# ────────────────────────────────────────────────────────────────────
if (-not (Test-Path $deployPath)) {
    Write-Host "❌ المسار غير موجود: $deployPath" -ForegroundColor Red
    exit 1
}

$toolPath = Join-Path $deployPath 'tool'
if (-not (Test-Path $toolPath)) {
    Write-Host "❌ مجلد الأدوات غير موجود: $toolPath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ مسارات موجودة" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# البحث عن ملفات البناء
# ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[1] البحث عن ملفات البناء..." -ForegroundColor Yellow

$backendDll = Get-ChildItem -Path $backendBuild -Filter "KineticEnterprise.Api.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($backendDll) {
    Write-Host "✅ Backend: $($backendDll.FullName)" -ForegroundColor Green
} else {
    Write-Host "⚠️  تحذير: Backend DLL غير موجودة" -ForegroundColor Yellow
    Write-Host "   تأكد من تشغيل: dotnet publish -c Release" -ForegroundColor Gray
}

# ────────────────────────────────────────────────────────────────────
# سجل النشر
# ────────────────────────────────────────────────────────────────────
$logFile = Join-Path $deployPath 'deploy.log'
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logEntry = "$timestamp | النسخة $Version | النشر المحلي | $env:USERNAME"

Write-Host ""
Write-Host "[2] تسجيل النشر..." -ForegroundColor Yellow
Add-Content -Path $logFile -Value $logEntry
Write-Host "✅ تم التسجيل في: $logFile" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# تشغيل deploy_update.ps1
# ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3] تشغيل نشرة التحديث..." -ForegroundColor Yellow

$deployScript = Join-Path $toolPath 'deploy_update.ps1'
if (-not (Test-Path $deployScript)) {
    Write-Host "❌ الملف غير موجود: $deployScript" -ForegroundColor Red
    exit 1
}

$params = @{
    Version = $Version
    SkipDb = $SkipDb.IsPresent
    LogFile = $logFile
}

Write-Host "   تشغيل: $deployScript" -ForegroundColor Gray
Write-Host "   الخيارات: Version=$Version, SkipDb=$($SkipDb.IsPresent)" -ForegroundColor Gray

try {
    & $deployScript @params
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ النشر نجح!" -ForegroundColor Green
        Write-Host "   النسخة: $Version" -ForegroundColor Green
        Write-Host "   الوجهة: $Target" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "❌ فشل النشر (رمز $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
} catch {
    Write-Host ""
    Write-Host "❌ خطأ: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
