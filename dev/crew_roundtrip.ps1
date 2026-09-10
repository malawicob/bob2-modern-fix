# Does a two-man record survive being saved, read back and advanced?
#
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File dev\crew_roundtrip.ps1
#
# This is the test that matters in the whole Bf 110 job. Save-Pilot
# refuses any record with fewer fields than the one on disk, and it does
# that because a career was destroyed on 9 September. Adding a second man
# to the record walks straight into that guard: nest a crew under one key
# and a two-man record counts as SMALLER than a one-man one, so either the
# save is refused or - worse - it is written once and then quietly
# discarded by the next write, since every other write path in the file
# rebuilds the record by copying properties flat.
#
# So this checks, against a throwaway copy of the state and never the real
# install:
#
#   1  a two-man record saves at all
#   2  it reads back with both men intact
#   3  Get-FieldCount counts the crew, so losing a crewman is refused
#   4  Update-CareerRecord advances the RIGHT man and leaves the other be
#   5  the two men do not promote in lockstep
#   6  a crewman's honours survive the round trip as objects, not as the
#      string "System.Collections.Hashtable" that ConvertTo-Json writes
#      when it runs out of depth
param([string]$Room)
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
$tmp = Join-Path (Split-Path -Parent $Room) '_crewtest.ps1'
Set-Content -Path $tmp -Value $src -Encoding UTF8
try { . $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

$realRoot = Split-Path -Parent $StateDir
$script:StateRootOverride = Join-Path ([IO.Path]::GetTempPath()) ('crew-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:StateRootOverride -Force | Out-Null
Set-StateSide 'lw'
if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }

$fails = 0
function Check { param([string]$What, [bool]$Ok, [string]$Saw = '')
    if ($Ok) { "  ok    $What" }
    else { $script:fails++; "  FAIL  $What$(if ($Saw) { "  (saw: $Saw)" })" } }

try {
    $script:CampaignDate = [datetime]'1940-08-15'

    "roles by type"
    Check 'a 109 carries one man'  (@(Get-CrewRoles 'Bf 109E').Count -eq 1)
    Check 'a 110 carries two'      (@(Get-CrewRoles 'Bf 110').Count -eq 2)
    Check 'a He 111 carries five'  (@(Get-CrewRoles 'He 111').Count -eq 5)
    Check 'an unknown type flies single-handed' (@(Get-CrewRoles 'Something Else').Count -eq 1)

    "saving a two-man record"
    $p = [ordered]@{
        pilot = 'Millin'; rank = 'Leutnant'; side = 'lw'; status = 'On strength'
        cmode = 'pilot'; unit = 'II./ZG 26'; gesch = 'ZG 26'; gruppe = 'II'
        staffel = 5; sqn = 0; actype = 'Bf 110'; base = 'Barley'; luftflotte = 2
        period = 'P2'; historical = $false; portrait = 'pilot01.jpg'; acnum = 7
        created = '1940-08-01'; campaignSorties = 0
        campaignKills = @(0,0,0,0,0,0,0)
        crew = @([ordered]@{ role = 'Bordfunker'; name = 'Kessler, H.'
                             rank = 'Unteroffizier'; rank_date = ''
                             portrait = 'pilot02.jpg'; honours = @()
                             sortiesBase = 0; src = 'invented' })
    }
    Save-Pilot -Pilot $p -Shrink
    $r = Get-Pilot
    Check 'the record reads back'            ($null -ne $r)
    Check 'the pilot is still the pilot'     ("$($r.pilot)" -eq 'Millin')
    Check 'the crewman came back'            (@(Get-Crew $r).Count -eq 1) "$(@(Get-Crew $r).Count)"
    Check 'his role survived'                ("$((Get-Crew $r)[0].role)" -eq 'Bordfunker')
    Check 'Test-MultiCrew says two'          (Test-MultiCrew $r)

    "the shrink guard counts the crew"
    $n2 = Get-FieldCount $r
    $flat = [ordered]@{}
    foreach ($pp in $r.PSObject.Properties) { if ($pp.Name -ne 'crew') { $flat[$pp.Name] = $pp.Value } }
    $n1 = Get-FieldCount $flat
    Check 'a two-man record counts higher than a one-man one' ($n2 -gt $n1) "$n2 vs $n1"
    $refused = $false
    try { Save-Pilot -Pilot $flat } catch { $refused = $true }
    Check 'dropping the crewman is REFUSED'  $refused

    "advancing the careers"
    $p2 = Get-Pilot
    $car = Get-Career $p2 @() -Sorties 12
    Check 'the pilot is due a step at 12'    ("$($car.rank)" -eq 'Oberleutnant') "$($car.rank)"
    $cc = Get-CrewCareer -Member (Get-Crew $p2)[0] -Pilot $p2 -Sorties 12
    Check 'the crewman is NOT, at 12'        ("$($cc.rank)" -eq 'Unteroffizier') "$($cc.rank)"
    $cc16 = Get-CrewCareer -Member (Get-Crew $p2)[0] -Pilot $p2 -Sorties 16
    Check 'the crewman steps up at 16'       ("$($cc16.rank)" -eq 'Feldwebel') "$($cc16.rank)"

    $hon = @(Get-LwHonours -Pilot $p2 -Career $car)
    $p3 = Update-CareerRecord -Pilot $p2 -Career $car -Honours $hon
    Check 'the pilot was promoted on disk'   ("$($p3.rank)" -eq 'Oberleutnant') "$($p3.rank)"
    $m = (Get-Crew $p3)[0]
    Check 'the crewman was left alone'       ("$($m.rank)" -eq 'Unteroffizier') "$($m.rank)"
    Check 'the crewman kept his name'        ("$($m.name)" -eq 'Kessler, H.')

    "his own decorations"
    $car2 = Get-Career $p3 @() -Sorties 30
    $p4 = Update-CareerRecord -Pilot $p3 -Career $car2 -Honours @(Get-LwHonours -Pilot $p3 -Career $car2)
    $m2 = (Get-Crew $p4)[0]
    $awards = @($m2.honours | ForEach-Object { "$($_.award)" })
    Check 'he has the EK II by 30 sorties'   ($awards -contains 'Eisernes Kreuz II. Klasse') "$($awards -join '; ')"
    Check 'and the EK I'                     ($awards -contains 'Eisernes Kreuz I. Klasse')
    Check 'no Ritterkreuz on his chest'      (-not ($awards -join ' ' -match 'Ritterkreuz'))
    Check 'his honours survived as objects'  (-not ("$($m2.honours)" -match 'Hashtable')) "$($m2.honours)"
    Check 'he was promoted by 30'            ("$($m2.rank)" -eq 'Feldwebel') "$($m2.rank)"

    "his seat, not a flight command"
    $ap = Get-CrewAppointment -Member $m2 -Career (Get-CrewCareer -Member $m2 -Pilot $p4 -Sorties 30)
    Check 'his appointment is his seat'      ($ap -eq 'Bordfunker') "$ap"
}
finally {
    Remove-Item $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue
}
""
if ($fails) { "$fails FAILURE(S)"; exit 1 } else { 'ALL CREW CHECKS PASSED'; exit 0 }
