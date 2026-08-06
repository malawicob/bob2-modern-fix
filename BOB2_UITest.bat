@echo off
REM ============================================================
REM  BOB2 menu-rescale PROTOTYPE
REM  Part of BOB2 Windows 10/11 Fix v1.5.0
REM ============================================================
REM
REM  This is an EXPERIMENT, not a fix. It answers one question:
REM  when the dialog templates are rescaled, does the artwork
REM  inside the controls scale with them?
REM
REM  Bob.exe is NOT touched. Patched copies were made:
REM
REM    Bob_ui110.exe   every dialog 1.10x larger, font 8 -> 9pt
REM                    (largest page 1149 -> 1264 px, which still
REM                     fits a 1280-wide campaign resolution)
REM    Bob_ui080.exe   every dialog 0.80x smaller, font 8 -> 6pt
REM                    (largest page 1149 -> 919 px)
REM
REM  The patch is in place: every coordinate in a dialog template
REM  is a fixed-width 16-bit field, so nothing was resized, no
REM  section rebuilt and no address moved. Both copies are exactly
REM  the same length as the original and all 154 templates still
REM  parse with unchanged control counts.
REM
REM  WHAT TO LOOK FOR
REM    The control FRAMES will change size - that part is certain.
REM    The question is the content:
REM      * If text and artwork scale with the frames, rescaling is
REM        a viable route to menus that fit any resolution.
REM      * If the frames grow but the text and button art stay the
REM        same size - leaving gaps, or overflowing at 0.80x - then
REM        rescaling alone cannot fix the menus.
REM
REM    Static analysis predicts the second outcome: none of the 11
REM    Rowan OCX controls imports StretchBlt, only BitBlt, which is
REM    a 1:1 pixel copy; and their artwork and font are selected by
REM    NUMBER (PictureFileNum, NormalFileNum, FontNum) rather than
REM    derived from the control size. This run is to confirm or
REM    refute that.
REM
REM  Just double-click it and pick from the menu. You can also pass
REM  the variant directly:  BOB2_UITest.bat 102
REM
REM    110    everything 1.10x, font 8 -> 9pt
REM    080    everything 0.80x, font 8 -> 6pt
REM    102    everything 1.02x, font unchanged at 8pt (2% - the
REM           smallest visible change; if even this goes blank then
REM           the control art depends on an EXACT size and rescaling
REM           is a dead end)
REM    GEOM   coordinates 1.10x, font left at 8pt
REM    FONT   font 8 -> 9pt only, every coordinate untouched
REM
REM  GEOM and FONT exist to isolate which of the two changes causes
REM  the blank screen, since the first attempt (110, which changed
REM  both) rendered white.
REM
REM  TO GO BACK: nothing to undo. Bob.exe is untouched; just start
REM  the game normally from the launcher. Delete Bob_ui110.exe and
REM  Bob_ui080.exe whenever you like.
REM
REM  NOTE ON WHERE THIS RUNS FROM
REM    Earlier versions assumed the game folder was the parent of
REM    this script. That is wrong when the script is run from a
REM    copy of the source tree - and CMD cannot use a UNC path
REM    (\\wsl.localhost\...) as a working directory at all, so it
REM    silently falls back to the Windows directory first. This
REM    version searches for the game instead of assuming.
REM ============================================================

setlocal enabledelayedexpansion
set WHICH=%~1

REM Double-clicking a .bat passes no arguments, so asking the user to run
REM "BOB2_UITest.bat 102" was useless advice. Ask instead when nothing is
REM given; the argument form still works for repeat runs.
if "%WHICH%"=="" (
    echo.
    echo ============================================================
    echo   BOB2 MENU RESCALE - which build do you want to try?
    echo ============================================================
    echo.
    echo   1.  1.02x  2%% bigger, font unchanged   ^(confirmed good^)
    echo              The smallest real change. Proven to run and to
    echo              render menus correctly, so the rescale approach
    echo              itself works. Barely changes text size, though.
    echo.
    echo   2.  1.10x  10%% bigger, font 8 -^> 9pt        (1264 px wide)
    echo   3.  1.25x  25%% bigger, font 8 -^> 10pt       (1437 px wide)
    echo   4.  1.40x  40%% bigger, font 8 -^> 11pt       (1608 px wide)
    echo              BIGGEST MENU TEXT. Your desktop reports 1707 px
    echo              across and the largest page is 1149 px, so about
    echo              1.49x is the ceiling before pages start clipping
    echo              again. If 1.40x clips, drop back to 1.25x.
    echo.
    echo   5.  0.80x  20%% smaller, font 8 -^> 6pt
    echo   6.  GEOM   coordinates 1.10x, font left alone
    echo   7.  FONT   font 8 -^> 9pt only, coordinates left alone
    echo.
    echo   8.  Cancel
    echo.
    set /p PICK=  Choose 1-8:
    if "!PICK!"=="1" set WHICH=102
    if "!PICK!"=="2" set WHICH=110
    if "!PICK!"=="3" set WHICH=125
    if "!PICK!"=="4" set WHICH=140
    if "!PICK!"=="5" set WHICH=080
    if "!PICK!"=="6" set WHICH=GEOM
    if "!PICK!"=="7" set WHICH=FONT
    if "!PICK!"=="8" exit /b
    if "!WHICH!"=="" (
        echo Not a valid choice.
        pause
        exit /b 1
    )
)

set TARGET=Bob_ui%WHICH%.exe
if /I "%WHICH%"=="geom" set TARGET=Bob_uiGEOM.exe
if /I "%WHICH%"=="font" set TARGET=Bob_uiFONT.exe

REM --- find the game folder rather than assuming it ---
set GAMEDIR=
call :try "%~dp0."
call :try "%~dp0.."
call :try "D:\Battle of Britain II"
call :try "C:\Battle of Britain II"
call :try "C:\Program Files (x86)\Battle of Britain II"
call :try "C:\Program Files (x86)\Shockwave\Battle of Britain II"
call :try "E:\Battle of Britain II"

if not defined GAMEDIR (
    echo.
    echo ERROR: could not find your Battle of Britain II folder.
    echo Looked for Bob.exe in:
    echo    %~dp0
    echo    %~dp0..
    echo    D:\Battle of Britain II
    echo    C:\Battle of Britain II
    echo    C:\Program Files ^(x86^)\Battle of Britain II
    echo.
    pause
    exit /b 1
)

echo Game folder: %GAMEDIR%

if not exist "%GAMEDIR%\%TARGET%" (
    echo.
    echo ERROR: %TARGET% is not in "%GAMEDIR%".
    echo.
    echo The prototype executables are built into the GAME folder,
    echo not into this script's folder. If they are missing, they
    echo were never built or have been deleted.
    echo.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights ^(needed for CPU pinning^)...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%WHICH%' -Verb RunAs"
    exit /b
)

echo.
echo Launching %TARGET% pinned to P-cores.
echo.
echo Go to any menu and compare it against the normal game.
echo Look at whether the TEXT and BUTTON ART changed size, not
echo just the spacing.
echo.

REM The game resolves its data paths (models\weapons.txt and the rest)
REM against the CURRENT DIRECTORY, so it must actually be the game folder.
REM An earlier version passed "start /D" instead of changing directory and
REM the game came up with "File 'models\weapons.txt' is missing!" over a
REM blank window - which looked like a rendering failure but was nothing of
REM the kind. pushd is what BOB2_Launch.bat has always done; do the same.
pushd "%GAMEDIR%"
if errorlevel 1 (
    echo ERROR: could not change directory to "%GAMEDIR%".
    pause
    exit /b 1
)
start "" /affinity FFFF /high "%TARGET%"
popd
exit /b

:try
if defined GAMEDIR exit /b
if exist "%~f1\Bob.exe" set GAMEDIR=%~f1
exit /b
