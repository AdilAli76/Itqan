<#
.SYNOPSIS
    صيانة وإعداد GitHub Actions Runner على السيرفر.

.DESCRIPTION
    يتحقق من جاهزية العداء وينسخ ملفات tool/ من GitHub
    تلقائياً عند الحاجة.

.PARAMETER Repository
    اسم المستودع (مثال: adilmohamed76-hub/kinetic-erp)

.PARAMETER RunnerPath
    مسار مجلد العداء (مثال: C:\actions-runner)

.EXAMPLE
    .\runner_maintenance.ps1 -Repository adilmohamed76-hub/kinetic-erp -RunnerPath C:\actions-runner
#>

[CmdletBinding()]
param(
    [string]$Repository = 'adilmohamed76-hub/kinetic-erp',
    [string]$RunnerPath = 'C:\actions-runner',
    [string]$StagingPath = 'C:\kinetic-staging',
    [string]$ProductionPath = 'C:\kinetic'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    ✅ $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    ⚠️  $t" -ForegroundColor Yellow }
function Error($t) { Write-Host "    ❌ $t" -ForegroundColor Red }
function Info($t) { Write-Host "    ℹ️  $t" -ForegroundColor Gray }

Step 0 'تحقق من متطلبات الصيانة'

# ── التحقق من المدير ────────────────────────────────────────────────
function Test-Admin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Error 'شغّل PowerShell كمسؤول'
    exit 1
}
Ok 'شغّل كمسؤول'

# ── التحقق من الاتصال ────────────────────────────────────────────────
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$connected = $false
try {
    $response = Invoke-WebRequest -Uri "https://github.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
    $connected = $response.StatusCode -eq 200
} catch { }

if (-not $connected) {
    Warn "لا اتصال بـ GitHub — سيتم التخطي"
} else {
    Ok 'اتصال بـ GitHub'
}

# ── دالة نسخ ملفات tool/ ──────────────────────────────────────────────
function Sync-ToolsFromGitHub {
    param([string]$TargetPath, [string]$Label)

    if (-not (Test-Path $TargetPath)) {
        Info "$Label: المجلد غير موجود، تخطّ"
        return
    }

    $toolPath = Join-Path $TargetPath 'tool'
    if (-not (Test-Path $toolPath)) {
        New-Item -ItemType Directory -Path $toolPath -Force | Out-Null
        Info "$Label: تم إنشاء مجلد tool"
    }

    $tools = @("ci_deploy.ps1", "ci_deploy_enhanced.ps1", "deploy_update.ps1", "backup.ps1", "api_test.ps1")
    $githubUrl = "https://raw.githubusercontent.com/$Repository/main/tool"
    $updated = 0

    foreach ($tool in $tools) {
        try {
            $toolFilePath = Join-Path $toolPath $tool
            $url = "$githubUrl/$tool"

            # الحصول على آخر تعديل على GitHub
            $headResponse = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction SilentlyContinue
            $remoteModified = [datetime]$headResponse.Headers['Last-Modified']

            # التحقق من وجود الملف محلياً وتاريخ آخر تعديل
            if (Test-Path $toolFilePath) {
                $localModified = (Get-Item $toolFilePath).LastWriteTime
                if ($remoteModified -le $localModified) {
                    continue  # الملف محدّث
                }
            }

            Info "$Label: تحديث $tool..."
            Invoke-WebRequest -Uri $url -OutFile $toolFilePath -UseBasicParsing -ErrorAction Stop
            $updated++
            Ok "$Label: تم $tool"

        } catch {
            Warn "$Label: فشل تحديث $tool — $_"
        }
    }

    if ($updated -gt 0) {
        Ok "$Label: تم تحديث $updated ملفات"
    } else {
        Info "$Label: جميع الملفات محدّثة"
    }
}

# ── نسخ الملفات ────────────────────────────────────────────────────────
if ($connected) {
    Step 1 'نسخ ملفات tool/ من GitHub'

    Sync-ToolsFromGitHub -TargetPath $StagingPath -Label 'Staging'
    Sync-ToolsFromGitHub -TargetPath $ProductionPath -Label 'Production'
}

# ── التحقق من خدمة العداء ────────────────────────────────────────────
Step 2 'التحقق من خدمة العداء'

$runnerService = Get-CimInstance Win32_Service -Filter "Name LIKE 'actions.runner%'" | Select-Object -First 1

if ($runnerService) {
    Ok "خدمة العداء: $($runnerService.Name)"
    Info "الحالة: $($runnerService.State)"
    Info "الحساب: $($runnerService.StartName)"

    if ($runnerService.State -ne 'Running') {
        Warn 'الخدمة متوقفة — تشغيل...'
        try {
            Start-Service $runnerService.Name -ErrorAction Stop
            Ok 'تم تشغيل الخدمة'
        } catch {
            Error "فشل تشغيل الخدمة: $_"
        }
    }
} else {
    Warn 'خدمة العداء غير مثبتة'
    Info 'شغّل runner_setup.ps1 لتثبيت العداء'
}

# ── معلومات النشر ────────────────────────────────────────────────────
Step 3 'معلومات النشر'

$deployLog = Join-Path $StagingPath 'deploy.log'
if (Test-Path $deployLog) {
    $lastDeploy = Get-Content $deployLog -Tail 1
    Info "آخر نشر على Staging: $lastDeploy"
} else {
    Info 'لا توجد عمليات نشر على Staging حتى الآن'
}

Write-Host ""
Ok 'اكتملت الصيانة'
Write-Host ""
