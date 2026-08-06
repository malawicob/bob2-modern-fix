@echo off
REM ============================================================
REM  BOB2 graphics wrapper switcher
REM  Part of BOB2 Windows 10/11 Fix v1.5.0
REM ============================================================
REM
REM  BOB2 is a Direct3D 9 game (verified: Bob.exe imports d3d9.dll
REM  and d3dx9_35.dll - there is no DirectDraw or D3D7 import).
REM  So the ONLY wrapper file that matters is d3d9.dll.
REM
REM  Usage:  BOB2_SetWrapper.bat [dgvoodoo^|native^|dxvk]
REM
REM    dgvoodoo  - dgVoodoo2 D3D9->D3D11. Known good. Handles the
REM                legacy display-mode enumeration the game needs.
REM    native    - no wrapper; use Windows' own d3d9.dll. Lowest CPU
REM                overhead, so potentially fastest while CPU-bound,
REM                but community reports in-flight crashes.
REM    dxvk      - D3D9->Vulkan. TESTED AND BROKEN for this game:
REM                the game asks for a 0x0/Unknown fullscreen
REM                swapchain, DXVK refuses, device is NULL, and
REM                Renderer::SetGamma dereferences it -> CTD.
REM                Kept only for reference.
REM ============================================================

setlocal
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

set MODE=%~1
if "%MODE%"=="" goto :status

if /I "%MODE%"=="dgvoodoo" goto :dgvoodoo
if /I "%MODE%"=="native"   goto :native
if /I "%MODE%"=="dxvk"     goto :dxvk
if /I "%MODE%"=="dgvoodoo2873" goto :dgv2873
echo Unknown mode "%MODE%". Use dgvoodoo, native or dxvk.
goto :end

:dgvoodoo
REM  Reverts to the ORIGINAL 2.86.5 set. For 2.87.3 use: BOB2_SetWrapper.bat dgvoodoo2873
if not exist "wrapper_backup_dgvoodoo\D3D9.dll" (
    echo ERROR: wrapper_backup_dgvoodoo\D3D9.dll not found.
    goto :end
)
del /q d3d9.dll D3D9.dll dxvk.conf 2>nul
copy /y "wrapper_backup_dgvoodoo\D3D9.dll"   . >nul
copy /y "wrapper_backup_dgvoodoo\D3D8.dll"   . >nul 2>nul
copy /y "wrapper_backup_dgvoodoo\D3DImm.dll" . >nul 2>nul
copy /y "wrapper_backup_dgvoodoo\DDraw.dll"  . >nul 2>nul
copy /y "wrapper_backup_dgvoodoo\dgVoodoo.conf" . >nul 2>nul
echo Switched to dgVoodoo2 ^(D3D9 -^> D3D11^).
goto :status

:native
del /q d3d9.dll D3D9.dll D3D8.dll D3DImm.dll DDraw.dll dxvk.conf 2>nul
echo Switched to NATIVE Direct3D 9 ^(no wrapper^).
echo If the game crashes in flight, run: BOB2_SetWrapper.bat dgvoodoo
goto :status

:dgv2873
if not exist "%~dp0dgv2873\D3D9.dll" (
    echo ERROR: dgVoodoo2 2.87.3 not staged at "%~dp0dgv2873\D3D9.dll"
    goto :end
)
del /q d3d9.dll D3D9.dll dxvk.conf 2>nul
copy /y "%~dp0dgv2873\*.dll" . >nul
echo Switched to dgVoodoo2 2.87.3 ^(config preserved^).
goto :status

:dxvk
if not exist "%~dp0dxvk\d3d9.dll" (
    echo ERROR: DXVK not staged at "%~dp0dxvk\d3d9.dll"
    goto :end
)
del /q d3d9.dll D3D9.dll D3D8.dll D3DImm.dll DDraw.dll 2>nul
copy /y "%~dp0dxvk\d3d9.dll" . >nul
echo Switched to DXVK. NOTE: this is known to crash on entering 3D.
goto :status

:status
echo.
echo Current wrapper files in "%GAMEDIR%":
set FOUND=0
if exist "D3D9.dll"     ( echo    D3D9.dll     - dgVoodoo2 & set FOUND=1 )
if exist "d3d9.dll"     ( if not exist "D3D9.dll" ( echo    d3d9.dll     - DXVK or dgVoodoo2 & set FOUND=1 ) )
if exist "dgVoodoo.conf" echo    dgVoodoo.conf
if exist "dxvk.conf"     echo    dxvk.conf
if "%FOUND%"=="0" echo    ^(none^) - using Windows' native d3d9.dll
echo.

:end
popd

goto :eof

:findgame
if defined GAMEDIR exit /b
if exist "%~f1\Bob.exe" set GAMEDIR=%~f1
exit /b
