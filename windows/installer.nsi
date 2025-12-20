; NSIS Installer Script for Another IPTV Player
; This script creates a Windows installer that installs the application
; to Program Files and creates shortcuts.

;--------------------------------
; Includes

!define APP_EXE "iptv_player.exe"

!include "MUI2.nsh"
!include "FileFunc.nsh"

;--------------------------------
; General

; Name and file
Name "Another IPTV Player"
OutFile "another-iptv-player-windows-setup.exe"
Unicode True

; Default installation folder
InstallDir "$PROGRAMFILES64\Another IPTV Player"

; Get installation folder from registry if available
InstallDirRegKey HKCU "Software\Another IPTV Player" ""

; Request application privileges for Windows Vista/7/8/10/11
RequestExecutionLevel admin

; Version information
VIProductVersion "1.3.0.0"
VIAddVersionKey "ProductName" "Another IPTV Player"
VIAddVersionKey "Comments" "A modern IPTV player application"
VIAddVersionKey "CompanyName" "Another IPTV Player"
VIAddVersionKey "LegalCopyright" "Copyright © 2025"
VIAddVersionKey "FileDescription" "Another IPTV Player Installer"
VIAddVersionKey "FileVersion" "1.3.0.0"
VIAddVersionKey "ProductVersion" "1.3.0.0"

;--------------------------------
; Interface Settings

!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"

;--------------------------------
; Pages

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "license.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

;--------------------------------
; Languages

!insertmacro MUI_LANGUAGE "English"

;--------------------------------
; Installer Sections

Section "Another IPTV Player" SecMain

  SectionIn RO
  
  ; Set output path to the installation directory

  SetOutPath "$INSTDIR"

  ; 1) Önce Release kökünde exe var mı?
  IfFileExists "..\build\windows\x64\runner\Release\${APP_EXE}" 0 +3
    File /r /x "*.pdb" "..\build\windows\x64\runner\Release\*"
    Goto +3
  
  ; 2) Yoksa Release altında oluşan klasörün içeriğini al (senin senaryo)
  File /r /x "*.pdb" "..\build\windows\x64\runner\Release\another-iptv-player-windows-*\*"



  
  ; Store installation folder
  WriteRegStr HKCU "Software\Another IPTV Player" "" $INSTDIR
  
  ; Create uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  
  ; Add to Add/Remove Programs
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
                   "DisplayName" "Another IPTV Player"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
  "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
                   "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
                 "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
                   "Publisher" "Another IPTV Player"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
                   "DisplayVersion" "1.3.0"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
                     "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player" \
                     "NoRepair" 1

SectionEnd

Section "Start Menu Shortcuts" SecStartMenu

  ; Create shortcuts
  CreateDirectory "$SMPROGRAMS\Another IPTV Player"
  CreateShortcut "$SMPROGRAMS\Another IPTV Player\Another IPTV Player.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\Another IPTV Player\Uninstall.lnk" "$INSTDIR\Uninstall.exe"

SectionEnd

Section "Desktop Shortcut" SecDesktop

  CreateShortcut "$DESKTOP\Another IPTV Player.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0


SectionEnd

;--------------------------------
; Descriptions

; Language strings
LangString DESC_SecMain ${LANG_ENGLISH} "Install Another IPTV Player application files."
LangString DESC_SecStartMenu ${LANG_ENGLISH} "Create Start Menu shortcuts."
LangString DESC_SecDesktop ${LANG_ENGLISH} "Create a desktop shortcut."

; Assign language strings to sections
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} $(DESC_SecMain)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStartMenu} $(DESC_SecStartMenu)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_SecDesktop)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

;--------------------------------
; Uninstaller Section

Section "Uninstall"

  ; Remove files and uninstaller
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"
  
  ; Remove shortcuts, if any
  Delete "$SMPROGRAMS\Another IPTV Player\Another IPTV Player.lnk"
  Delete "$SMPROGRAMS\Another IPTV Player\Uninstall.lnk"
  RMDir "$SMPROGRAMS\Another IPTV Player"
  Delete "$DESKTOP\Another IPTV Player.lnk"
  
  ; Remove registry keys
  DeleteRegKey /ifempty HKCU "Software\Another IPTV Player"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Another IPTV Player"

SectionEnd

