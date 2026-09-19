@echo off
REM =====================================================
REM Itqan ERP - Website Test Script
REM =====================================================
REM
REM الغرض: اختبار الموقع بعد النشر
REM
REM =====================================================

setlocal enabledelayedexpansion

REM التاريخ والوقت
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c-%%a-%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a-%%b)

cls
echo.
echo ╔════════════════════════════════════════════════════════╗
echo ║                                                        ║
echo ║       Itqan ERP - Website Test Script                 ║
echo ║       اختبار الموقع بعد النشر                          ║
echo ║                                                        ║
echo ║       تاريخ: %mydate% الوقت: %mytime%               ║
echo ║                                                        ║
echo ╚════════════════════════════════════════════════════════╝
echo.

REM =====================================================
REM الخطوة 1: التحقق من الملفات
REM =====================================================

echo 1️⃣  التحقق من الملفات...
echo.

set PASS_COUNT=0
set FAIL_COUNT=0
set LOG_FILE=C:\temp\website_test.log

REM حذف السجل القديم
if exist "%LOG_FILE%" del "%LOG_FILE%"

REM اختبار index.html
if exist "C:\kinetic\index.html" (
    echo ✓ تم العثور على: C:\kinetic\index.html
    echo [%mydate% %mytime%] ✓ index.html موجود >> "%LOG_FILE%"
    set /a PASS_COUNT+=1
) else (
    echo ❌ خطأ: C:\kinetic\index.html غير موجود
    echo [%mydate% %mytime%] ❌ index.html غير موجود >> "%LOG_FILE%"
    set /a FAIL_COUNT+=1
)

REM اختبار flutter.js
if exist "C:\kinetic\flutter.js" (
    echo ✓ تم العثور على: C:\kinetic\flutter.js
    echo [%mydate% %mytime%] ✓ flutter.js موجود >> "%LOG_FILE%"
    set /a PASS_COUNT+=1
) else (
    echo ❌ خطأ: C:\kinetic\flutter.js غير موجود
    echo [%mydate% %mytime%] ❌ flutter.js غير موجود >> "%LOG_FILE%"
    set /a FAIL_COUNT+=1
)

REM اختبار main.dart.js
if exist "C:\kinetic\main.dart.js" (
    echo ✓ تم العثور على: C:\kinetic\main.dart.js
    echo [%mydate% %mytime%] ✓ main.dart.js موجود >> "%LOG_FILE%"
    set /a PASS_COUNT+=1
) else (
    echo ❌ خطأ: C:\kinetic\main.dart.js غير موجود
    echo [%mydate% %mytime%] ❌ main.dart.js غير موجود >> "%LOG_FILE%"
    set /a FAIL_COUNT+=1
)

REM اختبار canvaskit
if exist "C:\kinetic\canvaskit" (
    echo ✓ تم العثور على: C:\kinetic\canvaskit\
    echo [%mydate% %mytime%] ✓ canvaskit موجود >> "%LOG_FILE%"
    set /a PASS_COUNT+=1
) else (
    echo ⚠️  تحذير: C:\kinetic\canvaskit\ غير موجود
    echo [%mydate% %mytime%] ⚠️  canvaskit غير موجود >> "%LOG_FILE%"
)

REM اختبار assets
if exist "C:\kinetic\assets" (
    echo ✓ تم العثور على: C:\kinetic\assets\
    echo [%mydate% %mytime%] ✓ assets موجود >> "%LOG_FILE%"
    set /a PASS_COUNT+=1
) else (
    echo ⚠️  تحذير: C:\kinetic\assets\ غير موجود
    echo [%mydate% %mytime%] ⚠️  assets غير موجود >> "%LOG_FILE%"
)

echo.

REM =====================================================
REM الخطوة 2: اختبار حجم الملفات
REM =====================================================

echo 2️⃣  اختبار حجم الملفات...
echo.

REM عد الملفات
for /f %%A in ('dir /s /b "C:\kinetic\*" 2^>nul ^| find /c /v ""') do (
    set FILE_COUNT=%%A
)

echo عدد الملفات: %FILE_COUNT%
echo [%mydate% %mytime%] عدد الملفات: %FILE_COUNT% >> "%LOG_FILE%"

echo.

REM =====================================================
REM الخطوة 3: اختبار الاتصال (محاكاة)
REM =====================================================

echo 3️⃣  اختبار الاتصال...
echo.

REM اختبار localhost:80
echo   اختبار: http://localhost:80
echo [%mydate% %mytime%] اختبار: http://localhost:80 >> "%LOG_FILE%"

powershell -Command "
try {
    \$response = Invoke-WebRequest -Uri 'http://localhost:80' -TimeoutSec 5 -ErrorAction Stop
    if (\$response.StatusCode -eq 200) {
        Write-Host '✓ الموقع متاح على: http://localhost:80'
        Write-Host '   الكود: 200 OK'
    }
} catch {
    Write-Host '⚠️  لم يتمكن من الاتصال بـ localhost:80'
    Write-Host '   تأكد من تشغيل IIS'
}
"

echo [%mydate% %mytime%] انتهى اختبار localhost >> "%LOG_FILE%"

echo.

REM =====================================================
REM الخطوة 4: ملخص الاختبار
REM =====================================================

echo ╔════════════════════════════════════════════════════════╗
if %FAIL_COUNT% equ 0 (
    echo ║               ✅ جميع الاختبارات نجحت!               ║
) else (
    echo ║               ⚠️  بعض الاختبارات فشلت!               ║
)
echo ╚════════════════════════════════════════════════════════╝
echo.

echo 📊 النتائج:
echo   ✓ نجح: %PASS_COUNT%
echo   ❌ فشل: %FAIL_COUNT%
echo   📦 عدد الملفات: %FILE_COUNT%
echo.

echo 🌐 روابط الاختبار:
echo   • http://localhost (محلياً)
echo   • http://localhost:80 (محلياً مع الميناء)
echo   • https://erp.droob-albayan.ly/app (الدومين الفعلي)
echo.

echo 📝 تم تسجيل النتائج في:
echo   %LOG_FILE%
echo.

echo [%mydate% %mytime%] ════════════════════════════════════════════════════════ >> "%LOG_FILE%"

pause
