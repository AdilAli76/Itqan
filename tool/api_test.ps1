# =============================================================================
#  اختبار منطق العمل على الـ API — من الألف إلى الياء
#
#  يختبر ما لا تراه العين: قواعد العمل في السيرفر نفسه، لا ما تخفيه الواجهة.
#  الواجهة تُخفي زراً؛ السؤال هو هل يرفض السيرفر الطلب إن أُرسل مباشرة.
#
#  كلمة المرور: تُطلب منك عند التشغيل ولا تُكتب في هذا الملف ولا تُمرَّر
#  كوسيط سطر أوامر (الوسائط تُسجَّل في تاريخ الأوامر وقائمة العمليات).
#
#  التشغيل:
#      powershell -ExecutionPolicy Bypass -File tool\api_test.ps1
#
#  العنوان يُشتقّ تلقائياً من موقع IIS باسم Kinetic. ولتجاوز ذلك:
#      ... -BaseUrl https://erp.droob-albayan.ly/api
#      ... -SiteName KineticStaging
#
#  يكتب بيانات تجريبية في القاعدة (أصناف وفواتير باسم يبدأ بـ TEST-).
#  لا تُشغّله على قاعدة إنتاج.
# =============================================================================

param(
    # يُشتقّ من الموقع في IIS إن وُجد، وإلا منفذ التطوير — راجع
    # Resolve-BaseUrl أدناه.
    [string]$BaseUrl = "",
    [string]$Email = "",
    # إقرارٌ صريح بالكتابة في دفاتر الإنتاج — راجع حارس الإنتاج أدناه.
    [switch]$AllowProduction,
    # اسم موقع IIS الذي يُشتقّ منه العنوان حين لا يُمرَّر BaseUrl.
    [string]$SiteName = "Kinetic"
)

<#
.SYNOPSIS
    يستنتج عنوان الـAPI من موقع IIS، وإلا يسقط على منفذ التطوير.

.DESCRIPTION
    كان الافتراضي localhost:5000 دائماً — وهو عنوان `dotnet run` في
    التطوير. والسكربت يُشحن داخل حزمة النشر ليُشغَّل على خادمٍ يعمل تحت
    IIS على المنفذ 80، فكان كل من يشغّله هناك يصطدم بـ«السيرفر لا يستجيب»
    ويظنّ النظام معطَّلاً وهو يعمل.
#>
function Resolve-BaseUrl([string]$Site) {
    if (-not (Get-Module -ListAvailable -Name WebAdministration)) { return $null }
    try {
        Import-Module WebAdministration -ErrorAction Stop
        $binding = Get-WebBinding -Name $Site -ErrorAction Stop |
            Sort-Object { if ($_.protocol -eq 'https') { 0 } else { 1 } } |
            Select-Object -First 1
        if (-not $binding) { return $null }

        # bindingInformation صيغتها  IP:Port:Host
        $parts = $binding.bindingInformation -split ':'
        if ($parts.Count -lt 2) { return $null }
        $port = $parts[1]
        # المضيف قد يكون فارغاً (ربط بكل العناوين) — localhost يفي حينها.
        $hostName = if ($parts.Count -ge 3 -and $parts[2]) { $parts[2] } else { 'localhost' }

        $scheme = $binding.protocol
        $suffix = if (($scheme -eq 'http' -and $port -eq '80') -or
                      ($scheme -eq 'https' -and $port -eq '443')) { '' } else { ":$port" }
        return "${scheme}://${hostName}${suffix}/api"
    } catch {
        return $null
    }
}

# ⚠ حارسُ الإنتاج.
#
# هذا السكربت **يكتب** — مئة وأربعة عشر فحصاً تُنشئ زبائن وأصنافاً وفواتير
# باسم TEST-. ومكانه بيئة التجربة وحدها.
#
# وقد شُغِّل مرّة على الإنتاج لأن اشتقاق العنوان يسقط على موقع «Kinetic»
# الافتراضي حين لا يُمرَّر شيء. فصار الإنتاج يحتاج إقراراً صريحاً: من
# قصده كتبه، ومن نسي لا يصيبه.
if ($SiteName -eq 'Kinetic' -and -not $AllowProduction) {
    Write-Host ""
    Write-Host "  رُفض: «Kinetic» هو موقع الإنتاج، وهذا الفحص يكتب بيانات TEST-." -ForegroundColor Red
    Write-Host "  للتجربة:  .	oolpi_test.ps1 -SiteName KineticStaging" -ForegroundColor Yellow
    Write-Host "  وإن قصدتَ الإنتاج فعلاً، أضف -AllowProduction." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

if (-not $BaseUrl) {
    $BaseUrl = Resolve-BaseUrl $SiteName
    if ($BaseUrl) {
        Write-Host "  العنوان مُشتقٌّ من موقع IIS «$SiteName»: $BaseUrl" -ForegroundColor DarkGray
    } else {
        $BaseUrl = "http://localhost:5000/api"
        Write-Host "  لا موقع IIS باسم «$SiteName» — يُجرَّب منفذ التطوير: $BaseUrl" -ForegroundColor DarkGray
    }
}

$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$script:Notes = @()

function Section([string]$title) {
    Write-Host ""
    Write-Host ("=" * 74) -ForegroundColor DarkGray
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host ("=" * 74) -ForegroundColor DarkGray
}

function Check([string]$name, [bool]$ok, [string]$detail = "") {
    if ($ok) {
        $script:Pass++
        Write-Host "  [نجح]  $name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "  [فشل]  $name" -ForegroundColor Red
        if ($detail) { Write-Host "         $detail" -ForegroundColor DarkYellow }
        $script:Notes += "فشل: $name — $detail"
    }
}

function Skipped([string]$name, [string]$why) {
    $script:Skip++
    Write-Host "  [تخطٍ] $name" -ForegroundColor DarkGray
    Write-Host "         $why" -ForegroundColor DarkGray
}

# استدعاء يُرجع دائماً كائناً فيه Status و Body، ولا يرمي استثناءً عند 4xx —
# رفض السيرفر هو **النتيجة المتوقَّعة** في نصف اختبارات هذا الملف.
function Api {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null,
        [string]$Token = $null
    )
    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }

    $params = @{
        Uri             = "$BaseUrl$Path"
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
        TimeoutSec      = 30
    }
    if ($null -ne $Body) {
        $params['ContentType'] = 'application/json; charset=utf-8'
        $params['Body'] = ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $Body -Depth 8)))
    }

    try {
        $response = Invoke-WebRequest @params
        $parsed = $null
        if ($response.Content) { try { $parsed = $response.Content | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $parsed; Raw = $response.Content }
    } catch {
        $status = 0
        $raw = ""
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode.value__
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $raw = $reader.ReadToEnd()
            } catch {}
        }
        $parsed = $null
        if ($raw) { try { $parsed = $raw | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = $status; Body = $parsed; Raw = $raw }
    }
}


# رفع ملف بصيغة multipart — Invoke-WebRequest في PowerShell 5.1 لا يدعم
# -Form، فتُبنى الحمولة يدوياً بالبايتات لتفادي إفساد ترميز محتوى الملف.
function Api-Upload {
    param([string]$Path, [string]$FilePath, [string]$Token)

    $boundary = [System.Guid]::NewGuid().ToString()
    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $fileName = [System.IO.Path]::GetFileName($FilePath)

    $enc = [System.Text.Encoding]::UTF8
    $head = $enc.GetBytes("--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$fileName`"`r`nContent-Type: text/csv`r`n`r`n")
    $tail = $enc.GetBytes("`r`n--$boundary--`r`n")

    $body = New-Object byte[] ($head.Length + $fileBytes.Length + $tail.Length)
    [Array]::Copy($head, 0, $body, 0, $head.Length)
    [Array]::Copy($fileBytes, 0, $body, $head.Length, $fileBytes.Length)
    [Array]::Copy($tail, 0, $body, $head.Length + $fileBytes.Length, $tail.Length)

    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl$Path" -Method POST `
            -Headers @{ Authorization = "Bearer $Token" } `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $body -UseBasicParsing -TimeoutSec 60
        $parsed = $null
        if ($response.Content) { try { $parsed = $response.Content | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $parsed }
    } catch {
        $status = 0; $raw = ""
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode.value__
            try { $raw = (New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
        }
        $parsed = $null
        if ($raw) { try { $parsed = $raw | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = $status; Body = $parsed }
    }
}

# -----------------------------------------------------------------------------
Section "٠. الاتصال وتسجيل الدخول"

$ping = Api GET "/products"
if ($ping.Status -eq 0) {
    Write-Host "  السيرفر لا يستجيب على $BaseUrl — شغّله أولاً (dotnet run)." -ForegroundColor Red
    exit 1
}
Check "السيرفر يستجيب" ($ping.Status -ne 0) ""

# 404 ليس كشفاً بل عنوانٌ خاطئ.
#
# كان الفحص يعدّ كل ما ليس 401 «نقطة نهاية مكشوفة!» — فمن يضرب موقعاً آخر
# في IIS (أو مساراً بلا /api) يرى إنذاراً أمنياً كاذباً ويطارده، بينما
# المشكلة أن التطبيق ليس على هذا العنوان أصلاً. وإنذارٌ كاذب واحد يكفي
# ليُهمَل الحقيقي بعده.
if ($ping.Status -eq 404) {
    Check "نقطة نهاية محمية ترفض بلا توكن (401)" $false `
        ("رجعت 404 — التطبيق ليس على $BaseUrl. " +
         "غالباً موقع IIS آخر يجيب على هذا المنفذ. تحقّق بـ: " +
         "Import-Module WebAdministration; Get-Website | Select Name,State,PhysicalPath")
    Write-Host ""
    Write-Host "  أوقفت الاختبار: العنوان خاطئ لا النظام معطَّل." -ForegroundColor Yellow
    Write-Host "  مرّر العنوان الصحيح بـ -BaseUrl، أو -SiteName لاسم موقع آخر." -ForegroundColor Yellow
    exit 1
}

Check "نقطة نهاية محمية ترفض بلا توكن (401)" ($ping.Status -eq 401) `
    "رجعت $($ping.Status) — نقطة نهاية مكشوفة!"

if (-not $Email -and $env:KINETIC_TEST_EMAIL) { $Email = $env:KINETIC_TEST_EMAIL }
if (-not $Email) { $Email = Read-Host "  البريد الإلكتروني" }

# قراءة كلمة المرور حرفاً حرفاً بدل Read-Host -AsSecureString.
#
# السبب: -AsSecureString لا يلتقط الإدخال بشكل موثوق في الطرفيات المدمجة
# (ظهرت نجمة واحدة مهما طالت الكلمة، فتُرسَل مبتورة ويردّ السيرفر 401 وكأن
# كلمة المرور خاطئة). ReadKey يعمل في أي مضيف حقيقي، ويطبع نجمة لكل حرف
# فيرى المستخدم أن ما كُتب وصل فعلاً.
function Read-Password([string]$label) {
    Write-Host -NoNewline "  $label`: "
    $buffer = New-Object System.Text.StringBuilder
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { Write-Host ""; break }
        if ($key.Key -eq 'Backspace') {
            if ($buffer.Length -gt 0) {
                $buffer.Length--
                Write-Host -NoNewline "`b `b"
            }
            continue
        }
        if ([char]::IsControl($key.KeyChar)) { continue }
        [void]$buffer.Append($key.KeyChar)
        Write-Host -NoNewline "*"
    }
    return $buffer.ToString()
}

$plain = ""

# مسار آليّ: كلمة المرور من متغيّر بيئة.
#
# **لتشغيل الفحص بلا طرفية** — على خادم بناء، أو في جولة تحقّق محلية على
# قاعدة فحص. ولا يُمرَّر كوسيط سطر أوامر: الوسائط تُسجَّل في تاريخ الأوامر
# وفي قائمة العمليات، ومتغيّر البيئة أضيق انتشاراً.
#
# ⚠ **لقاعدة فحص لا لإنتاج**: هذا السكربت يكتب بيانات (أصناف وفواتير باسم
# TEST-)، وحسابٌ حقيقي في متغيّر بيئة على جهاز مشترك يُقرأ من أي عملية
# تعمل بنفس الحساب.
if ($env:KINETIC_TEST_PASSWORD) {
    $plain = $env:KINETIC_TEST_PASSWORD
    Write-Host "  كلمة المرور من KINETIC_TEST_PASSWORD (تشغيل آليّ)" -ForegroundColor DarkGray
}
else {
try {
    $plain = Read-Password "كلمة المرور"
} catch {
    # لا طرفية حقيقية (إعادة توجيه أو مضيف بلا Console) — الرجوع للطريقة
    # القياسية بدل الفشل الصامت.
    $secure = Read-Host "  كلمة المرور" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
}

$capturedLength = $plain.Length
if ($capturedLength -eq 0) {
    Write-Host "  لم يُلتقط أي حرف من كلمة المرور." -ForegroundColor Red
    Write-Host "  شغّله من نافذة PowerShell حقيقية، أو اضبط KINETIC_TEST_EMAIL و" -ForegroundColor DarkYellow
    Write-Host "  KINETIC_TEST_PASSWORD للتشغيل الآليّ على قاعدة فحص." -ForegroundColor DarkYellow
    exit 1
}

$login = Api POST "/auth/login" @{ emailOrUsername = $Email; password = $plain }
$plain = $null

if ($login.Status -ne 200 -or -not $login.Body.token) {
    Write-Host "  تعذّر تسجيل الدخول (حالة $($login.Status)). أوقفت الاختبار." -ForegroundColor Red
    Write-Host "  التُقط $capturedLength حرفاً من كلمة المرور." -ForegroundColor DarkYellow
    Write-Host "  إن كان هذا العدد أقل مما كتبت فالمشكلة في التقاط الطرفية لا في كلمة المرور." -ForegroundColor DarkYellow
    Write-Host "  وإن كان مطابقاً فالكلمة نفسها غير صحيحة — أعِد تعيينها بـ:" -ForegroundColor DarkYellow
    Write-Host "      cd backend\KineticEnterprise.Api; dotnet run -- reset-user-password" -ForegroundColor DarkYellow
    exit 1
}
$token = $login.Body.token
$role = $login.Body.role
$isAdmin = $role -eq 'super_admin'
Check "تسجيل الدخول" $true ""
Write-Host "         الدور: $role" -ForegroundColor DarkGray

$badLogin = Api POST "/auth/login" @{ emailOrUsername = $Email; password = "definitely-not-the-password" }
Check "كلمة مرور خاطئة تُرفض (401)" ($badLogin.Status -eq 401) "رجعت $($badLogin.Status)"
Check "رسالة الخطأ لا تكشف وجود البريد" ($badLogin.Body.message -notmatch 'غير موجود|not found') "الرسالة: $($badLogin.Body.message)"

# -----------------------------------------------------------------------------
Section "١. الهوية والإعدادات"

$org = Api GET "/organizations/me" -Token $token
Check "قراءة هوية المنظمة" ($org.Status -eq 200) "حالة $($org.Status)"
if ($org.Status -eq 200) {
    Write-Host "         المنظمة: $($org.Body.displayName) | العملة: $($org.Body.currencySymbol)" -ForegroundColor DarkGray
}

$settings = Api GET "/organizations/me/settings" -Token $token
Check "قراءة إعدادات المنظمة" ($settings.Status -eq 200) "حالة $($settings.Status)"

$hasOpenFlag = $settings.Body.PSObject.Properties.Name -contains 'posAllowOpenProduct'
Check "إعداد الصنف المفتوح موجود في الـ API" $hasOpenFlag "العمود/الحقل مفقود — نفّذ docs\MIGRATIONS.sql"
$openAllowed = [bool]$settings.Body.posAllowOpenProduct
Write-Host "         بيع الأصناف مفتوحة القيمة: $(if ($openAllowed) {'مفعَّل'} else {'مطفأ'})" -ForegroundColor DarkGray

$perms = Api GET "/permissions/catalog" -Token $token
if ($isAdmin) {
    Check "كتالوج الصلاحيات غير فارغ" ($perms.Status -eq 200 -and $perms.Body.Count -gt 0) "عدد الصلاحيات: $($perms.Body.Count) — جدول permissions فارغ يعني فشل إنشاء أي منظمة جديدة"
} else {
    # PermissionsController محمي بـ [Authorize(Roles = "super_admin")] عمداً:
    # منح صلاحية لدور هو قرار تصعيد امتيازات لا يُفوَّض. فالمنع هو النجاح.
    Check "كتالوج الصلاحيات محجوب عن الدور $role (403)" ($perms.Status -eq 403) "حالة $($perms.Status) — وصول غير إداري إلى مصفوفة الصلاحيات!"
}
# الفحص على النص الخام لا على خصائص الكائن: اختلاف حالة الأحرف في تسمية
# حقول JSON كان يجعل الفحص يفشل بينما الصلاحية موجودة فعلاً في القاعدة.
if ($isAdmin) {
    $hasOverride = $perms.Raw -match 'pos\.price_override'
    Check "صلاحية pos.price_override مسجَّلة" $hasOverride "غير موجودة في ردّ الـ API — نفّذ docs\MIGRATIONS.sql"
} else {
    Skipped "فحص كتالوج الصلاحيات" "الكتالوج مقصور على super_admin — يُفحَص بحساب إداري"
}

# تلف الترميز يظهر كسلسلة 'ط' متبوعة بحرف لاتيني ممتد — يُفحَص على الخام
# لأن الحقل قد يأتي بأي تسمية.
if ($isAdmin) {
    $garbledCount = ([regex]::Matches($perms.Raw, 'ط[ -ÿ]')).Count
    Check "أسماء الصلاحيات عربية سليمة" ($garbledCount -eq 0) "$garbledCount موضع تالف الترميز في قاعدة البيانات"
}

# -----------------------------------------------------------------------------
Section "٢. الفروع والكتالوج"

$branches = Api GET "/branches" -Token $token
Check "قراءة الفروع" ($branches.Status -eq 200) "حالة $($branches.Status)"
$branchId = $null
if ($branches.Status -eq 200 -and $branches.Body.Count -gt 0) { $branchId = $branches.Body[0].id }
if (-not $branchId) {
    Write-Host "  لا يوجد فرع — مراحل البيع ستُتخطى. أنشئ فرعاً من شاشة الفروع." -ForegroundColor Yellow
}

$stamp = Get-Date -Format "yyyyMMddHHmmss"
$productPrice = 100
$newProduct = Api POST "/products" -Token $token -Body @{
    sku = "TEST-$stamp"
    name = "صنف اختبار $stamp"
    salePrice = $productPrice
    costPrice = 60
    unitBase = "piece"
    tracksStock = $true
    reorderLevel = 2
}

$canManageInventory = $true
$productId = $null

if ($newProduct.Status -eq 403) {
    # 403 هنا **سلوك صحيح**: إنشاء الأصناف يتطلّب inventory.manage، والكاشير
    # لا يملكها. فبدل إفشال الاختبار، نستعمل صنفاً قائماً في الكتالوج — وهذا
    # ما يسمح بتشغيل اختبارات التسعير بحساب كاشير، وهي الاختبارات الوحيدة
    # التي تُثبت أن منع تعديل السعر يعمل في وجه من يهمّه تجاوزه.
    Check "إنشاء صنف ممنوع على الدور $role (403)" $true "منع صحيح — inventory.manage غير ممنوحة"
    $canManageInventory = $false

    $existing = Api GET "/products/inventory" -Token $token
    # سعر أكبر من صفر شرط لا تفصيل: صنف بسعر 0.00 يجعل اختبار "سعر مخالف
    # يُرفض" أضعف مما يبدو، ويُنشئ فواتير بقيمة صفر في الدفتر الحقيقي.
    # ‎.Body.items لا ‎.Body — الرد صفحة {items, totalCount, page, pageSize}
    # (ProductInventoryPageDto). تمرير الصفحة نفسها عبر Where-Object كان يُرجع
    # لا شيء دائماً، فتُتخطّى اختبارات المخزون بصمت وتبدو ناجحة.
    $sellable = $existing.Body.items |
        Where-Object { $_.quantity -gt 1 -and $_.tracksStock -ne $false -and [decimal]$_.salePrice -gt 0 } |
        Select-Object -First 1
    if ($sellable) {
        $productId = $sellable.id
        $productPrice = [decimal]$sellable.salePrice
        Write-Host "         سيُستخدم صنف قائم: $($sellable.name) بسعر $productPrice ورصيد $($sellable.quantity)" -ForegroundColor DarkGray
        Write-Host "         تنبيه: هذا صنف حقيقي من الكتالوج — ستُنشأ فواتير في الدفتر الفعلي" -ForegroundColor Yellow
        Write-Host "         (البيع ثم الاسترجاع يُعيدان الرصيد كما كان، لكن الفواتير تبقى)" -ForegroundColor Yellow
    } else {
        Skipped "اختبارات التسعير" "لا صنف قائم برصيد كافٍ في هذه المنظمة — أضف صنفاً ورصيداً بحساب إداري أولاً"
    }
} else {
    Check "إنشاء صنف" ($newProduct.Status -in 200,201) "حالة $($newProduct.Status) — $($newProduct.Body.message)"
    $productId = $newProduct.Body.id

    # رسالة انتهاك القيد بالعربية — DbConstraintMessageMiddleware.
    #
    # يُختبر على الخادم لا في الواجهة: الحماية الحقيقية هي القيد الفريد في
    # قاعدة البيانات (الفحص المسبق في الكود يسقط أمام طلبين متزامنين)، والمهم
    # أن رسالته تصل عربية مفهومة لا نصّ SQL Server خاماً.
    $duplicate = Api POST "/products" -Token $token -Body @{
        sku = "TEST-$stamp"
        name = "صنف مكرّر $stamp"
        salePrice = $productPrice
        costPrice = 60
        unitBase = "piece"
    }
    Check "رفض تكرار رمز الصنف (409)" ($duplicate.Status -eq 409) "حالة $($duplicate.Status)"
    # يذكر SKU صراحةً: رسالة عامة («القيمة مستعملة») تترك المستخدم يخمّن أي
    # حقل يصحّح، وهو ما تُوجد هذه الطبقة لتفاديه.
    Check "الرسالة عربية وتسمّي الحقل" `
        ($duplicate.Body.message -and $duplicate.Body.message -match 'SKU|رمز الصنف') `
        "الرسالة: $($duplicate.Body.message)"
}

if ($productId -and $branchId -and $canManageInventory) {
    $adjust = Api POST "/products/$productId/stock-adjustments" -Token $token -Body @{
        branchId = $branchId; quantityDelta = 10
    }
    Check "إدخال رصيد افتتاحي (10)" ($adjust.Status -in 200,201) "حالة $($adjust.Status) — $($adjust.Body.message)"

    # التحقق أن الرصيد دخل فعلاً: نقطة النهاية تُرجع 200 حتى لو كان التغيير
    # صفراً (اسم حقل خاطئ يعني ربطاً صامتاً بصفر)، فبلا هذا الفحص تتتالى
    # كل اختبارات البيع بعده فاشلة لسبب غير حقيقي.
    $check = Api GET "/products/inventory?search=TEST-$stamp" -Token $token
    $qty = ($check.Body.items | Where-Object { $_.id -eq $productId }).quantity
    Check "الرصيد الافتتاحي وصل فعلاً (10)" ([decimal]$qty -eq 10) "الرصيد المقروء: $qty" 
}

# -----------------------------------------------------------------------------
Section "٣. قواعد التسعير — ما تخفيه الواجهة لا يكفي"

if (-not ($productId -and $branchId)) {
    Skipped "اختبارات البيع" "لا صنف أو لا فرع"
} else {
    # البيع بالسعر الصحيح
    $sale = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $productId; quantity = 1; unitPrice = $productPrice })
    }
    Check "بيع بسعر الكتالوج ينجح" ($sale.Status -in 200,201) "حالة $($sale.Status) — $($sale.Body.message)"
    $invoiceId = $sale.Body.id

    # الاختبار الحاسم: سعر مخالف مُرسَل مباشرة إلى الـ API
    $cheat = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $productId; quantity = 1; unitPrice = 0.5 })
    }
    $role = $login.Body.role
    if ($role -eq 'super_admin') {
        Check "سعر مخالف يُقبل من super_admin ويُسجَّل في التدقيق" ($cheat.Status -in 200,201) `
            "حالة $($cheat.Status) — المدير العام يملك pos.price_override دائماً"
        $script:Notes += "ملاحظة: اختبار رفض السعر المخالف يحتاج حساباً بدور كاشير — super_admin يتجاوزه بحكم التصميم."
    } else {
        Check "سعر مخالف يُرفض ممن لا يملك pos.price_override" ($cheat.Status -eq 400) `
            "حالة $($cheat.Status) — إن نجح البيع بنصف دينار فالسعر ما زال من العميل!"
    }

    # كمية صفرية أو سالبة
    $badQty = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $productId; quantity = 0; unitPrice = $productPrice })
    }
    Check "كمية صفر تُرفض" ($badQty.Status -eq 400) "حالة $($badQty.Status)"

    $negQty = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $productId; quantity = -5; unitPrice = $productPrice })
    }
    Check "كمية سالبة تُرفض" ($negQty.Status -eq 400) "حالة $($negQty.Status) — كمية سالبة تزيد المخزون وتُنقص الإيراد"

    # صنف غير موجود
    $ghost = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = "00000000-0000-0000-0000-000000000099"; quantity = 1; unitPrice = 1 })
    }
    Check "صنف غير موجود يُرفض" ($ghost.Status -eq 400) "حالة $($ghost.Status)"

    # -------------------------------------------------------------------------
    Section "٤. المخزون والتزامن"

    $available = Api GET "/products/inventory?search=TEST-$stamp" -Token $token
    $currentQty = ($available.Body.items | Where-Object { $_.id -eq $productId }).quantity
    Write-Host "         الرصيد الحالي: $currentQty" -ForegroundColor DarkGray

    $overSell = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $productId; quantity = 9999; unitPrice = $productPrice })
    }
    Check "البيع بما يفوق الرصيد يُرفض" ($overSell.Status -eq 400) "حالة $($overSell.Status)"

    if (-not $canManageInventory) {
        Skipped "اختبار التزامن" "ضبط الرصيد إلى قطعة واحدة يتطلّب inventory.manage — يُشغَّل بحساب إداري"
    } else {

    # سباق حقيقي: طلبان متزامنان على آخر قطعة.
    # يُضبط الرصيد إلى 1 ثم يُرسَل طلبان معاً؛ يجب أن ينجح واحد فقط.
    $reset = Api GET "/products/inventory?search=TEST-$stamp" -Token $token
    $qtyNow = ($reset.Body.items | Where-Object { $_.id -eq $productId }).quantity
    if ($qtyNow -gt 1) {
        Api POST "/products/$productId/stock-adjustments" -Token $token -Body @{
            branchId = $branchId; quantityDelta = -($qtyNow - 1)
        } | Out-Null
    }

    $body = ConvertTo-Json @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $productId; quantity = 1; unitPrice = $productPrice })
    } -Depth 8

    $jobs = 1..2 | ForEach-Object {
        Start-Job -ScriptBlock {
            param($url, $tok, $payload)
            try {
                $r = Invoke-WebRequest -Uri $url -Method POST -Headers @{ Authorization = "Bearer $tok" } `
                    -ContentType 'application/json; charset=utf-8' `
                    -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -UseBasicParsing -TimeoutSec 30
                [int]$r.StatusCode
            } catch {
                if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode.value__ } else { 0 }
            }
        } -ArgumentList "$BaseUrl/invoices", $token, $body
    }
    $codes = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    $succeeded = ($codes | Where-Object { $_ -in 200,201 }).Count

    if ($succeeded -eq 0) {
        # كلاهما رُفض: لا رصيد أصلاً، فالاختبار لم يُجرَ. الإبلاغ عنه كفشل
        # يعني إنذاراً كاذباً عن قفل التزامن وهو لم يُختبَر بعد.
        Skipped "بيعان متزامنان لآخر قطعة" "رُفض الطلبان (الرموز: $($codes -join ', ')) — لا رصيد للاختبار، النتيجة غير حاسمة"
    } else {
        Check "بيعان متزامنان لآخر قطعة: ينجح واحد فقط" ($succeeded -eq 1) `
            "نجح $succeeded من 2 (الرموز: $($codes -join ', ')) — نجاح اثنين يعني بيع بضاعة غير موجودة"
    }

    $after = Api GET "/products/inventory?search=TEST-$stamp" -Token $token
    $finalQty = ($after.Body.items | Where-Object { $_.id -eq $productId }).quantity
    Check "الرصيد لم يصبح سالباً" ($finalQty -ge 0) "الرصيد النهائي: $finalQty"
    }

    # -------------------------------------------------------------------------
    Section "٥. الاسترجاع"

    if ($invoiceId) {
        $refund1 = Api POST "/invoices/$invoiceId/refund" -Token $token
        Check "استرجاع فاتورة ينجح" ($refund1.Status -in 200,201) "حالة $($refund1.Status) — $($refund1.Body.message)"

        $refund2 = Api POST "/invoices/$invoiceId/refund" -Token $token
        Check "الاسترجاع المكرَّر يُرفض" ($refund2.Status -eq 400) `
            "حالة $($refund2.Status) — قبوله يعني إعادة البضاعة وردّ المال مرتين"
    } else {
        Skipped "اختبارات الاسترجاع" "لم تُنشأ فاتورة"
    }
}

# -----------------------------------------------------------------------------
Section "٥.١ الاستيراد من ملف"

if (-not $canManageInventory) {
    Skipped "اختبارات الاستيراد" "تتطلّب inventory.manage — تُشغَّل بحساب إداري"
} else {
    $csvPath = Join-Path $env:TEMP "kinetic_import_$stamp.csv"
    # BOM ثم أعمدة عربية: هذا بالضبط ما يُنتجه إكسل العربي عند الحفظ كـ CSV،
    # فالاختبار يمرّ بنفس الطريق الذي سيسلكه ملف العميل.
    $csv = "الاسم,الرمز,سعر البيع,سعر التكلفة,حد الطلب`r`n" +
           "صنف استيراد أ $stamp,IMP-A-$stamp,25.5,20,5`r`n" +
           "صنف استيراد ب $stamp,IMP-B-$stamp,١٢٫٥,10,3`r`n" +
           ",IMP-C-$stamp,30,25,2`r`n"
    [System.IO.File]::WriteAllText($csvPath, $csv, (New-Object System.Text.UTF8Encoding($true)))

    # معاينة: يجب أن تكتشف الصف الثالث (بلا اسم) ولا تكتب شيئاً
    $dry = Api-Upload "/products/import?dryRun=true" $csvPath $token
    Check "المعاينة تقرأ الملف" ($dry.Status -eq 200) "حالة $($dry.Status) — $($dry.Body.message)"
    Check "المعاينة تكتشف الصف الناقص" ([int]$dry.Body.withErrors -eq 1) "أخطاء: $($dry.Body.withErrors) (المتوقَّع 1)"
    Check "المعاينة تقرأ الأرقام العربية (١٢٫٥)" ([int]$dry.Body.willCreate -eq 2) "جديد: $($dry.Body.willCreate) (المتوقَّع 2)"

    $beforeCount = (Api GET "/products" -Token $token).Body.Count
    $commitBad = Api-Upload "/products/import?dryRun=false" $csvPath $token
    Check "الاستيراد يُرفض ما دام فيه خطأ" ($commitBad.Status -eq 400) "حالة $($commitBad.Status)"
    $afterCount = (Api GET "/products" -Token $token).Body.Count
    Check "لم يُكتب أي صنف رغم محاولة التنفيذ" ($afterCount -eq $beforeCount) "قبل $beforeCount بعد $afterCount"

    # ملف سليم
    $goodPath = Join-Path $env:TEMP "kinetic_import_ok_$stamp.csv"
    $good = "الاسم,الرمز,سعر البيع,سعر التكلفة`r`n" +
            "صنف استيراد أ $stamp,IMP-A-$stamp,25.5,20`r`n" +
            "صنف استيراد ب $stamp,IMP-B-$stamp,١٢٫٥,10`r`n"
    [System.IO.File]::WriteAllText($goodPath, $good, (New-Object System.Text.UTF8Encoding($true)))

    $commit = Api-Upload "/products/import?dryRun=false" $goodPath $token
    Check "استيراد ملف سليم ينجح" ($commit.Status -eq 200 -and [int]$commit.Body.willCreate -eq 2) `
        "حالة $($commit.Status) — جديد $($commit.Body.willCreate)"

    # إعادة استيراد نفس الملف: تحديث لا تكرار
    $again = Api-Upload "/products/import?dryRun=true" $goodPath $token
    Check "إعادة الاستيراد تُحدِّث ولا تُكرِّر" ([int]$again.Body.willUpdate -eq 2 -and [int]$again.Body.willCreate -eq 0) `
        "جديد $($again.Body.willCreate) / تحديث $($again.Body.willUpdate)"

    $tpl = Api GET "/products/import/template" -Token $token
    Check "قالب الاستيراد يُنزَّل" ($tpl.Status -eq 200) "حالة $($tpl.Status)"

    Remove-Item $csvPath, $goodPath -ErrorAction SilentlyContinue
}

# -----------------------------------------------------------------------------
Section "٥.٢ صرف الدفعات — FEFO"

# الخطأ الذي يمسكه هذا القسم: البيع كان يقرأ صفّ رصيد واحداً بـ FirstOrDefault
# بلا ORDER BY، بينما UQ_stock_levels يسمح بصفٍّ لكل دفعة. فكان يرفض بيع 15
# والمتاح 30 موزّعة على ثلاث دفعات، ويخصم من دفعة يقرّرها مخطّط SQL — فتُصرَّف
# البعيدة الانتهاء وتتلف القريبة على الرفّ.

if (-not $canManageInventory) {
    Skipped "صرف الدفعات (FEFO)" "إنشاء الدفعات يتطلّب inventory.manage — يُشغَّل بحساب إداري"
} else {

$fefoProduct = Api POST "/products" -Token $token -Body @{
    sku = "TEST-FEFO-$stamp"
    name = "دواء اختبار الدفعات $stamp"
    salePrice = 10; costPrice = 5
    unitBase = "piece"; tracksStock = $true; trackExpiry = $true; reorderLevel = 0
}

if ($fefoProduct.Status -notin 200,201) {
    Skipped "صرف الدفعات (FEFO)" "تعذّر إنشاء صنف الاختبار (حالة $($fefoProduct.Status))"
} else {
    $fefoId = $fefoProduct.Body.id
    $today  = (Get-Date).Date

    # ثلاث دفعات بكميات متساوية وتواريخ مختلفة، مُدخَلة بترتيب غير ترتيب
    # الصلاحية عمداً — حتى لا ينجح الاختبار بمجرّد أن يلتقط النظام الأقدم إدخالاً.
    $batches = @(
        @{ n = "B-LATE-$stamp"; d = $today.AddDays(180); q = 10 },
        @{ n = "B-SOON-$stamp"; d = $today.AddDays(30);  q = 10 },
        @{ n = "B-MID-$stamp";  d = $today.AddDays(90);  q = 10 }
    )
    foreach ($b in $batches) {
        Api POST "/products/$fefoId/stock-adjustments" -Token $token -Body @{
            branchId = $branchId; quantityDelta = $b.q
            batchNumber = $b.n; expiryDate = $b.d.ToString('yyyy-MM-dd')
        } | Out-Null
    }

    # الرد صفحة {items, totalCount, page, pageSize} لا مصفوفة — راجع
    # ProductInventoryPageDto في ProductsController.cs.
    $inv = Api GET "/products/inventory?search=TEST-FEFO-$stamp" -Token $token
    $totalQty = ($inv.Body.items | Where-Object { $_.id -eq $fefoId }).quantity
    Check "المتاح مجموع الدفعات الثلاث" ([decimal]$totalQty -eq 30) "المعروض: $totalQty (المتوقَّع 30)"

    # 15 لا تسعها دفعة واحدة (10) — هذا هو البيع الذي كان يُرفض.
    $spanSale = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $fefoId; quantity = 15; unitPrice = 10 })
    }
    Check "بيع كمية تمتدّ على أكثر من دفعة ينجح" ($spanSale.Status -in 200,201) `
        "حالة $($spanSale.Status) — الرفض يعني أن الفحص ما زال على دفعة واحدة"

    # رصيد كل دفعة من نقطة قراءة حقيقية.
    #
    # كانت تُقرأ بـ«تعديل مخزون بصفر» — حيلةٌ توقّفت حين صار التعديل الصفري
    # يُرفض صراحةً («لا تغيير في الكمية»)، وهو رفضٌ صحيح: صفٌّ في الدفتر بلا
    # حركة ضجيج. فبقيت أربعة فحوص تقارن قيماً فارغة وتفشل بلا أن يكون في
    # المنتج عطب — وفحصٌ يفشل بلا سبب حقيقي يُدرَّب على تجاهله.
    function Get-BatchQty([string]$name) {
        $r = Api GET "/products/$fefoId/batches?branchId=$branchId&includeEmpty=true" -Token $token
        if ($r.Status -ne 200) { return $null }
        $row = @($r.Body) | Where-Object { $_.batchNumber -eq $name } | Select-Object -First 1
        if ($null -eq $row) { return 0 }
        return [decimal]$row.quantity
    }

    $qSoon = Get-BatchQty "B-SOON-$stamp"
    $qMid  = Get-BatchQty "B-MID-$stamp"
    $qLate = Get-BatchQty "B-LATE-$stamp"
    Write-Host "         بعد بيع 15 — القريبة: $qSoon | الوسطى: $qMid | البعيدة: $qLate" -ForegroundColor DarkGray

    Check "الأقرب انتهاءً تُستنفد أولاً" ($qSoon -eq 0) "المتبقّي في القريبة: $qSoon (المتوقَّع 0)"
    Check "الفائض يُؤخذ من التالية بالترتيب" ($qMid -eq 5) "المتبقّي في الوسطى: $qMid (المتوقَّع 5)"
    Check "البعيدة انتهاءً لم تُمَسّ" ($qLate -eq 10) "المتبقّي في البعيدة: $qLate (المتوقَّع 10)"

    # دفعة منتهية الصلاحية: كمية كبيرة لا يجوز أن تُحتسب ضمن المتاح للبيع.
    Api POST "/products/$fefoId/stock-adjustments" -Token $token -Body @{
        branchId = $branchId; quantityDelta = 100
        batchNumber = "B-EXPIRED-$stamp"; expiryDate = $today.AddDays(-10).ToString('yyyy-MM-dd')
    } | Out-Null

    # المتبقّي الصالح 15 فقط (5 وسطى + 10 بعيدة) رغم أن المجموع 115.
    $expiredSale = Api POST "/invoices" -Token $token -Body @{
        branchId = $branchId; paymentMethod = "cash"
        lines = @(@{ productId = $fefoId; quantity = 20; unitPrice = 10 })
    }
    Check "المنتهي الصلاحية لا يُباع ولا يُحتسب متاحاً" ($expiredSale.Status -eq 400) `
        "حالة $($expiredSale.Status) — القبول يعني صرف دواء منتهي الصلاحية"

    $qExpired = Get-BatchQty "B-EXPIRED-$stamp"
    Check "الدفعة المنتهية بقيت كما هي" ($qExpired -eq 100) "المتبقّي: $qExpired (المتوقَّع 100)"

    # المرتجع يعيد كل كمية إلى دفعتها لا إلى دفعة عامة.
    if ($spanSale.Status -in 200,201) {
        $saleId = $spanSale.Body.id
        $ret = Api POST "/invoices/$saleId/refund" -Token $token
        if ($ret.Status -in 200,201) {
            $qSoonBack = Get-BatchQty "B-SOON-$stamp"
            $qMidBack  = Get-BatchQty "B-MID-$stamp"
            Check "المرتجع يعيد الكمية إلى دفعتها الأصلية" (($qSoonBack -eq 10) -and ($qMidBack -eq 10)) `
                "القريبة: $qSoonBack (10) | الوسطى: $qMidBack (10) — رجوعها إلى دفعة عامة يحرّف أرصدة الدفعات"
        } else {
            Skipped "المرتجع يعيد الكمية إلى دفعتها الأصلية" "تعذّر الاسترجاع (حالة $($ret.Status))"
        }
    }
}
}

# -----------------------------------------------------------------------------
Section "٥.٧ فئات العملاء وصرف المرتَّبات"

# العطب الذي يمسكه هذا القسم: مبلغ الاستحقاق كان رقماً على كل عميل،
# فجهةٌ تصرف على ألف منتسب في ثلاث فئات ترفع مرتب الفئة بتعديل ألف صفّ.
#
# وأخطر ما يُفحَص هنا **منع الصرف المزدوج**: زرٌّ يُضغط مرّتين، أو خدمة
# تعمل على خادمين، كانا سيُضاعفان المرتَّب على ألف بطاقة — والمال الخارج
# لا يعود.

$catA = Api POST "/customer-categories" -Token $token -Body @{
    name = "فئة أ $stamp"; periodAmount = 100; unspentExpires = $true
}
Check "فئة يسقط رصيدها أُنشئت" ($catA.Status -in 200,201) `
    "حالة $($catA.Status) — $($catA.Body.message)"

$catB = Api POST "/customer-categories" -Token $token -Body @{
    name = "فئة ب $stamp"; periodAmount = 50; unspentExpires = $false
}
Check "فئة يتراكم رصيدها أُنشئت" ($catB.Status -in 200,201) "حالة $($catB.Status)"

# اسمٌ مكرَّر يجعل اختيار الصحيحة تخميناً.
$dupCat = Api POST "/customer-categories" -Token $token -Body @{
    name = "فئة أ $stamp"; periodAmount = 100; unspentExpires = $true
}
Check "فئة باسم مكرَّر تُرفض" ($dupCat.Status -eq 409) "حالة $($dupCat.Status)"

$negCat = Api POST "/customer-categories" -Token $token -Body @{
    name = "فئة سالبة $stamp"; periodAmount = -5; unspentExpires = $true
}
Check "مرتَّب سالب يُرفض" ($negCat.Status -eq 400) "حالة $($negCat.Status)"

if ($catA.Status -notin 200,201 -or $catB.Status -notin 200,201) {
    Skipped "صرف المرتَّبات" "تعذّر تجهيز الفئات"
} else {
    # ── ثلاثة منتسبين: عاديّ، ومُعدَّل، وموقوف ──────────────────────────
    $m1 = Api POST "/customers" -Token $token -Body @{
        fullName = "منتسب عادي $stamp"; accountModel = "entitlement"; categoryId = $catA.Body.id
    }
    $m2 = Api POST "/customers" -Token $token -Body @{
        fullName = "منتسب معدَّل $stamp"; accountModel = "entitlement"
        categoryId = $catA.Body.id; entitlementOverride = 250
    }
    $m3 = Api POST "/customers" -Token $token -Body @{
        fullName = "منتسب موقوف $stamp"; accountModel = "entitlement"
        categoryId = $catA.Body.id; entitlementOverride = 0
    }
    # ورصيدٌ مدفوع مسبقاً — لا تمسّه المنحة أبداً.
    $prepaid = Api POST "/customers" -Token $token -Body @{
        fullName = "زبون مدفوع مسبقاً $stamp"; accountModel = "prepaid"; categoryId = $catA.Body.id
    }

    $ready = ($m1.Status -in 200,201) -and ($m2.Status -in 200,201) -and ($m3.Status -in 200,201)
    Check "المنتسبون أُنشئوا بفئاتهم" $ready "حالات: $($m1.Status) $($m2.Status) $($m3.Status)"

    if (-not $ready) {
        Skipped "صرف المرتَّبات" "تعذّر إنشاء المنتسبين"
    } else {
        # ── المعاينة قبل الصرف ──────────────────────────────────────────
        $preview = Api GET "/customer-categories/disburse/preview?categoryId=$($catA.Body.id)" -Token $token
        Check "معاينة الصرف تُقرأ" ($preview.Status -eq 200) "حالة $($preview.Status)"
        Check "المعاينة تعدّ الموقوفين على حدة" ([int]$preview.Body.suspended -ge 1) `
            "موقوفون $($preview.Body.suspended) — خلطُهم بالمدفوع يُخفيهم"
        Check "المعاينة تحسب التعديل الفردي" ([double]$preview.Body.totalAmount -ge 350) `
            "المجموع $($preview.Body.totalAmount) — المتوقّع 100 + 250 على الأقلّ"

        # ── الصرف ───────────────────────────────────────────────────────
        $pay = Api POST "/customer-categories/disburse" -Token $token -Body @{
            categoryId = $catA.Body.id
        }
        Check "الصرف يمرّ" ($pay.Status -eq 200) "حالة $($pay.Status) — $($pay.Body.message)"
        Check "الموقوف لم يُصرف له" ([int]$pay.Body.skipped -ge 1) `
            "متخطّى $($pay.Body.skipped) — التعديل بصفر قرارٌ صريح بالإيقاف"

        if ($pay.Status -eq 200) {
            $b1 = Api GET "/customers/$($m1.Body.id)" -Token $token
            $b2 = Api GET "/customers/$($m2.Body.id)" -Token $token
            $b3 = Api GET "/customers/$($m3.Body.id)" -Token $token

            Check "المنتسب العادي قبض مرتَّب فئته" `
                ([Math]::Abs([double]$b1.Body.walletBalance - 100) -lt 0.01) "رصيده $($b1.Body.walletBalance)"
            Check "التعديل الفردي يَجُبّ الفئة" `
                ([Math]::Abs([double]$b2.Body.walletBalance - 250) -lt 0.01) "رصيده $($b2.Body.walletBalance)"
            Check "الموقوف رصيده صفر" `
                ([Math]::Abs([double]$b3.Body.walletBalance) -lt 0.01) "رصيده $($b3.Body.walletBalance)"

            if ($prepaid.Status -in 200,201) {
                $bp = Api GET "/customers/$($prepaid.Body.id)" -Token $token
                Check "الرصيد المدفوع مسبقاً لم يمسّه المرتَّب" `
                    ([Math]::Abs([double]$bp.Body.walletBalance) -lt 0.01) `
                    "رصيده $($bp.Body.walletBalance) — شحنُه يعني صرف مالٍ لمن دفع ماله"
            }

            # ── الصرف مرّتين في الدورة نفسها ────────────────────────────
            $again = Api POST "/customer-categories/disburse" -Token $token -Body @{
                categoryId = $catA.Body.id
            }
            Check "الصرف الثاني لا يدفع شيئاً" `
                ($again.Status -eq 200 -and [int]$again.Body.customersPaid -eq 0) `
                "دُفع لـ$($again.Body.customersPaid) — المضاعفة على ألف بطاقة لا تعود"

            $b1After = Api GET "/customers/$($m1.Body.id)" -Token $token
            Check "الرصيد لم يتضاعف" `
                ([Math]::Abs([double]$b1After.Body.walletBalance - 100) -lt 0.01) `
                "رصيده $($b1After.Body.walletBalance) — المتوقّع 100 كما هو"
        }

        # ── رفع مرتب الفئة يسري على القادم لا الماضي ────────────────────
        $raise = Api PUT "/customer-categories/$($catA.Body.id)" -Token $token -Body @{
            name = "فئة أ $stamp"; periodAmount = 300; unspentExpires = $true
        }
        Check "رفع مرتب الفئة يمرّ" ($raise.Status -in 200,204) "حالة $($raise.Status)"

        $b1AfterRaise = Api GET "/customers/$($m1.Body.id)" -Token $token
        Check "رفع المرتب لا يمسّ ما صُرف" `
            ([Math]::Abs([double]$b1AfterRaise.Body.walletBalance - 100) -lt 0.01) `
            "رصيده $($b1AfterRaise.Body.walletBalance) — تعديل الماضي يجعل الكشف لا يطابق ما قُبض"
    }
}

# -----------------------------------------------------------------------------
Section "٥.٣ أنماط بطاقة المحفظة"

# العطب الذي يمسكه هذا القسم: الرقم السرّي كان إلزامياً دائماً بلا بديل،
# والرقم وسيلةُ إثبات يعرفها طرفان — الزبون يُدخله على جهاز الكاشير فيراه أو
# يحفظه، ثم يسحب بعد انصرافه بالبحث عن اسمه. البديل هو نمط «البطاقة وحدها
# بسقف يومي»: لا رقم يُحفَظ أصلاً، والخطر محصور برقم يضعه صاحب المحل.
#
# والسؤال الذي يُجاب هنا: هل يفرض **السيرفر** السقف، أم أنه رقمٌ تعرضه
# الواجهة ويُتجاوَز بطلب HTTP مباشر؟

$origSettings = Api GET "/organizations/me/settings" -Token $token
if ($origSettings.Status -ne 200) {
    Skipped "أنماط بطاقة المحفظة" "تعذّر قراءة الإعدادات (حالة $($origSettings.Status))"
} else {

$cardCap = 20
$baseSettings = @{
    currencyCode        = $origSettings.Body.currencyCode
    currencySymbol      = $origSettings.Body.currencySymbol
    locale              = $origSettings.Body.locale
    taxRate             = $origSettings.Body.taxRate
    passwordMinLength   = $origSettings.Body.passwordMinLength
    receiptWidthMm      = $origSettings.Body.receiptWidthMm
    posAllowOpenProduct = $origSettings.Body.posAllowOpenProduct
}

$setModes = Api PUT "/organizations/me/settings" -Token $token -Body ($baseSettings + @{
    cardModesAllowed     = "card,pin"
    cardModeDefault      = "pin"
    cardOpenModeDailyCap = $cardCap
})
Check "المدير يضبط مظروف الأنماط" ($setModes.Status -in 200,204) "حالة $($setModes.Status)"

# قائمة أنماط فارغة تعني حساباً لا يُصرَف منه أبداً — تُرفض.
$emptyModes = Api PUT "/organizations/me/settings" -Token $token -Body ($baseSettings + @{
    cardModesAllowed = ""; cardModeDefault = "pin"
})
Check "قائمة أنماط فارغة تُرفض" ($emptyModes.Status -eq 400) "حالة $($emptyModes.Status) — قبولها يترك حسابات لا تُصرَف"

# نمط افتراضي خارج المسموح يُسقِط كل حساب جديد إلى مسار لم يقصده أحد.
$badDefault = Api PUT "/organizations/me/settings" -Token $token -Body ($baseSettings + @{
    cardModesAllowed = "pin"; cardModeDefault = "card"
})
Check "افتراضي خارج المسموح يُرفض" ($badDefault.Status -eq 400) "حالة $($badDefault.Status)"

$cardCustomer = Api POST "/customers" -Token $token -Body @{
    fullName = "زبون بطاقة $stamp"; creditLimit = 0
}

if ($cardCustomer.Status -notin 200,201) {
    Skipped "أنماط بطاقة المحفظة" "تعذّر إنشاء العميل (حالة $($cardCustomer.Status))"
} else {
    $custId = $cardCustomer.Body.id

    # إصدار بطاقة بنمط «بطاقة فقط» بلا رقم سرّي إطلاقاً.
    $issued = Api POST "/wallet-cards/issue" -Token $token -Body @{
        customerId = $custId; cardMode = "card"; pin = $null
    }
    Check "إصدار بطاقة بلا رقم سرّي في نمط «بطاقة فقط»" ($issued.Status -in 200,201) "حالة $($issued.Status) — $($issued.Body.message)"

    # الرقم مع النمط المكشوف يُرفض: سرٌّ لا يستعمله أحد يبقى قابلاً للتسريب.
    $pinInCardMode = Api POST "/wallet-cards/issue" -Token $token -Body @{
        customerId = $custId; cardMode = "card"; pin = "4739"
    }
    Check "رقم سرّي مع نمط «بطاقة فقط» يُرفض" ($pinInCardMode.Status -eq 400) "حالة $($pinInCardMode.Status)"

    # سقف زبون أعلى من سقف المنظمة تجاوزٌ لحدٍّ وضعه صاحب المحل لمخاطرته هو.
    $capTooHigh = Api PUT "/customers/$custId/card-mode" -Token $token -Body @{
        cardMode = "card"; dailyCap = ($cardCap + 500)
    }
    Check "سقف زبون أعلى من سقف المنظمة يُرفض" ($capTooHigh.Status -eq 400) "حالة $($capTooHigh.Status) — قبوله يجعل سقف المنظمة زينة"

    # والأقلّ يُقبل: التشديد على النفس حقٌّ لا يحتاج إذناً.
    $capLower = Api PUT "/customers/$custId/card-mode" -Token $token -Body @{
        cardMode = "card"; dailyCap = 5
    }
    Check "سقف زبون أقلّ يُقبل" ($capLower.Status -in 200,204) "حالة $($capLower.Status)"

    # يُعاد إلى سقف المنظمة قبل اختبار الصرف.
    Api PUT "/customers/$custId/card-mode" -Token $token -Body @{ cardMode = "card"; dailyCap = 0 } | Out-Null

    # شحن المحفظة بما يفوق السقف بكثير — لنقيس السقف لا الرصيد.
    $topUp = Api POST "/customers/$custId/wallet-adjustments" -Token $token -Body @{
        amountDelta = 1000; note = "TEST-$stamp"
    }

    if ($topUp.Status -notin 200,201 -or -not $canManageInventory) {
        Skipped "فرض السقف اليومي" "يتطلّب شحن محفظة وإنشاء صنف (حالة الشحن $($topUp.Status))"
    } else {
        # يتتبّع المخزون: الصنف غير المتتبَّع يُعامَل «مفتوح القيمة» ويحتاج
        # إعداد posAllowOpenProduct — فيفشل البيع لسبب لا علاقة له بالسقف.
        $capProduct = Api POST "/products" -Token $token -Body @{
            sku = "TEST-CAP-$stamp"; name = "صنف اختبار السقف $stamp"
            salePrice = 15; costPrice = 5
            unitBase = "piece"; tracksStock = $true; reorderLevel = 0
        }
        if ($capProduct.Status -in 200,201) {
            Api POST "/products/$($capProduct.Body.id)/stock-adjustments" -Token $token -Body @{
                branchId = $branchId; quantityDelta = 100
            } | Out-Null
        }

        if ($capProduct.Status -notin 200,201) {
            Skipped "فرض السقف اليومي" "تعذّر إنشاء الصنف (حالة $($capProduct.Status))"
        } else {
            $capProductId = $capProduct.Body.id

            # فاتورة أولى بـ15 — تحت السقف (20) فتمرّ، **وبلا رقم سرّي**.
            $sale1 = Api POST "/invoices" -Token $token -Body @{
                branchId = $branchId; customerId = $custId
                paymentMethod = "customer_wallet"
                lines = @(@{ productId = $capProductId; quantity = 1 })
            }
            Check "صرف تحت السقف يمرّ بلا رقم سرّي" ($sale1.Status -in 200,201) "حالة $($sale1.Status) — $($sale1.Body.message)"

            # ثانية بـ15 — المجموع 30 يتجاوز السقف 20، والرصيد وافر (1000).
            # هذا هو الفحص الحقيقي: لولا فرضٍ في السيرفر لمرّت.
            $sale2 = Api POST "/invoices" -Token $token -Body @{
                branchId = $branchId; customerId = $custId
                paymentMethod = "customer_wallet"
                lines = @(@{ productId = $capProductId; quantity = 1 })
            }
            Check "تجاوز السقف اليومي يُرفَض رغم كفاية الرصيد" ($sale2.Status -eq 400) "حالة $($sale2.Status) — مروره يعني أن السقف رقمٌ في الواجهة لا حاجز"
            Check "رسالة الرفض تذكر السقف" ("$($sale2.Body.message)" -like "*السقف*") "الرسالة: $($sale2.Body.message)"
        }
    }
}

# تُعاد الإعدادات كما كانت — الاختبار لا يترك المنظمة بمظروف غير مظروفها.
Api PUT "/organizations/me/settings" -Token $token -Body ($baseSettings + @{
    cardModesAllowed     = $origSettings.Body.cardModesAllowed
    cardModeDefault      = $origSettings.Body.cardModeDefault
    cardOpenModeDailyCap = $origSettings.Body.cardOpenModeDailyCap
}) | Out-Null

}

# -----------------------------------------------------------------------------
Section "٥.٨ بوّابة العميل — حدّ ما يفتحه المسح"

# العطب الذي يمسكه هذا القسم: البوّابة صارت تقبل بطاقةً بلا رقم سرّي — وهو
# عكسُ قرارٍ سابق. والحدّ المتّفق عليه أن المسح وحده يفتح **الرصيد وآخر خمس
# حركات** لا كشف الحساب.
#
# وهذا حدٌّ لا يظهر خرقُه في أي شاشة: من يوسّعه سهواً (بتغيير Take أو نسيان
# تمرير pinVerified) يُنتج بوّابةً «تعمل» وتكشف تاريخ صاحب البطاقة كاملاً
# لمن وجدها. فيُفحَص بالعدد لا بالنظر.

$portalCustomer = Api POST "/customers" -Token $token -Body @{
    fullName = "عميل بوّابة $stamp"
}
if ($portalCustomer.Status -notin 200,201) {
    Skipped "بوّابة العميل" "تعذّر إنشاء العميل (حالة $($portalCustomer.Status))"
} else {
    $portalId = $portalCustomer.Body.id
    $portalCard = Api POST "/wallet-cards/issue" -Token $token -Body @{
        customerId = $portalId; cardMode = "card"; pin = $null
    }

    if ($portalCard.Status -notin 200,201) {
        Skipped "بوّابة العميل" "تعذّر إصدار البطاقة (حالة $($portalCard.Status))"
    } else {
        $portalCode = $portalCard.Body.cardCode

        # ستّ حركات: أكثر من حدّ المسح بواحدة، فيظهر القصّ إن وقع.
        1..6 | ForEach-Object {
            Api POST "/customers/$portalId/wallet-adjustments" -Token $token -Body @{
                amountDelta = 10; note = "TEST-portal-$_"
            } | Out-Null
        }

        # الدخول بالمسح وحده — بلا رقم سرّي إطلاقاً.
        $glance = Api POST "/customer-portal/login" -Body @{ cardCode = $portalCode }
        Check "بطاقة بلا رقم سرّي تدخل البوّابة بالمسح" ($glance.Status -eq 200) `
            "حالة $($glance.Status) — $($glance.Body.message)"

        if ($glance.Status -eq 200) {
            Check "المسح وحده لا يُعدّ تحقّقاً من رقم سرّي" `
                ($glance.Body.pinVerified -eq $false) `
                "pinVerified = $($glance.Body.pinVerified) — صدقُه يفتح الكشف الكامل"

            $count = @($glance.Body.transactions).Count
            Check "المسح يفتح خمس حركات لا أكثر" ($count -le 5) `
                "رجعت $count حركة — الحدّ خمس، وتجاوزه يكشف تاريخ صاحب البطاقة لمن وجدها"

            Check "الرصيد يُعرَض مع ذلك" ($null -ne $glance.Body.balance) `
                "الرصيد غائب — وهو سؤال العميل الحقيقي"
        }

        # رمز مجهول: نفس ردّ الرقم الخاطئ، فلا يُعرَف أيّ رمز مسجَّل فعلاً.
        $unknown = Api POST "/customer-portal/login" -Body @{ cardCode = "TEST-NOPE-$stamp" }
        Check "رمز بطاقة مجهول يُرفض بـ401" ($unknown.Status -eq 401) `
            "حالة $($unknown.Status) — وغيرُ 401 يكشف أيّ الرموز موجود"
    }
}

# -----------------------------------------------------------------------------
Section "٥.٤ الجرد الميداني"

# العطب الذي يمسكه هذا القسم: الجرد الدوري يبدأ بـ counted_quantity =
# system_quantity، ولا حقل كان يميّز السطر الذي عُدَّ وطابق من السطر الذي لم
# يره أحد. فعاملٌ مسح أربعين صنفاً من ثلاثمئة ثم أرسل، يقول له النظام «صفر
# فروقات» — لأن مئتين وستين وافقت نفسها. وهذا أسوأ من غياب الجرد: يمنح ثقةً
# لا سند لها.

if (-not $canManageInventory) {
    Skipped "الجرد الميداني" "يتطلّب inventory.manage و stock_count.manage"
} else {

$fieldProduct = Api POST "/products" -Token $token -Body @{
    sku = "TEST-FIELD-$stamp"; barcode = "TESTBC$stamp"
    name = "صنف الجرد الميداني $stamp"
    salePrice = 8; costPrice = 4
    unitBase = "piece"; tracksStock = $true; reorderLevel = 0
}

$newCount = Api POST "/stock-counts" -Token $token -Body @{ branchId = $branchId }

if ($fieldProduct.Status -notin 200,201 -or $newCount.Status -notin 200,201) {
    Skipped "الجرد الميداني" "تعذّر تجهيز الصنف أو الجرد (صنف $($fieldProduct.Status)، جرد $($newCount.Status))"
} else {
    $countId = $newCount.Body.id
    $totalItems = @($newCount.Body.items).Count

    Check "الجرد الجديد يبدأ وكل سطوره غير معدودة" ($newCount.Body.uncountedCount -eq $totalItems) `
        "بقي $($newCount.Body.uncountedCount) من $totalItems — تساويهما هو ما يمنع «صفر فروقات» الكاذبة"

    # ── المسار الناجح: مسح يجد سطره ──
    $scanFound = Api GET "/stock-counts/$countId/scan/TESTBC$stamp" -Token $token
    Check "مسح الباركود يجد سطر الجرد" ($scanFound.Status -eq 200 -and $scanFound.Body.outcome -eq 'found') `
        "حالة $($scanFound.Status)، النتيجة $($scanFound.Body.outcome)"

    # ── الاستثناء: رمز لا صنف له ──
    $scanUnknown = Api GET "/stock-counts/$countId/scan/LAYUJAD$stamp" -Token $token
    Check "رمز غير معروف يُسمّى صراحةً" ($scanUnknown.Body.outcome -eq 'unknown') `
        "النتيجة $($scanUnknown.Body.outcome) — بلا تسمية يخرج العامل من النظام إلى ورقة"

    # ── إنهاء بلا عدّ: يجب أن يُرفَض ──
    $earlySubmit = Api POST "/stock-counts/$countId/submit" -Token $token -Body @{ force = $false }
    Check "إنهاء العدّ وسطورٌ لم تُمَسّ يُرفَض" ($earlySubmit.Status -eq 400) `
        "حالة $($earlySubmit.Status) — قبوله يُنتج «صفر فروقات» عن رفوف لم يقف أمامها أحد"
    Check "الرفض يذكر كم بقي" ($earlySubmit.Body.uncountedCount -gt 0) `
        "uncountedCount = $($earlySubmit.Body.uncountedCount)"

    # ── العدّ يختم السطر ──
    $itemId = $scanFound.Body.item.id
    $setQty = Api PUT "/stock-counts/$countId/items/$itemId" -Token $token -Body @{ countedQuantity = 7 }
    Check "تسجيل الكمية يمرّ" ($setQty.Status -in 200,204) "حالة $($setQty.Status)"

    # ── الاستثناء: مسح ثانٍ لنفس الصنف لا يُكتب فوقه صامتاً ──
    $scanAgain = Api GET "/stock-counts/$countId/scan/TESTBC$stamp" -Token $token
    Check "مسح صنف عُدَّ من قبل يُنبَّه عليه" ($scanAgain.Body.outcome -eq 'already_counted') `
        "النتيجة $($scanAgain.Body.outcome) — الكتابة الصامتة تخفي صنفاً مُرَّ عليه مرّتين"

    $afterOne = Api GET "/stock-counts/$countId" -Token $token
    Check "عدّاد «كم بقي» ينقص بعد العدّ" ($afterOne.Body.uncountedCount -eq ($totalItems - 1)) `
        "بقي $($afterOne.Body.uncountedCount)، والمتوقّع $($totalItems - 1)"

    # ── الاستثناء: صنف على الرفّ وليس في القائمة ──
    # جرد موزَّع يستبعد ما عُدَّ حديثاً، فيقف العامل أمام صنف لا يجده.
    $future = (Get-Date).AddYears(-50).ToString('yyyy-MM-dd')
    $narrowCount = Api POST "/stock-counts" -Token $token -Body @{
        branchId = $branchId; notCountedSince = $future
    }
    if ($narrowCount.Status -in 200,201) {
        $narrowId = $narrowCount.Body.id
        $scanUnlisted = Api GET "/stock-counts/$narrowId/scan/TESTBC$stamp" -Token $token
        if ($scanUnlisted.Body.outcome -eq 'unlisted') {
            Check "صنف خارج القائمة يُسمّى unlisted" $true ""
            $added = Api POST "/stock-counts/$narrowId/items" -Token $token -Body @{
                productId = $fieldProduct.Body.id
            }
            Check "إضافة صنف وُجد على الرفّ وليس في القائمة" ($added.Status -in 200,201) `
                "حالة $($added.Status) — بلا هذا الطريق يكتب العامل على ورقة"
            Check "المُضاف يبدأ غير معدود" ($null -eq $added.Body.countedAt) `
                "الإضافة تسجيل وجود لا عدّ"
        } else {
            Skipped "صنف خارج القائمة" "الجرد الضيّق ضمّ الصنف (النتيجة $($scanUnlisted.Body.outcome))"
        }
        Api POST "/stock-counts/$narrowId/cancel" -Token $token -Body @{} | Out-Null
    } else {
        Skipped "صنف خارج القائمة" "تعذّر إنشاء جرد موزَّع (حالة $($narrowCount.Status))"
    }

    # ── الإنهاء الصريح رغم النقص ──
    $forced = Api POST "/stock-counts/$countId/submit" -Token $token -Body @{ force = $true }
    Check "الإنهاء الصريح مع النقص يمرّ" ($forced.Status -eq 200) "حالة $($forced.Status)"
}

}

# -----------------------------------------------------------------------------
Section "٥.٥ المحاسبة — الترحيل الآلي"

# السؤال الذي يُجاب هنا: هل يوازن الدفتر بعد بيعٍ ومرتجع فعليّين؟
#
# القيد غير المتوازن يُفسد ميزان المراجعة إلى الأبد: لا يظهر في أي شاشة بيع،
# ولا يُكتشف إلا يوم يُقفل الحساب فلا يُعرف أي قيدٍ من آلاف القيود سببه.

# إصدار المنظمة يُقرأ أولاً: مالك المنصّة يمرّ من حاجز الوحدة بلا فحص،
# فتنجح القراءة وبذرُ الدليل ثم تفشل كل فحوصات الترحيل الآلي بلا سببٍ
# ظاهر — وقد وقع ذلك فعلاً. وقول السبب مرّةً أصدق من أربعة إخفاقات
# متتالية يطاردها من يقرؤها.
$orgEdition = (Api GET "/organizations/me" -Token $token).Body.edition
$chart = Api GET "/accounting/accounts" -Token $token
if ($orgEdition -and $orgEdition -ne 'enterprise') {
    Skipped "المحاسبة" "إصدار المنظمة «$orgEdition» لا «enterprise» — الترحيل الآلي معطَّل بحكم التصميم"
} elseif ($chart.Status -eq 403) {
    Skipped "المحاسبة" "وحدة accounting غير مفعّلة لهذه المنظمة (إصدار المؤسسات وحده)"
} elseif ($chart.Status -ne 200) {
    Skipped "المحاسبة" "تعذّرت قراءة دليل الحسابات (حالة $($chart.Status))"
} else {

if (@($chart.Body).Count -eq 0) {
    $seed = Api POST "/accounting/accounts/seed" -Token $token -Body @{}
    Check "بذر دليل الحسابات الافتراضي" ($seed.Status -eq 200) "حالة $($seed.Status)"
    $chart = Api GET "/accounting/accounts" -Token $token
}

$accounts = @($chart.Body)
Check "الدليل يحوي الأقسام الأربعة" (
    ($accounts | Where-Object { $_.code -eq '1' }) -and
    ($accounts | Where-Object { $_.code -eq '2' }) -and
    ($accounts | Where-Object { $_.code -eq '3' }) -and
    ($accounts | Where-Object { $_.code -eq '4' })
) "الأصول والالتزامات والاستخدامات والإيرادات"

# الوسيط لا يُرحَّل إليه: قيدٌ على «الأصول» مباشرةً يكسر تساوي الأب بمجموع أبنائه.
$root = $accounts | Where-Object { $_.code -eq '1' } | Select-Object -First 1
Check "الحساب الجذر غير قابل للترحيل" ($root.isPostable -eq $false) `
    "قيدٌ على «الأصول» مباشرةً يجعل رصيد الأب لا يساوي مجموع أبنائه"

# البذر آمن للتكرار — لا يمحو دليلاً عدّله محاسب.
$reseed = Api POST "/accounting/accounts/seed" -Token $token -Body @{}
Check "إعادة البذر لا تمحو الدليل" ($reseed.Status -eq 200 -and $reseed.Body.seeded -eq $false) `
    "seeded = $($reseed.Body.seeded)"

# ── بيع فعليّ ثم قراءة الميزان ────────────────────────────────────────────
if (-not $canManageInventory) {
    Skipped "ترحيل الفاتورة" "يتطلّب إنشاء صنف"
} else {
    $accProduct = Api POST "/products" -Token $token -Body @{
        sku = "TEST-ACC-$stamp"; name = "صنف محاسبة $stamp"
        salePrice = 30; costPrice = 12
        unitBase = "piece"; tracksStock = $true; reorderLevel = 0
    }
    if ($accProduct.Status -in 200,201) {
        Api POST "/products/$($accProduct.Body.id)/stock-adjustments" -Token $token -Body @{
            branchId = $branchId; quantityDelta = 100
        } | Out-Null
    }

    if ($accProduct.Status -notin 200,201) {
        Skipped "ترحيل الفاتورة" "تعذّر إنشاء الصنف (حالة $($accProduct.Status))"
    } else {
        $before = Api GET "/accounting/journal" -Token $token
        $countBefore = @($before.Body).Count

        $accSale = Api POST "/invoices" -Token $token -Body @{
            branchId = $branchId; paymentMethod = "cash"
            lines = @(@{ productId = $accProduct.Body.id; quantity = 2 })
        }
        Check "البيع يمرّ مع تفعيل المحاسبة" ($accSale.Status -in 200,201) `
            "حالة $($accSale.Status) — $($accSale.Body.message)"

        if ($accSale.Status -in 200,201) {
            $after = Api GET "/accounting/journal" -Token $token
            Check "الفاتورة ولّدت قيداً آلياً" (@($after.Body).Count -gt $countBefore) `
                "قبل $countBefore وبعد $(@($after.Body).Count)"

            $saleEntry = @($after.Body) | Where-Object { $_.sourceId -eq $accSale.Body.id } | Select-Object -First 1
            if ($saleEntry) {
                $d = ($saleEntry.lines | Measure-Object -Property debit -Sum).Sum
                $c = ($saleEntry.lines | Measure-Object -Property credit -Sum).Sum
                Check "قيد الفاتورة متوازن" ([Math]::Abs($d - $c) -lt 0.01) "مدين $d ودائن $c"
            } else {
                Check "قيد الفاتورة موجود" $false "لم يُعثر على قيدٍ بمصدر الفاتورة"
            }

            # ── المرتجع ───────────────────────────────────────────────────
            $accRefund = Api POST "/invoices/$($accSale.Body.id)/refund" -Token $token -Body @{}
            Check "المرتجع يمرّ مع تفعيل المحاسبة" ($accRefund.Status -in 200,201) `
                "حالة $($accRefund.Status) — $($accRefund.Body.message)"

            if ($accRefund.Status -in 200,201) {
                $afterRefund = Api GET "/accounting/journal" -Token $token
                # المرتجع يكتب قيدين: إثبات الردّ ثم عودة التكلفة. والدفتر
                # يُرتَّب تنازلياً، فأحدثهما هو قيد التكلفة — والمقصود هنا
                # قيد الإيراد. يُلتقط بأنه الذي يمسّ «مردودات المبيعات».
                $returnEntries = @($afterRefund.Body) | Where-Object { $_.source -eq 'invoice_return' }
                $retEntry = $returnEntries | Where-Object {
                    $_.lines | Where-Object { $_.accountCode -eq '4102' }
                } | Select-Object -First 1
                if (-not $retEntry) { $retEntry = $returnEntries | Select-Object -First 1 }
                Check "المرتجع ولّد قيداً آلياً" ($null -ne $retEntry) `
                    "مرتجعٌ بلا قيد يترك المبيعات مضخّمة بما رُدّ"

                if ($retEntry) {
                    $rd = ($retEntry.lines | Measure-Object -Property debit -Sum).Sum
                    $rc = ($retEntry.lines | Measure-Object -Property credit -Sum).Sum
                    Check "قيد المرتجع متوازن" ([Math]::Abs($rd - $rc) -lt 0.01) "مدين $rd ودائن $rc"

                    # مردودات المبيعات حسابٌ مستقلّ لا خصمٌ من المبيعات: الخصم
                    # يُخفي حجم المرتجع تماماً.
                    $usesReturns = $retEntry.lines | Where-Object { $_.accountCode -eq '4102' }
                    Check "المرتجع يُرحَّل إلى «مردودات المبيعات» لا إلى «المبيعات»" `
                        ($null -ne $usesReturns) "الخصم من المبيعات يُخفي حجم المرتجع"
                }
            }
        }
    }
}

# ── المشتريات: الاستلام والمردود ─────────────────────────────────────────
#
# الفجوة التي يمسكها: الاستلام كان يزيد المخزون في دفتر المخزون بلا أي مقابل
# في الدفتر المحاسبي — أي أن الميزان يعرف ما بيع ولا يعرف من أين جاءت
# البضاعة ولا كم تدين للموردين.

if ($canManageInventory -and $accProduct -and $accProduct.Status -in 200,201) {
    $po = Api POST "/purchase-orders" -Token $token -Body @{
        branchId = $branchId
        lines = @(@{ productId = $accProduct.Body.id; quantity = 10; unitCost = 12 })
    }
    if ($po.Status -in 200,201) {
        Api POST "/purchase-orders/$($po.Body.id)/order" -Token $token -Body @{} | Out-Null
        $recv = Api POST "/purchase-orders/$($po.Body.id)/receive" -Token $token -Body @{
            lines = @(@{ productId = $accProduct.Body.id; quantity = 10 })
        }
        Check "استلام البضاعة يمرّ" ($recv.Status -in 200,204) "حالة $($recv.Status) — $($recv.Body.message)"

        $j = Api GET "/accounting/journal" -Token $token
        $recvEntry = @($j.Body) | Where-Object { $_.source -eq 'purchase_receipt' } | Select-Object -First 1
        Check "الاستلام ولّد قيداً آلياً" ($null -ne $recvEntry) `
            "بلا قيد يزيد المخزون الدفتري بلا مقابل في الموردين"
        if ($recvEntry) {
            $usesPayables = $recvEntry.lines | Where-Object { $_.accountCode -eq '2101' -and $_.credit -gt 0 }
            Check "الاستلام يُقيَّد على «الموردون» لا «الصندوق»" ($null -ne $usesPayables) `
                "قيدُه على الصندوق يفترض أن كل شحنة دُفعت نقداً لحظة وصولها"
        }

        # ── مردود الشراء ──
        $pret = Api POST "/purchase-orders/$($po.Body.id)/return-to-supplier" -Token $token -Body @{
            reason = "بضاعة تالفة"
            lines = @(@{ productId = $accProduct.Body.id; batchNumber = ""; quantity = 3 })
        }
        Check "مردود الشراء يمرّ" ($pret.Status -in 200,204) "حالة $($pret.Status) — $($pret.Body.message)"

        # السبب إلزامي: بضاعة تخرج بلا سبب مكتوب هي أوسع باب لإخفاء نقص.
        $noReason = Api POST "/purchase-orders/$($po.Body.id)/return-to-supplier" -Token $token -Body @{
            reason = ""; lines = @(@{ productId = $accProduct.Body.id; batchNumber = ""; quantity = 1 })
        }
        Check "مردود بلا سبب يُرفض" ($noReason.Status -eq 400) "حالة $($noReason.Status)"

        # لا يُعاد أكثر ممّا استُلم.
        $tooMuch = Api POST "/purchase-orders/$($po.Body.id)/return-to-supplier" -Token $token -Body @{
            reason = "اختبار"; lines = @(@{ productId = $accProduct.Body.id; batchNumber = ""; quantity = 999 })
        }
        Check "إرجاع أكثر من المستلَم يُرفض" ($tooMuch.Status -eq 400) "حالة $($tooMuch.Status)"
    } else {
        Skipped "ترحيل المشتريات" "تعذّر إنشاء أمر شراء (حالة $($po.Status))"
    }
}

# ── سداد الموردين ────────────────────────────────────────────────────────
#
# الثقب: حساب «الموردون» كان يتراكم بلا طرف مقابل — كل استلام يزيد الدَّين
# ولا شيء يُنقصه. فالميزان يقول إنك مدينٌ بكل ما اشتريتَه منذ أول يوم، ولو
# سدّدتَ كلّه نقداً.

$sup = Api POST "/suppliers" -Token $token -Body @{ name = "مورّد الفحص $stamp"; balance = 100 }
if ($sup.Status -notin 200,201) {
    Skipped "سداد الموردين" "تعذّر إنشاء المورّد (حالة $($sup.Status))"
} else {
    $supId = $sup.Body.id

    $st0 = Api GET "/suppliers/$supId/statement" -Token $token
    Check "كشف حساب المورّد يُقرأ" ($st0.Status -eq 200) "حالة $($st0.Status)"
    Check "الرصيد الافتتاحي يُقرأ كما أُدخل" ([decimal]$st0.Body.openingBalance -eq 100) `
        "المعروض $($st0.Body.openingBalance) — الرقم المُدخَل يدوياً رصيدٌ افتتاحي لا رصيد حالي"

    $pay = Api POST "/suppliers/$supId/payments" -Token $token -Body @{
        branchId = $branchId; amount = 40; method = "cash"; reference = "REC-$stamp"
    }
    Check "تسجيل سداد لمورّد" ($pay.Status -in 200,201) "حالة $($pay.Status) — $($pay.Body.message)"

    $bad = Api POST "/suppliers/$supId/payments" -Token $token -Body @{
        branchId = $branchId; amount = 0; method = "cash"
    }
    Check "سداد بصفر يُرفض" ($bad.Status -eq 400) "حالة $($bad.Status)"

    $st1 = Api GET "/suppliers/$supId/statement" -Token $token
    Check "الرصيد يُشتقّ ويَنقص بالسداد" ([decimal]$st1.Body.walletBalance -eq 60) `
        "المعروض $($st1.Body.walletBalance) والمتوقَّع 60 (افتتاحي 100 − سداد 40)"
    Check "الدفعة تظهر في الكشف" (@($st1.Body.payments).Count -eq 1) `
        "عدد الدفعات $(@($st1.Body.payments).Count)"

    # القيد: من ح/ الموردون إلى ح/ الصندوق.
    $jp = Api GET "/accounting/journal" -Token $token
    if ($jp.Status -eq 200) {
        $payEntry = @($jp.Body) | Where-Object { $_.source -eq 'payment' } | Select-Object -First 1
        Check "السداد ولّد قيداً آلياً" ($null -ne $payEntry) `
            "سدادٌ بلا قيد يترك «الموردون» متراكماً بلا طرف مقابل"
        if ($payEntry) {
            $d = ($payEntry.lines | Measure-Object -Property debit -Sum).Sum
            $c = ($payEntry.lines | Measure-Object -Property credit -Sum).Sum
            Check "قيد السداد متوازن" ([Math]::Abs($d - $c) -lt 0.01) "مدين $d ودائن $c"
            $hitsPayables = $payEntry.lines | Where-Object { $_.accountCode -eq '2101' -and $_.debit -gt 0 }
            Check "السداد يُنقص «الموردون» بالمدين" ($null -ne $hitsPayables) `
                "بلا ذلك يبقى الدَّين كما هو في الميزان"
        }
    }
}

# ── قائمة الدخل والميزانية ───────────────────────────────────────────────
#
# السؤال الحاسم: هل تتوازن الميزانية بعد دورة كاملة — شراء واستلام وسداد
# وبيع ومرتجع ومصروف؟ الأصول يجب أن تساوي الالتزامات + حقوق الملكية +
# نتيجة الفترة. واختلالها يعني قيداً دخل من خارج النظام.

$inc = Api GET "/accounting/income-statement" -Token $token
Check "قائمة الدخل تُقرأ" ($inc.Status -eq 200) "حالة $($inc.Status)"
if ($inc.Status -eq 200) {
    $r = [decimal]$inc.Body.totalRevenue
    $e = [decimal]$inc.Body.totalExpense
    $n = [decimal]$inc.Body.netIncome
    Check "صافي الدخل = الإيرادات − الاستخدامات" ([Math]::Abs(($r - $e) - $n) -lt 0.01) `
        "إيراد $r واستخدام $e وصافٍ $n"

    # مردودات المبيعات حسابٌ من نوع الإيراد برصيد مدين، فيُنقص الإيراد
    # تلقائياً بلا طرح يدوي.
    $ret = @($inc.Body.revenues) | Where-Object { $_.code -eq '4102' }
    if ($ret) {
        Check "المرتجع يُنقص الإيراد لا يُضاف إليه" ([decimal]$ret.amount -le 0) `
            "المعروض $($ret.amount) — الموجب يعني أن المرتجع يُقرأ إيراداً"
    }
}

$bs = Api GET "/accounting/balance-sheet" -Token $token
Check "الميزانية تُقرأ" ($bs.Status -eq 200) "حالة $($bs.Status)"
if ($bs.Status -eq 200) {
    Check "الميزانية متوازنة" ([Math]::Abs([decimal]$bs.Body.difference) -lt 0.01) `
        "الفرق $($bs.Body.difference) — الأصول $($bs.Body.totalAssets) مقابل التزامات $($bs.Body.totalLiabilities) وملكية $($bs.Body.totalEquity) ونتيجة $($bs.Body.retainedResult)"

    # النتيجة الجارية تُعرَض صراحةً لا تُخفى في الفرق: الإقفال السنوي غير
    # مبنيّ، فأرباح المدّة تبقى في حسابات الإيراد والاستخدام. ولولا إضافتها
    # لما توازنت الميزانية أبداً.
    if ($inc.Status -eq 200) {
        Check "نتيجة الميزانية توافق قائمة الدخل" `
            ([Math]::Abs([decimal]$bs.Body.retainedResult - [decimal]$inc.Body.netIncome) -lt 0.01) `
            "الميزانية $($bs.Body.retainedResult) والقائمة $($inc.Body.netIncome) — اختلافهما يعني مصدرَي حقيقة"
    }
}

# ── القيود اليدوية ───────────────────────────────────────────────────────
#
# الدفتر يعرف البيع والشراء والمصروف والسداد، ولا يعرف إهلاكاً ولا مخصّصاً
# ولا تصحيح تبويب. وبلا هذا الباب يخرج المحاسب إلى ملفٍ جانبي — فيصير
# الدفتر ناقصاً وهو يبدو كاملاً.
#
# والسؤال: هل يمرّ اليدوي بكل حرّاس الدفتر، أم يلتفّ عليها؟

$chartNow = Api GET "/accounting/accounts" -Token $token
$postable = @($chartNow.Body) | Where-Object { $_.isPostable -eq $true }
$cashAcc = $postable | Where-Object { $_.code -eq '1101' } | Select-Object -First 1
$genExp  = $postable | Where-Object { $_.code -eq '3201' } | Select-Object -First 1
$rootAcc = @($chartNow.Body) | Where-Object { $_.code -eq '1' } | Select-Object -First 1

if (-not $cashAcc -or -not $genExp) {
    Skipped "القيود اليدوية" "لم يُعثر على حسابَي الصندوق والمصروفات العمومية"
} else {
    # الوصف إلزامي: قيدٌ بلا شرح يترك من يراجعه بعد سنة أمام أرقام لا يعرف
    # لماذا كُتبت.
    $noDesc = Api POST "/accounting/journal" -Token $token -Body @{
        entryDate = [DateTime]::UtcNow.Date.ToString('yyyy-MM-dd'); description = ""
        lines = @(
            @{ accountId = $genExp.id; debit = 50; credit = 0 },
            @{ accountId = $cashAcc.id; debit = 0; credit = 50 }
        )
    }
    Check "قيد يدوي بلا وصف يُرفض" ($noDesc.Status -eq 400) "حالة $($noDesc.Status)"

    # غير المتوازن: هو ما يُفسد ميزان المراجعة إلى الأبد.
    $unbalanced = Api POST "/accounting/journal" -Token $token -Body @{
        entryDate = [DateTime]::UtcNow.Date.ToString('yyyy-MM-dd'); description = "غير متوازن"
        lines = @(
            @{ accountId = $genExp.id; debit = 50; credit = 0 },
            @{ accountId = $cashAcc.id; debit = 0; credit = 30 }
        )
    }
    Check "قيد يدوي غير متوازن يُرفض" ($unbalanced.Status -eq 400) `
        "حالة $($unbalanced.Status) — قبولُه يُفسد ميزان المراجعة إلى الأبد"

    # سطرٌ واحد ليس قيداً.
    $single = Api POST "/accounting/journal" -Token $token -Body @{
        entryDate = [DateTime]::UtcNow.Date.ToString('yyyy-MM-dd'); description = "سطر واحد"
        lines = @(@{ accountId = $genExp.id; debit = 50; credit = 0 })
    }
    Check "قيد بسطر واحد يُرفض" ($single.Status -eq 400) "حالة $($single.Status)"

    # الحساب التجميعي: رصيدُه يجب أن يبقى مجموع أبنائه.
    if ($rootAcc) {
        $onRoot = Api POST "/accounting/journal" -Token $token -Body @{
            entryDate = [DateTime]::UtcNow.Date.ToString('yyyy-MM-dd'); description = "على تجميعي"
            lines = @(
                @{ accountId = $rootAcc.id; debit = 50; credit = 0 },
                @{ accountId = $cashAcc.id; debit = 0; credit = 50 }
            )
        }
        Check "الترحيل إلى حساب تجميعي يُرفض" ($onRoot.Status -eq 400) `
            "حالة $($onRoot.Status) — قبولُه يجعل رصيد الأب لا يساوي مجموع أبنائه"
    }

    # والقيد السليم يمرّ ويظهر في الدفتر.
    $ok = Api POST "/accounting/journal" -Token $token -Body @{
        entryDate = [DateTime]::UtcNow.Date.ToString('yyyy-MM-dd')
        description = "تسوية يدوية $stamp"
        lines = @(
            @{ accountId = $genExp.id; debit = 50; credit = 0 },
            @{ accountId = $cashAcc.id; debit = 0; credit = 50 }
        )
    }
    Check "القيد اليدوي السليم يمرّ" ($ok.Status -in 200,201) `
        "حالة $($ok.Status) — $($ok.Body.message)"

    if ($ok.Status -in 200,201) {
        Check "مصدره manual" ($ok.Body.source -eq 'manual') "المصدر $($ok.Body.source)"
        Check "له رقم في تسلسل الدفتر" ([int]$ok.Body.number -gt 0) "الرقم $($ok.Body.number)"

        $tbAfter = Api GET "/accounting/trial-balance" -Token $token
        Check "الميزان يبقى متوازناً بعد القيد اليدوي" `
            ([Math]::Abs([decimal]$tbAfter.Body.totalDebit - [decimal]$tbAfter.Body.totalCredit) -lt 0.01) `
            "مدين $($tbAfter.Body.totalDebit) ودائن $($tbAfter.Body.totalCredit)"
    }
}

# ── الإقفال السنوي ───────────────────────────────────────────────────────
#
# الإقفال شيئان لا واحد: قيدٌ يُصفّر الإيرادات والاستخدامات ويُرحّل نتيجتها
# إلى «الأرباح المحتجزة»، **وقفلٌ يمنع أي قيد بتاريخ داخل المدّة**. وبلا
# القفل لا معنى للإقفال: فاتورةٌ بتاريخ العام الماضي تُغيّر أرقاماً صدرت عنها
# تقارير ووُقّعت عليها ميزانية.

# بتوقيت UTC كالخادم: حسابُه بالتوقيت المحلّي يجعل الفحص يفشل في الساعات
# التي يختلف فيها اليومان — ويبدو الفشل عطباً في المنتج وهو فرق توقيت.
$closeDate = [DateTime]::UtcNow.Date.AddDays(-1).ToString('yyyy-MM-dd')

# مدّة لم تنتهِ لا تُقفَل — إقفال اليوم يمنع بيع اليوم نفسه.
$future = Api POST "/accounting/closings" -Token $token -Body @{
    periodEnd = [DateTime]::UtcNow.Date.AddDays(5).ToString('yyyy-MM-dd')
}
Check "إقفال مدّة لم تنتهِ يُرفض" ($future.Status -eq 400) "حالة $($future.Status)"

# مصروفٌ بتاريخ داخل المدّة — بلا حركةٍ فيها لا شيء يُقفَل.
# وهو أيضاً إثباتٌ لـExpense.SpentOn: كان المصروف يُقيَّد بتاريخ إدخاله
# دائماً، ففاتورة الأسبوع الماضي تقع في أرقام اليوم.
$past = Api POST "/expenses" -Token $token -Body @{
    branchId = $branchId; category = "مصروف مدّة سابقة"; amount = 25
    spentOn = $closeDate
}
Check "مصروف بتاريخ سابق يُقبَل" ($past.Status -in 200,201) `
    "حالة $($past.Status) — بلا تاريخ صرف مستقلّ تقع فاتورة الأسبوع الماضي في أرقام اليوم"
if ($past.Status -in 200,201) {
    Check "تاريخ الصرف محفوظ كما أُدخل" ("$($past.Body.spentOn)" -like "$closeDate*") `
        "المحفوظ $($past.Body.spentOn) والمُدخَل $closeDate"
}

# على المدّة المُقفَلة نفسها لا على السنة كلّها: القائمة الافتراضية تشمل
# اليوم أيضاً، والإقفال يقف عند $closeDate — فمقارنتهما تقارن مدّتين.
$incBefore = Api GET "/accounting/income-statement?to=$closeDate" -Token $token
$netBefore = if ($incBefore.Status -eq 200) { [decimal]$incBefore.Body.netIncome } else { 0 }

$close = Api POST "/accounting/closings" -Token $token -Body @{ periodEnd = $closeDate }
Check "إقفال المدّة يمرّ" ($close.Status -in 200,201) "حالة $($close.Status) — $($close.Body.message)"

if ($close.Status -in 200,201) {
    Check "نتيجة الإقفال توافق قائمة الدخل" `
        ([Math]::Abs([decimal]$close.Body.netResult - $netBefore) -lt 0.01) `
        "الإقفال $($close.Body.netResult) والقائمة $netBefore"

    # القفل: لا قيد بتاريخ داخل المدّة المُقفَلة.
    $inClosed = Api POST "/expenses" -Token $token -Body @{
        branchId = $branchId; category = "مصروف داخل مدّة مُقفَلة"; amount = 10
        spentOn = $closeDate
    }
    Check "قيدٌ بتاريخ داخل المدّة المُقفَلة يُرفَض" ($inClosed.Status -eq 400) `
        "حالة $($inClosed.Status) — قبولُه يعني أن الإقفال بلا قفل، فتتغيّر أرقامٌ صدرت عنها تقارير"

    # وقفلُ الماضي يجب ألّا يمنع عمل اليوم.
    $today = Api POST "/expenses" -Token $token -Body @{
        branchId = $branchId; category = "مصروف اليوم"; amount = 10
    }
    Check "المصروف بتاريخ اليوم يمرّ رغم الإقفال" ($today.Status -in 200,201) `
        "حالة $($today.Status) — $($today.Body.message)"

    # إقفال المدّة نفسها مرّتين.
    $again = Api POST "/accounting/closings" -Token $token -Body @{ periodEnd = $closeDate }
    Check "إقفال مدّة مُقفَلة يُرفض" ($again.Status -eq 400) "حالة $($again.Status)"

    # الإيرادات والاستخدامات صفرت — قائمة الدخل بعد الإقفال لا ترى ما أُقفل.
    $sheet = Api GET "/accounting/balance-sheet" -Token $token
    Check "الميزانية تبقى متوازنة بعد الإقفال" `
        ([Math]::Abs([decimal]$sheet.Body.difference) -lt 0.01) `
        "الفرق $($sheet.Body.difference) — اختلالها بعد الإقفال يعني قيد إقفال غير متوازن"

    $list = Api GET "/accounting/closings" -Token $token
    Check "الإقفال يظهر في القائمة" (@($list.Body).Count -ge 1) "العدد $(@($list.Body).Count)"

    # الفتح بقرار صريح مسجَّل.
    $noReason = Api POST "/accounting/closings/$($close.Body.id)/reopen" -Token $token -Body @{ reason = "" }
    Check "فتح بلا سبب يُرفض" ($noReason.Status -eq 400) "حالة $($noReason.Status)"

    $reopen = Api POST "/accounting/closings/$($close.Body.id)/reopen" -Token $token -Body @{
        reason = "تصحيح فاتورة"
    }
    Check "فتح الإقفال بسبب مكتوب يمرّ" ($reopen.Status -in 200,204) `
        "حالة $($reopen.Status) — $($reopen.Body.message)"

    if ($reopen.Status -in 200,204) {
        $after = Api GET "/accounting/closings" -Token $token
        $row = @($after.Body) | Where-Object { $_.id -eq $close.Body.id } | Select-Object -First 1
        Check "الصفّ يبقى موسوماً بأنه فُتح" ($row -and $row.isReopened -eq $true) `
            "حذفُه يجعل السنة تبدو كأنها لم تُقفَل قطّ"
        Check "سبب الفتح محفوظ" ("$($row.reopenReason)" -like "*تصحيح*") "السبب: $($row.reopenReason)"

        $sheet2 = Api GET "/accounting/balance-sheet" -Token $token
        Check "الميزانية تبقى متوازنة بعد الفتح" `
            ([Math]::Abs([decimal]$sheet2.Body.difference) -lt 0.01) `
            "الفرق $($sheet2.Body.difference) — عكس قيد الإقفال يجب أن يُعيد الأرصدة كما كانت"
    }
}

# ── ميزان المراجعة ───────────────────────────────────────────────────────
$tb = Api GET "/accounting/trial-balance" -Token $token
Check "ميزان المراجعة يُقرأ" ($tb.Status -eq 200) "حالة $($tb.Status)"
if ($tb.Status -eq 200) {
    Check "ميزان المراجعة متوازن" `
        ([Math]::Abs([double]$tb.Body.totalDebit - [double]$tb.Body.totalCredit) -lt 0.01) `
        "مدين $($tb.Body.totalDebit) ودائن $($tb.Body.totalCredit) — الاختلال يعني قيداً دخل من خارج النظام"
}

}

# -----------------------------------------------------------------------------
Section "٣.١ الحدّ الأدنى لسعر البيع"

# العطب الذي يمسكه هذا القسم: صلاحية pos.price_override تسمح بأي سعر، ولا
# شيء كان يمنع البيع **تحت التكلفة**. ومدير المنظمة يملك الصلاحية دائماً،
# فالحماية بالصلاحية وحدها لا تحمي شيئاً.
#
# والحدّ مطلق: يُختبَر هنا بحسابٍ يملك تجاوز السعر — فإن مرّ البيع تحته كان
# الحدّ زينة.

if (-not $canManageInventory) {
    Skipped "الحدّ الأدنى للسعر" "يتطلّب إنشاء صنف"
} else {
    $floorProduct = Api POST "/products" -Token $token -Body @{
        sku = "TEST-FLOOR-$stamp"; name = "صنف حدّ أدنى $stamp"
        salePrice = 100; costPrice = 60; minSalePrice = 70
        unitBase = "piece"; tracksStock = $true; reorderLevel = 0
    }
    Check "صنف بحدٍّ أدنى أُنشئ" ($floorProduct.Status -in 200,201) "حالة $($floorProduct.Status)"

    if ($floorProduct.Status -in 200,201) {
        Api POST "/products/$($floorProduct.Body.id)/stock-adjustments" -Token $token -Body @{
            branchId = $branchId; quantityDelta = 50
        } | Out-Null

        # البيع بالسعر المعلَن يمرّ.
        $okSale = Api POST "/invoices" -Token $token -Body @{
            branchId = $branchId; paymentMethod = "cash"
            lines = @(@{ productId = $floorProduct.Body.id; quantity = 1 })
        }
        Check "البيع بسعر الكتالوج يمرّ" ($okSale.Status -in 200,201) `
            "حالة $($okSale.Status) — $($okSale.Body.message)"

        # وفوق الحدّ يمرّ.
        $aboveFloor = Api POST "/invoices" -Token $token -Body @{
            branchId = $branchId; paymentMethod = "cash"
            lines = @(@{ productId = $floorProduct.Body.id; quantity = 1; unitPrice = 80 })
        }
        Check "خصمٌ يبقى فوق الحدّ يمرّ" ($aboveFloor.Status -in 200,201) `
            "حالة $($aboveFloor.Status) — $($aboveFloor.Body.message)"

        # وتحته يُرفض — ولو كان الحساب يملك تجاوز السعر.
        $belowFloor = Api POST "/invoices" -Token $token -Body @{
            branchId = $branchId; paymentMethod = "cash"
            lines = @(@{ productId = $floorProduct.Body.id; quantity = 1; unitPrice = 65 })
        }
        Check "البيع تحت الحدّ مرفوض" ($belowFloor.Status -eq 400) `
            "حالة $($belowFloor.Status) — قبولها تعني أن الحدّ زينة"
        Check "الرسالة تُسمّي الحدّ" ($belowFloor.Body.message -match '70') `
            "«$($belowFloor.Body.message)» — بلا الرقم يجرّب الكاشير أرقاماً أمام زبون"

        # وتحت التكلفة يُرفض من باب أولى.
        $belowCost = Api POST "/invoices" -Token $token -Body @{
            branchId = $branchId; paymentMethod = "cash"
            lines = @(@{ productId = $floorProduct.Body.id; quantity = 1; unitPrice = 10 })
        }
        Check "البيع تحت التكلفة مرفوض" ($belowCost.Status -eq 400) "حالة $($belowCost.Status)"

        # صنفٌ بلا حدّ (صفر) يبقى حرّاً — الحدّ ميزة اختيارية لا قيدٌ مفروض.
        $freeProduct = Api POST "/products" -Token $token -Body @{
            sku = "TEST-NOFLOOR-$stamp"; name = "صنف بلا حدّ $stamp"
            salePrice = 100; costPrice = 60; minSalePrice = 0
            unitBase = "piece"; tracksStock = $true; reorderLevel = 0
        }
        if ($freeProduct.Status -in 200,201) {
            Api POST "/products/$($freeProduct.Body.id)/stock-adjustments" -Token $token -Body @{
                branchId = $branchId; quantityDelta = 20
            } | Out-Null
            $cheap = Api POST "/invoices" -Token $token -Body @{
                branchId = $branchId; paymentMethod = "cash"
                lines = @(@{ productId = $freeProduct.Body.id; quantity = 1; unitPrice = 5 })
            }
            Check "صنف بحدٍّ صفر يبقى حرّاً" ($cheap.Status -in 200,201) `
                "حالة $($cheap.Status) — الحدّ اختياري لا مفروض"
        }
    }
}

# -----------------------------------------------------------------------------
Section "٥.٦ فاتورة المورّد ومطابقتها بالاستلام"

# العطب الذي يمسكه هذا القسم: الدَّين للمورّد كان يُنشَأ من ورقة أمين المخزن
# بتكلفة أمر الشراء — أي بالسعر المتّفق عليه لا بالسعر المُطالَب به. فإن رفع
# المورّد سعره لم يكن ثمّة موضعٌ يُظهر الفرق: يُدفَع ما تقوله ورقته ويبقى
# الميزان يقول رقماً آخر إلى الأبد.
#
# ويُختبَر الطريق كاملاً: أمر شراء ← استلام ← فاتورة بسعرٍ أعلى ← ترحيل.

$siChart = Api GET "/accounting/accounts" -Token $token
if ($siChart.Status -ne 200) {
    Skipped "فاتورة المورّد" "وحدة accounting غير مفعّلة (حالة $($siChart.Status))"
} elseif (-not $canManageInventory) {
    Skipped "فاتورة المورّد" "يتطلّب إنشاء صنف ومورّد"
} else {

$siSupplier = Api POST "/suppliers" -Token $token -Body @{
    name = "مورّد فاتورة $stamp"
}
$siProduct = Api POST "/products" -Token $token -Body @{
    sku = "TEST-SI-$stamp"; name = "صنف فاتورة مورّد $stamp"
    salePrice = 50; costPrice = 20
    unitBase = "piece"; tracksStock = $true; reorderLevel = 0
}

if ($siSupplier.Status -notin 200,201 -or $siProduct.Status -notin 200,201) {
    Skipped "فاتورة المورّد" "تعذّر تجهيز المورّد أو الصنف"
} else {
    # lines لا items، والمسار /receive لا /receipts — راجع
    # CreatePurchaseOrderRequest و ReceivePurchaseOrderRequest.
    $siOrder = Api POST "/purchase-orders" -Token $token -Body @{
        branchId = $branchId; supplierId = $siSupplier.Body.id
        lines = @(@{ productId = $siProduct.Body.id; quantity = 10; unitCost = 20 })
    }
    Check "أمر شراء أُنشئ" ($siOrder.Status -in 200,201) `
        "حالة $($siOrder.Status) — $($siOrder.Body.message)"

    if ($siOrder.Status -in 200,201) {
        # الأمر يُعتمَد قبل أن يُستلَم: مسوّدة لا تُستلَم بحكم التصميم.
        $ordered = Api POST "/purchase-orders/$($siOrder.Body.id)/order" -Token $token -Body @{}
        Check "أمر الشراء اعتُمد" ($ordered.Status -in 200,204) "حالة $($ordered.Status)"

        $siReceipt = Api POST "/purchase-orders/$($siOrder.Body.id)/receive" -Token $token -Body @{
            supplierNoteNumber = "SN-$stamp"
            receivedOn = (Get-Date).ToString('yyyy-MM-dd')
            lines = @(@{ productId = $siProduct.Body.id; quantity = 10 })
        }
        Check "الاستلام سُجّل" ($siReceipt.Status -in 200,201,204) `
            "حالة $($siReceipt.Status) — $($siReceipt.Body.message)"

        # ── ما لم يُفوتر بعد ────────────────────────────────────────────────
        $uninvoiced = Api GET "/supplier-invoices/uninvoiced?supplierId=$($siSupplier.Body.id)" -Token $token
        Check "الوارد غير المُفوتر يُقرأ" ($uninvoiced.Status -eq 200) "حالة $($uninvoiced.Status)"

        $line = @($uninvoiced.Body) | Select-Object -First 1
        if (-not $line) {
            Skipped "مطابقة الفاتورة" "لا سطر استلام غير مُفوتر — تحقّق من تسجيل الاستلام"
        } else {
            Check "سطر الاستلام يحمل ما وصل" ([double]$line.quantity -eq 10 -and [double]$line.unitCost -eq 20) `
                "كمية $($line.quantity) بسعر $($line.unitCost)"

            # ── فاتورة بسعرٍ أعلى: 10 × 22 = 220 مقابل 200 وصلت ─────────────
            $siInvoice = Api POST "/supplier-invoices" -Token $token -Body @{
                branchId = $branchId; supplierId = $siSupplier.Body.id
                invoiceNumber = "INV-$stamp"
                invoiceDate = (Get-Date).ToString('yyyy-MM-dd')
                totalAmount = 220
                lines = @(@{
                    purchaseReceiptItemId = $line.purchaseReceiptItemId
                    quantity = 10; unitCost = 22
                })
            }
            Check "فاتورة المورّد أُنشئت مسوّدة" `
                ($siInvoice.Status -in 200,201 -and $siInvoice.Body.status -eq 'draft') `
                "حالة $($siInvoice.Status) — $($siInvoice.Body.message)"

            if ($siInvoice.Status -in 200,201) {
                $ml = @($siInvoice.Body.lines) | Select-Object -First 1
                Check "المطابقة تحسب فرق السعر" ([Math]::Abs([double]$ml.unitCostVariance - 2) -lt 0.01) `
                    "فرق الوحدة $($ml.unitCostVariance) — المتوقّع 2"
                Check "المطابقة تحسب فرق المبلغ" ([Math]::Abs([double]$ml.amountVariance - 20) -lt 0.01) `
                    "فرق المبلغ $($ml.amountVariance) — المتوقّع 20"

                # سطرٌ فُوتر مرّة لا يُفوتر ثانية: الازدواج يُضاعف الدَّين صامتاً.
                $dup = Api POST "/supplier-invoices" -Token $token -Body @{
                    branchId = $branchId; supplierId = $siSupplier.Body.id
                    invoiceNumber = "INV-DUP-$stamp"
                    invoiceDate = (Get-Date).ToString('yyyy-MM-dd')
                    totalAmount = 220
                    lines = @(@{
                        purchaseReceiptItemId = $line.purchaseReceiptItemId
                        quantity = 10; unitCost = 22
                    })
                }
                Check "تفويتر السطر مرّتين مرفوض" ($dup.Status -eq 400) `
                    "حالة $($dup.Status) — قبولها يُضاعف الدَّين للمورّد"

                # ── الترحيل ────────────────────────────────────────────────
                # ── الترحيل يتطلّب وحدة المحاسبة ────────────────────────
                #
                # يُتخطّى لا يُعدّ فشلاً على إصدارٍ لا يحملها — كما يفعل
                # القسم ٥.٥. وفشلٌ سببه ترخيصٌ لا عطب يُدرّب قارئه على
                # تجاهل الأحمر، فيُهمَل الفشل الحقيقي بعده.
                $posted = Api POST "/supplier-invoices/$($siInvoice.Body.id)/post" -Token $token -Body @{}
                if ($posted.Status -eq 400 -and "$($posted.Body.message)" -match 'المحاسبة') {
                    Skipped "ترحيل فاتورة المورّد" "وحدة المحاسبة غير مفعَّلة على هذا الإصدار"
                } else {
                    Check "الفاتورة رُحّلت" ($posted.Status -eq 200 -and $posted.Body.status -eq 'posted') `
                        "حالة $($posted.Status) — $($posted.Body.message)"
                }

                if ($posted.Status -eq 200) {
                    $siJournal = Api GET "/accounting/journal" -Token $token
                    $siEntry = @($siJournal.Body) | Where-Object { $_.sourceId -eq $siInvoice.Body.id } | Select-Object -First 1

                    if (-not $siEntry) {
                        Check "قيد الفاتورة موجود" $false "لم يُعثر على قيدٍ مصدره الفاتورة"
                    } else {
                        $d = ($siEntry.lines | Measure-Object -Property debit -Sum).Sum
                        $c = ($siEntry.lines | Measure-Object -Property credit -Sum).Sum
                        Check "قيد فاتورة المورّد متوازن" ([Math]::Abs($d - $c) -lt 0.01) "مدين $d ودائن $c"

                        # 2104 «وردت ولم تُفوتَر» يُفرَّغ بقيمة ما وصل (200) لا
                        # بقيمة الفاتورة — وإلا بقي فيه رصيدٌ وهمي لا يُصفَّر.
                        $grni = $siEntry.lines | Where-Object { $_.accountCode -eq '2104' } | Select-Object -First 1
                        Check "«وردت ولم تُفوتَر» يُفرَّغ بقيمة ما وصل" `
                            ($grni -and [Math]::Abs([double]$grni.debit - 200) -lt 0.01) `
                            "مدين $($grni.debit) — المتوقّع 200"

                        # 2101 «الموردون» يُقيَّد بإجمالي الفاتورة لا بما وصل.
                        $pay = $siEntry.lines | Where-Object { $_.accountCode -eq '2101' } | Select-Object -First 1
                        Check "الدَّين للمورّد بقيمة فاتورته" `
                            ($pay -and [Math]::Abs([double]$pay.credit - 220) -lt 0.01) `
                            "دائن $($pay.credit) — المتوقّع 220"

                        # 3103 «فروق أسعار المشتريات» يحمل الفرق ظاهراً لا مدفوناً.
                        $var = $siEntry.lines | Where-Object { $_.accountCode -eq '3103' } | Select-Object -First 1
                        Check "الفرق على حساب فروق الأسعار" `
                            ($var -and [Math]::Abs([double]$var.debit - 20) -lt 0.01) `
                            "مدين $($var.debit) — المتوقّع 20؛ غيابه يعني أن الفرق دُفن في مكانٍ ما"
                    }

                    # الترحيل مرّتين يُنشئ دَيناً مضاعفاً.
                    $rePost = Api POST "/supplier-invoices/$($siInvoice.Body.id)/post" -Token $token -Body @{}
                    Check "ترحيل الفاتورة مرّتين مرفوض" ($rePost.Status -eq 400) "حالة $($rePost.Status)"
                }
            }
        }
    }
}

}

# -----------------------------------------------------------------------------
Section "٦.١ الإسناد الجماعي — ما لا تعرضه الشاشة لا يُقبَل"

# العطب الذي يمسكه هذا القسم: أربعة متحكّمات كانت تربط الكيان كاملاً من
# الطلب. فمن يملك صلاحية الإدارة يرسل حقولاً لا تعرضها أي شاشة ويحرسها
# الخادم في مسارات أخرى — ومنها بصمة الرقم السرّي.
#
# والعزل بين المنظمات لا يحمي من هذا: الفاعل داخل منظمته.

$maName = "زبون إسناد $stamp"
$maCustomer = Api POST "/customers" -Token $token -Body @{
    fullName = $maName
    accountModel = "prepaid"
    creditLimit = 0
    creditDays = 0
    entitlementCeiling = 0
    # ── ما يجب ألّا يُقبَل ──────────────────────────────────────────────
    id = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    pinHash = '$2a$11$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012'
    dailyCap = 999999
    isDeleted = $true
    loyaltyPoints = 5000
}
Check "إنشاء العميل يمرّ" ($maCustomer.Status -in 200,201) `
    "حالة $($maCustomer.Status) — $($maCustomer.Body.message)"

if ($maCustomer.Status -in 200,201) {
    Check "المعرّف المُرسَل يُتجاهَل" `
        ($maCustomer.Body.id -ne 'dddddddd-dddd-dddd-dddd-dddddddddddd') `
        "المعرّف $($maCustomer.Body.id) — قبولُه يجعل العميل يختار مفاتيح الجدول"

    # الحقل الأخطر: بصمةٌ يعرف صاحبها رقمها تتجاوز مسار إصدار البطاقة كلّه.
    Check "بصمة الرقم السرّي لا تُقبَل من الطلب" ($maCustomer.Body.hasPin -ne $true) `
        "hasPin = $($maCustomer.Body.hasPin) — قبولها يعني رقماً سرّياً يضعه المُرسِل"

    Check "السقف اليومي لا يتجاوز سقف المنظمة" `
        ([double]$maCustomer.Body.effectiveDailyCap -lt 999999) `
        "السقف الفعّال $($maCustomer.Body.effectiveDailyCap)"

    # isDeleted = true كان سيُنشئ زبوناً محذوفاً لا يظهر ولا يُحذَف.
    $maRead = Api GET "/customers/$($maCustomer.Body.id)" -Token $token
    Check "الزبون لم يُولَد محذوفاً" ($maRead.Status -eq 200) "حالة $($maRead.Status)"
}

$maProduct = Api POST "/products" -Token $token -Body @{
    sku = "TEST-MA-$stamp"; name = "صنف إسناد $stamp"
    salePrice = 10; costPrice = 5; minSalePrice = 0
    unitBase = "piece"; tracksStock = $true; reorderLevel = 0
    unitConversionFactor = 1
    # ── ما يجب ألّا يُقبَل ──────────────────────────────────────────────
    id = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
    isDeleted = $true
    lastCountedAt = "2030-01-01T00:00:00"
}
Check "إنشاء الصنف يمرّ" ($maProduct.Status -in 200,201) "حالة $($maProduct.Status)"

if ($maProduct.Status -in 200,201) {
    Check "معرّف الصنف المُرسَل يُتجاهَل" `
        ($maProduct.Body.id -ne 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee') `
        "المعرّف $($maProduct.Body.id)"
    Check "الصنف لم يُولَد محذوفاً" ($maProduct.Body.isDeleted -ne $true) `
        "isDeleted = $($maProduct.Body.isDeleted)"
    # تاريخ جردٍ مزوَّر يُخفي الصنف من قائمة «لم يُجرَد منذ».
    Check "تاريخ آخر جرد لا يُقبَل من الطلب" `
        ($null -eq $maProduct.Body.lastCountedAt) `
        "lastCountedAt = $($maProduct.Body.lastCountedAt)"
}

# -----------------------------------------------------------------------------
Section "٦.٢ الإنشاء السريع — حقولٌ ناقصة تصل بافتراضاتها"

# العطب الذي يمسكه هذا القسم: نقطة البيع تُنشئ زبوناً بالاسم والهاتف
# وحدهما، وشاشة المشتريات تُنشئ صنفاً بستّة حقول وهي أمام المورّد.
#
# وحين استُبدل ربطُ الكيان بعقدٍ صريح كاد الناقص يصل **صفراً** بدل افتراض
# الكيان: accountModel فارغاً يُرفَض الطلب كلّه، و unitConversionFactor
# صفراً يجعل كل تحويل وحدةٍ قسمةً على صفر.

$quickCustomer = Api POST "/customers" -Token $token -Body @{
    fullName = "زبون سريع $stamp"
}
Check "زبون سريع بالاسم وحده يمرّ" ($quickCustomer.Status -in 200,201) `
    "حالة $($quickCustomer.Status) — $($quickCustomer.Body.message)"
if ($quickCustomer.Status -in 200,201) {
    Check "نموذج حسابه «مدفوع مسبقاً» افتراضاً" `
        ($quickCustomer.Body.accountModel -eq 'prepaid') `
        "النموذج $($quickCustomer.Body.accountModel)"
}

$quickProduct = Api POST "/products" -Token $token -Body @{
    name = "صنف سريع $stamp"
    sku = "TEST-QUICK-$stamp"
    costPrice = 5; salePrice = 10
    unitBase = "piece"; tracksStock = $true; reorderLevel = 0
}
Check "صنف سريع بستّة حقول يمرّ" ($quickProduct.Status -in 200,201) `
    "حالة $($quickProduct.Status) — $($quickProduct.Body.message)"
if ($quickProduct.Status -in 200,201) {
    Check "معامل تحويل الوحدة واحدٌ لا صفر" `
        ([double]$quickProduct.Body.unitConversionFactor -eq 1) `
        "المعامل $($quickProduct.Body.unitConversionFactor) — الصفر يجعل كل تحويل قسمةً على صفر"
    Check "يتتبّع المخزون افتراضاً" ($quickProduct.Body.tracksStock -eq $true) `
        "tracksStock = $($quickProduct.Body.tracksStock)"
}

# -----------------------------------------------------------------------------
Section "٦. العزل بين المنظمات"

$otherOrgProduct = Api GET "/products/00000000-0000-0000-0000-000000000042" -Token $token
Check "معرّف صنف غير موجود/من منظمة أخرى لا يُقرأ" ($otherOrgProduct.Status -in 404,400) "حالة $($otherOrgProduct.Status)"

$noToken = Api GET "/organizations/me/settings"
Check "الإعدادات محمية بلا توكن" ($noToken.Status -eq 401) "حالة $($noToken.Status)"

$badToken = Api GET "/organizations/me/settings" -Token "eyJhbGciOiJub25lIn0.eyJzdWIiOiJmYWtlIn0.x"
Check "توكن مزوَّر يُرفض" ($badToken.Status -eq 401) "حالة $($badToken.Status) — قبوله يعني أن التوقيع لا يُتحقَّق منه!"

# -----------------------------------------------------------------------------
Section "الخلاصة"

Write-Host ""
Write-Host "  نجح: $script:Pass" -ForegroundColor Green
Write-Host "  فشل: $script:Fail" -ForegroundColor $(if ($script:Fail -gt 0) { 'Red' } else { 'Green' })
Write-Host "  تخطٍ: $script:Skip" -ForegroundColor DarkGray

if ($script:Notes.Count -gt 0) {
    Write-Host ""
    Write-Host "  ملاحظات:" -ForegroundColor Yellow
    foreach ($n in $script:Notes) { Write-Host "   - $n" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "  بيانات الاختبار تحمل الوسم TEST-$stamp — احذفها من القاعدة عند الانتهاء." -ForegroundColor DarkGray
Write-Host ""

exit $(if ($script:Fail -gt 0) { 1 } else { 0 })
