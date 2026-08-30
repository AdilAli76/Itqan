#  =============================================================================
#   جولة شراء وبيع — دورة كاملة على الـAPI الحقيقي
#
#   يشتري فاتورة من عشرة أصناف، يستلمها في المخزن، ثم يبيع نصف كل صنف في
#   نقطة البيع، ويتحقّق من الرصيد بعد كل مرحلة.
#
#   لماذا عبر الـAPI لا عبر الواجهة: الواجهة تخفي زراً؛ السؤال هو ماذا يفعل
#   السيرفر. وهذا المسار — شراء ← استلام ← بيع — هو الذي يمسّ المخزون فعلياً
#   في ثلاث نقاط مختلفة، فخطأ في أيّها يظهر رصيداً خاطئاً لا رسالة خطأ.
#
#   التشغيل:
#       powershell -ExecutionPolicy Bypass -File tool\demo_purchase_sale.ps1 `
#           -BaseUrl https://<العنوان>/api
#
#   كلمة المرور تُطلب تفاعلياً ولا تُمرَّر كوسيط: الوسائط تُسجَّل في تاريخ
#   الأوامر وفي قائمة العمليات.
#
#   ⚠ يكتب بيانات حقيقية في القاعدة: عشرة أصناف باسم DEMO-، وأمر شراء،
#   وفاتورة بيع. الأصناف تبقى في الكتالوج بعد انتهائه — احذفها يدوياً إن
#   شئت، أو شغّله على قاعدة تجربة.
#  =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$Email = "",
    [int]$ItemCount = 10,
    [decimal]$QtyPerItem = 10,
    [decimal]$SellRatio = 0.5
)

$ErrorActionPreference = 'Continue'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$script:Pass = 0
$script:Fail = 0

function Section([string]$t) {
    Write-Host ""
    Write-Host ("═" * 74) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("═" * 74) -ForegroundColor DarkGray
}

function Check([string]$name, [bool]$ok, [string]$detail = "") {
    if ($ok) {
        $script:Pass++
        Write-Host "  [نجح]  $name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "  [فشل]  $name" -ForegroundColor Red
        if ($detail) { Write-Host "         $detail" -ForegroundColor DarkYellow }
    }
}

function Info([string]$t) { Write-Host "         $t" -ForegroundColor DarkGray }

# استدعاء لا يرمي استثناءً عند 4xx — رفض السيرفر نتيجةٌ تُقرأ لا عطل يُوقف.
function Api {
    param([string]$Method, [string]$Path, $Body = $null, [string]$Token = $null)

    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }

    $params = @{
        Uri = "$BaseUrl$Path"; Method = $Method; Headers = $headers
        UseBasicParsing = $true; TimeoutSec = 60
    }
    if ($null -ne $Body) {
        $params['ContentType'] = 'application/json; charset=utf-8'
        $params['Body'] = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $Body -Depth 8))
    }

    try {
        $r = Invoke-WebRequest @params
        $parsed = $null
        if ($r.Content) { try { $parsed = $r.Content | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Body = $parsed }
    } catch {
        $status = 0; $raw = ""
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode.value__
            try { $raw = (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
        }
        $parsed = $null
        if ($raw) { try { $parsed = $raw | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = $status; Body = $parsed }
    }
}

# ReadKey لا -AsSecureString: الأخير يبتر الإدخال في الطرفيات المدمجة فيردّ
# السيرفر 401 وكأن كلمة المرور خاطئة.
function Read-Password([string]$label) {
    Write-Host -NoNewline "  $label`: "
    $buf = New-Object Text.StringBuilder
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { Write-Host ""; break }
        if ($key.Key -eq 'Backspace') {
            if ($buf.Length -gt 0) { $buf.Length--; Write-Host -NoNewline "`b `b" }
            continue
        }
        if ([char]::IsControl($key.KeyChar)) { continue }
        [void]$buf.Append($key.KeyChar)
        Write-Host -NoNewline "*"
    }
    return $buf.ToString()
}

$BaseUrl = $BaseUrl.TrimEnd('/')
if ($BaseUrl -notmatch '/api$') {
    Write-Host "  BaseUrl يجب أن ينتهي بـ /api — مثال: https://example.com/api" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  جولة شراء وبيع — $BaseUrl" -ForegroundColor White
Write-Host "  $ItemCount أصناف × $QtyPerItem وحدة شراءً، ثم بيع $([int]($SellRatio * 100))% من كل صنف" -ForegroundColor DarkGray

# ─────────────────────────────── ١. الدخول ───────────────────────────────
Section "١. تسجيل الدخول"

$ping = Api GET "/products"
if ($ping.Status -eq 0) {
    Write-Host "  السيرفر لا يستجيب على $BaseUrl" -ForegroundColor Red
    exit 1
}
Check "السيرفر يستجيب" $true ""
Check "نقطة نهاية محمية ترفض بلا توكن (401)" ($ping.Status -eq 401) "رجعت $($ping.Status) — نقطة نهاية مكشوفة!"

if (-not $Email) { $Email = Read-Host "  البريد الإلكتروني" }
$plain = ""
try { $plain = Read-Password "كلمة المرور" } catch {
    $secure = Read-Host "  كلمة المرور" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
if ($plain.Length -eq 0) {
    Write-Host "  لم يُلتقط أي حرف — شغّل السكربت من نافذة PowerShell حقيقية." -ForegroundColor Red
    exit 1
}

$login = Api POST "/auth/login" @{ emailOrUsername = $Email; password = $plain }
$plain = $null
if ($login.Status -ne 200 -or -not $login.Body.token) {
    Write-Host "  تعذّر تسجيل الدخول (حالة $($login.Status))." -ForegroundColor Red
    exit 1
}
$token = $login.Body.token
Check "تسجيل الدخول" $true ""
Info "الدور: $($login.Body.role)"

$branches = Api GET "/branches" -Token $token
$branch = $branches.Body | Where-Object { $_.isActive -ne $false } | Select-Object -First 1
if (-not $branch) { $branch = $branches.Body | Select-Object -First 1 }
if (-not $branch) {
    Write-Host "  لا يوجد فرع في هذه المنظمة — أنشئ فرعاً من شاشة الفروع أولاً." -ForegroundColor Red
    exit 1
}
$branchId = $branch.id
Check "الفرع محدَّد" $true ""
Info "$($branch.name)  [$branchId]"

# ─────────────────────────────── ٢. الأصناف ──────────────────────────────
Section "٢. إنشاء $ItemCount أصناف"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$items = @()

for ($i = 1; $i -le $ItemCount; $i++) {
    $n = "{0:D2}" -f $i
    # أسعار متباينة بين الأصناف: سعرٌ موحّد يُخفي خطأ ضرب الكمية في سعر
    # الصنف الخطأ — المجموع يخرج صحيحاً بالمصادفة.
    $cost = 10 + ($i * 3)
    $sale = [Math]::Round($cost * 1.4, 2)

    $r = Api POST "/products" -Token $token -Body @{
        sku          = "DEMO-$stamp-$n"
        name         = "صنف تجريبي $n"
        salePrice    = $sale
        costPrice    = $cost
        unitBase     = "piece"
        tracksStock  = $true
        reorderLevel = 2
    }
    if ($r.Status -in 200, 201) {
        $items += [pscustomobject]@{
            Id = $r.Body.id; Sku = "DEMO-$stamp-$n"; Cost = $cost; Sale = $sale
        }
    } else {
        Check "إنشاء الصنف $n" $false "حالة $($r.Status) — $($r.Body.message)"
    }
}

Check "أُنشئت $($items.Count) من $ItemCount أصناف" ($items.Count -eq $ItemCount) "الناقص يعني صلاحية inventory.manage أو خطأ تحقّق"
if ($items.Count -eq 0) { exit 1 }

# ─────────────────────────────── ٣. الشراء ───────────────────────────────
Section "٣. فاتورة الشراء"

$poLines = $items | ForEach-Object {
    @{ productId = $_.Id; quantity = $QtyPerItem; unitCost = $_.Cost; salePrice = $_.Sale }
}
$expectedTotal = ($items | ForEach-Object { $_.Cost * $QtyPerItem } | Measure-Object -Sum).Sum

$po = Api POST "/purchase-orders" -Token $token -Body @{
    branchId = $branchId
    lines    = @($poLines)
}
Check "إنشاء أمر الشراء (مسودة)" ($po.Status -in 200, 201) "حالة $($po.Status) — $($po.Body.message)"
if ($po.Status -notin 200, 201) { exit 1 }

$poId = $po.Body.id
Info "رقم الأمر: $poId"
Check "الإجمالي محسوب في السيرفر ($expectedTotal)" ([decimal]$po.Body.totalAmount -eq [decimal]$expectedTotal) `
    "السيرفر أعاد $($po.Body.totalAmount) والمتوقَّع $expectedTotal"

# الاستلام قبل الإرسال يجب أن يُرفَض: الحالات الثلاث (مسودة/مُرسَل/مستلَم)
# ليست تزييناً — قفزها يعني إدخال مخزون لأمر لم يُطلب من مورّد أصلاً.
$early = Api POST "/purchase-orders/$poId/receive" -Token $token -Body @{ lines = @() }
Check "الاستلام قبل الإرسال مرفوض" ($early.Status -eq 400) "رجعت $($early.Status)"

$ordered = Api POST "/purchase-orders/$poId/order" -Token $token
Check "إرسال الأمر للمورّد" ($ordered.Status -in 200, 204) "حالة $($ordered.Status)"

$receiveLines = $items | ForEach-Object { @{ productId = $_.Id } }
$received = Api POST "/purchase-orders/$poId/receive" -Token $token -Body @{ lines = @($receiveLines) }
Check "استلام البضاعة في المخزن" ($received.Status -in 200, 204) "حالة $($received.Status) — $($received.Body.message)"

# ────────────────────────── ٤. الرصيد بعد الشراء ─────────────────────────
Section "٤. الرصيد بعد الاستلام"

function Get-Qty([string]$sku) {
    $inv = Api GET "/products/inventory?search=$sku" -Token $token
    # النقطة تُرجع صفحة {items, totalCount, ...} لا مصفوفة مباشرة.
    $row = $inv.Body.items | Where-Object { $_.sku -eq $sku } | Select-Object -First 1
    if ($null -eq $row) { return $null }
    return [decimal]$row.quantity
}

$afterBuy = 0
$okBuy = $true
foreach ($it in $items) {
    $q = Get-Qty $it.Sku
    if ($null -eq $q -or $q -ne $QtyPerItem) { $okBuy = $false; Info "$($it.Sku): $q (المتوقَّع $QtyPerItem)" }
    if ($null -ne $q) { $afterBuy += $q }
}
Check "كل صنف رصيده $QtyPerItem — الإجمالي $afterBuy" $okBuy "الرصيد لم يدخل كما يجب"

# ─────────────────────────────── ٥. البيع ────────────────────────────────
Section "٥. البيع في نقطة البيع — $([int]($SellRatio * 100))% من كل صنف"

$sellQty = $QtyPerItem * $SellRatio
$saleLines = $items | ForEach-Object {
    @{ productId = $_.Id; quantity = $sellQty; unitPrice = $_.Sale }
}
$expectedSale = ($items | ForEach-Object { $_.Sale * $sellQty } | Measure-Object -Sum).Sum

# مفتاح العملية: هو ما يجعل إعادة الإرسال بعد انقطاع الشبكة آمنة.
$clientRequestId = [Guid]::NewGuid().ToString()

$sale = Api POST "/invoices" -Token $token -Body @{
    branchId        = $branchId
    paymentMethod   = "cash"
    clientRequestId = $clientRequestId
    lines           = @($saleLines)
}
Check "فاتورة البيع ($sellQty من كل صنف)" ($sale.Status -in 200, 201) "حالة $($sale.Status) — $($sale.Body.message)"
if ($sale.Status -notin 200, 201) { exit 1 }
$invNo = if ($sale.Body.invoiceNumber) { $sale.Body.invoiceNumber } else { $sale.Body.id }
Info "رقم الفاتورة: $invNo"
Check "إجمالي الفاتورة محسوب في السيرفر ($expectedSale)" ([decimal]$sale.Body.totalAmount -eq [decimal]$expectedSale) `
    "السيرفر أعاد $($sale.Body.totalAmount) والمتوقَّع $expectedSale"

# إعادة إرسال نفس العملية — الحالة الشائعة في متجر: وصل الطلب وضاع الرد.
# الصواب هنا ألّا يُخصَم المخزون مرّتين، لا أن يُرفض الطلب.
$replay = Api POST "/invoices" -Token $token -Body @{
    branchId        = $branchId
    paymentMethod   = "cash"
    clientRequestId = $clientRequestId
    lines           = @($saleLines)
}
Check "إعادة إرسال نفس العملية لا تُنشئ فاتورة ثانية" `
    ($replay.Status -in 200, 201 -and $replay.Body.id -eq $sale.Body.id) `
    "حالة $($replay.Status)، المعرَّف $($replay.Body.id) مقابل $($sale.Body.id)"

# ────────────────────────── ٦. الرصيد بعد البيع ──────────────────────────
Section "٦. الرصيد بعد البيع"

$expectedLeft = $QtyPerItem - $sellQty
$afterSell = 0
$okSell = $true
foreach ($it in $items) {
    $q = Get-Qty $it.Sku
    if ($null -eq $q -or $q -ne $expectedLeft) { $okSell = $false; Info "$($it.Sku): $q (المتوقَّع $expectedLeft)" }
    if ($null -ne $q) { $afterSell += $q }
}
Check "كل صنف بقي منه $expectedLeft — الإجمالي $afterSell" $okSell "الخصم لم يقع كما يجب"

# البيع فوق الرصيد: الفحص الوحيد الذي يُثبت أن المخزون قيدٌ لا رقمٌ للعرض.
$over = Api POST "/invoices" -Token $token -Body @{
    branchId      = $branchId
    paymentMethod = "cash"
    lines         = @(@{ productId = $items[0].Id; quantity = ($QtyPerItem * 5); unitPrice = $items[0].Sale })
}
Check "البيع فوق الرصيد مرفوض" ($over.Status -eq 400) "رجعت $($over.Status) — رصيد سالب ممكن!"

# ─────────────────────────────── الخلاصة ─────────────────────────────────
Section "الخلاصة"

Write-Host "  اشتُري : $($items.Count) أصناف × $QtyPerItem = $afterBuy وحدة، بتكلفة $expectedTotal"
Write-Host "  بِيع   : $sellQty من كل صنف = $($afterBuy - $afterSell) وحدة، بقيمة $expectedSale"
Write-Host "  المتبقي: $afterSell وحدة"
Write-Host ""
Write-Host "  نجح: $script:Pass   فشل: $script:Fail" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
Write-Host ""
Write-Host "  الأصناف باسم DEMO-$stamp-* والفاتورة وأمر الشراء تبقى في القاعدة." -ForegroundColor DarkGray

if ($script:Fail -gt 0) { exit 1 }
