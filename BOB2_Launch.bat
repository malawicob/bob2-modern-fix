@echo off
REM ============================================================
REM  BOB2 launcher - pins the game to P-cores
REM  Part of BOB2 Windows 10/11 Fix
REM ============================================================
REM
REM  Why: BOB2's engine is effectively single-threaded (verified -
REM  CreateThread has only 2 call sites in the whole executable).
REM  On Intel hybrid CPUs (12th gen and later) Windows may schedule
REM  that single thread onto an E-core, which is much slower, and
REM  migration between P- and E-cores causes stutter.
REM
REM  IMPORTANT: this script self-elevates before launching. Bob.exe
REM  carries the RUNASADMIN compatibility shim, so if it were started
REM  from a normal prompt Windows would re-spawn it via the UAC
REM  elevation service - and the elevated child does NOT inherit the
REM  affinity mask set by "start /affinity". Elevating first keeps
REM  the launch in-process so the mask actually sticks.
REM
REM  The affinity actually applied is written to BOB2_Launch.log
REM  so it can be verified rather than assumed.
REM
REM  Affinity values:
REM    FFFF  = logical CPUs 0-15  (8 P-cores with hyperthreading)
REM    FF    = logical CPUs 0-7   (4 P-cores with hyperthreading)
REM    3     = logical CPUs 0-1   (1 P-core - most conservative)
REM    0     = disable pinning entirely
REM ============================================================

set AFFINITY=FFFF

REM --- NO self-elevation, deliberately ---
REM  This used to request administrator rights "for CPU pinning", which was
REM  never the real reason: "start /affinity" can pin a process you create
REM  yourself without any privileges at all. The actual cause was the
REM  RUNASADMIN compatibility shim on Bob.exe - launching an elevated child
REM  from a non-elevated parent loses the affinity mask, so the launcher had
REM  to elevate the whole chain to make pinning stick.
REM
REM  That shim is not needed either: the game folder grants Authenticated
REM  Users Modify, so BOB2 can write its saves, bdg.txt and logs as a normal
REM  user. With the shim removed there is nothing left to elevate for, and
REM  no UAC prompt before the game starts.
REM
REM  If you ever put RUNASADMIN back, the launcher notices and elevates
REM  again on its own - see Test-RunAsAdminShim in BOB2_Launcher.ps1.

REM --- find the game folder rather than assuming it is the parent of this
REM     script. Running from a copy of the source tree, or from a UNC path
REM     such as \\wsl.localhost\..., made the old assumption point at nothing -
REM     and CMD cannot use a UNC path as a working directory at all, so it
REM     silently falls back to the Windows directory first.
set GAMEDIR=
call :findgame "%~dp0."
call :findgame "%~dp0.."
call :findgame "D:\Battle of Britain II"
call :findgame "C:\Battle of Britain II"
call :findgame "C:\Program Files (x86)\Battle of Britain II"
call :findgame "C:\Program Files (x86)\Shockwave\Battle of Britain II"
call :findgame "E:\Battle of Britain II"
if not defined GAMEDIR (
    echo ERROR: could not find Bob.exe. Looked in "%~dp0", its parent, and the
    echo usual install locations on C:, D: and E:.
    pause
    exit /b 1
)
pushd "%GAMEDIR%"

if not exist "Bob.exe" (
    echo ERROR: Bob.exe not found in "%GAMEDIR%"
    pause
    popd
    exit /b 1
)

if "%AFFINITY%"=="0" (
    echo Launching BOB2 with no CPU pinning...
    start "" /high "Bob.exe"
) else (
    echo Launching BOB2 pinned to P-cores ^(mask %AFFINITY%^)...
    start "" /affinity %AFFINITY% /high "Bob.exe"
)

REM --- verify what actually got applied ---
powershell -NoProfile -Command ^
  "Start-Sleep -Seconds 4; $p = Get-Process Bob -ErrorAction SilentlyContinue | Select-Object -First 1; if ($p) { 'requested=0x%AFFINITY%  actual=0x{0:X}  priority={1}' -f [int64]$p.ProcessorAffinity, $p.PriorityClass } else { 'Bob.exe not found after launch' }" > "%GAMEDIR%\BOB2_Launch.log" 2>&1

echo.
type "%GAMEDIR%\BOB2_Launch.log"
echo.
echo ^(also saved to BOB2_Launch.log^)
popd

goto :eof

:findgame
if defined GAMEDIR exit /b
if exist "%~f1\Bob.exe" set GAMEDIR=%~f1
exit /b
