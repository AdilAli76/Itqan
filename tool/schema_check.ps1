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
    [string]$SqlInstance = '.\SQLEXPRESS01',
    [string]$Database = 'KineticEnterprise'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
$entities = Join-Path $root 'backend\KineticEnterprise.Api\Models\Entities.cs'
$context = Join-Path $root 'backend\KineticEnterprise.Api\Data\AppDbContext.cs'

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

# ── خريطة الكيان ← الجدول من AppDbContext ────────────────────────────────
$ctxText = Get-Content -LiteralPath $context -Raw -Encoding UTF8
$entityToTable = @{}
foreach ($m in [regex]::Matches($ctxText, 'Entity<(\w+)>\(\)\.ToTable\("(\w+)"\)')) {
    $entityToTable[$m.Groups[1].Value] = $m.Groups[2].Value
}

# ── خصائص كل كيان من Entities.cs ─────────────────────────────────────────
$text = Get-Content -LiteralPath $entities -Raw -Encoding UTF8
$classes = @{}
foreach ($m in [regex]::Matches($text, '(?s)public class (\w+)\s*\{(.*?)\n\}')) {
    $name = $m.Groups[1].Value
    $body = $m.Groups[2].Value
    $props = @()
    foreach ($p in [regex]::Matches($body, 'public\s+[\w<>,\?\[\]\s]+?\s+(\w+)\s*\{\s*get;')) {
        $props += $p.Groups[1].Value
    }
    $classes[$name] = $props
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
        # خصائص التنقّل (قوائم كيانات) لا تُقابل أعمدة
        if ($prop -match '^(Items|Payments)$') { continue }
        if (-not $dbCols[$table].Contains($col)) { $missing += "$prop -> $col" }
    }

    if ($missing.Count -gt 0) {
        Write-Host "  [$table]" -ForegroundColor Yellow
        foreach ($m in $missing) { Write-Host "      عمود مفقود: $m" -ForegroundColor Red }
        $problems += $missing.Count
    }
}

Write-Host ''
if ($problems -eq 0) {
    Write-Host "  متطابق: $checked خاصية في $($entityToTable.Count) جدول" -ForegroundColor Green
} else {
    Write-Host "  $problems عدم تطابق — كل واحد منها استثناء وقت تشغيل ينتظر" -ForegroundColor Red
    Write-Host '  (بعضها قد يكون خاصية غير مخزَّنة — أضفها إلى $known في هذا الملف)' -ForegroundColor Gray
    exit 1
}
