@echo off
setlocal
REM ============================================================
REM  Logitech / Astro A50 Auto-Audio Switcher - launcher
REM
REM  Double-click this file to run the switcher.
REM  No need to change the PowerShell execution policy: the
REM  -ExecutionPolicy Bypass flag below applies to this process
REM  only and does not require administrator rights.
REM ============================================================

set "SCRIPT=%~dp0AutoSwitch.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo  [ERROR] AutoSwitch.ps1 was not found next to this launcher.
    echo          Keep both files in the same folder.
    echo.
    pause
    exit /b 1
)

REM Remove the "downloaded from the internet" mark, if present.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Filter *.ps1 | Unblock-File" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*

echo.
echo  The switcher has stopped.
pause
