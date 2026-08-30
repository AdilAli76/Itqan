<#
.SYNOPSIS
    يبني حزمة النشر التي تُرفع إلى السيرفر.

.DESCRIPTION
    يُنتج مجلداً واحداً (وملف ZIP) يحوي كل ما يحتاجه السيرفر:

        publish/
          backend/     ← الخادم مبنياً للإنتاج (win-x64)، وتطبيق الويب
                         داخل backend\wwwroot (موقع IIS واحد يخدمهما معاً)
          sql/         ← المخطط والترحيلات والفهارس
          tool/        ← سكربتات التشغيل على السيرفر
          appsettings.Production.template.json
          README-النشر.txt

    ما لا يدخل الحزمة عمداً: أي سرّ. ملف الإعدادات قالب بقيم فارغة يُملأ على
    السيرفر — نسخ ملف أسرار جاهز في حزمة تنتقل عبر البريد أو USB هو أسهل
    طريق لتسريب مفتاح توقيع JWT، ومفتاح مسرَّب يعني تزوير توكن لأي مستخدم
    في أي منظمة.

.PARAMETER ApiUrl
    اختياري. الويب يشتقّ عنوان الـAPI من أصل الصفحة وقت التشغيل، فالحزمة
    الواحدة تعمل على أي نطاق بلا إعادة بناء. مرّره فقط إن كان الـAPI على
    أصل مختلف عن الصفحة. مثال: https://erp.droob-albayan.ly/api

.PARAMETER Output
    مجلد الإخراج. الافتراضي publish/ في جذر المشروع.

.PARAMETER SkipWeb
    تخطّي بناء الويب (للنشر على خادم API فقط).

.EXAMPLE
    .\tool\publish.ps1
    .\tool\publish.ps1 -ApiUrl https://erp.droob-albayan.ly/api
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
function Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }

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
# المحتوى أولاً ثم المجلد نفسه — وفشل الأخير لا يوقف البناء.
#
# مجلد الإخراج يبقى مفتوحاً في المستكشف أو تحت فحص المضاد أو المفهرس، فيُقفل
# **المجلد** بينما محتواه قابل للحذف. وRemove-Item -Recurse يفشل حينها فيسقط
# البناء كلّه عند خطوته الأولى — لسبب لا علاقة له بالشيفرة، ولا يفهمه من
# يقرأ الرسالة. وقع فعلاً.
if (Test-Path $Output) {
    Get-ChildItem -LiteralPath $Output -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # المتبقّي بعد المحاولة يعني قفلاً على ملف بعينه — وهذا يوقف البناء
    # فعلاً، لأن حزمةً تخلط ملفات نسختين أسوأ من بناء يفشل.
    $left = @(Get-ChildItem -LiteralPath $Output -Force -Recurse -ErrorAction SilentlyContinue)
    if ($left.Count -gt 0) {
        throw "تعذّر تفريغ $Output — $($left.Count) عنصراً ما زال مقفولاً. أغلق ما يفتحه ثم أعد المحاولة، أو مرّر -Output بمسار آخر."
    }
} else {
    New-Item -ItemType Directory -Path $Output | Out-Null
}
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

    # ── ضغط الأصول مرّة واحدة بأقصى جودة ────────────────────────────────
    #
    # يُنفَّذ بالحزمة نفسها لا بـPowerShell: BrotliStream غير موجود في
    # Windows PowerShell 5.1 (يحتاج .NET Core)، وهو المثبَّت افتراضياً على
    # ويندوز. راجع WebAssetCompressor لسبب الضغط وقت البناء لا وقت الطلب.
    $apiDll = Join-Path $backendOut 'KineticEnterprise.Api.dll'
    if (Test-Path $apiDll) {
        & dotnet $apiDll compress-web $wwwroot
        if ($LASTEXITCODE -ne 0) { throw 'ضغط أصول الويب فشل' }
    } else {
        Warn 'لم يُعثر على الحزمة لتشغيل ضغط الأصول — تُنشر بلا ضغط مسبق'
    }
}

# ── 5. ملفات SQL ────────────────────────────────────────────────────────
Step 5 'ملفات قاعدة البيانات'
$sqlOut = Join-Path $Output 'sql'
New-Item -ItemType Directory -Path $sqlOut | Out-Null
foreach ($f in @('docs\DATABASE_SCHEMA_SQLSERVER.sql', 'docs\MIGRATIONS.sql', 'docs\INDEXES.sql')) {
    $p = Join-Path $root $f
    if (Test-Path $p) { Copy-Item $p $sqlOut; Ok (Split-Path $f -Leaf) }
}

# لقطة المخطّط المتوقَّع — ما يجعل schema_check يعمل على السيرفر.
#
# الفاحص يقرأ Entities.cs وAppDbContext.cs، وهما غير موجودين على السيرفر
# (هناك DLL مبنيّة فقط). واللقطة تُبنى هنا من المصدر نفسه فتسافر مع الحزمة،
# فيبقى الفحص ممكناً في المكان الذي يهمّ فيه أكثر: بعد الترقية على الإنتاج.
& (Join-Path $root 'tool\schema_check.ps1') -Emit (Join-Path $sqlOut 'expected_schema.json')
Ok 'expected_schema.json'

# ── 5.5 سكربتات السيرفر ─────────────────────────────────────────────────
#
#  كانت الحزمة تصل بلا أي سكربت، فتصبح تعليمات README تركيباً يدوياً كاملاً
#  في IIS — وهي بالضبط الخطوات التي كتبنا server_setup.ps1 لأتمتتها. ومن
#  يفتح الحزمة على السيرفر لا يملك المستودع أصلاً، فأمرٌ مثل
#  `tool\server_setup.ps1` كان يفشل عنده بـ«الملف غير موجود».
#
#  ولا تدخل الحزمة أدوات التطوير (publish، run_local، capture_fixtures،
#  generate_app_icons): لا معنى لها على سيرفر بلا مستودع ولا Flutter، ووجودها
#  يوحي بأنها جزء من التشغيل.
Step 5.5 'سكربتات السيرفر'
$toolOut = Join-Path $Output 'tool'
New-Item -ItemType Directory -Path $toolOut | Out-Null
foreach ($f in @('server_setup.ps1', 'setup_staging.ps1', 'backup.ps1',
                 'deploy_update.ps1', 'schema_check.ps1', 'api_test.ps1',
                 'install_local.ps1', 'runner_setup.ps1')) {
    $p = Join-Path $root "tool\$f"
    if (Test-Path $p) { Copy-Item $p $toolOut; Ok $f }
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
  "AllowedOrigins": "https://erp.droob-albayan.ly"
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

3) الخادم والويب معاً — موقع IIS واحد
   تطبيق الويب مبنيٌّ داخل backend\wwwroot، فالخادم يخدمه من جذره ولا حاجة
   إلى موقع ثانٍ ولا إلى CORS أصلاً.

   من نافذة PowerShell **كمسؤول**، ومن مجلد الحزمة نفسه:
     .\tool\server_setup.ps1 -Stage iis -Domain erp.droob-albayan.ly

   ثم بعد ربط شهادة HTTPS:
     .\tool\server_setup.ps1 -Stage verify -Domain erp.droob-albayan.ly

   مرحلة verify هي ما يفعّل UseHttpsRedirection — لا تُفعّله يدوياً قبل
   الشهادة، فكل طلب يُحوَّل إلى https على خادم بلا شهادة يفشل تماماً.

   يدوياً إن لزم: انسخ backend\ إلى C:\inetpub\kinetic-api وأنشئ موقعاً
   بـ Application Pool من نوع "No Managed Code". وثبّت
   ASP.NET Core 8 Hosting Bundle أولاً في الحالتين.

4) بيئة التجربة (اختياري)
     .\tool\setup_staging.ps1
   النطاق الافتراضي staging-erp.droob-albayan.ly، وقاعدة وموقع ومجمّع
   مستقلّة تماماً عن الإنتاج. تأخذ بياناتها من آخر نسخة احتياطية —
   خذ واحدة بـ tool\backup.ps1 أولاً وإلا أُنشئت قاعدة فارغة.

5) أول حساب
   من مجلد الخادم على السيرفر:
     dotnet KineticEnterprise.Api.dll create-platform-owner
   أمر تفاعلي — شغّله من نافذة أوامر حقيقية لا عبر خدمة.

══════════════════════════════════════════════════════════════════════
  التركيب المحلّي — للمحلّ الواحد بلا فروع وبلا إنترنت
══════════════════════════════════════════════════════════════════════

  لا تتبع الخطوات 1–5 أعلاه. كلها في أمر واحد على جهاز المحلّ، من نافذة
  PowerShell **كمسؤول**:

     .\tool\install_local.ps1 -LicensePublicKey C:\key\public.pem

  يُنشئ القاعدة، ويسجّل الخادم خدمةَ ويندوز تعمل مع الإقلاع، ويفتح المنفذ
  على الشبكة الخاصّة وحدها، ويجدول نسخة احتياطية، ويطبع بصمة الجهاز.

  ولجهاز واحد لا كاشير ثانٍ معه:  -LocalhostOnly

  ثلاثة فروق جوهرية عن التركيب السحابي، مقصودة كلّها:
    • لا IIS — Kestrel كخدمة يكفي محلّاً واحداً وأقلُّ ما يُركَّب أقلُّ ما يُعطَب.
    • لا HTTPS — لا نطاق ولا إنترنت للتجديد، وشهادةٌ موقَّعة ذاتياً تُدرّب
      المستخدم على تجاوز تحذير الأمان. الحماية حدُّ الشبكة: لا تصل الجهاز
      بشبكة عامّة ولا تفتح المنفذ في الراوتر.
    • مفتاح الترخيص العامّ **يلزم فعلاً** هنا: القاعدة بيد الزبون، فبلا
      توقيع لا شيء يمنع تعديل تاريخ الانتهاء بسطر SQL واحد.

6) قبل التسليم
   راجع "ملخص فحص ما قبل الإطلاق" في DEPLOYMENT.md — وخاصةً:
   HTTPS بشهادة حقيقية، ونسخ احتياطي مجدوَل ومختبَر الاسترجاع.

   وفحصان جاهزان في tool\:
     .\tool\schema_check.ps1 -SqlInstance .\SQLEXPRESS -Database KineticEnterprise
        يكشف عموداً في الكود بلا نظير في القاعدة، وجدولاً بلا عزل صفوف.
     .\tool\api_test.ps1 -BaseUrl https://erp.droob-albayan.ly/api
        يختبر قواعد العمل على الخادم نفسه. يكتب بيانات باسم TEST- .
"@ | Out-File -LiteralPath (Join-Path $Output 'README-النشر.txt') -Encoding utf8
Ok 'README-النشر.txt'

# ── 8. ضغط ──────────────────────────────────────────────────────────────
Step 8 'ضغط الحزمة'

# اسمٌ مؤرَّخ لا اسمٌ ثابت: kinetic_pkg_2026-08-29_1226.zip
#
# كانت الحزمة تُسمّى publish.zip دائماً، فلا يُميَّز جديدُها من قديمها إلا
# بقراءة تاريخ الملف. ووقع ذلك فعلاً: بناءٌ فشل صامتاً فبقيت حزمة الأمس
# مكانها، ورُفعت على أنها الجديدة ولم يلاحظ أحد.
#
# والاسم يحمل kinetic_pkg لأنه ما يُعرَف به على الخادم — و«publish» اسمٌ
# عامّ يصطدم بأي مجلد نشر آخر عند فكّه.
$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$zip = Join-Path (Split-Path -Parent $Output) "kinetic_pkg_$stamp.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

# والحزم الأقدم من ثلاث تُزال: مجلدٌ فيه عشرون حزمة يجعل اختيار الصحيحة
# تخميناً، وكلٌّ منها يشغل خمسين ميغابايت.
Get-ChildItem -Path (Split-Path -Parent $Output) -Filter 'kinetic_pkg_*.zip' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 3 |
    ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Warn "أُزيلت حزمة قديمة: $($_.Name)"
    }

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
Write-Host "    $zip" -ForegroundColor White
Write-Host "    بُنيت: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n" -ForegroundColor DarkGray
