@echo off
rem Opens the awards preview. Double-click this: it quotes its own paths,
rem which is where running the PowerShell line by hand usually goes wrong.
setlocal
set "HERE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%awards_preview.ps1"
if errorlevel 1 pause
