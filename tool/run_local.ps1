<#
.SYNOPSIS
    تجهيز وتشغيل النظام كاملاً على جهاز التطوير للتجربة في المتصفح.

.DESCRIPTION
    يُنشئ قاعدة بيانات محلية منفصلة، ويولّد أسرار التطوير، ويشغّل الخادم
    وتطبيق الويب معاً.

    آمن على بياناتك القائمة: يُنشئ قاعدة باسم مستقل (KineticLocal افتراضياً)
    ولا يلمس أي قاعدة أخرى. ويرفض المتابعة إن كانت القاعدة موجودة إلا مع
    -Recreate الصريح.

.PARAMETER Database
    اسم قاعدة بيانات التجربة. الافتراضي KineticLocal.

.PARAMETER SqlInstance
    نسخة SQL Server. الافتراضي localhost.

.PARAMETER Recreate
    يحذف قاعدة التجربة ويعيد بناءها من الصفر. مدمِّر — لقاعدة التجربة وحدها.

.PARAMETER SetupOnly
    يجهّز القاعدة والأسرار ثم يتوقّف بلا تشغيل.

.EXAMPLE
    .\tool\run_local.ps1
    .\tool\run_local.ps1 -Recreate
#>
[CmdletBinding()]
param(
    [string]$Database = 'KineticLocal',
    [string]$SqlInstance = 'localhost',
    [switch]$Recreate,
    [switch]$SetupOnly
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$api = Join-Path $root 'backend\KineticEnterprise.Api'
$settings = Join-Path $api 'appsettings.Development.json'

function Step($n, $text) { Write-Host "`n[$n] $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "    $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }

function Invoke-Sql {
    param([string]$Db, [string]$Query, [string]$File)
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=$Db;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=10")
    $conn.Open()
    try {
        $text = if ($File) { Get-Content -LiteralPath $File -Raw -Encoding UTF8 } else { $Query }
        # SqlClient لا يفهم GO — هو فاصل دفعات في أدوات مايكروسوفت لا أمر SQL.
        # تقسيم النص عليه هو ما يجعل ملف المخطط ينفَّذ كما ينفَّذ في SSMS.
        $batches = [regex]::Split($text, '(?im)^\s*GO\s*$')
        foreach ($batch in $batches) {
            if ([string]::IsNullOrWhiteSpace($batch)) { continue }
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $batch
            $cmd.CommandTimeout = 180
            [void]$cmd.ExecuteNonQuery()
        }
    } finally { $conn.Close() }
}

function Test-Database {
    param([string]$Name)
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=master;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=10")
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT COUNT(*) FROM sys.databases WHERE name = @n"
        [void]$cmd.Parameters.AddWithValue('@n', $Name)
        return ([int]$cmd.ExecuteScalar()) -gt 0
    } finally { $conn.Close() }
}

Write-Host "`n=== تشغيل Kinetic Enterprise محلياً ===" -ForegroundColor White
Write-Host "    قاعدة التجربة: $Database على $SqlInstance"

# ── 1. فحص المتطلبات ────────────────────────────────────────────────────
Step 1 'فحص المتطلبات'

# Flutter لا يُضيف نفسه إلى PATH عند التثبيت اليدوي (وهو الشائع على ويندوز)،
# فالفشل بـ«غير موجود» بينما هو مثبَّت فعلاً إزعاج بلا داعٍ. نبحث في
# المواضع المعتادة قبل الاستسلام، ونضيفه إلى PATH لهذه الجلسة وحدها.
if (-not (Get-Command 'flutter' -ErrorAction SilentlyContinue)) {
    $guesses = @(
        'C:\src\flutter\bin',
        "$env:LOCALAPPDATA\flutter\bin",
        "$env:USERPROFILE\flutter\bin",
        'C:\flutter\bin',
        'C:\tools\flutter\bin'
    )
    foreach ($g in $guesses) {
        if (Test-Path (Join-Path $g 'flutter.bat')) {
            $env:PATH = "$env:PATH;$g"
            Warn "flutter غير موجود في PATH — استُعمل $g لهذه الجلسة"
            break
        }
    }
}

foreach ($tool in @('dotnet', 'flutter')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool غير موجود في PATH. ثبّته أو أضف مجلد bin الخاص به إلى PATH."
    }
    Ok "$tool موجود"
}

# ── 2. قاعدة البيانات ───────────────────────────────────────────────────
Step 2 'قاعدة البيانات'
$exists = Test-Database -Name $Database

if ($exists -and $Recreate) {
    Warn "حذف $Database وإعادة بنائها…"
    # SINGLE_USER يفصل أي اتصال قائم؛ بدونه يفشل DROP إن كان الخادم يعمل.
    Invoke-Sql -Db 'master' -Query @"
ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$Database];
"@
    $exists = $false
}

if ($exists) {
    Ok "$Database موجودة — تُستخدم كما هي (استعمل -Recreate لإعادة بنائها)"
} else {
    Invoke-Sql -Db 'master' -Query "CREATE DATABASE [$Database];"
    Ok "أُنشئت $Database"

    Invoke-Sql -Db $Database -File (Join-Path $root 'docs\DATABASE_SCHEMA_SQLSERVER.sql')
    Ok 'نُفِّذ المخطط الأساسي'
}

# الترحيلات والفهارس تُنفَّذ دائماً: كلاهما مكتوب ليُعاد تنفيذه بلا خطر
# (IF NOT EXISTS حول كل تغيير)، وهذا ما يجعل تشغيل السكربت مراراً آمناً.
foreach ($file in @('docs\MIGRATIONS.sql', 'docs\INDEXES.sql')) {
    $path = Join-Path $root $file
    if (Test-Path $path) {
        Invoke-Sql -Db $Database -File $path
        Ok "نُفِّذ $file"
    }
}

# ── 3. أسرار التطوير ────────────────────────────────────────────────────
Step 3 'أسرار التطوير'
if (Test-Path $settings) {
    Ok 'appsettings.Development.json موجود — يُترك كما هو'
} else {
    # مفتاح عشوائي حقيقي لا قيمة ثابتة: ملف التطوير مستثنى من Git، لكن
    # مفتاحاً ثابتاً في سكربت مرفوع يعني أن كل من نسخ المستودع يملك مفتاح
    # توقيع جهازك — ويستطيع تزوير توكن صالح على أي نسخة تطوير.
    $bytes = New-Object byte[] 48
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $jwtKey = [Convert]::ToBase64String($bytes)

    $config = [ordered]@{
        ConnectionStrings = [ordered]@{
            Default = "Server=$SqlInstance;Database=$Database;Integrated Security=true;TrustServerCertificate=true"
        }
        Jwt = [ordered]@{
            Key      = $jwtKey
            Issuer   = 'KineticEnterprise.Api'
            Audience = 'KineticEnterprise.Client'
        }
        AllowedOrigins = 'http://localhost:8080,http://127.0.0.1:8080'
    }
    $config | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $settings -Encoding utf8
    Ok 'أُنشئ appsettings.Development.json بمفتاح JWT عشوائي (مستثنى من Git)'
}

# ── 4. حساب مالك المنصة ─────────────────────────────────────────────────
Step 4 'حساب مالك المنصة'
$hasOwner = $false
try {
    $conn = New-Object System.Data.SqlClient.SqlConnection(
        "Server=$SqlInstance;Database=$Database;Integrated Security=true;TrustServerCertificate=true")
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 'SELECT COUNT(*) FROM dbo.app_users WHERE is_platform_admin = 1'
    $hasOwner = ([int]$cmd.ExecuteScalar()) -gt 0
    $conn.Close()
} catch { }

if ($hasOwner) {
    Ok 'يوجد حساب مالك منصة'
} else {
    Warn 'لا يوجد حساب مالك منصة بعد. شغّل في نافذة أوامر منفصلة:'
    Write-Host "        cd `"$api`"" -ForegroundColor White
    Write-Host '        dotnet run -- create-platform-owner' -ForegroundColor White
    Warn 'الأمر تفاعلي (يقرأ كلمة المرور بلا إظهار) فلا يمكن تشغيله من هنا.'
}

if ($SetupOnly) {
    Write-Host "`nجاهز. أعد التشغيل بلا -SetupOnly للتشغيل الفعلي.`n" -ForegroundColor Green
    return
}

# ── 5. التشغيل ──────────────────────────────────────────────────────────
Step 5 'تشغيل الخادم وتطبيق الويب'

# ASPNETCORE_ENVIRONMENT=Development هو ما يجعل الخادم يقرأ ملف الأسرار
# الذي أنشأناه أعلاه بدل appsettings.json الفارغ.
$env:ASPNETCORE_ENVIRONMENT = 'Development'

$backend = Start-Process -FilePath 'dotnet' -ArgumentList 'run' -WorkingDirectory $api -PassThru
Ok "الخادم يعمل (PID $($backend.Id)) على https://localhost:5001"

Write-Host "`n    انتظار جهوزية الخادم…" -ForegroundColor Gray
$ready = $false
foreach ($i in 1..30) {
    Start-Sleep -Seconds 2
    try {
        # -SkipCertificateCheck ضروري: شهادة التطوير موقّعة ذاتياً.
        $null = Invoke-WebRequest -Uri 'https://localhost:5001/api/platform-settings' `
            -SkipCertificateCheck -TimeoutSec 3 -ErrorAction Stop
        $ready = $true; break
    } catch {
        # 401 يعني أن الخادم يردّ ويطبّق المصادقة — أي أنه جاهز تماماً.
        if ($_.Exception.Response.StatusCode.value__ -in @(401, 403)) { $ready = $true; break }
    }
}
if ($ready) { Ok 'الخادم يستجيب' } else { Warn 'الخادم لم يستجب بعد ٦٠ ثانية — راجع نافذته' }

Write-Host ''
Write-Host '    تشغيل تطبيق الويب على http://localhost:8080 …' -ForegroundColor Gray
Write-Host '    (اتركه يعمل؛ أغلق بـ Ctrl+C ثم أوقف الخادم بنافذته)' -ForegroundColor Gray
Write-Host ''

flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1 `
    --dart-define=API_BASE_URL=https://localhost:5001/api
