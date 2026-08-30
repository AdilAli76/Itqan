<#
.SYNOPSIS
    يثبّت عدّاء GitHub Actions على الخادم — الطرف الذي ينفّذ النشر.

.DESCRIPTION
    بعده يصير النشر زرّاً في المتصفّح بدل أربع خطوات على جهازين: يُبنى في
    السحابة، ويُنزَّل هنا، ويُرقَّى بـ deploy_update.ps1 — بلا سطح مكتب
    بعيد ولا نسخ ملفات ولا احتمال أن تُنشر حزمة الأمس.

    ولا يُفتح أي منفذ: العدّاء هو من يتّصل بـGitHub صادراً ويسأل «هل من
    عمل؟» — فلا مدخل جديد إلى الخادم.

    ⚠ ومن يملك الدفع إلى المستودع يملك تنفيذ أوامر على هذا الخادم. هذا
    ثمن النشر بزرّ، ويُقبَل لأن المستودع خاصّ ومطوّره واحد. فإن دخل شريك
    يوماً، فالنقاش يبدأ من هنا لا من ذاك اليوم.

.PARAMETER Token
    رمز التسجيل من:
      Settings ← Actions ← Runners ← New self-hosted runner ← Windows
    وهو صالح ساعةً واحدة. ليس رمز وصولٍ شخصياً ولا يُحفَظ في أي ملف.

.EXAMPLE
    .\runner_setup.ps1 -Token AXXXXXX...
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Token,
    [string]$Repository = 'adilmohamed76-hub/kinetic-erp',
    [string]$Path = 'C:\actions-runner',
    [string]$Name = "kinetic-$env:COMPUTERNAME",
    # الوسوم التي يختار بها سير النشر هذا العدّاء — راجع
    # ‏.github/workflows/deploy.yml (runs-on).
    [string]$Labels = 'self-hosted,windows,kinetic',
    [string]$Version = '2.328.0'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) { throw 'شغّل PowerShell كمسؤول — تثبيت خدمة ويندوز يحتاج ذلك.' }

Write-Host ""
Write-Host "  عدّاء النشر لـ $Repository" -ForegroundColor White
Write-Host "    المسار : $Path"
Write-Host "    الاسم  : $Name"
Write-Host "    الوسوم : $Labels"

# ── 1. التنزيل ──────────────────────────────────────────────────────────
Step 1 'تنزيل العدّاء'
if (Test-Path (Join-Path $Path 'config.cmd')) {
    Ok 'العدّاء منزَّل مسبقاً — يُعاد ضبطه فقط.'
} else {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    $zip = Join-Path $env:TEMP "actions-runner-$Version.zip"
    $url = "https://github.com/actions/runner/releases/download/v$Version/actions-runner-win-x64-$Version.zip"
    # TLS 1.2 صراحةً: ويندوز سيرفر القديم يتفاوض 1.0 افتراضاً فيردّ GitHub
    # بقطعٍ للاتصال بلا رسالة مفهومة.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $Path -Force
    Remove-Item $zip -Force
    Ok "نُزِّل وفُكَّ في $Path"
}

# ── 2. الضبط ────────────────────────────────────────────────────────────
Step 2 'تسجيل العدّاء'

# تسجيلٌ سابق يُزال أولاً: config.cmd يفشل على مجلد مضبوط، ورسالتُه
# «already configured» تُقرأ خطأً على أنها نجاح.
if (Test-Path (Join-Path $Path '.runner')) {
    Warn 'يوجد تسجيل سابق — يُزال.'
    & (Join-Path $Path 'config.cmd') remove --token $Token
}

# ⚠ الخدمة تعمل بحساب مسؤول لا بـNETWORK SERVICE الافتراضي.
#
# لأن deploy_update.ps1 يوقف موقع IIS ويستبدل ملفات C:\kinetic — وكلاهما
# ممنوع على الحساب الافتراضي. وبدون هذا ينجح التسجيل، ثم تفشل أول نشرة
# بـ«Access denied» في منتصف الاستبدال: الموقع متوقّف والملفات نصفها.
#
# ويطلب config.cmd الحساب وكلمته تفاعلياً — لا تُمرَّر في سطر أوامر يُحفَظ
# في سجلّ الأوامر.
Push-Location $Path
try {
    & .\config.cmd --unattended --replace `
        --url "https://github.com/$Repository" `
        --token $Token --name $Name --labels $Labels `
        --work '_work' --runasservice
    if ($LASTEXITCODE -ne 0) { throw "فشل التسجيل (رمز $LASTEXITCODE) — تأكّد أن الرمز لم تمضِ عليه ساعة." }
} finally { Pop-Location }
Ok 'مسجَّل ومثبَّت كخدمة'

# ── 3. صلاحية الخدمة ────────────────────────────────────────────────────
Step 3 'حساب تشغيل الخدمة'
$svc = Get-CimInstance Win32_Service -Filter "Name LIKE 'actions.runner%'" | Select-Object -First 1
if ($svc) {
    Ok "الخدمة: $($svc.Name)"
    Write-Host "    الحساب: $($svc.StartName)" -ForegroundColor Gray
    if ($svc.StartName -match 'NETWORK SERVICE|LocalService') {
        Warn 'الحساب الافتراضي لا يملك إيقاف IIS ولا الكتابة في C:\kinetic.'
        Warn 'غيّره إلى حساب مسؤول من services.msc ← خصائص ← Log On، ثم أعد تشغيل الخدمة.'
    }
    if ($svc.State -ne 'Running') { Start-Service $svc.Name; Ok 'شُغِّلت' }
} else {
    Warn 'لم تُعثر خدمة العدّاء — راجع مخرجات الضبط أعلاه.'
}

Write-Host ""
Write-Host "  تمّ. العدّاء يظهر الآن في:" -ForegroundColor Green
Write-Host "    https://github.com/$Repository/settings/actions/runners" -ForegroundColor Gray
Write-Host ""
Write-Host "  والنشر من: Actions ← «النشر» ← Run workflow" -ForegroundColor Green
Write-Host "    الوسم ثم الوجهة (staging أوّلاً — الإنتاج يرفض حزمة لم تمرّ بها)." -ForegroundColor Gray
Write-Host ""
