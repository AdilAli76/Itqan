#  =============================================================================
#   تجهيز بيئة تجربة معزولة — تُنفَّذ على الخادم كمسؤول.
#
#   موقع وقاعدة ومجمّع تطبيقات مستقلّة تماماً عن بيئة العملاء. العزل شرط لا
#   تحسين: بيئة تجربة تشترك مع الإنتاج في القاعدة تعني أن أول اختبار خاطئ
#   يمسّ بيانات عميل حقيقي، وأن ترحيلاً تجريبياً يُطبَّق على دفاتر يعتمد
#   عليها أحد.
#
#   وبيانات التجربة تأتي من استرجاع آخر نسخة احتياطية للإنتاج، لسببين:
#   الاختبار على بيانات تشبه الواقع بحجمه يكشف ما تخفيه قاعدة فارغة، وكل
#   تشغيل لهذا السكربت هو اختبار فعلي لصلاحية نسختك الاحتياطية — وهو
#   الاختبار الذي يُؤجَّل دائماً حتى تأتي الحاجة.
#
#   التشغيل (النطاق الافتراضي هو نطاق التجربة الحقيقي، فيكفي):
#       .\setup_staging.ps1
#       .\setup_staging.ps1 -RefreshData
#       .\setup_staging.ps1 -Domain other-staging.example.ly
#
#   -RefreshData وحدها تُعيد تحميل بيانات الإنتاج إلى قاعدة التجربة، بلا
#   لمس الموقع ولا المجمّع.
#  =============================================================================

[CmdletBinding()]
param(
    # نطاق التجربة الحقيقي افتراضاً — يُمرَّر صراحةً فقط لبيئة تجربة أخرى.
    # والإنتاج erp.droob-albayan.ly لا يُمرَّر هنا أبداً: هذا السكربت يُنشئ
    # موقعاً ومجمّعاً وقاعدةً باسم Staging، وتوجيهه إلى نطاق الإنتاج يعني
    # موقعين يتنازعان الارتباط نفسه.
    [string]$Domain = 'staging-erp.droob-albayan.ly',
    [string]$SqlInstance = '.\SQLEXPRESS',
    [string]$ProdDatabase = 'KineticEnterprise',
    [string]$StagingDatabase = 'KineticStaging',
    [string]$StagingPath = 'C:\kinetic-staging',
    [string]$BackupPath = 'C:\Backups\Kinetic',
    [string]$SiteName = 'KineticStaging',
    [string]$PoolName = 'KineticStagingPool',
    [int]$Port = 8080,
    [switch]$RefreshData
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Head($t) { Write-Host "`n$t" -ForegroundColor Cyan; Write-Host ('─' * 62) -ForegroundColor DarkGray }
function Ok($t)   { Write-Host "  [تمّ  ] $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [تنبيه] $t" -ForegroundColor Yellow }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Sql {
    param([string]$Db, [string]$Query)
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=$Db;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=30")
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = 300
        return $cmd.ExecuteScalar()
    } finally { $conn.Close() }
}

if (-not (Test-Admin)) { throw 'شغّل PowerShell كمسؤول' }

Write-Host ""
Write-Host "  بيئة التجربة — $Domain" -ForegroundColor White

# ── استرجاع بيانات الإنتاج ───────────────────────────────────────────────
Head 'بيانات التجربة من آخر نسخة احتياطية'

$bak = Get-ChildItem (Join-Path $BackupPath '*.bak') -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bak) {
    Warn "لا نسخة احتياطية في $BackupPath — خذ واحدة بـ backup.ps1 أولاً."
    Warn 'تُنشأ قاعدة التجربة فارغة، وستحتاج تطبيق المخطط عليها يدوياً.'
} else {
    Write-Host "  المصدر: $($bak.Name) ($([math]::Round($bak.Length/1MB,1)) ميغابايت)" -ForegroundColor Gray

    # الأسماء المنطقية تُقرأ من النسخة لا تُفترَض: قاعدة أُعيدت تسميتها أو
    # نُقلت تحمل أسماء غير المتوقَّعة، والافتراض يُفشل الاسترجاع برسالة
    # غامضة عن ملف غير موجود.
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=master;Integrated Security=true;TrustServerCertificate=true")
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "RESTORE FILELISTONLY FROM DISK = N'$($bak.FullName)'"
    $reader = $cmd.ExecuteReader()
    $dataName = $null; $logName = $null
    while ($reader.Read()) {
        if ($reader['Type'] -eq 'D' -and -not $dataName) { $dataName = $reader['LogicalName'] }
        if ($reader['Type'] -eq 'L' -and -not $logName)  { $logName  = $reader['LogicalName'] }
    }
    $reader.Close(); $conn.Close()
    Ok "الأسماء المنطقية: $dataName / $logName"

    $dataFile = Join-Path $BackupPath "$StagingDatabase.mdf"
    $logFile  = Join-Path $BackupPath "$StagingDatabase`_log.ldf"

    # SINGLE_USER قبل الاستبدال: اتصال واحد مفتوح من تشغيل سابق يمنع
    # الاسترجاع، والرسالة الخام لا تقول ذلك.
    $exists = [int](Invoke-Sql -Db 'master' -Query "SELECT COUNT(*) FROM sys.databases WHERE name = N'$StagingDatabase'")
    if ($exists -gt 0) {
        Invoke-Sql -Db 'master' -Query "ALTER DATABASE [$StagingDatabase] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;" | Out-Null
        Warn 'قاعدة التجربة قائمة — ستُستبدَل ببيانات الإنتاج.'
    }

    Invoke-Sql -Db 'master' -Query @"
RESTORE DATABASE [$StagingDatabase] FROM DISK = N'$($bak.FullName)'
WITH MOVE N'$dataName' TO N'$dataFile',
     MOVE N'$logName'  TO N'$logFile',
     REPLACE, RECOVERY;
"@ | Out-Null
    Invoke-Sql -Db 'master' -Query "ALTER DATABASE [$StagingDatabase] SET MULTI_USER;" | Out-Null

    $tables = [int](Invoke-Sql -Db $StagingDatabase -Query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'")
    Ok "استُرجعت بيانات الإنتاج — $tables جدولاً"
}

if ($RefreshData) {
    Write-Host ""
    Write-Host "  اكتفيتُ بتحديث البيانات (-RefreshData)." -ForegroundColor Green
    return
}

# ── الموقع والمجمّع ──────────────────────────────────────────────────────
Import-Module WebAdministration

Head 'مجمّع التطبيقات'
if (-not (Test-Path "IIS:\AppPools\$PoolName")) { New-WebAppPool -Name $PoolName | Out-Null }
Set-ItemProperty "IIS:\AppPools\$PoolName" -Name managedRuntimeVersion -Value ''
Ok "$PoolName جاهز (No Managed Code)"

$poolIdentity = "IIS APPPOOL\$PoolName"
Invoke-Sql -Db 'master' -Query @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$poolIdentity')
    CREATE LOGIN [$poolIdentity] FROM WINDOWS;
"@ | Out-Null
Invoke-Sql -Db $StagingDatabase -Query @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$poolIdentity')
    CREATE USER [$poolIdentity] FOR LOGIN [$poolIdentity];
ALTER ROLE db_datareader ADD MEMBER [$poolIdentity];
ALTER ROLE db_datawriter ADD MEMBER [$poolIdentity];
GRANT EXECUTE ON SCHEMA::dbo TO [$poolIdentity];
"@ | Out-Null
Ok 'صلاحيات القاعدة ممنوحة (بلا db_owner)'

Head 'الموقع'
New-Item -ItemType Directory -Force -Path (Join-Path $StagingPath 'backend') | Out-Null
if (-not (Get-Website -Name $SiteName -ErrorAction SilentlyContinue)) {
    New-Website -Name $SiteName -PhysicalPath (Join-Path $StagingPath 'backend') `
        -Port $Port -HostHeader $Domain -ApplicationPool $PoolName -Force | Out-Null
}
Ok "$SiteName على المنفذ $Port بترويسة $Domain"

# ── ملف الأسرار ──────────────────────────────────────────────────────────
Head 'ملف أسرار التجربة'
$settings = Join-Path $StagingPath 'backend\appsettings.Production.json'
if (Test-Path $settings) {
    Ok 'موجود — لم يُلمس'
} else {
    # مفتاح JWT مستقلّ عن الإنتاج بقصد: توكن صادر من التجربة يجب ألّا
    # يُقبل على بيانات العملاء إطلاقاً، والمفتاح المشترك يجعله مقبولاً.
    $bytes = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $key = [Convert]::ToBase64String($bytes)

    @{
        ConnectionStrings = @{ Default = "Server=$SqlInstance;Database=$StagingDatabase;Trusted_Connection=True;TrustServerCertificate=True;" }
        Jwt = @{ Key = $key }
        AllowedOrigins = "https://$Domain"
        Storage = @{ Path = 'C:\kinetic-staging-data\uploads' }
    } | ConvertTo-Json -Depth 6 | Set-Content $settings -Encoding UTF8

    New-Item -ItemType Directory -Force -Path 'C:\kinetic-staging-data\uploads' | Out-Null
    & icacls 'C:\kinetic-staging-data\uploads' /grant "$poolIdentity`:(OI)(CI)M" | Out-Null
    Ok 'أُنشئ بمفتاح JWT مستقلّ عن الإنتاج'
}

Write-Host ""
Write-Host "  بيئة التجربة جاهزة. انشر عليها بـ:" -ForegroundColor Green
Write-Host "    .\deploy_update.ps1 -Package C:\publish.zip ``" -ForegroundColor White
Write-Host "        -Target $StagingPath -SiteName $SiteName -PoolName $PoolName" -ForegroundColor White
Write-Host ""
Write-Host "  ولتحديث بياناتها من الإنتاج لاحقاً:  .\setup_staging.ps1 -Domain $Domain -RefreshData" -ForegroundColor Gray
