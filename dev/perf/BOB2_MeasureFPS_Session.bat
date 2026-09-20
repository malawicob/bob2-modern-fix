@echo off
REM  BOB2_MeasureFPS_Session.bat [label]
REM  Records the WHOLE game session: arm it, start the game, fly, quit.
REM  PresentMon stops by itself when Bob.exe exits. The analysis keeps the
REM  minute of flying before the last ten seconds, so it does not matter how
REM  long the menus took or how short the flight was. Self-elevates.
setlocal enabledelayedexpansion
set TOOL=D:\BOB2 Files\tools\PresentMon.exe
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    exit /b
)
set LABEL=%~1
if "%LABEL%"=="" set LABEL=run
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%t
set OUT=%~dp0fps_%LABEL%_%STAMP%.csv
echo.
echo ============================================================
echo  ARMED for label %LABEL%. Start the game, fly, quit as normal.
echo  Recording stops by itself when the game closes.
echo ============================================================
"%TOOL%" --process_name Bob.exe --output_file "%OUT%" --terminate_on_proc_exit --stop_existing_session
echo Done: %OUT%
timeout /t 5 >nul
