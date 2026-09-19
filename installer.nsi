; Itqan ERP - Windows Installer Script
; ====================================

!include "MUI2.nsh"

; ====== البيانات الأساسية ======
Name "Itqan ERP"
OutFile "ItqanERP-Setup-v1.0.0.exe"
InstallDir "$PROGRAMFILES\Itqan ERP"
InstallDirRegKey HKCU "Software\Itqan ERP" "Install_Dir"

; ====== إعدادات MUI ======
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "Arabic"

; ====== البيانات الوصفية ======
VIProductVersion "1.0.0.0"
VIAddVersionKey /LANG=1033 "ProductName" "Itqan ERP"
VIAddVersionKey /LANG=1033 "Comments" "نظام Itqan ERP المتكامل"
VIAddVersionKey /LANG=1033 "CompanyName" "Itqan Inc."
VIAddVersionKey /LANG=1033 "FileDescription" "برنامج إدارة المشاريع المتكامل"
VIAddVersionKey /LANG=1033 "FileVersion" "1.0.0.0"
VIAddVersionKey /LANG=1033 "ProductVersion" "1.0.0.0"
VIAddVersionKey /LANG=1033 "LegalCopyright" "© 2026 Itqan Inc."
VIAddVersionKey /LANG=1033 "OriginalFilename" "ItqanERP-Setup-v1.0.0.exe"

; ====== قسم التثبيت ======
Section "Install"
  SetOutPath "$INSTDIR"

  ; نسخ جميع الملفات من Release folder
  File /r "build\windows\x64\runner\Release\*.*"

  ; إنشاء اختصار في Start Menu
  CreateDirectory "$SMPROGRAMS\Itqan ERP"
  CreateShortCut "$SMPROGRAMS\Itqan ERP\Itqan ERP.lnk" "$INSTDIR\kinetic_enterprise.exe"
  CreateShortCut "$SMPROGRAMS\Itqan ERP\Uninstall.lnk" "$INSTDIR\uninstall.exe"

  ; إنشاء اختصار على سطح المكتب
  CreateShortCut "$DESKTOP\Itqan ERP.lnk" "$INSTDIR\kinetic_enterprise.exe"

  ; كتابة معلومات التثبيت في Registry
  WriteRegStr HKCU "Software\Itqan ERP" "Install_Dir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Itqan ERP" "DisplayName" "Itqan ERP v1.0.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Itqan ERP" "DisplayVersion" "1.0.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Itqan ERP" "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Itqan ERP" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Itqan ERP" "Publisher" "Itqan Inc."

  ; إنشاء ملف uninstall
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; رسالة النجاح
  MessageBox MB_OK "تم تثبيت Itqan ERP بنجاح!$\n$\nانقر OK لبدء البرنامج."
  Exec "$INSTDIR\kinetic_enterprise.exe"
SectionEnd

; ====== قسم إلغاء التثبيت ======
Section "Uninstall"
  ; حذف الملفات
  RMDir /r "$INSTDIR"

  ; حذف اختصارات Start Menu
  RMDir /r "$SMPROGRAMS\Itqan ERP"

  ; حذف اختصار سطح المكتب
  Delete "$DESKTOP\Itqan ERP.lnk"

  ; حذف Registry entries
  DeleteRegKey HKCU "Software\Itqan ERP"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Itqan ERP"

  MessageBox MB_OK "تم حذف Itqan ERP بنجاح."
SectionEnd

; ====== التحقق من الإدارة ======
Function .onInit
  ; التحقق من صلاحيات المسؤول
  UserInfo::GetAccountType
  Pop $0
  ${If} $0 != "admin"
    MessageBox MB_OK "يجب أن تقوم بتشغيل المثبّت كمسؤول!"
    Quit
  ${EndIf}
FunctionEnd
