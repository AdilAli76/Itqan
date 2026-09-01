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
    [switch]$SkipDb,
    # يجعل شريط التحديث في التطبيق إلزامياً — للحالة التي يتغيّر فيها عقد
    # الـAPI فتصير النسخة القديمة عاطلة لا متأخّرة.
    [switch]$MandatoryUpdate
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
$packages = @($rel.assets | Where-Object { $_.name -like 'kinetic_pkg_*.zip' })
if ($packages.Count -eq 0) { throw "لا حزمة مرفقة بالإصدار $Tag — راجع سير «بناء حزمة النشر»." }

# حزمتان على إصدارٍ واحد = خطأ يُوقف، لا اختيارٌ عشوائي.
#
# يقع فعلاً: خطوة الإرفاق تفشل بعطبٍ عابر في واجهة GitHub بعد نجاح البناء
# (HttpError: other side closed)، فيُعاد تشغيل الوظيفة — والاسم مؤرَّخ
# بالدقيقة فتُرفَق حزمةٌ ثانية بجوار الأولى.
#
# وأخذُ الأولى صامتاً كان ينشر **بناءً غير الذي جُرِّب**، ولا شيء في
# السجلّ يدلّ عليه: رقم الوسم واحد، والبصمة تُطبع ولا يقارنها أحد بذاكرته.
# وهو نفس ما تمنعه بوّابة الإنتاج أدناه — فيُمنع هنا أيضاً لا يُترك لها.
if ($packages.Count -gt 1) {
    $names = ($packages | ForEach-Object { $_.name }) -join '، '
    throw "الإصدار $Tag يحمل $($packages.Count) حزمة: $names. احذف القديمة من صفحة الإصدار وأبقِ واحدة."
}
$asset = $packages[0]

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
        # ── مجلد المرفقات يُمرَّر صراحةً ────────────────────────────────
        #
        # نسخة القاعدة وحدها **لا تكفي**: صفوف attachments تشير إلى ملفات
        # على القرص، فاسترجاعها بلا الملفات يُنتج نظاماً يعرض مرفقاتٍ لا
        # تُفتح — وهو أسوأ من فقدانها لأن المستخدم يظنّها موجودة.
        #
        # وكان لا يُمرَّر، فيسقط backup.ps1 على استكشافٍ ذاتي يبحث في
        # مسارين ثابتين ويستسلم إن لم يجد Storage.Path — وهو ما وقع فعلاً:
        # «لم يُحدَّد مجلد المرفقات — نسخة القاعدة وحدها». تحذيرٌ يمرّ في
        # سطرٍ وسط سجلّ ناجح فلا يقرؤه أحد حتى يوم الاسترجاع.
        #
        # وهذا ليس تخميناً للبيئة (راجع HANDOVER §٣ «أدواتٌ تخمّن بيئتها»):
        # $root معلومٌ صراحةً من الوجهة المُمرَّرة، والقيمة تُقرأ من ملف
        # إعدادات تلك البيئة بعينها.
        $uploads = $null
        $appsettings = Join-Path $root 'backend\appsettings.Production.json'
        if (Test-Path $appsettings) {
            try {
                $cfg = Get-Content -LiteralPath $appsettings -Raw | ConvertFrom-Json
                if ($cfg.Storage -and $cfg.Storage.Path) { $uploads = $cfg.Storage.Path }
            } catch {
                Warn "تعذّرت قراءة $appsettings — يُجرَّب المسار الافتراضي."
            }
        }
        if (-not $uploads) {
            # نفس ما يفعله الخادم حين تغيب Storage:Path — مجلد uploads
            # داخل جذر المحتوى. ومحاكاتُه هنا لا الاستسلام: المجلد موجودٌ
            # فعلاً وفيه مرفقات العملاء، وغيابُ الإعداد لا يعني غياب الملفات.
            $uploads = Join-Path $root 'backend\uploads'
            Warn "لا Storage:Path في الإعدادات — يُنسخ المسار الافتراضي: $uploads"
            Warn 'وهو داخل مجلد النشر: انقله إلى C:\kinetic-data\uploads واضبط Storage:Path.'
        }

        # ⚠ $LASTEXITCODE يُصفَّر **قبل** النداء لا يُقرأ بعده وحسب.
        #
        # العطب الذي يصلحه — أوقف نشرةَ إنتاجٍ ناجحة تماماً: PowerShell لا
        # يضبط $LASTEXITCODE إلا لأمرٍ **أصليّ** (exe) أو لسكربتٍ استدعى
        # `exit` صراحةً. وbackup.ps1 يخرج بـ1 عند الفشل ولا يخرج بشيء عند
        # النجاح — فيبقى $LASTEXITCODE على قيمته من قبل، أياً كان مصدرها.
        #
        # فالنسخة تُؤخذ وتُتحقَّق ويُطبع «اكتمل»، ثم يُقرأ رقمٌ لا علاقة له
        # بها فيُقال «فشلت النسخة الاحتياطية».
        #
        # وهو عين ما يحذّر منه HANDOVER §٣ «حالةٌ تصف حدوثاً لا نتيجة»:
        # قيمةٌ تصف شيئاً آخر تُقرأ كأنها النتيجة. ونظيرتُها المعروفة هنا
        # `[double]$null` التي تساوي صفراً فينجح كل اختبارٍ يقارن بصفر.
        #
        # والتصفير قبل النداء يجعل غياب `exit` يعني نجاحاً — وهو المعنى
        # الصحيح — ويُبقي `exit 1` مقروءاً كما هو.
        $global:LASTEXITCODE = 0
        & $backup -Database 'KineticEnterprise' -UploadsPath $uploads
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

# ── لا فحص واجهةٍ هنا، عمداً ──────────────────────────────────────────
#
# ‏api_test يطلب البريد وكلمة المرور تفاعلياً، والعدّاء بلا طرفية — فيتجمّد
# ثلاثين دقيقة ثم ينقطع بالمهلة. وتشغيلُه آلياً يحتاج حساباً حقيقياً في
# متغيّر بيئة، وهو ما يحذّر منه السكربت نفسه.
#
# فيبقى بيد صاحبه على بيئة التجربة حين يشاء:
#
#     .	oolpi_test.ps1 -SiteName KineticStaging
#
# ولا سرّ يُخزَّن على الخادم ولا في GitHub مقابل فحصٍ يُشغَّل بأمر واحد.

# ── 5. نسخة الأندرويد ونقطة التحديث ─────────────────────────────────────
#
# الحلقة كانت مقطوعة في وصلة واحدة: يُبنى APK آلياً، ويُرفَق آلياً، ثم
# ينتظر أن يُكتب رقمُه ورابطه بيدٍ في appsettings — فيبقى موظّفوك على نسخة
# قديمة لا لأن التحديث غير موجود، بل لأن أحداً لم يُخبرهم.
#
# والملف يُخدَم من نطاقك لا من GitHub: المستودع خاصّ، فزرّ «تنزيل» في
# التطبيق كان سيقود الموظّف إلى صفحة تطلب حساباً لا يملكه.
#
# ويأتي **بعد** الترقية: deploy_update ينسخ backend فوق القديم، وما يُوضع
# قبله في wwwroot قد يُدهَس.
Step 5 'نسخة الأندرويد ونقطة التحديث'

$apk = $rel.assets | Where-Object { $_.name -like 'itqan-*.apk' } | Select-Object -First 1
if (-not $apk) {
    Warn 'لا حزمة أندرويد في هذا الإصدار — تُخطّى نقطة التحديث.'
}
else {
    $version = $Tag -replace '^v', ''

    # الاسم يُشتقّ من ارتباط الموقع لا يُفترَض: التجربة تُعطي رابط التجربة
    # والإنتاج رابط الإنتاج، بلا أن يُكتب أيّهما هنا.
    $hostName = $null
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $hostName = (Get-WebBinding -Name $site -Protocol https -ErrorAction SilentlyContinue |
                     ForEach-Object { ($_.bindingInformation -split ':')[2] } |
                     Where-Object { $_ } | Select-Object -First 1)
        if (-not $hostName) {
            $hostName = (Get-WebBinding -Name $site -ErrorAction SilentlyContinue |
                         ForEach-Object { ($_.bindingInformation -split ':')[2] } |
                         Where-Object { $_ } | Select-Object -First 1)
        }
    } catch { }

    if (-not $hostName) {
        Warn 'تعذّر اشتقاق نطاق الموقع — تُخطّى نقطة التحديث.'
    }
    else {
        $appDir = Join-Path $root 'backend\wwwroot\app'
        New-Item -ItemType Directory -Force -Path $appDir | Out-Null
        $apkPath = Join-Path $appDir $apk.name

        Invoke-WebRequest -Headers $bin -Uri $apk.url -OutFile $apkPath -UseBasicParsing
        Ok "$($apk.name)  ($([math]::Round((Get-Item $apkPath).Length / 1MB, 1)) ميغابايت)"

        # آخر ثلاث نسخ تبقى — كما تفعل publish.ps1 بالحزم. ولا تُحذف كلها:
        # جهازٌ فتح رابط النسخة السابقة ولم يُكمل التنزيل يجدها.
        Get-ChildItem -Path $appDir -Filter 'itqan-*.apk' |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 |
            ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

        $downloadUrl = "https://$hostName/app/$($apk.name)"

        # ملف الأسرار يُنسخ قبل التعديل: خطأٌ في كتابته يُسقط الموقع كلّه —
        # سلسلة الاتصال ومفتاح JWT فيه.
        $settingsPath = Join-Path $root 'backend\appsettings.Production.json'
        $settingsBackup = "$settingsPath.before-appversion"
        Copy-Item $settingsPath $settingsBackup -Force

        try {
            $cfg = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if (-not $cfg.AppVersion) {
                $cfg | Add-Member -NotePropertyName AppVersion -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.AppVersion | Add-Member -NotePropertyName Latest -NotePropertyValue $version -Force
            $cfg.AppVersion | Add-Member -NotePropertyName AndroidDownloadUrl -NotePropertyValue $downloadUrl -Force
            $cfg.AppVersion | Add-Member -NotePropertyName Mandatory -NotePropertyValue ([bool]$MandatoryUpdate) -Force

            $cfg | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8

            # يُقرأ بعد الكتابة: ConvertTo-Json قد يُفسد بنيةً عميقة، وملفٌ
            # تالف لا يظهر خطؤه إلا حين يفشل الموقع في الإقلاع.
            $check = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($check.Jwt.Key) -or
                [string]::IsNullOrWhiteSpace($check.ConnectionStrings.Default)) {
                throw 'الملف المكتوب ناقص مفتاح JWT أو سلسلة الاتصال.'
            }
            Ok "نقطة التحديث: $version — $downloadUrl"
            if ($MandatoryUpdate) { Warn 'التحديث معلَّم إلزامياً.' }
        }
        catch {
            Copy-Item $settingsBackup $settingsPath -Force
            throw "تعذّر تحديث AppVersion، وأُعيد ملف الأسرار كما كان: $($_.Exception.Message)"
        }

        # المجمّع يُعاد تشغيله: الإعدادات تُقرأ عند الإقلاع، فبلا هذا يبقى
        # الخادم يُعلن النسخة السابقة حتى إعادة تشغيلٍ عارضة.
        try {
            Restart-WebAppPool -Name $pool -ErrorAction Stop
            Ok "أُعيد تشغيل $pool"
        } catch {
            Warn "تعذّرت إعادة تشغيل $pool — أعِدها يدوياً لتُقرأ نقطة التحديث."
        }
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
