@echo off
REM  BOB2 Configurator - a working replacement for the game's options screens.
REM  The in-game options render at a fixed ~1024px width and clip on modern
REM  displays, and several settings are not in those screens at all.  This
REM  edits bdg.txt, keys.txt, settings.cfg and Weather.cfg directly, so it
REM  does not depend on the game's UI working.
REM
REM  Close Battle of Britain II before saving: it rewrites all of these files
REM  when it exits and would discard anything written here.
REM  Started through the .vbs so no console window is ever drawn. Windows
REM  Terminal ignores -WindowStyle Hidden, which is why the old line left a
REM  black powershell window sitting behind the settings screen.
if exist "%~dp0BOB2_Config.vbs" (
    start "" wscript.exe //nologo "%~dp0BOB2_Config.vbs"
) else (
    start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0BOB2_Config.ps1"
)
