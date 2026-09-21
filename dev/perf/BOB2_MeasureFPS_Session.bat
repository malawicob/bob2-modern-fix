@echo off
REM  BOB2_MeasureFPS_Session.bat [label]
REM  Records the WHOLE game session: arm it, start the game, fly, quit.
REM  PresentMon is started in the background; this window then waits for
REM  Bob.exe to appear and to go away again, and stops the recording itself,
REM  so the capture file is released the moment the game closes. (PresentMon's
REM  own --terminate_on_proc_exit did not let go of the file.) Self-elevates.
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
"%TOOL%" --terminate_existing_session >nul 2>&1
echo.
echo ============================================================
echo  ARMED for label %LABEL%. Start the game, fly, quit as normal.
echo  This window closes by itself a few seconds after the game.
echo ============================================================
start "" /b "%TOOL%" --process_name Bob.exe --output_file "%OUT%" --stop_existing_session
:waitstart
timeout /t 2 /nobreak >nul
tasklist /FI "IMAGENAME eq Bob.exe" 2>nul | find /I "Bob.exe" >nul
if errorlevel 1 goto waitstart
echo  Game seen. Recording.
:waitend
timeout /t 2 /nobreak >nul
tasklist /FI "IMAGENAME eq Bob.exe" 2>nul | find /I "Bob.exe" >nul
if not errorlevel 1 goto waitend
echo  Game closed. Stopping the recording.
"%TOOL%" --terminate_existing_session >nul 2>&1
timeout /t 3 /nobreak >nul
echo  Done: %OUT%
timeout /t 3 /nobreak >nul
