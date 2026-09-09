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
#
# -Room is optional: with nothing given it looks NEXT DOOR, the way the
# awards preview does, so this works wherever the fix folder has been put
# and can simply be double-clicked. Without that default it died on
# Get-Content with an empty path, which reads as a fault in the Room
# rather than a missing argument.
param([string]$Room)
if (-not $Room) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Room = Join-Path (Split-Path -Parent $here) 'BOB2_SquadronRoom.ps1'
}
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Room)) {
    Write-Host "Cannot find the Squadron Room script at:" -ForegroundColor Red
    Write-Host "  $Room" -ForegroundColor Red
    Write-Host "Pass its path with -Room."
    exit 2
}
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

# ---------------------------------------------------------------------
#  Draw against a COPY of the state, never the real thing.
#
#  Drawing is not read-only. Show-Roster runs Sync-CampaignClaims and
#  Update-CareerRecord; Show-Paper marks the morning bulletin read. Run
#  straight against an install, this test therefore edits the pilot it is
#  supposed to be examining - and it did: it read Patrick's bulletin for
#  him, so the dispersal had nothing to flag when he went looking for it.
#
#  Every path is reassigned, not just $StateDir: each one was computed
#  from $StateDir when the script loaded, so moving the folder afterwards
#  leaves them all pointing at the old place.
# ---------------------------------------------------------------------
$realState = $StateDir
$StateDir  = Join-Path ([IO.Path]::GetTempPath()) ('roomtest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$PilotPath     = Join-Path $StateDir 'pilot.json'
$SessionsPath  = Join-Path $StateDir 'sessions.json'
$FlightOpen    = Join-Path $StateDir 'flight.open'
$AcPosPath     = Join-Path $StateDir 'acpos.json'
$AutoClaimPath = Join-Path $StateDir 'autoclaim.json'
if (Test-Path $realState) {
    Get-ChildItem $realState -File -ErrorAction SilentlyContinue |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $StateDir $_.Name) -Force }
}
try {
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
}
finally {
    # the throwaway copy goes, whatever happened above
    if ($StateDir -ne $realState) { Remove-Item $StateDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fails.Count) { "FAILURES: $($fails.Count)"; exit 1 } else { 'ALL SCREENS BUILT'; exit 0 }
