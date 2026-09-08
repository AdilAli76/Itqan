<#
.SYNOPSIS
    بناء النشرة ونسخها وتطبيقها على الفور

.DESCRIPTION
    1. بناء Backend (.NET)
    2. بناء Frontend (Flutter)
    3. نسخ الملفات المبنيّة إلى C:\kinetic-staging أو C:\kinetic
    4. تشغيل deploy_update.ps1

.PARAMETER Target
    staging أو production

.PARAMETER Version
    رقم النسخة المُراد نشرها

.PARAMETER SkipBuild
    تخطّي البناء — استخدم الملفات المبنيّة السابقة

.PARAMETER SkipDb
    تخطّي ترحيلات قاعدة البيانات

.EXAMPLE
    .\sync_and_deploy.ps1 -Target staging -Version "1.6.6"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('staging', 'production')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [switch]$SkipBuild = $false,
    [switch]$SkipDb = $false
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

# ────────────────────────────────────────────────────────────────────
# المسارات
# ────────────────────────────────────────────────────────────────────
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$backendDir = Join-Path $repoRoot 'backend'
$frontendDir = Join-Path $repoRoot 'frontend'
$deployPath = if ($Target -eq 'staging') { 'C:\kinetic-staging' } else { 'C:\kinetic' }

Write-Host ""
Write-Host "═══ بناء ونشر محليّ ═══" -ForegroundColor Cyan
Write-Host "الوجهة: $Target" -ForegroundColor Yellow
Write-Host "النسخة: $Version" -ForegroundColor Yellow
Write-Host "البناء: $($SkipBuild ? 'مخطّى' : 'سيتم')" -ForegroundColor Gray
Write-Host ""

# ────────────────────────────────────────────────────────────────────
# [1] بناء Backend
# ────────────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "[1] بناء Backend..." -ForegroundColor Yellow
    Push-Location $backendDir
    try {
        Write-Host "   تشغيل: dotnet publish -c Release" -ForegroundColor Gray
        & dotnet publish -c Release -o (Join-Path $backendDir 'bin' 'Release') 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ فشل البناء" -ForegroundColor Red
            exit 1
        }
        Write-Host "✅ Backend بُنيت بنجاح" -ForegroundColor Green
    } finally {
        Pop-Location
    }
    Write-Host ""
}

# ────────────────────────────────────────────────────────────────────
# [2] بناء Frontend (Flutter web)
# ────────────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    if (Test-Path $frontendDir) {
        Write-Host "[2] بناء Frontend..." -ForegroundColor Yellow
        Push-Location $frontendDir
        try {
            # التحقق من وجود Flutter
            $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
            if ($flutterCmd) {
                Write-Host "   تشغيل: flutter build web --release" -ForegroundColor Gray
                & flutter build web --release 2>&1 | Write-Host
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "⚠️  تحذير: فشل بناء Frontend" -ForegroundColor Yellow
                } else {
                    Write-Host "✅ Frontend بُنيت بنجاح" -ForegroundColor Green
                }
            } else {
                Write-Host "⚠️  تحذير: Flutter غير مثبت — تخطّي بناء Frontend" -ForegroundColor Yellow
            }
        } finally {
            Pop-Location
        }
    }
    Write-Host ""
}

# ────────────────────────────────────────────────────────────────────
# [3] نسخ الملفات إلى الوجهة
# ────────────────────────────────────────────────────────────────────
Write-Host "[3] نسخ الملفات..." -ForegroundColor Yellow

# Backend
$srcBackend = Join-Path $backendDir 'bin' 'Release'
$destBackend = Join-Path $deployPath 'backend'

if (Test-Path $srcBackend) {
    Write-Host "   Backend: $srcBackend → $destBackend" -ForegroundColor Gray
    if (-not (Test-Path $destBackend)) {
        New-Item -ItemType Directory -Path $destBackend -Force | Out-Null
    }
    Copy-Item -Path "$srcBackend\*" -Destination $destBackend -Recurse -Force | Out-Null
    Write-Host "   ✅ تم نسخ Backend" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Backend غير موجود: $srcBackend" -ForegroundColor Yellow
}

# Frontend (إن وجد)
$srcFrontend = Join-Path $frontendDir 'build' 'web'
$destFrontend = Join-Path $deployPath 'frontend'

if (Test-Path $srcFrontend) {
    Write-Host "   Frontend: $srcFrontend → $destFrontend" -ForegroundColor Gray
    if (-not (Test-Path $destFrontend)) {
        New-Item -ItemType Directory -Path $destFrontend -Force | Out-Null
    }
    Copy-Item -Path "$srcFrontend\*" -Destination $destFrontend -Recurse -Force | Out-Null
    Write-Host "   ✅ تم نسخ Frontend" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Frontend غير مبنيّة: $srcFrontend" -ForegroundColor Yellow
}

# appsettings
$srcSettings = Join-Path $backendDir 'appsettings.json'
if (Test-Path $srcSettings) {
    Copy-Item -Path $srcSettings -Destination $deployPath -Force | Out-Null
    Write-Host "   ✅ تم نسخ appsettings.json" -ForegroundColor Green
}

Write-Host ""

# ────────────────────────────────────────────────────────────────────
# [4] تشغيل النشر
# ────────────────────────────────────────────────────────────────────
Write-Host "[4] تشغيل deploy_update.ps1..." -ForegroundColor Yellow

$toolPath = Join-Path $deployPath 'tool'
$deployScript = Join-Path $toolPath 'deploy_update.ps1'

if (-not (Test-Path $deployScript)) {
    Write-Host "❌ الملف غير موجود: $deployScript" -ForegroundColor Red
    exit 1
}

$params = @{
    Version = $Version
    SkipDb = $SkipDb.IsPresent
}

try {
    & $deployScript @params
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ النشر نجح تماماً!" -ForegroundColor Green
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
