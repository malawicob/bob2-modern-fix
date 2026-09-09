# Mark the morning bulletin unread again, so the dispersal's news strip
# comes back and can be tested more than once.
#
# It removes ONE field, paperRead, from pilot.json and leaves every other
# thing about the pilot alone. A copy of the file is kept beside it first.
#
# Why it is written this way: the obvious version of this script builds a
# fresh pilot object and saves it, which is exactly how a test harness
# wiped a real pilot record on 9 September 2026. Read, drop one property,
# write back. Never construct.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File dev\reset_news_flag.ps1
#
# -GameDir is worked out from where this sits, or pass it.
param([string]$GameDir)
$ErrorActionPreference = 'Stop'
if (-not $GameDir) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $GameDir = Split-Path -Parent (Split-Path -Parent $here)
}
$pj = Join-Path $GameDir 'SquadronRoom\pilot.json'
if (-not (Test-Path $pj)) {
    Write-Host "No pilot record found at:" -ForegroundColor Red
    Write-Host "  $pj" -ForegroundColor Red
    Write-Host "Pass the game folder with -GameDir."
    Read-Host 'Press Enter to close'; exit 1
}
$p = Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json
$was = if ($p.PSObject.Properties.Name -contains 'paperRead') { "$($p.paperRead)" } else { $null }
if (-not $was) {
    Write-Host "Already unread - the dispersal should be showing the news strip." -ForegroundColor Yellow
    Read-Host 'Press Enter to close'; exit 0
}
Copy-Item $pj ($pj + '.before-news-reset') -Force
$p.PSObject.Properties.Remove('paperRead')
$p | ConvertTo-Json -Depth 6 | Set-Content -Path $pj -Encoding UTF8
Write-Host "Cleared the read mark (it was $was)." -ForegroundColor Green
Write-Host "Pilot $($p.pilot), No. $($p.sqn) Squadron - everything else untouched."
Write-Host "Open the Squadron Room: the dispersal should show the news strip again."
Read-Host 'Press Enter to close'
