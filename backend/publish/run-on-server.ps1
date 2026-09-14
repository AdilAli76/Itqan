# تشغيل على الخادم الإنتاجي
# يُشغّل هذا على الخادم (C:\publish\New folder) فقط

$TargetFolder = "C:\publish\New folder"
$DatabaseName = "ItqanEnterprise"

Write-Host "================================" -ForegroundColor Green
Write-Host "نشر Kinetic ERP v2.0.3" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green

# 1. تطبيق الترحيل (إضافة جدول refresh_tokens)
Write-Host "`n1️⃣ تطبيق ترحيل قاعدة البيانات..." -ForegroundColor Cyan

cd $TargetFolder

# تثبيت dotnet ef إذا لم يكن موجوداً
dotnet tool list --global | findstr dotnet-ef
if ($LASTEXITCODE -ne 0) {
    Write-Host "تثبيت dotnet-ef..." -ForegroundColor Yellow
    dotnet tool install --global dotnet-ef
}

# تطبيق الترحيل
$ConnectionString = "Server=.;Database=$DatabaseName;Trusted_Connection=true;Encrypt=false;"
dotnet ef database update --connection $ConnectionString --verbose

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ تم تطبيق الترحيل بنجاح!" -ForegroundColor Green
} else {
    Write-Host "❌ فشل تطبيق الترحيل" -ForegroundColor Red
    exit 1
}

# 2. التحقق من appsettings.Production.json
Write-Host "`n2️⃣ التحقق من إعدادات الاتصال..." -ForegroundColor Cyan

if (Test-Path "$TargetFolder\appsettings.Production.json") {
    Write-Host "✅ ملف الإعدادات موجود" -ForegroundColor Green
} else {
    Write-Host "⚠️ تحذير: appsettings.Production.json غير موجود" -ForegroundColor Yellow
}

# 3. تشغيل التطبيق
Write-Host "`n3️⃣ تشغيل التطبيق..." -ForegroundColor Cyan

$env:ASPNETCORE_ENVIRONMENT = "Production"
dotnet KineticEnterprise.Api.dll

# لو تريد تشغيله بدون الانتظار (في الخلفية):
# Start-Process -FilePath "dotnet" -ArgumentList "KineticEnterprise.Api.dll" -WindowStyle Hidden

Write-Host "`n✅ التطبيق يعمل الآن!" -ForegroundColor Green
Write-Host "الرابط: http://localhost:5000" -ForegroundColor Green
