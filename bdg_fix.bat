@echo off
echo Fixing bdg.txt video settings...

if not exist bdg.txt (
    echo ERROR: bdg.txt not found. Run this from your BOB2 game folder.
    pause
    exit /b 1
)

if not exist bdg.txt.backup (
    copy bdg.txt bdg.txt.backup >nul
    echo Backed up bdg.txt
)

powershell -Command "(Get-Content 'bdg.txt') -replace 'SKIP_VIDEOS=OFF', 'SKIP_VIDEOS=ON' -replace 'SKIP_QUICKVIDEOS=OFF', 'SKIP_QUICKVIDEOS=ON' -replace 'INTRO_VIDEO=ON', 'INTRO_VIDEO=OFF' | Set-Content 'bdg.txt'"

echo Done. SKIP_VIDEOS=ON, SKIP_QUICKVIDEOS=ON, INTRO_VIDEO=OFF
pause
