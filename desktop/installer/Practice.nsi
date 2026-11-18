; The Windows installer for Practice (desktop/scripts/build.ps1 runs makensis with VERSION, STAGE and OUT).
; Installs for this user only (no administrator rights, nothing outside the user's own folders): the program in
; %LOCALAPPDATA%\Programs\Practice, a Start menu and a desktop shortcut, and an uninstaller listed in Apps.
; The app's own updater runs it silently with /S /UPDATE; then the app is started again when it is done.
Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"

Name "Practice"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\Practice"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "Practice ${VERSION}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "Practice"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "Caulfield Engineering"
VIAddVersionKey "FileDescription" "Practice for Windows"

!define MUI_ICON "${STAGE}\icon.ico"
!define MUI_UNICON "${STAGE}\icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\Practice.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open Practice"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

!define UNINST "Software\Microsoft\Windows\CurrentVersion\Uninstall\Practice"

Section "Practice"
  ; the app closes itself before an update; give it a moment, then make sure
  Sleep 1200
  nsExec::Exec 'taskkill /IM Practice.exe /F'
  SetOutPath "$INSTDIR"
  File "${STAGE}\Practice.exe"
  File "${STAGE}\icon.ico"
  RMDir /r "$INSTDIR\resources"
  SetOutPath "$INSTDIR\resources"
  File /r "${STAGE}\resources\*.*"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\Practice.lnk" "$INSTDIR\Practice.exe" "" "$INSTDIR\icon.ico"
  CreateShortcut "$DESKTOP\Practice.lnk" "$INSTDIR\Practice.exe" "" "$INSTDIR\icon.ico"
  WriteRegStr HKCU "${UNINST}" "DisplayName" "Practice"
  WriteRegStr HKCU "${UNINST}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST}" "Publisher" "Caulfield Engineering"
  WriteRegStr HKCU "${UNINST}" "DisplayIcon" "$INSTDIR\icon.ico"
  WriteRegStr HKCU "${UNINST}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINST}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST}" "NoRepair" 1
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/UPDATE" $1
  IfErrors +2 0
    Exec '"$INSTDIR\Practice.exe"'
SectionEnd

Section "Uninstall"
  nsExec::Exec 'taskkill /IM Practice.exe /F'
  Delete "$SMPROGRAMS\Practice.lnk"
  Delete "$DESKTOP\Practice.lnk"
  RMDir /r "$INSTDIR\resources"
  Delete "$INSTDIR\Practice.exe"
  Delete "$INSTDIR\icon.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "${UNINST}"
  ; his runs and settings stay in %APPDATA%\Practice (and every run is on the drill server too)
SectionEnd
