@echo off
REM ============================================================
REM  Undo the menu rescale - put the original Bob.exe back
REM  Part of BOB2 Windows 10/11 Fix v1.5.0
REM ============================================================
REM
REM  The menus are drawn from 154 Win32 dialog templates stored as
REM  resources inside Bob.exe. Every coordinate in them, and the font
REM  point size, is a fixed-width 16-bit field, so they were rescaled
REM  by patching those numbers in place - nothing was resized, no
REM  section rebuilt, no address moved. The patched Bob.exe is exactly
REM  the same length as the original.
REM
REM  Bob.exe          rescaled 1.40x, dialog font 8 -> 11pt
REM  Bob.exe.unscaled the untouched original, md5 877cd76d...
REM
REM  This script copies the original back over Bob.exe. Run it if the
REM  menus clip, or if you simply want the stock game.
REM
REM  IF YOU RE-PATCH THE GAME: applying BDG v2.13 again, or any other
REM  patch that replaces Bob.exe, will silently wipe the rescale AND
REM  overwrite Bob.exe.unscaled if you let it. Delete Bob.exe.unscaled
REM  before re-patching, then ask for the rescale to be reapplied.
REM ============================================================

setlocal

set GAMEDIR=
call :findgame "%~dp0."
call :findgame "%~dp0.."
call :findgame "D:\Battle of Britain II"
call :findgame "C:\Battle of Britain II"
call :findgame "C:\Program Files (x86)\Battle of Britain II"
if not defined GAMEDIR (
    echo ERROR: could not find Bob.exe.
    pause
    exit /b 1
)

echo Game folder: %GAMEDIR%

if not exist "%GAMEDIR%\Bob.exe.unscaled" (
    echo.
    echo ERROR: Bob.exe.unscaled is not there, so there is nothing to
    echo restore. Bob.exe may already be the original.
    echo.
    pause
    exit /b 1
)

tasklist /FI "IMAGENAME eq Bob.exe" 2>nul | find /I "Bob.exe" >nul
if not errorlevel 1 (
    echo.
    echo The game is running. Close it first - Bob.exe cannot be
    echo replaced while it is in use.
    echo.
    pause
    exit /b 1
)

echo.
echo Restoring the original Bob.exe...
copy /y "%GAMEDIR%\Bob.exe.unscaled" "%GAMEDIR%\Bob.exe" >nul
if errorlevel 1 (
    echo FAILED. Try running this as administrator.
    pause
    exit /b 1
)

echo Done. The menus are back to their original size.
echo Bob.exe.unscaled has been left in place so the rescale can be
echo reapplied later.
echo.
pause
exit /b

:findgame
if defined GAMEDIR exit /b
if exist "%~f1\Bob.exe" set GAMEDIR=%~f1
exit /b
