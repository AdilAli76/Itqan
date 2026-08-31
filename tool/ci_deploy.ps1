<#
.SYNOPSIS
    ينشر حزمة إصدارٍ على بيئة التجربة أو الإنتاج. يستدعيه سير GitHub.

.DESCRIPTION
    المنطق هنا لا في ملف السير — وليس تنظيماً بل ضرورة:

    GitHub يكتب كل خطوة run: في ملف .ps1 مؤقّت **بلا BOM**، وPowerShell 5.1
    يقرأ ما لا BOM له بترميز النظام. فتتحوّل كل حرفٍ عربي إلى رموز، وتنكسر
    علامات الاقتباس، ويسقط السير بـ«النصّ بلا منهٍ» — وهو ما وقع فعلاً.

    وهذا الملف يُحفَظ بـBOM كبقية ملفات tool/، فيُقرأ صحيحاً. ويُفحَص
    بالمُحلّل محلياً قبل الدفع — وذاك ما يستحيل على خطوةٍ داخل YAML.

.PARAMETER Tag
    وسم الإصدار الذي تُؤخذ منه الحزمة. مثال: v1.0.0

.PARAMETER Target
    staging أو production.

.PARAMETER Token
    رمز الوظيفة — يُمرَّر من ${{ github.token }} ولا يُحفَظ.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Repo,
    [Parameter(Mandatory = $true)] [string]$Tag,
    [Parameter(Mandatory = $true)] [ValidateSet('staging', 'production')] [string]$Target,
    [Parameter(Mandatory = $true)] [string]$Token,
    [switch]$SkipDb
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

# ‏PowerShell 5.1 لا يتفاوض TLS 1.2 افتراضاً على ويندوز سيرفر، فيُقطع
# الاتصال بـGitHub برسالةٍ لا تذكر السبب.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }

$auth = @{ Authorization = "Bearer $Token"; 'User-Agent' = 'kinetic-deploy' }
$bin  = @{ Authorization = "Bearer $Token"; 'User-Agent' = 'kinetic-deploy'; Accept = 'application/octet-stream' }

# ── 1. تنزيل الحزمة ─────────────────────────────────────────────────────
Step 1 "تنزيل حزمة $Tag"

$rel = Invoke-RestMethod -Headers $auth -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
$asset = $rel.assets | Where-Object { $_.name -like 'kinetic_pkg_*.zip' } | Select-Object -First 1
if (-not $asset) { throw "لا حزمة مرفقة بالإصدار $Tag — راجع سير «بناء حزمة النشر»." }

$dir = Join-Path $env:RUNNER_TEMP 'kinetic-pkg'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$pkg = Join-Path $dir $asset.name
Invoke-WebRequest -Headers $bin -Uri $asset.url -OutFile $pkg -UseBasicParsing
$sha = (Get-FileHash -LiteralPath $pkg -Algorithm SHA256).Hash
Ok "$($asset.name)  ($([math]::Round((Get-Item $pkg).Length / 1MB, 1)) ميغابايت)"
Ok "البصمة: $sha"

# البصمة تُقارَن بالمرفَق الذي كُتب وقت البناء: تنزيلٌ مبتور يُنتج ملفاً
# صالح الاسم فاسد المحتوى، ويُفكّ نصفَ حزمة فوق نشرٍ يعمل.
$sig = $rel.assets | Where-Object { $_.name -like '*.sha256' } | Select-Object -First 1
if ($sig) {
    $sigFile = Join-Path $dir 'pkg.sha256'
    Invoke-WebRequest -Headers $bin -Uri $sig.url -OutFile $sigFile -UseBasicParsing
    $want = (Get-Content -LiteralPath $sigFile -Raw) -replace '[^0-9A-Fa-f]', ''
    if ($want.Length -ge 64 -and $want.Substring(0, 64) -ne $sha) {
        throw 'بصمة الحزمة المُنزَّلة لا تطابق المرفَق — التنزيل مبتور أو الحزمة استُبدلت.'
    }
    Ok 'البصمة تطابق المرفَق'
}

# ── 2. وجهة النشر ───────────────────────────────────────────────────────
if ($Target -eq 'staging') {
    $root = 'C:\kinetic-staging'; $site = 'KineticStaging'; $pool = 'KineticStagingPool'
} else {
    $root = 'C:\kinetic';         $site = 'Kinetic';        $pool = 'KineticApi'
}

# ── 3. بوّابة الإنتاج ───────────────────────────────────────────────────
#
# لا يصل الإنتاج إلا ما نُشر على التجربة بعينه. والدليل ليس ذاكرة أحد بل
# deploy.log على الخادم: هو من كتب البصمة ساعةَ النشر فعلاً.
#
# وهذا يمسك ما لا يمسكه انضباط: وسمٌ بُني وأُصلح فيه سطر بعد اختبار
# التجربة، فيُنشر على الإنتاج شيءٌ لم يعمل على أي خادم قطّ — وكله يبدو
# صحيحاً في السجلّ لأن رقم الوسم واحد.
if ($Target -eq 'production') {
    Step 2 'التحقّق أن هذه الحزمة جُرِّبت'
    $log = 'C:\kinetic-staging\deploy.log'
    if (-not (Test-Path $log)) { throw 'لا سجلّ نشر على بيئة التجربة — انشر عليها أولاً.' }
    $hit = Select-String -Path $log -SimpleMatch $sha | Select-Object -Last 1
    if (-not $hit) {
        throw "هذه الحزمة ($($sha.Substring(0,16))…) لم تُنشر على التجربة. انشرها هناك واختبرها، ثم أعد المحاولة بنفس الوسم."
    }
    Ok "مطابِقة: نُشرت على التجربة في $($hit.Line.Split('|')[0].Trim())"

    # ── نسخة قبل الترحيل ────────────────────────────────────────────────
    #
    # الترقية تُنفّذ ترحيلات على قاعدة الإنتاج، والترحيل لا يُتراجع عنه.
    # وdeploy_update يحفظ ملف الأسرار وحده — لا القاعدة.
    #
    # والنسخة الليلية لا تكفي: بين الثانية فجراً ونشرةِ الظهر يومُ عملٍ
    # كامل من فواتير عملاء. فتُؤخذ الآن، ويفشل النشر إن تعذّرت.
    if (-not $SkipDb) {
        Step 3 'نسخة احتياطية قبل الترحيل'
        $backup = Join-Path $root 'tool\backup.ps1'
        if (-not (Test-Path $backup)) {
            throw "backup.ps1 غير موجود في $root\tool — انشر حزمة حديثة يدوياً مرّة، أو خذ نسخة بنفسك قبل المتابعة."
        }
        & $backup -Database 'KineticEnterprise'
        if ($LASTEXITCODE -ne 0) { throw 'فشلت النسخة الاحتياطية — أُوقف النشر قبل أي ترحيل.' }
    }
}

# ── 4. الترقية ──────────────────────────────────────────────────────────
Step 4 "ترقية $site"

# السكربت المقيم على الخادم لا نسخة المستودع: هو الذي حُدِّث مع آخر حزمة
# نُشرت هناك، ويعرف حال تلك البيئة.
$update = Join-Path $root 'tool\deploy_update.ps1'
if (-not (Test-Path $update)) { throw "deploy_update.ps1 غير موجود في $root\tool." }

& $update -Package $pkg -Target $root -SiteName $site -PoolName $pool -SkipDb:$SkipDb

# ── 5. فحص الواجهة ──────────────────────────────────────────────────────
#
# على التجربة وحدها: يكتب بيانات باسم -TEST ولا مكان لها في دفاتر عميل.
# ولا يُفشل النشر — الترقية تمّت، وهذه قراءةٌ لحالها بعدها.
if ($Target -eq 'staging') {
    Step 5 'فحص قواعد العمل على الخادم'
    $test = Join-Path $root 'tool\api_test.ps1'
    if (Test-Path $test) {
        try { & $test -SiteName $site } catch { Warn "تعثّر الفحص: $($_.Exception.Message)" }
    } else {
        Warn 'api_test.ps1 غير موجود بعدُ على هذه البيئة.'
    }
}

# ── 6. الملخّص ──────────────────────────────────────────────────────────
if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @(
        "## $Target",
        '',
        "- **الوسم:** $Tag",
        "- **الحزمة:** $($asset.name)",
        "- **SHA256:** $sha"
    )
    # بلا BOM: الملخّص يُقرأ UTF-8، وBOM يظهر حرفاً غريباً في أوّل سطر.
    [IO.File]::AppendAllLines($env:GITHUB_STEP_SUMMARY, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
}

Write-Host ""
Write-Host "  تمّ النشر على $Target — البصمة $sha" -ForegroundColor Green
