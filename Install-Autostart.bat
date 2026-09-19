@echo off
setlocal
REM ============================================================
REM  Installs (or removes) a hidden scheduled task that starts
REM  the switcher automatically at logon.
REM
REM  Run the switcher once first, so the configuration wizard
REM  can complete - a hidden task cannot show prompts.
REM
REM  No administrator rights required.
REM ============================================================

set "SCRIPT=%~dp0AutoSwitch.ps1"
set "TASKNAME=Astro A50 AutoSwitch"

if not exist "%SCRIPT%" (
    echo.
    echo  [ERROR] AutoSwitch.ps1 was not found next to this launcher.
    echo.
    pause
    exit /b 1
)

echo.
echo  ====================================================
echo    Astro A50 AutoSwitch - autostart setup
echo  ====================================================
echo.
echo    [1] Enable autostart at logon
echo    [2] Disable autostart
echo    [3] Cancel
echo.
set /p "CHOICE=  Selection: "

if "%CHOICE%"=="2" goto :remove
if "%CHOICE%"=="1" goto :install
goto :end

:install
if not exist "%~dp0A50-AutoSwitch.config.json" (
    echo.
    echo  [!] No configuration file found.
    echo      Run Start-AutoSwitch.bat first and complete the wizard,
    echo      otherwise the hidden task will have nothing to load.
    echo.
    pause
    goto :end
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File \"' + '%SCRIPT%' + '\"');" ^
  "$t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME;" ^
  "$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -Hidden;" ^
  "$p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited;" ^
  "Register-ScheduledTask -TaskName '%TASKNAME%' -Action $a -Trigger $t -Settings $s -Principal $p -Force | Out-Null;" ^
  "Write-Host '  [OK] Autostart enabled.' -ForegroundColor Green"

echo.
echo  The switcher will start automatically the next time you log in.
echo  To stop it now, end 'powershell.exe' in Task Manager.
echo.
pause
goto :end

:remove
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Unregister-ScheduledTask -TaskName '%TASKNAME%' -Confirm:$false -ErrorAction SilentlyContinue;" ^
  "Write-Host '  [OK] Autostart removed.' -ForegroundColor Green"
echo.
pause
goto :end

:end
endlocal
