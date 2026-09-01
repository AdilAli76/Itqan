#  =============================================================================
#   مولّد أيقونات إتقان ERP — يشتقّ كل المقاسات من شعار المنتج الواحد.
#
#   كان يرسم أيقونةً تركيبية بالكود (عقدة مركزية وأربع فروع) قبل أن يوجد
#   شعار. فلمّا صار للمنتج شعار حقيقي بقيت الأيقونات القديمة في مكانها،
#   وظهر شعار فلاتر الافتراضي في تبويب المتصفّح — لأن web/ لم يكن في نطاق
#   المولّد أصلاً.
#
#   والمصدر الآن ملفٌّ واحد: assets/branding/itqan_logo.png. تغييرُه وإعادة
#   تشغيل هذا السكربت يُحدّث الهوية في كل مكان دفعةً واحدة — بدل تحديث
#   أحدها ونسيان البقية، وهو ما وقع فعلاً.
#
#   التشغيل:
#       powershell -ExecutionPolicy Bypass -File tool\generate_app_icons.ps1
#  =============================================================================

[CmdletBinding()]
param(
    [string]$Source,
    <#
      منطقة الشعار داخل الصورة المصدر: "س،ص،الضلع".

      ولماذا قصٌّ لا استعمالُ الصورة كما هي: ملف الهوية بطاقةُ عرضٍ تحوي
      الدرعَ واسمَ المنتج ومحاكاةَ أيقونة. واستعمالها كاملةً في أيقونة
      32 بكسل يُنتج لطخةً لا يُقرأ منها شيء — وهو ما ظهر أوّل مرّة.
      الأيقونة هي **الدرع وحده**.
    #>
    [string]$LogoCrop = '295,212,440'
)

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
if (-not $Source) { $Source = Join-Path $root 'assets\branding\itqan_logo.png' }

if (-not (Test-Path $Source)) {
    throw "لا شعار في $Source — ضع الشعار هناك أو مرّر -Source."
}

function Step($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }

# لون الخلفية للأيقونات المعتِمة (maskable وأندرويد): يُقرأ من بكسل الزاوية
# في الشعار نفسه لا يُكتب ثابتاً — شعارٌ يُستبدل بخلفية أخرى يُنتج حينها
# إطاراً بلون غريب حوله.
$original = [System.Drawing.Image]::FromFile($Source)
$probe = New-Object System.Drawing.Bitmap($original)
$background = $probe.GetPixel(0, 0)
$probe.Dispose()
Ok "المصدر: $Source ($($original.Width)×$($original.Height))"

# اقتصاص الدرع مرّةً واحدة — كل المقاسات تُشتقّ منه.
$parts = $LogoCrop -split ','
if ($parts.Count -ne 3) { throw "صيغة LogoCrop يجب أن تكون 'س،ص،الضلع'" }
$cropX = [int]$parts[0]; $cropY = [int]$parts[1]; $cropSide = [int]$parts[2]

$sourceImage = New-Object System.Drawing.Bitmap($cropSide, $cropSide)
$cg = [System.Drawing.Graphics]::FromImage($sourceImage)
$cg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$cg.DrawImage($original,
    (New-Object System.Drawing.Rectangle(0, 0, $cropSide, $cropSide)),
    (New-Object System.Drawing.Rectangle($cropX, $cropY, $cropSide, $cropSide)),
    [System.Drawing.GraphicsUnit]::Pixel)
$cg.Dispose()
$original.Dispose()
Ok "اقتُصّ الشعار: ($cropX، $cropY) بضلع $cropSide"
Ok ("لون الخلفية المستنتَج: #{0:X2}{1:X2}{2:X2}" -f $background.R, $background.G, $background.B)

<#
.SYNOPSIS
    يرسم الشعار في مربّع بالمقاس المطلوب.

.PARAMETER Inset
    نسبة الهامش حول الشعار (0 = يملأ المربّع).
    أيقونات maskable في أندرويد تُقصّ دائرياً، فشعارٌ يملأ المربّع تُقصّ
    أطرافه. و20٪ هامش هو ما توصي به مواصفة المنطقة الآمنة.

.PARAMETER Transparent
    خلفية شفّافة بدل لون الشعار — للأيقونات التي يضع النظام خلفيتها.
#>
function Save-Icon([string]$Path, [int]$Size, [double]$Inset = 0, [switch]$Transparent) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        # HighQualityBicubic لا Default: تصغير 1024 إلى 32 بالافتراضي يُنتج
        # حوافّ مسنّنة تظهر بوضوح في تبويب المتصفّح.
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        if (-not $Transparent) {
            $brush = New-Object System.Drawing.SolidBrush($background)
            $g.FillRectangle($brush, 0, 0, $Size, $Size)
            $brush.Dispose()
        }

        $margin = [int]([Math]::Round($Size * $Inset / 2))
        $inner = $Size - ($margin * 2)
        $g.DrawImage($sourceImage, $margin, $margin, $inner, $inner)

        $dir = Split-Path -Parent $Path
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $g.Dispose()
        $bmp.Dispose()
    }
}

# ── الويب ────────────────────────────────────────────────────────────────
Step '[1] أيقونات الويب'

$web = Join-Path $root 'web'
Save-Icon (Join-Path $web 'favicon.png') 32
Ok 'favicon.png (32)'

Save-Icon (Join-Path $web 'icons\Icon-192.png') 192
Save-Icon (Join-Path $web 'icons\Icon-512.png') 512
Ok 'Icon-192.png · Icon-512.png'

# maskable بهامش: نظام التشغيل يقصّها دائرياً عند التثبيت على الشاشة.
Save-Icon (Join-Path $web 'icons\Icon-maskable-192.png') 192 -Inset 0.20
Save-Icon (Join-Path $web 'icons\Icon-maskable-512.png') 512 -Inset 0.20
Ok 'Icon-maskable-192.png · Icon-maskable-512.png (بهامش 20٪)'

# ── أندرويد ──────────────────────────────────────────────────────────────
Step '[2] أيقونات أندرويد'

$res = Join-Path $root 'android\app\src\main\res'
$launcherSizes = @{
    'mipmap-mdpi'    = 48
    'mipmap-hdpi'    = 72
    'mipmap-xhdpi'   = 96
    'mipmap-xxhdpi'  = 144
    'mipmap-xxxhdpi' = 192
}
foreach ($entry in $launcherSizes.GetEnumerator() | Sort-Object Value) {
    Save-Icon (Join-Path $res "$($entry.Key)\ic_launcher.png") $entry.Value
}
Ok "ic_launcher — $($launcherSizes.Count) كثافات"

# ── طبقات الأيقونة التكيّفية ──────────────────────────────────────────────
#
#   ⚠ **هذه هي الأيقونة التي يراها كل هاتف حديث، لا ic_launcher.png.**
#
#   mipmap-anydpi-v26/ic_launcher.xml يعلن adaptive-icon، وأندرويد ٨ فما
#   فوق يفضّله على الصورة الجاهزة دائماً. وكان هذا المولّد يكتب
#   ic_launcher.png وحدها ويترك ic_launcher_foreground.png كما وُلدت أوّل
#   مرّة — أيقونةً تركيبية رُسمت بالكود قبل أن يوجد شعار.
#
#   فكانت النتيجة: شعار إتقان في المستودع، وعقدةٌ ذهبية عامّة على شاشة كل
#   جهاز. والملف الصحيح موجودٌ بجواره ولا أحد يقرؤه — وهو أسوأ من غيابه،
#   لأن فحصه بالعين يقول إن الأيقونة سليمة.
#
#   والهامش ٢٥٪ ليس تجميلاً: النظام يقصّ الطبقة الأمامية بقناعه الخاص
#   (دائرة، حصاة، مربّع دائري) ويحتفظ بالثلثين الأوسطين فقط. شعارٌ يملأ
#   المربّع كاملاً يُقصّ طرفاه على أجهزة سامسونج وحدها — عطبٌ لا يظهر على
#   جهاز المطوّر.
#
#   والطبقة شفّافة: الخلفية يحدّدها ic_launcher_background.xml، ورسمُها
#   هنا يُنتج مربّعاً ظاهراً داخل القناع.
foreach ($entry in $launcherSizes.GetEnumerator() | Sort-Object Value) {
    Save-Icon (Join-Path $res "$($entry.Key)\ic_launcher_foreground.png") $entry.Value -Inset 0.25 -Transparent
    # الطبقة الأحادية (أيقونات أندرويد ١٣ المموّهة): النظام يقرأ شكلها
    # ويلوّنها بلون النظام، فتُشتقّ من نفس الشعار بنفس الهامش لا تُترك
    # متخلّفة عنه.
    Save-Icon (Join-Path $res "$($entry.Key)\ic_launcher_monochrome.png") $entry.Value -Inset 0.25 -Transparent
}
Ok "ic_launcher_foreground · ic_launcher_monochrome — بهامش ٢٥٪ للقناع"

# والأيقونة المستديرة: أجهزة تطلبها صراحةً عبر android:roundIcon.
foreach ($entry in $launcherSizes.GetEnumerator() | Sort-Object Value) {
    Save-Icon (Join-Path $res "$($entry.Key)\ic_launcher_round.png") $entry.Value
}
Ok "ic_launcher_round — $($launcherSizes.Count) كثافات"

# شعار شاشة البدء بخلفية شفّافة: الخلفية يحدّدها launch_background.xml،
# ورسمُها هنا يُنتج مربّعاً ظاهراً فوقها.
$splashSizes = @{
    'drawable-mdpi'    = 120
    'drawable-hdpi'    = 180
    'drawable-xhdpi'   = 240
    'drawable-xxhdpi'  = 360
    'drawable-xxxhdpi' = 480
}
foreach ($entry in $splashSizes.GetEnumerator() | Sort-Object Value) {
    Save-Icon (Join-Path $res "$($entry.Key)\splash_logo.png") $entry.Value -Transparent
}
Ok "splash_logo — $($splashSizes.Count) كثافات (خلفية شفّافة)"

# ── ويندوز ───────────────────────────────────────────────────────────────
Step '[3] أيقونة ويندوز'

$icoPath = Join-Path $root 'windows\runner\resources\app_icon.ico'
if (Test-Path (Split-Path -Parent $icoPath)) {
    # ICO متعدّد المقاسات يحتاج مكتبة خارجية؛ و256 وحده يكفي ويندوز 10/11
    # فهو يُصغّره عند الحاجة.
    $tmp = Join-Path $env:TEMP 'itqan_icon_256.png'
    Save-Icon $tmp 256

    $bmp = [System.Drawing.Bitmap]::FromFile($tmp)
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $fs = [System.IO.File]::Create($icoPath)
    try { $icon.Save($fs) } finally { $fs.Dispose(); $icon.Dispose(); $bmp.Dispose() }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Ok 'app_icon.ico (256)'
} else {
    Write-Host '    لا مجلد windows\runner\resources — تُخطّى' -ForegroundColor DarkGray
}

$sourceImage.Dispose()

Write-Host "`nتمّت الأيقونات. أعِد بناء الويب والأندرويد لتظهر." -ForegroundColor Green
Write-Host ""
