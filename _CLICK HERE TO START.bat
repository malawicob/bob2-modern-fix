@echo off
REM ============================================================
REM  Battle of Britain II  -  CLICK THIS ONE
REM  Same as BOB2.bat, named so it sorts to the very top of the
REM  folder and cannot be missed. It opens the launcher window:
REM  press PLAY there to fly. Every other file in this folder is
REM  machinery the launcher calls for you.
REM ============================================================
if exist "%~dp0BOB2_Launcher.vbs" (
    start "" wscript.exe //nologo "%~dp0BOB2_Launcher.vbs"
) else (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0BOB2_Launcher.ps1"
)
