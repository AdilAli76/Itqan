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

.PARAMETER RunId
    بديلٌ عن الوسم: رقم سير «بناء حزمة النشر» تُؤخذ حزمته من أثره
    مباشرةً. للتجربة وحدها — راجع الشرح عند الحصول على الحزمة أدناه.

.PARAMETER Version
    رقم النسخة المُعلَن لنقطة التحديث في وضع RunId. بلاه تُنشَر الحزمة
    ولا يُخبَر جهازٌ بتحديث — وهو الافتراض المقصود.

.PARAMETER Target
    staging أو production.

.PARAMETER Token
    رمز الوظيفة — يُمرَّر من ${{ github.token }} ولا يُحفَظ.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$Repo,

    # ‏الوسم ورقم السير كلاهما نصّ وكلاهما اختياري في التوقيع، والتحقّق
    # أدناه لا في السمات: سير النشر يمرّر الوسيطين دائماً، وأحدهما فارغ.
    # ومجموعات الوسائط ترى النصّ الفارغ **قيمةً مُمرَّرة** فتلتبس عليها
    # المجموعة، فتسقط برسالةٍ عن «مجموعة غير محدَّدة» لا يفهمها أحد.
    [string]$Tag,
    [string]$RunId,
    [string]$Version,
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

# ── 0. مصدر الحزمة ──────────────────────────────────────────────────────
#
# ‏مصدران لا ثالث: **إصدارٌ موسوم** وهو الأصل، أو **أثر سير بناء** وهو
# طريقٌ للتجربة وحدها.
#
# ‏والثاني أُضيف لأن الأوّل يحتاج وسماً، والوسم قرارٌ لا يُتخذ لتجربة شاشةٍ
# على خادم التجربة: يبقى في تاريخ المستودع، ويُعلن نسخةً للناس. فكان من
# يريد التجربة إمّا أن يوسم إصداراً لا ينوي إصداره، أو يرفع الحزمة بيده
# ويفقد كل ما يحرسه هذا السكربت.
#
# ‏ولا يبلغ الإنتاجَ أثرٌ أبداً: الأثر يُمحى بعد ثلاثين يوماً، ورقم السير
# لا يقول ما فيه — فلا يبقى بعد شهرين ما يُراجَع به ما يعمل على الخادم.
# والإنتاج يبقى على عقده: إصدارٌ موسوم، جُرِّب بعينه، محفوظٌ إلى الأبد.
if ($Tag -and $RunId) {
    throw 'مُرِّر الوسم أو رقم السير — لا كليهما. الوسم للإصدار، ورقم السير لتجربة بناءٍ لم يُوسم.'
}
if (-not $Tag -and -not $RunId) {
    throw 'لا وسم ولا رقم سير. مرّر -Tag v1.2.3 لنشر إصدار، أو -RunId 12345 لنشر أثر سير بناء على التجربة.'
}
if ($RunId -and $RunId -notmatch '^[0-9]+$') {
    throw "رقم السير غير رقمي: $RunId. هو الرقم في آخر رابط صفحة السير (…/actions/runs/<الرقم>)."
}
if ($RunId -and $Target -eq 'production') {
    throw 'أثر السير لا يُنشر على الإنتاج. أنشئ وسماً من نفس الشيفرة وانشر إصداره — راجع الشرح أعلاه.'
}
if ($Tag -and $Version) {
    throw 'رقم النسخة يُشتقّ من الوسم — لا يُمرَّر معه. و-Version لوضع RunId وحده.'
}

$source = if ($RunId) { "أثر السير #$RunId" } else { $Tag }

$dir = Join-Path $env:RUNNER_TEMP 'kinetic-pkg'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# ‏روابط تنزيل الآثار تُحوَّل إلى مخزن كائناتٍ يوقّع الإذن في الرابط نفسه،
# ويردّ 400 على طلبٍ يحمل ترويسة Authorization فوق ذلك. فيُقرأ التحويل
# ثمّ يُنزَّل الهدف عارياً من الترويسة.
function Get-ArtifactZip($url, $outFile) {
    $location = $null
    try {
        Invoke-WebRequest -Headers $auth -Uri $url -MaximumRedirection 0 -UseBasicParsing -OutFile $outFile
    } catch {
        $resp = $_.Exception.Response
        if (-not $resp) { throw }
        $code = [int]$resp.StatusCode
        if ($code -lt 300 -or $code -ge 400) { throw }

        # ‏ترويسات الردّ صنفان بحسب مُحرّك الطلب: WebHeaderCollection في
        # ويندوز باورشيل (فهرسٌ بالاسم)، وHttpResponseHeaders في السابع
        # (خاصيّة Location). وقراءةُ أحدهما بأسلوب الآخر تُعطي $null صامتاً
        # فيُكتب ملفٌ فارغ مكان الحزمة.
        $location = $null
        if ($resp.Headers.Location) { $location = [string]$resp.Headers.Location }
        else { try { $location = @($resp.Headers['Location'])[0] } catch { } }
        if (-not $location) { throw "تحويلٌ بلا عنوان ($code) عند تنزيل الأثر." }
    }
    if ($location) {
        Invoke-WebRequest -Uri $location -OutFile $outFile -UseBasicParsing
    }
}

function Get-RunArtifact($name) {
    $list = Invoke-RestMethod -Headers $auth -Uri "https://api.github.com/repos/$Repo/actions/runs/$RunId/artifacts?per_page=100"
    $hit = $list.artifacts | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $hit) { return $null }
    if ($hit.expired) { throw "أثر «$name» في السير #$RunId انتهت مدّته (ثلاثون يوماً) — أعد البناء أو انشر إصداراً موسوماً." }

    $zip = Join-Path $dir "$name.zip"
    Get-ArtifactZip $hit.archive_download_url $zip
    $into = Join-Path $dir $name
    Expand-Archive -LiteralPath $zip -DestinationPath $into -Force
    return $into
}

# ── 1. الحصول على الحزمة ────────────────────────────────────────────────
Step 1 "تنزيل حزمة $source"

$rel = $null
$apkAsset = $null      # مرفَق الإصدار (وضع الوسم)
$apkLocal = $null      # ملفٌّ على القرص (وضع الأثر)
$wantSha = $null       # البصمة المكتوبة وقت البناء

if ($RunId) {
    $pkgDir = Get-RunArtifact 'kinetic_pkg'
    if (-not $pkgDir) { throw "لا أثر باسم kinetic_pkg في السير #$RunId — أهو سير «بناء حزمة النشر»؟" }

    # نفس قاعدة الإصدار: حزمتان = وقوف لا اختيارٌ عشوائي.
    $found = @(Get-ChildItem -Path $pkgDir -Filter 'kinetic_pkg_*.zip' -File)
    if ($found.Count -eq 0) { throw "أثر kinetic_pkg في السير #$RunId لا يحوي حزمة." }
    if ($found.Count -gt 1) {
        throw "أثر السير #$RunId يحمل $($found.Count) حزمة: $((($found | ForEach-Object { $_.Name }) -join '، '))."
    }

    $pkgName = $found[0].Name
    $pkg = $found[0].FullName
    $sigFile = Get-ChildItem -Path $pkgDir -Filter '*.sha256' -File | Select-Object -First 1
    if ($sigFile) { $wantSha = (Get-Content -LiteralPath $sigFile.FullName -Raw) -replace '[^0-9A-Fa-f]', '' }

    $apkDir = Get-RunArtifact 'itqan-apk'
    if ($apkDir) { $apkLocal = Get-ChildItem -Path $apkDir -Filter 'itqan-*.apk' -File | Select-Object -First 1 }
}
else {
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
    $pkgName = $asset.name
    $pkg = Join-Path $dir $pkgName
    Invoke-WebRequest -Headers $bin -Uri $asset.url -OutFile $pkg -UseBasicParsing

    $sig = $rel.assets | Where-Object { $_.name -like '*.sha256' } | Select-Object -First 1
    if ($sig) {
        $sigFile = Join-Path $dir 'pkg.sha256'
        Invoke-WebRequest -Headers $bin -Uri $sig.url -OutFile $sigFile -UseBasicParsing
        $wantSha = (Get-Content -LiteralPath $sigFile -Raw) -replace '[^0-9A-Fa-f]', ''
    }

    $apkAsset = $rel.assets | Where-Object { $_.name -like 'itqan-*.apk' } | Select-Object -First 1
}

$sha = (Get-FileHash -LiteralPath $pkg -Algorithm SHA256).Hash
Ok "$pkgName  ($([math]::Round((Get-Item $pkg).Length / 1MB, 1)) ميغابايت)"
Ok "البصمة: $sha"

# البصمة تُقارَن بالتي كُتبت وقت البناء: نقلٌ مبتور يُنتج ملفاً صالح الاسم
# فاسد المحتوى، ويُفكّ نصفَ حزمة فوق نشرٍ يعمل.
if ($wantSha -and $wantSha.Length -ge 64) {
    if ($wantSha.Substring(0, 64) -ne $sha) {
        throw 'بصمة الحزمة لا تطابق المكتوبة وقت البناء — النقل مبتور أو الحزمة استُبدلت.'
    }
    Ok 'البصمة تطابق المكتوبة وقت البناء'
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

# نفس حزام backup.ps1: $LASTEXITCODE يصف آخر أمرٍ أصليّ لا نتيجة هذا
# السكربت، فيُصفَّر قبل النداء ليصير غياب `exit` نجاحاً.
$global:LASTEXITCODE = 0
& $update -Package $pkg -Target $root -SiteName $site -PoolName $pool -SkipDb:$SkipDb
if ($LASTEXITCODE -ne 0) {
    throw "الترقية انتهت برمز $LASTEXITCODE — راجع السطور أعلاه. الموقع قد يكون متوقّفاً: Start-WebAppPool -Name $pool; Start-Website -Name $site"
}

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
Step 5 'نسخ الأجهزة ونقطة التحديث'

# ── تطبيق سطح المكتب ────────────────────────────────────────────────────
#
# **الحلقة التي تُغلَق هنا:** التطبيق يُبنى ويدخل الحزمة تحت desktop/، ثمّ
# لا شيء يُخرجه منها: deploy_update ينسخ backend وsql وtool فقط، والمجلد
# المؤقّت يُمحى معه. فالتطبيق يُبنى في كل نشرة ويضيع في كل نشرة.
#
# ويُفكّ **من الحزمة المتحقَّق من بصمتها** لا يُنزَّل ثانيةً: هو جزء منها،
# وتنزيله منفرداً يُدخل احتمال أن يصل الجهازَ بناءٌ غير الذي جُرِّب.
#
# ويُوضع في موضعين لغرضين مختلفين:
#   $root\desktop        — نسخةٌ على الخادم تُنسخ إلى أجهزة المحلّ بالشبكة.
#   wwwroot\app\*.zip    — رابط تنزيل من نطاقك، كما يفعل الأندرويد تماماً.
# ‏رقم النسخة من الوسم، أو من -Version في وضع الأثر. وبلا أيّهما لا
# نسخة: أثرٌ بُني على فرعٍ لا يحمل رقماً يُعلَن، واختراعُ رقمٍ له يعني
# أجهزةً تُخبَر بتحديثٍ إلى نسخةٍ لا وجود لها في أي إصدار.
$version = if ($Tag) { $Tag -replace '^v', '' } else { $Version }
$deskVersion = if ($version) { $version } else { "run$RunId" }
$deskZipName = "itqan-desktop-$deskVersion.zip"

# يُهيَّأ صراحةً: يُقرأ في كتلةٍ أخرى بعد عشرات الأسطر، ومتغيّرٌ لم يُعرَّف
# قطّ يُقرأ $null بصمت — وهو ما يجعل الفرق بين «تعذّر» و«لم يُحاوَل» غير
# مرئي في السجلّ.
$deskReady = $false

try {
    $extract = Join-Path $env:RUNNER_TEMP "kinetic-desktop-$deskVersion"
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -LiteralPath $pkg -DestinationPath $extract -Force

    $deskSrc = Join-Path $extract 'desktop'
    if (-not (Test-Path $deskSrc)) {
        Warn 'لا مجلد desktop في هذه الحزمة — حزمةٌ بُنيت قبل إضافته.'
    }
    else {
        # النسخة على الخادم: تُستبدل كاملةً لا تُدمَج. ملفٌّ من نسخةٍ سابقة
        # يبقى بجوار ملفّات الجديدة يُنتج تطبيقاً يفتح ثم يُغلق بلا رسالة.
        $deskDst = Join-Path $root 'desktop'
        if (Test-Path $deskDst) { Remove-Item $deskDst -Recurse -Force }
        Copy-Item $deskSrc $deskDst -Recurse -Force
        Ok "سطح المكتب على الخادم: $deskDst"

        # وملفُّ عنوان الخادم بجواره — فمن نسخ المجلد إلى جهازٍ في المحلّ
        # لا يُقابَل بسؤال «أدخل عنوان الخادم». راجع ApiClient.
        # (يُكتب بعد اشتقاق النطاق أدناه، فيُؤجَّل إلى هناك.)
        $deskReady = $true
    }
} catch {
    # فشل سطح المكتب لا يُسقط نشرةً نجحت: الخادم يعمل والأندرويد يُخدَم،
    # وهذا ملفٌّ يُنسخ. يُسجَّل بوضوح ويُكمَل.
    Warn "تعذّر تجهيز تطبيق سطح المكتب: $($_.Exception.Message)"
}


if (-not $version) {
    # ‏نشرُ أثرٍ بلا رقم نسخة: الخادم يُرقّى وسطح المكتب يُنسخ، ولا يُمسّ
    # AppVersion. فلا يرى أحدٌ «تحديث متاح» إلى بناءٍ للتجربة.
    Warn 'لا رقم نسخة (مرّر -Version لإعلانها) — تُخطّى نقطة التحديث.'
}
elseif (-not $apkAsset -and -not $apkLocal) {
    Warn 'لا حزمة أندرويد مع هذه الحزمة — تُخطّى نقطة التحديث.'
}
else {
    $apkName = if ($apkLocal) { $apkLocal.Name } else { $apkAsset.name }

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
        $apkPath = Join-Path $appDir $apkName

        if ($apkLocal) { Copy-Item $apkLocal.FullName $apkPath -Force }
        else { Invoke-WebRequest -Headers $bin -Uri $apkAsset.url -OutFile $apkPath -UseBasicParsing }
        Ok "$apkName  ($([math]::Round((Get-Item $apkPath).Length / 1MB, 1)) ميغابايت)"

        # آخر ثلاث نسخ تبقى — كما تفعل publish.ps1 بالحزم. ولا تُحذف كلها:
        # جهازٌ فتح رابط النسخة السابقة ولم يُكمل التنزيل يجدها.
        Get-ChildItem -Path $appDir -Filter 'itqan-*.apk' |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 |
            ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

        $downloadUrl = "https://$hostName/app/$apkName"

        # ── رابط تنزيل سطح المكتب ───────────────────────────────────────
        #
        # يُضغَط **بعد** الترقية: deploy_update ينسخ backend فوق القديم،
        # وwwwroot معه — فأي ملفٍّ يُوضع قبله يُدهَس. نفس سبب تأخير الأندرويد.
        $desktopUrl = $null
        if ($deskReady) {
            try {
                # وserver.txt يُكتب الآن لا قبل اشتقاق النطاق: عنوان الخادم
                # هو ما يجعل النسخة المنسوخة إلى جهازٍ في المحلّ تعمل بلا
                # سؤالٍ عن عنوان لا يعرفه من يفتحها.
                @(
                    '# عنوان خادم إتقان — كتبته نشرة الخادم.',
                    '# غيّره فقط إن نُقل الخادم إلى نطاق آخر.',
                    "https://$hostName/api"
                ) | Set-Content -LiteralPath (Join-Path $root 'desktop\server.txt') -Encoding utf8

                $deskZip = Join-Path $appDir $deskZipName
                if (Test-Path $deskZip) { Remove-Item $deskZip -Force }
                Compress-Archive -Path (Join-Path $root 'desktop\*') -DestinationPath $deskZip -Force

                # آخر ثلاث نسخ تبقى — كما تفعل حزم الأندرويد أعلاه.
                Get-ChildItem -Path $appDir -Filter 'itqan-desktop-*.zip' |
                    Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 |
                    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

                $desktopUrl = "https://$hostName/app/$deskZipName"
                Ok "$deskZipName  ($([math]::Round((Get-Item $deskZip).Length / 1MB, 1)) ميغابايت)"
            } catch {
                Warn "تعذّر تجهيز رابط سطح المكتب: $($_.Exception.Message)"
            }
        }

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
            # DownloadUrl لسطح المكتب: كان معرَّفاً في عقد AppVersionDto منذ
            # بنائه **ولا يكتبه أحد** — أي أن مدقّق التحديث على سطح المكتب
            # كان يجد رابطاً فارغاً أبداً، فيقول «تحديث متاح» بلا ما يُنزَّل.
            if ($desktopUrl) {
                $cfg.AppVersion | Add-Member -NotePropertyName DownloadUrl -NotePropertyValue $desktopUrl -Force
            }
            $cfg.AppVersion | Add-Member -NotePropertyName Mandatory -NotePropertyValue ([bool]$MandatoryUpdate) -Force

            $cfg | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8

            # يُقرأ بعد الكتابة: ConvertTo-Json قد يُفسد بنيةً عميقة، وملفٌ
            # تالف لا يظهر خطؤه إلا حين يفشل الموقع في الإقلاع.
            $check = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($check.Jwt.Key) -or
                [string]::IsNullOrWhiteSpace($check.ConnectionStrings.Default)) {
                throw 'الملف المكتوب ناقص مفتاح JWT أو سلسلة الاتصال.'
            }
            Ok "نقطة التحديث: $version"
            Ok "  أندرويد   : $downloadUrl"
            if ($desktopUrl) { Ok "  سطح المكتب: $desktopUrl" }
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
        "- **المصدر:** $source",
        "- **الحزمة:** $pkgName",
        "- **SHA256:** $sha"
    )
    # بلا BOM: الملخّص يُقرأ UTF-8، وBOM يظهر حرفاً غريباً في أوّل سطر.
    [IO.File]::AppendAllLines($env:GITHUB_STEP_SUMMARY, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
}

Write-Host ""
Write-Host "  تمّ النشر على $Target من $source — البصمة $sha" -ForegroundColor Green
