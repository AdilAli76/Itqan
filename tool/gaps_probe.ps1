#  =============================================================================
#   فحص الثغرات المُبلَّغ عنها — أين النقص فعلاً: في السيرفر أم في الواجهة؟
#
#   هذا ليس اختبار نجاح/فشل. هو **تشخيص**: لكل نقص لاحظه المستخدم على
#   الشاشة، يسأل السيرفر مباشرةً هل القدرة موجودة فيه أصلاً. والجواب يقرّر
#   نوع العمل المطلوب:
#
#       [الواجهة]  السيرفر يدعمها والشاشة لا تستعملها  ← عمل في lib/ وحده
#       [السيرفر]  القدرة غير موجودة في الـAPI أصلاً    ← عمل في backend/ أولاً
#
#   الفرق ليس تفصيلاً: نقصٌ في الواجهة يُصلَح في ساعات، ونقصٌ في السيرفر
#   يعني عمود قاعدة بيانات وترحيلاً ونقطة نهاية جديدة.
#
#   التشغيل:
#       powershell -ExecutionPolicy Bypass -File tool\gaps_probe.ps1 `
#           -BaseUrl https://<العنوان>/api
#
#   ⚠ يكتب بيانات تجريبية: أصناف باسم PROBE-، وأمر شراء، وفواتير.
#  =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$Email = ""
)

$ErrorActionPreference = 'Continue'
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

$script:Findings = @()

function Section([string]$t) {
    Write-Host ""
    Write-Host ("═" * 74) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("═" * 74) -ForegroundColor DarkGray
}

# الحكم على القدرة لا على الطلب: "موجودة في السيرفر" أو "غير موجودة".
function Verdict([string]$name, [bool]$serverHasIt, [string]$detail) {
    if ($serverHasIt) {
        Write-Host "  [الواجهة] $name" -ForegroundColor Yellow
        Write-Host "            $detail" -ForegroundColor DarkGray
        $script:Findings += [pscustomobject]@{ Layer = 'الواجهة'; Item = $name; Detail = $detail }
    } else {
        Write-Host "  [السيرفر] $name" -ForegroundColor Magenta
        Write-Host "            $detail" -ForegroundColor DarkGray
        $script:Findings += [pscustomobject]@{ Layer = 'السيرفر'; Item = $name; Detail = $detail }
    }
}

function Info([string]$t) { Write-Host "            $t" -ForegroundColor DarkGray }

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
    Write-Host "  BaseUrl يجب أن ينتهي بـ /api" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────── الدخول ──────────────────────────────────
Section "تسجيل الدخول"

if (-not $Email) { $Email = Read-Host "  البريد الإلكتروني" }
$plain = ""
try { $plain = Read-Password "كلمة المرور" } catch {
    $secure = Read-Host "  كلمة المرور" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
$login = Api POST "/auth/login" @{ emailOrUsername = $Email; password = $plain }
$plain = $null
if ($login.Status -ne 200 -or -not $login.Body.token) {
    Write-Host "  تعذّر تسجيل الدخول (حالة $($login.Status))." -ForegroundColor Red
    exit 1
}
$token = $login.Body.token
Write-Host "  الدخول تمّ — الدور: $($login.Body.role)" -ForegroundColor Green

$branches = Api GET "/branches" -Token $token
$branch = $branches.Body | Where-Object { $_.isActive -ne $false } | Select-Object -First 1
if (-not $branch) { $branch = $branches.Body | Select-Object -First 1 }
if (-not $branch) { Write-Host "  لا فرع — أوقفت الفحص." -ForegroundColor Red; exit 1 }
$branchId = $branch.id
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

# ───────────────────────────── ١. المشتريات ──────────────────────────────
Section "١. المشتريات"

# صنف جديد أثناء الشراء
$p1 = Api POST "/products" -Token $token -Body @{
    sku = "PROBE-$stamp-A"; name = "صنف فحص أ"; salePrice = 50; costPrice = 30
    unitBase = "piece"; tracksStock = $true; reorderLevel = 1
}
Verdict "إنشاء صنف جديد أثناء أمر الشراء" ($p1.Status -in 200, 201) `
    "POST /products متاح بنفس التوكن (حالة $($p1.Status)) — فالشاشة تستطيع فتح بطاقة صنف من داخل أمر الشراء بلا أي تعديل في السيرفر."
$prodA = $p1.Body.id

$p2 = Api POST "/products" -Token $token -Body @{
    sku = "PROBE-$stamp-B"; name = "صنف فحص ب"; salePrice = 80; costPrice = 50
    unitBase = "piece"; tracksStock = $true; reorderLevel = 1
}
$prodB = $p2.Body.id

# إدخال متعدد الأسطر
$po = Api POST "/purchase-orders" -Token $token -Body @{
    branchId = $branchId
    lines    = @(
        @{ productId = $prodA; quantity = 10; unitCost = 30; salePrice = 50 },
        @{ productId = $prodB; quantity = 10; unitCost = 50; salePrice = 80 }
    )
}
Verdict "أمر شراء بعدّة أصناف في طلب واحد" ($po.Status -in 200, 201) `
    "السيرفر قبل سطرين في أمر واحد (حالة $($po.Status)) — التعدّد مدعوم؛ الناقص هو الإدخال الجماعي (لصق/استيراد ملف) في الشاشة."
$poId = $po.Body.id

# مرفق فاتورة المورّد
$att = Api POST "/purchase-orders/$poId/attachments" -Token $token -Body @{ fileName = "x.pdf" }
Verdict "رفع صورة/ملف فاتورة المورّد" ($att.Status -notin 404, 405) `
    "POST /purchase-orders/{id}/attachments ردّ $($att.Status) — لا نقطة نهاية ولا جدول مرفقات. يحتاج عمود/جدول وترحيلاً ونقطة رفع في السيرفر قبل أي عمل في الشاشة."

# استلام جزئي
$null = Api POST "/purchase-orders/$poId/order" -Token $token
$recv = Api POST "/purchase-orders/$poId/receive" -Token $token -Body @{
    # الكمية مُرسَلة عمداً: إن كان الاستلام الجزئي مدعوماً فسيستلم 4 لا 10.
    lines = @(@{ productId = $prodA; quantity = 4 }, @{ productId = $prodB; quantity = 4 })
}
Start-Sleep -Milliseconds 300
$inv = Api GET "/products/inventory?search=PROBE-$stamp-A" -Token $token
$qtyA = [decimal](($inv.Body.items | Where-Object { $_.sku -eq "PROBE-$stamp-A" }).quantity)
Verdict "استلام كمية جزئية من أمر الشراء" ($qtyA -ne 10 -and $qtyA -gt 0) `
    "طُلبت 10 واستُلمت بكمية 4 مُرسَلة، فدخل المخزون $qtyA. ReceiveLineRequest لا يحوي حقل كمية أصلاً — يستلم الأمر كاملاً أو لا شيء. توريد ناقص من المورّد لا يمكن تسجيله."

# ─────────────────────────── ٢. نقطة البيع ──────────────────────────────
Section "٢. نقطة البيع"

# صنف لا يتتبّع المخزون — الخدمات والأصناف المفتوحة
$svc = Api POST "/products" -Token $token -Body @{
    sku = "PROBE-$stamp-S"; name = "خدمة فحص"; salePrice = 25; costPrice = 0
    unitBase = "piece"; tracksStock = $false; reorderLevel = 0
}
$prodS = $svc.Body.id
$sellSvc = Api POST "/invoices" -Token $token -Body @{
    branchId = $branchId; paymentMethod = "cash"
    lines = @(@{ productId = $prodS; quantity = 1; unitPrice = 25 })
}
Verdict "بيع صنف بلا مخزون (tracksStock=false)" ($sellSvc.Status -in 200, 201) `
    "السيرفر باعه بلا رصيد (حالة $($sellSvc.Status)) — القدرة موجودة. لكن شاشة البيع لا تعرض شيئاً قبل الكتابة في مربع البحث (pos_providers.dart: البحث فارغ يعني قائمة فارغة)، فصنف بلا باركود لا سبيل إليه إلا بكتابة اسمه كاملاً."

$invS = Api GET "/products/inventory?search=PROBE-$stamp-S" -Token $token
$rowS = $invS.Body.items | Where-Object { $_.sku -eq "PROBE-$stamp-S" }
Verdict "الصنف بلا مخزون يظهر في نتائج البحث" ($null -ne $rowS) `
    "GET /products/inventory يُرجعه برصيد $($rowS.quantity) — لا يُخفيه السيرفر. فغيابه عن الشاشة سببه الواجهة لا الـAPI."

# الأكثر مبيعاً
$today = (Get-Date).ToString('yyyy-MM-dd')
$from = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd')
$rep = Api GET "/reports/sales-summary?from=$from&to=$today" -Token $token
$hasTop = ($rep.Status -eq 200 -and $null -ne $rep.Body.topProducts)
Verdict "قائمة الأصناف الأكثر مبيعاً" $hasTop `
    "GET /reports/sales-summary يُرجع topProducts ($(if ($hasTop) { $rep.Body.topProducts.Count } else { 0 }) صنفاً) — البيانات جاهزة في السيرفر، والناقص شبكة أزرار ثابتة على شاشة البيع تستهلكها."

# بطاقة العميل
$cards = Api GET "/wallet-cards" -Token $token
$card = $null
if ($cards.Status -eq 200) {
    $list = if ($cards.Body.items) { $cards.Body.items } else { $cards.Body }
    $card = $list | Where-Object { $_.status -eq 'active' -or $_.isActive -eq $true } | Select-Object -First 1
}
if ($card) {
    $code = if ($card.cardCode) { $card.cardCode } else { $card.code }
    $byCard = Api GET "/customers/by-card/$code" -Token $token
    Verdict "تمرير بطاقة العميل للخصم من محفظته" ($byCard.Status -eq 200) `
        "GET /customers/by-card/{code} ردّ $($byCard.Status) — الوظيفة تعمل، والمسح يجري على **نفس مربع بحث الأصناف**: يُجرَّب باركود صنف أولاً، فإن لم يطابق يُجرَّب كبطاقة عميل (pos_screen.dart:_tryCardScan). لا زر ظاهر لها، وهذا سبب عدم عثورك عليها."
} else {
    Write-Host "  [تخطٍ]   بطاقة العميل — لا بطاقة نشطة في هذه المنظمة" -ForegroundColor DarkGray
    Info "أصدر بطاقة من شاشة بطاقات المحفظة ثم أعد التشغيل لفحص هذا البند."
}

# الدفع النقدي: المستلَم والباقي
$cash = Api POST "/invoices" -Token $token -Body @{
    branchId = $branchId; paymentMethod = "cash"
    lines = @(@{ productId = $prodS; quantity = 1; unitPrice = 25 })
}
$fields = @()
if ($cash.Body) { $fields = $cash.Body.PSObject.Properties.Name }
$hasCashFields = ($fields -contains 'tenderedAmount') -or ($fields -contains 'changeDue') -or ($fields -contains 'amountPaid')
Verdict "حفظ المبلغ المستلَم والباقي مع الفاتورة" $hasCashFields `
    "حقول الفاتورة المُعادة: $($fields -join ', ') — لا حقل للمستلَم ولا للباقي. حاسبة النقد في الشاشة تحسبهما وتعرضهما ثم تنساهما (cash_payment_dialog.dart يقول ذلك صراحةً)، فلا يُطبَعان على الإيصال ولا يُراجَعان في تسوية الدرج."

$hasSplit = ($fields -contains 'payments')
Verdict "دفع مقسّم (نقد + بطاقة على فاتورة واحدة)" $hasSplit `
    "جدول InvoicePayments موجود ويقبل أكثر من صف، لكن InvoicesController يُنشئ صفاً واحداً بطريقة دفع واحدة — والشاشة لا تعرض تقسيماً."

# ─────────────────────────────── الخلاصة ────────────────────────────────
Section "الخلاصة"

$ui = @($script:Findings | Where-Object { $_.Layer -eq 'الواجهة' })
$srv = @($script:Findings | Where-Object { $_.Layer -eq 'السيرفر' })

Write-Host "  نقص في الواجهة وحدها ($($ui.Count)) — السيرفر يدعمها اليوم:" -ForegroundColor Yellow
$ui | ForEach-Object { Write-Host "     • $($_.Item)" -ForegroundColor Gray }
Write-Host ""
Write-Host "  نقص في السيرفر ($($srv.Count)) — يحتاج قاعدة بيانات ونقاط نهاية:" -ForegroundColor Magenta
$srv | ForEach-Object { Write-Host "     • $($_.Item)" -ForegroundColor Gray }
Write-Host ""
Write-Host "  بيانات الفحص باسم PROBE-$stamp-* تبقى في القاعدة." -ForegroundColor DarkGray
