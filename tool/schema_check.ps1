<#
.SYNOPSIS
    يقارن أعمدة الكيانات في الكود بأعمدة قاعدة البيانات الفعلية.

.DESCRIPTION
    يكشف صنفاً من الأخطاء لا يكشفه المترجم ولا الاختبارات: عمود في الكيان
    لا نظير له في القاعدة. النتيجة استثناء وقت التشغيل عند أول استعلام
    يمسّ الجدول — لا عند البناء.

    وقع هذا فعلاً ثلاث مرّات في هذا المشروع:
      - BarcodeTemplateJson  ← barcode_template (لا barcode_template_json)
      - EnabledModulesJson   ← enabled_modules
      - ClientRequestId      ← client_request_id

    والأثر أوسع من الميزة المعنيّة: عمود واحد مفقود في جدول الفواتير أسقط
    لوحة التحكم والفواتير والتقارير والبحث عن الأصناف معاً، لأن كل استعلام
    على الجدول يفشل لا الاستعلام الجديد وحده.

    الفحص نصّي على ملف الكيانات: يستخرج الخصائص، ويحوّلها إلى snake_case
    كما يفعل UseSnakeCaseNamingConvention، ويقارن. لا يفهم HasColumnName
    فيُبلّغ عن الاستثناءات المعرَّفة صراحةً — تُمرَّر في KnownMappings أدناه.

.EXAMPLE
    .\tool\schema_check.ps1
    .\tool\schema_check.ps1 -SqlInstance .\SQLEXPRESS -Database KineticEnterprise
#>
[CmdletBinding()]
param(
    [string]$SqlInstance = '.\SQLEXPRESS',
    [string]$Database = 'KineticEnterprise',
    # يكتب لقطة (كيان ← جدول ← أعمدة) ثم يخرج بلا فحص. يستدعيها publish.ps1
    # لتسافر مع الحزمة.
    [string]$Emit
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$entities = Join-Path $root 'backend\KineticEnterprise.Api\Models\Entities.cs'
$context = Join-Path $root 'backend\KineticEnterprise.Api\Data\AppDbContext.cs'

# لقطة بديلة عن الشيفرة المصدرية.
#
# على السيرفر لا وجود لـEntities.cs ولا AppDbContext.cs — هناك DLL مبنيّة
# فقط. وفحص «عمود في الكيان بلا نظير في القاعدة» هو **أنفع ما يكون بعد
# ترقية على السيرفر**، أي في المكان الذي لا مصدر فيه. فتُبنى اللقطة على
# جهاز التطوير وتسافر مع الحزمة في sql\expected_schema.json.
$snapshot = @(
    (Join-Path $root 'sql\expected_schema.json'),
    (Join-Path $PSScriptRoot 'expected_schema.json')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$fromSource = (Test-Path $entities) -and (Test-Path $context)
if (-not $fromSource -and -not $snapshot) {
    throw "لا شيفرة مصدرية ولا لقطة. على جهاز التطوير شغّله من المستودع، وعلى السيرفر يلزم sql\expected_schema.json داخل مجلد النشر."
}

# خصائص لا تُخزَّن أو تُخزَّن باسم مختلف صراحةً عبر HasColumnName / Ignore.
$known = @{
    'BarcodeTemplateJson' = 'barcode_template'
    'EnabledModulesJson'  = 'enabled_modules'
}

function ConvertTo-SnakeCase([string]$name) {
    # نفس ما يفعله EFCore.NamingConventions: حدّ بين حرف صغير/رقم وحرف كبير.
    $s = [regex]::Replace($name, '([a-z0-9])([A-Z])', '$1_$2')
    $s = [regex]::Replace($s, '([A-Z]+)([A-Z][a-z])', '$1_$2')
    return $s.ToLower()
}

# ── خريطة الكيان ← الجدول ─────────────────────────────────────────────────
$entityToTable = @{}
if ($fromSource) {
    $ctxText = Get-Content -LiteralPath $context -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($ctxText, 'Entity<(\w+)>\(\)\.ToTable\("(\w+)"\)')) {
        $entityToTable[$m.Groups[1].Value] = $m.Groups[2].Value
    }
}

# ── خصائص كل كيان: من الشيفرة على جهاز التطوير، ومن اللقطة على السيرفر ──
$classes = @{}
if ($fromSource) {
    $text = Get-Content -LiteralPath $entities -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($text, '(?s)public class (\w+)\s*\{(.*?)\n\}')) {
        $name = $m.Groups[1].Value
        $body = $m.Groups[2].Value
        $props = @()
        foreach ($p in [regex]::Matches($body, 'public\s+(.+?)\s+(\w+)\s*\{\s*get;')) {
            # خصائص التنقّل (قوائم كيانات) لا تُقابل أعمدة. تُستبعَد **بنوعها لا
            # باسمها**: القائمة المكتوبة يدوياً (Items، Payments) نُسي تحديثها عند
            # إضافة Batches، فبلّغ الفاحص عن عمود مفقود لا وجود له وأخفى بذلك
            # نتيجة فحص العزل تحته.
            if ($p.Groups[1].Value -match '^(List|ICollection|IEnumerable|HashSet)\s*<') { continue }
            $props += $p.Groups[2].Value
        }
        $classes[$name] = $props
    }

}
else {
    # اللقطة تحمل أسماء الأعمدة نهائيةً (بعد snake_case وبعد الاستثناءات)،
    # فلا يُعاد اشتقاقها هنا — اشتقاقٌ ثانٍ بمنطق قد ينحرف يُنتج فحصاً يكذب.
    $snap = Get-Content -LiteralPath $snapshot -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($e in $snap.entities) {
        $entityToTable[$e.entity] = $e.table
        $classes[$e.entity] = @($e.columns)
        foreach ($c in $e.columns) { $known[$c] = $c }
    }
    Write-Host "  المصدر: لقطة $snapshot (بُنيت في $($snap.generatedAt))" -ForegroundColor DarkGray
}

# ── وضع الإصدار: يكتب اللقطة ويخرج ───────────────────────────────────────
if ($Emit) {
    if (-not $fromSource) { throw 'اللقطة تُبنى من الشيفرة المصدرية — شغّله من المستودع.' }
    $out = [ordered]@{
        generatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        entities = @(
            foreach ($e in ($entityToTable.Keys | Sort-Object)) {
                if (-not $classes.ContainsKey($e)) { continue }
                [ordered]@{
                    entity  = $e
                    table   = $entityToTable[$e]
                    columns = @($classes[$e] | ForEach-Object {
                        if ($known.ContainsKey($_)) { $known[$_] } else { ConvertTo-SnakeCase $_ }
                    })
                }
            }
        )
    }
    $dir = Split-Path -Parent $Emit
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $out | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $Emit -Encoding utf8
    Write-Host "لقطة المخطّط: $Emit ($($out.entities.Count) كياناً)" -ForegroundColor Green
    return
}

# ── أعمدة القاعدة ────────────────────────────────────────────────────────
$conn = New-Object System.Data.SqlClient.SqlConnection(
    "Server=$SqlInstance;Database=$Database;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=15")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = 'SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS'
$reader = $cmd.ExecuteReader()
$dbCols = @{}
while ($reader.Read()) {
    $t = $reader[0].ToString().ToLower()
    if (-not $dbCols.ContainsKey($t)) { $dbCols[$t] = New-Object System.Collections.Generic.HashSet[string] }
    [void]$dbCols[$t].Add($reader[1].ToString().ToLower())
}
$reader.Close()
$conn.Close()

Write-Host "`n=== فحص تطابق الكيانات مع $Database على $SqlInstance ===" -ForegroundColor White

$problems = 0
$checked = 0

foreach ($entity in ($entityToTable.Keys | Sort-Object)) {
    $table = $entityToTable[$entity]
    if (-not $dbCols.ContainsKey($table)) {
        Write-Host "  [جدول مفقود] $entity -> $table" -ForegroundColor Red
        $problems++
        continue
    }
    if (-not $classes.ContainsKey($entity)) { continue }

    $missing = @()
    foreach ($prop in $classes[$entity]) {
        $checked++
        $col = if ($known.ContainsKey($prop)) { $known[$prop] } else { ConvertTo-SnakeCase $prop }
        if (-not $dbCols[$table].Contains($col)) { $missing += "$prop -> $col" }
    }

    if ($missing.Count -gt 0) {
        Write-Host "  [$table]" -ForegroundColor Yellow
        foreach ($m in $missing) { Write-Host "      عمود مفقود: $m" -ForegroundColor Red }
        $problems += $missing.Count
    }
}


# ═══════════════════ فحص تغطية سياسات العزل ═══════════════════════════════
Write-Host ''
Write-Host '=== تغطية سياسات العزل (Row-Level Security) ===' -ForegroundColor White

# معفاة عمداً وبمبرّر موثَّق في المخطط — لا تُضاف لها سياسة أبداً:
#   app_users            : AuthController يبحث بالبريد قبل معرفة المنظمة،
#                          فلا سبيل لضبط السياق قبل تحديد المستخدم.
#   customer_card_index  : بوابة العميل تحدّد المنظمة من رمز البطاقة نفسه
#                          قبل وجود أي سياق.
#   permissions          : كتالوج عام لا يخصّ منظمة.
#   platform_*           : مستوى المنصّة لا مستوى العميل.
#   medicine_reference   : معرفة دوائية عامة لا بيانات منظمة — «باراسيتامول
#                          500 مجم» له نفس موانع الاستعمال في كل صيدلية.
#                          ربطه بالمنظمة كان يعني أن كل عميل جديد يبدأ
#                          بنشرات فارغة (راجع MedicineReference في
#                          Entities.cs). ولا سعر فيه ولا مخزون، فلا تسرّب.
$rlsExempt = @('app_users', 'customer_card_index', 'permissions',
               'platform_organizations', 'platform_settings',
               'medicine_reference')

$conn2 = New-Object System.Data.SqlClient.SqlConnection(
    "Server=$SqlInstance;Database=$Database;Integrated Security=true;TrustServerCertificate=true;Connection Timeout=15")
$conn2.Open()
$cmd2 = $conn2.CreateCommand()
$cmd2.CommandText = @"
SELECT t.name,
       CASE WHEN EXISTS (SELECT 1 FROM sys.security_predicates sp
                         WHERE sp.target_object_id = t.object_id) THEN 1 ELSE 0 END
FROM sys.tables t ORDER BY t.name
"@
$rd = $cmd2.ExecuteReader()
$unprotected = @()
$protected = 0
while ($rd.Read()) {
    if ([int]$rd[1] -eq 1) { $protected++ }
    elseif ($rlsExempt -notcontains $rd[0]) { $unprotected += $rd[0] }
}
$rd.Close()
$conn2.Close()

Write-Host "  محميّة: $protected جدولاً" -ForegroundColor Green
if ($unprotected.Count -gt 0) {
    Write-Host "  بلا سياسة وبلا إعفاء موثَّق:" -ForegroundColor Red
    foreach ($t in $unprotected) { Write-Host "      - $t" -ForegroundColor Red }
    Write-Host '  كل واحد منها يعني أن بيانات عميل تُقرأ من سياق عميل آخر.' -ForegroundColor Gray
    Write-Host '  إن كان الإعفاء مقصوداً فأضفه إلى $rlsExempt مع سببه.' -ForegroundColor Gray
    exit 1
} else {
    Write-Host '  لا جدول بلا حماية ولا إعفاء موثَّق' -ForegroundColor Green
}

Write-Host ''
if ($problems -eq 0) {
    Write-Host "  متطابق: $checked خاصية في $($entityToTable.Count) جدول" -ForegroundColor Green
} else {
    Write-Host "  $problems عدم تطابق — كل واحد منها استثناء وقت تشغيل ينتظر" -ForegroundColor Red
    Write-Host '  (بعضها قد يكون خاصية غير مخزَّنة — أضفها إلى $known في هذا الملف)' -ForegroundColor Gray
    exit 1
}
