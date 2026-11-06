@echo off
REM CleverHttpTunnel — build + run DUnitX (Win32 Debug default; optional win64).
setlocal
cd /d "%~dp0"

call "C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat"
if errorlevel 1 (
  echo FAIL: rsvars.bat
  exit /b 1
)

REM After rsvars — it may clear/override PLATFORM.
set "PLATFORM=Win32"
if /I "%~1"=="win64" set "PLATFORM=Win64"

msbuild "test\projects\D113\Test.dproj" /t:Build /p:Config=Debug /p:Platform=%PLATFORM% /v:minimal
if errorlevel 1 (
  echo FAIL: msbuild Test.dproj %PLATFORM%
  exit /b 1
)

set "TEST_EXE=test\projects\D113\%PLATFORM%\Debug\Test.exe"
if not exist "%TEST_EXE%" (
  echo FAIL: missing %TEST_EXE%
  exit /b 1
)

"%TEST_EXE%"
set "ERR=%ERRORLEVEL%"
exit /b %ERR%
