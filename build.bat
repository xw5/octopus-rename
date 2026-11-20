@echo off
REM Build Octopus File GUI - requires Lazarus installed at C:\lazarus
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

REM Regenerate form manifest resource if missing
if not exist fprename_gui.res "%WINDRES%" -i manifest_clean.rc -o fprename_gui.res

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

if exist ..\bin\fprename_gui.exe (echo BUILD OK: bin\fprename_gui.exe) else (echo BUILD FAILED)
pause
