@echo off
REM  CONSOLE FALLBACK. Normal use goes through the launcher's
REM  INSTALL AND REPAIR window (BOB2_Install.vbs). This numbered menu is
REM  kept only for troubleshooting, and drives the same code.
echo Starting BOB2 2.13 Modern Fix - install and repair (console)...
powershell -ExecutionPolicy Bypass -File "%~dp0BOB2_Setup.ps1"
pause
