<#
.SYNOPSIS
    يضبط ساعة الخادم من ترويسة HTTP، ويجدّدها كل ساعة كمهمّة مجدولة.

.DESCRIPTION
    ساعة هذا الخادم تأخّرت أربع عشرة دقيقة، ولم يُكتشف إلا حين رفض GitHub
    رموز العدّاء. و«w32tm /query /status» كان يقول «آخر مزامنة ناجحة» في
    كل مرّة — فهو يصف **حدوث** المزامنة لا **صحّة** نتيجتها.

    والسبب أن NTP يعمل على UDP 123، وهو محجوب عند كثير من المستضيفين.
    فالوقت يُؤخذ هنا من ترويسة Date في ردٍّ على 443 — المنفذ الذي نعلم أنه
    مفتوح لأن الخادم يخدم به.

    <para><b>ولماذا يعني هذا أكثر من عدّاء نشر:</b> كل فاتورة وكل قيدٍ في
    الدفتر يحمل وقت هذا الخادم. وفي نظامٍ قاعدته حرمة القيد فالوقت جزءٌ من
    القيد لا زينة فيه — ودفترٌ ساعتُه منحرفة يُراجَع بعد شهور فلا يُصدَّق
    ترتيبه.</para>

.PARAMETER Install
    يسجّل مهمّةً مجدولة تعمل كل ساعة بحساب SYSTEM.

.PARAMETER ToleranceSeconds
    لا تُضبط الساعة لانحرافٍ أقلّ من هذا. الافتراضي 5 ثوانٍ: ترويسة HTTP
    دقّتها ثانية، وزمن الشبكة يضيف كسراً — فتصحيحُ ثانيتين ضجيجٌ يكتب سطراً
    في السجلّ كل ساعة بلا معنى.

.EXAMPLE
    .\time_sync.ps1
    .\time_sync.ps1 -Install
    .\time_sync.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Install,
    [int]$ToleranceSeconds = 5,
    # مصادر بترتيب التفضيل. أوّلها يردّ يفوز.
    [string[]]$Sources = @(
        'https://api.github.com',
        'https://www.microsoft.com',
        'https://www.cloudflare.com'
    ),
    [string]$LogPath = 'C:\Backups\Kinetic\timesync.log',
    [string]$TaskName = 'Kinetic - ضبط الساعة'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

# ‏PowerShell 5.1 لا يتفاوض TLS 1.2 افتراضاً على ويندوز سيرفر.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $dir = Split-Path -Parent $LogPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        # ‏WhatIf:$false — السجلّ يُكتب حتى في التجربة الجافّة: أثرُ ما
        # قيس ليس تغييراً في النظام، وإخفاؤه يجعل التجربة أقلّ صدقاً.
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -WhatIf:$false
    } catch { }
    $color = switch ($Level) { 'ERR' { 'Red' } 'WARN' { 'Yellow' } 'FIX' { 'Cyan' } default { 'Gray' } }
    Write-Host "  $line" -ForegroundColor $color
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ── التثبيت ─────────────────────────────────────────────────────────────
if ($Install) {
    if (-not (Test-Admin)) { throw 'شغّل PowerShell كمسؤول — تسجيل مهمّة بحساب SYSTEM يحتاج ذلك.' }

    $self = $MyInvocation.MyCommand.Path
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $self)

    # كل ساعة لا مرّةً يومياً: انحرافُ خادمٍ لا يتزامن يتراكم، وساعةٌ واحدة
    # تكفي ليُرفَض رمز مصادقة — وهو ما وقع.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(3) `
        -RepetitionInterval (New-TimeSpan -Hours 1)

    # SYSTEM لا حساب مستخدم: ضبط ساعة النظام يحتاج امتيازاً، وحسابُ مستخدمٍ
    # تنتهي كلمتُه يوماً فتتوقّف المهمّة صامتةً.
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
        -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    if ($PSCmdlet.ShouldProcess($TaskName, 'تسجيل مهمّة مجدولة')) {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        Write-Host ""
        Write-Host "  سُجّلت المهمّة «$TaskName» — كل ساعة بحساب SYSTEM." -ForegroundColor Green
        Write-Host "  السجلّ: $LogPath" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  للتشغيل الآن:  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
        Write-Host "  للحال:         Get-ScheduledTaskInfo -TaskName '$TaskName'" -ForegroundColor Gray
        Write-Host ""
    }
    return
}

# ── القياس ──────────────────────────────────────────────────────────────
$serverUtc = $null
$used = $null

foreach ($src in $Sources) {
    try {
        # زمن الرحلة يُقاس ويُضاف نصفُه: الترويسة كُتبت لحظة الإرسال، فما
        # وصلنا أقدمُ ممّا نراه بمقدار نصف الرحلة تقريباً.
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri $src -UseBasicParsing -TimeoutSec 15 -Method Head
        $sw.Stop()

        $dateHeader = $resp.Headers['Date']
        if (-not $dateHeader) { continue }

        $parsed = [DateTime]::ParseExact(
            $dateHeader, 'ddd, dd MMM yyyy HH:mm:ss \G\M\T',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)

        $serverUtc = $parsed.AddMilliseconds($sw.Elapsed.TotalMilliseconds / 2)
        $used = $src
        break
    } catch {
        Write-Log "تعذّر $src : $($_.Exception.Message)" 'WARN'
    }
}

if (-not $serverUtc) {
    Write-Log 'لم يردّ أي مصدر — الساعة كما هي.' 'ERR'
    exit 1
}

$localUtc = (Get-Date).ToUniversalTime()
$skew = ($serverUtc - $localUtc).TotalSeconds

# ── التصحيح ─────────────────────────────────────────────────────────────
if ([math]::Abs($skew) -lt $ToleranceSeconds) {
    Write-Log ('الساعة مضبوطة ({0:+0.0;-0.0;0} ثانية عن {1})' -f $skew, $used)
    exit 0
}

if (-not (Test-Admin)) {
    Write-Log ('انحراف {0:+0;-0;0} ثانية — وضبطُ الساعة يحتاج صلاحية مسؤول.' -f $skew) 'ERR'
    exit 1
}

if ($PSCmdlet.ShouldProcess('ساعة النظام', ('تصحيح {0:+0;-0;0} ثانية' -f $skew))) {
    $before = Get-Date
    Set-Date -Date $serverUtc.ToLocalTime() | Out-Null
    Write-Log ('صُحّحت {0:+0;-0;0} ثانية — من {1} إلى {2} (المصدر {3})' -f `
        $skew, $before.ToString('HH:mm:ss'), (Get-Date).ToString('HH:mm:ss'), $used) 'FIX'
}
