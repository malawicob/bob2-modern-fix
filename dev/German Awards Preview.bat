@echo off
rem Opens the German awards preview: the Iron Cross ladder at every rung,
rem with the rank insignia and pilot badge beside it. Double-click this.
setlocal
set "HERE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%awards_preview.ps1" -Side lw
if errorlevel 1 pause
