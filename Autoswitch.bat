@echo off
setlocal
REM ============================================================
REM  Logitech / Astro Auto-Switcher - double-click this file.
REM
REM  Everything (setup, autostart, diagnostics) is in the menu.
REM  -ExecutionPolicy Bypass applies to this process only, so no
REM  system-wide policy change and no administrator rights are
REM  needed.
REM ============================================================
set "SCRIPT=%~dp0AutoSwitch.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo  [ERROR] AutoSwitch.ps1 was not found next to this file.
    echo          Both files must stay in the same folder.
    echo.
    pause
    exit /b 1
)

REM Clear the "downloaded from the internet" mark, if present.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Filter *.ps1 | Unblock-File" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Menu

endlocal
