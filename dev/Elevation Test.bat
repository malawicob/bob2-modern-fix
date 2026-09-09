@echo off
rem Proves the elevated registry write used by the DPI manifest step,
rem without touching the real setting. Two UAC prompts: say Yes to both.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0elevation_test.ps1"
echo.
pause
