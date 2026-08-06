@echo off
echo ========================================
echo  BOB2 Windows 10/11 Compatibility Fix
echo ========================================
echo.

:: Check we're in the right directory
if not exist Bob.exe (
    echo ERROR: Bob.exe not found in current directory.
    echo Please copy this fix into your BOB2 game folder
    echo and run install.bat from there.
    echo.
    pause
    exit /b 1
)

:: Backup bdg.txt
if exist bdg.txt (
    if not exist bdg.txt.backup (
        copy bdg.txt bdg.txt.backup >nul
        echo [OK] Backed up bdg.txt to bdg.txt.backup
    ) else (
        echo [OK] bdg.txt.backup already exists, skipping backup
    )
) else (
    echo WARNING: bdg.txt not found - skipping video fix
    goto :dll
)

:: Fix video settings in bdg.txt
:: Use PowerShell for reliable text replacement
powershell -Command "(Get-Content 'bdg.txt') -replace 'SKIP_VIDEOS=OFF', 'SKIP_VIDEOS=ON' -replace 'SKIP_QUICKVIDEOS=OFF', 'SKIP_QUICKVIDEOS=ON' -replace 'INTRO_VIDEO=ON', 'INTRO_VIDEO=OFF' | Set-Content 'bdg.txt'"
echo [OK] Set SKIP_VIDEOS=ON, SKIP_QUICKVIDEOS=ON, INTRO_VIDEO=OFF

:dll
:: Install crash guard DLL
if exist dinput8.dll.original (
    echo [OK] dinput8.dll.original already exists, skipping DLL backup
) else (
    if exist dinput8.dll (
        rename dinput8.dll dinput8.dll.original
        echo [OK] Backed up existing dinput8.dll to dinput8.dll.original
    )
)

copy /y "%~dp0dinput8.dll" dinput8.dll >nul
echo [OK] Installed dinput8.dll crash guard

:: Remove Bob.exe.local if present (causes DLL loading issues)
if exist Bob.exe.local (
    del Bob.exe.local
    echo [OK] Removed Bob.exe.local (was causing DLL conflicts)
)

echo.
echo ========================================
echo  Installation complete!
echo  Launch BOB2 normally.
echo ========================================
echo.
pause
