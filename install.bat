@echo off
REM Itqan ERP - Simple Installer Script
REM ====================================

setlocal enabledelayedexpansion

REM Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo يجب تشغيل هذا البرنامج كمسؤول!
    echo Right-click and select "Run as administrator"
    pause
    exit /b 1
)

cls
echo.
echo ╔════════════════════════════════════════╗
echo ║     Itqan ERP - Windows Installer      ║
echo ║          Version 1.0.0                 ║
echo ╚════════════════════════════════════════╝
echo.

REM Set installation directory
set INSTALL_DIR=%ProgramFiles%\Itqan ERP
echo تثبيت في: %INSTALL_DIR%
echo.

REM Create installation directory
if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
    echo ✓ تم إنشاء مجلد التثبيت
) else (
    echo ✓ مجلد التثبيت موجود
)

REM Copy application files
echo.
echo جاري نسخ الملفات...
if exist "build\windows\x64\runner\Release" (
    xcopy "build\windows\x64\runner\Release\*.*" "%INSTALL_DIR%\" /E /I /Y /Q
    echo ✓ تم نسخ الملفات بنجاح
) else (
    echo ✗ خطأ: لم يتم العثور على ملفات التطبيق!
    pause
    exit /b 1
)

REM Create Start Menu shortcut
echo.
echo جاري إنشاء اختصارات...
set SHORTCUT_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Itqan ERP
if not exist "%SHORTCUT_DIR%" mkdir "%SHORTCUT_DIR%"

REM Create shortcuts using PowerShell
powershell -Command ^
    "$WshShell = New-Object -ComObject WScript.Shell; ^
    $Shortcut = $WshShell.CreateShortcut('%SHORTCUT_DIR%\Itqan ERP.lnk'); ^
    $Shortcut.TargetPath = '%INSTALL_DIR%\kinetic_enterprise.exe'; ^
    $Shortcut.WorkingDirectory = '%INSTALL_DIR%'; ^
    $Shortcut.IconLocation = '%INSTALL_DIR%\kinetic_enterprise.exe'; ^
    $Shortcut.Save()"

REM Create desktop shortcut
powershell -Command ^
    "$WshShell = New-Object -ComObject WScript.Shell; ^
    $Shortcut = $WshShell.CreateShortcut('%USERPROFILE%\Desktop\Itqan ERP.lnk'); ^
    $Shortcut.TargetPath = '%INSTALL_DIR%\kinetic_enterprise.exe'; ^
    $Shortcut.WorkingDirectory = '%INSTALL_DIR%'; ^
    $Shortcut.IconLocation = '%INSTALL_DIR%\kinetic_enterprise.exe'; ^
    $Shortcut.Save()"

echo ✓ تم إنشاء الاختصارات

REM Create uninstaller script
echo.
echo جاري إنشاء أداة إلغاء التثبيت...
(
    echo @echo off
    echo cls
    echo echo.
    echo echo حذف Itqan ERP...
    echo timeout /t 2 /nobreak
    echo rmdir /s /q "%INSTALL_DIR%"
    echo del "%%APPDATA%%\Microsoft\Windows\Start Menu\Programs\Itqan ERP\*.*"
    echo rmdir "%%APPDATA%%\Microsoft\Windows\Start Menu\Programs\Itqan ERP"
    echo del "%%USERPROFILE%%\Desktop\Itqan ERP.lnk"
    echo echo ✓ تم حذف البرنامج بنجاح
    echo pause
) > "%INSTALL_DIR%\uninstall.bat"

echo ✓ تم إنشاء أداة إلغاء التثبيت

REM Complete message
echo.
echo ╔════════════════════════════════════════╗
echo ║  تم التثبيت بنجاح!                    ║
echo ║                                        ║
echo ║  ✓ التطبيق:  %INSTALL_DIR%            ║
echo ║  ✓ البداية السريعة متوفرة               ║
echo ║  ✓ اختصار سطح المكتب متوفر              ║
echo ║                                        ║
echo ║  جاري تشغيل البرنامج...              ║
echo ╚════════════════════════════════════════╝
echo.

REM Launch application
start "" "%INSTALL_DIR%\kinetic_enterprise.exe"

pause
