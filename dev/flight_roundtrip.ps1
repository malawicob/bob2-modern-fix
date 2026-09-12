# Is a quick mission left out of the logbook, and a campaign sortie put in?
#
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File dev\flight_roundtrip.ps1
#
# The Squadron Room's pilot is a campaign pilot and nothing else, and the
# test of that is Finalize-Flight: it must log nothing when the campaign
# save is unchanged, whatever the clock says, and log a sortie when the
# save changed. It used to decide on wall-clock minutes between Play and
# the newest save's timestamp, which logged quick missions as campaign
# sorties with a campaign date copied from before the flight.
#
# Against a throwaway state root AND a throwaway SAVEGAME folder, never
# the real install:
#
#   1  an unchanged save logs nothing and clears the marker
#   2  a changed save logs one session
#   3  a .BSL is found for a Luftwaffe pilot, and preferred over a .BSR
#      of the same age
#   4  a save whose surname is not the pilot's is not his war, and its
#      identity carries that name for the adoption prompt
#   5  the launch card names the pilot's own save when he has one
#   6  DELETE THIS PILOT clears everything the Room holds for a side,
#      keeps a copy under archive\deleted-, brings up that side's
#      enrollment board, and leaves the game's saves alone, RAF and LW
param([string]$Room, [string]$SourceSave)
if (-not $Room) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Room = Join-Path (Split-Path -Parent $here) 'BOB2_SquadronRoom.ps1'
}
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$src = Get-Content $Room -Raw
$src = $src -replace '(?m)^\[void\]\$Win\.ShowDialog\(\)\s*$', ''
$src = $src -replace '(?m)^Finalize-Flight\s*$', ''
$src = $src -replace '(?m)^Start-Room\s*$', ''
$tmp = Join-Path (Split-Path -Parent $Room) '_flighttest.ps1'
Set-Content -Path $tmp -Value $src -Encoding UTF8
try { . $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

# A real save to copy, so the diary reader has something true to read. Found
# the way the other dev tools find their inputs, by a default that points at
# the dev install, and NOT through the Room's own game-folder detection: that
# is empty when the Room is dot-sourced from the repo, which is how every
# harness runs it.
$realSave = $null
$cands = @()
if ($SourceSave) { $cands += $SourceSave }
$cands += 'D:\Battle of Britain II_Latest_test\SAVEGAME\Auto Save.BSR'
$cands += 'D:\Battle of Britain II_Latest_test\SAVEGAME\Bob.bsR'
$cands += 'D:\Battle of Britain II\SAVEGAME\Auto Save.BSR'
foreach ($cand in $cands) { if (Test-Path $cand) { $realSave = $cand; break } }
if (-not $realSave) { 'no campaign save found to copy from; pass -SourceSave'; exit 1 }
"a real save to copy: $realSave"

$script:StateRootOverride = Join-Path ([IO.Path]::GetTempPath()) ('flight-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:StateRootOverride -Force | Out-Null
# and a throwaway game folder, so Get-SaveFiles reads a SAVEGAME that is ours
# both spellings, so the override reaches the Room's functions whichever
# way they read it
$GameDir = Join-Path $script:StateRootOverride 'game'
$script:GameDir = $GameDir
New-Item -ItemType Directory -Path (Join-Path $GameDir 'SAVEGAME') -Force | Out-Null
Set-StateSide 'raf'
if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }

$fails = 0
function Check { param([string]$What, [bool]$Ok, [string]$Saw = '')
    if ($Ok) { "  ok    $What" }
    else { $script:fails++; "  FAIL  $What$(if ($Saw) { "  (saw: $Saw)" })" } }

function New-Marker { param([string]$SavePath)
    @{ start = (Get-Date).AddMinutes(-30).ToString('s'); dateBefore = '1940-07-10'; savePath = $SavePath } |
        ConvertTo-Json | Set-Content -Path $FlightOpen -Encoding UTF8
    Copy-Item $SavePath (Join-Path $StateDir 'before.bsr') -Force
}

try {
    $save = Join-Path $GameDir 'SAVEGAME\Auto Save.BSR'
    Copy-Item $realSave $save -Force
    $pilot = [ordered]@{
        pilot = 'Millin'; rank = 'Sergeant'; codes = 'GZ-T'; status = 'On strength'
        serials = 'N3200'; note = 'test'; cmode = 'pilot'; sqn = 32; sqcode = 'GZ'
        actype = 'Spitfire I'; base = 'Biggin Hill'; period = 'P1'; historical = $false
        portrait = 'pilot01.jpg'; created = '1940-07-10'; campaignSorties = 0
        campaignKills = @(0,0,0,0,0,0,0); savePath = $save; saveAsked = $true
    }
    Save-Pilot -Pilot $pilot -Shrink

    "1  an unchanged save logs nothing"
    New-Marker $save
    $n0 = @(Get-Sessions).Count
    Finalize-Flight
    Check 'no session was logged'        (@(Get-Sessions).Count -eq $n0) "$(@(Get-Sessions).Count) vs $n0"
    Check 'the marker was cleared'       (-not (Test-Path $FlightOpen))
    Check 'the snapshot was cleared'     (-not (Test-Path (Join-Path $StateDir 'before.bsr')))

    "2  a changed save logs one session"
    New-Marker $save
    $bytes = [System.IO.File]::ReadAllBytes($save)
    $bytes[$bytes.Length - 40] = [byte](($bytes[$bytes.Length - 40] + 1) % 256)
    [System.IO.File]::WriteAllBytes($save, $bytes)
    $n1 = @(Get-Sessions).Count
    Finalize-Flight
    Check 'one session was logged'       (@(Get-Sessions).Count -eq ($n1 + 1)) "$(@(Get-Sessions).Count) vs $($n1 + 1)"
    Check 'the marker was cleared'       (-not (Test-Path $FlightOpen))

    "3  a Luftwaffe save is found, and preferred"
    $bsl = Join-Path $GameDir 'SAVEGAME\Auto Save.BSL'
    Copy-Item $realSave $bsl -Force
    (Get-Item $bsl).LastWriteTime = (Get-Item $save).LastWriteTime
    Set-StateSide 'lw'
    $files = @(Get-SaveFiles)
    Check 'both extensions are listed'   ($files.Count -eq 2) "$($files.Count)"
    Check 'the .BSL comes first on the LW side' ($files[0].Extension -ieq '.bsl') "$($files[0].Name)"
    Set-StateSide 'raf'
    $files = @(Get-SaveFiles)
    Check 'the .BSR comes first on the RAF side' ($files[0].Extension -ieq '.bsr') "$($files[0].Name)"

    "4  another man's war is recognised as not his"
    $other = Join-Path $GameDir 'SAVEGAME\Hughes.bsR'
    $ob = [System.IO.File]::ReadAllBytes($realSave)
    $nm = [System.Text.Encoding]::ASCII.GetBytes('Hughes')
    for ($i = 0; $i -lt 21; $i++) { $ob[100 + $i] = 0 }
    [Array]::Copy($nm, 0, $ob, 100, $nm.Length)
    [System.IO.File]::WriteAllBytes($other, $ob)
    $id = Get-CampaignIdentity -Path $other
    Check 'the identity carries the surname'   ($id.Name -eq 'Hughes') "$($id.Name)"
    Check 'the identity carries the side'      ($id.Side -eq 'raf') "$($id.Side)"
    Check 'it does not match Millin'           (-not (Test-CampaignMatch -Pilot (Get-Pilot) -Identity $id))
    # his own war carries HIS name: the borrowed real save is somebody
    # else's pilot, so the name is written in the way the Hughes one was,
    # and the check does not depend on whose save was copied
    $mb = [System.IO.File]::ReadAllBytes($save)
    $mn = [System.Text.Encoding]::ASCII.GetBytes('Millin')
    for ($i = 0; $i -lt 21; $i++) { $mb[100 + $i] = 0 }
    [Array]::Copy($mn, 0, $mb, 100, $mn.Length)
    [System.IO.File]::WriteAllBytes($save, $mb)
    $mine = Get-CampaignIdentity -Path $save
    Check 'his own save does match'            (Test-CampaignMatch -Pilot (Get-Pilot) -Identity $mine) "$($mine.Name)"

    "5  the launch card names his save"
    $card = New-LaunchCardData
    Check 'the card exists'                     ($null -ne $card)
    Check 'it names the save to load'           (($card.Steps -join ' ') -match 'LOAD GAME.*Auto Save\.BSR') "$($card.Steps -join ' | ')"
    Check 'it names the man'                    ($card.Name -eq 'Millin') "$($card.Name)"

    "6  DELETE THIS PILOT, both sides"
    $saveCount = @(Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -File).Count
    foreach ($side in 'raf', 'lw') {
        Set-StateSide $side
        if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }
        $dp = [ordered]@{ pilot = 'Testman'; rank = $(if ($side -eq 'lw') { 'Leutnant' } else { 'Sergeant' })
                          status = 'On strength'; cmode = 'pilot'; sqn = $(if ($side -eq 'lw') { 0 } else { 32 })
                          actype = 'x'; base = 'y'; period = 'P1'; historical = $false; portrait = 'pilot01.jpg'
                          created = '1940-07-10'; campaignSorties = 0; campaignKills = @(0,0,0,0,0,0,0) }
        if ($side -eq 'lw') { $dp['side'] = 'lw'; $dp['unit'] = 'I./JG 3'; $dp['gesch'] = 'JG 3'; $dp['gruppe'] = 'I'; $dp['staffel'] = 1; $dp['luftflotte'] = 2; $dp['acnum'] = 3 }
        Save-Pilot -Pilot $dp -Shrink
        Set-Content -Path $SessionsPath -Value '[]' -Encoding UTF8
        Set-Content -Path $FlightOpen -Value '{}' -Encoding UTF8
        Set-Content -Path (Join-Path $StateDir 'before.bsr') -Value 'x' -Encoding ASCII
        $script:LaunchCard = [pscustomobject]@{ Steps = @('x') }
        Remove-PilotCareer -Force
        Check "$side`: no pilot afterwards"          ($null -eq (Get-Pilot))
        Check "$side`: sessions, marker and snapshot gone" (-not (Test-Path $SessionsPath) -and -not (Test-Path $FlightOpen) -and -not (Test-Path (Join-Path $StateDir 'before.bsr')))
        $arch = @(Get-ChildItem (Join-Path $StateDir 'archive') -Directory -Filter 'deleted-*' -ErrorAction SilentlyContinue)
        Check "$side`: a copy was kept under archive\deleted-" ($arch.Count -eq 1 -and (Test-Path (Join-Path $arch[0].FullName 'pilot.json')))
        Check "$side`: the enrollment board is up"   ($script:Stage.Children.Count -gt 0)
        Check "$side`: the launch card is cleared"   ($null -eq $script:LaunchCard)
    }
    Check 'the game''s saves were not touched'      (@(Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -File).Count -eq $saveCount) "$saveCount"
}
finally {
    Remove-Item $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue
}
""
if ($fails) { "$fails FAILURE(S)"; exit 1 } else { 'ALL FLIGHT CHECKS PASSED'; exit 0 }
