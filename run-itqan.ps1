# Itqan ERP Desktop — سكربت التشغيل
# يشغّل التطبيق والـ Backend بسهولة

param(
  [Parameter(Position=0)]
  [ValidateSet("app", "web", "backend", "all", "build", "build-windows", "build-web")]
  [string]$Action = "app"
)

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendPath = "$projectRoot\backend\KineticEnterprise.Api"
$exePath = "$projectRoot\build\windows\x64\runner\Release\kinetic_enterprise.exe"

function Show-Menu {
  Clear-Host
  Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
  Write-Host "   منظومة إتقان ERP — قائمة التشغيل" -ForegroundColor Yellow
  Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
  Write-Host "1. تشغيل التطبيق الديسكتوب فقط (Desktop)" -ForegroundColor Green
  Write-Host "2. تشغيل Backend فقط (.NET)" -ForegroundColor Green
  Write-Host "3. تشغيل الويب (Web in Chrome)" -ForegroundColor Green
  Write-Host "4. تشغيل الكل معاً (App + Backend)" -ForegroundColor Magenta
  Write-Host "5. بناء نسخة Windows Desktop" -ForegroundColor Cyan
  Write-Host "6. بناء نسخة الويب" -ForegroundColor Cyan
  Write-Host "7. بناء الكل" -ForegroundColor Cyan
  Write-Host "0. خروج`n" -ForegroundColor Gray
}

function Run-Desktop {
  Write-Host "`n🚀 تشغيل التطبيق الديسكتوب...`n" -ForegroundColor Green

  if (-not (Test-Path $exePath)) {
    Write-Host "❌ ملف التطبيق غير موجود: $exePath" -ForegroundColor Red
    Write-Host "   اختر 'بناء Windows Desktop' أولاً" -ForegroundColor Yellow
    Read-Host "اضغط Enter للعودة"
    return
  }

  Set-Location "$projectRoot\build\windows\x64\runner\Release"
  Write-Host "✅ تشغيل: $([System.IO.Path]::GetFileName($exePath))`n" -ForegroundColor Green
  & .\kinetic_enterprise.exe
}

function Run-Backend {
  Write-Host "`n⚙️  تشغيل Backend (.NET)...`n" -ForegroundColor Green

  if (-not (Test-Path "$backendPath\appsettings.json")) {
    Write-Host "❌ ملف appsettings.json غير موجود" -ForegroundColor Red
    Write-Host "   تأكد من وجود: $backendPath\appsettings.json" -ForegroundColor Yellow
    Read-Host "اضغط Enter للعودة"
    return
  }

  Write-Host "⚠️  تأكد من:`n" -ForegroundColor Yellow
  Write-Host "   • تشغيل SQL Server`n" -ForegroundColor Gray
  Write-Host "   • تنفيذ DATABASE_SCHEMA_SQLSERVER.sql`n" -ForegroundColor Gray
  Write-Host "   • صحة بيانات appsettings.json`n" -ForegroundColor Gray

  Set-Location $backendPath
  Write-Host "✅ تشغيل Backend على: https://localhost:5001`n" -ForegroundColor Green
  dotnet run
}

function Run-Web {
  Write-Host "`n🌐 تشغيل الويب في Chrome...`n" -ForegroundColor Green
  Set-Location $projectRoot

  Write-Host "✅ اضغط Ctrl+C لإيقاف الخادم`n" -ForegroundColor Yellow
  flutter run -d chrome
}

function Run-Both {
  Write-Host "`n🔄 تشغيل Desktop + Backend معاً...`n" -ForegroundColor Magenta
  Write-Host "⚠️  سيتم فتح نافذتي PowerShell جديدتين:`n" -ForegroundColor Yellow
  Write-Host "   1. للـ Backend (.NET)`n"
  Write-Host "   2. للتطبيق الديسكتوب`n"

  $backendCmd = "`$backendPath = '$backendPath'; Set-Location `$backendPath; dotnet run"
  $appCmd = "`$exePath = '$exePath'; `$releaseDir = Split-Path `$exePath; Set-Location `$releaseDir; & .\kinetic_enterprise.exe"

  Write-Host "▶ بدء Backend..." -ForegroundColor Cyan
  Start-Process powershell -ArgumentList "-NoExit", "-Command", $backendCmd

  Start-Sleep -Seconds 3

  Write-Host "▶ بدء Desktop App..." -ForegroundColor Cyan
  Start-Process powershell -ArgumentList "-NoExit", "-Command", $appCmd

  Write-Host "`n✅ تم فتح النافذتين!`n" -ForegroundColor Green
  Read-Host "اضغط Enter للعودة"
}

function Build-Windows {
  Write-Host "`n🔨 بناء نسخة Windows Desktop...`n" -ForegroundColor Cyan
  Set-Location $projectRoot

  Write-Host "⏳ هذا قد يستغرق 10-20 دقيقة...`n" -ForegroundColor Yellow
  flutter build windows --release

  if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ تم البناء بنجاح!`n" -ForegroundColor Green
    Write-Host "📦 الملف: $exePath`n" -ForegroundColor Green
  } else {
    Write-Host "`n❌ فشل البناء`n" -ForegroundColor Red
  }

  Read-Host "اضغط Enter للعودة"
}

function Build-Web {
  Write-Host "`n🌐 بناء نسخة الويب...`n" -ForegroundColor Cyan
  Set-Location $projectRoot

  Write-Host "⏳ هذا قد يستغرق 5-10 دقائق...`n" -ForegroundColor Yellow
  flutter build web --release

  if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ تم البناء بنجاح!`n" -ForegroundColor Green
    Write-Host "📂 المجلد: $projectRoot\build\web`n" -ForegroundColor Green
  } else {
    Write-Host "`n❌ فشل البناء`n" -ForegroundColor Red
  }

  Read-Host "اضغط Enter للعودة"
}

function Build-All {
  Write-Host "`n🔨 بناء Windows Desktop...`n" -ForegroundColor Cyan
  Set-Location $projectRoot
  flutter build windows --release

  if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Windows: تم البناء بنجاح!`n" -ForegroundColor Green
  } else {
    Write-Host "`n❌ Windows: فشل البناء`n" -ForegroundColor Red
    return
  }

  Write-Host "`n🌐 بناء الويب...`n" -ForegroundColor Cyan
  flutter build web --release

  if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Web: تم البناء بنجاح!`n" -ForegroundColor Green
  } else {
    Write-Host "`n❌ Web: فشل البناء`n" -ForegroundColor Red
  }

  Read-Host "اضغط Enter للعودة"
}

# Main loop
do {
  if ([string]::IsNullOrEmpty($Action) -or $Action -eq "interactive") {
    Show-Menu
    $choice = Read-Host "اختر خياراً"
    $Action = $choice
  }

  switch ($Action) {
    "app" { Run-Desktop; break }
    "1" { Run-Desktop; break }
    "backend" { Run-Backend; break }
    "2" { Run-Backend; break }
    "web" { Run-Web; break }
    "3" { Run-Web; break }
    "all" { Run-Both; break }
    "4" { Run-Both; break }
    "build-windows" { Build-Windows; break }
    "5" { Build-Windows; break }
    "build-web" { Build-Web; break }
    "6" { Build-Web; break }
    "build" { Build-All; break }
    "7" { Build-All; break }
    "0" { exit }
    default {
      Write-Host "❌ اختيار غير صحيح" -ForegroundColor Red
      Read-Host "اضغط Enter"
      $Action = ""
    }
  }
} while ($true)
