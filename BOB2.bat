@echo off
REM ============================================================
REM  Battle of Britain II - launcher
REM  Part of BOB2 Windows 10/11 Fix
REM ============================================================
REM
REM  THIS IS THE ONLY FILE YOU NEED TO RUN.
REM
REM  It opens a window with Play, Settings, Measure FPS, Graphics
REM  Wrapper and Setup. The other .bat files in this folder are the
REM  backends it calls; they still work on their own if you prefer,
REM  but the launcher is what enforces the safe ordering.
REM
REM  Specifically: the game rewrites bdg.txt and settings.cfg when it
REM  exits, so anything you change while it is running is lost on quit.
REM  The launcher disables Settings whenever Bob.exe is running, which
REM  makes that mistake impossible rather than merely documented.
REM
REM  Deliberately NOT self-elevating. The launcher window itself needs
REM  no privileges; it elevates only the individual actions that do
REM  (Play, for CPU pinning; Measure FPS, to trace an elevated process;
REM  Setup, to write to Program Files). Running the whole UI as
REM  administrator would mean any file it creates is owned by an
REM  elevated user for no reason.
REM ============================================================

REM  Started through the .vbs, not powershell directly. When Windows
REM  Terminal is the default terminal application it ignores
REM  -WindowStyle Hidden and parks a black console behind the launcher
REM  for the whole session. wscript has no console of its own and starts
REM  PowerShell hidden from the outset, so nothing is ever drawn.
if exist "%~dp0BOB2_Launcher.vbs" (
    start "" wscript.exe //nologo "%~dp0BOB2_Launcher.vbs"
) else (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0BOB2_Launcher.ps1"
)
