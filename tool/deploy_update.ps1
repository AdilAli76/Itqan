#  =============================================================================
#   ترقية نسخة قائمة على الخادم — يُنفَّذ على الخادم كمسؤول.
#
#   يفعل بأمر واحد ما كان يُفعَل يدوياً في خمس خطوات تُنسى إحداها كل مرّة:
#   إيقاف الموقع، حفظ ملف الأسرار، فكّ الحزمة فوق النشر، إعادة الأسرار،
#   تشغيل الموقع، ثم تنفيذ الترحيلات.
#
#   ولماذا لا يُنسَخ من المستكشف: النسخ اليدوي يفشل صامتاً بثلاث طرق —
#   ملفات .dll مقفولة والموقع يعمل فتُنسَخ نصف الملفات، ونافذة UAC تُلغى
#   في منتصف النسخ، ومجلد backend يُسقَط داخل backend فيبقى القديم يعمل.
#   وكلها تُنتج نظاماً «يعمل» بملفات مختلطة من نسختين.
#
#   التشغيل:
#       .\deploy_update.ps1 -Package C:\publish.zip
#       .\deploy_update.ps1 -Package C:\publish.zip -SkipDb
#  =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Package,
    [string]$Target = 'C:\kinetic',
    [string]$SiteName = 'Kinetic',
    [string]$PoolName = 'KineticApi',
    # الترحيلات آمنة للإعادة، وتخطّيها يُترك للحالات التي نُفِّذت فيها للتوّ.
    [switch]$SkipDb
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step($n, $t) { Write-Host "`n[$n] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) { throw 'شغّل PowerShell كمسؤول — الكتابة في مجلد النشر تحتاج ذلك (وهي رسالة «تحتاج إذناً» في المستكشف).' }
if (-not (Test-Path $Package)) { throw "الحزمة غير موجودة: $Package" }
if (-not (Test-Path $Target))  { throw "مجلد النشر غير موجود: $Target — هذه ترقية لا تثبيت أول." }

Import-Module WebAdministration

$secrets = Join-Path $Target 'backend\appsettings.Production.json'
$backup  = Join-Path $env:TEMP ("kinetic-secrets-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$staging = Join-Path $env:TEMP ("kinetic-pkg-{0}"          -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

# بصمة الحزمة — الدليل على أن ما يُنشر على العملاء هو عين ما جُرِّب.
#
# الدورة الصحيحة: تُبنى الحزمة مرّة، تُنشر على التجربة، فإن نجحت تُنشر
# **نفس الحزمة** على الإنتاج. وإعادة البناء بينهما تُبطل الاختبار كله —
# فما اختُبر لم يعد هو ما سُلِّم. والبصمة تكشف ذلك بلا اعتماد على الذاكرة.
$hash = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash

Write-Host ""
Write-Host "  ترقية Kinetic Enterprise" -ForegroundColor White
Write-Host "    الحزمة : $Package"
Write-Host "    البصمة : $($hash.Substring(0,16))…" -ForegroundColor Gray
Write-Host "    الوجهة : $Target"

# ── 1. ملف الأسرار ──────────────────────────────────────────────────────
Step 1 'حفظ ملف الأسرار'
if (Test-Path $secrets) {
    Copy-Item $secrets $backup -Force
    Ok "نسخة احتياطية: $backup"
} else {
    Warn 'لا ملف أسرار في النشر الحالي — سيلزم إنشاؤه بعد الترقية.'
}

# ── 2. فكّ الحزمة قبل الإيقاف ───────────────────────────────────────────
# الفكّ أولاً والموقع يعمل: حزمة تالفة تُكتشف قبل أن يتوقّف النظام، لا بعد.
Step 2 'فكّ الحزمة في مجلد مؤقّت'
New-Item -ItemType Directory -Force -Path $staging | Out-Null
Expand-Archive -LiteralPath $Package -DestinationPath $staging -Force
$srcBackend = Join-Path $staging 'backend'
if (-not (Test-Path $srcBackend)) { throw "الحزمة لا تحوي مجلد backend — تأكّد أنها publish.zip الصحيحة." }
Ok "فُكّت في $staging"

# ── 3. إيقاف الموقع ─────────────────────────────────────────────────────
# التوقّف شرط لا احتياط: ملفات .dll مقفولة ما دام التطبيق يعمل، والنسخ
# فوقها يفشل ملفاً ملفاً — فتبقى نسخة مختلطة تعمل وتُخطئ بلا رسالة.
Step 3 'إيقاف الموقع'
Stop-Website -Name $SiteName -ErrorAction SilentlyContinue
Stop-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue
# تحرير المقابض يستغرق لحظة بعد إيقاف المجمّع.
Start-Sleep -Seconds 3
Ok 'الموقع ومجمّع التطبيقات متوقّفان'

try {
    # ── 4. الاستبدال ────────────────────────────────────────────────────
    Step 4 'استبدال ملفات النشر'
    Copy-Item -Path (Join-Path $srcBackend '*') -Destination (Join-Path $Target 'backend') -Recurse -Force
    Ok 'الخادم وتطبيق الويب مُحدَّثان'

    $srcSql = Join-Path $staging 'sql'
    if (Test-Path $srcSql) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Target 'sql') | Out-Null
        Copy-Item -Path (Join-Path $srcSql '*') -Destination (Join-Path $Target 'sql') -Recurse -Force
        Ok 'ملفات SQL مُحدَّثة'
    }

    # ── 5. إعادة الأسرار ────────────────────────────────────────────────
    Step 5 'إعادة ملف الأسرار'
    if (Test-Path $backup) {
        Copy-Item $backup $secrets -Force
        $cfg = Get-Content $secrets -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($cfg.Jwt.Key)) { throw 'ملف الأسرار المُعاد بلا مفتاح JWT — أوقفت الترقية.' }
        Ok 'ملف الأسرار في مكانه وسليم'
    } else {
        Warn 'لا نسخة أسرار — أنشئ appsettings.Production.json قبل التشغيل.'
    }
} finally {
    # ── 6. التشغيل ──────────────────────────────────────────────────────
    # في finally: فشل النسخ في المنتصف يجب ألّا يترك النظام متوقّفاً بلا
    # أن ينتبه أحد — يعود للعمل ثم يُقرأ الخطأ.
    Step 6 'تشغيل الموقع'
    Start-WebAppPool -Name $PoolName -ErrorAction SilentlyContinue
    Start-Website -Name $SiteName -ErrorAction SilentlyContinue
    Ok 'الموقع يعمل'
}

# ── 7. الترحيلات ────────────────────────────────────────────────────────
if (-not $SkipDb) {
    Step 7 'تنفيذ ترحيلات قاعدة البيانات'
    $setup = Join-Path $Target 'server_setup.ps1'
    if (Test-Path $setup) {
        & $setup -Stage db -PackagePath $Target
    } else {
        Warn "server_setup.ps1 غير موجود في $Target — نفّذ الترحيلات يدوياً."
    }
}

# ── 8. فحص سريع ─────────────────────────────────────────────────────────
Step 8 'فحص الاستجابة'
try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1/' -Headers @{ Host = 'localhost' } `
        -UseBasicParsing -TimeoutSec 20
    Ok "الموقع يردّ ($($r.StatusCode))"
} catch {
    Warn "لم يردّ محلياً: $($_.Exception.Message.Split([char]10)[0])"
    Warn 'قد يكون الموقع مربوطاً بترويسة مضيف — جرّب بالنطاق الحقيقي.'
}

Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
# سجلّ النشر: أي بصمة نُشرت أين ومتى. سؤال «هل الإنتاج على نفس نسخة
# التجربة؟» يُجاب من ملف لا من الذاكرة.
$logLine = '{0} | {1} | {2} | {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $SiteName, $hash, (Split-Path $Package -Leaf)
Add-Content -LiteralPath (Join-Path $Target 'deploy.log') -Value $logLine -Encoding UTF8

Write-Host ""
Write-Host "  البصمة المنشورة: $hash" -ForegroundColor Gray
Write-Host "  سُجّلت في $(Join-Path $Target 'deploy.log')" -ForegroundColor Gray
Write-Host ""
Write-Host "  تمّت الترقية. نسخة الأسرار الاحتياطية باقية في:" -ForegroundColor Green
Write-Host "    $backup" -ForegroundColor Gray
Write-Host "  ونفق cloudflared لا يتأثّر بهذه العملية — الرابط كما هو." -ForegroundColor Gray
