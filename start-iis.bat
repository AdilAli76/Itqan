@echo off
REM =====================================================
REM Itqan ERP - IIS Startup Script
REM =====================================================
REM
REM الغرض: تشغيل موقع الويب في IIS
REM الدومين: https://erp.droob-albayan.ly/app
REM المسار: C:\kinetic
REM
REM =====================================================

setlocal enabledelayedexpansion

cls
echo.
echo ╔════════════════════════════════════════════════════════╗
echo ║                                                        ║
echo ║    Itqan ERP - IIS Startup Script                     ║
echo ║    سكريبت تشغيل IIS                                    ║
echo ║                                                        ║
echo ╚════════════════════════════════════════════════════════╝
echo.

REM =====================================================
REM التحقق من صلاحيات Admin
REM =====================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ❌ خطأ: يجب تشغيل السكريبت كمسؤول!
    echo.
    echo الحل:
    echo 1. انقر بزر الفأرة الأيمن على هذا الملف
    echo 2. اختر "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo ✓ صلاحيات Admin موجودة
echo.

REM =====================================================
REM الخطوة 1: التحقق من وجود مجلد الموقع
REM =====================================================

echo 1️⃣  التحقق من مجلد الموقع...
echo.

if not exist "C:\kinetic" (
    echo ❌ خطأ: لم يتم العثور على المجلد C:\kinetic
    echo.
    echo الحل:
    echo 1. تأكد من نشر الملفات على C:\kinetic
    echo 2. شغّل deploy.bat أولاً
    echo.
    pause
    exit /b 1
) else (
    echo ✓ المجلد موجود: C:\kinetic
)

if not exist "C:\kinetic\index.html" (
    echo ❌ خطأ: لم يتم العثور على index.html
    echo.
    pause
    exit /b 1
) else (
    echo ✓ ملف index.html موجود
)

echo.

REM =====================================================
REM الخطوة 2: إعادة تشغيل IIS
REM =====================================================

echo 2️⃣  إعادة تشغيل IIS...
echo.

iisreset /restart /noforce

if %errorLevel% equ 0 (
    echo ✓ تم إعادة تشغيل IIS بنجاح
) else (
    echo ❌ خطأ في إعادة تشغيل IIS
    echo.
    pause
    exit /b 1
)

echo.

REM =====================================================
REM الخطوة 3: فتح الموقع في المتصفح
REM =====================================================

echo 3️⃣  فتح الموقع في المتصفح...
echo.

timeout /t 3 /nobreak

REM افتح الرابط
start https://erp.droob-albayan.ly/app

echo ✓ تم فتح الموقع
echo.

REM =====================================================
REM ملخص البدء
REM =====================================================

echo ╔════════════════════════════════════════════════════════╗
echo ║               ✅ تم التشغيل بنجاح!                     ║
echo ╚════════════════════════════════════════════════════════╝
echo.
echo 🌐 الموقع متاح على:
echo    https://erp.droob-albayan.ly/app
echo.
echo 📂 مسار الملفات:
echo    C:\kinetic
echo.
echo 🔍 للتحقق من الحالة:
echo    iisreset /status
echo.
echo 🛑 لإيقاف الموقع:
echo    iisreset /stop
echo.
echo 🚀 لإعادة التشغيل:
echo    iisreset /restart
echo.

pause
