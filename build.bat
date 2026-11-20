@echo off
setlocal enabledelayedexpansion
REM Build Octopus Rename GUI - requires Lazarus installed at C:\lazarus
REM Usage: build.bat [release]  (release = build + package release zip)
cd /d "%~dp0src"

set "FPC=C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe"
set "WINDRES=C:\lazarus\fpc\3.2.2\bin\x86_64-win64\windres.exe"
REM windres needs cpp (C preprocessor) from the same bin dir on PATH
set "PATH=C:\lazarus\fpc\3.2.2\bin\x86_64-win64;%PATH%"

if not exist "%FPC%" (
  echo ERROR: FPC not found at "%FPC%"
  pause
  exit /b 1
)

REM ---- Read APP_VERSION from version.inc (single source of truth) ----
set "APP_VERSION="
for /f "tokens=2 delims='" %%v in ('findstr /b "APP_VERSION" version.inc') do set "APP_VERSION=%%v"
if not defined APP_VERSION (
  echo ERROR: cannot read APP_VERSION from src\version.inc
  pause
  exit /b 1
)
for /f "tokens=1-3 delims=." %%a in ("%APP_VERSION%") do (
  set "VER_MAJOR=%%a"
  set "VER_MINOR=%%b"
  set "VER_PATCH=%%c"
)

REM ---- VERSIONINFO resource: exe properties show version info ----
> versioninfo.rc echo 1 VERSIONINFO
>> versioninfo.rc echo FILEVERSION !VER_MAJOR!,!VER_MINOR!,!VER_PATCH!,0
>> versioninfo.rc echo PRODUCTVERSION !VER_MAJOR!,!VER_MINOR!,!VER_PATCH!,0
>> versioninfo.rc echo FILEOS 0x40004L
>> versioninfo.rc echo FILETYPE 0x1L
>> versioninfo.rc echo BEGIN
>> versioninfo.rc echo   BLOCK "StringFileInfo"
>> versioninfo.rc echo   BEGIN
>> versioninfo.rc echo     BLOCK "040904B0"
>> versioninfo.rc echo     BEGIN
>> versioninfo.rc echo       VALUE "CompanyName", "Octopus Rename"
>> versioninfo.rc echo       VALUE "FileDescription", "Octopus Rename - batch rename tool"
>> versioninfo.rc echo       VALUE "FileVersion", "%APP_VERSION%.0"
>> versioninfo.rc echo       VALUE "InternalName", "fprename_gui"
>> versioninfo.rc echo       VALUE "OriginalFilename", "fprename_gui.exe"
>> versioninfo.rc echo       VALUE "ProductName", "Octopus Rename"
>> versioninfo.rc echo       VALUE "ProductVersion", "%APP_VERSION%"
>> versioninfo.rc echo     END
>> versioninfo.rc echo   END
>> versioninfo.rc echo   BLOCK "VarFileInfo"
>> versioninfo.rc echo   BEGIN
>> versioninfo.rc echo     VALUE "Translation", 0x409, 0x04B0
>> versioninfo.rc echo   END
>> versioninfo.rc echo END
"%WINDRES%" -i versioninfo.rc -o versioninfo.res

REM ---- Manifest resource: inject version from manifest_clean.rc template ----
(for /f "usebackq delims=" %%L in ("manifest_clean.rc") do (
  set "LINE=%%L"
  echo !LINE:@APPVER@=%APP_VERSION%!
)) > manifest_gen.rc
"%WINDRES%" -i manifest_gen.rc -o fprename_gui.res

REM Application icon (MAINICON): exe / taskbar / title bar
"%WINDRES%" -i appicon.rc -o appicon.res

if not exist ..\bin mkdir ..\bin
if not exist lib mkdir lib

"%FPC%" -O2 -Sh -WG -FUlib -FE..\bin ^
  -FuC:\lazarus\lcl\units\x86_64-win64 ^
  -FuC:\lazarus\lcl\units\x86_64-win64\win32 ^
  -FuC:\lazarus\components\lazutils\lib\x86_64-win64 ^
  -FuC:\lazarus\fpc\3.2.2\units\x86_64-win64\regexpr ^
  fprename_gui.lpr

if not exist ..\bin\fprename_gui.exe (
  echo BUILD FAILED
  pause
  exit /b 1
)
echo BUILD OK: bin\fprename_gui.exe  v%APP_VERSION%

REM ---- Package release zip: release\OctopusRename-v<version>-win64.zip ----
if /i "%~1"=="release" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\package.ps1" -Version "%APP_VERSION%"
  if errorlevel 1 (
    echo PACKAGE FAILED
    pause
    exit /b 1
  )
)
pause
