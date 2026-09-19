@echo off
REM =====================================================
REM Itqan ERP - Web Deployment Script
REM =====================================================
REM
REM الغرض: فك ضغط ملف الويب ونسخه إلى مجلد الإنتاج
REM المصدر: C:\temp\ItqanERP-Web-v1.0.0.zip
REM الهدف: C:\kinetic
REM
REM =====================================================

setlocal enabledelayedexpansion

REM =====================================================
REM إعدادات أساسية
REM =====================================================

set SOURCE_ZIP=C:\temp\ItqanERP-Web-v1.0.0.zip
set TARGET_DIR=C:\kinetic
set TEMP_EXTRACT=C:\temp\extract_temp
set LOG_FILE=C:\temp\deployment.log

REM التاريخ والوقت
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c-%%a-%%b)
for /f "tokens=1-2 delims=/:" %%a in ('time /t') do (set mytime=%%a-%%b)

cls
echo.
echo ╔════════════════════════════════════════════════════════╗
echo ║                                                        ║
echo ║       Itqan ERP - Web Deployment Script               ║
echo ║       نسخة الويب - سكريبت النشر                         ║
echo ║                                                        ║
echo ║       تاريخ: %mydate% الوقت: %mytime%               ║
echo ║                                                        ║
echo ╚════════════════════════════════════════════════════════╝
echo.

REM =====================================================
REM التحقق من الملف المصدر
REM =====================================================

echo [%mydate% %mytime%] بدء النشر... >> "%LOG_FILE%"
echo.
echo 1️⃣  جاري التحقق من ملف ZIP...
echo.

if not exist "%SOURCE_ZIP%" (
    echo ❌ خطأ: لم يتم العثور على الملف!
    echo الملف المتوقع: %SOURCE_ZIP%
    echo.
    echo [%mydate% %mytime%] ❌ خطأ: ملف ZIP غير موجود >> "%LOG_FILE%"
    pause
    exit /b 1
) else (
    echo ✓ ملف ZIP موجود: %SOURCE_ZIP%
    for %%A in ("%SOURCE_ZIP%") do (
        set FILE_SIZE=%%~zA
        echo   حجم الملف: !FILE_SIZE! بايت
    )
    echo [%mydate% %mytime%] ✓ ملف ZIP موجود >> "%LOG_FILE%"
)

REM =====================================================
REM فك ضغط الملف
REM =====================================================

echo.
echo 2️⃣  جاري فك ضغط الملف...
echo.

if exist "%TEMP_EXTRACT%" (
    echo   حذف المجلد المؤقت السابق...
    rmdir /s /q "%TEMP_EXTRACT%" >nul 2>&1
)

mkdir "%TEMP_EXTRACT%" >nul 2>&1

REM استخدام PowerShell لفك الضغط
powershell -Command "
\$SourceZip = '%SOURCE_ZIP%'
\$DestinationPath = '%TEMP_EXTRACT%'

try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory(\$SourceZip, \$DestinationPath)
    Write-Host '✓ تم فك الضغط بنجاح'
} catch {
    Write-Host '❌ خطأ في فك الضغط: ' \$_.Exception.Message
    exit 1
}
"

if errorlevel 1 (
    echo ❌ خطأ: فشل فك الضغط!
    echo [%mydate% %mytime%] ❌ خطأ في فك الضغط >> "%LOG_FILE%"
    pause
    exit /b 1
)

echo [%mydate% %mytime%] ✓ تم فك الضغط بنجاح >> "%LOG_FILE%"

REM =====================================================
REM حذف المجلد القديم (اختياري)
REM =====================================================

echo.
echo 3️⃣  جاري حذف النسخة القديمة...
echo.

if exist "%TARGET_DIR%" (
    echo   حذف: %TARGET_DIR%
    rmdir /s /q "%TARGET_DIR%" >nul 2>&1
    echo ✓ تم حذف المجلد القديم
) else (
    echo   المجلد الهدف غير موجود (أول نشر)
)

echo [%mydate% %mytime%] ✓ حذف النسخة القديمة >> "%LOG_FILE%"

REM =====================================================
REM نسخ الملفات الجديدة
REM =====================================================

echo.
echo 4️⃣  جاري نسخ الملفات الجديدة...
echo.

mkdir "%TARGET_DIR%" >nul 2>&1

REM نسخ جميع الملفات من المجلد المستخرج
xcopy "%TEMP_EXTRACT%\*" "%TARGET_DIR%\" /E /I /Y /Q >nul 2>&1

if errorlevel 1 (
    echo ❌ خطأ: فشلت عملية النسخ!
    echo [%mydate% %mytime%] ❌ خطأ في نسخ الملفات >> "%LOG_FILE%"
    pause
    exit /b 1
) else (
    echo ✓ تم نسخ الملفات بنجاح
    echo   الهدف: %TARGET_DIR%
    echo [%mydate% %mytime%] ✓ تم نسخ الملفات بنجاح >> "%LOG_FILE%"
)

REM =====================================================
REM تعيين الصلاحيات (Windows)
REM =====================================================

echo.
echo 5️⃣  جاري تعيين الصلاحيات...
echo.

icacls "%TARGET_DIR%" /grant Everyone:F /T /Q >nul 2>&1

if errorlevel 1 (
    echo ⚠️  تحذير: قد تحتاج صلاحيات أعلى
) else (
    echo ✓ تم تعيين الصلاحيات
)

echo [%mydate% %mytime%] ✓ تم تعيين الصلاحيات >> "%LOG_FILE%"

REM =====================================================
REM تنظيف ملفات مؤقتة
REM =====================================================

echo.
echo 6️⃣  جاري التنظيف...
echo.

if exist "%TEMP_EXTRACT%" (
    rmdir /s /q "%TEMP_EXTRACT%" >nul 2>&1
    echo ✓ تم حذف الملفات المؤقتة
)

echo [%mydate% %mytime%] ✓ تم التنظيف >> "%LOG_FILE%"

REM =====================================================
REM التحقق النهائي
REM =====================================================

echo.
echo 7️⃣  جاري التحقق النهائي...
echo.

if exist "%TARGET_DIR%\index.html" (
    echo ✓ تم العثور على index.html
    echo ✓ النشر نجح بنجاح!
    echo [%mydate% %mytime%] ✓ النشر نجح >> "%LOG_FILE%"
) else (
    echo ❌ خطأ: لم يتم العثور على index.html
    echo [%mydate% %mytime%] ❌ خطأ: index.html غير موجود >> "%LOG_FILE%"
    pause
    exit /b 1
)

REM =====================================================
REM ملخص النشر
REM =====================================================

echo.
echo ╔════════════════════════════════════════════════════════╗
echo ║                   ✅ النشر مكتمل!                      ║
echo ╚════════════════════════════════════════════════════════╝
echo.
echo 📊 الملخص:
echo   ✓ ملف المصدر: %SOURCE_ZIP%
echo   ✓ مجلد الهدف: %TARGET_DIR%
echo   ✓ الحالة: نجح بنجاح
echo   ✓ السجل: %LOG_FILE%
echo.
echo 🌐 للوصول للموقع:
echo   http://localhost:80 (محلياً)
echo   أو: عنوان IP السيرفر
echo.
echo 📝 تم تسجيل العملية في:
echo   %LOG_FILE%
echo.

echo [%mydate% %mytime%] ✅ النشر مكتمل بنجاح >> "%LOG_FILE%"
echo ════════════════════════════════════════════════════════ >> "%LOG_FILE%"

pause
