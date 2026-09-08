<#
.SYNOPSIS
    فحص بيئة النشر والملفات المطلوبة على السيرفر
#>

$ErrorActionPreference = 'Continue'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Check-Path($path, $description) {
    if (Test-Path $path) {
        Write-Host "✅ $description" -ForegroundColor Green
        Write-Host "   $path" -ForegroundColor Gray
        return $true
    } else {
        Write-Host "❌ $description" -ForegroundColor Red
        Write-Host "   $path" -ForegroundColor Gray
        return $false
    }
}

function Check-File($path, $description) {
    if (Test-Path $path -PathType Leaf) {
        $size = (Get-Item $path).Length / 1KB
        Write-Host "✅ $description ($([math]::Round($size, 1)) KB)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ $description" -ForegroundColor Red
        Write-Host "   $path" -ForegroundColor Gray
        return $false
    }
}

Write-Host ""
Write-Host "═══ فحص بيئة النشر ═══" -ForegroundColor Cyan
Write-Host ""

# ── المسارات الأساسية ───────────────────────────────────────────────────
Write-Host "[1] المسارات الأساسية:" -ForegroundColor Yellow
$paths = @(
    @{Path = 'C:\kinetic-staging'; Desc = 'مجلد بيئة التجربة'},
    @{Path = 'C:\kinetic'; Desc = 'مجلد بيئة الإنتاج'},
    @{Path = 'C:\kinetic-staging\tool'; Desc = 'مجلد أدوات التجربة'},
    @{Path = 'C:\kinetic\tool'; Desc = 'مجلد أدوات الإنتاج'},
    @{Path = 'C:\kinetic-staging\backend'; Desc = 'بيئة التجربة - Backend'},
    @{Path = 'C:\kinetic\backend'; Desc = 'بيئة الإنتاج - Backend'}
)
$pathsOk = 0
foreach ($p in $paths) {
    if (Check-Path $p.Path $p.Desc) { $pathsOk++ }
}
Write-Host "   النتيجة: $pathsOk / $($paths.Count) ✓" -ForegroundColor Gray
Write-Host ""

# ── ملفات النشر المطلوبة ──────────────────────────────────────────────────
Write-Host "[2] ملفات النشر المطلوبة:" -ForegroundColor Yellow
$files = @(
    @{Path = 'C:\kinetic-staging\tool\deploy_update.ps1'; Desc = 'deploy_update.ps1 (Staging)'},
    @{Path = 'C:\kinetic-staging\tool\backup.ps1'; Desc = 'backup.ps1 (Staging)'},
    @{Path = 'C:\kinetic-staging\tool\ci_deploy.ps1'; Desc = 'ci_deploy.ps1 (Staging)'},
    @{Path = 'C:\kinetic\tool\deploy_update.ps1'; Desc = 'deploy_update.ps1 (Production)'},
    @{Path = 'C:\kinetic\tool\backup.ps1'; Desc = 'backup.ps1 (Production)'},
    @{Path = 'C:\kinetic\tool\ci_deploy.ps1'; Desc = 'ci_deploy.ps1 (Production)'}
)
$filesOk = 0
foreach ($f in $files) {
    if (Check-File $f.Path $f.Desc) { $filesOk++ }
}
Write-Host "   النتيجة: $filesOk / $($files.Count) ✓" -ForegroundColor Gray
Write-Host ""

# ── تثبيت البرامج المطلوبة ────────────────────────────────────────────────
Write-Host "[3] البرامج والخدمات:" -ForegroundColor Yellow
try {
    $dotnet = dotnet --version
    Write-Host "✅ .NET: $dotnet" -ForegroundColor Green
} catch {
    Write-Host "❌ .NET غير مثبت" -ForegroundColor Red
}

try {
    $runnerService = Get-CimInstance Win32_Service -Filter "Name LIKE 'actions.runner%'" | Select-Object -First 1
    if ($runnerService) {
        $state = $runnerService.State
        $stateColor = if ($state -eq 'Running') { 'Green' } else { 'Red' }
        Write-Host "✅ GitHub Actions Runner: $state" -ForegroundColor $stateColor
        Write-Host "   الخدمة: $($runnerService.Name)" -ForegroundColor Gray
        Write-Host "   الحساب: $($runnerService.StartName)" -ForegroundColor Gray
    } else {
        Write-Host "❌ GitHub Actions Runner غير مثبت" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ خطأ في فحص خدمة Runner: $_" -ForegroundColor Red
}
Write-Host ""

# ── قاعدة البيانات ──────────────────────────────────────────────────────
Write-Host "[4] قاعدة البيانات:" -ForegroundColor Yellow
try {
    $connStr = "Server=.\SQLEXPRESS;Database=master;Integrated Security=true;"
    $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
    $conn.Open()
    Write-Host "✅ اتصال قاعدة البيانات: نجح" -ForegroundColor Green
    $conn.Close()
} catch {
    Write-Host "⚠️  اتصال قاعدة البيانات: $_" -ForegroundColor Yellow
}
Write-Host ""

# ── ملف الإعدادات ───────────────────────────────────────────────────────
Write-Host "[5] ملفات الإعدادات:" -ForegroundColor Yellow
if (Check-File 'C:\kinetic-staging\backend\appsettings.Production.json' 'appsettings.Production.json (Staging)') {
    try {
        $cfg = Get-Content 'C:\kinetic-staging\backend\appsettings.Production.json' -Raw | ConvertFrom-Json
        if ($cfg.Storage -and $cfg.Storage.Path) {
            Write-Host "✅ مسار المرفقات: $($cfg.Storage.Path)" -ForegroundColor Green
        } else {
            Write-Host "⚠️  مسار المرفقات غير محدد (سيُستخدم المسار الافتراضي)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️  خطأ في قراءة الإعدادات: $_" -ForegroundColor Yellow
    }
}
Write-Host ""

# ── سجل النشر ──────────────────────────────────────────────────────────
Write-Host "[6] سجل النشر:" -ForegroundColor Yellow
if (Test-Path 'C:\kinetic-staging\deploy.log') {
    $lastLines = Get-Content 'C:\kinetic-staging\deploy.log' -Tail 5
    Write-Host "✅ موجود — آخر 5 نشرات:" -ForegroundColor Green
    foreach ($line in $lastLines) {
        Write-Host "   $line" -ForegroundColor Gray
    }
} else {
    Write-Host "⚠️  السجل غير موجود (أول نشر على التجربة)" -ForegroundColor Yellow
}
Write-Host ""

# ── الملخص ──────────────────────────────────────────────────────────────
Write-Host "═══ الملخص ═══" -ForegroundColor Cyan
if ($pathsOk -eq $paths.Count -and $filesOk -eq $files.Count) {
    Write-Host "✅ البيئة جاهزة للنشر!" -ForegroundColor Green
} else {
    Write-Host "⚠️  هناك مشاكل تحتاج إلى حل:" -ForegroundColor Red
    Write-Host "   - المسارات: $pathsOk/$($paths.Count)" -ForegroundColor Gray
    Write-Host "   - الملفات: $filesOk/$($files.Count)" -ForegroundColor Gray
}
Write-Host ""
