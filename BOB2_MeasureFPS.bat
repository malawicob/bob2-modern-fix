@echo off
REM ============================================================
REM  BOB2 FPS measurement - captures real frame data to CSV
REM  Part of BOB2 Windows 10/11 Fix v1.5.0
REM ============================================================
REM
REM  >>> YOU DO NOT ALT-TAB. <<<
REM
REM  Earlier versions of this script told you to start the game, get
REM  airborne, then Alt-Tab out to start the capture and Alt-Tab back.
REM  That is bad advice for this game: with dgVoodoo2 in exclusive
REM  fullscreen, Alt-Tab loses the D3D9 device and BOB2 does not survive
REM  the reset - it crashes to desktop. Measuring the frame rate must
REM  never require leaving the cockpit.
REM
REM  So the capture is ARMED BEFORE OR DURING PLAY and TRIGGERED FROM
REM  INSIDE THE GAME. PresentMon registers a system-wide hotkey, which
REM  Windows delivers before the game ever sees the keystroke.
REM
REM  Usage:  BOB2_MeasureFPS.bat [label] [hotkey^|timed] [seconds]
REM
REM    hotkey  (default)  Arms and waits. Press ALT+SHIFT+F11 in the
REM                       cockpit to record 60 seconds. Scroll Lock
REM                       lights up while recording and goes out when
REM                       it finishes, so you get feedback without
REM                       looking away from the game.
REM    timed              Records automatically N seconds from now
REM                       (default 120), for 60 seconds. Use this if
REM                       the hotkey is awkward on your keyboard.
REM
REM  ALT+SHIFT+F11 was chosen because it is unbound in this install.
REM  F11 alone is IMPACTTOG, SHIFT+F11 is FOV_LARGE and CTRL+F11 is
REM  WINAMP_STOP, so any of those would have stolen a game function -
REM  Windows consumes a registered hotkey and never passes it on.
REM
REM  Examples:
REM    BOB2_MeasureFPS.bat
REM    BOB2_MeasureFPS.bat density2
REM    BOB2_MeasureFPS.bat density2 timed 180
REM ============================================================

setlocal enabledelayedexpansion
REM  PresentMon is Intel's and is a separate download - not shipped here.
REM  Look where a user would sensibly put it instead of one hardcoded path.
set TOOL=
if exist "%~dp0tools\PresentMon.exe" set TOOL=%~dp0tools\PresentMon.exe
if not defined TOOL if exist "%~dp0PresentMon.exe" set TOOL=%~dp0PresentMon.exe
if not defined TOOL if exist "%~dp0..\tools\PresentMon.exe" set TOOL=%~dp0..\tools\PresentMon.exe
if not defined TOOL if exist "D:\BOB2 Files\tools\PresentMon.exe" set TOOL=D:\BOB2 Files\tools\PresentMon.exe
if not defined TOOL set TOOL=%~dp0tools\PresentMon.exe
set CAPTURE_KEY=ALT+SHIFT+F11
set DURATION=60

REM --- self-elevate: PresentMon needs admin to open an ETW trace session ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights ^(needed to trace Bob.exe^)...
    REM  Only pass arguments we actually got. Start-Process REJECTS an
    REM  ArgumentList containing empty strings, which would make the elevated
    REM  window fail to open at all.
    set "ELEVARGS="
    if not "%~1"=="" set "ELEVARGS='%~1'"
    if not "%~2"=="" set "ELEVARGS='%~1','%~2'"
    if not "%~3"=="" set "ELEVARGS='%~1','%~2','%~3'"
    if "!ELEVARGS!"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList !ELEVARGS! -Verb RunAs"
    )
    exit /b
)

set LABEL=%~1
if "%LABEL%"=="" set LABEL=run
set MODE=%~2
if "%MODE%"=="" set MODE=hotkey
set DELAY=%~3
if "%DELAY%"=="" set DELAY=120

if not exist "%TOOL%" (
    echo ERROR: PresentMon was not found.
    echo   Put PresentMon.exe in:  %~dp0tools\
    echo Download it from https://github.com/GameTechDev/PresentMon/releases
    pause
    exit /b 1
)

REM --- timestamp so nothing is ever overwritten ---
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set STAMP=%%t
set OUT=%~dp0fps_%LABEL%_%STAMP%.csv

echo.
echo ============================================================
if /I "%MODE%"=="timed" (
    echo  TIMED CAPTURE
    echo.
    echo  Recording starts in %DELAY% seconds and runs for %DURATION%.
    echo  Get into a mission and be FLYING before it starts - a capture
    echo  taken at a menu measures nothing, because the menu barely
    echo  renders.
) else (
    echo  ARMED - WAITING FOR YOUR HOTKEY
    echo.
    echo  Go and fly. When you are in the cockpit and the scene looks
    echo  representative, press:
    echo.
    echo         %CAPTURE_KEY%
    echo.
    echo  Scroll Lock lights up while it records %DURATION% seconds,
    echo  then goes out. You never need to leave the game.
)
echo.
echo  DO NOT ALT-TAB. This game crashes when it loses the display.
echo  Leave this window behind the game; it closes itself.
echo ============================================================
echo.

if /I "%MODE%"=="timed" (
    "%TOOL%" --process_name Bob.exe --output_file "%OUT%" --delay %DELAY% --timed %DURATION% --terminate_after_timed --scroll_indicator --stop_existing_session
) else (
    "%TOOL%" --process_name Bob.exe --output_file "%OUT%" --hotkey %CAPTURE_KEY% --timed %DURATION% --terminate_after_timed --scroll_indicator --stop_existing_session
)

echo.
if not exist "%OUT%" (
    echo No data was captured.
    echo   - In hotkey mode, this means the hotkey was never pressed.
    echo   - Otherwise the game may not have been rendering.
    pause
    exit /b 1
)

REM --- sanity check: count captured frames ---
set COUNT=0
for /f %%c in ('find /c /v "" ^< "%OUT%"') do set COUNT=%%c
set /a FRAMES=!COUNT!-1

echo Captured !FRAMES! frames.
if !FRAMES! LSS 200 (
    echo.
    echo ============================================================
    echo  WARNING: too few frames for a meaningful result.
    echo  A good %DURATION%-second capture in flight is 1500-6000
    echo  frames. This looks like the game was at a menu, paused, or
    echo  the capture was cut short. Please redo it while flying.
    echo ============================================================
) else (
    echo Looks good.
)
echo.
echo Saved to:
echo   %OUT%
echo.
pause
