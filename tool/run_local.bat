@echo off
chcp 65001 > nul
title تشغيل منظومة إتقان ERP — محلياً
setlocal

rem  يُشغّل الخادم والواجهة معاً للتطوير المحلي فقط.
rem
rem  ولا كلمة مرور هنا: النسخة السابقة من هذا الملف كتبت بريد المستخدم
rem  وكلمة مروره بنصّ صريح، فصار أي من يفتح المجلد يملك حساب مالك المنصة.
rem  بيانات الدخول تُدخَل في الشاشة.

set "ROOT=%~dp0.."
set "FLUTTER=flutter"
where /q flutter || set "FLUTTER=C:\src\flutter\bin\flutter.bat"

echo [1/2] الخادم — ASP.NET Core على المنفذ 5000...
start "إتقان API — 5000" cmd /k "cd /d "%ROOT%\backend\KineticEnterprise.Api" && set ASPNETCORE_ENVIRONMENT=Development && dotnet run"

timeout /t 5 /nobreak > nul

echo [2/2] الواجهة — Flutter Web على Chrome...
start "إتقان — الواجهة" cmd /k "cd /d "%ROOT%" && "%FLUTTER%" run -d chrome --dart-define=API_BASE_URL=http://localhost:5000/api"

echo.
echo تم التشغيل. أدخل بياناتك في شاشة الدخول.
pause
