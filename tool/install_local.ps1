<#
.SYNOPSIS
    تركيب Kinetic على جهاز محلّ واحد — بلا فروع وبلا إنترنت.

.DESCRIPTION
    النسخة المحلّية الكاملة: القاعدة والخادم والواجهة كلّها على جهاز واحد
    داخل المحلّ. لا سحابة، ولا اشتراك شهري يتوقّف إن انقطع الخط.

    يُنفَّذ على جهاز الزبون بصلاحية مسؤول، مرّة واحدة.

    ── ما يفعله ──
      1. يفحص المتطلّبات (SQL Server وحزمة .NET) ويتوقّف إن نقص شيء.
      2. يُنشئ القاعدة وينفّذ المخطط والترحيلات والفهارس.
      3. يكتب appsettings.Production.json بمفتاح JWT عشوائي.
      4. يسجّل الخادم **خدمةَ ويندوز** تعمل مع الإقلاع.
      5. يفتح المنفذ للشبكة الخاصّة وحدها.
      6. يجدول نسخة احتياطية يومية.
      7. يطبع بصمة الجهاز لإصدار الترخيص.

    ── لماذا خدمة ويندوز لا IIS ──
    IIS مكوّن إضافي يُثبَّت ويُحدَّث ويُشخَّص عند العطل، وصاحب المحلّ ليس
    مدير خوادم. Kestrel كخدمة يكفي حِملَ محلٍّ واحد ويعمل بلا شيء يُثبَّت
    فوقه — وأقلُّ ما يُركَّب أقلُّ ما يُعطَب.

    ── وعن HTTPS: قرار مقصود ومُعلَن ──
    لا شهادة هنا. الشهادة تحتاج نطاقاً وتجديداً دورياً من الإنترنت — وهذه
    نسخة **لا إنترنت لها أصلاً**. وشهادة موقَّعة ذاتياً أسوأ من غيابها:
    تُدرّب المستخدم على تجاوز تحذير الأمان بالضغط، فيتجاوزه يوم يكون
    حقيقياً.

    فالحماية هنا حدُّ الشبكة لا التعمية: المنفذ مفتوح على ملفّ الشبكة
    **الخاصّة وحده**، أي على السويتش داخل المحلّ. ومن كان على ذلك السويتش
    فهو داخل المحلّ فعلاً.

    **وهذا يعني صراحةً:** لا تُوصِّل هذا الجهاز بشبكة عامّة أو واي-فاي
    مفتوح للزبائن، ولا تفتح المنفذ في الراوتر. أردت شيئاً من ذلك؟ فهذه
    النسخة السحابية لا المحلّية.

.PARAMETER PackagePath
    مجلد الحزمة المفكوكة. الافتراضي C:\kinetic

.PARAMETER DataPath
    مجلد البيانات — المرفوعات والنسخ الاحتياطية. **خارج مجلد الحزمة
    عمداً**: كل ترقية تستبدل مجلد backend كاملاً فتمحو ما بداخله.
    الافتراضي C:\kinetic-data

.PARAMETER SqlInstance
    الافتراضي .\SQLEXPRESS — نفس افتراض server_setup.ps1 وbackup.ps1.

.PARAMETER Database
    الافتراضي KineticEnterprise

.PARAMETER Port
    منفذ الخادم المحلّي. الافتراضي 5000.

.PARAMETER LicensePublicKey
    المفتاح العامّ للتحقّق من مفتاح الترخيص (ملف .pem أو نصّه).

    **تركه فارغاً يترك حارس الترخيص معطَّلاً** — والقاعدة هنا بيد الزبون،
    فأعمدة expires_at وmax_branches بياناتُ عرض لا أدلّة. راجع
    LicenseVerification.

.PARAMETER LocalhostOnly
    يقصر الخادم على الجهاز نفسه بلا أي وصول من الشبكة. للمحلّ الذي جهازه
    واحد — لا كاشير ثانٍ ولا هاتف يمسح.

.PARAMETER SkipBackupSchedule
    لا يجدول النسخ الاحتياطي (إن كان للزبون نظام نسخ خاصّ به).

.EXAMPLE
    .\install_local.ps1
    .\install_local.ps1 -LicensePublicKey C:\key\public.pem
    .\install_local.ps1 -LocalhostOnly -Port 5050
#>
[CmdletBinding()]
param(
    [string]$PackagePath = 'C:\kinetic',
    [string]$DataPath = 'C:\kinetic-data',
    [string]$SqlInstance = '.\SQLEXPRESS',
    [string]$Database = 'KineticEnterprise',
    [int]$Port = 5000,
    [string]$LicensePublicKey,
    [switch]$LocalhostOnly,
    [switch]$SkipBackupSchedule
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$ServiceName = 'KineticErp'
$ServiceLabel = 'Kinetic ERP'

function Head($t) { Write-Host "`n$t" -ForegroundColor Cyan; Write-Host ('─' * 64) -ForegroundColor DarkGray }
function Ok($t)   { Write-Host "  [تمّ  ] $t" -ForegroundColor Green }
function Miss($t) { Write-Host "  [ناقص] $t" -ForegroundColor Red }
function Warn($t) { Write-Host "  [تنبيه] $t" -ForegroundColor Yellow }
function Info($t) { Write-Host "         $t" -ForegroundColor DarkGray }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Sql {
    param([string]$Db, [string]$Query, [string]$File)

    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=$Db;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=15")
    $conn.Open()
    try {
        $text = if ($File) { Get-Content -LiteralPath $File -Raw -Encoding UTF8 } else { $Query }

        # GO ليس أمر T-SQL بل فاصل دُفعات يفهمه sqlcmd وحده. إرسال الملف
        # كاملاً عبر SqlClient يفشل عند أول GO — فيُقسَّم هنا.
        $batches = [regex]::Split($text, '(?im)^\s*GO\s*$')
        foreach ($b in $batches) {
            if ([string]::IsNullOrWhiteSpace($b)) { continue }
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $b
            $cmd.CommandTimeout = 300
            [void]$cmd.ExecuteNonQuery()
        }
    } finally { $conn.Close() }
}

# ════════════════════════════════════════════════════════════════════════
Head 'Kinetic — التركيب المحلّي'

if (-not (Test-Admin)) {
    Miss 'يلزم تشغيل هذه النافذة كمسؤول (Run as administrator).'
    Info 'تسجيل خدمة ويندوز وفتح منفذ في الجدار الناري لا يقعان بلا ذلك.'
    exit 1
}
Ok 'صلاحية مسؤول'

# ── 1. المتطلّبات ────────────────────────────────────────────────────────
Head '١. المتطلّبات'

$fail = $false

if (-not (Test-Path $PackagePath)) {
    Miss "مجلد الحزمة غير موجود: $PackagePath"
    Info 'فُكّ الحزمة إلى هذا المسار أولاً، أو مرّر -PackagePath.'
    $fail = $true
} else { Ok "الحزمة: $PackagePath" }

$backendPath = Join-Path $PackagePath 'backend'
$apiDll = Join-Path $backendPath 'KineticEnterprise.Api.dll'
$apiExe = Join-Path $backendPath 'KineticEnterprise.Api.exe'

if (-not (Test-Path $apiDll)) {
    Miss "ملف الخادم غير موجود: $apiDll"
    $fail = $true
} else { Ok 'ملفات الخادم' }

# .NET: الحزمة تُنشر --self-contained false، فالتشغيل يحتاج ASP.NET Core Runtime.
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Miss 'حزمة .NET غير مثبّتة'
    Info 'نزّل ASP.NET Core Runtime 8 (Hosting Bundle) من:'
    Info '  https://dotnet.microsoft.com/download/dotnet/8.0'
    $fail = $true
} else {
    $runtimes = & dotnet --list-runtimes 2>$null
    if ($runtimes -match 'Microsoft\.AspNetCore\.App 8\.') {
        Ok 'ASP.NET Core Runtime 8'
    } else {
        Miss 'ASP.NET Core Runtime 8 غير مثبّت (وُجدت dotnet لكن بلا حزمة الويب)'
        Info 'نزّل ASP.NET Core Runtime 8 من الرابط أعلاه.'
        $fail = $true
    }
}

try {
    Invoke-Sql -Db 'master' -Query 'SELECT 1'
    Ok "SQL Server يستجيب على $SqlInstance"
} catch {
    Miss "تعذّر الاتصال بـ SQL Server على $SqlInstance"
    Info 'نزّل SQL Server 2019/2022 Express (مجاني) وثبّته، ثم أعد التشغيل.'
    Info "أو مرّر -SqlInstance باسم النسخة الصحيح إن كانت مثبّتة باسم آخر."
    Info $_.Exception.Message
    $fail = $true
}

if ($fail) {
    Write-Host "`nالتركيب متوقّف — عالج ما سبق ثم أعد التشغيل.`n" -ForegroundColor Red
    exit 1
}

# ── 2. القاعدة ──────────────────────────────────────────────────────────
Head '٢. قاعدة البيانات'

$sqlPath = Join-Path $PackagePath 'sql'
$dbExists = $false
try {
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=master;Integrated Security=true;TrustServerCertificate=true")
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT DB_ID('$Database')"
    $dbExists = $cmd.ExecuteScalar() -isnot [DBNull]
    $conn.Close()
} catch { }

if ($dbExists) {
    # لا يُعاد إنشاؤها أبداً: إعادة تركيب فوق قاعدة قائمة هي **محو محلٍّ
    # عامل**. الترحيلات وحدها تُنفَّذ، وهي idempotent بتصميمها.
    Ok "القاعدة $Database موجودة — لن تُنشأ من جديد"
    Warn 'ستُنفَّذ الترحيلات وحدها. لا شيء يُحذف.'
} else {
    $schema = Join-Path $sqlPath 'DATABASE_SCHEMA_SQLSERVER.sql'
    if (-not (Test-Path $schema)) { throw "ملف المخطط مفقود: $schema" }

    # المخطط يحمل اسم القاعدة مكتوباً فيه (CREATE DATABASE ثم USE)، فيُنشأ
    # الاسم المطلوب أولاً ثم يُنفَّذ داخله بلا سطرَي CREATE/USE.
    Invoke-Sql -Db 'master' -Query "CREATE DATABASE [$Database];"
    Ok "أُنشئت القاعدة $Database"

    $body = Get-Content -LiteralPath $schema -Raw -Encoding UTF8
    $body = [regex]::Replace($body, '(?im)^\s*(CREATE\s+DATABASE|USE|ALTER\s+DATABASE)\s+KineticEnterprise.*$', '')
    $tmp = Join-Path $env:TEMP "kinetic_schema_$PID.sql"
    $body | Out-File -LiteralPath $tmp -Encoding utf8
    try {
        Invoke-Sql -Db $Database -File $tmp
        Ok 'نُفِّذ المخطط'
    } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

foreach ($f in @('MIGRATIONS.sql', 'INDEXES.sql')) {
    $p = Join-Path $sqlPath $f
    if (Test-Path $p) {
        Invoke-Sql -Db $Database -File $p
        Ok "نُفِّذ $f"
    } else {
        Warn "$f غير موجود في الحزمة"
    }
}

# ── 3. مجلدات البيانات ──────────────────────────────────────────────────
Head '٣. مجلدات البيانات'

$uploads = Join-Path $DataPath 'uploads'
$backups = Join-Path $DataPath 'backups'
foreach ($d in @($DataPath, $uploads, $backups)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
Ok "البيانات: $DataPath"
Info 'خارج مجلد الحزمة عمداً — كل ترقية تستبدل backend كاملاً.'

# الخدمة تعمل بهوية NETWORK SERVICE (انظر أدناه)، فتلزمها الكتابة هنا.
foreach ($d in @($uploads, $backups)) {
    & icacls $d /grant '"NETWORK SERVICE":(OI)(CI)M' /T /Q | Out-Null
}
Ok 'صلاحية الكتابة ممنوحة لهوية الخدمة'

# ── 4. الإعدادات ────────────────────────────────────────────────────────
Head '٤. الإعدادات والأسرار'

$settingsPath = Join-Path $backendPath 'appsettings.Production.json'

if (Test-Path $settingsPath) {
    # لا يُكتب فوقه أبداً: توليد مفتاح JWT جديد على تركيب عامل **يُخرج كل
    # المستخدمين فوراً** ويُبطل كل توكن قائم، بلا أن يطلب أحدٌ ذلك.
    Ok 'appsettings.Production.json موجود — يُترك كما هو'
    Warn 'إن أردت تغيير إعداد فحرّره يدوياً ثم أعد تشغيل الخدمة.'
} else {
    $bytes = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $jwtKey = [Convert]::ToBase64String($bytes)

    $publicKey = ''
    if ($LicensePublicKey) {
        $publicKey = if (Test-Path $LicensePublicKey) {
            Get-Content -LiteralPath $LicensePublicKey -Raw -Encoding UTF8
        } else { $LicensePublicKey }
        $publicKey = $publicKey.Trim()
    }

    $bindHost = if ($LocalhostOnly) { '127.0.0.1' } else { '0.0.0.0' }

    $config = [ordered]@{
        ConnectionStrings = [ordered]@{
            # مصادقة ويندوز: بلا كلمة مرور مكتوبة في ملف على جهاز في محلّ.
            Default = "Server=$SqlInstance;Database=$Database;Trusted_Connection=True;TrustServerCertificate=True;"
        }
        Jwt = [ordered]@{ Key = $jwtKey }
        License = [ordered]@{ PublicKey = $publicKey }
        # لا تحويل إلى HTTPS: لا شهادة هنا، وتفعيله يقطع الاتصال تماماً.
        UseHttpsRedirection = $false
        Storage = [ordered]@{ Path = $uploads }
        Kestrel = [ordered]@{
            Endpoints = [ordered]@{
                Http = [ordered]@{ Url = "http://${bindHost}:$Port" }
            }
        }
    }
    $config | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $settingsPath -Encoding utf8
    Ok 'كُتب appsettings.Production.json بمفتاح JWT عشوائي'

    if ($publicKey) {
        Ok 'مفتاح الترخيص العامّ مضبوط — حارس الترخيص والبصمة مفعَّل'
    } else {
        Warn 'License:PublicKey فارغ — حارس الترخيص **معطَّل** على هذا التركيب.'
        Info 'القاعدة بيد الزبون هنا، فبلا توقيع لا شيء يمنع تعديل تاريخ الانتهاء.'
        Info 'أعد التشغيل بـ -LicensePublicKey، أو حرّر الملف وأعد تشغيل الخدمة.'
    }
}

# ── 5. الخدمة ───────────────────────────────────────────────────────────
Head '٥. خدمة ويندوز'

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force
        Ok 'أُوقفت الخدمة القائمة للتحديث'
    }
    & sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
    Ok 'حُذف تسجيل الخدمة القديم'
}

# exe المولَّد مع النشر يُفضَّل على "dotnet <dll>": الوسيط في الثاني يجعل
# مدير الخدمات يراقب عملية dotnet لا الخادم، ويعقّد مسار العمل.
$binPath = if (Test-Path $apiExe) { "`"$apiExe`"" } else { "`"$($dotnet.Source)`" `"$apiDll`"" }

& sc.exe create $ServiceName binPath= $binPath start= auto obj= 'NT AUTHORITY\NETWORK SERVICE' DisplayName= $ServiceLabel | Out-Null
if ($LASTEXITCODE -ne 0) { throw "تعذّر تسجيل الخدمة (رمز $LASTEXITCODE)" }

& sc.exe description $ServiceName 'خادم Kinetic ERP — التركيب المحلّي' | Out-Null

# مجلد العمل: بلا ضبطه يقرأ الخادم appsettings من system32 فلا يجدها.
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
New-ItemProperty -Path $regPath -Name 'WorkingDirectory' -Value $backendPath -PropertyType String -Force | Out-Null
Set-ItemProperty -Path $regPath -Name 'ImagePath' -Value $binPath

# البيئة: الخدمة لا ترث متغيّرات جلستك، وبلا هذا يقرأ الخادم
# appsettings.Development.json أو لا شيء.
New-ItemProperty -Path $regPath -Name 'Environment' `
    -Value @('ASPNETCORE_ENVIRONMENT=Production', "DOTNET_ROOT=$(Split-Path $dotnet.Source)") `
    -PropertyType MultiString -Force | Out-Null

# إعادة التشغيل التلقائي عند الانهيار: جهاز في محلّ لا يقف عنده أحد يراقب،
# وخدمة ماتت الساعة الثامنة صباحاً تعني محلاً معطّلاً حتى يتّصل صاحبه.
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null

Ok "سُجّلت الخدمة $ServiceName (تعمل مع الإقلاع)"

# ── 6. الجدار الناري ────────────────────────────────────────────────────
Head '٦. الشبكة'

$ruleName = 'Kinetic ERP (محلّي)'
Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

if ($LocalhostOnly) {
    Ok 'الخادم مقصور على هذا الجهاز — لا قاعدة جدار ناري ولا منفذ مفتوح'
} else {
    # الملفّ الخاصّ وحده: الشبكة العامّة تعني مقهى أو واي-فاي مفتوح، وفتح
    # المنفذ هناك يعرض الخادم لكل من على الشبكة.
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $Port -Profile Private | Out-Null
    Ok "فُتح المنفذ $Port على الشبكة الخاصّة وحدها"
    Warn 'لا تفتح هذا المنفذ في الراوتر ولا تصل الجهاز بشبكة عامّة.'
    Info 'الاتصال هنا بلا تعمية — حمايته أنه لا يخرج من المحلّ.'
}

# ── 7. النسخ الاحتياطي ──────────────────────────────────────────────────
Head '٧. النسخ الاحتياطي'

if ($SkipBackupSchedule) {
    Warn 'تُخطّيت الجدولة بطلبك — تأكّد من وجود نسخ بوسيلة أخرى.'
} else {
    $backupScript = Join-Path $PackagePath 'tool\backup.ps1'
    if (Test-Path $backupScript) {
        & $backupScript -Install -SqlInstance $SqlInstance -Database $Database -Path $backups
        if ($LASTEXITCODE -eq 0 -or $?) { Ok 'جُدولت نسخة يومية' }
        Warn "النسخ في $backups — على القرص نفسه."
        Info 'قرصٌ يتلف يأخذ القاعدة ونسخها معاً. انسخها إلى ذاكرة خارجية دورياً.'
    } else {
        Warn "backup.ps1 غير موجود في الحزمة — لم تُجدوَل نسخة."
    }
}

# ── 8. التشغيل ──────────────────────────────────────────────────────────
Head '٨. التشغيل والتحقّق'

Start-Service -Name $ServiceName
Start-Sleep -Seconds 5

$svc = Get-Service -Name $ServiceName
if ($svc.Status -ne 'Running') {
    Miss "الخدمة لم تعمل (الحالة: $($svc.Status))"
    Info 'اقرأ السبب من: Get-EventLog -LogName Application -Newest 20'
    exit 1
}
Ok 'الخدمة تعمل'

$baseUrl = "http://localhost:$Port"
$reachable = $false
foreach ($try in 1..6) {
    try {
        $r = Invoke-WebRequest -Uri "$baseUrl/api/app-version" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) { $reachable = $true; break }
    } catch { Start-Sleep -Seconds 3 }
}

if ($reachable) { Ok "الخادم يستجيب على $baseUrl" }
else {
    Miss "الخادم لا يستجيب على $baseUrl بعد الانتظار"
    Info 'الخدمة تعمل لكن الخادم لا يردّ — راجع سجل الأحداث.'
}

# ── 9. البصمة والخطوات المتبقّية ────────────────────────────────────────
Head '٩. ما تبقّى — خطوتان يدويتان'

Write-Host ''
Write-Host '  ١) بصمة هذا الجهاز — أرسلها لإصدار الترخيص:' -ForegroundColor Yellow
Write-Host ''
Push-Location $backendPath
try { & dotnet $apiDll machine-fingerprint }
finally { Pop-Location }

Write-Host '  ٢) حساب المدير — الأمر تفاعليّ (يقرأ كلمة المرور بلا إظهار)' -ForegroundColor Yellow
Write-Host '     فلا يمكن تشغيله من هنا. نفّذه بنفسك:' -ForegroundColor Yellow
Write-Host ''
Write-Host "        cd `"$backendPath`"" -ForegroundColor White
Write-Host "        dotnet KineticEnterprise.Api.dll create-platform-owner" -ForegroundColor White
Write-Host ''

Head 'تمّ'
Write-Host ''
Write-Host "  العنوان على هذا الجهاز:  $baseUrl" -ForegroundColor Green
if (-not $LocalhostOnly) {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
           Select-Object -First 1).IPAddress
    if ($ip) { Write-Host "  ومن أجهزة المحلّ:        http://${ip}:$Port" -ForegroundColor Green }
}
Write-Host ''
Write-Host '  إيقاف/تشغيل الخدمة:' -ForegroundColor DarkGray
Write-Host "      Restart-Service $ServiceName" -ForegroundColor White
Write-Host ''
