#!/usr/bin/env pwsh
<#
.SYNOPSIS
    بناء وتوزيع Kinetic ERP v1.6.6 بسهولة
.DESCRIPTION
    سكريبت PowerShell يقوم بـ:
    - بناء Backend
    - بناء Frontend
    - إنشاء حزمة نشر
.EXAMPLE
    .\build-v1.6.6.ps1
    .\build-v1.6.6.ps1 -SkipTests
    .\build-v1.6.6.ps1 -Backend
#>

param(
    [switch]$Backend,
    [switch]$Frontend,
    [switch]$SkipTests,
    [switch]$SkipWeb,
    [switch]$SkipDesktop
)

$ErrorActionPreference = "Stop"
$Version = "1.6.6"
$BuildDate = Get-Date -Format "yyyy-MM-dd_HHmm"

Write-Host "🚀 Kinetic ERP v$Version - Build Script" -ForegroundColor Green
Write-Host "=" * 50

# 1. التحضيرات
Write-Host "📋 فحص التحضيرات..." -ForegroundColor Cyan

if (-not (Test-Path "backend/KineticEnterprise.Api")) {
    Write-Host "❌ مجلد Backend غير موجود" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "❌ مجلد Frontend غير موجود" -ForegroundColor Red
    exit 1
}

Write-Host "✓ المشروع موجود" -ForegroundColor Green

# 2. بناء Backend
if ($Backend -or -not $Frontend) {
    Write-Host "`n🔨 بناء Backend..." -ForegroundColor Cyan

    try {
        cd backend/KineticEnterprise.Api

        Write-Host "  • استعيد الحزم..."
        dotnet restore --verbosity quiet

        Write-Host "  • البناء..."
        dotnet build --configuration Release --verbosity minimal

        if (-not $SkipTests) {
            Write-Host "  • الاختبارات..."
            dotnet test --configuration Release --verbosity minimal --no-build
        }

        Write-Host "  • النشر..."
        dotnet publish --configuration Release --output ../../bin/publish/backend --verbosity minimal

        Write-Host "✓ Backend جاهز" -ForegroundColor Green
        cd ../..
    } catch {
        Write-Host "❌ فشل بناء Backend: $_" -ForegroundColor Red
        exit 1
    }
}

# 3. بناء Frontend
if ($Frontend -or -not $Backend) {
    Write-Host "`n🎨 بناء Frontend..." -ForegroundColor Cyan

    try {
        Write-Host "  • استعيد الحزم..."
        flutter pub get --verbosity error

        if (-not $SkipWeb) {
            Write-Host "  • بناء Web..."
            flutter build web --release --build-name=$Version --build-number=1660 | Out-Null
            Write-Host "✓ Web جاهز" -ForegroundColor Green
        }

        if (-not $SkipDesktop) {
            Write-Host "  • بناء Desktop (Windows)..."
            flutter build windows --release | Out-Null
            Write-Host "✓ Desktop جاهز" -ForegroundColor Green
        }
    } catch {
        Write-Host "❌ فشل بناء Frontend: $_" -ForegroundColor Red
        exit 1
    }
}

# 4. إنشاء الحزمة
Write-Host "`n📦 إنشاء الحزمة..." -ForegroundColor Cyan

try {
    $PackageDir = "build/package/$Version"
    $ZipName = "kinetic_pkg_$BuildDate.zip"

    # إنشاء المجلدات
    if (Test-Path $PackageDir) {
        Remove-Item -Path $PackageDir -Recurse -Force
    }
    New-Item -Path $PackageDir -ItemType Directory -Force | Out-Null

    # نسخ Backend
    if (Test-Path "bin/publish/backend") {
        Write-Host "  • نسخ Backend..."
        Copy-Item -Path "bin/publish/backend/*" -Destination "$PackageDir" -Recurse -Force
    }

    # نسخ Frontend (Web)
    if (Test-Path "build/web" -and -not $SkipWeb) {
        Write-Host "  • نسخ Web..."
        $wwwrootPath = "$PackageDir/wwwroot"
        Remove-Item -Path $wwwrootPath -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "build/web" -Destination $wwwrootPath -Recurse
    }

    # نسخ Desktop
    if (Test-Path "build/windows/x64/runner/Release" -and -not $SkipDesktop) {
        Write-Host "  • نسخ Desktop..."
        Copy-Item -Path "build/windows/x64/runner/Release/*" -Destination "$PackageDir/desktop" -Recurse
    }

    # نسخ Database
    Write-Host "  • نسخ Database Migration..."
    Copy-Item -Path "docs/MIGRATIONS_1.6.6.sql" -Destination "$PackageDir/"
    Copy-Item -Path "docs/V1.6.6_MIGRATION_GUIDE.md" -Destination "$PackageDir/"

    # نسخ Scripts
    Write-Host "  • نسخ Deployment Scripts..."
    Copy-Item -Path "tool/deploy-now.ps1" -Destination "$PackageDir/" -Force

    # ضغط
    Write-Host "  • ضغط الملفات..."
    if (Test-Path "build/package/$ZipName") {
        Remove-Item "build/package/$ZipName"
    }

    Compress-Archive -Path "$PackageDir" -DestinationPath "build/package/$ZipName" -Force

    $ZipSize = (Get-Item "build/package/$ZipName").Length / 1MB
    Write-Host "✓ تم الضغط بنجاح ($([Math]::Round($ZipSize, 1)) MB)" -ForegroundColor Green

    # الحساب
    $Hash = (Get-FileHash "build/package/$ZipName" -Algorithm SHA256).Hash
    "SHA256: $Hash" | Out-File -Path "build/package/$ZipName.sha256" -Force

} catch {
    Write-Host "❌ فشل الضغط: $_" -ForegroundColor Red
    exit 1
}

# 5. النتيجة النهائية
Write-Host "`n" -ForegroundColor Green
Write-Host "✅ البناء اكتمل بنجاح!" -ForegroundColor Green
Write-Host "=" * 50
Write-Host "📦 الحزمة جاهزة في:"
Write-Host "   build/package/$ZipName"
Write-Host "`n📊 الملفات المرفقة:"
Write-Host "   ✓ Backend .NET"
Write-Host "   ✓ Frontend Web"
if (-not $SkipDesktop) { Write-Host "   ✓ Desktop (Windows)" }
Write-Host "   ✓ Database Migration"
Write-Host "   ✓ Deployment Scripts"
Write-Host "`n🚀 للنشر على الخادم:"
Write-Host "   1. انسخ $ZipName إلى الخادم"
Write-Host "   2. طبق الهجرة: MIGRATIONS_1.6.6.sql"
Write-Host "   3. شغّل: .\deploy-now.ps1 -Target staging -Version $Version"
Write-Host "=" * 50
Write-Host "🎉 جاهز للنشر!" -ForegroundColor Green
