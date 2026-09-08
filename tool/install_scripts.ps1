<#
.SYNOPSIS
    تثبيت ملفات النشر من ZIP على السيرفر

.DESCRIPTION
    فك ضغط deploy-scripts.zip وتثبيت الملفات في:
    - C:\kinetic-staging\tool\
    - C:\kinetic\tool\

.PARAMETER ZipPath
    مسار ملف ZIP (مثال: C:\Temp\deploy-scripts.zip)

.PARAMETER Target
    staging أو production أو both

.EXAMPLE
    .\install_scripts.ps1 -ZipPath "C:\Temp\deploy-scripts.zip" -Target staging
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('staging', 'production', 'both')]
    [string]$Target = 'both'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

# ────────────────────────────────────────────────────────────────────
# التحقق من ZIP
# ────────────────────────────────────────────────────────────────────
if (-not (Test-Path $ZipPath)) {
    Write-Host "❌ ملف ZIP غير موجود: $ZipPath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "═══ تثبيت ملفات النشر ═══" -ForegroundColor Cyan
Write-Host "الملف: $ZipPath" -ForegroundColor Yellow
Write-Host "الوجهات: $Target" -ForegroundColor Yellow
Write-Host ""

# ────────────────────────────────────────────────────────────────────
# فك الضغط
# ────────────────────────────────────────────────────────────────────
$tempPath = Join-Path $env:TEMP "deploy-scripts-$(Get-Random)"
Write-Host "[1] فك الضغط..." -ForegroundColor Yellow

try {
    Expand-Archive -Path $ZipPath -DestinationPath $tempPath -Force
    Write-Host "✅ تم فك الضغط في: $tempPath" -ForegroundColor Green
} catch {
    Write-Host "❌ خطأ في فك الضغط: $_" -ForegroundColor Red
    exit 1
}

# ────────────────────────────────────────────────────────────────────
# التثبيت
# ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2] نسخ الملفات..." -ForegroundColor Yellow

$paths = @()
if ($Target -eq 'staging' -or $Target -eq 'both') {
    $paths += 'C:\kinetic-staging'
}
if ($Target -eq 'production' -or $Target -eq 'both') {
    $paths += 'C:\kinetic'
}

foreach ($path in $paths) {
    Write-Host ""
    Write-Host "   → $path" -ForegroundColor Gray

    # التحقق من المسار
    if (-not (Test-Path $path)) {
        Write-Host "      ⚠️  المسار غير موجود — تخطّي" -ForegroundColor Yellow
        continue
    }

    # نسخ tool/
    $toolSrc = Join-Path $tempPath 'tool'
    $toolDest = Join-Path $path 'tool'

    if (Test-Path $toolSrc) {
        if (-not (Test-Path $toolDest)) {
            New-Item -ItemType Directory -Path $toolDest -Force | Out-Null
        }

        Get-ChildItem -Path $toolSrc -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $toolDest -Force
            Write-Host "      ✅ نُسخ: $($_.Name)" -ForegroundColor Green
        }
    }

    # نسخ DEPLOY_LOCAL.md
    $mdSrc = Join-Path $tempPath 'DEPLOY_LOCAL.md'
    if (Test-Path $mdSrc) {
        Copy-Item -Path $mdSrc -Destination $path -Force
        Write-Host "      ✅ نُسخ: DEPLOY_LOCAL.md" -ForegroundColor Green
    }
}

# ────────────────────────────────────────────────────────────────────
# التنظيف
# ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3] التنظيف..." -ForegroundColor Yellow
Remove-Item -Path $tempPath -Recurse -Force
Write-Host "✅ تم حذف الملفات المؤقتة" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# الملخص
# ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══ تمّ التثبيت بنجاح ═══" -ForegroundColor Green
Write-Host ""
Write-Host "الخطوة التالية:" -ForegroundColor Yellow
Write-Host "  cd C:\kinetic-staging\tool" -ForegroundColor Gray
Write-Host "  .\sync_and_deploy.ps1 -Target staging -Version 'v1.6.6'" -ForegroundColor Gray
Write-Host ""
