# Smoke test: BUILD every screen of the Squadron Room, offscreen.
#
# Why it exists: on 8 September 2026 the Room would not open at all. One
# line still read a roster record's victories as a number after they had
# become a list of dated claims, and it threw the moment the dispersal was
# drawn. Every helper-level test passed, because the fault only appears
# while a screen is being built. This builds all of them, and the
# dispersal for every squadron on the map at three campaign dates.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File dev\room_smoketest.ps1 \
#       -Room "D:\Battle of Britain II\BOB2-Win11-Fix\BOB2_SquadronRoom.ps1"
#
# Exit code 0 means every screen built. It does not judge how they look.
param([string]$Room)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$fails = @()
# Copy the script beside the real one, with the lines that SHOW the window
# taken out, and dot-source that copy as a FILE so it still resolves its
# own folder the way it does when the launcher runs it.
$src = Get-Content $Room -Raw
$src = $src -replace '(?m)^\[void\]\$Win\.ShowDialog\(\)\s*$', ''
$src = $src -replace '(?m)^Finalize-Flight\s*$', ''
$src = $src -replace '(?m)^\$existing = Get-Pilot\s*$', ''
$src = $src -replace '(?m)^if \(\$existing\) \{ Show-Roster -Pilot \$existing \} else \{ Show-SquadronSelect \}\s*$', ''
$tmp = Join-Path (Split-Path -Parent $Room) '_rendertest.ps1'
Set-Content -Path $tmp -Value $src -Encoding UTF8
try { . $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
"loaded: pilot '$((Get-Pilot).pilot)', squadron $((Get-Pilot).sqn), campaign date $(Get-CampaignDate)"
foreach ($tab in 'dispersal','logbook','map','paper') {
    try { Show-Tab $tab; "  $tab : drew $($script:Stage.Children.Count) blocks" }
    catch { $fails += "$tab : $($_.Exception.Message)"; "  $tab : FAILED - $($_.Exception.Message)" }
}
try { Show-SquadronSelect; "  postings : drew $($script:Stage.Children.Count) blocks" }
catch { $fails += "postings : $($_.Exception.Message)"; "  postings : FAILED - $($_.Exception.Message)" }
# and the dispersal for a pilot in every squadron on the map, at four dates
$saved = Get-Content $PilotPath -Raw
$bad = 0
foreach ($q in (Get-Squadrons)) {
    foreach ($d in '1940-07-10','1940-08-24','1940-10-31') {
        $script:CampaignDate = [datetime]$d
        $p = $saved | ConvertFrom-Json
        $p.sqn = $q.Num
        try { Show-Roster -Pilot $p } catch { $bad++; if ($bad -le 5) { $fails += "No. $($q.Num) on $d : $($_.Exception.Message)" ; "  No. $($q.Num) on $d FAILED: $($_.Exception.Message)" } }
    }
}
Set-Content -Path $PilotPath -Value $saved -Encoding UTF8
"  dispersal for all $((Get-Squadrons).Count) squadrons x 3 dates: $bad failure(s)"
if ($fails.Count) { "FAILURES: $($fails.Count)"; exit 1 } else { 'ALL SCREENS BUILT'; exit 0 }
