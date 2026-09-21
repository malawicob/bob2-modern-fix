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
#   7  PLAY CAMPAIGN's autostart request carries the pilot's side, role,
#      phase and name for a new campaign and nothing for a pilot with a
#      save; the guard's report is read back once and consumed
#   8  who the game flew him with, and what a fresh pilot is
#   9  the Room mirrors the aeroplane the game gave him: plane id, number
#      and colour from the game's own rules, by date
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
    # somebody else's war, by name: the borrowed real save now carries
    # whatever pilot last flew the dev install, and section 8 needs this
    # file NOT to be Millin's
    $lb = [System.IO.File]::ReadAllBytes($realSave)
    $ln = [System.Text.Encoding]::ASCII.GetBytes('Bob')
    for ($i = 0; $i -lt 21; $i++) { $lb[100 + $i] = 0 }
    [Array]::Copy($ln, 0, $lb, 100, $ln.Length)
    [System.IO.File]::WriteAllBytes($bsl, $lb)
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

    "7  the autostart request and the guard's report"
    Set-StateSide 'lw'
    $ap = [ordered]@{ pilot = 'Kohler'; rank = 'Leutnant'; side = 'lw'; status = 'On strength'; cmode = 'pilot'; sqn = 0
                      unit = 'I./JG 3'; gesch = 'JG 3'; gruppe = 'I'; staffel = 1; luftflotte = 2; actype = 'Bf 109E'; base = 'Colombert'
                      period = 'P3'; historical = $false; portrait = 'pilot01.jpg'; acnum = 3; created = '1940-08-24'
                      campaignSorties = 0; campaignKills = @(0,0,0,0,0,0,0) }
    Save-Pilot -Pilot $ap -Shrink
    $req = Join-Path $script:StateRootOverride 'autostart.txt'
    $done = Join-Path $script:StateRootOverride 'autostart.done'
    Set-Content -Path $done -Value 'status=ok' -Encoding ASCII
    $wrote = Write-AutostartRequest -Pilot (Get-Pilot)
    $txt = if (Test-Path $req) { Get-Content $req -Raw } else { '' }
    Check 'a new Luftwaffe campaign is asked for'  ($wrote -and (Test-Path $req))
    Check 'mode=begin, side=1, role=4, phase=2'   ($txt -match 'mode=begin' -and $txt -match 'side=1' -and $txt -match 'role=4' -and $txt -match 'phase=2') ($txt -replace "`r?`n", ' | ')
    Check 'the name is his'                        ($txt -match 'name=Kohler')
    Check 'his Gruppe as the game numbers it'      ($txt -match 'unit=160') ($txt -replace "`r?`n", ' | ')
    Check 'a stale report was cleared first'       (-not (Test-Path $done))
    Set-StateSide 'raf'
    $bp = [ordered]@{ pilot = 'Millin'; rank = 'Pilot Officer'; status = 'On strength'; cmode = 'commander'; sqn = 32
                      actype = 'Hurricane'; base = 'Biggin Hill'; period = 'P1'; historical = $false; portrait = 'pilot01.jpg'
                      created = '1940-07-10'; campaignSorties = 0; campaignKills = @(0,0,0,0,0,0,0) }
    Save-Pilot -Pilot $bp -Shrink
    [void](Write-AutostartRequest -Pilot (Get-Pilot))
    $txt = Get-Content $req -Raw
    Check 'RAF commander, Convoys: side=0, role=5, phase=0' ($txt -match 'side=0' -and $txt -match 'role=5' -and $txt -match 'phase=0' -and $txt -match 'name=Millin') ($txt -replace "`r?`n", ' | ')
    Check 'No. 32 Squadron is unit 64'              ($txt -match 'unit=64')
    [void](Write-AutostartRequest -Pilot $null)
    Check 'a pilot with a save asks for nothing'   (-not (Test-Path $req))
    Check 'no report means no note'                ($null -eq (Read-AutostartResult))
    Set-Content -Path $done -Value "status=armed`nstatus=mismatch" -Encoding ASCII
    $st = Read-AutostartResult
    Check 'the last status line is read back'      ($st -eq 'mismatch') "$st"
    Check 'and the report is consumed'             (-not (Test-Path $done))
    "8  who the game flew him with, and what fresh means"
    $ub = [System.IO.File]::ReadAllBytes($realSave)
    $mn = [System.Text.Encoding]::ASCII.GetBytes('Millin')
    for ($i = 0; $i -lt 21; $i++) { $ub[100 + $i] = 0 }
    [Array]::Copy($mn, 0, $ub, 100, $mn.Length)
    $ub[11344] = 163; $ub[11345] = 0; $ub[11346] = 6; $ub[11347] = 0        # I./JG 26, seventh aircraft
    $unitSave = Join-Path $GameDir 'SAVEGAME\Unit.bsL'
    [System.IO.File]::WriteAllBytes($unitSave, $ub)
    $pu = Get-SavePlayerUnit -Path $unitSave
    Check 'playersquadron and playeracnum read back' ($pu -and $pu.SqIdx -eq 163 -and $pu.AcNum -eq 6) "$($pu | ConvertTo-Json -Compress)"
    $u = Get-UnitBySqIdx -Idx 163
    Check '163 is I./JG 26'                           ($u.Side -eq 'lw' -and $u.Unit -eq 'I./JG 26') "$($u.Label)"
    $u2 = Get-UnitBySqIdx -Idx 160
    Check '160 is I./JG 3, as the real save said'      ($u2.Unit -eq 'I./JG 3') "$($u2.Label)"
    $u3 = Get-UnitBySqIdx -Idx 66
    Check '66 is No. 501 Squadron (provisional base)'  ($u3.Side -eq 'raf' -and $u3.Num -eq 501) "$($u3.Label)"
    $ub[11344] = 0; $ub[11346] = 0
    [System.IO.File]::WriteAllBytes((Join-Path $GameDir 'SAVEGAME\Nobody.bsL'), $ub)
    Check 'nobody flown yet reads as nothing'          ($null -eq (Get-SavePlayerUnit -Path (Join-Path $GameDir 'SAVEGAME\Nobody.bsL')))
    Set-StateSide 'lw'
    Check 'a Luftwaffe Kohler with only Millin saves on disk is fresh' (Test-FreshPilot -Pilot (Get-Pilot))
    $kp = Get-Pilot; $kp.pilot = 'Millin'; Save-Pilot -Pilot $kp
    Check 'a Luftwaffe Millin with a Millin .BSL on disk is not fresh' (-not (Test-FreshPilot -Pilot (Get-Pilot)))
    $kp = Get-Pilot; $kp | Add-Member -NotePropertyName createdAt -NotePropertyValue ((Get-Date).AddMinutes(5).ToString('s')) -Force; Save-Pilot -Pilot $kp
    Check 'but a Millin enrolled AFTER that save was written is fresh' (Test-FreshPilot -Pilot (Get-Pilot))
    $kp = Get-Pilot; $kp.createdAt = (Get-Date).AddDays(-1).ToString('s'); Save-Pilot -Pilot $kp
    Check 'and one enrolled before it is not'          (-not (Test-FreshPilot -Pilot (Get-Pilot)))
    Remove-Item $unitSave, (Join-Path $GameDir 'SAVEGAME\Nobody.bsL') -Force
    Check 'and fresh again once that .BSL is gone'      (Test-FreshPilot -Pilot (Get-Pilot))
    Set-StateSide 'raf'
    Check 'an RAF Millin whose name is on a .BSR is not fresh' (-not (Test-FreshPilot -Pilot (Get-Pilot)))
    Check 'own Gruppe test'                            ((Test-FlownIsOwn -Pilot ([pscustomobject]@{ unit='I./JG 26'; sqn=0 }) -Flown $u) -and -not (Test-FlownIsOwn -Pilot ([pscustomobject]@{ unit='I./JG 26'; sqn=0 }) -Flown $u2))
    "9  the Room mirrors the aeroplane the game gave him"
    $script:CampaignDate = [datetime]'1940-09-07'
    $mp = [pscustomobject]@{ pilot='Millin'; side='lw'; unit='II./JG 26'; actype='Bf 109E'; staffel=6; acnum=7
                             lastFlown=[pscustomobject]@{ own=$true; acnum=11; sqidx=164; unit='II./JG 26'; date='1940-09-07' } }
    $fm = Get-FlownMark -Pilot $mp
    Check 'aircraft 12 of II./JG 26 wears white 12'   ($fm -and $fm.PlaneId -eq 12 -and $fm.Number -eq 12 -and $fm.Colour -eq 'white') "$($fm | ConvertTo-Json -Compress)"
    Check 'the plane id follows the flown aeroplane'  ((Get-PlaneId -Pilot $mp) -eq 12)
    $mp.lastFlown.acnum = 30
    $fm = Get-FlownMark -Pilot $mp
    Check 'aircraft 31 is yellow 7 in September'       ($fm.Number -eq 7 -and $fm.Colour -eq 'yellow') "$($fm | ConvertTo-Json -Compress)"
    $script:CampaignDate = [datetime]'1940-08-01'
    Check 'and brown 7 before the repaint'             ((Get-FlownMark -Pilot $mp).Colour -eq 'brown')
    $kp2 = [pscustomobject]@{ pilot='Millin'; side='lw'; unit='I./JG 26'; actype='Bf 109E'; staffel=1; acnum=7
                              lastFlown=[pscustomobject]@{ own=$true; acnum=0; sqidx=163; unit='I./JG 26'; date='1940-09-07' } }
    Check 'aircraft 1 of I./JG 26 is the blank-numbered leader' ((Get-FlownMark -Pilot $kp2).Blank)
    $kp2.lastFlown.own = $false
    Check 'another unit''s aeroplane is not mirrored'  ($null -eq (Get-FlownMark -Pilot $kp2))
    Check 'and his own number stands'                  ((Get-PlaneId -Pilot $kp2) -eq 7) "$(Get-PlaneId -Pilot $kp2)"
    "10 adopting a save binds only a man of the save's own unit"
    Set-StateSide 'lw'
    $ad = Join-Path $GameDir 'SAVEGAME\Adopt.bsL'
    $ab = New-Object byte[] 12000
    [System.Text.Encoding]::ASCII.GetBytes('Rowan Savegame: V 0') | ForEach-Object -Begin { $i = 1 } -Process { $ab[$i] = $_; $i++ }
    [BitConverter]::GetBytes([int16]164).CopyTo($ab, 11344)          # II./JG 26
    [System.IO.File]::WriteAllBytes($ad, $ab)
    $script:AdoptFrom = [pscustomobject]@{ Path = $ad; Side = 'lw'; Name = 'Milllin' }
    Check 'a II./JG 26 man is bound to a II./JG 26 save'   (Test-AdoptFits -Pilot ([ordered]@{ pilot='Millin'; side='lw'; unit='II./JG 26' }))
    Check 'a III./ZG 26 man is NOT bound to it'            (-not (Test-AdoptFits -Pilot ([ordered]@{ pilot='Millin'; side='lw'; unit='III./ZG 26' })))
    [BitConverter]::GetBytes([int16]0).CopyTo($ab, 11344)
    [System.IO.File]::WriteAllBytes($ad, $ab)
    Check 'a save nobody has flown in binds as before'     (Test-AdoptFits -Pilot ([ordered]@{ pilot='Millin'; side='lw'; unit='III./ZG 26' }))
    $script:AdoptFrom = $null
    Check 'and with nothing adopted nothing is bound'      (-not (Test-AdoptFits -Pilot ([ordered]@{ pilot='Millin'; side='lw'; unit='III./ZG 26' })))
    Remove-Item $ad -Force -ErrorAction SilentlyContinue
    "11 a background behind the portrait"
    $script:CampaignDate = [datetime]'1940-08-12'
    $cases = @(
        [pscustomobject]@{ pilot='Millin'; first='Patrick'; rank='Sergeant'; sqn=610; actype='Spitfire I'; base='Biggin Hill' },
        [pscustomobject]@{ pilot='Millin'; rank='Pilot Officer'; sqn=32; actype='Hurricane I'; base='Biggin Hill' },
        [pscustomobject]@{ pilot='Millin'; rank='Unteroffizier'; side='lw'; unit='II./JG 26'; actype='Bf 109E'; base='Marquise' },
        [pscustomobject]@{ pilot='Millin'; rank='Leutnant'; side='lw'; unit='III./ZG 26'; actype='Bf 110'; base='Barley' }
    )
    foreach ($c in $cases) {
        $seenRoutes = @{}
        $bad = @()
        foreach ($salt in 0..39) {
            $b = New-PilotBackground -Man $c -Pilot $c -Salt $salt
            if (-not $b) { $bad += "salt $salt : nothing"; continue }
            if ("$($b.story)" -match '[{}]') { $bad += "salt $salt : an unfilled token" }
            if ("$($b.story)" -match [char]0x2014 -or "$($b.story)" -match [char]0x2013 -or "$($b.story)" -match ' - ') { $bad += "salt $salt : a dash" }
            $y = [int]("$($b.born)".Substring("$($b.born)".Length - 4))
            $j = [int]$b.joined
            if ("$($b.story)" -notmatch " in $j") { $bad += "salt $salt : the year he joined is not in the story" }
            if ($y -lt 1911 -or $y -gt 1921) { $bad += "salt $salt : born $y" }
            if ($j -and (($j - $y) -lt 17 -or ($j - $y) -gt 25)) { $bad += "salt $salt : joined at $($j - $y)" }
            $seenRoutes["$("$($b.story)".Substring(0, 40))"] = 1
        }
        Check "$($c.rank), $($c.actype): forty pasts, all sound" ($bad.Count -eq 0) (($bad | Select-Object -First 3) -join '; ')
    }
    $sgt = New-PilotBackground -Man $cases[0] -Pilot $cases[0]
    Check 'a Sergeant is not given Cranwell or a commission'   ("$($sgt.story)" -notmatch 'Cranwell|short service|University Air')
    Check 'the same man gets the same past twice'              ((New-PilotBackground -Man $cases[0] -Pilot $cases[0]).story -eq $sgt.story)
    $z = New-PilotBackground -Man $cases[3] -Pilot $cases[3]
    Check 'a 110 pilot went through the Zerstoerer school'     ("$($z.story)" -match 'Zerst' -and "$($z.story)" -match 'blind flying')
    $bf = [pscustomobject]@{ pilot='Lehmann, P'; rank='Unteroffizier'; role='Bordfunker' }
    $bfb = New-PilotBackground -Man $bf -Pilot $cases[3]
    Check 'a roster man gets a first name from his initial'   ((Get-BackgroundNames -Man $bf -Seed 5).first -match '^P' -and (Get-BackgroundNames -Man $bf -Seed 5).last -eq 'Lehmann')
    Check 'his Bordfunker is a wireless man, not a pilot'      ("$($bfb.story)" -match 'wireless operator' -and "$($bfb.story)" -notmatch 'pilot.s badge')
    Set-StateSide 'lw'
    $zp = [ordered]@{ pilot='Millin'; rank='Leutnant'; side='lw'; unit='III./ZG 26'; actype='Bf 110'; base='Barley'; status='On strength'
                      staffel=7; acnum=4; portrait='pilot01.jpg'; created='1940-07-10'; campaignSorties=0; campaignKills=@(0,0,0,0,0,0,0)
                      crew=@([ordered]@{ role='Bordfunker'; pilot='Lehmann, P'; rank='Unteroffizier'; portrait=''; honours=@(); sortiesBase=0; joined='1940-07-10'; src='invented' }) }
    Save-Pilot -Pilot $zp -Shrink
    $p1 = Save-PilotBackground -Pilot (Get-Pilot) -CrewIndex -1 -Born '3 May 1917' -Place 'Ulm' -Story 'My own words.'
    Check 'the player''s own words are kept'                   ("$((Get-PilotBackground -Pilot (Get-Pilot)).story)" -eq 'My own words.' -and [bool](Get-Pilot).background.custom)
    [void](Save-PilotBackground -Pilot (Get-Pilot) -CrewIndex 0 -Born '1 June 1918' -Place 'Kiel' -Story 'The man in the back.')
    $p2 = Get-Pilot
    Check 'and the crewman''s, without touching the pilot''s'  ("$(@(Get-Crew $p2)[0].background.story)" -eq 'The man in the back.' -and "$($p2.background.story)" -eq 'My own words.' -and "$(@(Get-Crew $p2)[0].pilot)" -eq 'Lehmann, P')
    $bw = New-BackgroundWindow -Pilot $p2 -CrewIndex -1
    Check 'the window builds with his record in it'            ($bw -and "$($script:BgDlg.Story.Text)" -eq 'My own words.' -and "$($script:BgDlg.Born.Text)" -eq '3 May 1917')
    # THE BUTTONS ANSWER A PRESS. They were wired to the release, and the
    # window's drag swallowed it: all three were dead and the test, which
    # called the action directly, never knew.
    $btnRow = @($script:BgDlg.Win.Content.Child.Children)[-1]
    $press = { param($Border)
        $ev = New-Object Windows.Input.MouseButtonEventArgs([Windows.Input.Mouse]::PrimaryDevice, 0, [Windows.Input.MouseButton]::Left)
        $ev.RoutedEvent = [Windows.UIElement]::MouseLeftButtonDownEvent
        $Border.RaiseEvent($ev) }
    $script:BgDlg.First.Text = 'Patrick'
    & $press @($btnRow.Children)[0]
    Check 'pressing WRITE ANOTHER writes another, with his name' ("$($script:BgDlg.Story.Text)" -ne 'My own words.' -and "$($script:BgDlg.Story.Text)" -match 'Patrick Millin')
    $script:BgDlg.Story.Text = 'Typed by the player.'
    & $press @($btnRow.Children)[2]
    $p3 = Get-Pilot
    Check 'pressing SAVE keeps his words and his first name'   ("$($p3.background.story)" -eq 'Typed by the player.' -and "$($p3.first)" -eq 'Patrick' -and (Get-FullName $p3) -eq 'Patrick Millin')
    $bw = New-BackgroundWindow -Pilot $p3 -CrewIndex -1
    Invoke-BackgroundAction 'another'
    Check 'WRITE ANOTHER writes another'                       ("$($script:BgDlg.Story.Text)" -ne 'My own words.' -and "$($script:BgDlg.Story.Text)".Length -gt 300)
    $script:BgDlg = $null
    ''
    '--- samples, to be read by a person ---'
    foreach ($c in $cases) { $b = New-PilotBackground -Man $c -Pilot $c; ''; "[$($c.rank), $($c.actype)]  born $($b.born), $($b.place)"; $b.story }
    ''; "[Bordfunker]  born $($bfb.born), $($bfb.place)"; $bfb.story; ''
    foreach ($side in 'raf', 'lw') { Set-StateSide $side; Remove-PilotCareer -Force }
}
finally {
    Remove-Item $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue
}
""
if ($fails) { "$fails FAILURE(S)"; exit 1 } else { 'ALL FLIGHT CHECKS PASSED'; exit 0 }
