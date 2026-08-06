@echo off
REM ============================================================
REM  BOB2 menu scale - resize the in-game menus for your screen
REM  Part of BOB2 Windows 10/11 Fix v1.5.0
REM ============================================================
REM
REM  BOB2's menus are 154 Win32 dialog templates laid out in dialog
REM  units against an 8pt font. On a high-resolution screen they end up
REM  occupying a small part of the display with unreadably small text.
REM  This rescales them. Four sizes, defaulting to the largest.
REM
REM  Close the game first - Bob.exe cannot be replaced while it runs.
REM ============================================================
start "" /wait powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BOB2_MenuScale.ps1" %*
