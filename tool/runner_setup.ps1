<#
.SYNOPSIS
    إعداد عدّاء GitHub Actions مستضاف ذاتياً على الخادم.
    
.DESCRIPTION
    ينشئ حسابات الخدمة والمجلدات المطلوبة، ويثبّت العدّاء.
    يُشغَّل مرة واحدة على الخادم.
    
.PARAMETER GitHubRepo
    المستودع (owner/repo)
    
.PARAMETER GitHubToken
    Personal Access Token مع صلاحيات admin:org_self_hosted_runner
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$GitHubRepo,
    [Parameter(Mandatory = $true)] [string]$GitHubToken
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }

Step 1 "إعداد حسابات الخدمة"

# حساب لتشغيل العدّاء
$runnerUser = 'GitHubRunner'
$runnerPassword = [System.Web.Security.Membership]::GeneratePassword(16, 2)

try {
    $user = Get-LocalUser -Name $runnerUser -ErrorAction SilentlyContinue
    if (-not $user) {
        New-LocalUser -Name $runnerUser -Password (ConvertTo-SecureString $runnerPassword -AsPlainText -Force) -FullName 'GitHub Actions Runner' -Description 'خدمة تشغيل العدّاء' -PasswordNeverExpires
        Ok "تم إنشاء حساب: $runnerUser"
    } else {
        Ok "حساب موجود: $runnerUser"
    }
    
    # أضفه لـ Administrators
    $group = [ADSI]'WinNT://./Administrators'
    $group.Add("WinNT://$env:COMPUTERNAME/$runnerUser") -ErrorAction SilentlyContinue
    Ok "تم إضافة الحساب لـ Administrators"
} catch {
    Warn "تعذّر إعداد الحساب: $_"
}

Step 2 "إنشاء المجلدات"

$runnerHome = 'C:\github-runner'
$runnerWork = Join-Path $runnerHome '_work'
$runnerTemp = Join-Path $runnerHome '_temp'

foreach ($dir in @($runnerHome, $runnerWork, $runnerTemp)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Ok "تم إنشاء: $dir"
    }
}

Step 3 "تحميل وتثبيت العدّاء"

$runnerVersion = '2.319.1'  # تحديث هذا الرقم عند وجود نسخة أحدث
$runnerZip = Join-Path $runnerHome "actions-runner-win-x64-$runnerVersion.zip"
$runnerUrl = "https://github.com/actions/runner/releases/download/v$runnerVersion/actions-runner-win-x64-$runnerVersion.zip"

if (-not (Test-Path $runnerZip)) {
    Invoke-WebRequest -Uri $runnerUrl -OutFile $runnerZip
    Ok "تم تحميل العدّاء: v$runnerVersion"
}

# فكّ الحزمة
Expand-Archive -LiteralPath $runnerZip -DestinationPath $runnerHome -Force
Ok "تم فكّ الحزمة"

Step 4 "تكوين العدّاء"

$runnerConfig = Join-Path $runnerHome 'config.cmd'
$owner, $repo = $GitHubRepo -split '/'

# السماح بتشغيل السكريبتات
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# تكوين العدّاء (غير تفاعلي)
& cmd.exe /c $runnerConfig --unattended --url "https://github.com/$GitHubRepo" --token $GitHubToken --name 'kinetic-server' --labels 'self-hosted,kinetic' --work '_work' --replace

if ($LASTEXITCODE -eq 0) {
    Ok "تم تكوين العدّاء"
} else {
    throw "فشل التكوين (رمز: $LASTEXITCODE)"
}

Step 5 "إعداد الخدمة"

$runnerPath = Join-Path $runnerHome 'run.cmd'
$serviceName = 'GitHubRunner'
$serviceDisplay = 'GitHub Actions Runner'

# حذف الخدمة إن وجدت
Get-Service -Name $serviceName -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
Remove-Service -Name $serviceName -ErrorAction SilentlyContinue

# إنشاء الخدمة
New-Service -Name $serviceName -DisplayName $serviceDisplay -BinaryPathName "cmd.exe /c $runnerPath" -StartupType Automatic -Credential (New-Object System.Management.Automation.PSCredential($runnerUser, (ConvertTo-SecureString $runnerPassword -AsPlainText -Force)))
Ok "تم إنشاء الخدمة: $serviceName"

# بدء الخدمة
Start-Service -Name $serviceName
Ok "تم بدء الخدمة"

Write-Host "`n✅ تمّ الإعداد بنجاح!" -ForegroundColor Green
Write-Host "   العدّاء يعمل الآن ويستقبل المهام من GitHub" -ForegroundColor Green
Write-Host "`n   لمراقبة الحالة:" -ForegroundColor Cyan
Write-Host "   Get-Service -Name $serviceName" -ForegroundColor Gray
Write-Host "   Get-EventLog -LogName System -Source 'Service Control Manager' -Newest 10" -ForegroundColor Gray

exit 0
