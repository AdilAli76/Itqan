# =============================================================================
#  مولّد أيقونات Kinetic ERP — يُنتج كل مقاسات أندرويد المطلوبة كصور PNG حقيقية.
#
#  الهوية: "Kinetic Ink & Amber" — نفس لوحة lib/core/theme/app_colors.dart
#  الشكل:  عقدة مركزية + أربع عقد فرعية موصولة بها = "إدارة موحّدة لكل فروعك
#          من لوحة تحكم واحدة" (نفس رسالة شاشة الدخول ونفس Icons.hub_outlined).
#
#  التشغيل:  powershell -ExecutionPolicy Bypass -File tool\generate_app_icons.ps1
#  الأيقونات مولَّدة ومرفوعة في المستودع؛ أعِد تشغيل هذا الملف فقط عند تغيير
#  الهوية البصرية.
# =============================================================================

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$res  = Join-Path $root 'android\app\src\main\res'

# ---- لوحة الألوان (مطابقة لـ AppColors) ----
$inkDark   = [System.Drawing.Color]::FromArgb(255, 0x0B, 0x25, 0x40)  # primary
$inkLight  = [System.Drawing.Color]::FromArgb(255, 0x12, 0x35, 0x54)  # primaryDark
$amber     = [System.Drawing.Color]::FromArgb(255, 0xC8, 0x95, 0x2B)  # secondary
$amberSoft = [System.Drawing.Color]::FromArgb(255, 0xF3, 0xE3, 0xC2)  # secondaryLight
$white     = [System.Drawing.Color]::White

# مسار مستطيل بزوايا دائرية
function Get-RoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# رسم الشعار: box = طول ضلع المربع المخصّص للشعار، (cx,cy) مركزه.
# كل الأبعاد نسبية إلى box حتى يبقى الشعار متطابقاً في كل المقاسات.
function Draw-Glyph($g, [single]$cx, [single]$cy, [single]$box, $nodeColor, $linkColor) {
    # المسافة أكبر من مجموع نصفي القطرين بفارق واضح، وإلا اختفت خطوط الوصل
    # تحت العقد نفسها ولم يبقَ من معنى "الربط" شيء.
    $dist   = $box * 0.355   # مسافة العقدة الفرعية من المركز
    $rNode  = $box * 0.098   # نصف قطر العقدة الفرعية
    $rHub   = $box * 0.155   # نصف قطر العقدة المركزية
    $stroke = $box * 0.058   # سماكة خط الوصل

    $pen = New-Object System.Drawing.Pen($linkColor, $stroke)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round

    # أربع عقد على الأقطار (45°, 135°, 225°, 315°)
    $angles = @(45, 135, 225, 315)
    $pts = @()
    foreach ($a in $angles) {
        $rad = $a * [Math]::PI / 180.0
        $pts += ,@([single]($cx + $dist * [Math]::Cos($rad)), [single]($cy + $dist * [Math]::Sin($rad)))
    }

    # الخطوط أولاً ثم العقد فوقها، حتى تُخفي العقد نهايات الخطوط
    foreach ($p in $pts) {
        $g.DrawLine($pen, $cx, $cy, $p[0], $p[1])
    }

    $brushNode = New-Object System.Drawing.SolidBrush($nodeColor)
    foreach ($p in $pts) {
        $g.FillEllipse($brushNode, $p[0] - $rNode, $p[1] - $rNode, $rNode * 2, $rNode * 2)
    }
    $g.FillEllipse($brushNode, $cx - $rHub, $cy - $rHub, $rHub * 2, $rHub * 2)

    $pen.Dispose()
    $brushNode.Dispose()
}

# mode: legacy | round | foreground | monochrome | store | splash
function New-IconFile([int]$size, [string]$mode, [string]$outPath) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $s = [single]$size
    $glyphBox = $s * 0.74
    $nodeColor = $amber
    $linkColor = $amberSoft

    if ($mode -eq 'legacy' -or $mode -eq 'round' -or $mode -eq 'store') {
        # خلفية متدرّجة قطرياً بين درجتي الكحلي
        $rect = New-Object System.Drawing.RectangleF(0, 0, $s, $s)
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $inkLight, $inkDark, 45.0)

        if ($mode -eq 'round') {
            $g.FillEllipse($grad, 0, 0, $s - 1, $s - 1)
        } elseif ($mode -eq 'store') {
            # متجر Google Play يطبّق قناعه الخاص — الصورة تُسلَّم مربعة كاملة
            $g.FillRectangle($grad, 0, 0, $s, $s)
        } else {
            $inset = $s * 0.055
            $path = Get-RoundedPath $inset $inset ($s - $inset * 2) ($s - $inset * 2) ($s * 0.215)
            $g.FillPath($grad, $path)
            $path.Dispose()
        }
        $grad.Dispose()
    }

    if ($mode -eq 'splash') {
        # شعار شاشة الإقلاع: بلا خلفية (الخلفية الكحلية تأتي من الـ layer-list
        # أو من windowSplashScreenBackground)، والشعار يشغل القماش كاملاً.
        $glyphBox = $s * 0.94
    }

    if ($mode -eq 'foreground' -or $mode -eq 'monochrome') {
        # الأيقونة التكيّفية: القماش 108 وحدة والمرئي منه 72 فقط، فيُصغَّر
        # الشعار إلى ما يعادل حجمه في الأيقونة التقليدية داخل المنطقة الآمنة.
        $glyphBox = $s * 0.50
        if ($mode -eq 'monochrome') {
            # أيقونات أندرويد 13 المموّهة: النظام يلوّنها بنفسه، فتُرسَم بالأبيض
            $nodeColor = $white
            $linkColor = $white
        }
    }

    Draw-Glyph $g ($s / 2.0) ($s / 2.0) $glyphBox $nodeColor $linkColor

    $dir = Split-Path -Parent $outPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Output ("  {0,-52} {1}x{1}" -f (Resolve-Path -Relative $outPath), $size)
}

# ---- كثافات أندرويد: التقليدية 48dp والتكيّفية 108dp ----
$densities = @(
    @{ Name = 'mdpi';    Legacy = 48;  Adaptive = 108; Splash = 120 },
    @{ Name = 'hdpi';    Legacy = 72;  Adaptive = 162; Splash = 180 },
    @{ Name = 'xhdpi';   Legacy = 96;  Adaptive = 216; Splash = 240 },
    @{ Name = 'xxhdpi';  Legacy = 144; Adaptive = 324; Splash = 360 },
    @{ Name = 'xxxhdpi'; Legacy = 192; Adaptive = 432; Splash = 480 }
)

Write-Output 'أيقونات التشغيل (mipmap):'
foreach ($d in $densities) {
    $dir = Join-Path $res ('mipmap-' + $d.Name)
    New-IconFile $d.Legacy   'legacy'     (Join-Path $dir 'ic_launcher.png')
    New-IconFile $d.Legacy   'round'      (Join-Path $dir 'ic_launcher_round.png')
    New-IconFile $d.Adaptive 'foreground' (Join-Path $dir 'ic_launcher_foreground.png')
    New-IconFile $d.Adaptive 'monochrome' (Join-Path $dir 'ic_launcher_monochrome.png')
}

Write-Output 'شعار شاشة الإقلاع (drawable):'
foreach ($d in $densities) {
    $dir = Join-Path $res ('drawable-' + $d.Name)
    New-IconFile $d.Splash 'splash' (Join-Path $dir 'splash_logo.png')
}

# الأصل وأيقونة المتجر خارج assets/ عن قصد: مجلد assets/icons مُعلَن في
# pubspec.yaml، فأي ملف فيه يُحزَم داخل كل APK — وهذان الملفان للتصميم
# والنشر فقط ولا يقرأهما التطبيق أبداً.
Write-Output 'الأصل عالي الدقة وأيقونة المتجر:'
$brand = Join-Path $root 'docs\branding'
New-IconFile 1024 'legacy' (Join-Path $brand 'app_icon_1024.png')
New-IconFile 512  'store'  (Join-Path $brand 'play_store_512.png')

Write-Output 'تم.'
