<#
.SYNOPSIS
    تجهيز خادم ويندوز خام لتشغيل Kinetic Enterprise — يُنفَّذ على الخادم.

.DESCRIPTION
    يفحص المتطلبات، ويُنشئ قاعدة البيانات، ويجهّز مواقع IIS، ويتحقّق من كل
    خطوة قبل التالية.

    لا يُثبّت البرامج بنفسه: تنزيل مثبِّتات من الإنترنت وتشغيلها على خادم
    إنتاج قرارٌ يخصّ مدير الخادم لا سكربتاً. يفحص ويُبلّغ بما ينقص ومن أين
    يُنزَّل، ثم يتوقّف.

    يُنفَّذ على مراحل عبر -Stage، لأن بين المراحل خطوات يدوية (تثبيت
    البرامج، إصدار الشهادة، ملء الأسرار).

.PARAMETER Stage
    check   : فحص المتطلبات فقط (ابدأ به)
    db      : إنشاء القاعدة وتنفيذ المخطط والترحيلات والفهارس
    iis     : إنشاء موقعَي الـAPI والويب في IIS
    verify  : فحص شامل بعد اكتمال كل شيء

.PARAMETER Domain
    النطاق الحقيقي، مثل erp.example.ly

.PARAMETER PackagePath
    مسار مجلد الحزمة المفكوكة (publish). الافتراضي C:\kinetic

.PARAMETER SqlInstance
    الافتراضي .\SQLEXPRESS

.EXAMPLE
    .\server_setup.ps1 -Stage check
    .\server_setup.ps1 -Stage db
    .\server_setup.ps1 -Stage iis -Domain erp.example.ly
    .\server_setup.ps1 -Stage verify -Domain erp.example.ly
#>
[CmdletBinding()]
param(
    [ValidateSet('check', 'db', 'iis', 'verify')]
    [string]$Stage = 'check',
    [string]$Domain,
    [string]$PackagePath = 'C:\kinetic',
    [string]$SqlInstance = '.\SQLEXPRESS',
    [string]$Database = 'KineticEnterprise'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Ok($t)   { Write-Host "  [موجود] $t" -ForegroundColor Green }
function Miss($t) { Write-Host "  [ناقص ] $t" -ForegroundColor Red }
function Warn($t) { Write-Host "  [تنبيه] $t" -ForegroundColor Yellow }
function Head($t) { Write-Host "`n$t" -ForegroundColor Cyan; Write-Host ('─' * 62) -ForegroundColor DarkGray }

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
        # GO فاصل دفعات في أدوات مايكروسوفت لا أمر SQL — SqlClient لا يفهمه.
        foreach ($batch in [regex]::Split($text, '(?im)^\s*GO\s*$')) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $batch
            $cmd.CommandTimeout = 300
            [void]$cmd.ExecuteNonQuery()
        }
    } finally { $conn.Close() }
}

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor White
Write-Host   "║   تجهيز خادم Kinetic Enterprise — المرحلة: $($Stage.PadRight(18))║" -ForegroundColor White
Write-Host   "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor White

# ══════════════════════════════ check ═══════════════════════════════════
if ($Stage -eq 'check') {
    $missing = @()

    Head 'صلاحيات'
    if (Test-Admin) { Ok 'PowerShell يعمل كمسؤول' }
    else { Miss 'شغّل PowerShell كمسؤول — مراحل db وiis تحتاجها'; $missing += 'admin' }

    Head 'نظام التشغيل'
    $os = (Get-CimInstance Win32_OperatingSystem)
    Ok "$($os.Caption) — $($os.OSArchitecture)"

    Head 'SQL Server'
    $instances = Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue |
                 Where-Object { $_.Status -eq 'Running' -and $_.Name -match '^MSSQL(\$|SERVER)' }
    if ($instances) {
        foreach ($i in $instances) { Ok "خدمة تعمل: $($i.Name)" }
        try {
            $c = New-Object System.Data.SqlClient.SqlConnection(
                "Server=$SqlInstance;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=8")
            $c.Open()
            $cmd = $c.CreateCommand()
            $cmd.CommandText = "SELECT CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(30)) + ' | ' + CAST(SERVERPROPERTY('Edition') AS VARCHAR(50))"
            $info = $cmd.ExecuteScalar()
            $c.Close()
            Ok "الاتصال بـ $SqlInstance ناجح: $info"

            # الإصدار 13 = SQL Server 2016، أول إصدار يدعم Row-Level Security
            # وsp_set_session_context — وعليهما يقوم عزل المنظمات كله. أقدم
            # منه ينفّذ المخطط ثم يفشل صامتاً في العزل، وهو أسوأ من الرفض.
            $major = [int]((($info -split '\|')[0].Trim() -split '\.')[0])
            if ($major -lt 13) {
                Miss "الإصدار $major أقدم من 2016 — لا يدعم Row-Level Security. عزل المنظمات لن يعمل."
                $missing += 'sqlversion'
            } else { Ok "الإصدار يدعم عزل الصفوف (RLS)" }
        } catch {
            Miss "تعذّر الاتصال بـ $SqlInstance — $($_.Exception.Message.Split([char]10)[0])"
            $missing += 'sqlconn'
        }
    } else {
        Miss 'لا نسخة SQL Server تعمل'
        Write-Host '        نزّل SQL Server 2022 Express (مجاني):' -ForegroundColor Gray
        Write-Host '        https://www.microsoft.com/sql-server/sql-server-downloads' -ForegroundColor Gray
        Write-Host '        اختر Basic، ودوّن اسم النسخة (SQLEXPRESS افتراضياً).' -ForegroundColor Gray
        $missing += 'sql'
    }

    Head '.NET 8 Hosting Bundle'
    $runtimes = & dotnet --list-runtimes 2>$null
    $hasAspNet = $runtimes | Where-Object { $_ -match 'Microsoft\.AspNetCore\.App 8\.' }
    if ($hasAspNet) { Ok ($hasAspNet | Select-Object -First 1) }
    else {
        Miss 'ASP.NET Core Runtime 8 غير مثبَّت'
        Write-Host '        نزّل "ASP.NET Core 8 Hosting Bundle" (يشمل Runtime + وحدة IIS):' -ForegroundColor Gray
        Write-Host '        https://dotnet.microsoft.com/download/dotnet/8.0' -ForegroundColor Gray
        Write-Host '        ثبّته *بعد* IIS، وإلا لم تُسجَّل وحدة IIS. أعد التشغيل بعده.' -ForegroundColor Gray
        $missing += 'dotnet'
    }

    Head 'IIS'
    # W3SVC بدل Get-WindowsFeature: الأخيرة موجودة على إصدارات الخادم وحدها
    # فينهار الفحص على أي نسخة عميل (ويندوز 10/11)، وهي بيئة التجربة قبل
    # النقل. وجود الخدمة دليل التثبيت على الاثنين معاً.
    $w3svc = Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue
    if ($w3svc) {
        Ok "خدمة IIS موجودة (الحالة: $($w3svc.Status))"
        if ($w3svc.Status -ne 'Running') { Warn 'IIS متوقّف — شغّله: Start-Service W3SVC' }
        if (Get-Module -ListAvailable -Name WebAdministration) { Ok 'وحدة WebAdministration متاحة' }
        else { Miss 'وحدة WebAdministration غير متاحة'; $missing += 'iismod' }
        try {
            $ancm = Get-WebGlobalModule -ErrorAction Stop | Where-Object { $_.Name -like 'AspNetCoreModule*' }
            if ($ancm) { Ok "وحدة $($ancm[0].Name) مسجَّلة" }
            else { Miss 'AspNetCoreModule غير مسجَّلة — ثبّت Hosting Bundle *بعد* IIS'; $missing += 'ancm' }
        } catch {
            Warn 'تعذّر فحص وحدات IIS — تحقّق يدوياً من AspNetCoreModuleV2'
        }
    } else {
        Miss 'IIS غير مثبَّت'
        Write-Host '        على Windows Server:' -ForegroundColor Gray
        Write-Host '        Install-WindowsFeature -Name Web-Server -IncludeManagementTools' -ForegroundColor Gray
        $missing += 'iis'
    }

    Head 'الحزمة'
    if (Test-Path (Join-Path $PackagePath 'backend')) { Ok "الحزمة مفكوكة في $PackagePath" }
    else {
        Miss "لا حزمة في $PackagePath"
        Write-Host '        فُكّ publish.zip هناك (يحوي backend و web و sql).' -ForegroundColor Gray
        $missing += 'package'
    }

    Head 'المنافذ'
    foreach ($p in @(80, 443)) {
        $used = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
        if ($used) { Warn "المنفذ $p مستعمل — تأكّد أنه IIS لا برنامج آخر" }
        else { Ok "المنفذ $p متاح" }
    }

    Write-Host ''
    if ($missing.Count -eq 0) {
        Write-Host '  كل المتطلبات جاهزة. التالي:  .\server_setup.ps1 -Stage db' -ForegroundColor Green
    } else {
        Write-Host "  ينقص $($missing.Count) متطلَّب — عالجها ثم أعد الفحص." -ForegroundColor Red
        exit 1
    }
}

# ══════════════════════════════ db ══════════════════════════════════════
if ($Stage -eq 'db') {
    $sqlDir = Join-Path $PackagePath 'sql'
    foreach ($f in @('DATABASE_SCHEMA_SQLSERVER.sql', 'MIGRATIONS.sql', 'INDEXES.sql')) {
        if (-not (Test-Path (Join-Path $sqlDir $f))) { throw "ملف مفقود: $f في $sqlDir" }
    }

    Head 'إنشاء القاعدة'
    $exists = $false
    $c = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=master;Integrated Security=true;TrustServerCertificate=true")
    $c.Open()
    $cmd = $c.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM sys.databases WHERE name = @n"
    [void]$cmd.Parameters.AddWithValue('@n', $Database)
    $exists = ([int]$cmd.ExecuteScalar()) -gt 0
    $c.Close()

    if ($exists) {
        Warn "$Database موجودة — لن تُنشأ من جديد. الترحيلات ستُنفَّذ عليها."
    } else {
        Invoke-Sql -Db 'master' -Query "CREATE DATABASE [$Database];"
        Ok "أُنشئت $Database"
        Invoke-Sql -Db $Database -File (Join-Path $sqlDir 'DATABASE_SCHEMA_SQLSERVER.sql')
        Ok 'نُفِّذ المخطط الأساسي (الجداول وسياسات العزل)'
    }

    # كلاهما آمن للإعادة (IF NOT EXISTS حول كل تغيير) فيُنفَّذان دائماً.
    Invoke-Sql -Db $Database -File (Join-Path $sqlDir 'MIGRATIONS.sql')
    Ok 'نُفِّذت الترحيلات'
    Invoke-Sql -Db $Database -File (Join-Path $sqlDir 'INDEXES.sql')
    Ok 'نُفِّذت الفهارس'

    Head 'التحقّق'
    $c = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=$Database;Integrated Security=true;TrustServerCertificate=true")
    $c.Open()
    foreach ($q in @(
        @{ n = 'الجداول';       s = 'SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES' },
        @{ n = 'سياسات العزل';  s = 'SELECT COUNT(*) FROM sys.security_policies' },
        @{ n = 'الصلاحيات';     s = 'SELECT COUNT(*) FROM dbo.permissions' })) {
        $cmd = $c.CreateCommand(); $cmd.CommandText = $q.s
        Ok "$($q.n): $($cmd.ExecuteScalar())"
    }
    # العمود الذي يعتمد عليه البيع دون اتصال — بالصيغة snake_case حصراً
    $cmd = $c.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.invoices') AND name='client_request_id'"
    if ([int]$cmd.ExecuteScalar() -eq 1) { Ok 'client_request_id موجود' }
    else { Miss 'client_request_id مفقود — البيع دون اتصال لن يعمل' }
    $c.Close()

    Write-Host ''
    Write-Host '  التالي: املأ appsettings.Production.json ثم:' -ForegroundColor Green
    $shown = if ($Domain) { $Domain } else { 'erp.example.ly' }
    Write-Host "         .\server_setup.ps1 -Stage iis -Domain $shown" -ForegroundColor Green
}

# ══════════════════════════════ iis ═════════════════════════════════════
if ($Stage -eq 'iis') {
    if (-not $Domain) { throw 'مرّر -Domain (مثل erp.example.ly)' }
    if (-not (Test-Admin)) { throw 'شغّل PowerShell كمسؤول' }
    Import-Module WebAdministration

    $apiPath = Join-Path $PackagePath 'backend'
    $webPath = Join-Path $PackagePath 'web'
    foreach ($p in @($apiPath, $webPath)) {
        if (-not (Test-Path $p)) { throw "مسار مفقود: $p" }
    }

    $settings = Join-Path $apiPath 'appsettings.Production.json'
    if (-not (Test-Path $settings)) {
        throw "appsettings.Production.json مفقود في $apiPath — انسخ القالب واملأه أولاً."
    }
    $cfg = Get-Content $settings -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($cfg.Jwt.Key)) { throw 'Jwt:Key فارغ في appsettings.Production.json' }
    if ($cfg.Jwt.Key.Length -lt 32) { throw 'Jwt:Key أقصر من 32 حرفاً — مفتاح ضعيف يعني تزوير توكن' }
    if ([string]::IsNullOrWhiteSpace($cfg.ConnectionStrings.Default)) { throw 'سلسلة الاتصال فارغة' }
    Ok 'ملف الأسرار مكتمل'

    Head 'مجمع التطبيقات'
    $poolName = 'KineticApi'
    if (-not (Test-Path "IIS:\AppPools\$poolName")) {
        New-WebAppPool -Name $poolName | Out-Null
    }
    # No Managed Code: التطبيق .NET Core يعمل خارج CLR الخاص بـIIS تماماً،
    # وIIS يعمل وسيطاً عكسياً فقط. تركه على .NET CLR v4 يُحمّل وقت تشغيل
    # لا يُستعمل ويُربك التشخيص عند الأخطاء.
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name managedRuntimeVersion -Value ''
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name startMode -Value 'AlwaysRunning'
    Ok "مجمع $poolName جاهز (No Managed Code، تشغيل دائم)"

    Head 'المواقع'
    if (-not (Get-Website -Name 'KineticWeb' -ErrorAction SilentlyContinue)) {
        New-Website -Name 'KineticWeb' -PhysicalPath $webPath -Port 80 -HostHeader $Domain | Out-Null
    } else {
        Set-ItemProperty 'IIS:\Sites\KineticWeb' -Name physicalPath -Value $webPath
    }
    Ok "موقع KineticWeb -> $webPath (المنفذ 80، المضيف $Domain)"

    if (-not (Get-WebApplication -Site 'KineticWeb' -Name 'api' -ErrorAction SilentlyContinue)) {
        New-WebApplication -Site 'KineticWeb' -Name 'api' -PhysicalPath $apiPath -ApplicationPool $poolName | Out-Null
    } else {
        Set-ItemProperty 'IIS:\Sites\KineticWeb\api' -Name physicalPath -Value $apiPath
    }
    Ok "تطبيق /api -> $apiPath"

    # ملف الأسرار يجب ألّا يُخدَم كملف ثابت لو أخطأ أحد في ترتيب المسارات.
    Head 'الحماية'
    $req = "IIS:\Sites\KineticWeb\api"
    Add-WebConfigurationProperty -PSPath $req -Filter 'system.webServer/security/requestFiltering/hiddenSegments' `
        -Name '.' -Value @{ segment = 'appsettings.Production.json' } -ErrorAction SilentlyContinue
    Ok 'appsettings.Production.json محجوب عن الطلبات المباشرة'

    Write-Host ''
    Write-Host '  التالي — الشهادة (الخطوة الوحيدة المتبقّية قبل الإطلاق):' -ForegroundColor Yellow
    Write-Host '    1) وجّه سجل DNS من A إلى IP هذا الخادم، وتأكّد أن 80 و443 مفتوحان.' -ForegroundColor Gray
    Write-Host '    2) نزّل win-acme من https://www.win-acme.com ثم:' -ForegroundColor Gray
    Write-Host '         .\wacs.exe --target iis --siteid (Get-Website KineticWeb).Id' -ForegroundColor White
    Write-Host '       يُصدر شهادة Let''s Encrypt ويربطها بالمنفذ 443 ويجدّدها تلقائياً.' -ForegroundColor Gray
    Write-Host '    3) ثم:  .\server_setup.ps1 -Stage verify -Domain ' -NoNewline -ForegroundColor Gray
    Write-Host $Domain -ForegroundColor Gray
}

# ══════════════════════════════ verify ══════════════════════════════════
if ($Stage -eq 'verify') {
    if (-not $Domain) { throw 'مرّر -Domain' }
    $fail = 0

    Head 'HTTPS'
    try {
        $r = Invoke-WebRequest -Uri "https://$Domain" -TimeoutSec 20 -UseBasicParsing
        Ok "https://$Domain يستجيب ($($r.StatusCode))"
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($code -gt 0) { Ok "https://$Domain يستجيب ($code)" }
        else { Miss "https://$Domain لا يستجيب — $($_.Exception.Message.Split([char]10)[0])"; $fail++ }
    }

    Head 'الـAPI'
    try {
        $null = Invoke-WebRequest -Uri "https://$Domain/api/platform-settings" -TimeoutSec 20 -UseBasicParsing
        Warn 'نقطة محمية ردّت 200 بلا توكن — راجع إعداد المصادقة'
        $fail++
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($code -eq 401) { Ok 'الـAPI يعمل والمصادقة مفعّلة (401 بلا توكن)' }
        elseif ($code -eq 0) { Miss 'الـAPI لا يستجيب'; $fail++ }
        else { Warn "رد غير متوقَّع: $code"; $fail++ }
    }

    Head 'HTTP لا يُقبَل'
    try {
        $r = Invoke-WebRequest -Uri "http://$Domain/api/platform-settings" -TimeoutSec 15 -MaximumRedirection 0 -UseBasicParsing
        Warn "HTTP يردّ $($r.StatusCode) بلا تحويل — أضف قاعدة تحويل إلى HTTPS"
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($code -in @(301, 302, 307, 308)) { Ok "HTTP يُحوَّل إلى HTTPS ($code)" }
        else { Warn "HTTP: $code — يُفضَّل تحويله إلى HTTPS" }
    }

    Head 'قاعدة البيانات'
    try {
        $c = New-Object System.Data.SqlClient.SqlConnection(
            "Server=$SqlInstance;Database=$Database;Integrated Security=true;TrustServerCertificate=true")
        $c.Open()
        $cmd = $c.CreateCommand()
        $cmd.CommandText = 'SELECT COUNT(*) FROM dbo.app_users WHERE is_platform_admin = 1'
        $owners = [int]$cmd.ExecuteScalar()
        $c.Close()
        if ($owners -gt 0) { Ok "حساب مالك المنصة موجود ($owners)" }
        else {
            Miss 'لا حساب مالك منصة — نفّذ من مجلد backend:'
            Write-Host '        dotnet KineticEnterprise.Api.dll create-platform-owner' -ForegroundColor Gray
            $fail++
        }
    } catch { Miss "تعذّر فحص القاعدة: $($_.Exception.Message.Split([char]10)[0])"; $fail++ }

    Head 'النسخ الاحتياطي'
    if (Get-ScheduledTask -TaskName "KineticBackup_$Database" -ErrorAction SilentlyContinue) {
        Ok 'المهمة اليومية مسجَّلة'
    } else {
        Miss 'النسخ الاحتياطي غير مجدوَل — .\backup.ps1 -Install'
        $fail++
    }

    Write-Host ''
    if ($fail -eq 0) { Write-Host '  الخادم جاهز للإطلاق.' -ForegroundColor Green }
    else { Write-Host "  $fail بنداً يحتاج معالجة قبل الإطلاق." -ForegroundColor Red; exit 1 }
}
