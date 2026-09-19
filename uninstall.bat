@echo off
REM Itqan ERP - Uninstaller Script
REM ================================

setlocal enabledelayedexpansion

REM Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo يجب تشغيل هذا البرنامج كمسؤول!
    pause
    exit /b 1
)

cls
echo.
echo ╔════════════════════════════════════════╗
echo ║   Itqan ERP - Uninstaller              ║
echo ║     Version 1.0.0                      ║
echo ╚════════════════════════════════════════╝
echo.

REM Set installation directory
set INSTALL_DIR=%ProgramFiles%\Itqan ERP

REM Confirm uninstall
echo هل تريد فعلاً حذف Itqan ERP؟
echo.
set /p CONFIRM="أدخل 'نعم' للمتابعة (Yes to continue): "

if /i not "%CONFIRM%"=="نعم" if /i not "%CONFIRM%"=="yes" (
    echo تم الإلغاء.
    pause
    exit /b 0
)

echo.
echo جاري حذف البرنامج...
timeout /t 2 /nobreak

REM Remove installation directory
if exist "%INSTALL_DIR%" (
    rmdir /s /q "%INSTALL_DIR%"
    echo ✓ تم حذف مجلد التثبيت
)

REM Remove shortcuts
if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Itqan ERP" (
    rmdir /s /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Itqan ERP"
    echo ✓ تم حذف اختصارات القائمة
)

if exist "%USERPROFILE%\Desktop\Itqan ERP.lnk" (
    del "%USERPROFILE%\Desktop\Itqan ERP.lnk"
    echo ✓ تم حذف اختصار سطح المكتب
)

echo.
echo ╔════════════════════════════════════════╗
echo ║  تم الحذف بنجاح!                      ║
echo ║                                        ║
echo ║  تم إزالة جميع ملفات البرنامج         ║
echo ║  شكراً لاستخدام Itqan ERP             ║
echo ╚════════════════════════════════════════╝
echo.

pause
