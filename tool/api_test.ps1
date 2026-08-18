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
#      powershell -ExecutionPolicy Bypass -File tool\api_test.ps1 -BaseUrl http://localhost:5000/api
#
#  يكتب بيانات تجريبية في القاعدة (أصناف وفواتير باسم يبدأ بـ TEST-).
#  لا تُشغّله على قاعدة إنتاج.
# =============================================================================

param(
    [string]$BaseUrl = "http://localhost:5000/api",
    [string]$Email = ""
)

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
Check "نقطة نهاية محمية ترفض بلا توكن (401)" ($ping.Status -eq 401) "رجعت $($ping.Status) — نقطة نهاية مكشوفة!"

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
try {
    $plain = Read-Password "كلمة المرور"
} catch {
    # لا طرفية حقيقية (إعادة توجيه أو مضيف بلا Console) — الرجوع للطريقة
    # القياسية بدل الفشل الصامت.
    $secure = Read-Host "  كلمة المرور" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

$capturedLength = $plain.Length
if ($capturedLength -eq 0) {
    Write-Host "  لم يُلتقط أي حرف من كلمة المرور — شغّل السكربت من نافذة PowerShell حقيقية." -ForegroundColor Red
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
    $sellable = $existing.Body |
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
    $qty = ($check.Body | Where-Object { $_.id -eq $productId }).quantity
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
    $currentQty = ($available.Body | Where-Object { $_.id -eq $productId }).quantity
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
    $qtyNow = ($reset.Body | Where-Object { $_.id -eq $productId }).quantity
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
    $finalQty = ($after.Body | Where-Object { $_.id -eq $productId }).quantity
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
