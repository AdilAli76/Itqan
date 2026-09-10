# SSL Certificate Setup Script
# للاستخدام في Production مع Let's Encrypt

param(
    [Parameter(Mandatory=$true)]
    [string]$Domain,

    [Parameter(Mandatory=$false)]
    [string]$Email = "admin@$Domain"
)

Write-Host "🔐 SSL Certificate Setup للـ Domain: $Domain" -ForegroundColor Cyan

# التحقق من الأدوات المطلوبة
if (-not (Get-Command certbot -ErrorAction SilentlyContinue)) {
    Write-Host "❌ certbot غير مثبت. يرجى تثبيت Let's Encrypt certbot أولاً" -ForegroundColor Red
    Write-Host "Windows: choco install certbot -y" -ForegroundColor Yellow
    Write-Host "أو قم بالتحميل من: https://certbot.eff.org/" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ certbot موجود" -ForegroundColor Green

# التحقق من تثبيت IIS
$iisInstalled = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if ($iisInstalled -and $iisInstalled.Installed) {
    Write-Host "✓ IIS مثبت" -ForegroundColor Green
    $webServer = "IIS"
} else {
    Write-Host "⚠️ IIS غير مثبت. سيتم استخدام Manual mode" -ForegroundColor Yellow
    $webServer = "Manual"
}

# إنشاء الشهادة
Write-Host "`n🔧 جاري إنشاء شهادة SSL..." -ForegroundColor Cyan

if ($webServer -eq "IIS") {
    # استخدام IIS plugin
    & certbot certonly `
        --iis `
        --domain $Domain `
        --email $Email `
        --agree-tos `
        --non-interactive
} else {
    # استخدام standalone mode
    & certbot certonly `
        --standalone `
        --domain $Domain `
        --email $Email `
        --agree-tos `
        --non-interactive
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ تم إنشاء الشهادة بنجاح" -ForegroundColor Green

    # المسار الافتراضي للشهادة
    $certPath = "C:\ProgramData\letsencrypt\live\$Domain"
    Write-Host "`n📁 مسار الشهادة: $certPath" -ForegroundColor Cyan

    # التعليمات
    Write-Host "`n📋 التعليمات التالية:`n" -ForegroundColor Cyan
    Write-Host "1. في ASP.NET Core appsettings.Production.json، أضف:" -ForegroundColor White
    Write-Host @"
    {
      "Kestrel": {
        "Certificates": {
          "Default": {
            "Path": "C:\\ProgramData\\letsencrypt\\live\\$Domain\\pkcs12\\your-domain.pfx",
            "Password": "your-password"
          }
        },
        "Endpoints": {
          "Http": { "Url": "http://localhost:5000" },
          "Https": { "Url": "https://localhost:5001" }
        }
      }
    }
"@ -ForegroundColor Yellow

    Write-Host "2. تحويل الشهادة إلى PKCS12:" -ForegroundColor White
    Write-Host @"
    openssl pkcs12 -export `
      -in $certPath\fullchain.pem `
      -inkey $certPath\privkey.pem `
      -out $certPath\pkcs12\your-domain.pfx `
      -passout pass:your-password
"@ -ForegroundColor Yellow

    Write-Host "3. تحديث السماح بالـ IIS (إن لزم الأمر):" -ForegroundColor White
    Write-Host "   icacls 'C:\ProgramData\letsencrypt' /grant 'IIS_IUSRS:F'" -ForegroundColor Yellow

} else {
    Write-Host "❌ فشل إنشاء الشهادة. تحقق من المشاكل أعلاه." -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ إعداد الشهادة مكتمل!" -ForegroundColor Green
Write-Host "`n⚠️ ملاحظة مهمة: الشهادات من Let's Encrypt تنتهي بعد 90 يوم" -ForegroundColor Yellow
Write-Host "قم بإعداد renewal تلقائي: certbot renew --dry-run" -ForegroundColor Yellow
