<#
.SYNOPSIS
    يبني حزمة النشر التي تُرفع إلى السيرفر.

.DESCRIPTION
    يُنتج مجلداً واحداً (وملف ZIP) يحوي كل ما يحتاجه السيرفر:

        publish/
          backend/     ← الخادم مبنياً للإنتاج (win-x64)
          web/         ← تطبيق الويب مبنياً
          sql/         ← المخطط والترحيلات والفهارس
          appsettings.Production.template.json
          README-النشر.txt

    ما لا يدخل الحزمة عمداً: أي سرّ. ملف الإعدادات قالب بقيم فارغة يُملأ على
    السيرفر — نسخ ملف أسرار جاهز في حزمة تنتقل عبر البريد أو USB هو أسهل
    طريق لتسريب مفتاح توقيع JWT، ومفتاح مسرَّب يعني تزوير توكن لأي مستخدم
    في أي منظمة.

.PARAMETER ApiUrl
    اختياري. الويب يشتقّ عنوان الـAPI من أصل الصفحة وقت التشغيل، فالحزمة
    الواحدة تعمل على أي نطاق بلا إعادة بناء. مرّره فقط إن كان الـAPI على
    أصل مختلف عن الصفحة. مثال: https://erp.example.ly/api

.PARAMETER Output
    مجلد الإخراج. الافتراضي publish/ في جذر المشروع.

.PARAMETER SkipWeb
    تخطّي بناء الويب (للنشر على خادم API فقط).

.EXAMPLE
    .	ool\publish.ps1
    .	ool\publish.ps1 -ApiUrl https://erp.example.ly/api
#>
[CmdletBinding()]
param(
    # اختياري: الويب يشتقّ العنوان من أصل الصفحة. مرّره فقط إن كان الـAPI
    # على أصل مختلف عن الصفحة.
    [string]$ApiUrl,
    [string]$Output,
    [switch]$SkipWeb,
    # للتجربة الأولى على عنوان IP قبل توفّر النطاق والشهادة. لا يُستعمل
    # لتسليم حقيقي: التوكنات وكلمات المرور تمرّ نصاً واضحاً على الشبكة.
    [switch]$AllowInsecure
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
if (-not $Output) { $Output = Join-Path $root 'publish' }
$api = Join-Path $root 'backend\KineticEnterprise.Api'

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "    $t" -ForegroundColor Green }

if ($ApiUrl -and $ApiUrl -notmatch '^https://') {
    if (-not $AllowInsecure) {
        # HTTP يعني توكن JWT وكلمات مرور تمرّ بنصّ ظاهر على الشبكة.
        throw "ApiUrl يجب أن يبدأ بـ https:// — أو مرّر -AllowInsecure لتجربة أولى على IP."
    }
    Write-Host ''
    Write-Host '  ############################################################' -ForegroundColor Red
    Write-Host '  #  حزمة غير آمنة — للتجربة وحدها                          #' -ForegroundColor Red
    Write-Host '  #  HTTP يعني أن توكن الدخول وكلمات المرور تمرّ نصاً        #' -ForegroundColor Red
    Write-Host '  #  واضحاً على الشبكة. لا تُسلَّم لعميل ولا تُترك تعمل.      #' -ForegroundColor Red
    Write-Host '  #  وتطبيق أندرويد لن يتصل بها إطلاقاً (سياسة الشبكة).      #' -ForegroundColor Red
    Write-Host '  ############################################################' -ForegroundColor Red
    Write-Host ''
}
if ($ApiUrl -and $ApiUrl -notmatch '/api/?$') {
    throw "ApiUrl يجب أن ينتهي بـ /api — هذا ما يتوقّعه ApiClient.baseUrl."
}

Write-Host "`n=== بناء حزمة النشر ===" -ForegroundColor White
Write-Host "    عنوان الـ API: $(if ($ApiUrl) { $ApiUrl } else { 'يُشتقّ من أصل الصفحة — الحزمة تعمل على أي نطاق' })"

# ── 1. تنظيف ────────────────────────────────────────────────────────────
Step 1 'تنظيف مجلد الإخراج'
if (Test-Path $Output) { Remove-Item -LiteralPath $Output -Recurse -Force }
New-Item -ItemType Directory -Path $Output | Out-Null
Ok $Output

# ── 2. اختبارات قبل البناء ──────────────────────────────────────────────
Step 2 'التحقّق قبل البناء'
Push-Location $root
try {
    & dart analyze lib
    if ($LASTEXITCODE -ne 0) { throw 'dart analyze فشل — لا تُبنى حزمة من شيفرة بها أخطاء.' }
    Ok 'dart analyze نظيف'
} finally { Pop-Location }

# ── 3. الخادم ───────────────────────────────────────────────────────────
Step 3 'بناء الخادم (win-x64، self-contained=false)'
$backendOut = Join-Path $Output 'backend'
Push-Location $api
try {
    # self-contained=false يعتمد على .NET Hosting Bundle المثبَّت على
    # السيرفر (راجع DEPLOYMENT.md §2ج) — حزمة أصغر بعشرات الميغابايت،
    # وتحديثات الأمان تأتي مع تحديث الويندوز لا مع إعادة نشر التطبيق.
    & dotnet publish -c Release -r win-x64 --self-contained false -o $backendOut
    if ($LASTEXITCODE -ne 0) { throw 'dotnet publish فشل' }
} finally { Pop-Location }

# حارس: ملف أسرار تسلّل إلى المخرجات
Get-ChildItem -Path $backendOut -Filter 'appsettings.*.json' | ForEach-Object {
    if ($_.Name -match 'Production|Development|Local') {
        Remove-Item $_.FullName -Force
        Write-Host "    أُزيل من الحزمة: $($_.Name)" -ForegroundColor Yellow
    }
}
Ok 'الخادم جاهز'

# ── 4. تطبيق الويب ──────────────────────────────────────────────────────
if (-not $SkipWeb) {
    Step 4 'بناء تطبيق الويب'
    Push-Location $root
    try {
        # بلا --dart-define: الويب يشتقّ عنوان الـAPI من أصل الصفحة وقت
        # التشغيل (راجع ApiClient.baseUrl)، فالحزمة الواحدة تعمل على أي
        # نطاق. ويُخبَز العنوان فقط إن مُرِّر -ApiUrl صراحةً — حالة استضافة
        # الـAPI على أصل مختلف.
        if ($ApiUrl) {
            & flutter build web --release --dart-define=API_BASE_URL=$ApiUrl
        } else {
            & flutter build web --release
        }
        if ($LASTEXITCODE -ne 0) { throw 'flutter build web فشل' }
    } finally { Pop-Location }
    # داخل wwwroot لا في مجلد منفصل: الخادم يخدم الويب من جذره (راجع
    # UseStaticFiles في Program.cs)، فموقع IIS واحد يكفي — ولا تركيب تطبيق
    # فرعي تحت /api يُضاعف بادئة المسار.
    $wwwroot = Join-Path $backendOut 'wwwroot'
    if (Test-Path $wwwroot) { Remove-Item $wwwroot -Recurse -Force }
    Copy-Item -Path (Join-Path $root 'build\web') -Destination $wwwroot -Recurse
    Ok 'الويب جاهز داخل backend\wwwroot'
}

# ── 5. ملفات SQL ────────────────────────────────────────────────────────
Step 5 'ملفات قاعدة البيانات'
$sqlOut = Join-Path $Output 'sql'
New-Item -ItemType Directory -Path $sqlOut | Out-Null
foreach ($f in @('docs\DATABASE_SCHEMA_SQLSERVER.sql', 'docs\MIGRATIONS.sql', 'docs\INDEXES.sql')) {
    $p = Join-Path $root $f
    if (Test-Path $p) { Copy-Item $p $sqlOut; Ok (Split-Path $f -Leaf) }
}

# ── 6. قالب الإعدادات ───────────────────────────────────────────────────
Step 6 'قالب الإعدادات'
@'
{
  "// تحذير": "املأ هذا الملف على السيرفر وحده. لا يُرفع على Git أبداً.",
  "// المفتاح": "ولّد مفتاحاً عشوائياً جديداً — لا تنسخ مفتاح جهاز التطوير. راجع DEPLOYMENT.md",

  "ConnectionStrings": {
    "Default": "Server=.\\SQLEXPRESS;Database=KineticEnterprise;Trusted_Connection=True;TrustServerCertificate=True;"
  },
  "Jwt": {
    "Key": "",
    "Issuer": "KineticEnterprise.Api",
    "Audience": "KineticEnterprise.Client"
  },
  "AllowedOrigins": "https://erp.example.ly"
}
'@ | Out-File -LiteralPath (Join-Path $Output 'appsettings.Production.template.json') -Encoding utf8
Ok 'appsettings.Production.template.json'

# ── 7. تعليمات مرافقة ───────────────────────────────────────────────────
Step 7 'تعليمات مرافقة'
@"
تثبيت Kinetic Enterprise على السيرفر
=====================================
حُزمت في: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
عنوان الـ API: $(if ($ApiUrl) { "مخبوز — $ApiUrl" } else { 'يُشتقّ من أصل الصفحة وقت التشغيل (يعمل على أي نطاق)' })

الترتيب مُلزَم — كل خطوة تعتمد على ما قبلها.

1) قاعدة البيانات
   sqlcmd -S .\SQLEXPRESS -E -I -i "sql\DATABASE_SCHEMA_SQLSERVER.sql"
   sqlcmd -S .\SQLEXPRESS -E -I -d KineticEnterprise -i "sql\MIGRATIONS.sql"
   sqlcmd -S .\SQLEXPRESS -E -I -d KineticEnterprise -i "sql\INDEXES.sql"

   على ترقية لقاعدة قائمة: نفّذ MIGRATIONS.sql وINDEXES.sql وحدهما.
   كلاهما آمن للإعادة (IF NOT EXISTS حول كل تغيير).

2) الأسرار
   انسخ appsettings.Production.template.json إلى داخل backend\ باسم
   appsettings.Production.json ثم املأه:
     - ConnectionStrings:Default  حساب SQL مقيَّد الصلاحيات لا db_owner
     - Jwt:Key                    مفتاح جديد عشوائي، 32 بايت على الأقل:
         [Convert]::ToBase64String((1..48|%{Get-Random -Max 256}))
     - AllowedOrigins             نطاقك الحقيقي لا localhost

3) الخادم
   انسخ backend\ إلى C:\inetpub\kinetic-api ثم أنشئ موقعاً في IIS يشير إليه
   بـ Application Pool من نوع "No Managed Code".
   تأكّد من تثبيت ASP.NET Core 8 Hosting Bundle أولاً.

4) الويب
   انسخ web\ إلى موقع IIS آخر (أو مجلد فرعي) على النطاق نفسه.
   إن اختلف النطاق فأضفه إلى AllowedOrigins وإلا حجبه CORS.

5) أول حساب
   من مجلد الخادم على السيرفر:
     dotnet KineticEnterprise.Api.dll create-platform-owner
   أمر تفاعلي — شغّله من نافذة أوامر حقيقية لا عبر خدمة.

6) قبل التسليم
   راجع "ملخص فحص ما قبل الإطلاق" في DEPLOYMENT.md — وخاصةً:
   HTTPS بشهادة حقيقية، ونسخ احتياطي مجدوَل ومختبَر الاسترجاع.
"@ | Out-File -LiteralPath (Join-Path $Output 'README-النشر.txt') -Encoding utf8
Ok 'README-النشر.txt'

# ── 8. ضغط ──────────────────────────────────────────────────────────────
Step 8 'ضغط الحزمة'
$zip = "$Output.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

# ZipFile بدل Compress-Archive: الأخير يقرأ كل ملف على حدة فيتعثّر بأي ملف
# يقفله برنامج آخر لحظتها (المضاد للفيروسات يفحص مخرجات البناء فور كتابتها).
# وإعادة المحاولة تحلّ القفل العابر بدل إفشال حزمة اكتملت خطواتها كلها.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipped = $false
foreach ($attempt in 1..3) {
    try {
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $Output, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        $zipped = $true
        break
    } catch {
        if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        if ($attempt -eq 3) {
            Write-Host "    تعذّر الضغط: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "    المجلد جاهز رغم ذلك — اضغطه يدوياً: $Output" -ForegroundColor Yellow
        } else {
            Start-Sleep -Seconds 3
        }
    }
}
if (-not $zipped) { return }
$sizeMb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Ok "$zip ($sizeMb ميغابايت)"

Write-Host "`nتمّت الحزمة. ارفع الملف التالي إلى السيرفر:" -ForegroundColor Green
Write-Host "    $zip`n" -ForegroundColor White
