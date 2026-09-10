# =====================================================================
#  THE SQUADRON ROOM
#  Fullscreen dispersal: the readiness board, the framed photograph on the
#  wall, your logbook, the sector map and the morning paper.
#
#  It READS the game's campaign save (the pilot, the date, and the Log
#  Book of your own sorties and victories) and it can LAUNCH the game.
#  It never writes to the game's own files. Its state lives in
#  <GameDir>\SquadronRoom\: pilot.json, sessions.json, autoclaim.json,
#  ringpos.json, flight.open, before.bsr and archive\. Portraits, rosters,
#  the order of battle and the newspaper ship read-only in .\squadronroom\.
# =====================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ModDir      = Join-Path $ScriptDir 'squadronroom'
# The RAF keeps its art at the top of squadronroom\ and the Luftwaffe in
# lw\ beneath it. Set by Set-AssetSide, which Set-StateSide calls, so the
# art and the state can never end up describing different air forces.
$PortraitDir = Join-Path $ModDir 'portraits'
$PortIndex   = Join-Path $ModDir 'portraits.json'
$BadgeDir    = Join-Path $ModDir 'badges'
$AircraftDir = Join-Path $ModDir 'aircraft'
function Set-AssetSide {
    param([string]$Side)
    $base = if ($Side -eq 'lw') { Join-Path $ModDir 'lw' } else { $ModDir }
    $script:SideModDir  = $base
    $script:PortraitDir = Join-Path $base 'portraits'
    $script:PortIndex   = Join-Path $base 'portraits.json'
    $script:BadgeDir    = Join-Path $base 'badges'
    $script:AircraftDir = Join-Path $base 'aircraft'
}

function Find-GameDir {
    foreach ($d in @($ScriptDir, (Split-Path $ScriptDir -Parent))) {
        if ($d -and (Test-Path (Join-Path $d 'Bob.exe'))) { return $d }
    }
    return $null
}
$GameDir   = Find-GameDir

# =====================================================================
#  WHICH AIR FORCE
#
#  BOB2 is flown from either side, and a man can keep a British and a
#  German career at once. Each side gets its own folder under the state
#  root, so the two never see each other's pilot, log book or claims:
#
#      <GameDir>\SquadronRoom\raf\pilot.json
#      <GameDir>\SquadronRoom\lw\pilot.json
#
#  The six state paths are DERIVED from $StateDir, and were derived once
#  at load. Change $StateDir on its own and every one of them still points
#  at the old folder, which is the trap dev\README-testing.md was written
#  about. Set-StateSide is now the only place any of them is assigned, and
#  they are always assigned together.
# =====================================================================
$StateRoot = if ($GameDir) { Join-Path $GameDir 'SquadronRoom' } else { Join-Path $ModDir 'state' }
# A test harness sets this to draw against a copy. Honoured by Set-StateSide,
# so it survives a side change instead of being quietly overwritten.
$script:StateRootOverride = $null
$script:Side = 'raf'

function Set-StateSide {
    param([string]$Side = $script:Side)
    $root = if ($script:StateRootOverride) { $script:StateRootOverride } else { $StateRoot }
    $script:Side       = $Side
    $script:StateDir   = Join-Path $root $Side
    $script:PilotPath    = Join-Path $script:StateDir 'pilot.json'
    $script:SessionsPath = Join-Path $script:StateDir 'sessions.json'
    $script:FlightOpen   = Join-Path $script:StateDir 'flight.open'
    $script:AcPosPath    = Join-Path $script:StateDir 'acpos.json'
    $script:AutoClaimPath = Join-Path $script:StateDir 'autoclaim.json'
    Set-AssetSide $Side
    if (Get-Command Load-MapProjection -ErrorAction SilentlyContinue) { Load-MapProjection $Side }
}
# WHICH SIDE THE ROOM OPENS ON. It always opened on the RAF, so a man
# with a German career had to find the side switch every time.
#
# The last side WRITTEN is the last side flown, because the Room saves the
# pilot record every time it draws his screens. The campaign save would be
# a truer source and it is not used: byte 0 of the .BSR is
# MissMan::currcampaignnum, which is WHICH campaign and not which side,
# and no other field is known to carry the nationality. The launcher picks
# its emblem by the same rule, in Get-LastRoomSide, so the button and the
# Room cannot disagree.
function Get-LastSide {
    $root = if ($script:StateRootOverride) { $script:StateRootOverride } else { $StateRoot }
    $best = 'raf'; $bestAt = $null
    foreach ($side in @('raf', 'lw')) {
        $f = Join-Path (Join-Path $root $side) 'pilot.json'
        if (-not (Test-Path $f)) { continue }
        $t = (Get-Item $f).LastWriteTimeUtc
        if (($null -eq $bestAt) -or ($t -gt $bestAt)) { $bestAt = $t; $best = $side }
    }
    $best
}
Set-StateSide 'raf'

# Careers made before there were two sides sit loose in the state root.
# Move them under raf\ so the German side can have its own.
#
# The rules here are all about not repeating 9 September 2026, when a
# career was lost to a careless write:
#
#   Copy, never move. The loose files stay exactly where they are. They
#   cost three kilobytes and they are a free way back.
#   Read the copy back and check it is a pilot BEFORE declaring success.
#   On any doubt at all, change nothing and carry on in the old shape. A
#   Room that works in the old layout beats one that half-moved.
function Initialize-StateLayout {
    $root = if ($script:StateRootOverride) { $script:StateRootOverride } else { $StateRoot }
    $flat = Join-Path $root 'pilot.json'
    $done = Join-Path $root 'layout.json'
    if ((Test-Path $done) -or -not (Test-Path $flat)) { return }
    $dst = Join-Path $root 'raf'
    if (Test-Path (Join-Path $dst 'pilot.json')) { return }   # someone got here first
    $log = Join-Path $root 'migrate.log'
    try {
        if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
        $moved = @()
        foreach ($f in @('pilot.json','sessions.json','autoclaim.json','acpos.json','flight.open','before.bsr')) {
            $src = Join-Path $root $f
            if (Test-Path $src) { Copy-Item $src (Join-Path $dst $f) -Force; $moved += $f }
        }
        $arch = Join-Path $root 'archive'
        if (Test-Path $arch) { Copy-Item $arch (Join-Path $dst 'archive') -Recurse -Force; $moved += 'archive\' }

        # Prove it before committing to it. A pilot.json that will not read
        # back as a pilot means the copy failed, whatever the file system
        # said, and the old layout is still good.
        $check = Get-Content (Join-Path $dst 'pilot.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $check -or -not "$($check.pilot)".Trim()) { throw 'the copied record does not read back as a pilot' }
        $srcN = @((Get-Content $flat -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties).Count
        $dstN = @($check.PSObject.Properties).Count
        if ($dstN -ne $srcN) { throw "the copy has $dstN fields where the original has $srcN" }

        @{ version = 2; migrated = (Get-Date).ToString('s'); from = 'flat'; files = $moved } |
            ConvertTo-Json -Depth 3 | Set-Content -Path $done -Encoding UTF8
        Add-Content -LiteralPath $log -Value ("{0}  moved to raf\: {1}" -f (Get-Date -Format 's'), ($moved -join ', ')) -ErrorAction SilentlyContinue
    }
    catch {
        # No layout.json is written, so this is retried next time rather
        # than being left half done, and the loose files are untouched.
        $script:StateLegacy = $true
        try { Add-Content -LiteralPath $log -Value ("{0}  FAILED, left in the old layout: {1}" -f (Get-Date -Format 's'), $_.Exception.Message) -ErrorAction SilentlyContinue } catch { }
        Set-StateSideLegacy
    }
}
# The old shape: everything loose in the state root, no side folder.
function Set-StateSideLegacy {
    $root = if ($script:StateRootOverride) { $script:StateRootOverride } else { $StateRoot }
    $script:StateDir      = $root
    $script:PilotPath     = Join-Path $root 'pilot.json'
    $script:SessionsPath  = Join-Path $root 'sessions.json'
    $script:FlightOpen    = Join-Path $root 'flight.open'
    $script:AcPosPath     = Join-Path $root 'acpos.json'
    $script:AutoClaimPath = Join-Path $root 'autoclaim.json'
}
Initialize-StateLayout

# --- squadrons a new pilot may join --------------------------------------
# Postings are PER CAMPAIGN PERIOD: P1 = the Channel battles (10 Jul),
# P2 = Eagle Day and the airfields (13 Aug), P3 = London (7 Sep).
# Each period entry is 'Station,ActionRating' or '-' when the squadron is
# resting in the north. Station anchors are image fractions on the table.
# Where each station sits on the sector map, as a fraction of its width
# and height. Read from squadronroom\map\sector-map.json, which the map
# renderer writes when it draws the image: the map and these positions
# come out of the same projection, so a ring cannot drift from the field
# it belongs to. The old table was thirteen anchors placed by eye, and
# every station beyond them had to be fitted to those.
$MapStations = @{}
$MapSectors  = @{}
$MapUnnamed  = @{}
$MapProj = $null
$MapProjPath = Join-Path (Join-Path $ModDir 'map') 'sector-map.json'
# Each air force has its own sheet and its own projection, so this is
# reloaded when the side changes rather than read once at startup. Drawn
# from the RAF projection, a German field would be plotted with England's
# arithmetic and land in the sea.
function Load-MapProjection {
    param([string]$Side = $script:Side)
    $script:MapStations = @{}
    $script:MapSectors  = @{}
    $script:MapUnnamed  = @{}
    $script:MapProj = $null
    $dir = if ($Side -eq 'lw') { Join-Path (Join-Path $ModDir 'lw') 'map' } else { Join-Path $ModDir 'map' }
    $file = if ($Side -eq 'lw') { 'kanalfront-map.json' } else { 'sector-map.json' }
    $script:MapProjPath = Join-Path $dir $file
    $script:MapImagePath = Join-Path $dir ($file -replace '\.json$', '.jpg')
    if (-not (Test-Path $script:MapProjPath)) { return }
    try {
        $script:MapProj = Get-Content $script:MapProjPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pp in $script:MapProj.stations.PSObject.Properties) {
            $script:MapStations[$pp.Name] = @([double]$pp.Value[0], [double]$pp.Value[1])
        }
        if ($script:MapProj.PSObject.Properties.Name -contains 'unnamed') {
            foreach ($nm in @($script:MapProj.unnamed)) {
                $script:MapUnnamed["$nm"] = $true; $script:MapUnnamed['RAF ' + $nm] = $true
            }
        }
        if ($script:MapProj.PSObject.Properties.Name -contains 'sectors') {
            foreach ($pp in $script:MapProj.sectors.PSObject.Properties) {
                $script:MapSectors[$pp.Name] = $pp.Value
                $script:MapSectors['RAF ' + $pp.Name] = $pp.Value
            }
        }
    } catch { }
}
if (Test-Path $MapProjPath) {
    try {
        $MapProj = Get-Content $MapProjPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($pp in $MapProj.stations.PSObject.Properties) {
            $MapStations[$pp.Name] = @([double]$pp.Value[0], [double]$pp.Value[1])
        }
        # The fields whose names the sheet does not print, because they are
        # packed too tightly to carry them. Their plaque says who they are.
        if ($MapProj.PSObject.Properties.Name -contains 'unnamed') {
            foreach ($nm in @($MapProj.unnamed)) { $MapUnnamed["$nm"] = $true; $MapUnnamed['RAF ' + $nm] = $true }
        }
        # which sector each field belonged to, and what it was in it
        if ($MapProj.PSObject.Properties.Name -contains 'sectors') {
            foreach ($pp in $MapProj.sectors.PSObject.Properties) {
                $MapSectors[$pp.Name] = $pp.Value
                $MapSectors['RAF ' + $pp.Name] = $pp.Value
            }
        }
    } catch { }
}
# A field's sector, in words. Fighter Command fought the Battle by sector:
# each had an operations room at its sector station that controlled the
# satellite and forward fields under it.
function Get-SectorText {
    param([string]$Base)
    $sec = $MapSectors[$Base]
    if (-not $sec) { return '' }
    $letter = "$($sec.letter)"; $station = "$($sec.station)"; $role = "$($sec.role)"
    $t = ''
    if ($role -eq 'sector station') {
        $t = if ($letter) { "Sector station for $letter Sector" } else { 'sector station' }
    }
    elseif ($station) {
        $whose = if ($letter) { "$letter Sector" } else { "$station's sector" }
        $t = "$role, $whose"
    }
    elseif ($role) { $t = $role }
    if ("$($sec.note)") { $t += " ($($sec.note))" }
    $t
}

# Squadron code letters as carried during the Battle, 10 July to 31
# October 1940. Every one confirmed against at least two dated sources
# (the per-squadron histories on Wikipedia and rafweb, checked against
# 1940 loss and photograph records).
#
# The trap here is the reallocation of September 1939: nearly every one of
# these squadrons changed code at the outbreak of war, so BL for 609, AW
# for 504, TM for 111, ZH for 501 and their like are 1938-39 codes and
# wrong for the Battle. Only 145, 213 and 616 kept theirs through it. Two
# changed during 1940 itself and had settled before 10 July: 92 from GR to
# QJ in May, and 257 from DT to ML and back to DT in June. 92 and 616
# genuinely shared QJ that summer.
$SquadronCodes = @{
      1='JX';   3='QO';  17='YB';  19='QV';  32='GZ';  41='EB';  43='FT';  46='PO'
     54='KL';  56='US';  64='SH';  65='YT';  66='LZ';  72='RN';  73='TP';  74='ZP'
     79='NV';  85='VY';  87='LK';  92='QJ'; 111='JU'; 145='SO'; 151='DZ'; 152='UM'
    213='AK'; 222='ZD'; 229='RE'; 232='EF'; 234='AZ'; 238='VK'; 242='LE'; 249='GN'
    253='SW'; 257='DT'; 263='HE'; 266='UO'; 302='WX'; 303='RF'; 310='NN'; 312='DU'
    501='SD'; 504='TM'; 601='UF'; 602='LO'; 603='XT'; 605='UP'; 607='AF'; 609='PR'
    610='DW'; 611='FY'; 615='KW'; 616='QJ'
}
# The campaign's four starting points, and the order of battle date each
# one reads. These are the game's own dates, not ours.
$Periods = @(
    @{ Id='P1'; Key='1940-07-10'; Label='10 JULY - THE CHANNEL';    Desc='convoy battles over the Channel' }
    @{ Id='P2'; Key='1940-08-12'; Label='12 AUGUST - EAGLE DAY';    Desc='the assault on the airfields' }
    @{ Id='P3'; Key='1940-08-24'; Label='24 AUGUST - THE AIRFIELDS'; Desc='the attack on the sector stations' }
    @{ Id='P4'; Key='1940-09-07'; Label='7 SEPTEMBER - LONDON';     Desc='the great daylight raids on London' }
)
# Every squadron in Fighter Command's order of battle, built from the
# game's own oob.json rather than a hand-kept list of the two dozen we
# happened to have codes for. Station and aircraft type per period come
# straight out of that file; the code letters come from $SquadronCodes;
# and how busy a station was is read from its group, since the order of
# battle does not record it: 11 Group bore the weight of the fighting,
# 10 and 12 Group saw steady action, and a squadron sent to 13 Group was
# resting.
function Build-Squadrons {
    $out = @()
    if (-not (Test-Path $OobPath)) { return $out }
    try {
        $all = @(Get-Content $OobPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        while ($all.Count -eq 1 -and ($all[0] -is [System.Array])) { $all = $all[0] }
    } catch { return $out }
    foreach ($o in $all) {
        $q = @{ Num = [int]$o.num; Type = "$($o.type)"; Code = '' }
        if ($SquadronCodes.ContainsKey([int]$o.num)) { $q.Code = $SquadronCodes[[int]$o.num] }
        foreach ($per in $Periods) {
            $v = ''
            if ($o.bases -and ($o.bases.PSObject.Properties.Name -contains $per.Key)) { $v = "$($o.bases.$($per.Key))" }
            if ((-not $v) -or ($v -match '^\s*13\s*Group\s*$')) { $q[$per.Id] = '-'; continue }
            if ($v -match '^\s*\d+\s*Group\s*$') { $q[$per.Id] = '-'; continue }
            $st = if ($v -match '^RAF ') { $v } else { "RAF $v" }
            # the order of battle spells North Weald two ways
            if ($st -eq 'RAF Northweald') { $st = 'RAF North Weald' }
            $grp = Get-GroupForBase $st
            $act = switch ($grp) { 11 { 'H' } 10 { 'M' } 12 { 'M' } default { 'L' } }
            $q[$per.Id] = "$st,$act"
        }
        $out += $q
    }
    $out
}
# a squadron's posting in a period: @{Base;Act;Mx;My} or $null when resting
function Get-Posting { param($Q, [string]$Period)
    $raw = "$($Q[$Period])"
    if ((-not $raw) -or ($raw -eq '-')) { return $null }
    $parts = $raw -split ','
    $base = $parts[0]; $act = if ($parts.Count -gt 1) { $parts[1] } else { 'M' }
    $st = $MapStations[$base]
    $mx = -1.0; $my = -1.0
    if ($st) { $mx = [double]$st[0]; $my = [double]$st[1] }
    @{ Base = $base; Act = $act; Mx = $mx; My = $my }
}
# Built once, on first use: Build-Squadrons needs Get-GroupForBase, which
# is defined further down the file, so it cannot run where it is written.
function Get-Squadrons {
    if (-not $script:SquadronList) { $script:SquadronList = @(Build-Squadrons) }
    $script:SquadronList
}
function Get-SquadronDef { param([int]$Num)
    foreach ($q in (Get-Squadrons)) { if ($q.Num -eq $Num) { return $q } }
    $null
}

# --- data ---------------------------------------------------------------
function Get-Portraits {
    if (Test-Path $PortIndex) { try { return @(Get-Content $PortIndex -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
    @(Get-ChildItem $PortraitDir -Filter '*.jpg' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.Name })
}
# The squadron's own men. Researched rosters live one file per unit in
# squadronroom/rosters (92's original seed file is still honoured).
function Get-Historical {
    param([int]$Sqn = 92)
    $per = Join-Path (Join-Path $ModDir 'rosters') "$Sqn.json"
    if (-not (Test-Path $per)) { return @() }
    $path = $per
    try {
        # ConvertFrom-Json hands a top-level JSON array back as ONE object,
        # and @() then wraps that in a second array. Without unrolling it
        # the whole roster rendered as a single airman whose name was every
        # name and whose source line was every credit (seen 2026-09-07).
        # Same loop as Get-Oob.
        $men = @(Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        while ($men.Count -eq 1 -and ($men[0] -is [System.Array])) { $men = $men[0] }
        return @($men)
    } catch { return @() }
}
# The game's own order of battle: real stations by campaign date, plus the
# skill and fatigue ratings it starts each squadron with (English/TEXT/
# RAF_OOB.htm, extracted to oob.json).
$OobPath = Join-Path $ModDir 'oob.json'
function Get-Oob {
    param([int]$Sqn)
    if (-not (Test-Path $OobPath)) { return $null }
    try {
        $all = @(Get-Content $OobPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        while ($all.Count -eq 1 -and ($all[0] -is [System.Array])) { $all = $all[0] }
        foreach ($o in $all) { if ([int]$o.num -eq $Sqn) { return $o } }
    } catch { }
    $null
}
function Get-Pilot {
    if (Test-Path $PilotPath) { try { return (Get-Content $PilotPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
    $null
}
# Every write in the program comes through here: Set-BulletinRead,
# Update-CareerRecord, Add-AutoClaims, Sync-CampaignClaims, Ensure-Serial,
# Ensure-Squadron and Invoke-Submit. That makes it the one place worth
# guarding, and on 9 September 2026 it needed guarding: a test harness
# built a stub pilot called "Test" and saved it over a real career. The
# function did exactly what it was told. Nothing warned, and nothing had
# kept a copy.
#
# Three rules, cheap enough to run on every write:
#
#   A record with no name is not a pilot. Refuse it.
#   A record with FEWER fields than the one on disk is a stub overwriting
#   a career. Refuse it unless the caller says -Shrink and means it.
#   Keep the last twenty versions, so a bad write is an inconvenience
#   rather than a loss.
#
# Sync-CampaignClaims already reasons about the second hazard in a comment
# of its own ("a stub containing only campaignKills would destroy a
# career"). This makes it a rule instead of a comment.
# How many fields a record has, whichever shape it arrives in.
#
# Half the callers build an [ordered]@{} and half pass the PSCustomObject
# that came back from ConvertFrom-Json, and .PSObject.Properties on a
# dictionary does NOT list what is in it: it lists the dictionary's own
# members, Count, Keys, Values and the rest. Always seven, whatever the
# record holds. Counting that way made the guard below refuse every
# legitimate write through Sync-CampaignClaims the moment a career grew
# past seven fields, which is to say immediately.
#
# It also counts THE CREW. A Bf 110 record carries a `crew` array of the
# other men in the aeroplane, and if only top-level keys were counted then
# losing a crewman's rank, his honours or the whole man would read as no
# change at all and the guard below would wave it through. The guard is
# here because a career was destroyed on 9 September; it should protect
# the second man as well as the first.
function Get-FieldCount {
    param($Obj)
    if ($null -eq $Obj) { return 0 }
    if ($Obj -is [System.Collections.IDictionary]) {
        $n = @($Obj.Keys).Count
        if ($Obj.Contains('crew')) { foreach ($m in @($Obj['crew'])) { $n += Get-FieldCount $m } }
        return $n
    }
    $n = @($Obj.PSObject.Properties).Count
    if ($Obj.PSObject.Properties.Name -contains 'crew') {
        foreach ($m in @($Obj.crew)) { $n += Get-FieldCount $m }
    }
    $n
}
function Save-Pilot {
    param($Pilot, [switch]$Shrink)
    if (-not $Pilot) { throw 'Save-Pilot was given nothing to save.' }
    $name = "$($Pilot.pilot)".Trim()
    if (-not $name) { throw 'Save-Pilot refused a record with no pilot name.' }

    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

    if (Test-Path $PilotPath) {
        $old = $null
        try { $old = Get-Content $PilotPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        if ($old) {
            if (-not $Shrink) {
                $wasN = Get-FieldCount $old
                $nowN = Get-FieldCount $Pilot
                if ($nowN -lt $wasN) {
                    throw ("Save-Pilot refused to replace a $wasN field record for " +
                           "'$($old.pilot)' with a $nowN field one for '$name'. " +
                           'Pass -Shrink if that is really meant.')
                }
            }
            # Keep the version being replaced, newest twenty only. Written
            # before the new one, so the copy on disk is always the last
            # good state rather than the one just written.
            try {
                $bak = Join-Path $StateDir 'archive\autobackup'
                if (-not (Test-Path $bak)) { New-Item -ItemType Directory -Path $bak -Force | Out-Null }
                # Milliseconds, not seconds. Drawing one screen can save
                # twice through Sync-CampaignClaims and Update-CareerRecord,
                # and at second resolution the second write overwrote the
                # first backup: thirty saves kept two copies, not twenty.
                Copy-Item $PilotPath (Join-Path $bak ('pilot-' + (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '.json')) -Force
                Get-ChildItem $bak -Filter 'pilot-*.json' -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending | Select-Object -Skip 20 |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            } catch { }
        }
    }
    # Depth 8, not 6: a crew member's honours array sits two levels deeper
    # than anything the record used to hold, and ConvertTo-Json silently
    # writes the string "System.Collections.Hashtable" once it runs out.
    $Pilot | ConvertTo-Json -Depth 8 | Set-Content -Path $PilotPath -Encoding UTF8
}

# =====================================================================
#  Window shell - fullscreen dispersal
# =====================================================================
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="The Squadron Room"
        WindowStyle="None" WindowState="Maximized" ResizeMode="NoResize"
        Background="#14212A" Foreground="#E9E3D4"
        UseLayoutRounding="True" TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI Variable Text, Segoe UI, Tahoma">
  <Window.Resources>
    <SolidColorBrush x:Key="Base"     Color="#14212A"/>
    <SolidColorBrush x:Key="Panel"    Color="#1B2B34"/>
    <SolidColorBrush x:Key="PanelHi"  Color="#213540"/>
    <SolidColorBrush x:Key="Rule"     Color="#2C424E"/>
    <SolidColorBrush x:Key="Ink"      Color="#E9E3D4"/>
    <SolidColorBrush x:Key="Muted"    Color="#9FB0B8"/>
    <SolidColorBrush x:Key="Faint"    Color="#6F828C"/>
    <SolidColorBrush x:Key="Brass"    Color="#C8973F"/>
    <SolidColorBrush x:Key="BrassDk"  Color="#8A6D34"/>
    <SolidColorBrush x:Key="Plate"    Color="#241E12"/>
    <SolidColorBrush x:Key="Good"     Color="#8FB56A"/>
    <SolidColorBrush x:Key="Warn"     Color="#D9A441"/>
    <SolidColorBrush x:Key="Danger"   Color="#D66A5C"/>
    <SolidColorBrush x:Key="RAFred"   Color="#C8102E"/>

    <Style x:Key="Serif" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Rockwell, Rockwell Nova, Georgia, Cambria, 'Times New Roman', serif"/>
    </Style>
    <Style x:Key="Cond" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0E171D"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="BorderBrush" Value="{StaticResource BrassDk}"/>
      <Setter Property="BorderThickness" Value="0,0,0,2"/>
      <Setter Property="Padding" Value="6,7"/><Setter Property="FontSize" Value="18"/>
      <Setter Property="FontFamily" Value="Georgia, Cambria, serif"/>
      <Setter Property="CaretBrush" Value="{StaticResource Brass}"/>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontFamily" Value="Bahnschrift SemiCondensed, Segoe UI"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="FontFamily" Value="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
      <Setter Property="FontSize" Value="16"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#171203"/>
      <Setter Property="Padding" Value="22,10"/><Setter Property="MinWidth" Value="150"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{StaticResource Brass}" BorderBrush="{StaticResource BrassDk}"
                    BorderThickness="1" CornerRadius="3" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#DCA84B"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- header: roundel, squadron, motto, close -->
    <Grid Grid.Row="0" Background="#101B22">
      <StackPanel Orientation="Horizontal" Margin="40,20,0,20" VerticalAlignment="Center">
        <Grid Width="52" Height="52" VerticalAlignment="Center">
          <!-- Fighter Command's roundel. -->
          <Grid x:Name="HdrRoundel">
            <Ellipse Fill="#1C3F94"/>
            <Ellipse Fill="#F2EFE6" Margin="8"/>
            <Ellipse Fill="#C8102E" Margin="17"/>
          </Grid>
          <!-- The Balkenkreuz: white bars with the black cross inside
               them, which is what the marking is on an aeroplane.

               The black is DARKER than the header rather than equal to
               it. At the header's own tone the cross vanished into the
               background and the emblem read as four white corner
               pieces instead of a cross. -->
          <Grid x:Name="HdrBalkenkreuz" Visibility="Collapsed">
            <Rectangle Fill="#F2EFE6" Width="52" Height="22" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Rectangle Fill="#F2EFE6" Width="22" Height="52" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Rectangle Fill="#07090B" Width="52" Height="11" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Rectangle Fill="#07090B" Width="11" Height="52" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
        </Grid>
        <StackPanel Margin="20,0,0,0" VerticalAlignment="Center">
          <TextBlock Style="{StaticResource Serif}" FontSize="27" FontWeight="Bold"
                     Foreground="{StaticResource Ink}" x:Name="HdrSquadron" Text="No. 92 Squadron"/>
          <TextBlock Style="{StaticResource Cond}" FontSize="13" Foreground="{StaticResource Faint}"
                     x:Name="HdrMotto" Text="ROYAL AIR FORCE  &#x2022;  AUT PUGNA AUT MORERE" Margin="1,3,0,0"/>
        </StackPanel>
        <!-- Which air force. Detection from the campaign save cannot help
             on the day a career starts, because a campaign that has flown
             nothing has no player record to read, so this is the way in
             rather than a fallback for odd cases. -->
        <StackPanel x:Name="SideSwitch" Orientation="Horizontal" Margin="26,0,0,0" VerticalAlignment="Center">
          <Border x:Name="SideRaf" Background="#213540" BorderBrush="#C8973F" BorderThickness="0,0,0,2"
                  CornerRadius="3,0,0,3" Cursor="Hand" Padding="13,7">
            <TextBlock x:Name="SideRafText" Text="RAF"
                       FontFamily="Bahnschrift SemiCondensed, Segoe UI" FontSize="12.5"
                       FontWeight="Bold" Foreground="#E9E3D4" VerticalAlignment="Center"/>
          </Border>
          <Border x:Name="SideLw" Background="#101B22" BorderBrush="#101B22" BorderThickness="0,0,0,2"
                  CornerRadius="0,3,3,0" Cursor="Hand" Padding="13,7">
            <TextBlock x:Name="SideLwText" Text="LUFTWAFFE"
                       FontFamily="Bahnschrift SemiCondensed, Segoe UI" FontSize="12.5"
                       FontWeight="Bold" Foreground="#6F828C" VerticalAlignment="Center"/>
          </Border>
        </StackPanel>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,84,0">
        <!-- the way back, and the one thing to press on whatever screen is
             up: reporting to a squadron, or for duty. They live in the
             header because the header does not scroll and the screens
             below it do. -->
        <Border x:Name="RoomBack" Background="#101B22" BorderBrush="#22303C" BorderThickness="1"
                CornerRadius="3" Cursor="Hand" Padding="18,9" Margin="0,0,14,0" Visibility="Collapsed">
          <TextBlock x:Name="RoomBackText" Text="&#x2190;  BACK"
                     FontFamily="Bahnschrift SemiCondensed, Segoe UI" FontSize="15"
                     FontWeight="Bold" Foreground="#9FB0B8" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="RoomAction" Background="#C8973F" CornerRadius="3" Cursor="Hand"
                Padding="22,10" Visibility="Collapsed">
          <TextBlock x:Name="RoomActionText" Text="REPORT TO THIS SQUADRON"
                     FontFamily="Bahnschrift SemiCondensed, Segoe UI" FontSize="16"
                     FontWeight="Bold" Foreground="#171203" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="RoomPlay" Background="#C8973F" CornerRadius="3" Cursor="Hand" Padding="26,10">
          <TextBlock Text="PLAY" FontFamily="Bahnschrift SemiCondensed, Segoe UI" FontSize="17"
                     FontWeight="Bold" Foreground="#171203" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="RoomNewCareer" Background="#A6252F" CornerRadius="3" Cursor="Hand" Padding="20,10" Margin="14,0,0,0">
          <TextBlock Text="START A NEW CAREER" FontFamily="Bahnschrift SemiCondensed, Segoe UI" FontSize="15"
                     FontWeight="Bold" Foreground="#F7ECE6" VerticalAlignment="Center"/>
        </Border>
      </StackPanel>
      <Border x:Name="ChromeClose" Width="52" Height="52" Background="Transparent"
              HorizontalAlignment="Right" VerticalAlignment="Top" Cursor="Hand" Margin="0,0,10,0">
        <TextBlock Text="&#x2715;" Foreground="#9FB0B8" FontSize="17"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <Rectangle Height="2" VerticalAlignment="Bottom" Fill="#8A6D34" Opacity="0.55"/>
    </Grid>

    <!-- stage: views injected here, centred with a max width -->
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <Grid>
        <StackPanel x:Name="Stage" MaxWidth="1240" Margin="40,28,40,28" HorizontalAlignment="Center"/>
      </Grid>
    </ScrollViewer>

    <!-- footer -->
    <Grid Grid.Row="2" Background="#101B22">
      <TextBlock Style="{StaticResource Cond}" Foreground="{StaticResource Faint}" FontSize="12.5"
                 Margin="40,10,0,10" VerticalAlignment="Center"
                 Text="Battle of Britain II &#x2022; The Squadron Room &#x2022; press Esc to close"/>
    </Grid>
  </Grid>
</Window>
'@

$Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$Xaml)))
function C { param($n) $Win.FindName($n) }
function Res { param($k) $Win.FindResource($k) }

# never vanish silently again: surface any handler error
$Win.Dispatcher.add_UnhandledException({
    param($s,$e)
    [System.Windows.MessageBox]::Show(($e.Exception.Message + "`n`n" + $e.Exception.StackTrace), 'Squadron Room error') | Out-Null
    $e.Handled = $true
})
$Win.Add_KeyDown({ param($s,$e) if ($e.Key -eq 'Escape') { $Win.Close() } })
# Coming back from a flight started with PLAY: log the sortie, take the
# claims and redraw whatever screen is showing. Without this the Room sat
# on a stale logbook, stale claims and yesterday's campaign date until it
# was closed and opened again.
$script:CurrentTab = 'dispersal'
function Show-Tab {
    param([string]$Tab)
    $script:CurrentTab = $Tab
    $pl = Get-Pilot
    # No career on this side yet: send him to the right board, not the
    # RAF's. A German pilot arriving at the Fighter Command plotting table
    # would be able to report to No. 32 Squadron from it.
    if (-not $pl) {
        if ($script:Side -eq 'lw') { Show-GruppeSelect } else { Show-SquadronSelect }
        return
    }
    switch ($Tab) {
        'logbook' { if ($script:Side -eq 'lw') { Show-Flugbuch -Pilot $pl } else { Show-Logbook -Pilot $pl } }
        'map'     { if ($script:Side -eq 'lw') { Show-GruppeSelect } else { Show-Map -Pilot $pl } }
        'paper'   { if ($script:Side -eq 'lw') { Show-Morgenmeldung -Pilot $pl } else { Show-Paper -Pilot $pl } }
        'gruppen' { Show-GruppeSelect }
        default   { if ($script:Side -eq 'lw') { Show-ReadyRoom -Pilot $pl } else { Show-Roster -Pilot $pl } }
    }
}
$Win.Add_Activated({
    if ($script:Activating) { return }
    if (Test-GameRunning) { return }
    if (-not (Test-Path $FlightOpen)) { return }
    $script:Activating = $true
    try { Finalize-Flight; Show-Tab $script:CurrentTab } catch { } finally { $script:Activating = $false }
})
# PLAY from inside the Room: same flight-marker pipeline as the launcher,
# so the sortie logs itself; then the game starts via the pinning bat.
$rp = C 'RoomPlay'
if ($rp) {
    $rp.Add_MouseLeftButtonUp({
        if (-not $GameDir) { [System.Windows.MessageBox]::Show('Run the Squadron Room from the game folder to fly.', 'Squadron Room') | Out-Null; return }
        if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) { [System.Windows.MessageBox]::Show('The game is already running.', 'Squadron Room') | Out-Null; return }
        try {
            if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
            $before = ''
            $cd0 = Get-CampaignDate
            if ($cd0) { $before = $cd0.ToString('yyyy-MM-dd') }
            $sav0 = Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            # record WHICH save was snapshotted: byte offsets only line up
            # against the same slot, and "newest" can be a different file
            # after the flight (Auto Save vs a named save)
            @{ start = (Get-Date).ToString('s'); dateBefore = $before; savePath = $(if ($sav0) { $sav0.FullName } else { '' }) } |
                ConvertTo-Json | Set-Content -Path $FlightOpen -Encoding UTF8
            if ($sav0) { Copy-Item $sav0.FullName (Join-Path $StateDir 'before.bsr') -Force }
        } catch { }
        $bat = Join-Path $ScriptDir 'BOB2_Launch.bat'
        if (Test-Path $bat) { Start-Process -FilePath $bat -WorkingDirectory $GameDir }
        else { Start-Process -FilePath (Join-Path $GameDir 'Bob.exe') -WorkingDirectory $GameDir }
        $Win.WindowState = 'Minimized'
    })
    $rp.Add_MouseEnter({ param($se,$e) $se.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#DCA84B') })
    $rp.Add_MouseLeave({ param($se,$e) $se.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#C8973F') })
}
$rb = C 'RoomBack'
if ($rb) {
    $rb.Add_MouseLeftButtonUp({ if ($script:ChromeBackDo) { & $script:ChromeBackDo } })
    $rb.Add_MouseEnter({ param($se,$e) $se.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom('#C8973F') })
    $rb.Add_MouseLeave({ param($se,$e) $se.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom('#22303C') })
}
$ra = C 'RoomAction'
if ($ra) {
    $ra.Add_MouseLeftButtonUp({ if ($script:ChromeActionOn -and $script:ChromeActionDo) { & $script:ChromeActionDo } })
    $ra.Add_MouseEnter({ param($se,$e) if ($script:ChromeActionOn) { $se.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#DCA84B') } })
    $ra.Add_MouseLeave({ param($se,$e) if ($script:ChromeActionOn) { $se.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#C8973F') } })
}
# Move between the two air forces. Each keeps its own pilot, log book and
# claims under its own folder, so nothing of one is visible from the other
# and a man can have a British and a German career at the same time.
foreach ($pair in @(@('SideRaf','raf'), @('SideLw','lw'))) {
    $seg = C $pair[0]
    if (-not $seg) { continue }
    $seg.Tag = $pair[1]
    # Pressing the side you are already in does nothing rather than
    # rebuilding the screen under the pointer.
    $seg.Add_MouseLeftButtonUp({
        param($sender, $e)
        if ("$($sender.Tag)" -ne $script:Side) { Set-Side "$($sender.Tag)" }
    })
}
function Update-SideSwitch {
    # Both segments are always there; the one you are in is lit and the
    # other is dim, so the control says where you are AND what it will do.
    $lwOn = ($script:Side -eq 'lw')
    foreach ($x in @(@('SideRaf','SideRafText', -not $lwOn), @('SideLw','SideLwText', $lwOn))) {
        $b = C $x[0]; $t = C $x[1]; $on = [bool]$x[2]
        if ($b) {
            $b.Background  = [Windows.Media.BrushConverter]::new().ConvertFrom($(if ($on) { '#213540' } else { '#101B22' }))
            $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFrom($(if ($on) { '#C8973F' } else { '#101B22' }))
        }
        if ($t) { $t.Foreground = [Windows.Media.BrushConverter]::new().ConvertFrom($(if ($on) { '#E9E3D4' } else { '#6F828C' })) }
    }
    # The emblem is the quickest way to see which air force is up. The RAF
    # gets its roundel and the Luftwaffe its Balkenkreuz, rather than the
    # header quietly changing a word nobody reads.
    $lw = ($script:Side -eq 'lw')
    $r = C 'HdrRoundel';      if ($r) { $r.Visibility = $(if ($lw) { 'Collapsed' } else { 'Visible' }) }
    $b = C 'HdrBalkenkreuz';  if ($b) { $b.Visibility = $(if ($lw) { 'Visible' } else { 'Collapsed' }) }
}
function Set-Side {
    param([string]$Side)
    Set-StateSide $Side
    $script:SquadronList = $null
    $script:SelSq = $null
    Update-SideSwitch
    $p = Get-Pilot
    if ($Side -eq 'lw') {
        if ($p) { Show-ReadyRoom -Pilot $p } else { Show-GruppeSelect }
    }
    else {
        if ($p) { Show-Roster -Pilot $p } else { Show-SquadronSelect }
    }
}

$rnc = C 'RoomNewCareer'
if ($rnc) {
    $rnc.Add_MouseLeftButtonUp({ Start-NewCareer })
    $rnc.Add_MouseEnter({ param($se,$e) $se.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#C23440') })
    $rnc.Add_MouseLeave({ param($se,$e) $se.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#A6252F') })
}
$cx = C 'ChromeClose'
if ($cx) {
    $cx.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled = $true; $Win.Close() })
    $cx.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#C8102E') })
    $cx.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
}

# --- brushes / helpers --------------------------------------------------
function B { param([string]$hex) [Windows.Media.BrushConverter]::new().ConvertFrom($hex) }
$script:BrassBrush = (B '#C8973F'); $script:BrassBrush.Freeze()
$script:FrameBrush = (B '#8A6D34'); $script:FrameBrush.Freeze()
$script:Stage = C 'Stage'

function Load-Portrait {
    param([string]$File, [int]$DecodeHeight = 300)
    $path = Join-Path $PortraitDir $File
    if (-not (Test-Path $path)) { return $null }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption   = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile
        $bmp.DecodePixelHeight = $DecodeHeight
        $bmp.UriSource = [Uri]$path
        $bmp.EndInit(); $bmp.Freeze()
        return $bmp
    } catch { return $null }
}
function Load-Image {
    param([string]$Path, [int]$DecodeWidth = 0)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption   = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile
        if ($DecodeWidth -gt 0) { $bmp.DecodePixelWidth = $DecodeWidth }
        $bmp.UriSource = [Uri]$Path
        $bmp.EndInit(); $bmp.Freeze()
        return $bmp
    } catch { return $null }
}
# Insignia chips cut from the 1943 'Rank and Badges' booklet: rank cuffs,
# the pilot's flying badge, and medal ribbons. Each renders as a small
# framed print so the period paper ground reads as intentional.
function New-BadgeImage {
    param([string]$File, [double]$Height = 40, [string]$Tip)
    $bmp = Load-Image -Path (Join-Path $BadgeDir $File)
    if (-not $bmp) { return $null }
    $img = New-Object Windows.Controls.Image
    $img.Source = $bmp; $img.Height = $Height; $img.Stretch = 'Uniform'
    $bd = New-Object Windows.Controls.Border
    $bd.BorderBrush = Res 'Rule'; $bd.BorderThickness = '1'
    $bd.SnapsToDevicePixels = $true; $bd.VerticalAlignment = 'Center'
    if ($Tip) { $bd.ToolTip = $Tip }
    $bd.Child = $img
    $bd
}
function Get-RankBadgeFile {
    param([string]$Rank)
    # The German collar patches. Order matters, as it does below: this is
    # -Regex and matches substrings, so Oberfeldwebel must be tested
    # before Feldwebel and Oberleutnant before Leutnant, or both come out
    # one rank too low. Hauptmann has none: it is a command, not a rung,
    # and New-BadgeImage returning $null leaves the rank in words.
    if ($script:Side -eq 'lw') {
        switch -Regex ($Rank) {
            '^Oberfeldwebel' { return 'oberfeldwebel.png' }
            '^Feldwebel'     { return 'feldwebel.png' }
            '^Unteroffizier' { return 'unteroffizier.png' }
            '^Oberleutnant'  { return 'oberleutnant.png' }
            '^Leutnant'      { return 'leutnant.png' }
        }
        return $null
    }
    switch -Regex ($Rank) {
        '^Sergeant'          { return 'sergeant.png' }
        '^Pilot Officer'     { return 'pilot-officer.png' }
        '^Flying Officer'    { return 'flying-officer.png' }
        '^Flight Lieutenant' { return 'flight-lieutenant.png' }
        '^Squadron Leader'   { return 'squadron-leader.png' }
    }
    return $null
}
# One chip per decoration in wearing order; a Bar becomes the rosette
# variant of the same ribbon, never a second ribbon. MiD has no ribbon of
# its own in 1940, so it stays a written honour.
# The ribbons, left to right in the order they were worn: British
# gallantry awards by precedence, then the awards of an allied government,
# which came after all of them however high they stood at home.
function New-RibbonRow {
    param($Honours, [double]$Height = 15)
    $set = @($Honours)
    $items = @()
    if ($set -contains 'VC')  { $items += @{ f='ribbon-vc.png';  t='Victoria Cross' } }
    if ($set -contains 'Bar to DSO')     { $items += @{ f='ribbon-dso-bar.png'; t='Distinguished Service Order and Bar' } }
    elseif ($set -contains 'DSO')        { $items += @{ f='ribbon-dso.png';     t='Distinguished Service Order' } }
    if ($set -contains 'Bar to DFC')     { $items += @{ f='ribbon-dfc-bar.png'; t='Distinguished Flying Cross and Bar' } }
    elseif ($set -contains 'DFC')        { $items += @{ f='ribbon-dfc.png';     t='Distinguished Flying Cross' } }
    if ($set -contains 'Bar to DFM')     { $items += @{ f='ribbon-dfm-bar.png'; t='Distinguished Flying Medal and Bar' } }
    elseif ($set -contains 'DFM')        { $items += @{ f='ribbon-dfm.png';     t='Distinguished Flying Medal' } }
    if ($set -contains 'Virtuti Militari')          { $items += @{ f='ribbon-vm.png';   t='Virtuti Militari, 5th Class (Poland)' } }
    if ($set -contains 'Cross of Valour')           { $items += @{ f='ribbon-kw.png';   t='Cross of Valour, Krzyz Walecznych (Poland)' } }
    if ($set -contains 'Czechoslovak War Cross')    { $items += @{ f='ribbon-czwc.png'; t='Czechoslovak War Cross 1939' } }
    if ($items.Count -eq 0) { return $null }
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
    foreach ($i in $items) {
        $chip = New-BadgeImage -File $i.f -Height $Height -Tip $i.t
        if ($chip) { $chip.Margin = '0,0,6,0'; [void]$row.Children.Add($chip) }
    }
    if ($row.Children.Count -eq 0) { return $null }
    $row
}
function New-TB {
    param([string]$Text, [string]$Family = 'Segoe UI', [double]$Size = 15, $Colour, [switch]$Bold, [switch]$Wrap)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontFamily = $Family; $t.FontSize = $Size
    if ($Bold) { $t.FontWeight = 'SemiBold' }
    if ($Colour) { $t.Foreground = B $Colour }
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    $t
}
$BattleStart = [datetime]'1940-07-10'
$BattleEnd   = [datetime]'1940-10-31'
$SerifFam = 'Rockwell, Georgia, Cambria, serif'
$CondFam  = 'Bahnschrift SemiCondensed, Segoe UI'
function Fate-Colour { param([string]$s)
    # Survival is checked FIRST: "Survived BoB (Later WIA/POW)" is a man
    # who came through the Battle, and used to render as a casualty.
    if ($s -match 'Survived|On strength') { return '#8FB56A' }
    if ($s -match 'KIA|Killed|Died|DoW|MIA|Missing|Failed to return|Lost') { return '#D66A5C' }
    if ($s -match 'WIA|Wounded|Injured') { return '#D9A441' }
    if ($s -match 'POW|Captured|Prisoner') { return '#9FB0B8' }
    '#8FB56A'
}

# --- campaign clock: the board is a snapshot of THIS day ----------------
# Reads the newest campaign save: u32 seconds since 1901-01-01 at OFFSET
# 57, the campaign's CURRENT day. Offsets 49/53 hold the campaign start
# and 61 a later date (a campaign end or scheduled event) - reading 61
# put the whole Room a month ahead of the game. Verified against Bob.exe's
# own constant (1247184000 = 10 Jul 1940) and against the game's Log Book
# and Combat Report: across one sortie offset 57 moved 10 -> 11 July while
# 61 sat still at 11 August. $null when no campaign.
function Get-CampaignDate {
    if (-not $GameDir) { return $null }
    $dir = Join-Path $GameDir 'SAVEGAME'
    if (-not (Test-Path $dir)) { return $null }
    $sav = Get-ChildItem $dir -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $sav) { return $null }
    try {
        $b = [System.IO.File]::ReadAllBytes($sav.FullName)
        if ($b.Length -lt 70) { return $null }
        $hdr = [System.Text.Encoding]::ASCII.GetString($b, 1, 20)
        if ($hdr -notmatch '^Rowan Savegame: V 0') { return $null }
        $secs = [BitConverter]::ToUInt32($b, 57)
        if ($secs % 86400 -ne 0) { return $null }
        $date = ([datetime]'1901-01-01').AddSeconds($secs)
        if ($date.Year -lt 1939 -or $date.Year -gt 1941) { return $null }
        return $date
    } catch { return $null }
}
# Where a squadron stood on a given date.
#
# Two sources, in order. First a researched move list for squadrons we
# have one for (below). Then the game's own order of battle in oob.json,
# which carries four campaign dates per squadron and is the truth for the
# campaign the player is flying; its "13 Group" means withdrawn north to
# rest, and is shown as such rather than as a station.
#
# This replaces three separate "if the squadron is 92" special cases in
# the dispersal, the map and the newspaper, which left every other
# squadron standing at its first posting for the whole Battle - No. 32
# was still at Biggin Hill in October although the campaign had sent it
# north on 7 September.
$SquadronMoves = @{
    92 = @(
        @{ d = [datetime]'1940-01-01'; f = 'RAF Croydon' },
        @{ d = [datetime]'1940-05-23'; f = 'RAF Hornchurch' },
        @{ d = [datetime]'1940-06-18'; f = 'RAF Pembrey' },
        @{ d = [datetime]'1940-09-08'; f = 'RAF Biggin Hill' }
    )
}
function Get-SquadronBase {
    param([int]$Sqn, $Date, $Pilot)
    if ($Date -and $SquadronMoves.ContainsKey($Sqn)) {
        $cur = $null
        foreach ($m in $SquadronMoves[$Sqn]) { if ($Date -ge $m.d) { $cur = $m.f } }
        if ($cur) { return $cur }
    }
    if ($Date) {
        $oob = Get-Oob -Sqn $Sqn
        if ($oob -and $oob.bases) {
            $best = $null; $bestD = $null
            foreach ($pr in $oob.bases.PSObject.Properties) {
                try { $kd = [datetime]::ParseExact($pr.Name, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { continue }
                if ($Date -ge $kd -and ((-not $bestD) -or ($kd -gt $bestD))) { $bestD = $kd; $best = "$($pr.Value)" }
            }
            if ($best) {
                if ($best -match '^\s*\d+\s*Group\s*$') { return 'resting in the north' }
                if ($best -notmatch '^RAF ') { return "RAF $best" }
                return $best
            }
        }
    }
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'base') -and $Pilot.base) { return "$($Pilot.base)" }
    $null
}
# The campaign pilot from the newest save. The .BSR carries the pilot
# surname at file offset 100 and the aircraft name at 121 (char[21], NUL
# padded) inside the campaign block - see modernization/BSR_FORMAT.md.
function Get-CampaignPilot {
    if (-not $GameDir) { return $null }
    $dir = Join-Path $GameDir 'SAVEGAME'
    if (-not (Test-Path $dir)) { return $null }
    $sav = Get-ChildItem $dir -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $sav) { return $null }
    try {
        $b = [System.IO.File]::ReadAllBytes($sav.FullName)
        if ($b.Length -lt 160) { return $null }
        if ([System.Text.Encoding]::ASCII.GetString($b, 1, 20) -notmatch '^Rowan Savegame: V 0') { return $null }
        $name  = [System.Text.Encoding]::ASCII.GetString($b, 100, 21).TrimEnd([char]0)
        if ($name -notmatch '^[ -~]{2,20}$') { return $null }
        # The save also carries an aircraft name at 121 - "Silver Eagle" by
        # default - and it is not shown. RAF fighters in 1940 were known by
        # their squadron code and individual letter, QJ-K, and their serial.
        # Machines were pooled: a man flew whatever was serviceable that
        # morning, so a personally named aeroplane is not a thing he had.
        # The names that WERE painted on were presentation names, put there
        # by the Spitfire Fund for the donor, and nothing to do with the
        # pilot. This one is the game's invention, so it stays out.
        return @{ Name = $name }
    } catch { return $null }
}
# Pull a date out of a fate string like "KIA 19 Oct 1940" / "24 Sept 1940"
function Parse-FateDate {
    param([string]$s)
    if ($s -match '(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\s+(\d{4})') {
        $mon = $matches[2].Substring(0,3)
        try { return [datetime]::ParseExact("$($matches[1]) $mon $($matches[3])", 'd MMM yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
    }
    return $null
}
# One date out of a roster record, in the schema's yyyy-MM-dd form.
function Get-RosterDate {
    param($P, [string]$Field)
    if (($P.PSObject.Properties.Name -contains $Field) -and $P.$Field) {
        try { return [datetime]::ParseExact("$($P.$Field)", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    $null
}
# The day a man joined the squadron. Not researched for most men yet, and
# a null means he was there when the Battle opened.
function Get-JoinDate { param($P) Get-RosterDate $P 'joined' }
# The day he left it, for whatever reason. Null means he was still on
# strength when the Battle ended.
function Get-LeaveDate {
    param($P)
    $d = Get-RosterDate $P 'left'
    if ($d) { return $d }
    if (($P.PSObject.Properties.Name -contains 'fate') -and $P.fate -and $P.fate.date) {
        try { return [datetime]::ParseExact("$($P.fate.date)", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    # older files kept the date in the status text
    Parse-FateDate "$($P.status)"
}
function Get-FateDate { param($P) Get-LeaveDate $P }
# Was this man on the squadron's strength on this day?
function Test-OnStrength {
    param($P, $Date)
    if (-not $Date) { return $true }
    $j = Get-JoinDate $P; if ($j -and ($Date -lt $j)) { return $false }
    $l = Get-LeaveDate $P; if ($l -and ($Date -ge $l)) { return $false }
    $true
}
# How his service ended, in words, from the schema's fate record.
function Get-FateText {
    param($P, [switch]$Short)
    if (($P.PSObject.Properties.Name -contains 'fate') -and $P.fate) {
        if ($P.fate.note -and -not $Short) { return "$($P.fate.note)" }
        switch ("$($P.fate.status)") {
            'KIA' { return 'Killed in action' }
            'MIA' { return 'Missing' }
            'DoW' { return 'Died of wounds' }
            'POW' { return 'Prisoner of war' }
            'WIA' { return 'Wounded' }
            'Survived' { return 'Survived the Battle' }
        }
        return "$($P.fate.status)"
    }
    "$($P.status)"
}
# What this pilot's status reads AS OF the campaign date. Before his loss he
# is on strength; on or after, his recorded fate. No date -> final record.
function Resolve-Status {
    param($P, $Date)
    $raw = Get-FateText $P
    if ($Date) {
        $j = Get-JoinDate $P
        if ($j -and ($Date -lt $j)) { return @{ Text = "Joins $($j.ToString('d MMM'))"; Colour = '#6F828C' } }
        $l = Get-LeaveDate $P
        if ($l) {
            if ($Date -lt $l) { return @{ Text = 'On strength'; Colour = '#8FB56A' } }
        }
        elseif ($Date -le $BattleEnd) {
            # No date for this man's ending. While the Battle is still being
            # fought nobody's is known yet, so he stands on strength: the
            # board used to announce "Survived BoB" for every survivor on
            # the first morning, which gave the whole war away.
            return @{ Text = 'On strength'; Colour = '#8FB56A' }
        }
    }
    @{ Text = $raw; Colour = (Fate-Colour $raw) }
}
# Victories credited by the campaign date.
#
# Where a man's claims are researched they carry their own dates and are
# simply counted up to the day. Where only his Battle total is known, it is
# spread evenly across his time with the squadron, and the figure is an
# estimate: the roster note on the board says which of the two this
# squadron has.
function Get-DatedVictories {
    param($P)
    if (($P.PSObject.Properties.Name -contains 'victories') -and $P.victories -and ($P.victories -is [System.Array] -or $P.victories.Count)) {
        return @($P.victories)
    }
    @()
}
function Accrue-Victories {
    param($P, $Date)
    $dated = Get-DatedVictories $P
    if ($dated.Count -gt 0) {
        if (-not $Date) { return "$($dated.Count)" }
        $n = 0
        foreach ($v in $dated) {
            $vd = $null
            try { $vd = [datetime]::ParseExact("$($v.date)", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { }
            if ($vd -and ($vd -le $Date)) { $n++ }
        }
        return "$n"
    }
    $total = 0
    if (($P.PSObject.Properties.Name -contains 'victories_total') -and ($null -ne $P.victories_total)) { $total = [int]$P.victories_total }
    elseif (($P.PSObject.Properties.Name -contains 'victories') -and ($P.victories -is [int])) { $total = [int]$P.victories }
    if ($total -le 0) { return '' }
    if (-not $Date) { return "$total" }
    $start = Get-JoinDate $P; if (-not $start) { $start = $BattleStart }
    $end = Get-LeaveDate $P; if (-not $end) { $end = $BattleEnd }
    if ($Date -le $start) { return '0' }
    if ($end -le $start) { return "$total" }
    if ($Date -ge $end) { return "$total" }
    $frac = ($Date - $start).TotalDays / ($end - $start).TotalDays
    "$([math]::Round($total * $frac))"
}
# Decorations, shown once the campaign date reaches the (approx) award date.
# Decorations, each shown once the campaign date reaches its own date. An
# award with no date is shown from the start, since we cannot say when it
# was gazetted.
function Get-Awards {
    param($P, $Date)
    if (-not (($P.PSObject.Properties.Name -contains 'awards') -and $P.awards)) { return '' }
    $out = @()
    foreach ($a in @($P.awards)) {
        $name = if ($a -is [string]) { "$a" } else { "$($a.award)" }
        if (-not $name) { continue }
        if ($Date -and -not ($a -is [string]) -and $a.date) {
            try {
                $ad = [datetime]::ParseExact("$($a.date)", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                if ($Date -lt $ad) { continue }
            } catch { }
        }
        $out += $name
    }
    ($out -join ', ')
}

# --- a framed photograph on the wall ------------------------------------
function New-Frame {
    param($Pilot, [switch]$IsPlayer)
    $col = New-Object Windows.Controls.StackPanel
    $col.Width = 196; $col.Margin = '0,0,22,26'

    # brass/wood frame around the photograph
    $frame = New-Object Windows.Controls.Border
    $frame.Background = if ($IsPlayer) { Res 'Brass' } else { Res 'BrassDk' }
    $frame.CornerRadius = '2'; $frame.Padding = '5'
    $frame.SnapsToDevicePixels = $true

    $photo = New-Object Windows.Controls.Border
    $photo.Height = 208; $photo.Background = B '#0B1116'; $photo.ClipToBounds = $true
    $file = $null
    if ($Pilot.PSObject.Properties.Name -contains 'portrait') { $file = $Pilot.portrait }
    if ($file) {
        $bmp = Load-Portrait -File $file -DecodeHeight 300
        if ($bmp) {
            $img = New-Object Windows.Controls.Image
            $img.Source = $bmp; $img.Stretch = 'UniformToFill'
            $photo.Child = $img
        }
    }
    if (-not $photo.Child) {
        $ini = New-Object Windows.Controls.TextBlock
        $nm = "$($Pilot.pilot)".Trim()
        $ini.Text = if ($nm.Length -gt 0) { $nm.Substring(0,1).ToUpper() } else { '?' }
        $ini.FontFamily = $SerifFam; $ini.FontSize = 66; $ini.Foreground = B '#33414B'
        $ini.HorizontalAlignment = 'Center'; $ini.VerticalAlignment = 'Center'
        $photo.Child = $ini
    }
    $frame.Child = $photo
    [void]$col.Children.Add($frame)
    $col
}

# --- the player's aircraft: a Spitfire profile with live codes and serial --
# per-type profile art and marking defaults (roundel positions measured)
# The serial was painted about eight inches high on the rear fuselage,
# against code letters of twenty-four to thirty: roughly a quarter their
# height, not the two thirds it was drawn at. The wheel adjusts it from
# there, and what you choose is kept per mark of aircraft.
function Get-AircraftSpec { param([string]$Type)
    if ($Type -match 'Hurricane') {
        return @{ Img='hurricane.png'; Ratio=(300.0/1000.0); SqX=0.4118; SqY=0.3474; IndX=0.6313; IndY=0.3532; SerX=0.7182; SerTy=0.4900; CodeSize=78.0; SerSize=22.0 }
    }
    @{ Img='spitfire.png'; Ratio=(324.0/1000.0); SqX=0.4194; SqY=0.3461; IndX=0.6727; IndY=0.3326; SerX=0.7443; SerTy=0.4650; CodeSize=84.0; SerSize=24.0 }
}
$AcW          = 760.0            # on-screen width; height follows the image
# historically-approximate: RAF 'Sky' grey block codes, black serial
$CodeFont     = 'Bahnschrift SemiBold, Bahnschrift, Franklin Gothic Medium, Arial'
$CodeColour   = '#C3C9B4'
$SerialFont   = 'Bahnschrift Condensed, Arial Narrow, Arial'
$SerialColour = '#171712'
# The aircraft markings were once draggable, and saved where you dropped
# them. The feature was removed; New-Aircraft paints them from the spec.
function New-Serial {
    param([string]$Type = 'Spitfire I')
    if ($Type -match 'Hurricane') {
        $pool = @(@{p='P2';lo=550;hi=999}, @{p='P3';lo=30;hi=980}, @{p='V6';lo=530;hi=999}, @{p='V7';lo=200;hi=499})
        $pick = $pool | Get-Random
        return ('{0}{1:000}' -f $pick.p, (Get-Random -Minimum $pick.lo -Maximum $pick.hi))
    }
    $pool = @(@{p='R';lo=6800;hi=6999}, @{p='N';lo=3200;hi=3299}, @{p='X';lo=4200;hi=4399}, @{p='P';lo=9300;hi=9499})
    $pick = $pool | Get-Random
    "$($pick.p)$(Get-Random -Minimum $pick.lo -Maximum $pick.hi)"
}
# Give an older pilot (made before serials existed) one, and save it, so the
# tail marking paints without having to recreate the pilot.
function Ensure-Serial {
    param($Pilot)
    if ($null -eq $Pilot) { return $Pilot }
    if (($Pilot.PSObject.Properties.Name -contains 'serials') -and $Pilot.serials) { return $Pilot }
    $obj = [ordered]@{}
    foreach ($p in $Pilot.PSObject.Properties) { $obj[$p.Name] = $p.Value }
    $obj['serials'] = New-Serial
    Save-Pilot $obj
    Get-Pilot
}
# Older pilots predate squadron choice: they are 92 Squadron men.
function Ensure-Squadron {
    param($Pilot)
    if ($null -eq $Pilot) { return $Pilot }
    if (($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { return $Pilot }
    $obj = [ordered]@{}
    foreach ($pp in $Pilot.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
    # A pilot made before squadrons existed is a 92 Squadron man. His
    # station is NOT set here: Get-SquadronBase knows where 92 stood on
    # any date, and a stored 'RAF Biggin Hill' used to override it and
    # contradict the record of service on the same screen.
    $obj['sqn'] = 92; $obj['sqcode'] = 'QJ'; $obj['actype'] = 'Spitfire I'
    Save-Pilot $obj
    Get-Pilot
}
# Which group a station belonged to in 1940. Every station named in the
# order of battle is listed; anything unknown is taken for 11 Group, which
# is where most of the fighting was.
function Get-GroupForBase { param([string]$Base)
    if ($Base -match 'Pembrey|Exeter|Warmwell|Middle Wallop|Boscombe|Colerne|Filton|St Eval') { return 10 }
    if ($Base -match 'Duxford|Digby|Coltishall|Fowlmere|Kirton|Wittering') { return 12 }
    if ($Base -match 'Acklington|Catterick|Church Fenton|Drem|Turnhouse|Usworth|Leconfield|Prestwick|Dyce|Grangemouth|Wick') { return 13 }
    11
}
# Squadron mottoes, for the ones we know. Anything else gets its group.
$SquadronMottoes = @{
    32 = 'ADESTE COMITES'
    92 = 'AUT PUGNA AUT MORERE'
}
# PLAY and START A NEW CAREER belong to a career that exists. While a man
# is still picking his squadron there is nothing to play and nothing to
# start over, and the board's own button is the only thing to press.
function Show-ChromeButtons {
    param([bool]$Show)
    foreach ($n in @('RoomPlay', 'RoomNewCareer')) {
        $el = C $n
        if ($el) { $el.Visibility = $(if ($Show) { 'Visible' } else { 'Collapsed' }) }
    }
    if ($Show) { Set-ChromeAction -Text ''; Set-ChromeBack -Text '' }
}
# the way out of a screen, in the header for the same reason
$script:ChromeBackDo = $null
function Set-ChromeBack {
    param([string]$Text, $OnClick)
    $el = C 'RoomBack'; $tb = C 'RoomBackText'
    if (-not $el) { return }
    if (-not $Text) { $el.Visibility = 'Collapsed'; $script:ChromeBackDo = $null; return }
    if ($tb) { $tb.Text = ([char]0x2190) + '  ' + $Text }
    $script:ChromeBackDo = $OnClick
    $el.Visibility = 'Visible'
}
# The screen's own action, sitting in the header where it cannot be
# scrolled past. A man was missing REPORT TO THIS SQUADRON entirely
# because it sat under a map seven hundred pixels tall.
$script:ChromeActionOn = $false
$script:ChromeActionDo = $null
function Set-ChromeActionEnabled {
    param([bool]$On)
    $el = C 'RoomAction'; $tb = C 'RoomActionText'
    if (-not $el) { return }
    $script:ChromeActionOn = $On
    $el.Background = B $(if ($On) { '#C8973F' } else { '#26313A' })
    $el.Cursor = $(if ($On) { 'Hand' } else { 'Arrow' })
    if ($tb) { $tb.Foreground = B $(if ($On) { '#171203' } else { '#6F828C' }) }
}
function Set-ChromeAction {
    param([string]$Text, [bool]$Enabled = $false, $OnClick)
    $el = C 'RoomAction'; $tb = C 'RoomActionText'
    if (-not $el) { return }
    if (-not $Text) {
        $el.Visibility = 'Collapsed'; $script:ChromeActionDo = $null; $script:ChromeActionOn = $false
        return
    }
    if ($tb) { $tb.Text = $Text }
    $script:ChromeActionDo = $OnClick
    $el.Visibility = 'Visible'
    Set-ChromeActionEnabled $Enabled
}
function Set-Header {
    param($Pilot)
    Show-ChromeButtons $true
    # No default squadron: an unposted pilot gets the service, not 92's
    # number and 92's group, which is what this used to show.
    $num = 0; $grp = 0
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { $num = [int]$Pilot.sqn }
    $base = Get-SquadronBase -Sqn $num -Date $script:CampaignDate -Pilot $Pilot
    if ($base) { $grp = Get-GroupForBase "$base" }
    $h = C 'HdrSquadron'
    if ($h) { $h.Text = if ($num -gt 0) { "No. $num Squadron" } else { 'Royal Air Force' } }
    $m = C 'HdrMotto'
    if ($m) {
        $m.Text = if ($num -gt 0 -and $SquadronMottoes.ContainsKey($num)) { "ROYAL AIR FORCE  $([char]0x2022)  $($SquadronMottoes[$num])" }
                  elseif ($grp -gt 0) { "ROYAL AIR FORCE  $([char]0x2022)  NO. $grp GROUP, FIGHTER COMMAND" }
                  else { "ROYAL AIR FORCE  $([char]0x2022)  FIGHTER COMMAND" }
    }
}
# Where the code letters and the serial sit on the aeroplane. The spec
# gives the researched position; anything nudged by hand is kept here,
# and kept PER TYPE, because a Hurricane's fuselage is not a Spitfire's
# and a letter that sits right on one lands on the roundel of the other.
# assigned by Set-StateSide, with every other state path, so a side
# change cannot leave this one pointing at the other air force
function Get-AcKey { param([string]$Type) if ("$Type" -match 'Hurricane') { 'Hurricane' } else { 'Spitfire' } }
function Get-AcPos {
    $t = @{}
    if (Test-Path $AcPosPath) {
        try {
            $j = Get-Content $AcPosPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) {
                $x = [double]$p.Value.x; $y = [double]$p.Value.y
                $sz = 0.0
                if ($p.Value.PSObject.Properties.Name -contains 's') { $sz = [double]$p.Value.s }
                # a mark dragged off the picture, or shrunk to nothing, could
                # never be caught again
                if ($sz -gt 0 -and ($sz -lt 8 -or $sz -gt 140)) { $sz = 0.0 }
                if ($x -ge -0.05 -and $x -le 1.05 -and $y -ge -0.05 -and $y -le 1.05) {
                    $rec = @{ x = $x; y = $y }
                    if ($sz -gt 0) { $rec['s'] = $sz }
                    $t[$p.Name] = $rec
                }
            }
        } catch { }
    }
    $t
}
function Save-AcPos {
    param($Table)
    try {
        if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
        ($Table | ConvertTo-Json -Depth 4) | Set-Content -Path $AcPosPath -Encoding UTF8
    } catch { }
}
function New-Aircraft {
    param($Pilot)
    $ptype = 'Spitfire I'
    if (($Pilot.PSObject.Properties.Name -contains 'actype') -and $Pilot.actype) { $ptype = "$($Pilot.actype)" }
    $spec = Get-AircraftSpec $ptype
    $AircraftImg = Join-Path (Join-Path $ModDir 'aircraft') $spec.Img
    if (-not (Test-Path $AircraftImg)) { return $null }
    $acH = $AcW * [double]$spec.Ratio
    $script:AcW = $AcW; $script:AcHpx = $acH
    $wrap = New-Object Windows.Controls.Grid
    $wrap.Width = $AcW; $wrap.Height = $acH; $wrap.HorizontalAlignment = 'Left'; $wrap.Margin = '0,2,0,10'
    $img = New-Object Windows.Controls.Image
    $bmp = Load-Image -Path $AircraftImg -DecodeWidth 900
    if ($bmp) { $img.Source = $bmp }
    $img.Stretch = 'Fill'; $img.Width = $AcW; $img.Height = $acH
    [void]$wrap.Children.Add($img)

    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $AcW; $cv.Height = $acH
    $codes = "$($Pilot.codes)"
    $sq = ($codes -replace '-.*','')
    $ind = ''; if ($codes -match '-(.+)$') { $ind = $matches[1] }

    $script:AcPos = Get-AcPos
    $acKey = Get-AcKey $ptype

    # The RAF codes are DRAWN TEXT, as they always were.
    #
    # They were briefly switched to BOB2's own letter tiles, placed by the
    # game's own MultiSkin coordinates, and Patrick's call is to leave the
    # RAF as it was. The measurement stands and is worth keeping: it
    # confirmed the horizontal placement here is right to within one or
    # two per cent of what the game does. What it could not settle is the
    # vertical, because the game positions a picture and this positions a
    # TextBlock, whose leading sits above the glyphs, so the two numbers
    # are not comparable without calibrating the font - and nobody had
    # seen the tile version rendered.
    #
    # squadronroom/marking-positions.json keeps the RAF measurements, and
    # dev/build_raf_markings.py will cut the tiles again if anyone wants
    # to take it up. Nothing reads either on this side.
    $tSq  = Add-AcMark -Canvas $cv -Key "$acKey|sq"  -Text $sq  -Family $CodeFont   -Size ([double]$spec.CodeSize) `
                       -Colour $CodeColour   -DX ([double]$spec.SqX)  -DY ([double]$spec.SqY)  -W $AcW -H $acH
    $tInd = Add-AcMark -Canvas $cv -Key "$acKey|ind" -Text $ind -Family $CodeFont   -Size ([double]$spec.CodeSize) `
                       -Colour $CodeColour   -DX ([double]$spec.IndX) -DY ([double]$spec.IndY) -W $AcW -H $acH
    $ser = "$($Pilot.serials)"
    if ($ser) {
        [void](Add-AcMark -Canvas $cv -Key "$acKey|ser" -Text $ser -Family $SerialFont -Size ([double]$spec.SerSize) `
                          -Colour $SerialColour -DX ([double]$spec.SerX) -DY ([double]$spec.SerTy) -W $AcW -H $acH)
    }
    [void]$wrap.Children.Add($cv)
    $wrap
}
# One mark on the aeroplane: drawn where the spec says, or where it was
# last put by hand, and draggable to somewhere better. Dragging is the
# whole point of it, so no modifier is asked for -- but a press that does
# not move is not a drag, and nothing is written for it.
function Save-AcMark {
    param($Mark)
    $t = $Mark.Tag
    $script:AcPos[$t.Key] = @{
        x = [math]::Round([Windows.Controls.Canvas]::GetLeft($Mark) / $t.W, 4)
        y = [math]::Round([Windows.Controls.Canvas]::GetTop($Mark)  / $t.H, 4)
        s = [math]::Round($Mark.FontSize, 2)
    }
    Save-AcPos $script:AcPos
}
function Add-AcMark {
    param($Canvas, [string]$Key, [string]$Text, [string]$Family, [double]$Size,
          [string]$Colour, [double]$DX, [double]$DY, [double]$W, [double]$H)
    $fx = $DX; $fy = $DY; $pt = $Size
    if ($script:AcPos.ContainsKey($Key)) {
        $rec = $script:AcPos[$Key]
        $fx = [double]$rec.x; $fy = [double]$rec.y
        if ($rec.ContainsKey('s') -and [double]$rec.s -gt 0) { $pt = [double]$rec.s }
    }
    $tb = New-TB -Text $Text -Family $Family -Size $pt -Colour $Colour -Bold
    # a TextBlock with no brush is hit-testable only on its glyphs, and the
    # gaps between letters would drop the drag
    $tb.Background = B '#00000000'
    $tb.Cursor = 'SizeAll'
    $tb.ToolTip = 'Drag to move, roll the wheel to size it. Double-click to put it back where the research says.'
    [Windows.Controls.Canvas]::SetLeft($tb, $fx * $W)
    [Windows.Controls.Canvas]::SetTop($tb,  $fy * $H)
    $tb.Tag = @{ Key = $Key; W = $W; H = $H; DX = $DX; DY = $DY; DS = $Size
                 Drag = $false; Moved = $false; OX = 0.0; OY = 0.0 }
    $tb.Add_MouseWheel({
        param($sender, $e)
        $t = $sender.Tag
        $n = $sender.FontSize * $(if ($e.Delta -gt 0) { 1.06 } else { 1.0 / 1.06 })
        $n = [math]::Max(8.0, [math]::Min(140.0, $n))
        $sender.FontSize = $n
        Save-AcMark $sender
        $e.Handled = $true
    })
    $tb.Add_MouseLeftButtonDown({
        param($sender, $e)
        $t = $sender.Tag
        if ($e.ClickCount -ge 2) {
            [Windows.Controls.Canvas]::SetLeft($sender, $t.DX * $t.W)
            [Windows.Controls.Canvas]::SetTop($sender,  $t.DY * $t.H)
            $sender.FontSize = $t.DS
            $script:AcPos.Remove($t.Key); Save-AcPos $script:AcPos
            $e.Handled = $true; return
        }
        $p = $e.GetPosition($sender.Parent)
        $t.OX = $p.X - [Windows.Controls.Canvas]::GetLeft($sender)
        $t.OY = $p.Y - [Windows.Controls.Canvas]::GetTop($sender)
        $t.Drag = $true; $t.Moved = $false
        [void]$sender.CaptureMouse(); $e.Handled = $true
    })
    $tb.Add_MouseMove({
        param($sender, $e)
        $t = $sender.Tag
        if (-not $t.Drag) { return }
        $p = $e.GetPosition($sender.Parent)
        $nx = $p.X - $t.OX; $ny = $p.Y - $t.OY
        if (-not $t.Moved -and ([math]::Abs($nx - [Windows.Controls.Canvas]::GetLeft($sender)) -le 2) `
                          -and ([math]::Abs($ny - [Windows.Controls.Canvas]::GetTop($sender)) -le 2)) { return }
        $t.Moved = $true
        $nx = [math]::Max(-20.0, [math]::Min($t.W - 10.0, $nx))
        $ny = [math]::Max(-20.0, [math]::Min($t.H - 10.0, $ny))
        [Windows.Controls.Canvas]::SetLeft($sender, $nx)
        [Windows.Controls.Canvas]::SetTop($sender, $ny)
    })
    $tb.Add_MouseLeftButtonUp({
        param($sender, $e)
        $t = $sender.Tag
        if (-not $t.Drag) { return }
        $t.Drag = $false; [void]$sender.ReleaseMouseCapture()
        if (-not $t.Moved) { return }
        Save-AcMark $sender
    })
    [void]$Canvas.Children.Add($tb)
    $tb
}

function New-Heading {
    param([string]$Eyebrow, [string]$Title)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '0,0,0,22'
    if ($Eyebrow) {
        $e = New-TB -Text $Eyebrow -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold
        [void]$sp.Children.Add($e)
    }
    $t = New-TB -Text $Title -Family $SerifFam -Size 24 -Colour '#E9E3D4' -Bold
    $t.Margin = '0,4,0,0'
    [void]$sp.Children.Add($t)
    $sp
}

# =====================================================================
#  Views
# =====================================================================
function Add-Cell {
    param($Grid,[string]$Text,[int]$Col,[string]$Fam='Segoe UI',[double]$Size=14,$Colour,[switch]$Right,[switch]$Center,[switch]$Bold)
    $t = New-TB -Text $Text -Family $Fam -Size $Size -Colour $Colour -Bold:$Bold
    $t.VerticalAlignment = 'Center'; $t.TextTrimming = 'CharacterEllipsis'
    if ($Right) { $t.HorizontalAlignment = 'Right'; $t.Margin = '0,0,4,0' }
    elseif ($Center) { $t.HorizontalAlignment = 'Center' }
    [Windows.Controls.Grid]::SetColumn($t,$Col)
    [void]$Grid.Children.Add($t)
}
function New-RosterRow {
    param($P,[switch]$Header,[int]$Index=0,[switch]$IsPlayer,[switch]$Invented,[switch]$CampaignLost)
    $b = New-Object Windows.Controls.Border
    $b.Padding = '18,10,18,10'; $b.BorderThickness = '0,0,0,1'; $b.BorderBrush = Res 'Rule'
    if ($Header) { $b.Background = B '#101B22' }
    elseif ($IsPlayer) { $b.Background = B '#26313B'; $b.BorderBrush = Res 'BrassDk' }
    elseif ($Index % 2 -eq 1) { $b.Background = Res 'Panel' }
    else { $b.Background = Res 'PanelHi' }
    # An invented man is marked wherever he appears, and never dressed to
    # look like a record.
    if ($Invented) { $b.BorderBrush = B '#5A4A2A'; $b.BorderThickness = '2,0,0,1' }
    elseif ($CampaignLost) { $b.BorderBrush = B '#6B3A2E'; $b.BorderThickness = '2,0,0,1' }

    $g = New-Object Windows.Controls.Grid
    foreach ($w in @('*','110','150','300')) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)) }
        else { $cd.Width = New-Object Windows.GridLength([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }

    if ($Header) {
        Add-Cell $g 'PILOT'          0 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'VICTORIES'      1 $CondFam 12 '#C8973F' -Bold -Center
        Add-Cell $g 'AWARDS'         2 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'STATUS / FATE'  3 $CondFam 12 '#C8973F' -Bold
    } else {
        $ns = New-Object Windows.Controls.StackPanel
        [void]$ns.Children.Add((New-TB -Text ("$($P.pilot)") -Family $SerifFam -Size 15.5 -Colour $(if ($Invented) { '#B9AE93' } else { '#E9E3D4' })))
        $rc = "$($P.rank)"; if ($P.codes) { $rc = "$($P.rank)   $([char]0x2022)   $($P.codes)" }
        if ($Invented) { $rc += "   $([char]0x2022)   INVENTED, NOT A HISTORICAL RECORD" }
        $rct = New-TB -Text $rc -Family $CondFam -Size 11.5 -Colour '#6F828C'; $rct.Margin = '0,2,0,0'
        [void]$ns.Children.Add($rct)
        [Windows.Controls.Grid]::SetColumn($ns,0); [void]$g.Children.Add($ns)

        $vic = if ($IsPlayer) { $(if ([int]$P.victories -gt 0) { "$($P.victories)" } else { '' }) } else { Accrue-Victories $P $script:CampaignDate }
        Add-Cell $g $vic 1 $CondFam 16 '#D9B45A' -Center -Bold
        $aw = if ($IsPlayer) { "$($P.awards)" } else { Get-Awards $P $script:CampaignDate }
        Add-Cell $g $aw 2 $CondFam 13.5 '#C8973F' -Bold
        if ($Invented) {
            Add-Cell $g 'Lost in this campaign' 3 $CondFam 13.5 '#D66A5C'
        } elseif ($CampaignLost) {
            # Your campaign, not the record. Both are shown, so the board
            # never quietly rewrites a man's war.
            $real = Get-FateText $P -Short
            $txt = 'Lost in your campaign'
            if ($real -and $real -ne 'Survived the Battle') { $txt += "  ($real in the record)" }
            elseif ($real) { $txt += '  (survived, in the record)' }
            Add-Cell $g $txt 3 $CondFam 13 '#C77A5C'
        } else {
            $stat = Resolve-Status $P $script:CampaignDate
            Add-Cell $g $stat.Text 3 $CondFam 13.5 $stat.Colour
        }
    }
    $b.Child = $g
    $b
}
# =====================================================================
#  Phase 2: the self-filling logbook
# =====================================================================
function Test-GameRunning { [bool](Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) }

function Get-Sessions {
    # Returns only real session objects. Repairs two legacy corruptions:
    # the ConvertTo-Json value/Count wrapper shape, and empty-array
    # elements leaked in by an old comma-return (both made the count
    # read nonzero with no flights, unlocking the aircraft early).
    $out = @()
    if (Test-Path $SessionsPath) {
        try {
            $j = Get-Content $SessionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j -and ($j.PSObject.Properties.Name -contains 'value')) { $j = $j.value }
            $out = @($j) | Where-Object { $_ -and ($_ -isnot [array]) -and ($_.PSObject.Properties.Name -contains 'end') }
        } catch { $out = @() }
    }
    $out
}
function Save-Sessions {
    param($S)
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $flat = @(@($S) | Where-Object { $_ -and ($_ -isnot [array]) })
    ConvertTo-Json -InputObject $flat -Depth 6 | Set-Content -Path $SessionsPath -Encoding UTF8
}
# When the room opens after a flight, turn the launcher's flight marker into
# a logged sortie. End time is taken from the newest save (best proxy for
# when flying stopped); the campaign date each side records a day flown.
function Finalize-Flight {
    if (-not (Test-Path $FlightOpen)) { return }
    if (Test-GameRunning) { return }
    $mk = $null
    try { $mk = Get-Content $FlightOpen -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    if (-not $mk) { Remove-Item $FlightOpen -Force -ErrorAction SilentlyContinue; return }
    $start = $null; try { $start = [datetime]$mk.start } catch { }
    $end = $null
    if ($GameDir) {
        $sav = Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($sav) { $end = $sav.LastWriteTime }
    }
    if (-not $end) { $end = Get-Date }
    $mins = 0
    if ($start) { $mins = [int][math]::Max(0, ($end - $start).TotalMinutes) }
    $after = Get-CampaignDate
    # outcome: did the campaign move on while you flew? Compare the save the
    # launcher snapshotted at Play against the newest one now.
    $outcome = ''
    $beforeSnap = Join-Path $StateDir 'before.bsr'
    try {
        $newest = $null
        if ($GameDir) { $newest = Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
        if ($mk.dateBefore) {
            $dAfter = if ($after) { $after.ToString('yyyy-MM-dd') } else { '' }
            if ($dAfter -and ($dAfter -gt "$($mk.dateBefore)")) { $outcome = 'Campaign day flown' }
            elseif ((Test-Path $beforeSnap) -and $newest) {
                $a = [System.IO.File]::ReadAllBytes($beforeSnap)
                $b2 = [System.IO.File]::ReadAllBytes($newest.FullName)
                $same = ($a.Length -eq $b2.Length)
                if ($same) { for ($i = 0; $i -lt $a.Length; $i += 97) { if ($a[$i] -ne $b2[$i]) { $same = $false; break } } }
                $outcome = if ($same) { 'No campaign progress' } else { 'Campaign progressed' }
            }
        } else { $outcome = 'Practice flight' }
    } catch { }
    # ---- automatic claims -------------------------------------------
    # Level the record with the campaign's Log Book (see Sync-CampaignClaims);
    # the snapshot only records how many rows the flight added.
    $autoAdded = 0
    try {
        $rowsBefore = -1
        if (Test-Path $beforeSnap) { $dB = Get-SaveDiary -Path $beforeSnap; if ($dB) { $rowsBefore = @($dB.rows).Count } }
        $v0 = 0; $p0 = Get-Pilot; if ($p0 -and ($p0.PSObject.Properties.Name -contains 'victories') -and $p0.victories) { $v0 = [int]$p0.victories }
        $dA = Sync-CampaignClaims
        $p1 = Get-Pilot; $v1 = 0; if ($p1 -and ($p1.PSObject.Properties.Name -contains 'victories') -and $p1.victories) { $v1 = [int]$p1.victories }
        $autoAdded = [math]::Max(0, $v1 - $v0)
        if ($dA) {
            Save-AutoClaim ([ordered]@{
                table      = $dA.table
                rowsBefore = $rowsBefore
                rowsAfter  = @($dA.rows).Count
                totalAfter = $dA.total
                credited   = $autoAdded
                lastFlight = (Get-Date).ToString('s')
            })
        }
    } catch { }
    Remove-Item $beforeSnap -Force -ErrorAction SilentlyContinue
    $sess = [ordered]@{
        end        = $end.ToString('s')
        minutes    = $mins
        dateBefore = "$($mk.dateBefore)"
        dateAfter  = if ($after) { $after.ToString('yyyy-MM-dd') } else { "$($mk.dateBefore)" }
        mode       = if ($mk.dateBefore) { 'campaign' } else { 'instant' }
        outcome    = $outcome
        claims     = $autoAdded
    }
    # A marker is written at every Play, including the ones where nobody
    # flew. Only a flight is a sortie: time in the air, a new Log Book row,
    # or the campaign moved on. Everything else is dropped silently, which
    # is what used to fill the table with 0-minute duplicates.
    $flew = ($mins -gt 0) -or ($autoAdded -gt 0) -or ($outcome -eq 'Campaign day flown')
    # A new row in the game's own Log Book is a flight - but only when
    # there WAS a before-count to compare against. rowsBefore is -1 when no
    # snapshot was taken, and "0 rows now is more than -1 rows then" used
    # to make every non-flight look like a sortie.
    try {
        $ac2 = Get-AutoClaim
        if ($ac2 -and ($ac2.PSObject.Properties.Name -contains 'rowsBefore')) {
            $rb = [int]$ac2.rowsBefore; $ra = [int]$ac2.rowsAfter
            if ($rb -ge 0 -and $ra -gt $rb) { $flew = $true }
        }
    } catch { }
    if ($flew) { Save-Sessions (@(Get-Sessions) + $sess) }
    Remove-Item $FlightOpen -Force -ErrorAction SilentlyContinue
}

function Get-Career {
    param($Pilot, $Sessions, [int]$Sorties = -1)
    $sorties = if ($Sorties -ge 0) { $Sorties } else { @($Sessions).Count }
    $mins = 0; foreach ($s in $Sessions) { $mins += [int]$s.minutes }
    $hours = [math]::Round($mins / 60.0, 1)
    if (($Pilot.PSObject.Properties.Name -contains 'cmode') -and ("$($Pilot.cmode)" -eq 'commander')) {
        # a Gruppenkommandeur was a Hauptmann; a Major would be a
        # Kommodore, and a Geschwader is not on offer here
        $cmd = if ($script:Side -eq 'lw') { 'Hauptmann' } else { 'Squadron Leader' }
        return @{ sorties = $sorties; hours = $hours; rank = $cmd; next = $null; nextAt = 0 }
    }
    $ladder = Get-RankLadder -Rank "$($Pilot.rank)"
    # The stored rank is a FLOOR, not a starting point: a man promoted at
    # twelve sorties keeps his rank even if a new campaign resets the count.
    $idx = [array]::IndexOf($ladder, "$($Pilot.rank)"); if ($idx -lt 0) { $idx = 0 }
    $step = 12
    $promos = [math]::Floor($sorties / $step)
    $curIdx = [math]::Min($ladder.Count - 1, [math]::Max($idx, $promos))
    $next = $null; $nextAt = 0
    # counted off the rung he STANDS on, not off the promotions he has
    # earned: a man commissioned on the day he joined starts one rung up,
    # and his next step is at 24 sorties, not the 12 that would take a
    # sergeant to where he already is
    if ($curIdx -lt $ladder.Count - 1) { $next = $ladder[$curIdx + 1]; $nextAt = ($curIdx + 1) * $step }
    @{ sorties = $sorties; hours = $hours; rank = $ladder[$curIdx]; next = $next; nextAt = $nextAt }
}
# THE SECOND MAN'S CAREER, on the same sorties as the first.
#
# He flies every sortie the pilot flies, so the count is shared and only
# the ladder and the step differ. Everything here is invented; see the
# note on $CrewByType. Nothing in it is read from the save, and no screen
# that shows it may present it as though it were.
function Get-CrewCareer {
    param($Member, $Pilot, [int]$Sorties, [double]$Hours = 0)
    $role = "$($Member.role)"
    # sorties flown SINCE HE JOINED THE CREW. A man who replaces a lost
    # Bordfunker does not inherit the sorties flown before he arrived.
    $base = 0
    if ($Member.PSObject.Properties.Name -contains 'sortiesBase') { $base = [int]$Member.sortiesBase }
    $his = [math]::Max(0, $Sorties - $base)
    $ladder = Get-CrewLadder -Role $role -Rank "$($Member.rank)"
    $idx = [array]::IndexOf($ladder, "$($Member.rank)"); if ($idx -lt 0) { $idx = 0 }
    $promos = [math]::Floor($his / $CrewRankStep)
    $curIdx = [math]::Min($ladder.Count - 1, [math]::Max($idx, $promos))
    $next = $null; $nextAt = 0
    if ($curIdx -lt $ladder.Count - 1) { $next = $ladder[$curIdx + 1]; $nextAt = ($curIdx + 1) * $CrewRankStep + $base }
    @{ sorties = $his; hours = $Hours; rank = $ladder[$curIdx]; next = $next; nextAt = $nextAt
       role = $role; step = $CrewRankStep }
}
# What he is doing, which is his seat and nothing else. Rottenflieger,
# Schwarmfuehrer and Staffelkapitaen are flying-leadership appointments
# and none of them belongs to a man in the back.
function Get-CrewAppointment {
    param($Member, $Career)
    $role = "$($Member.role)"
    if ($role -eq 'Bordfunker' -and [int]$Career.sorties -ge 40) { return 'Bordfunkermeister' }
    switch ($role) {
        'Bordfunker'     { 'Bordfunker' }
        'Beobachter'     { 'Beobachter' }
        'Bordmechaniker' { 'Bordmechaniker' }
        'Bordschuetze'   { 'Bordschuetze' }
        default          { $role }
    }
}
# His decorations, earned on SORTIES rather than on victories.
#
# Patrick's decision, and the right one: the save records one kill tally
# per sortie with no gun position, so splitting it between the pilot and
# the man on the rear MG would be a fabricated attribution sitting next to
# figures that really are read from the save. He has no victories here, so
# the Ritterkreuz and the Eichenlaub - both awarded on a score - are not
# on his ladder at all. What is left is what a crewman actually got: the
# Iron Cross, on sorties flown and a unit recommendation.
function Get-CrewHonours {
    param($Member, $Career)
    $out = @()
    if ($Member.PSObject.Properties.Name -contains 'honours') {
        foreach ($h in @($Member.honours)) { if ("$($h.award)") { $out += "$($h.award)" } }
    }
    $n = [int]$Career.sorties
    foreach ($a in @(
        @{ At = 5;  Award = 'Eisernes Kreuz II. Klasse' },
        @{ At = 25; Award = 'Eisernes Kreuz I. Klasse' },
        @{ At = 60; Award = 'Ehrenpokal fuer besondere Leistungen im Luftkrieg' })) {
        if ($n -ge $a.At -and ($out -notcontains $a.Award)) { $out += $a.Award }
    }
    # A PLAIN return, not ",$out". Every caller collects with @(...), and a
    # comma return plus @() at the caller nests the array one level deeper,
    # so the honour list arrives as a single element printing as
    # "System.Object[]" and no award is ever matched. Get-PlayerHonours
    # shipped with exactly this and put "Honours: System.Object[]" on the
    # logbook. The rule in this file is: comma return XOR @() at the
    # caller, never both.
    $out
}
# Rank and decorations are PERSISTED the first time they are earned, with
# the date, and never taken away. Without this a pilot who starts a fresh
# campaign in the game drops from Flight Lieutenant back to Sergeant, and
# his DFC silently becomes a DFM, because both were recomputed from the
# sortie count every time the screen was drawn.
$RankLadder = @('Sergeant','Pilot Officer','Flying Officer','Flight Lieutenant')
# The German ladder is TWO ladders, which is the real difference from the
# RAF and not a simplification.
#
# Fighter Command commissioned its sergeant pilots freely, and a man who
# came up that way went on climbing the one ladder, which is why the RAF
# side has a single list with Sergeant at the bottom. The Luftwaffe kept
# its non-commissioned and commissioned pilots on separate tracks and
# moved men between them rarely. So an Unteroffizier rises to
# Oberfeldwebel and stops; a Leutnant rises to Hauptmann.
#
# Stacking them into one six-rung list, which is what I tried first, is
# wrong twice over: it commissions an Unteroffizier automatically at
# thirty-six sorties, and it makes a man who joins as a Leutnant wait
# FORTY-EIGHT for his first step, because Get-Career counts from the rung
# he stands on and he starts at index three. On his own ladder he starts
# at index nought and is promoted at twelve, like everybody else.
# Hauptmann is left off the ladder on purpose, exactly as Squadron Leader
# is on the RAF side: it is a command, reached through cmode, not a rung
# a man climbs to by flying. Left in, an officer made Hauptmann at
# twenty-four sorties, where an RAF pilot reaches Flight Lieutenant at
# thirty-six.
$LwRankNCO     = @('Unteroffizier','Feldwebel','Oberfeldwebel')
$LwRankOfficer = @('Leutnant','Oberleutnant')

# =====================================================================
#  THE CREW
#
#  A Bf 109 carries one man. A Bf 110 carries two, and the Room was built
#  throughout on the assumption of one - one pilot.json, one name, one
#  rank, one set of honours.
#
#  WHAT THE GAME KNOWS ABOUT THE SECOND MAN: nothing whatever. Not a
#  detail, the whole thing. GunnerInfo in the game's own headers is a 3D
#  shape and two eye angles, a camera station rather than a person. The
#  110's four gunner slots are the placeholder shape CPT2 where the Ju 87
#  has real turrets. SquadronBase counts numpilotslost, and the game's own
#  Luftwaffe diary screen prints that counter under the heading "Air
#  Crew", so a downed 110 cannot register two men even there.
#  Diary::Player has one outcome per sortie and one kill tally with no gun
#  position, and the save holds one pilot surname at offset 100. The words
#  Bordfunker and crewman do not occur in the source at all.
#
#  So EVERY PART OF THE SECOND MAN IS INVENTED. That is a deliberate
#  choice, and the price of it is that he must be marked as invention
#  wherever he appears and never allowed to borrow the authority of the
#  figures beside him that really are read out of the save.
#
#  The crew is a property of the AEROPLANE, keyed by the order of
#  battle's own type string, so the bombers need no rework when their turn
#  comes. A single-seat type returns one role and every screen behaves
#  exactly as it did.
# =====================================================================
$CrewByType = [ordered]@{
    'Bf 109E' = @('Flugzeugfuehrer')
    'Bf 110'  = @('Flugzeugfuehrer','Bordfunker')
    'Ju 87'   = @('Flugzeugfuehrer','Bordfunker')
    'Do 17'   = @('Flugzeugfuehrer','Beobachter','Bordfunker','Bordmechaniker')
    'Ju 88'   = @('Flugzeugfuehrer','Beobachter','Bordfunker','Bordschuetze')
    'He 111'  = @('Flugzeugfuehrer','Beobachter','Bordfunker','Bordmechaniker','Bordschuetze')
}
function Get-CrewRoles {
    param([string]$Type)
    foreach ($k in $CrewByType.Keys) {
        if ("$Type" -like "$k*") { return $CrewByType[$k] }
    }
    # An unknown type is flown single-handed rather than guessed at.
    @('Flugzeugfuehrer')
}
# The men in the aeroplane besides the player. The player himself stays
# where he has always been, at the top level of the record: every screen
# and every write path already reads him there, and moving him would mean
# touching all of them for no gain.
# A crew member's NAME FIELD IS `pilot`, not `name`, so New-Frame and
# New-LwRosterRow take one straight off the record. Both read .pilot, and
# every roster man in squadronroom/lw/rosters uses `pilot` too, so one
# spelling serves the player, his crew and the whole Staffel.
function Get-Crew {
    param($Pilot)
    if (-not $Pilot) { return @() }
    if ($Pilot.PSObject.Properties.Name -notcontains 'crew') { return @() }
    @($Pilot.crew | Where-Object { $_ })
}
function Test-MultiCrew {
    param($Pilot)
    (@(Get-CrewRoles "$($Pilot.actype)").Count -gt 1)
}
# What a man in a given seat is called on the day he arrives.
$CrewEntryRank = @{
    'Bordfunker'      = 'Unteroffizier'
    'Beobachter'      = 'Leutnant'
    'Bordmechaniker'  = 'Unteroffizier'
    'Bordschuetze'    = 'Unteroffizier'
}
# A crewman climbs the NCO ladder and no other. Leutnant, Oberleutnant and
# Hauptmann are a pilot's, and cmode 'commander' means a Gruppe command,
# which is not a thing a radio operator holds.
#
# The step is SIXTEEN sorties against the pilot's twelve, and that number
# is invented. It is not from a source and there is no source to have: it
# is chosen only so that two men flying the identical sortie do not step
# up together at twelve, twenty-four and thirty-six, which reads as
# machinery rather than as two careers.
$CrewRankStep = 16
function Get-CrewLadder {
    param([string]$Role, [string]$Rank)
    if ("$Role" -eq 'Beobachter' -and (($LwRankOfficer -contains "$Rank") -or -not "$Rank")) {
        return $LwRankOfficer
    }
    $LwRankNCO
}
function Get-RankLadder {
    param([string]$Rank)
    if ($script:Side -ne 'lw') { return $RankLadder }
    if (($LwRankOfficer -contains "$Rank") -or ("$Rank" -eq 'Hauptmann')) { return $LwRankOfficer }
    return $LwRankNCO
}
function Update-CareerRecord {
    param($Pilot, $Career, $Honours)
    if (-not $Pilot -or -not $Career) { return $Pilot }
    $changed = $false
    $obj = [ordered]@{}
    foreach ($pp in $Pilot.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
    $lad = Get-RankLadder -Rank "$($Pilot.rank)"
    $storedIdx = [array]::IndexOf($lad, "$($Pilot.rank)")
    $earnedIdx = [array]::IndexOf($lad, "$($Career.rank)")
    if ($earnedIdx -gt $storedIdx) {
        $obj['rank'] = $lad[$earnedIdx]
        $obj['rank_date'] = $(if ($script:CampaignDate) { $script:CampaignDate.ToString('yyyy-MM-dd') } else { '' })
        $changed = $true
    }
    if ($Honours -and @($Honours).Count) {
        $had = @(); if (($Pilot.PSObject.Properties.Name -contains 'honours') -and $Pilot.honours) { $had = @($Pilot.honours) }
        $names = @($had | ForEach-Object { "$($_.award)" })
        $add = @($Honours | Where-Object { $names -notcontains "$_" })
        if ($add.Count) {
            $when = $(if ($script:CampaignDate) { $script:CampaignDate.ToString('yyyy-MM-dd') } else { '' })
            foreach ($a in $add) { $had += [ordered]@{ award = "$a"; date = $when } }
            $obj['honours'] = @($had)
            $changed = $true
        }
    }
    # THE REST OF THE CREW, advanced in the same pass.
    #
    # Done here rather than in a second function with a second Save-Pilot,
    # because two saves in one screen draw is how the autobackup ring used
    # to eat itself, and because a crewman must never be written by a path
    # that does not also carry the pilot: every other write in this file
    # rebuilds the record by copying properties flat, so a crew updated on
    # its own would be silently discarded by the next such write.
    $crew = @(Get-Crew $Pilot)
    if ($crew.Count) {
        $newCrew = @()
        foreach ($m in $crew) {
            $mo = [ordered]@{}
            foreach ($mp in $m.PSObject.Properties) { $mo[$mp.Name] = $mp.Value }
            $cc = Get-CrewCareer -Member $m -Pilot $Pilot -Sorties ([int]$Career.sorties) -Hours ([double]$Career.hours)
            $ml = Get-CrewLadder -Role "$($m.role)" -Rank "$($m.rank)"
            $mStored = [array]::IndexOf($ml, "$($m.rank)")
            $mEarned = [array]::IndexOf($ml, "$($cc.rank)")
            if ($mEarned -gt $mStored) {
                $mo['rank'] = $ml[$mEarned]
                $mo['rank_date'] = $(if ($script:CampaignDate) { $script:CampaignDate.ToString('yyyy-MM-dd') } else { '' })
                $changed = $true
            }
            $mh = @(Get-CrewHonours -Member $m -Career $cc)
            if ($mh.Count) {
                $mhad = @(); if (($m.PSObject.Properties.Name -contains 'honours') -and $m.honours) { $mhad = @($m.honours) }
                $mnames = @($mhad | ForEach-Object { "$($_.award)" })
                $madd = @($mh | Where-Object { $mnames -notcontains "$_" })
                if ($madd.Count) {
                    $when = $(if ($script:CampaignDate) { $script:CampaignDate.ToString('yyyy-MM-dd') } else { '' })
                    foreach ($a in $madd) { $mhad += [ordered]@{ award = "$a"; date = $when } }
                    $mo['honours'] = @($mhad)
                    $changed = $true
                }
            }
            $newCrew += [pscustomobject]$mo
        }
        $obj['crew'] = @($newCrew)
    }
    if (-not $changed) { return $Pilot }
    Save-Pilot $obj
    $np = Get-Pilot
    if ($np) { return $np }
    $Pilot
}
# The player's own decoration. Stored award wins; otherwise a DFC once he has
# five victories (a plausible Battle of Britain threshold). "None yet" before.
# Rank-aware honours ladder, computed from the record. Sergeants earn the
# DFM, officers the DFC (as the RAF actually did); a second award of the
# same decoration is a Bar. Mentioned in Despatches for sustained flying.
# The squadrons whose men were decorated by their own governments in
# exile as well as by the RAF. Poles and Czechs flew in British squadrons
# too, but these four were their own units and their own award lists.
$PolishSquadrons = @(302, 303)
$CzechSquadrons  = @(310, 312)
# Was there one sortie he should not have come back from? The Victoria
# Cross went to one Fighter Command pilot in the whole war -- Flt Lt
# James Nicolson of 249, on 16 August 1940, for pressing his attack home
# while his Hurricane burned -- so it is not a score that earns it but a
# single action fought past the point of sense. Three or more claims in
# one sortie, from an aeroplane he did not bring back.
function Test-VictoriaCrossAction {
    param($Diary)
    if (-not $Diary) { return $false }
    foreach ($r in @($Diary.rows)) {
        $k = 0; for ($i = 0; $i -lt 7; $i++) { $k += [int]$r.kills[$i] }
        if ($k -ge 3 -and ([int]$r.ended -in 3, 4, 5, 6, 7, 8, 9)) { return $true }
    }
    $false
}
function Get-PlayerHonours {
    param($Pilot, $Career, $Diary)
    $v = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $v = [int]$Pilot.victories }
    $sorties = 0; if ($Career) { $sorties = [int]$Career.sorties }
    $isNCO = ("$($Career.rank)" -eq 'Sergeant')
    $cross = if ($isNCO) { 'DFM' } else { 'DFC' }
    $h = @()
    if (($Pilot.PSObject.Properties.Name -contains 'honours') -and $Pilot.honours) {
        foreach ($a in @($Pilot.honours)) { $h += "$($a.award)" }
    }
    # A man decorated as a sergeant KEEPS his DFM when he is commissioned;
    # he does not also collect the officers' DFC for the same victories.
    # Whichever cross he already holds is the one his Bar belongs to.
    foreach ($k in @('DFM','DFC')) { if ($h -contains $k) { $cross = $k } }
    if ($sorties -ge 10 -and ($h -notcontains 'MiD')) { $h += 'MiD' }
    if ($v -ge 5  -and ($h -notcontains $cross)) { $h += $cross }
    if ($v -ge 10 -and ($h -notcontains "Bar to $cross")) { $h += "Bar to $cross" }
    if ($v -ge 15 -and ($h -notcontains 'DSO')) { $h += 'DSO' }
    if ($v -ge 25 -and ($h -contains 'DSO') -and ($h -notcontains 'Bar to DSO')) { $h += 'Bar to DSO' }
    # An allied government's awards, for a man on one of its own squadrons.
    # The Cross of Valour was given freely for good work in action; the
    # Virtuti Militari was Poland's highest and was not.
    $sqn = 0
    if (($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { $sqn = [int]$Pilot.sqn }
    if ($PolishSquadrons -contains $sqn) {
        if ($v -ge 3 -and ($h -notcontains 'Cross of Valour'))   { $h += 'Cross of Valour' }
        if ($v -ge 8 -and ($h -notcontains 'Virtuti Militari'))  { $h += 'Virtuti Militari' }
    }
    if ($CzechSquadrons -contains $sqn) {
        if ($v -ge 3 -and ($h -notcontains 'Czechoslovak War Cross')) { $h += 'Czechoslovak War Cross' }
    }
    if (($h -notcontains 'VC') -and (Test-VictoriaCrossAction $Diary)) { $h += 'VC' }
    if (($Pilot.PSObject.Properties.Name -contains 'awards') -and $Pilot.awards -and ($h -notcontains "$($Pilot.awards)")) { $h = @("$($Pilot.awards)") + $h }
    # no comma return: every caller collects with @(...), and comma + @()
    # double-wraps into the System.Object[] display bug
    $h
}
# =====================================================================
#  The squadron's own war, out of the campaign save
#
#  The game keeps a diary for every squadron, not only for the player: a
#  table of 24-byte records, one per squadron per action, holding how many
#  aircraft it put up, what it claimed by enemy type, how many aircraft
#  and pilots it lost, and when it landed.
#
#      +0  u8    squadron, as an index into the game's own list
#      +1  u8    aircraft lost      +2 u8  aircraft damaged
#      +3  u8    pilots lost        +8 u8  aircraft launched
#      +9  u16   which intercept    +11 u32 landing time, seconds into the day
#      +17 u8[7] claims, by the same seven bins as the player's Log Book
#
#  The game names nobody. It knows twelve aircraft went up and one pilot
#  did not come back; it does not know who he was. The names are the one
#  thing history supplies and the game lacks, which is why the readiness
#  board is worth having at all.
# =====================================================================
$SquadronDiaryRow = 24
# The game's squadron list, from its own symbols. The index in the save is
# NOT the RAF number: 64 means No. 32, and read raw the table appears to
# describe squadrons that never existed.
$SquadIndexToRAF = @{
     64=32;  65=610;  66=501;  67=56;  68=151;  69=85;  70=64;  71=615;  72=111
     74=54;  75=65;   76=74;   77=266; 78=43;   79=601; 80=145; 81=17;   83=1
     84=257; 85=303;  86=87;   87=213; 88=238;  89=609; 90=152; 91=234;  92=92
     93=310; 94=19;   95=66;   96=242; 97=222;  98=611; 99=46; 100=229; 101=72
    102=249; 103=253; 104=605; 105=603; 106=41; 107=607; 108=602; 109=73
    110=504; 111=79;  112=302; 113=616; 114=3;  115=232; 116=245
}
function Test-SquadronRow {
    param([byte[]]$B, [int]$O)
    if (($O + $SquadronDiaryRow) -gt $B.Length) { return $false }
    if (-not $SquadIndexToRAF.ContainsKey([int]$B[$O])) { return $false }
    if ($B[$O+8] -gt 24) { return $false }                       # launched
    if ($B[$O+1] -gt 12 -or $B[$O+2] -gt 12 -or $B[$O+3] -gt 12) { return $false }
    $k = 0
    for ($i = 0; $i -lt 7; $i++) { if ($B[$O+17+$i] -gt 12) { return $false }; $k += $B[$O+17+$i] }
    ($k -le 25)
}
# Every action in the save, or an empty list. Slow enough to want caching,
# so the answer is kept until the save changes.
function Get-SquadronDiary {
    if (-not $GameDir) { return @() }
    $sav = Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $sav) { return @() }
    $stamp = "$($sav.FullName)|$($sav.LastWriteTime.Ticks)"
    if ($script:SqDiaryStamp -eq $stamp) { return $script:SqDiaryRows }
    $rows = @()
    try {
        $b = [System.IO.File]::ReadAllBytes($sav.FullName)
        # Find the longest run of well-formed records. A quarter of a
        # million calls to Test-SquadronRow took twenty-six seconds and
        # froze the window, so the search is two cheap byte tests first
        # and the full check only where those pass.
        $isIdx = New-Object bool[] 256
        foreach ($k in $SquadIndexToRAF.Keys) { $isIdx[[int]$k] = $true }
        $bestAt = -1; $bestN = 0; $o = 40; $end = $b.Length - $SquadronDiaryRow
        while ($o -lt $end) {
            if ($isIdx[$b[$o]] -and $b[$o+8] -le 24 -and $b[$o+1] -le 12) {
                if (Test-SquadronRow $b $o) {
                    $n = 0
                    while (Test-SquadronRow $b ($o + $n * $SquadronDiaryRow)) { $n++ }
                    if ($n -gt $bestN) { $bestN = $n; $bestAt = $o }
                    $o += [Math]::Max(1, $n * $SquadronDiaryRow)
                    continue
                }
            }
            $o++
        }
        # kept so Get-GruppeDiary knows where to stop: the German table
        # sits immediately below this one
        $script:SqDiaryAt = $bestAt
        if ($bestN -ge 6) {
            for ($i = 0; $i -lt $bestN; $i++) {
                $p = $bestAt + $i * $SquadronDiaryRow
                $k = New-Object int[] 7
                for ($j = 0; $j -lt 7; $j++) { $k[$j] = [int]$b[$p+17+$j] }
                $rows += [pscustomobject]@{
                    Sqn      = [int]$SquadIndexToRAF[[int]$b[$p]]
                    Launched = [int]$b[$p+8]
                    AcLost   = [int]$b[$p+1]
                    AcDamaged= [int]$b[$p+2]
                    PilotsLost = [int]$b[$p+3]
                    Kills    = $k
                    Landed   = [int][BitConverter]::ToUInt32($b, $p+11)
                }
            }
        }
    } catch { }
    $script:SqDiaryStamp = $stamp
    $script:SqDiaryRows = $rows
    $rows
}
# The German squadron diary, which is a SEPARATE table from the RAF one.
#
# The game keeps two, side by side, and they are not the same shape. From
# the disassembly notes in modernization/BSR_FORMAT.md and confirmed
# against real saves by dev/lw_diary_probe.py:
#
#   RAF  Diary::Squadron  24-byte records  squadnum  64..116  7 bins at +17
#   LW   Diary::Gruppen   17-byte records  squadnum 159..231  6 bins at +11
#
# In Patrick's save the German table held 122 rows at 89459 and the RAF
# table began at 91533, and 89459 + 122 x 17 is 91533 exactly: they are
# adjacent, which is what proves the record size.
#
# The German table is present in an RAF save too, because the campaign
# tracks both air forces, so none of this needed a German career to work
# out. What it did need was care about WHERE to look. Turned loose on the
# whole file a 17-byte window finds two convincing frauds - a field of
# zeros scoring thousands of empty rows, and a region whose squadnums
# step by exactly two with every other value identical - and both beat
# the real table on any score based on run length. So the search runs
# immediately below the RAF table and scores on live squadrons.
$LwDiaryRow = 17
function Get-GruppeDiary {
    if (-not $GameDir) { return @() }
    $sav = Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $sav) { return @() }
    $stamp = "$($sav.FullName)|$($sav.LastWriteTime.Ticks)"
    if ($script:LwDiaryStamp -eq $stamp) { return $script:LwDiaryRows }
    $rows = @()
    try {
        $b = [System.IO.File]::ReadAllBytes($sav.FullName)
        # the RAF table's start is the ceiling of the search
        $rafAt = -1
        $raf = @(Get-SquadronDiary)
        if ($raf.Count) { $rafAt = [int]$script:SqDiaryAt }
        if ($rafAt -le 0) { $rafAt = $b.Length }
        $from = [math]::Max(40, $rafAt - 4000)
        $bestAt = -1; $bestReal = 0; $bestN = 0
        for ($o = $from; $o -lt $rafAt; $o++) {
            $n = 0; $real = 0
            while ($true) {
                $p = $o + $n * $LwDiaryRow
                if (($p + $LwDiaryRow) -gt $b.Length -or $p -ge $rafAt) { break }
                $sq = [int]$b[$p]
                if ($sq -eq 0) { $n++; continue }
                $launched = [int]$b[$p+8]; $lost = [int]$b[$p+1]
                if ($sq -ge 159 -and $sq -le 231 -and $launched -gt 0 -and $launched -le 60 -and $lost -le $launched) {
                    $real++; $n++
                } else { break }
            }
            if ($real -gt $bestReal) { $bestReal = $real; $bestN = $n; $bestAt = $o }
        }
        if ($bestReal -gt 0) {
            for ($i = 0; $i -lt $bestN; $i++) {
                $p = $bestAt + $i * $LwDiaryRow
                $sq = [int]$b[$p]
                if ($sq -eq 0) { continue }
                $k = New-Object int[] 6
                for ($j = 0; $j -lt 6; $j++) { $k[$j] = [int]$b[$p+11+$j] }
                $rows += [pscustomobject]@{
                    Idx      = $sq
                    Launched = [int]$b[$p+8]
                    AcLost   = [int]$b[$p+1]
                    AcDamaged= [int]$b[$p+2]
                    PilotsLost = [int]$b[$p+3]
                    Kills    = $k
                }
            }
        }
    } catch { }
    $script:LwDiaryStamp = $stamp
    $script:LwDiaryRows = $rows
    $rows
}
# What one Gruppe has done in this campaign, summed. $Idx is the save's
# own index for it, carried in lw/oob.json as sqidx; the four
# Lehrgeschwader Gruppen BOB2 added have none and get nothing rather than
# somebody else's figures.
function Get-GruppeRecord {
    param($Idx)
    if ($null -eq $Idx) { return $null }
    $rows = @(Get-GruppeDiary | Where-Object { $_.Idx -eq [int]$Idx })
    if ($rows.Count -eq 0) { return $null }
    $k = New-Object int[] 6
    foreach ($r in $rows) { for ($i = 0; $i -lt 6; $i++) { $k[$i] += $r.Kills[$i] } }
    [pscustomobject]@{
        Actions    = $rows.Count
        Launched   = ($rows | Measure-Object Launched -Sum).Sum
        AcLost     = ($rows | Measure-Object AcLost -Sum).Sum
        AcDamaged  = ($rows | Measure-Object AcDamaged -Sum).Sum
        PilotsLost = ($rows | Measure-Object PilotsLost -Sum).Sum
        Kills      = $k
        Total      = ($k | Measure-Object -Sum).Sum
    }
}

# What one squadron has done in this campaign, summed.
function Get-SquadronRecord {
    param([int]$Sqn)
    $rows = @(Get-SquadronDiary | Where-Object { $_.Sqn -eq $Sqn })
    if ($rows.Count -eq 0) { return $null }
    $k = New-Object int[] 7
    foreach ($r in $rows) { for ($i = 0; $i -lt 7; $i++) { $k[$i] += $r.Kills[$i] } }
    [pscustomobject]@{
        Actions    = $rows.Count
        Launched   = ($rows | Measure-Object Launched -Sum).Sum
        AcLost     = ($rows | Measure-Object AcLost -Sum).Sum
        AcDamaged  = ($rows | Measure-Object AcDamaged -Sum).Sum
        PilotsLost = ($rows | Measure-Object PilotsLost -Sum).Sum
        Kills      = $k
        Total      = ($k | Measure-Object -Sum).Sum
    }
}

# =====================================================================
#  The men the game lost but did not name
#
#  The campaign save says a squadron lost nine pilots. The roster names
#  the ones history recorded. The rest are real losses with no name
#  attached, and this gives them one.
#
#  Two rules, and they are the whole of it. A man who really flew is NEVER
#  killed by arithmetic: if history says he came through the Battle, he
#  comes through it here. And a pilot invented to carry an unattributed
#  loss is marked as invented wherever he appears, in the data and on the
#  board, because a made-up name on a memorial roll is the one mistake
#  this room must not make.
#
#  The names are period-plausible and deliberately NOT drawn from the list
#  of the Few: borrowing a real airman's surname for an invented man would
#  be worse than inventing one outright.
# =====================================================================
$InventedSurnames = @(
    'Ashworth','Ballantyne','Bickerton','Blythe','Cadogan','Carmichael','Chadwick',
    'Charteris','Coleridge','Cranfield','Darnley','Delamere','Ellerby','Fanshawe',
    'Farquhar','Fenwick','Gallagher','Garforth','Haldane','Halliwell','Hartnell',
    'Havelock','Inchbald','Kerrigan','Langdale','Lockhart','Marchant','Merriman',
    'Netherton','Ockenden','Pemberton','Prendergast','Quayle','Ravenhill','Redmayne',
    'Rowntree','Sandiford','Selwyn','Sheridan','Standish','Thackeray','Tremayne',
    'Underhill','Vansittart','Wetherby','Whitcombe','Wolstenholme','Yardley'
)
$InventedInitials = @('A','B','C','D','E','F','G','H','J','K','L','M','N','P','R','S','T','W')
$InventedRanks = @('Sergeant','Sergeant','Sergeant','Pilot Officer','Pilot Officer','Flying Officer')

# A man history has already accounted for is never touched by the
# campaign's arithmetic:
#
#   the player                      his own save says what happened to him
#   a documented fate in the Battle killed, missing, taken prisoner or
#                                   wounded on a recorded day
#   an ace or a decorated man       his record is the reason he is known
#
# Everyone else is an ordinary pilot whose war the record does not follow,
# and those are the men your campaign's losses fall on. It is a claim
# about YOUR campaign, not about the man, and the board says so on his own
# row and gives his real ending beside it.
function Test-ProtectedPilot {
    param($P)
    if (("$($P.left_reason)" -in @('KIA','MIA','POW','WIA','DoW')) -and $P.left) { return $true }
    if (($P.PSObject.Properties.Name -contains 'awards') -and @($P.awards).Count -gt 0) { return $true }
    if (($P.PSObject.Properties.Name -contains 'victories_total') -and ($null -ne $P.victories_total) -and ([int]$P.victories_total -ge 5)) { return $true }
    $false
}
# Which of the squadron's ordinary men your campaign has cost it. Same
# squadron, same campaign, same men every time.
function Get-CampaignCasualties {
    param($Roster, [int]$Count, [int]$Sqn)
    if ($Count -le 0) { return @{} }
    $pool = @($Roster | Where-Object { -not (Test-ProtectedPilot $_) })
    if ($pool.Count -eq 0) { return @{} }
    $out = @{}
    for ($i = 0; $i -lt $Count -and $i -lt $pool.Count; $i++) {
        $pick = $pool[(($Sqn * 17 + $i * 29) % $pool.Count)]
        $n = 0
        while ($out.ContainsKey("$($pick.pilot)") -and $n -lt $pool.Count) {
            $pick = $pool[((($Sqn * 17 + $i * 29) + ++$n) % $pool.Count)]
        }
        $out["$($pick.pilot)"] = $true
    }
    $out
}

# The same squadron always invents the same men, so a pilot does not
# change his name between one visit and the next.
function Get-InventedPilots {
    param([int]$Sqn, [int]$Count, $Roster)
    if ($Count -le 0) { return @() }
    $taken = @{}
    foreach ($m in @($Roster)) {
        $sur = ("$($m.pilot)" -split ',')[0].Trim()
        if ($sur) { $taken[$sur.ToLower()] = $true }
    }
    $out = @()
    $i = 0; $step = 0
    while ($out.Count -lt $Count -and $step -lt 400) {
        $step++
        $idx = ($Sqn * 7 + $i * 13) % $InventedSurnames.Count
        $sur = $InventedSurnames[$idx]
        $i++
        if ($taken.ContainsKey($sur.ToLower())) { continue }
        $taken[$sur.ToLower()] = $true
        $a = $InventedInitials[($Sqn * 3 + $out.Count * 5) % $InventedInitials.Count]
        $b = $InventedInitials[($Sqn * 11 + $out.Count * 7) % $InventedInitials.Count]
        $out += [pscustomobject]@{
            pilot = "$sur, $a.$b."
            rank  = $InventedRanks[($Sqn + $out.Count) % $InventedRanks.Count]
            historical = $false
        }
    }
    $out
}

# How many of the campaign's pilot losses history has already named, and
# how many it has not.
function Get-UnnamedLosses {
    param($Roster, $Record, $Date)
    if (-not $Record) { return 0 }
    $named = 0
    foreach ($m in @($Roster)) {
        if ("$($m.left_reason)" -notin @('KIA','MIA','DoW')) { continue }
        $l = Get-LeaveDate $m
        if ($l -and $l -ge $BattleStart -and (-not $Date -or $l -le $Date)) { $named++ }
    }
    [Math]::Max(0, [int]$Record.PilotsLost - $named)
}

# =====================================================================
#  Automatic claims
#
#  The game keeps the player's Log Book inside the campaign save as an
#  array of 25-byte Diary::Player records, one per sortie:
#      +0   u16   diarysquadindex
#      +2   u32   howendedmission      (EndFlightStatus: 9 = baled out)
#      +6   u8[6] specificdamage
#      +12  u16   descriptionstringindex   (= 512 * row number)
#      +14  u32   flyingcs
#      +18  u8[7] kills, indexed by the victim's STATISTICS_TYPE bin
#  The Log Book's Claims column is the sum of the seven kills bytes and
#  Diary::AddKill is their only writer, so the player's own victories, by
#  type, are read from here. Established 2026-09-07 from Bob212.pdb, a
#  before/after sortie pair and the game's own Log Book (3 + 1 Ju 87).
#
#  The table sat at 99047 in every save seen (three files of three sizes:
#  the save only grows after this block). It is verified by signature
#  before use, and searched for when the check fails. Empty slots carry
#  0xFFFF in the first and fourth fields.
# assigned by Set-StateSide (see the note beside AcPosPath)
$DiaryRowSize    = 25
$DiaryTableGuess = 99047
$DiaryMaxRows    = 200
# STATISTICS_TYPE bins for what an RAF pilot shoots down, and for a
# Luftwaffe pilot (the last three of those are dummies in the game).
# What each side shoots at. The counts are not the same and that is not a
# detail: the save header carries ST_GERM_COUNT = 7 and ST_BRIT_COUNT = 6,
# and the disassembly notes in modernization/BSR_FORMAT.md record that an
# RAF squadron's tallies sit at record+0x11 over seven German types while
# a Luftwaffe Gruppe's sit at record+0x0b over six British ones.
#
# $KillBinsLW used to be seven long, padded out with three "Other"
# entries. That was a guess made to match the RAF list and it was wrong.
# A German pilot has six bins, and a seventh read out of his record is
# somebody else's data.
$KillBinsRAF = @('Bf 109E','Bf 110','Ju 87','Do 17','Ju 88','He 111','He 59')
$KillBinsLW  = @('Spitfire','Hurricane','Defiant','Blenheim','Beaufighter','Other')
function Get-KillBins {
    param($Pilot)
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'side') -and ("$($Pilot.side)" -match '^(lw|luftwaffe|german)')) { return $KillBinsLW }
    if ($script:Side -eq 'lw') { return $KillBinsLW }
    $KillBinsRAF
}
function Get-AutoClaim {
    if (Test-Path $AutoClaimPath) {
        try { return (Get-Content $AutoClaimPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    $null
}
function Save-AutoClaim {
    param($Obj)
    try {
        if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
        $Obj | ConvertTo-Json -Depth 5 | Set-Content -Path $AutoClaimPath -Encoding UTF8
    } catch { }
}
function Read-DiaryRow {
    param([byte[]]$B, [int]$O)
    if ($O -lt 0 -or ($O + $DiaryRowSize) -gt $B.Length) { return $null }
    $k = New-Object int[] 7
    for ($i = 0; $i -lt 7; $i++) { $k[$i] = [int]$B[$O + 18 + $i] }
    [pscustomobject]@{
        off   = $O
        sq    = [int]$B[$O] + 256 * [int]$B[$O+1]
        ended = [int]$B[$O+2] + 256 * [int]$B[$O+3] + 65536 * [int]$B[$O+4] + 16777216 * [int]$B[$O+5]
        str   = [int]$B[$O+12] + 256 * [int]$B[$O+13]
        kills = $k
        total = ($k | Measure-Object -Sum).Sum
    }
}
# True when a Diary::Player table starts at $P: row 0 used with string
# index 0, and every following row either used with index 512*i and a sane
# ending, or an empty slot.
function Test-DiaryTableAt {
    param([byte[]]$B, [int]$P)
    $r0 = Read-DiaryRow $B $P
    if (-not $r0 -or $r0.sq -eq 0xFFFF -or $r0.str -ne 0 -or $r0.ended -gt 9) { return $false }
    for ($i = 1; $i -lt 3; $i++) {
        $r = Read-DiaryRow $B ($P + $i * $DiaryRowSize)
        if (-not $r) { return $false }
        $empty = ($r.sq -eq 0xFFFF -and $r.str -eq 0xFFFF)
        $used  = ($r.str -eq 512 * $i -and $r.ended -le 9 -and $r.sq -lt 0xFFFF)
        if (-not ($empty -or $used)) { return $false }
    }
    $true
}
function Find-DiaryTable {
    param([byte[]]$B)
    if (Test-DiaryTableAt $B $DiaryTableGuess) { return $DiaryTableGuess }
    # The guess is where the table sat in every save seen so far; this scan
    # is the fallback and covers the WHOLE file, since a shorter campaign
    # or a different slot can put the block outside any fixed window.
    $hi = $B.Length - 200
    # Row 0's string index is two zero bytes at +12: skip everything else
    # before paying for the full check (a quarter of a million positions
    # otherwise cost several seconds in PowerShell).
    for ($p = 0; $p -lt $hi; $p++) {
        if ($B[$p + 12] -ne 0 -or $B[$p + 13] -ne 0) { continue }
        # ...and row 1's index is 512 (bytes 00 02) or the empty marker FF FF
        if (-not (($B[$p + 37] -eq 0 -and $B[$p + 38] -eq 2) -or ($B[$p + 37] -eq 0xFF -and $B[$p + 38] -eq 0xFF))) { continue }
        if (Test-DiaryTableAt $B $p) { return $p }
    }
    -1
}
# The player's Log Book as the save holds it: rows, kills by bin, total.
# $null when the file cannot be read or the table is not found.
function Get-SaveDiary {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) { return $null }
        $b = [System.IO.File]::ReadAllBytes($Path)
        $p = Find-DiaryTable $b
        if ($p -lt 0) {
            # A campaign that has not been flown yet has no used rows, so
            # no table can be recognised. That is an EMPTY Log Book, not an
            # unreadable save, and the screen should say so.
            if ($b.Length -gt 160 -and ([System.Text.Encoding]::ASCII.GetString($b, 1, 20) -match '^Rowan Savegame: V 0')) {
                return [pscustomobject]@{ table = -1; rows = @(); kills = (New-Object int[] 7); total = 0 }
            }
            return $null
        }
        $rows = @(); $bins = New-Object int[] 7
        for ($i = 0; $i -lt $DiaryMaxRows; $i++) {
            $r = Read-DiaryRow $b ($p + $i * $DiaryRowSize)
            if (-not $r) { break }
            if ($r.sq -eq 0xFFFF -and $r.str -eq 0xFFFF) { continue }     # empty slot
            if ($r.str -ne 512 * $i -or $r.ended -gt 9) { break }          # past the table
            # keep the game's own slot number: skipping empties used to
            # renumber every sortie after a gap
            $r | Add-Member -NotePropertyName 'slot' -NotePropertyValue ($i + 1) -Force
            $rows += $r
            for ($k = 0; $k -lt 7; $k++) { $bins[$k] += $r.kills[$k] }
        }
        return [pscustomobject]@{ table = $p; rows = $rows; kills = $bins; total = ($bins | Measure-Object -Sum).Sum }
    } catch { return $null }
}
# How many sorties this pilot has flown, and where the number came from.
# The campaign's own Log Book is the record; the launcher's timed sessions
# are only a fallback for a pilot whose save cannot be read, and they used
# to be the source on the dispersal while the logbook used the save - so
# the two screens could show different ranks for the same man.
function Get-SortieCount {
    param($Diary, $Sessions, $Pilot)
    if ($Diary) {
        $rows = @($Diary.rows).Count
        # A new man posted into a campaign that has already been flown
        # starts at nought. campaignSorties is the Log Book's length on the
        # day he joined; everything before it belongs to the man he
        # replaced. Without this a new career opened with the previous
        # pilot's sorties, rank and victories already on the board.
        if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'campaignSorties') -and ($null -ne $Pilot.campaignSorties)) {
            $base = [int]$Pilot.campaignSorties
            if ($rows -lt $base) { return $rows }   # the game started a new campaign: it is all his
            return ($rows - $base)
        }
        return $rows
    }
    @($Sessions).Count
}
# The campaign's Log Book holds every sortie the SAVE has flown, and a new
# man posted into a campaign already under way inherits none of them. The
# counters already knew that; the sortie table and the claims line did
# not, so a fresh career opened showing the last man's flying. This trims
# the book to the career: the rows after his baseline, and the victories
# recounted from those rows alone.
function Get-CareerDiary {
    param($Diary, $Pilot)
    if (-not $Diary) { return $null }
    $rows = @($Diary.rows)
    $base = 0
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'campaignSorties') -and ($null -ne $Pilot.campaignSorties)) {
        $base = [int]$Pilot.campaignSorties
    }
    # fewer rows than the baseline means the game began a new campaign of
    # its own, and the whole book is his
    if ($base -gt 0 -and $rows.Count -ge $base) { $rows = @($rows | Select-Object -Skip $base) }
    $bins = New-Object int[] 7
    foreach ($r in $rows) { for ($k = 0; $k -lt 7; $k++) { $bins[$k] += [int]$r.kills[$k] } }
    [pscustomobject]@{ table = $Diary.table; rows = $rows; kills = $bins; total = ($bins | Measure-Object -Sum).Sum }
}
# The newest campaign save's Log Book, for the logbook screen.
# Every .BSR in the game's SAVEGAME folder, newest first.
function Get-SaveFiles {
    if (-not $GameDir) { return @() }
    @(Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}
# WHICH save is this career's campaign. Newest-wins is only a guess: a man
# with two campaigns on the go, or who saves under his own names, would
# have his sorties and victories read out of somebody else's war. Once he
# says which file is his it is written into his record and used from then
# on, and only falls back to the newest if that file has gone.
function Get-CampaignSavePath {
    param($Pilot)
    if (-not $Pilot) { $Pilot = Get-Pilot }
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'savePath') -and "$($Pilot.savePath)" -and (Test-Path "$($Pilot.savePath)")) {
        return "$($Pilot.savePath)"
    }
    $f = Get-SaveFiles | Select-Object -First 1
    if ($f) { return $f.FullName }
    $null
}
function Get-LatestSaveDiary {
    param($Pilot)
    $p = Get-CampaignSavePath -Pilot $Pilot
    if (-not $p) { return $null }
    Get-SaveDiary -Path $p
}
# Bring the pilot's record level with the campaign's own Log Book. The
# record carries campaignKills, the seven bins it has already credited;
# whatever the save shows above that is entered now, by type, dated with
# the campaign day. Works whether the game was started from the launcher,
# from this room, or by double-clicking Bob.exe, so no flight marker is
# needed for claims. A save whose bins have gone DOWN is a new campaign:
# the baseline is reset without crediting anything.
function Sync-CampaignClaims {
    $ld = Get-LatestSaveDiary
    if (-not $ld) { return $null }
    $p = Get-Pilot
    if (-not $p) { return $ld }
    $have = New-Object int[] 7
    $known = ($p.PSObject.Properties.Name -contains 'campaignKills') -and $p.campaignKills
    if ($known) {
        $arr = @($p.campaignKills)
        for ($k = 0; $k -lt 7 -and $k -lt $arr.Count; $k++) { $have[$k] = [int]$arr[$k] }
    } else {
        # No baseline recorded. This is a pilot made before baselines
        # existed, flying his own campaign, so the Log Book is his: take it
        # as the baseline rather than crediting it all over again. (A pilot
        # posted since then always carries a baseline, written at posting,
        # so a new career can never inherit the previous man's victories.)
        for ($k = 0; $k -lt 7; $k++) { $have[$k] = [int]$ld.kills[$k] }
    }
    $lower = $false
    for ($k = 0; $k -lt 7; $k++) { if ([int]$ld.kills[$k] -lt $have[$k]) { $lower = $true } }
    $bins = Get-KillBins $p
    $newTypes = @()
    if (-not $lower) {
        # The player's own row holds seven tallies whichever side he flies,
        # but a German pilot only has six types to shoot at. Running to
        # seven would index past the end of his list and credit him a claim
        # with no aircraft type on it at all.
        for ($k = 0; $k -lt $bins.Count; $k++) {
            $d = [int]$ld.kills[$k] - $have[$k]
            for ($j = 0; $j -lt $d; $j++) { $newTypes += $bins[$k] }
        }
    }
    if ($newTypes.Count -gt 0) { Add-AutoClaims -Types $newTypes }
    # record the baseline (re-read: Add-AutoClaims saved the pilot). If the
    # record cannot be read back - locked, mid-write, corrupt - write
    # NOTHING: a stub containing only campaignKills would destroy a career.
    $p2 = Get-Pilot
    if (-not $p2) { return $ld }
    $obj = [ordered]@{}
    foreach ($pp in $p2.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
    $obj['campaignKills'] = @(0..6 | ForEach-Object { [int]$ld.kills[$_] })
    # A shorter Log Book than his baseline means the game started a fresh
    # campaign: his sortie baseline goes back to nought with it.
    if (($p2.PSObject.Properties.Name -contains 'campaignSorties') -and ($null -ne $p2.campaignSorties)) {
        if (@($ld.rows).Count -lt [int]$p2.campaignSorties) { $obj['campaignSorties'] = 0 }
    }
    Save-Pilot $obj
    $ld
}
# Several claims at once, credited from the campaign's own Log Book, each
# with the type the save recorded.
function Add-AutoClaims {
    param([string[]]$Types, [string]$Date = '')
    if (-not $Types -or $Types.Count -le 0) { return }
    $p = Get-Pilot
    if (-not $p) { return }
    $v = 0; if (($p.PSObject.Properties.Name -contains 'victories') -and $p.victories) { $v = [int]$p.victories }
    $claims = @(); if (($p.PSObject.Properties.Name -contains 'claims') -and $p.claims) { $claims = @($p.claims) }
    $when = $Date
    if (-not $when) { $cd = Get-CampaignDate; $when = if ($cd) { $cd.ToString('yyyy-MM-dd') } else { (Get-Date).ToString('yyyy-MM-dd') } }
    foreach ($t in $Types) { $claims += $(if ($t) { "$when $t" } else { "$when" }) }
    $obj = [ordered]@{}
    foreach ($pp in $p.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
    $obj['victories'] = $v + $Types.Count
    $obj['claims'] = @($claims)
    Save-Pilot $obj
}
# "2 x Bf 109E, 1 x He 111" from the stored claim strings
function Get-ClaimSummary {
    param($Pilot)
    $claims = @(); if (($Pilot.PSObject.Properties.Name -contains 'claims') -and $Pilot.claims) { $claims = @($Pilot.claims) }
    $byType = @{}
    foreach ($c in $claims) {
        $t = ("$c" -replace '^\d{4}-\d{2}-\d{2}\s*','')
        if (-not $t) { $t = 'type not recorded' }
        if ($byType.ContainsKey($t)) { $byType[$t]++ } else { $byType[$t] = 1 }
    }
    (@($byType.Keys | Sort-Object | ForEach-Object { "$($byType[$_]) x $_" })) -join ', '
}

function New-Stat {
    param([string]$Label, [string]$Value, $Chip)
    $b = New-Object Windows.Controls.Border
    $b.Background = Res 'Panel'; $b.BorderBrush = Res 'Rule'; $b.BorderThickness = '1'; $b.CornerRadius = '4'
    $b.Padding = '20,14'; $b.Margin = '0,0,16,0'; $b.MinWidth = 148
    $sp = New-Object Windows.Controls.StackPanel
    $vrow = New-Object Windows.Controls.StackPanel; $vrow.Orientation = 'Horizontal'
    [void]$vrow.Children.Add((New-TB -Text $Value -Family $SerifFam -Size 30 -Colour '#E9E3D4' -Bold))
    if ($Chip) { $Chip.Margin = '12,0,0,0'; $Chip.VerticalAlignment = 'Center'; [void]$vrow.Children.Add($Chip) }
    [void]$sp.Children.Add($vrow)
    $l = New-TB -Text $Label -Family $CondFam -Size 11.5 -Colour '#C8973F' -Bold; $l.Margin = '0,2,0,0'
    [void]$sp.Children.Add($l)
    $b.Child = $sp; $b
}
function New-Nav {
    param([string]$Current)
    $nav = New-Object Windows.Controls.StackPanel; $nav.Orientation = 'Horizontal'; $nav.Margin = '0,0,0,22'
    # Four tabs a side, and they answer each other: the room you sit in,
    # your own book, the plotting table, and the morning's news. The German
    # side ran three for a while because the RAF's paper is a hundred
    # Allied front pages and its map is southern England, so neither could
    # simply be pointed at a Luftwaffe pilot. Both now have a German
    # counterpart of their own - Show-Morgenmeldung and the Kanalfront
    # table - so the shapes match.
    $tabs = if ($script:Side -eq 'lw') {
        @(@{k='dispersal';l='THE READY ROOM'}, @{k='logbook';l='FLUGBUCH'}, @{k='gruppen';l='THE GRUPPEN'}, @{k='paper';l='MORGENMELDUNG'})
    } else {
        @(@{k='dispersal';l='THE DISPERSAL'}, @{k='logbook';l="PILOT'S LOGBOOK"}, @{k='map';l='MAP'}, @{k='paper';l='MORNING BULLETIN'})
    }
    foreach ($t in $tabs) {
        $active = ($t.k -eq $Current)
        $tb = New-Object Windows.Controls.Border
        $tb.Padding = '15,9'; $tb.Margin = '0,0,10,0'; $tb.CornerRadius = '3'; $tb.Cursor = 'Hand'; $tb.Tag = $t.k
        $tb.Background = if ($active) { Res 'PanelHi' } else { B '#101B22' }
        $tb.BorderThickness = '0,0,0,2'
        $tb.BorderBrush = if ($active) { Res 'Brass' } else { B '#101B22' }
        $col = if ($active) { '#E9E3D4' } else { '#6F828C' }
        $tb.Child = (New-TB -Text $t.l -Family $CondFam -Size 12.5 -Colour $col -Bold)
        $tb.Add_MouseLeftButtonUp({ param($s,$e) Show-Tab ("$($s.Tag)") })
        [void]$nav.Children.Add($tb)
    }
    $nav
}
# Archive the current man and choose a squadron for the next.
# Called from the red header button.
function Start-NewCareer {
    $ans = [System.Windows.MessageBox]::Show($Win,
        "Start a new career? Your current pilot and logbook are archived (not deleted) and you choose a squadron for the new man." +
        "`n`nStart a new campaign in the game as well. The Room reads your sorties and victories from the campaign save, so a new pilot left flying the old campaign inherits its date and its squadron. He will not inherit its victories: he is credited only with what he scores from the day he is posted.",
        'New career', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    # Nothing is archived YET. This used to move the pilot away here and
    # then show the postings map, so pressing Escape at that map left you
    # with no pilot at all and a manual copy out of archive\ to recover.
    # The old man is put away by Complete-NewCareer, when the new one is
    # actually posted.
    $script:NewCareerPending = $true
    # the board for HIS air force. This sent a German pilot to the Fighter
    # Command plotting table, where he could have reported to No. 32 Squadron.
    if ($script:Side -eq 'lw') { Show-GruppeSelect } else { Show-SquadronSelect }
}
# Put the previous pilot away. Called at the moment a new man is posted.
function Complete-NewCareer {
    if (-not $script:NewCareerPending) { return }
    $script:NewCareerPending = $false
    try {
        $arch = Join-Path $StateDir ('archive\' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $arch -Force | Out-Null
        foreach ($f in @($PilotPath, $SessionsPath)) {
            if (Test-Path $f) { Move-Item $f (Join-Path $arch (Split-Path $f -Leaf)) -Force }
        }
        # a flight marker or save snapshot from the OLD career must not
        # become the new pilot's phantom first sortie
        foreach ($f in @($FlightOpen, (Join-Path $StateDir 'before.bsr'), $AutoClaimPath)) {
            if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }
    } catch { }
}
function New-LogRow {
    param($S, [switch]$Header, [int]$Index = 0)
    $b = New-Object Windows.Controls.Border
    $b.Padding = '18,10,18,10'; $b.BorderThickness = '0,0,0,1'; $b.BorderBrush = Res 'Rule'
    if ($Header) { $b.Background = B '#101B22' } elseif ($Index % 2 -eq 1) { $b.Background = Res 'Panel' } else { $b.Background = Res 'PanelHi' }
    $g = New-Object Windows.Controls.Grid
    foreach ($w in @('*','150','170','190')) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)) }
        else { $cd.Width = New-Object Windows.GridLength([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    if ($Header) {
        Add-Cell $g 'FLOWN'        0 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'FLIGHT TIME'  1 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'CAMPAIGN DAY' 2 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'OUTCOME'      3 $CondFam 12 '#C8973F' -Bold
    } else {
        $flown = "$($S.end)"; try { $flown = ([datetime]$S.end).ToString('ddd d MMM, HH:mm') } catch { }
        Add-Cell $g $flown 0 $CondFam 13.5 '#E9E3D4'
        $mins = [int]$S.minutes
        $ft = if ($mins -ge 60) { '{0}h {1:00}m' -f [int]($mins/60), ($mins%60) } else { "$mins min" }
        Add-Cell $g $ft 1 $CondFam 13.5 '#9FB0B8'
        $day = "$($S.dateAfter)"; if ((-not $day) -or ($S.mode -eq 'instant')) { $day = 'Instant Action' }
        Add-Cell $g $day 2 $CondFam 13.5 '#9FB0B8'
        $oc = ''
        if ($S.PSObject.Properties.Name -contains 'outcome') { $oc = "$($S.outcome)" }
        $occol = if ($oc -eq 'Campaign day flown') { '#8FB56A' } elseif ($oc -eq 'No campaign progress') { '#D9A441' } else { '#9FB0B8' }
        Add-Cell $g $oc 3 $CondFam 13 $occol
    }
    $b.Child = $g; $b
}
# What the game recorded for how each sortie ended (EndFlightStatus).
$EndFlightNames = @{ 0='Returned'; 1='Landed'; 2='Landed at another airfield'; 3='Landed in a field'; 4='Forced landing'; 5='Aircraft lost'; 6='Killed'; 7='Crashed'; 8='Pilot lost'; 9='Baled out' }
# A sortie as the campaign's own Log Book holds it. Claims by type from the
# kills bytes; the row number is the game's, oldest first.
function New-DiaryRow {
    param($R, [int]$Number, [switch]$Header, [int]$Index = 0, [string[]]$Bins)
    $b = New-Object Windows.Controls.Border
    $b.Padding = '18,10,18,10'; $b.BorderThickness = '0,0,0,1'; $b.BorderBrush = Res 'Rule'
    if ($Header) { $b.Background = B '#101B22' } elseif ($Index % 2 -eq 1) { $b.Background = Res 'Panel' } else { $b.Background = Res 'PanelHi' }
    $g = New-Object Windows.Controls.Grid
    foreach ($w in @('110','*','260')) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)) }
        else { $cd.Width = New-Object Windows.GridLength([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    if ($Header) {
        Add-Cell $g 'SORTIE'  0 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'OUTCOME' 1 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'CLAIMS'  2 $CondFam 12 '#C8973F' -Bold
    } else {
        Add-Cell $g "$Number" 0 $CondFam 13.5 '#E9E3D4'
        $oc = "$($EndFlightNames[[int]$R.ended])"; if (-not $oc) { $oc = "Ended $($R.ended)" }
        $occol = if ([int]$R.ended -in 1,2) { '#8FB56A' } elseif ([int]$R.ended -in 6,8) { '#D9534F' } elseif ([int]$R.ended -ge 3) { '#D9A441' } else { '#9FB0B8' }
        Add-Cell $g $oc 1 $CondFam 13.5 $occol
        $parts = @()
        # to the length of the SIDE's list, not to seven: a German pilot
        # has six types and the seventh tally is not his to read
        $nb = if ($Bins) { $Bins.Count } else { 7 }
        for ($k = 0; $k -lt $nb; $k++) { if ([int]$R.kills[$k] -gt 0) { $parts += "$([int]$R.kills[$k]) x $($Bins[$k])" } }
        $cl = if ($parts.Count) { $parts -join ', ' } else { [string][char]0x2014 }
        Add-Cell $g $cl 2 $CondFam 13.5 $(if ($parts.Count) { '#E9E3D4' } else { '#6F828C' })
    }
    $b.Child = $g; $b
}
# Asked once, after his first operation: which of the game's saves is this
# career's campaign. Only worth asking when there is more than one to
# choose between; a single save needs no confirming.
function New-SaveChooser {
    param($Pilot, [switch]$Settled)
    $files = @(Get-SaveFiles)
    if ($files.Count -eq 0) { return $null }
    $cur = Get-CampaignSavePath -Pilot $Pilot
    $bd = New-Object Windows.Controls.Border
    $bd.CornerRadius = '3'; $bd.Padding = '16,12'; $bd.Margin = '0,0,0,20'
    $bd.HorizontalAlignment = 'Left'; $bd.MaxWidth = 900
    $bd.Background = B $(if ($Settled) { '#101B22' } else { '#2A2418' })
    $bd.BorderBrush = B $(if ($Settled) { '#22303C' } else { '#C8973F' }); $bd.BorderThickness = '1'
    $sp = New-Object Windows.Controls.StackPanel
    if ($Settled) {
        $t = New-TB -Text ("Reading your campaign from " + (Split-Path $cur -Leaf) + ". Pick another if that is the wrong war.") -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Wrap
        [void]$sp.Children.Add($t)
    } else {
        [void]$sp.Children.Add((New-TB -Text 'WHICH CAMPAIGN IS YOURS?' -Family $CondFam -Size 12 -Colour '#E0952F' -Bold))
        $t = New-TB -Text ("The game keeps " + $files.Count + " saves, and your sorties and victories are read out of one of them. Say which is this career's campaign so the Room reads the right war. It is remembered, and you can change it here at any time.") -Family 'Segoe UI' -Size 13 -Colour '#C9D4CE' -Wrap
        $t.Margin = '0,6,0,10'; $t.MaxWidth = 860
        [void]$sp.Children.Add($t)
    }
    $wrap = New-Object Windows.Controls.WrapPanel; $wrap.Margin = '0,8,0,0'; $wrap.MaxWidth = 860
    foreach ($fl in $files) {
        $chip = New-Object Windows.Controls.Border
        $chip.Padding = '11,7'; $chip.Margin = '0,0,8,8'; $chip.CornerRadius = '3'; $chip.Cursor = 'Hand'
        $isCur = ($fl.FullName -eq $cur)
        $chip.Background = B $(if ($isCur) { '#213540' } else { '#101B22' })
        $chip.BorderBrush = B $(if ($isCur) { '#FFE28A' } else { '#22303C' }); $chip.BorderThickness = '1'
        $when = $fl.LastWriteTime.ToString('ddd d MMM, HH:mm')
        $inner = New-Object Windows.Controls.StackPanel
        [void]$inner.Children.Add((New-TB -Text $fl.BaseName -Family $CondFam -Size 12.5 -Colour $(if ($isCur) { '#FFE28A' } else { '#C8D4DC' }) -Bold))
        [void]$inner.Children.Add((New-TB -Text "saved $when" -Family 'Segoe UI' -Size 11 -Colour '#6F828C'))
        $chip.Child = $inner
        $chip.Tag = $fl.FullName
        $chip.Add_MouseLeftButtonUp({
            param($sender, $e)
            $p = Get-Pilot
            if ($p) {
                $o = @{}
                foreach ($pp in $p.PSObject.Properties) { $o[$pp.Name] = $pp.Value }
                $o['savePath'] = "$($sender.Tag)"
                $o['saveAsked'] = $true
                # The victory baseline is deliberately NOT touched here.
                # Zeroing it would re-credit every kill in the newly named
                # campaign, and he would be paid twice for the ones he has
                # already been given. Choosing a save chooses the file to
                # read, nothing more.
                Save-Pilot ([pscustomobject]$o)
            }
            Show-Logbook -Pilot (Get-Pilot)
        })
        [void]$wrap.Children.Add($chip)
    }
    [void]$sp.Children.Add($wrap)
    $bd.Child = $sp
    $bd
}
function Show-Logbook {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'logbook'))
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow "PILOT'S LOGBOOK" -Title ("$($Pilot.pilot)")))

    $cp = Get-CampaignPilot
    if ($cp) {
        $cpTxt = "Campaign pilot on record: $($cp.Name)"
        $cpl = New-TB -Text $cpTxt -Family 'Segoe UI' -Size 13 -Colour '#9FB0B8'
        $cpl.Margin = '0,-12,0,14'
        [void]$script:Stage.Children.Add($cpl)
    }

    $sessions = Get-Sessions
    # The campaign's own Log Book is the record of sorties when it can be
    # read; the launcher's timed sessions only supply the flying hours.
    # Level the record with it first, so victories scored in a game started
    # any way at all are in before the tiles are drawn.
    $ld = Sync-CampaignClaims
    $p2 = Get-Pilot; if ($p2) { $Pilot = $p2 }
    $career = Get-Career $Pilot $sessions -Sorties (Get-SortieCount -Diary $ld -Sessions $sessions -Pilot $Pilot)
    # everything below the counters is this career's book, not the save's
    $ld = Get-CareerDiary -Diary $ld -Pilot $Pilot
    $vics = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $vics = [int]$Pilot.victories }

    $tiles = New-Object Windows.Controls.StackPanel; $tiles.Orientation = 'Horizontal'; $tiles.Margin = '0,-6,0,12'
    [void]$tiles.Children.Add((New-Stat 'SORTIES' "$($career.sorties)"))
    [void]$tiles.Children.Add((New-Stat 'FLYING HOURS' "$($career.hours)"))
    [void]$tiles.Children.Add((New-Stat 'VICTORIES' "$vics"))
    $honours = @(Get-PlayerHonours $Pilot $career -Diary $ld)
    $Pilot = Update-CareerRecord -Pilot $Pilot -Career $career -Honours $honours
    $awTile = if ($honours.Count) { $honours[$honours.Count-1] } else { 'None yet' }
    [void]$tiles.Children.Add((New-Stat 'AWARDS' $awTile -Chip (New-RibbonRow $honours -Height 13)))
    [void]$tiles.Children.Add((New-Stat 'RANK' "$($career.rank)" -Chip $(
        $f = Get-RankBadgeFile "$($career.rank)"
        if ($f) { New-BadgeImage -File $f -Height 38 -Tip "$($career.rank)" }
    )))
    [void]$script:Stage.Children.Add($tiles)

    $isCmdr2 = (($Pilot.PSObject.Properties.Name -contains 'cmode') -and ("$($Pilot.cmode)" -eq 'commander'))
    $pn = if ($isCmdr2) { 'You command the squadron. Its fortunes in the air are yours to answer for.' }
          elseif ($career.next) { "Next promotion to $($career.next) at $($career.nextAt) sorties." } else { 'At the top of the tree.' }
    # honours read from the ribbon chips and the AWARDS tile; no text prefix
    $cs = Get-ClaimSummary $Pilot
    if ($cs -and -not $ld) { $pn = "Claims: $cs.  $pn" }
    $pnt = New-TB -Text $pn -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Wrap; $pnt.Margin = '0,2,0,18'; $pnt.MaxWidth = 860; $pnt.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($pnt)

    # ---- automatic claims: one statement, the campaign's own figure ----
    $binsL = Get-KillBins $Pilot
    if ($ld -and @($ld.rows).Count -gt 0) {
        $byType = @()
        for ($k = 0; $k -lt $binsL.Count; $k++) { if ([int]$ld.kills[$k] -gt 0) { $byType += "$([int]$ld.kills[$k]) x $($binsL[$k])" } }
        $acTxt = "Automatic claims are on: the campaign's Log Book credits you with " +
                 $(if ([int]$ld.total -eq 1) { 'one victory' } elseif ([int]$ld.total -eq 0) { 'no victories yet' } else { "$([int]$ld.total) victories" }) +
                 $(if ($byType.Count) { ', ' + ($byType -join ', ') } else { '' }) +
                 ". Every victory the campaign credits you with is entered here by itself, whichever way the game was started."
    } elseif ($ld) {
        $acTxt = "Automatic claims are on. You have not flown an operation yet; fly one and it appears here by itself, victories and all."
    } else {
        $acTxt = 'Automatic claims are on, but no campaign save could be read yet. Victories the campaign credits you with are entered here by themselves once there is one.'
    }
    $lk = New-TB -Text $acTxt -Family 'Segoe UI' -Size 12.5 -Colour '#9FB0B8' -Wrap
    $lk.Margin = '0,0,0,22'; $lk.MaxWidth = 860; $lk.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($lk)

    # which save this career is being read from
    $flownAny = ($ld -and @($ld.rows).Count -gt 0)
    $asked = (($Pilot.PSObject.Properties.Name -contains 'saveAsked') -and $Pilot.saveAsked)
    $nSaves = @(Get-SaveFiles).Count
    if ($flownAny -and $nSaves -gt 1 -and -not $asked) {
        $ch = New-SaveChooser -Pilot $Pilot
        if ($ch) { [void]$script:Stage.Children.Add($ch) }
    } elseif ($flownAny -and $nSaves -gt 0) {
        $ch = New-SaveChooser -Pilot $Pilot -Settled
        if ($ch) { [void]$script:Stage.Children.Add($ch) }
    }

    [void]$script:Stage.Children.Add((New-TB -Text 'SORTIES FLOWN' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
    if ($ld -and @($ld.rows).Count -gt 0) {
        # the game's own Log Book, newest first
        $lw = New-Object Windows.Controls.Border; $lw.BorderBrush = Res 'Rule'; $lw.BorderThickness = '1'; $lw.CornerRadius = '3'; $lw.Margin = '0,10,0,0'; $lw.ClipToBounds = $true
        $ls = New-Object Windows.Controls.StackPanel
        [void]$ls.Children.Add((New-DiaryRow -Header))
        # numbered as HIS sorties, first to last: the save's own slot
        # numbers carry the previous man's flying in them
        $arr = @($ld.rows); $i = 0
        for ($k = $arr.Count - 1; $k -ge 0; $k--) {
            [void]$ls.Children.Add((New-DiaryRow -R $arr[$k] -Number ($k + 1) -Index $i -Bins $binsL)); $i++
        }
        $lw.Child = $ls
        [void]$script:Stage.Children.Add($lw)
        $timed = @($sessions | Where-Object { [int]$_.minutes -gt 0 })
        if ($timed.Count -gt 0) {
            $tm = 0; foreach ($t in $timed) { $tm += [int]$t.minutes }
            $tl = New-TB -Text "Read from the campaign save. Flying hours are timed by the launcher: $($timed.Count) timed flight$(if ($timed.Count -ne 1) { 's' }), $([math]::Round($tm/60.0,1)) h." -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Wrap
            $tl.Margin = '0,8,0,0'
            [void]$script:Stage.Children.Add($tl)
        }
    } elseif ($ld -or @($sessions).Count -eq 0) {
        $none = New-TB -Text 'No sorties logged yet. Fly your first operation and your logbook fills itself.' -Family 'Segoe UI' -Size 13.5 -Colour '#9FB0B8' -Wrap
        $none.Margin = '0,10,0,0'
        [void]$script:Stage.Children.Add($none)
    } else {
        $lw = New-Object Windows.Controls.Border; $lw.BorderBrush = Res 'Rule'; $lw.BorderThickness = '1'; $lw.CornerRadius = '3'; $lw.Margin = '0,10,0,0'; $lw.ClipToBounds = $true
        $ls = New-Object Windows.Controls.StackPanel
        [void]$ls.Children.Add((New-LogRow -Header))
        $arr = @($sessions); $i = 0
        for ($k = $arr.Count - 1; $k -ge 0; $k--) { [void]$ls.Children.Add((New-LogRow -S $arr[$k] -Index $i)); $i++ }
        $lw.Child = $ls
        [void]$script:Stage.Children.Add($lw)
    }
}

function Show-Roster {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'dispersal'))
    $Pilot = Ensure-Squadron -Pilot $Pilot
    Set-Header $Pilot
    $sqnum = 92; if (($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { $sqnum = [int]$Pilot.sqn }
    # Every screen counts sorties from the same place: the campaign's own
    # Log Book. The dispersal used to count the launcher's timed sessions,
    # so the hero card and the roster row could disagree about your rank.
    $ld0 = Get-LatestSaveDiary
    $sessions0 = Get-Sessions
    $flownCount = Get-SortieCount -Diary $ld0 -Sessions $sessions0 -Pilot $Pilot
    $career0 = Get-Career $Pilot $sessions0 -Sorties $flownCount
    $ph0 = @(Get-PlayerHonours $Pilot $career0 -Diary (Get-CareerDiary -Diary $ld0 -Pilot $Pilot))
    $Pilot = Update-CareerRecord -Pilot $Pilot -Career $career0 -Honours $ph0
    $bs = Get-SquadronBase -Sqn $sqnum -Date $script:CampaignDate -Pilot $Pilot
    $baseTxt = if ($bs) { $bs.ToUpper() } else { 'THE DISPERSAL' }
    $eyebrow = if ($script:CampaignDate) { "$baseTxt  $([char]0x2022)  $($script:CampaignDate.ToString('dddd d MMMM yyyy').ToUpper())" } else { $baseTxt }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow $eyebrow -Title "No. $sqnum Squadron at readiness"))

    # The morning's paper, if he has not seen this one. It carries the
    # actual headline rather than "you have unread news", because the
    # headline is the reason to go and read it. Click takes him there,
    # which is also what marks it read.
    $unread = Get-UnreadBulletin -Pilot $Pilot
    if ($unread) {
        $nb = New-Object Windows.Controls.Border
        $nb.Background = B '#1A1710'; $nb.BorderBrush = $script:BrassBrush
        $nb.BorderThickness = '3,0,0,0'; $nb.CornerRadius = '0,3,3,0'
        $nb.Padding = '16,12'; $nb.Margin = '0,0,0,20'
        # the full width of the stage, as the tab row above it is: a strip
        # that stops two thirds of the way across reads as a stray card
        $nb.HorizontalAlignment = 'Stretch'; $nb.Cursor = 'Hand'
        $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
        $ic = New-NewspaperIcon
        $ic.Margin = '2,3,18,0'; $ic.VerticalAlignment = 'Top'
        [void]$row.Children.Add($ic)
        $ns = New-Object Windows.Controls.StackPanel
        $eb = New-TB -Text ('THE MORNING BULLETIN  ' + [char]0x2022 + '  ' + (Format-ShortDate "$($unread.date)")) `
                     -Family $CondFam -Size 11.5 -Colour '#C8973F' -Bold
        [void]$ns.Children.Add($eb)
        $hl = New-TB -Text "$($unread.headline)" -Family $SerifFam -Size 17 -Colour '#E9E3D4' -Wrap
        $hl.Margin = '0,4,0,0'
        [void]$ns.Children.Add($hl)
        $go = New-TB -Text 'not yet read - click to open it' -Family $CondFam -Size 12 -Colour '#6F828C'
        $go.Margin = '0,5,0,0'
        [void]$ns.Children.Add($go)
        [void]$row.Children.Add($ns)
        $nb.Child = $row
        $nb.Add_MouseLeftButtonUp({ param($s,$e) Show-Tab 'paper' })
        [void]$script:Stage.Children.Add($nb)
    }

    # the only photograph on the wall is yours
    $hero = New-Object Windows.Controls.StackPanel; $hero.Orientation = 'Horizontal'; $hero.Margin = '0,-6,0,32'
    [void]$hero.Children.Add((New-Frame -Pilot $Pilot -IsPlayer))
    $d = New-Object Windows.Controls.StackPanel; $d.Margin = '30,4,0,0'; $d.VerticalAlignment = 'Top'
    [void]$d.Children.Add((New-TB -Text ("$($Pilot.pilot)") -Family $SerifFam -Size 30 -Colour '#E9E3D4' -Bold))
    $line = if ($flownCount -gt 0) { "$($Pilot.rank)   $([char]0x2022)   $($Pilot.codes)" } else { "$($Pilot.rank)   $([char]0x2022)   awaiting first operation" }
    $lt = New-TB -Text $line -Family $CondFam -Size 15 -Colour '#9FB0B8'; $lt.Margin = '0,7,0,0'
    [void]$d.Children.Add($lt)
    # worn on the tunic: rank cuff and wings, the ribbons beneath them
    $chipRow = New-Object Windows.Controls.StackPanel; $chipRow.Orientation = 'Horizontal'; $chipRow.Margin = '0,14,0,0'
    $rbf = Get-RankBadgeFile "$($Pilot.rank)"
    if ($rbf) {
        $cuff = New-BadgeImage -File $rbf -Height 52 -Tip "$($Pilot.rank)"
        if ($cuff) { $cuff.Margin = '0,0,10,0'; [void]$chipRow.Children.Add($cuff) }
    }
    $wg = New-BadgeImage -File 'wings.png' -Height 52 -Tip "Qualified pilot's flying badge"
    if ($wg) { [void]$chipRow.Children.Add($wg) }
    if ($chipRow.Children.Count -gt 0) { [void]$d.Children.Add($chipRow) }
    # The ribbons on the tunic are the ribbons in the record, not a second
    # opinion. This used to work the honours out again from the launcher's
    # timed sessions alone, with no Log Book: it counted a different number
    # of sorties, so it could disagree with the roster row below it about
    # rank, and it could never show the VC, which is read from the Book.
    $heroRib = New-RibbonRow $ph0
    if ($heroRib) { $heroRib.Margin = '0,10,0,0'; $heroRib.HorizontalAlignment = 'Left'; [void]$d.Children.Add($heroRib) }
    $st = New-TB -Text 'ON STRENGTH' -Family $CondFam -Size 13 -Colour '#C8973F' -Bold; $st.Margin = '0,16,0,0'
    [void]$d.Children.Add($st)
    if ($Pilot.note) {
        $nt = New-TB -Text ("$($Pilot.note)") -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Wrap
        $nt.Margin = '0,12,0,0'; $nt.MaxWidth = 380
        [void]$d.Children.Add($nt)
    }
    [void]$hero.Children.Add($d)
    [void]$script:Stage.Children.Add($hero)

    # first-timer's orders: until a sortie is in the book, say what comes next
    if ($flownCount -eq 0) {
        $ord = New-Object Windows.Controls.Border
        $ord.Background = B '#1E2A18'; $ord.BorderBrush = B '#4A6B3A'; $ord.BorderThickness = '1'
        $ord.CornerRadius = '3'; $ord.Padding = '16,12'; $ord.Margin = '0,-14,0,24'; $ord.HorizontalAlignment = 'Left'; $ord.MaxWidth = 760
        $os2 = New-Object Windows.Controls.StackPanel
        [void]$os2.Children.Add((New-TB -Text 'YOUR ORDERS' -Family $CondFam -Size 12 -Colour '#8FB56A' -Bold))
        $ot = New-TB -Text "Press PLAY (top right). In the game, start or continue the Campaign and fly the day. When you come back here your first sortie will be in the logbook, and your aircraft, with your code letter and serial, will be waiting on the board." -Family 'Segoe UI' -Size 13.5 -Colour '#C9D4CE' -Wrap
        $ot.Margin = '0,6,0,0'
        [void]$os2.Children.Add($ot)
        $ord.Child = $os2
        [void]$script:Stage.Children.Add($ord)
    }
    $Pilot = Ensure-Serial -Pilot $Pilot
    $flown = ($flownCount -gt 0)
    $ac = if ($flown) { New-Aircraft -Pilot $Pilot } else { $null }
    if ($ac) {
        [void]$script:Stage.Children.Add($ac)
        $acHint = New-TB -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Wrap -Text (
            'The squadron code, your letter and the serial can be dragged to sit better on the ' +
            'aeroplane, and the wheel sizes them. Where you put them is remembered for this mark of ' +
            'aircraft, so a Spitfire and a Hurricane keep their own. Double-click a marking to put it ' +
            'back where the research says.')
        $acHint.Margin = '0,-4,0,16'; $acHint.MaxWidth = 760
        [void]$script:Stage.Children.Add($acHint)
    }

    # the squadron as a records book: names, victories, fate
    [void]$script:Stage.Children.Add((New-TB -Text 'THE SQUADRON' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
    $men = @(Get-Historical -Sqn $sqnum)
    $sqrec = $null
    try { $sqrec = Get-SquadronRecord -Sqn $sqnum } catch { }
    # Say what this squadron's roster actually holds. Promising victories
    # "documented for the aces" in front of 62 blank columns was a straight
    # contradiction on any squadron whose scores are not researched yet.
    $anyVics = $false
    foreach ($h in $men) {
        if ((Get-DatedVictories $h).Count -gt 0) { $anyVics = $true; break }
        if (($h.PSObject.Properties.Name -contains 'victories_total') -and ($null -ne $h.victories_total) -and ([int]$h.victories_total -gt 0)) { $anyVics = $true; break }
    }
    $scoreNote = if ($anyVics) { ' Victories and decorations are documented for the aces and estimated for the others.' }
                 else { ' Victories and decorations for this squadron are not researched yet, and are left blank rather than invented.' }
    $subText = if ($script:CampaignDate) {
        "The squadron as it stood on $($script:CampaignDate.ToString('d MMMM yyyy')). Men on strength show as such; losses and awards appear as their day is reached." + $scoreNote
    } else {
        'No campaign in progress, so this shows the final Battle of Britain record. Start a campaign and the board tracks the squadron day by day.' + $scoreNote
    }
    $sub = New-TB -Text $subText -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Wrap
    $sub.Margin = '0,4,0,14'; $sub.MaxWidth = 720; $sub.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($sub)

    $listWrap = New-Object Windows.Controls.Border
    $listWrap.BorderBrush = Res 'Rule'; $listWrap.BorderThickness = '1'; $listWrap.CornerRadius = '3'; $listWrap.ClipToBounds = $true
    $ls = New-Object Windows.Controls.StackPanel
    [void]$ls.Children.Add((New-RosterRow -Header))
    # you, first on the board, with your LIVE record
    $pv = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $pv = [int]$Pilot.victories }
    $ph = $ph0
    $me = [pscustomobject]@{
        pilot = "$($Pilot.pilot)"
        rank = "$($career0.rank)"
        codes = "$($Pilot.codes)"
        status = 'On strength'
        victories = $pv
        awards = if ($ph.Count) { $ph[$ph.Count-1] } else { '' }
    }
    [void]$ls.Children.Add((New-RosterRow -P $me -Index 0 -IsPlayer))
    $i = 1
    # The board is the squadron AS IT STOOD: men who have not joined yet,
    # and men already lost, are not on it. The lost are named underneath.
    $onStrength = @($men | Where-Object { Test-OnStrength $_ $script:CampaignDate })
    # Pilots the campaign has lost that history does not name. They stand
    # on the board like anyone else until their day, and are marked as
    # invented wherever they appear.
    $unnamed = 0
    try { $unnamed = Get-UnnamedLosses -Roster $men -Record $sqrec -Date $script:CampaignDate } catch { }
    # The squadron's own men carry the campaign's losses first. Only when
    # there are not enough ordinary pilots to carry them does anyone have
    # to be invented.
    $script:CampaignLost = Get-CampaignCasualties -Roster $men -Count $unnamed -Sqn $sqnum
    $stillUnnamed = [Math]::Max(0, $unnamed - $script:CampaignLost.Count)
    $invented = @(Get-InventedPilots -Sqn $sqnum -Count $stillUnnamed -Roster $men)
    foreach ($h in $onStrength) {
        [void]$ls.Children.Add((New-RosterRow -P $h -Index $i -CampaignLost:($script:CampaignLost.ContainsKey("$($h.pilot)")))); $i++
    }
    foreach ($h in $invented) {
        $row = [pscustomobject]@{
            pilot = "$($h.pilot)"; rank = "$($h.rank)"; codes = ''
            historical = $false
            fate = [pscustomobject]@{ status = 'Lost'; date = $null; note = 'Lost in this campaign' }
            joined = $null; left = $null; left_reason = $null
            victories = @(); victories_total = $null; awards = @()
        }
        [void]$ls.Children.Add((New-RosterRow -P $row -Index $i -Invented)); $i++
    }
    $listWrap.Child = $ls
    [void]$script:Stage.Children.Add($listWrap)

    # What the squadron itself has done in this campaign, out of the game's
    # own diary. The game counts; history names. Neither alone is a
    # squadron.
    if ($sqrec) {
        $h2 = New-TB -Text 'THE SQUADRON IN THIS CAMPAIGN' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold
        $h2.Margin = '0,26,0,0'
        [void]$script:Stage.Children.Add($h2)
        $byType = @()
        # the squadron's own tally, in the types ITS side shoots at
        $sqBins = Get-KillBins $Pilot
        for ($k = 0; $k -lt $sqBins.Count; $k++) { if ([int]$sqrec.Kills[$k] -gt 0) { $byType += "$([int]$sqrec.Kills[$k]) x $($sqBins[$k])" } }
        $line = "$($sqrec.Actions) $(if ($sqrec.Actions -eq 1) { 'action' } else { 'actions' }), " +
                "$($sqrec.Launched) sorties flown. " +
                $(if ($sqrec.Total -gt 0) { "Claims: $($sqrec.Total) ($($byType -join ', ')). " } else { 'No claims yet. ' }) +
                $(if ($sqrec.AcLost -gt 0 -or $sqrec.PilotsLost -gt 0) {
                    "Lost $($sqrec.AcLost) aircraft and $($sqrec.PilotsLost) $(if ($sqrec.PilotsLost -eq 1) { 'pilot' } else { 'pilots' })" +
                    $(if ($sqrec.AcDamaged -gt 0) { ", $($sqrec.AcDamaged) more damaged." } else { '.' })
                } else { 'No losses.' })
        $lt3 = New-TB -Text $line -Family 'Segoe UI' -Size 13.5 -Colour '#C9D4CE' -Wrap
        $lt3.Margin = '0,8,0,4'; $lt3.MaxWidth = 900
        [void]$script:Stage.Children.Add($lt3)
        $noteTxt = 'Read from the campaign save. The game keeps this tally for every squadron but names nobody.'
        if ($unnamed -gt 0) {
            $noteTxt += "  $unnamed of those losses are not in the historical record, so the board gives them to men of the squadron whose own war the record does not follow. They are marked as lost in YOUR campaign, with their real ending beside them. No ace, no decorated man and nobody with a recorded fate is touched."
        }
        $note2 = New-TB -Text $noteTxt -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Wrap
        $note2.Margin = '0,0,0,4'; $note2.MaxWidth = 900
        [void]$script:Stage.Children.Add($note2)
    }

    # Who the squadron has lost, most recent first, and who went this week.
    if ($script:CampaignDate) {
        $gone = @()
        foreach ($h in $men) {
            $l = Get-LeaveDate $h
            if ($l -and ($l -le $script:CampaignDate) -and ($l -ge $BattleStart)) {
                $gone += [pscustomobject]@{ Man = $h; When = $l }
            }
        }
        if ($gone.Count -gt 0) {
            $gone = @($gone | Sort-Object When -Descending)
            $week = @($gone | Where-Object { ($script:CampaignDate - $_.When).TotalDays -le 7 })
            $hdr = New-TB -Text 'LOSSES' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold
            $hdr.Margin = '0,26,0,0'
            [void]$script:Stage.Children.Add($hdr)
            $lead = if ($week.Count -eq 0) { "The squadron has lost $($gone.Count) $(if ($gone.Count -eq 1) { 'man' } else { 'men' }) since the Battle opened. None this week." }
                    elseif ($week.Count -eq 1) { "One man lost in the past week, $($gone.Count) since the Battle opened." }
                    else { "$($week.Count) men lost in the past week, $($gone.Count) since the Battle opened." }
            $lt2 = New-TB -Text $lead -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Wrap
            $lt2.Margin = '0,8,0,8'; $lt2.MaxWidth = 900
            [void]$script:Stage.Children.Add($lt2)
            $lossWrap = New-Object Windows.Controls.Border
            $lossWrap.BorderBrush = Res 'Rule'; $lossWrap.BorderThickness = '1'; $lossWrap.CornerRadius = '3'; $lossWrap.ClipToBounds = $true
            $lsx = New-Object Windows.Controls.StackPanel
            $j = 0
            foreach ($g in ($gone | Select-Object -First 12)) {
                $row = New-Object Windows.Controls.Border
                $row.Padding = '18,8'; $row.BorderThickness = '0,0,0,1'; $row.BorderBrush = Res 'Rule'
                $row.Background = if ($j % 2 -eq 1) { Res 'Panel' } else { Res 'PanelHi' }
                $gg = New-Object Windows.Controls.Grid
                foreach ($w in @('130','*','220')) {
                    $cd = New-Object Windows.Controls.ColumnDefinition
                    if ($w -eq '*') { $cd.Width = New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)) }
                    else { $cd.Width = New-Object Windows.GridLength([double]$w) }
                    [void]$gg.ColumnDefinitions.Add($cd)
                }
                Add-Cell $gg $g.When.ToString('d MMM') 0 $CondFam 13 '#9FB0B8'
                Add-Cell $gg "$($g.Man.pilot)" 1 $SerifFam 14.5 '#E9E3D4'
                Add-Cell $gg (Get-FateText $g.Man -Short) 2 $CondFam 13 (Fate-Colour (Get-FateText $g.Man))
                $row.Child = $gg
                [void]$lsx.Children.Add($row)
                $j++
            }
            $lossWrap.Child = $lsx
            [void]$script:Stage.Children.Add($lossWrap)
        }
    }

    # Every squadron gets its record of service, from the game's own order
    # of battle: where it stood as the campaign moved, and how Fighter
    # Command rated it on the first day.
    $oob = Get-Oob -Sqn $sqnum
    if ($oob) {
        $card = New-Object Windows.Controls.Border
        $card.Background = Res 'Panel'; $card.BorderBrush = Res 'Rule'; $card.BorderThickness = '1'; $card.CornerRadius = '4'
        $card.Padding = '20,16'; $card.Margin = '0,16,0,0'; $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 900
        $cst = New-Object Windows.Controls.StackPanel
        [void]$cst.Children.Add((New-TB -Text 'RECORD OF SERVICE' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
        $moves = @()
        foreach ($d in @('1940-07-10','1940-08-12','1940-08-24','1940-09-07')) {
            $b = "$($oob.bases.$d)"
            if ($b) {
                $lbl = ([datetime]::ParseExact($d,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)).ToString('d MMM')
                # "13 Group" is the game's shorthand for resting in the north
                $where = if ($b -eq '13 Group') { 'resting in the north' } else { "RAF $b" }
                $moves += "$lbl  $where"
            }
        }
        $sep = "     $([char]0x2022)     "
        $mv = New-TB -Text ($moves -join $sep) -Family 'Segoe UI' -Size 13 -Colour '#C9D4CE' -Wrap
        $mv.Margin = '0,9,0,0'; $mv.MaxWidth = 840
        [void]$cst.Children.Add($mv)
        # the game's own campaign ratings, said plainly as such rather than
        # dressed up as a historical Fighter Command assessment
        $rate = "Flying $($oob.type).  The campaign starts the squadron $("$($oob.skill)".ToLower()) in skill, with $("$($oob.fatigue)".ToLower()) reserves of freshness."
        if ("$($oob.notes)") { $rate += "  $($oob.notes)." }
        $rt = New-TB -Text $rate -Family 'Segoe UI' -Size 13 -Colour '#9FB0B8' -Wrap
        $rt.Margin = '0,8,0,0'; $rt.MaxWidth = 840
        [void]$cst.Children.Add($rt)
        if ($men.Count -eq 0) {
            $pend = New-TB -Text 'The names of this squadron''s pilots are still being researched; yours is on the board above.' -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Wrap
            $pend.Margin = '0,10,0,0'; $pend.MaxWidth = 840
            [void]$cst.Children.Add($pend)
        } else {
            # credit whoever the names came from; a roster may mix sources
            $srcs = @($men | ForEach-Object { "$($_.src)" } | Where-Object { $_ } | Sort-Object -Unique)
            if ($srcs.Count) {
                $sl = New-TB -Text ("Names from " + ($srcs -join '; ') + ".") -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Wrap
                $sl.Margin = '0,10,0,0'; $sl.MaxWidth = 840
                [void]$cst.Children.Add($sl)
            }
        }
        $card.Child = $cst
        [void]$script:Stage.Children.Add($card)
    } elseif ($men.Count -eq 0) {
        $nr = New-TB -Text 'The names of this squadron''s pilots are still being researched; yours is on the board above.' -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C'
        $nr.Margin = '2,8,0,0'
        [void]$script:Stage.Children.Add($nr)
    }
}

function Update-RankSegs {
    foreach ($seg in @($script:RankSegs)) {
        $on = ("$($seg.Tag)" -eq "$($script:SelRank)")
        $seg.Background = B $(if ($on) { '#213540' } else { '#101B22' })
        $seg.BorderThickness = '0,0,0,2'
        $seg.BorderBrush = B $(if ($on) { '#C8973F' } else { '#101B22' })
    }
}
function Update-CreateValid {
    $ok = ($script:NameBox.Text.Trim().Length -ge 2) -and ($null -ne $script:SelPortrait)
    $script:SubmitBtn.IsEnabled = $ok
    Set-ChromeActionEnabled $ok
}
function Invoke-Submit {
    Complete-NewCareer
    $isCmdr = $false
    $rank = if ($script:SelRank) { "$($script:SelRank)" } else { 'Sergeant' }
    $letter = ('A','B','D','E','F','G','H','J','K','L','N','P','R','S','T','U','V','W','X','Y','Z' | Get-Random)
    $serial = New-Serial -Type ("$($script:SelSq.Type)")
    $pilot = [ordered]@{
        pilot   = $script:NameBox.Text.Trim()
        rank    = $rank
        codes   = $(if ("$($script:SelSq.Code)") { "$($script:SelSq.Code)-$letter" } else { "$letter" })
        status  = 'On strength'
        serials = $serial
        note    = "Posted to No. $($script:SelSq.Num) Squadron at $($script:SelSq.Base)."
        cmode   = if ($isCmdr) { 'commander' } else { 'pilot' }
        sqn     = [int]$script:SelSq.Num
        sqcode  = "$($script:SelSq.Code)"
        actype  = "$($script:SelSq.Type)"
        base    = "$($script:SelSq.Base)"
        period  = "$($script:SelSq.Period)"
        historical = $false
        portrait = $script:SelPortrait
        created = (Get-Date).ToString('yyyy-MM-dd')
    }
    # Where the campaign stood the day he was posted. Everything already in
    # the Log Book belongs to the man before him; this pilot's own record
    # is what happens from here.
    $ld0 = Get-LatestSaveDiary
    if ($ld0) {
        $pilot['campaignSorties'] = @($ld0.rows).Count
        $pilot['campaignKills'] = @(0..6 | ForEach-Object { [int]$ld0.kills[$_] })
    } else {
        $pilot['campaignSorties'] = 0
        $pilot['campaignKills'] = @(0,0,0,0,0,0,0)
    }
    # The one write that is MEANT to replace a career with a smaller
    # record: a new man starts with nothing but what he was posted with.
    # Complete-NewCareer has already put the previous pilot away, so there
    # should be nothing here to lose, but say so rather than relying on it.
    Save-Pilot -Pilot $pilot -Shrink
    Show-Roster -Pilot (Get-Pilot)
}

# =====================================================================
#  The map: the plotting table with your own station ringed
# =====================================================================
# Make a map pan and zoom under the mouse, and clip it to its frame.
#
# Fifty-two squadrons on one table crowd badly around Biggin Hill and
# Hornchurch. The wheel zooms about the pointer, a drag moves the sheet,
# and a double-click puts it back. The rings scale with the map, so a
# knot of them opens out as you go in.
function Enable-MapZoom {
    param($Frame, $Content, [double]$Min = 1.0, [double]$Max = 6.0)
    $sc = New-Object Windows.Media.ScaleTransform 1, 1
    $tr = New-Object Windows.Media.TranslateTransform 0, 0
    $tg = New-Object Windows.Media.TransformGroup
    [void]$tg.Children.Add($sc); [void]$tg.Children.Add($tr)
    $Content.RenderTransform = $tg
    $Frame.ClipToBounds = $true
    $st = @{ Sc = $sc; Tr = $tr; Min = $Min; Max = $Max; Drag = $false; PX = 0.0; PY = 0.0; Moved = $false }
    $Frame.Tag = $st
    $Frame.Add_MouseWheel({
        param($sender, $e)
        $t = $sender.Tag
        $p = $e.GetPosition($sender)
        $old = $t.Sc.ScaleX
        $new = if ($e.Delta -gt 0) { $old * 1.25 } else { $old / 1.25 }
        if ($new -lt $t.Min) { $new = $t.Min }
        if ($new -gt $t.Max) { $new = $t.Max }
        if ($new -eq $old) { $e.Handled = $true; return }
        # hold the point under the pointer still
        $t.Tr.X = $p.X - ($p.X - $t.Tr.X) * ($new / $old)
        $t.Tr.Y = $p.Y - ($p.Y - $t.Tr.Y) * ($new / $old)
        $t.Sc.ScaleX = $new; $t.Sc.ScaleY = $new
        Limit-MapPan $sender
        $e.Handled = $true
    })
    $Frame.Add_MouseLeftButtonDown({
        param($sender, $e)
        $t = $sender.Tag
        if ($e.ClickCount -ge 2) {
            $t.Sc.ScaleX = 1.0; $t.Sc.ScaleY = 1.0; $t.Tr.X = 0.0; $t.Tr.Y = 0.0
            $e.Handled = $true; return
        }
        if ($t.Sc.ScaleX -le $t.Min) { return }
        $p = $e.GetPosition($sender)
        $t.PX = $p.X; $t.PY = $p.Y; $t.Drag = $true; $t.Moved = $false
        [void]$sender.CaptureMouse()
    })
    $Frame.Add_MouseMove({
        param($sender, $e)
        $t = $sender.Tag
        if (-not $t.Drag) { return }
        $p = $e.GetPosition($sender)
        $t.Tr.X += ($p.X - $t.PX); $t.Tr.Y += ($p.Y - $t.PY)
        $t.PX = $p.X; $t.PY = $p.Y; $t.Moved = $true
        Limit-MapPan $sender
    })
    $Frame.Add_MouseLeftButtonUp({
        param($sender, $e)
        $t = $sender.Tag
        if ($t.Drag) { $t.Drag = $false; [void]$sender.ReleaseMouseCapture() }
    })
}
# Keep the sheet over the frame: no dragging the map off into space.
function Limit-MapPan {
    param($Frame)
    $t = $Frame.Tag
    $w = $Frame.ActualWidth; $h = $Frame.ActualHeight
    if ($w -le 0) { $w = $Frame.Width }; if ($h -le 0) { $h = $Frame.Height }
    $over = ($t.Sc.ScaleX - 1.0)
    $maxX = $w * $over; $maxY = $h * $over
    if ($t.Tr.X -gt 0) { $t.Tr.X = 0 }
    if ($t.Tr.Y -gt 0) { $t.Tr.Y = 0 }
    if ($t.Tr.X -lt -$maxX) { $t.Tr.X = -$maxX }
    if ($t.Tr.Y -lt -$maxY) { $t.Tr.Y = -$maxY }
}
# A squadron on the table is drawn as a callout: a small dot on its
# actual field, a thin elbowed leader, and a numbered circle set where
# there is room for it. Rings drawn on the fields themselves buried the
# map's own lettering and each other, and no amount of fanning fixed it
# once fifty-two squadrons were on one sheet.
#
# Placement is a coarse grid. Each circle takes the nearest free cell to
# its own field, so a lone squadron sits just beside its station and a
# crowded one steps outward until it finds space.
# What the pointer is over, set out as a card rather than one long line of
# bullet points. Pass a hashtable of the parts; $null clears it.
function Set-MapReadout {
    param($Info)
    if (-not $script:MapTitle) { return }
    if (-not $Info) {
        $script:MapTitle.Text = ' '
        $script:MapWhere.Text = ' '
        $script:MapNote.Text  = ' '
        return
    }
    $script:MapTitle.Text = "$($Info.Title)"
    $script:MapTitle.Foreground = B $(if ($Info.Mine) { '#FFE28A' } else { '#E9E3D4' })
    $script:MapWhere.Text = "$($Info.Where)"
    $script:MapNote.Text  = "$($Info.Note)"
}
# =====================================================================
#  The squadron layer on the sector map
#
#  Forty-one squadrons will not go on as forty-one circles. Ten fields in
#  the London approaches hold twenty-one of them, and nothing readable
#  packs into that square. So the layer draws ONE PLAQUE PER AIRFIELD
#  carrying its squadrons as numbered tiles, bundles fields that sit on
#  top of one another at this scale, and docks the plaque to a margin
#  rail where the field has no room to hold it. Leaders are straight:
#  an elbow reads as a wiring diagram and costs twice the ink for
#  nothing. The sheet itself no longer prints the names of the packed
#  fields, so their plaque carries the name instead.
# =====================================================================
$PlaqueTileW = 29.0     # 28px tile plus its hairline
# One place decides how wide a tile is, because the layout measures the
# plaque BEFORE the tiles exist and the tiles are then drawn into it. Two
# answers here and the label is clipped by the plaque it sits in, which is
# exactly what a German Gruppe did: "III./JG 26" in a box sized for "266".
function Get-TileWidth {
    param($Sq)
    $lab = ''
    if ($Sq -is [System.Collections.IDictionary]) { if ($Sq.Contains('Label')) { $lab = "$($Sq.Label)" } }
    elseif ($Sq.PSObject.Properties.Name -contains 'Label') { $lab = "$($Sq.Label)" }
    if (-not $lab) { return 28.0 }
    # Bahnschrift SemiCondensed at 11.5 runs about 5.6px a character
    [math]::Max(28.0, [math]::Ceiling($lab.Length * 5.6) + 12.0)
}
$PlaqueH     = 24.0
$PlaqueNameH = 13.0
$PlaqueBundle = 22.0    # dots closer than this are one drawable anchor

function Format-FieldName {
    param([string]$Base)
    $n = "$Base" -replace '^RAF ', ''
    $sec = $MapSectors[$Base]
    if ($sec -and "$($sec.role)" -eq 'sector station' -and "$($sec.letter)") { $n = "$n ($($sec.letter))" }
    $n
}
function Measure-PlaqueName {
    param([string]$Text)
    # 10px condensed. Near enough for collision work and it costs nothing.
    [math]::Max(30.0, $Text.Length * 5.9 + 8.0)
}
function Set-PlaqueSize {
    param($G)
    $gw = 0.0; $anyName = $false
    foreach ($m in $G.Members) {
        $m.OW = if ($m.Named) { [math]::Max($m.PW, $m.NW) } else { $m.PW }
        if ($m.Named) { $anyName = $true }
        if ($gw -gt 0) { $gw += 10.0 }
        $gw += $m.OW
    }
    $G.W = $gw
    $G.NameRow = $anyName
    $G.H = $PlaqueH + $(if ($anyName) { $PlaqueNameH } else { 0.0 })
}
function Test-BoxClear {
    param($Box, $Obstacles)
    foreach ($t in $Obstacles) {
        if (-not ($Box[2] -lt $t[0] -or $Box[0] -gt $t[2] -or $Box[3] -lt $t[1] -or $Box[1] -gt $t[3])) { return $false }
    }
    $true
}

# What the pointer gets when it finds a squadron: not a line of text but
# the squadron's own card, with its aeroplane, where it stood that day,
# what Fighter Command thought of it, and the men on its strength.
function New-SquadronTip {
    param($Card)
    # WPF's own tooltip chrome is a pale bordered box, which would frame
    # the card in daylight. Take it off and let the card be the tooltip.
    $tt = New-Object Windows.Controls.ToolTip
    $tt.Content = $Card
    $tt.Background = B '#00000000'
    $tt.BorderThickness = '0'
    $tt.Padding = '0'
    $tt.HasDropShadow = $false
    $tt.Placement = 'Right'
    $tt.HorizontalOffset = 10
    $tt
}
function New-SquadronCard {
    param([int]$Num, [string]$Type, [string]$Base, [bool]$Mine, $Date)
    $card = New-Object Windows.Controls.Border
    $card.Background = B '#F20B141B'; $card.BorderBrush = B $(if ($Mine) { '#FFE28A' } else { '#2C3A52' })
    $card.BorderThickness = '1'; $card.CornerRadius = '3'; $card.Padding = '0'
    $card.MaxWidth = 430
    $col = New-Object Windows.Controls.StackPanel

    # the head: the aeroplane it flew, and who it is
    $head = New-Object Windows.Controls.Border
    $head.Background = B '#14202B'; $head.Padding = '16,12,16,11'
    $hrow = New-Object Windows.Controls.StackPanel; $hrow.Orientation = 'Horizontal'
    $silPath = Join-Path (Join-Path $ModDir 'aircraft') $(if ("$Type" -match 'Spitfire') { 'spitfire.png' } else { 'hurricane.png' })
    $sil = Load-Image -Path $silPath -DecodeWidth 320
    if ($sil) {
        $im = New-Object Windows.Controls.Image
        $im.Source = $sil; $im.Width = 96; $im.Stretch = 'Uniform'
        $im.Opacity = 0.85; $im.Margin = '0,0,14,0'; $im.VerticalAlignment = 'Center'
        [void]$hrow.Children.Add($im)
    }
    $hc = New-Object Windows.Controls.StackPanel; $hc.VerticalAlignment = 'Center'
    $ttl = New-TB -Text "No. $Num Squadron" -Family $SerifFam -Size 19 -Colour $(if ($Mine) { '#FFE28A' } else { '#E9E3D4' })
    [void]$hc.Children.Add($ttl)
    $sub = "$Type"
    if ($SquadronCodes.ContainsKey([int]$Num)) { $sub += "   $([char]0x2022)   code $($SquadronCodes[[int]$Num])" }
    [void]$hc.Children.Add((New-TB -Text $sub -Family $CondFam -Size 12.5 -Colour '#8FBEDA'))
    [void]$hrow.Children.Add($hc)
    $head.Child = $hrow
    [void]$col.Children.Add($head)

    $body = New-Object Windows.Controls.StackPanel; $body.Margin = '16,12,16,14'

    # where it stood
    $where = "$Base"
    $g = Get-GroupForBase $Base
    if ($g) { $where += "   $([char]0x2022)   No. $g Group" }
    [void]$body.Children.Add((New-TB -Text $where -Family $CondFam -Size 13 -Colour '#C8D4DC'))
    $secTxt = Get-SectorText $Base
    if ($secTxt) {
        $st = New-TB -Text $secTxt -Family 'Segoe UI' -Size 11.5 -Colour '#6F828C' -Wrap
        $st.Margin = '0,2,0,0'; [void]$body.Children.Add($st)
    }

    # what the order of battle thought of it
    $oob = Get-Oob -Sqn $Num
    if ($oob) {
        $cond = "$($oob.skill) squadron, $("$($oob.fatigue)".ToLower()) condition"
        $ct = New-TB -Text $cond -Family $CondFam -Size 12 -Colour '#8FB56A'
        $ct.Margin = '0,8,0,0'; [void]$body.Children.Add($ct)
        if ("$($oob.notes)") {
            $nt = New-TB -Text "$($oob.notes)" -Family 'Segoe UI' -Size 11.5 -Colour '#6F828C' -Wrap
            $nt.Margin = '0,3,0,0'; $nt.MaxWidth = 396; [void]$body.Children.Add($nt)
        }
    }

    # and the men on its strength this morning
    $men = @(Get-Historical -Sqn $Num | Where-Object { $_.historical -and (Test-OnStrength $_ $Date) })
    if ($men.Count) {
        $rule = New-Object Windows.Shapes.Rectangle
        $rule.Height = 1; $rule.Fill = B '#22303C'; $rule.Margin = '0,12,0,10'
        [void]$body.Children.Add($rule)
        $hdr = New-TB -Text "ON STRENGTH  $([char]0x2022)  $($men.Count) PILOTS" -Family $CondFam -Size 10.5 -Colour '#C8973F' -Bold
        [void]$body.Children.Add($hdr)
        $best = @($men | Sort-Object @{ e = { [int](Accrue-Victories $_ $Date) }; Descending = $true } | Select-Object -First 3)
        foreach ($m in $best) {
            $v = [int](Accrue-Victories $m $Date)
            $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,5,0,0'
            $nm = New-TB -Text "$($m.pilot)" -Family 'Segoe UI' -Size 12 -Colour '#C8D4DC'
            $nm.Width = 210; [void]$row.Children.Add($nm)
            $rk = New-TB -Text (Short-Rank "$($m.rank)") -Family $CondFam -Size 11.5 -Colour '#6F828C'
            $rk.Width = 62; [void]$row.Children.Add($rk)
            if ($v -gt 0) {
                $vt = New-TB -Text "$v victor$(if ($v -eq 1) { 'y' } else { 'ies' })" -Family $CondFam -Size 11.5 -Colour '#F5A83C'
                [void]$row.Children.Add($vt)
            }
            [void]$body.Children.Add($row)
        }
    }
    [void]$col.Children.Add($body)
    $card.Child = $col
    $card
}
function Short-Rank {
    param([string]$R)
    switch -Regex ("$R") {
        'Squadron Leader'   { 'S/Ldr' ; break }
        'Flight Lieutenant' { 'F/Lt'  ; break }
        'Flying Officer'    { 'F/O'   ; break }
        'Pilot Officer'     { 'P/O'   ; break }
        'Sergeant'          { 'Sgt'   ; break }
        'Wing Commander'    { 'W/Cdr' ; break }
        'Oberfeldwebel'     { 'Ofw.'  ; break }
        'Oberleutnant'      { 'Oblt.' ; break }
        'Unteroffizier'     { 'Uffz.' ; break }
        'Feldwebel'         { 'Fw.'   ; break }
        'Leutnant'          { 'Lt.'   ; break }
        'Hauptmann'         { 'Hptm.' ; break }
        default             { "$R" }
    }
}

# One squadron lit and the rest held back. Hover does it for as long as
# the pointer is there; a selection does it until the choice changes. Both
# go through here so that letting go of a hover restores the SELECTION
# rather than lighting the whole sheet again.
function Set-MapFocus {
    param($Asm)
    $lit = $Asm
    if (-not $lit) { foreach ($a in $script:MapAssemblies) { if ($a.Sel) { $lit = $a; break } } }
    foreach ($a in $script:MapAssemblies) {
        $on = ((-not $lit) -or ($a -eq $lit) -or $a.Mine)
        $o = if ($on) { 1.0 } else { 0.3 }
        $a.Plaque.Opacity = $o; $a.Lead.Opacity = $o; $a.Dot.Opacity = $o
        if ($a.Name) { $a.Name.Opacity = $o }
        $top = ($a -eq $lit)
        [Windows.Controls.Panel]::SetZIndex($a.Plaque, $(if ($top) { 40 } else { 10 }))
        [Windows.Controls.Panel]::SetZIndex($a.Lead,   $(if ($top) { 38 } else { 5 }))
        [Windows.Controls.Panel]::SetZIndex($a.Dot,    $(if ($top) { 39 } else { 8 }))
        if ($a.Name) { [Windows.Controls.Panel]::SetZIndex($a.Name, $(if ($top) { 41 } else { 12 })) }
        # the chosen squadron's own plaque keeps its gold and its glow
        $a.Plaque.BorderBrush = B $(if ($a.Sel) { '#FFE28A' } elseif ($a.Mine) { '#FFE28A' } elseif ($top) { '#5A6B85' } else { '#2C3A52' })
        $a.Plaque.Background  = B $(if ($a.Sel -or $top) { '#0E1626' } else { '#EB0E1626' })
        if (-not $top) {
            $a.Lead.Stroke = B $(if ($a.Sel) { '#FFE28A' } else { '#7A6E7C93' })
            $a.Lead.StrokeThickness = $(if ($a.Sel) { 2 } else { 1 })
            if ($a.Dot.Width -gt 8 -and -not $a.Sel) { Set-DotSize $a 8 }
            if ($a.Sel) { Set-DotSize $a 12; $a.Dot.Fill = B '#FFE28A' } else { $a.Dot.Fill = B $a.DotCol }
        }
    }
}
function Set-DotSize {
    param($Asm, [double]$Size)
    $d = $Asm.Dot
    $cx = [Windows.Controls.Canvas]::GetLeft($d) + $d.Width / 2.0
    $cy = [Windows.Controls.Canvas]::GetTop($d) + $d.Height / 2.0
    $d.Width = $Size; $d.Height = $Size
    [Windows.Controls.Canvas]::SetLeft($d, $cx - $Size / 2.0)
    [Windows.Controls.Canvas]::SetTop($d, $cy - $Size / 2.0)
}

# Every squadron on the day's sheet, laid out and drawn.
function Add-SquadronPlaques {
    param($Canvas, $Fields, [double]$W, [double]$H, [int]$Mine, $Date,
          $OnSelect, [switch]$AlwaysName, [switch]$Activity)

    # ---- 1. bundle the fields that are one anchor at this scale --------
    $groups = @()
    foreach ($f in $Fields) {
        $into = $null
        foreach ($g in $groups) {
            foreach ($m in $g.Members) {
                if ([math]::Sqrt([math]::Pow($m.X - $f.X, 2) + [math]::Pow($m.Y - $f.Y, 2)) -le $PlaqueBundle) { $into = $g; break }
            }
            if ($into) { break }
        }
        if ($into) { $into.Members = @($into.Members) + @($f) }
        else { $groups += ,@{ Members = @($f) } }
    }

    # ---- 2. measure each one ------------------------------------------
    # A plaque beside its own field needs no name: the sheet prints one,
    # unless the field is in the packed quadrant where it does not. A
    # plaque out on a rail always needs one, because nothing else out
    # there says which field it belongs to. So measuring runs twice, once
    # before placement and again for whatever ends up docked.
    foreach ($g in $groups) {
        $g.Members = @($g.Members | Sort-Object @{ e = { $_.X } }, @{ e = { $_.Y } })
        foreach ($m in $g.Members) {
            $w0 = 0.0
            foreach ($sq0 in @($m.Sqns)) { $w0 += (Get-TileWidth $sq0) + 1.0 }
            $m.PW = $w0 + 1.0
            $m.Full = Format-FieldName "$($m.Base)"
            $m.Short = ''
            if ($Activity) {
                # how hard this station was being fought over, as the board
                # has always shown it
                $act = 'L'
                foreach ($q3 in $m.Sqns) { if ("$($q3.Act)" -eq 'H') { $act = 'H' } elseif ("$($q3.Act)" -eq 'M' -and $act -ne 'H') { $act = 'M' } }
                $pips = switch ($act) { 'H' { "$([char]0x25B2)$([char]0x25B2)$([char]0x25B2)" } 'M' { "$([char]0x25B2)$([char]0x25B2)" } default { "$([char]0x25B2)" } }
                $m.Short = $pips
                $m.Full = "$($m.Full)  $pips"
            }
            # Beside its own field a plaque need not repeat a name the
            # sheet already prints; on a rail, or where the sheet keeps
            # quiet, it must carry one.
            $m.Named = if ($AlwaysName) { $true } else { [bool]$MapUnnamed["$($m.Base)"] }
            $m.Label = if ($MapUnnamed["$($m.Base)"] -or -not $m.Short) { $m.Full } else { $m.Short }
            $m.NW = Measure-PlaqueName $m.Label
        }
        $g.AX = [double]$g.Members[0].X; $g.AY = [double]$g.Members[0].Y
        $g.Docked = $true
        Set-PlaqueSize $g
    }

    # ---- 3. what the placement has to keep clear of --------------------
    $obs = @()
    # Every field on the sheet is ground a plaque may not sit on, and so is
    # the name printed beside it.
    #
    # This used to skip anything whose key did not begin "RAF ", which was
    # a way of ignoring the RAF table's duplicate aliases - each of its
    # fields is stored under both "Biggin Hill" and "RAF Biggin Hill". The
    # German table has no such keys, so the obstacle list came out EMPTY
    # and the Gruppen plaques were laid straight over Cambrai, Epinoy and
    # Arras. Duplicates are skipped by position now, which works for both
    # sheets and depends on nothing being called anything in particular.
    $seenPos = @{}
    foreach ($pp in $MapStations.GetEnumerator()) {
        $nm = "$($pp.Key)"
        $fx = [double]$pp.Value[0] * $W; $fy = [double]$pp.Value[1] * $H
        if ($fx -lt 0 -or $fx -gt $W -or $fy -lt 0 -or $fy -gt $H) { continue }
        $key = '{0:0.0},{1:0.0}' -f $fx, $fy
        if ($seenPos.ContainsKey($key)) { continue }
        $seenPos[$key] = $true
        $obs += ,@(($fx - 11.0), ($fy - 11.0), ($fx + 11.0), ($fy + 11.0))
        # where the sheet still prints the field's name, that box is taken
        if (-not $MapUnnamed[$nm]) { $obs += ,@(($fx - 4.0), ($fy - 17.0), ($fx + 106.0), ($fy + 17.0)) }
    }

    # The margins belong to the rails. Without this a plaque placed beside
    # a field in the south-east sat exactly where a docked one was about
    # to land, and the two overlapped.
    $railW = 0.0
    foreach ($g in $groups) { if ($g.W -gt $railW) { $railW = [math]::Max($railW, $g.W) } }
    $railW = [math]::Min($railW + 24.0, 0.24 * $W)
    $obs += ,@(($W - $railW), 0.0, $W, $H)
    $obs += ,@(0.0, ($H - 52.0), $W, $H)

    # ---- 4. near the field where there is room -------------------------
    # Isolated fields claim their slot first, so the crowded ones fall
    # through to the rails, which is where they were going anyway.
    foreach ($g in $groups) {
        $n = 0
        foreach ($h2 in $groups) {
            if ($h2 -eq $g) { continue }
            if ([math]::Sqrt([math]::Pow($h2.AX - $g.AX, 2) + [math]::Pow($h2.AY - $g.AY, 2)) -le 120.0) { $n++ }
        }
        $g.Dens = $n
    }
    foreach ($g in @($groups | Sort-Object @{ e = { $_.Dens } }, @{ e = { $_.AX } })) {
        $gw = $g.W; $gh = $g.H
        # PowerShell's comma binds tighter than its arithmetic, so every
        # element of these tables has to be parenthesised or the list comes
        # out as one long subtraction.
        $west = @(
            ,@(($g.AX - 12.0 - $gw), ($g.AY - $gh / 2.0))
            ,@(($g.AX - 10.0 - $gw), ($g.AY + 20.0 - $gh / 2.0))
            ,@(($g.AX - 10.0 - $gw), ($g.AY - 20.0 - $gh / 2.0))
            ,@(($g.AX - $gw / 2.0), ($g.AY + 16.0))
            ,@(($g.AX - $gw / 2.0), ($g.AY - 16.0 - $gh))
            ,@(($g.AX + 102.0), ($g.AY - $gh / 2.0))
        )
        # near the western edge the map's own names run east, so go south
        if ($g.AX -lt 0.35 * $W) {
            $west = @($west[3], $west[1], $west[4], $west[2], $west[0], $west[5])
        }
        foreach ($c in $west) {
            $b = @($c[0], $c[1], ($c[0] + $gw), ($c[1] + $gh))
            if ($b[0] -lt 16 -or $b[1] -lt 16 -or $b[2] -gt $W - 16 -or $b[3] -gt $H - 16) { continue }
            if (-not (Test-BoxClear $b $obs)) { continue }
            $g.BX = $c[0]; $g.BY = $c[1]; $g.Docked = $false
            $obs += ,@(($b[0] - 12.0), ($b[1] - 12.0), ($b[2] + 12.0), ($b[3] + 12.0))
            break
        }
    }

    # ---- 5. the rest dock to the North Sea and the Channel -------------
    # Bundling exists so that three fields a dozen pixels apart do not try
    # to hold three plaques between them. Out on a rail there is room, and
    # a stack of three named rows is narrower and plainer than one wide
    # plaque, so a bundle that docks comes apart again.
    $dock = @()
    foreach ($g in @($groups | Where-Object { $_.Docked })) {
        if ($g.Members.Count -le 1) { $dock += ,$g; continue }
        $groups = @($groups | Where-Object { $_ -ne $g })
        foreach ($m in $g.Members) {
            $one = @{ Members = @($m); AX = [double]$m.X; AY = [double]$m.Y; Docked = $true }
            $groups += ,$one; $dock += ,$one
        }
    }
    if ($dock.Count) {
        foreach ($g in $dock) {
            foreach ($m in $g.Members) {
                $m.Named = $true; $m.Label = $m.Full; $m.NW = Measure-PlaqueName $m.Label
            }
            Set-PlaqueSize $g
        }
        $mx = 0.0; $my = 0.0
        foreach ($g in $dock) { $mx += $g.AX; $my += $g.AY }
        $mx = $mx / $dock.Count; $my = $my / $dock.Count
        foreach ($g in $dock) {
            # the x clause sends the rightmost low anchors east rather than
            # dragging them all the way across the Channel
            $g.Rail = if (($g.AY -le $my + 10.0) -or ($g.AX -ge $mx + 55.0)) { 'E' } else { 'S' }
        }
        # Ordering each rail by its anchor is the whole crossing defence:
        # with the slots monotone in the same axis, no two leaders can
        # cross, so there is nothing left to untangle afterwards.
        $railE = @($dock | Where-Object { $_.Rail -eq 'E' } | Sort-Object @{ e = { $_.AY } })
        $railS = @($dock | Where-Object { $_.Rail -eq 'S' } | Sort-Object @{ e = { $_.AX } })
        $eW = 0.0; foreach ($g in $railE) { if ($g.W -gt $eW) { $eW = $g.W } }
        $eX = $W - 24.0 - $eW
        $sY = $H - 18.0
        foreach ($g in $railS) { $sY = [math]::Min($sY, $H - 18.0 - $g.H) }

        # slide each slot toward its anchor, then push the run apart
        $p = @(); foreach ($g in $railE) { $p += ($g.AY - $g.H / 2.0) }
        for ($pass = 0; $pass -lt 3; $pass++) {
            for ($i = 1; $i -lt $railE.Count; $i++) {
                $min = $p[$i - 1] + $railE[$i - 1].H + 10.0
                if ($p[$i] -lt $min) { $p[$i] = $min }
            }
            for ($i = $railE.Count - 1; $i -ge 0; $i--) {
                $max = if ($i -eq $railE.Count - 1) { $H - 20.0 - $railE[$i].H } else { $p[$i + 1] - $railE[$i].H - 10.0 }
                if ($p[$i] -gt $max) { $p[$i] = $max }
            }
            if ($railE.Count -and $p[0] -lt 20.0) { $p[0] = 20.0 }
        }
        for ($i = 0; $i -lt $railE.Count; $i++) { $railE[$i].BX = $eX; $railE[$i].BY = $p[$i] }

        $q = @(); foreach ($g in $railS) { $q += ($g.AX - $g.W / 2.0) }
        for ($pass = 0; $pass -lt 3; $pass++) {
            for ($i = 1; $i -lt $railS.Count; $i++) {
                $min = $q[$i - 1] + $railS[$i - 1].W + 28.0
                if ($q[$i] -lt $min) { $q[$i] = $min }
            }
            for ($i = $railS.Count - 1; $i -ge 0; $i--) {
                $max = if ($i -eq $railS.Count - 1) { $W - 20.0 - $railS[$i].W } else { $q[$i + 1] - $railS[$i].W - 28.0 }
                if ($q[$i] -gt $max) { $q[$i] = $max }
            }
            if ($railS.Count -and $q[0] -lt 20.0) { $q[0] = 20.0 }
        }
        for ($i = 0; $i -lt $railS.Count; $i++) { $railS[$i].BX = $q[$i]; $railS[$i].BY = $sY }

        # a hairline behind each rail turns a row of blocks into a column
        if ($railE.Count -gt 1) {
            $r = New-Object Windows.Shapes.Line
            $r.X1 = $eX - 10.0; $r.X2 = $eX - 10.0; $r.Y1 = $p[0]; $r.Y2 = $p[$railE.Count - 1] + $railE[$railE.Count - 1].H
            $r.Stroke = B '#662C3A52'; $r.StrokeThickness = 1
            [void]$Canvas.Children.Add($r); [Windows.Controls.Panel]::SetZIndex($r, 2)
        }
        if ($railS.Count -gt 1) {
            $r = New-Object Windows.Shapes.Line
            $r.Y1 = $sY - 9.0; $r.Y2 = $sY - 9.0; $r.X1 = $q[0]; $r.X2 = $q[$railS.Count - 1] + $railS[$railS.Count - 1].W
            $r.Stroke = B '#662C3A52'; $r.StrokeThickness = 1
            [void]$Canvas.Children.Add($r); [Windows.Controls.Panel]::SetZIndex($r, 2)
        }
    }

    # ---- 6. draw ------------------------------------------------------
    $script:MapAssemblies = @()
    $script:MapTiles = @()
    foreach ($g in $groups) {
        $ox = [double]$g.BX
        foreach ($m in $g.Members) {
            $isMine = [bool](@($m.Sqns | Where-Object { [int]$_.Num -eq $Mine }).Count)
            $mx2 = $ox + ($m.OW - $m.PW) / 2.0
            $my2 = [double]$g.BY + $(if ($g.NameRow) { $PlaqueNameH } else { 0.0 })

            # the field's name, where the sheet no longer prints it
            $nameTb = $null
            if ($m.Named) {
                $nameTb = New-TB -Text $m.Label -Family $CondFam -Size 10.5 -Colour '#93A0B5'
                $nameTb.IsHitTestVisible = $false
                [Windows.Controls.Canvas]::SetLeft($nameTb, $ox); [Windows.Controls.Canvas]::SetTop($nameTb, [double]$g.BY - 1.0)
                [void]$Canvas.Children.Add($nameTb); [Windows.Controls.Panel]::SetZIndex($nameTb, 12)
            }

            # the plaque, and its squadron tiles
            $plaque = New-Object Windows.Controls.Border
            $plaque.Background = B '#EB0E1626'
            $plaque.BorderBrush = B $(if ($isMine) { '#FFE28A' } else { '#2C3A52' })
            $plaque.BorderThickness = '1'; $plaque.CornerRadius = '3'
            $plaque.Height = $PlaqueH; $plaque.Width = $m.PW
            $tiles = New-Object Windows.Controls.StackPanel; $tiles.Orientation = 'Horizontal'
            $plaque.Child = $tiles
            [Windows.Controls.Canvas]::SetLeft($plaque, $mx2); [Windows.Controls.Canvas]::SetTop($plaque, $my2)
            [void]$Canvas.Children.Add($plaque); [Windows.Controls.Panel]::SetZIndex($plaque, 10)

            # the dot on the field, and one straight leader out to the plaque
            $dot = New-Object Windows.Shapes.Ellipse
            $dot.Width = 8; $dot.Height = 8; $dot.StrokeThickness = 0
            $types = @($m.Sqns | ForEach-Object { if ("$($_.Type)" -match 'Spitfire') { 'S' } else { 'H' } } | Sort-Object -Unique)
            $dotCol = if ($isMine) { '#FFE28A' } elseif ($types.Count -gt 1) { '#E8EDF5' } elseif ($types[0] -eq 'S') { '#5FD0E8' } else { '#F5A83C' }
            $dot.Fill = B $dotCol
            [Windows.Controls.Canvas]::SetLeft($dot, [double]$m.X - 4.0); [Windows.Controls.Canvas]::SetTop($dot, [double]$m.Y - 4.0)
            [void]$Canvas.Children.Add($dot); [Windows.Controls.Panel]::SetZIndex($dot, 8)

            $bx1 = $mx2; $by1 = $my2; $bx2 = $mx2 + $m.PW; $by2 = $my2 + $PlaqueH
            $cx2 = ($bx1 + $bx2) / 2.0; $cy2 = ($by1 + $by2) / 2.0
            $dx = $cx2 - [double]$m.X; $dy = $cy2 - [double]$m.Y
            if ([math]::Abs($dy) -gt [math]::Abs($dx)) {
                $ex = [math]::Max($bx1 + 8.0, [math]::Min($bx2 - 8.0, [double]$m.X))
                $ey = if ($dy -gt 0) { $by1 } else { $by2 }
            } else {
                $ex = if ($dx -gt 0) { $bx1 } else { $bx2 }
                $ey = [math]::Max($by1 + 6.0, [math]::Min($by2 - 6.0, [double]$m.Y))
            }
            $len = [math]::Sqrt($dx * $dx + $dy * $dy)
            $sx2 = [double]$m.X; $sy2 = [double]$m.Y
            if ($len -gt 8.0) { $sx2 += 6.0 * $dx / $len; $sy2 += 6.0 * $dy / $len }
            $lead = New-Object Windows.Shapes.Line
            $lead.X1 = $sx2; $lead.Y1 = $sy2; $lead.X2 = $ex; $lead.Y2 = $ey
            $lead.Stroke = B '#7A6E7C93'; $lead.StrokeThickness = 1
            [void]$Canvas.Children.Add($lead); [Windows.Controls.Panel]::SetZIndex($lead, 5)

            $asm = @{ Plaque = $plaque; Lead = $lead; Dot = $dot; Name = $nameTb; DotCol = $dotCol; Mine = $isMine; Sel = $false }
            $script:MapAssemblies += ,$asm

            $n = 0
            foreach ($q2 in @($m.Sqns | Sort-Object { [int]$_.Num })) {
                if ($n -gt 0) {
                    $sep = New-Object Windows.Shapes.Rectangle
                    $sep.Width = 1; $sep.Fill = B '#2C3A52'
                    [void]$tiles.Children.Add($sep)
                }
                $n++
                $isSpit = ("$($q2.Type)" -match 'Spitfire')
                $mineTile = ([int]$q2.Num -eq $Mine)
                $tcol = if ($mineTile) { '#FFC24A' } elseif ($isSpit) { '#8FBEDA' } else { '#E0952F' }
                $tile = New-Object Windows.Controls.Border
                $tile.Width = (Get-TileWidth $q2); $tile.Height = 22; $tile.Cursor = 'Hand'
                $tile.Background = B '#00000000'
                $tile.BorderBrush = B $tcol; $tile.BorderThickness = '0,0,0,3'
                # A German Gruppe has no number to show, so an entry may
                # carry a Label. Num is still there and still unique, which
                # is what the sorting, the bundling and the "is this mine"
                # test all key on; only the words change.
                $lab = if ($q2.PSObject.Properties.Name -contains 'Label' -and "$($q2.Label)") { "$($q2.Label)" }
                       elseif ($q2 -is [System.Collections.IDictionary] -and $q2.Contains('Label')) { "$($q2.Label)" }
                       else { "$($q2.Num)" }
                $tb = New-TB -Text $lab -Family $CondFam -Size 11.5 -Colour $tcol -Bold
                $tb.IsHitTestVisible = $false; $tb.TextAlignment = 'Center'
                $tb.VerticalAlignment = 'Center'; $tb.HorizontalAlignment = 'Stretch'
                $tile.Child = $tb
                $tile.Tag = @{ Asm = $asm; Text = $tb; Colour = $tcol; Num = [int]$q2.Num; Label = $lab
                               Type = "$($q2.Type)"; Base = "$($m.Base)"; Mine = $mineTile; Date = $Date
                               Sqn = $q2; Sel = $false }
                if ($OnSelect) {
                    $script:MapTiles += ,$tile
                    $tile.Add_MouseLeftButtonUp({ param($sender, $e) & $script:SelectSq $sender.Tag.Sqn; $e.Handled = $true })
                }
                $tile.Add_MouseEnter({
                    param($sender, $e)
                    $t = $sender.Tag
                    if (-not $sender.ToolTip) {
                        $cardCtl = if ($script:Side -eq 'lw') {
                            New-GruppeCard (@(Get-LwGruppen) | Where-Object { "$($_.unit)" -eq "$($t.Label)" } | Select-Object -First 1) $t.Mine
                        } else {
                            New-SquadronCard -Num $t.Num -Type $t.Type -Base $t.Base -Mine $t.Mine -Date $t.Date
                        }
                        if ($cardCtl) { $sender.ToolTip = New-SquadronTip $cardCtl }
                        [Windows.Controls.ToolTipService]::SetInitialShowDelay($sender, 90)
                        [Windows.Controls.ToolTipService]::SetShowDuration($sender, 90000)
                        [Windows.Controls.ToolTipService]::SetBetweenShowDelay($sender, 0)
                    }
                    $hot = B '#FFE28A'
                    $sender.Background = B ('#30' + $t.Colour.Substring(1))
                    $t.Text.Foreground = $hot
                    $a = $t.Asm
                    Set-MapFocus $a
                    $a.Lead.Stroke = $hot; $a.Lead.StrokeThickness = 2
                    Set-DotSize $a 12; $a.Dot.Fill = $hot
                    Set-MapReadout @{ Title = $(if ($script:Side -eq 'lw') { "$($t.Label)" } else { "No. $($t.Num) Squadron" })
                                      Where = "$($t.Base)   $([char]0x2022)   $($t.Type)"
                                      Note  = 'Hold the pointer still for the squadron card.'
                                      Mine  = $t.Mine }
                })
                $tile.Add_MouseLeave({
                    param($sender, $e)
                    $t = $sender.Tag
                    $sender.Background = if ($t.Sel) { B '#33FFC24A' } else { B '#00000000' }
                    $t.Text.Foreground = if ($t.Sel) { B '#FFE28A' } else { B $t.Colour }
                    Set-MapFocus $null
                    Set-MapReadout $null
                })
                [void]$tiles.Children.Add($tile)
            }
            $ox += $m.OW + 10.0
        }
    }
}

function Show-Map {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'map'))
    $Pilot = Ensure-Squadron -Pilot $Pilot
    Set-Header $Pilot
    $sqnum = 92; if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { $sqnum = [int]$Pilot.sqn }
    # the same base rule as the dispersal, for every squadron
    $base = Get-SquadronBase -Sqn $sqnum -Date $script:CampaignDate -Pilot $Pilot
    if (-not $base) { $base = 'Fighter Command' }
    $eyebrow = if ($script:CampaignDate) { "FIGHTER COMMAND  $([char]0x2022)  $($script:CampaignDate.ToString('dddd d MMMM yyyy').ToUpper())" } else { 'FIGHTER COMMAND' }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow $eyebrow -Title "No. $sqnum Squadron at $base"))

    $onTable = [bool]$MapStations[$base]
    # Where every squadron in Fighter Command stood on this day, so the
    # table is the day's dispositions and not one lonely ring. Squadrons
    # resting in the north, or at a station off the western edge, are named
    # underneath instead.
    $others = @(); $offTable = @()
    foreach ($q in (Get-Squadrons)) {
        $qb = Get-SquadronBase -Sqn $q.Num -Date $script:CampaignDate -Pilot $null
        if (-not $qb) { continue }
        if ($qb -eq 'resting in the north') { continue }
        $qst = $MapStations[$qb]
        if ($qst) { $others += @{ Num=$q.Num; Type=$q.Type; Base=$qb; St=$qst } }
        else { $offTable += @{ Num=$q.Num; Type=$q.Type; Base=$qb } }
    }
    # your own squadron, if the order of battle did not already list it
    if ($onTable -and -not ($others | Where-Object { $_.Num -eq $sqnum })) {
        $others += @{ Num=$sqnum; Type=$(if ($Pilot.actype) { "$($Pilot.actype)" } else { '' }); Base=$base; St=$MapStations[$base] }
    }
    $leadTxt = if ($onTable) { "No. $(Get-GroupForBase $base) Group, Fighter Command. Every squadron in the line is a dot on its own field with its number beside it, gold for yours, blue for Spitfires and amber for Hurricanes." }
               else { "No. $(Get-GroupForBase $base) Group, Fighter Command. $base lies beyond the western edge of this table, so your squadron is named below it. Every other squadron in the line is a dot on its own field with its number beside it, blue for Spitfires and amber for Hurricanes." }
    $secNow = Get-SectorText $base
    if ($secNow) { $leadTxt += "  Your station is the $secNow." }
    $leadTxt += '  A ringed field is a sector station, the one holding the operations room that fought that sector.  Point at a squadron number for its card: the aeroplane, the station, what Fighter Command made of it, and the men on its strength that morning.  Roll the wheel to zoom, drag to move the sheet, double-click to set it back.'
    $lead = New-TB -Text $leadTxt -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Wrap
    $lead.Margin = '0,0,0,12'; $lead.MaxWidth = 1180
    [void]$script:Stage.Children.Add($lead)
    # what the pointer is over, read out under the table
    # a three-line card under the table: who, where, and what Fighter
    # Command thought of them
    $script:MapReadout = New-Object Windows.Controls.Border
    $script:MapReadout.Background = Res 'Panel'; $script:MapReadout.BorderBrush = Res 'Rule'
    $script:MapReadout.BorderThickness = '1'; $script:MapReadout.CornerRadius = '3'
    $script:MapReadout.Padding = '16,10'; $script:MapReadout.Margin = '0,12,0,0'
    $script:MapReadout.HorizontalAlignment = 'Left'; $script:MapReadout.MinWidth = 560
    $rd = New-Object Windows.Controls.StackPanel
    $script:MapTitle = New-TB -Text ' ' -Family $SerifFam -Size 17 -Colour '#E9E3D4'
    $script:MapWhere = New-TB -Text ' ' -Family $CondFam -Size 13 -Colour '#9FB0B8'
    $script:MapWhere.Margin = '0,3,0,0'
    $script:MapNote  = New-TB -Text ' ' -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Wrap
    $script:MapNote.Margin = '0,3,0,0'; $script:MapNote.MaxWidth = 780
    [void]$rd.Children.Add($script:MapTitle)
    [void]$rd.Children.Add($script:MapWhere)
    [void]$rd.Children.Add($script:MapNote)
    $script:MapReadout.Child = $rd

    $W = 1180.0; $H = [math]::Round($W * 1600.0 / 2560.0)
    $mapWrap = New-Object Windows.Controls.Border
    $mapWrap.Width = $W + 2; $mapWrap.Height = $H + 2; $mapWrap.HorizontalAlignment = 'Left'
    $mapWrap.Background = B '#0B141B'; $mapWrap.BorderBrush = Res 'Rule'; $mapWrap.BorderThickness = '1'; $mapWrap.CornerRadius = '3'
    $grid = New-Object Windows.Controls.Grid
    $imgPath = Join-Path (Join-Path $ModDir 'map') 'sector-map.jpg'
    $bg = New-Object Windows.Controls.Image
    $bmp = Load-Image -Path $imgPath -DecodeWidth 2560
    if ($bmp) { $bg.Source = $bmp }
    $bg.Stretch = 'Uniform'; $bg.Width = $W; $bg.Height = $H
    [void]$grid.Children.Add($bg)
    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $W; $cv.Height = $H; $cv.ClipToBounds = $true
    [void]$grid.Children.Add($cv)
    $mapWrap.Child = $grid

    # One plaque per field, carrying the squadrons standing on it that
    # morning. Where the field has no room the plaque docks to a margin
    # rail and a straight leader runs back to the dot.
    $byField = @{}
    foreach ($o in $others) {
        $k = "$($o.Base)"
        if (-not $byField.ContainsKey($k)) {
            $byField[$k] = @{ Base = $k; X = [double]$o.St[0] * $W; Y = [double]$o.St[1] * $H; Sqns = @() }
        }
        $byField[$k].Sqns = @($byField[$k].Sqns) + @($o)
    }
    $fields = @($byField.Values | Sort-Object @{ e = { $_.X } }, @{ e = { $_.Y } })
    Add-SquadronPlaques -Canvas $cv -Fields $fields -W $W -H $H -Mine $sqnum -Date $script:CampaignDate

    # an invisible patch over every station, so hovering a field tells you
    # its name, its group and which squadrons are standing on it today
    $atField = @{}
    foreach ($o in $others) { $atField[$o.Base] = @($atField[$o.Base]) + @($o.Num) }
    if ($onTable) { $atField[$base] = @($atField[$base]) + @($sqnum) }
    foreach ($pp in $MapStations.GetEnumerator()) {
        $nm = "$($pp.Key)"
        if ($nm -notmatch '^RAF ') { continue }           # each field is listed twice
        $fx = [double]$pp.Value[0] * $W; $fy = [double]$pp.Value[1] * $H
        if ($fx -lt 0 -or $fx -gt $W -or $fy -lt 0 -or $fy -gt $H) { continue }
        $hit = New-Object Windows.Shapes.Ellipse
        $hit.Width = 22; $hit.Height = 22; $hit.Fill = B '#01000000'
        [Windows.Controls.Canvas]::SetLeft($hit, $fx - 11); [Windows.Controls.Canvas]::SetTop($hit, $fy - 11)
        $here = @($atField[$nm] | Where-Object { $_ } | Sort-Object)
        $who = if ($here.Count -eq 0) { 'no squadron here today' }
               elseif ($here.Count -eq 1) { "No. $($here[0]) Squadron" }
               else { 'Nos. ' + (($here | ForEach-Object { "$_" }) -join ', ') + ' Squadrons' }
        $secTxt = Get-SectorText $nm
        $hit.Tag = @{ Title = $nm
                      Where = "No. $(Get-GroupForBase $nm) Group" + $(if ($secTxt) { "   $([char]0x2022)   $secTxt" } else { '' })
                      Note  = $who; Mine = $false }
        $hit.ToolTip = "$nm  $([char]0x2022)  $who"
        $hit.Add_MouseEnter({ param($sender,$e) if ($script:MapTitle -and $script:MapTitle.Text.Trim() -eq '') { Set-MapReadout $sender.Tag } })
        $hit.Add_MouseLeave({ param($sender,$e) Set-MapReadout $null })
        [void]$cv.Children.Insert(0, $hit)
    }
    Enable-MapZoom -Frame $mapWrap -Content $grid
    [void]$script:Stage.Children.Add($mapWrap)
    [void]$script:Stage.Children.Add($script:MapReadout)

    # Your own squadron, when its station is off the table
    if (-not $onTable) {
        $chip = New-Object Windows.Controls.Border
        $chip.Padding = '14,9'; $chip.Margin = '0,14,0,0'; $chip.CornerRadius = '3'; $chip.HorizontalAlignment = 'Left'
        $chip.Background = B '#101B22'; $chip.BorderBrush = B '#FFE28A'; $chip.BorderThickness = '1.5'
        $chip.Child = (New-TB -Text "No. $sqnum SQUADRON  $([char]0x2022)  $($base.ToUpper())  $([char]0x2022)  BEYOND THIS TABLE" -Family $CondFam -Size 12.5 -Colour '#FFE28A' -Bold)
        [void]$script:Stage.Children.Add($chip)
    }
    # and the other squadrons whose stations lie off it
    $offOthers = @($offTable | Where-Object { $_.Num -ne $sqnum })
    if ($offOthers.Count -gt 0) {
        $oh = New-TB -Text 'ALSO IN THE LINE, BEYOND THIS TABLE' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold
        $oh.Margin = '0,18,0,8'
        [void]$script:Stage.Children.Add($oh)
        $wrap = New-Object Windows.Controls.WrapPanel
        $wrap.MaxWidth = 1080
        foreach ($o in ($offOthers | Sort-Object { "$($_.Base)" }, { [int]$_.Num })) {
            $c2 = New-Object Windows.Controls.Border
            $c2.Padding = '10,6'; $c2.Margin = '0,0,8,8'; $c2.CornerRadius = '3'
            $c2.Background = B '#101B22'; $c2.BorderBrush = Res 'Rule'; $c2.BorderThickness = '1'
            $col = if ("$($o.Type)" -match 'Spitfire') { '#9FE0F0' } else { '#F8C87E' }
            $c2.Child = (New-TB -Text "No. $($o.Num)  $([char]0x2022)  $($o.Base)" -Family $CondFam -Size 11.5 -Colour $col)
            [void]$wrap.Children.Add($c2)
        }
        [void]$script:Stage.Children.Add($wrap)
    }
}
# =====================================================================
#  The Morning Bulletin: the day's paper, from the real 1940 cables
# =====================================================================
$PaperPath = Join-Path $ModDir 'paper.json'
function Get-Paper {
    # The comma keeps the array intact through the function return, so the
    # caller gets every entry, not a single wrapped object whose members
    # then enumerate into one mashed string.
    $out = @()
    if (Test-Path $PaperPath) { try { $out = @(Get-Content $PaperPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $out = @() } }
    ,$out
}
function Format-ShortDate {
    param([string]$s)
    try { return ([datetime]::ParseExact($s,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)).ToString('d MMM') } catch { return $s }
}
# A folded newspaper, drawn from rectangles rather than shipped as a PNG:
# it has to sit on the dispersal's dark ground at one size only, and four
# rectangles beat another file to keep in step with the badge folder.
# The page uses the same cream as the bulletin itself, so the strip and
# the screen it leads to are obviously the same thing.
function New-NewspaperIcon {
    $c = New-Object Windows.Controls.Canvas
    # sized against three lines of text beside it: at 30 wide it read as a
    # bullet point rather than a masthead
    $c.Width = 40; $c.Height = 35
    function Add-Rect {
        param($Canvas, [double]$X, [double]$Y, [double]$W, [double]$H, [string]$Fill)
        $r = New-Object Windows.Shapes.Rectangle
        $r.Width = $W; $r.Height = $H; $r.Fill = B $Fill
        [Windows.Controls.Canvas]::SetLeft($r, $X); [Windows.Controls.Canvas]::SetTop($r, $Y)
        [void]$Canvas.Children.Add($r)
    }
    # the sheet behind, so it reads as a folded paper rather than a card
    Add-Rect $c 9.5 0 29.5 29.5 '#8A6D34'
    Add-Rect $c 1 5.5 29.5 28 '#E9E0CA'
    # masthead, photograph and three lines of column
    Add-Rect $c 5 9.5 21.5 3.4 '#2A2418'
    Add-Rect $c 5 16 9.4 10.7 '#8C8474'
    Add-Rect $c 17.4 16 9.4 2.2 '#6B6250'
    Add-Rect $c 17.4 20.3 9.4 2.2 '#6B6250'
    Add-Rect $c 17.4 24.6 9.4 2.2 '#6B6250'
    $c
}
function New-Rule {
    param([string]$Colour = '#221E15', [double]$H = 1.5)
    $r = New-Object Windows.Controls.Border
    $r.Height = $H; $r.Background = B $Colour; $r.Margin = '0,10,0,10'
    $r
}
# Which front page belongs to the campaign's current date, as an index into
# the entries. Lifted out of Show-Paper so the dispersal can ask the same
# question without drawing anything: two answers to "what is today's paper"
# would eventually disagree, and the unread flag would then be lying.
function Get-LeadBulletinIndex {
    param($Entries, $Date)
    $leadIdx = -1
    if ($Date) {
        for ($k = 0; $k -lt $Entries.Count; $k++) {
            $ed = $null
            try { $ed = [datetime]::ParseExact($Entries[$k].date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture) } catch { }
            if ($ed -and ($ed -le $Date)) { $leadIdx = $k }
        }
    }
    # a campaign day before the first paper reads the first paper; no
    # campaign at all shows the latest front page
    if (($leadIdx -lt 0) -and $Entries.Count) { $leadIdx = if ($Date) { 0 } else { $Entries.Count - 1 } }
    $leadIdx
}
# The entries as Show-Paper uses them, unwrapped the same way.
function Get-PaperEntries {
    $entries = @(Get-Paper)
    while ($entries.Count -eq 1 -and ($entries[0] -is [System.Array])) { $entries = $entries[0] }
    ,$entries
}
# Today's front page, or $null. Used by the dispersal to say there is
# something new to read.
function Get-UnreadBulletin {
    param($Pilot)
    try {
        $entries = Get-PaperEntries
        if (-not $entries.Count) { return $null }
        $i = Get-LeadBulletinIndex -Entries $entries -Date $script:CampaignDate
        if ($i -lt 0) { return $null }
        $lead = $entries[$i]
        $seen = $null
        if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'paperRead')) { $seen = "$($Pilot.paperRead)" }
        if ($seen -and ($seen -eq "$($lead.date)")) { return $null }
        return $lead
    } catch { }
    $null
}
# Remember the front page he has actually been shown. Written when the
# bulletin is opened, not when it is generated, so the flag tracks reading
# rather than the passing of campaign days.
function Set-BulletinRead {
    param($Pilot, [string]$Date)
    if (-not $Pilot -or -not $Date) { return }
    try {
        if ($Pilot.PSObject.Properties.Name -contains 'paperRead') { $Pilot.paperRead = $Date }
        else { $Pilot | Add-Member -NotePropertyName paperRead -NotePropertyValue $Date -Force }
        Save-Pilot $Pilot
    } catch { }
}
function Show-Paper {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'paper'))
    $Pilot = Ensure-Squadron -Pilot $Pilot
    $sqnum = 92; if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { $sqnum = [int]$Pilot.sqn }

    # ConvertFrom-Json plus the pipeline can nest the entry array several
    # layers deep (a single flatten once shipped broken); Get-PaperEntries
    # peels it, and the dispersal reads it through the same door.
    $entries = Get-PaperEntries
    $leadIdx = Get-LeadBulletinIndex -Entries $entries -Date $script:CampaignDate
    # opening it counts as reading it, so the dispersal stops flagging it
    if ($leadIdx -ge 0) { Set-BulletinRead -Pilot $Pilot -Date "$($entries[$leadIdx].date)" }

    $paper = New-Object Windows.Controls.Border
    $paper.Background = B '#E9E0CA'; $paper.CornerRadius = '2'; $paper.Padding = '40,26,40,34'
    $paper.MaxWidth = 940; $paper.HorizontalAlignment = 'Left'
    $paper.BorderBrush = B '#2A2418'; $paper.BorderThickness = '1'
    $col = New-Object Windows.Controls.StackPanel

    # ---- masthead ----
    [void]$col.Children.Add((New-Rule '#1A1712' 3))
    $mh = New-TB -Text 'The Morning Bulletin' -Family "Old English Text MT, Blackadder ITC, Georgia, 'Times New Roman', serif" -Size 50 -Colour '#141109'
    $mh.HorizontalAlignment = 'Center'; $mh.Margin = '0,6,0,2'
    [void]$col.Children.Add($mh)
    [void]$col.Children.Add((New-Rule '#1A1712' 1))

    $base = Get-SquadronBase -Sqn $sqnum -Date $script:CampaignDate -Pilot $Pilot
    $centTxt = if ($base) { $base.ToUpper() } else { 'FIGHTER COMMAND' }
    $dstr = if ($script:CampaignDate) { $script:CampaignDate.ToString('dddd, d MMMM yyyy').ToUpper() } else { 'THE BATTLE OF BRITAIN, 1940' }
    $dl = New-Object Windows.Controls.Grid; $dl.Margin = '0,5,0,5'
    foreach ($w in @('*','*','*')) { $cd=New-Object Windows.Controls.ColumnDefinition; $cd.Width=New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)); [void]$dl.ColumnDefinitions.Add($cd) }
    $dLeft  = New-TB -Text "No. $sqnum Squadron R.A.F." -Family $CondFam -Size 11.5 -Colour '#4A4436' -Bold; $dLeft.VerticalAlignment='Center'
    $dCent  = New-TB -Text $centTxt -Family $CondFam -Size 11.5 -Colour '#4A4436' -Bold; $dCent.HorizontalAlignment='Center'; $dCent.VerticalAlignment='Center'
    $dRight = New-TB -Text $dstr -Family $CondFam -Size 11.5 -Colour '#4A4436' -Bold; $dRight.HorizontalAlignment='Right'; $dRight.VerticalAlignment='Center'
    [Windows.Controls.Grid]::SetColumn($dLeft,0); [Windows.Controls.Grid]::SetColumn($dCent,1); [Windows.Controls.Grid]::SetColumn($dRight,2)
    [void]$dl.Children.Add($dLeft); [void]$dl.Children.Add($dCent); [void]$dl.Children.Add($dRight)
    [void]$col.Children.Add($dl)
    [void]$col.Children.Add((New-Rule '#1A1712' 2.5))

    # ---- two columns: lead story | latest signals ----
    $bodyG = New-Object Windows.Controls.Grid; $bodyG.Margin = '0,12,0,0'
    $g0=New-Object Windows.Controls.ColumnDefinition; $g0.Width=New-Object Windows.GridLength(2,([Windows.GridUnitType]::Star))
    $g1=New-Object Windows.Controls.ColumnDefinition; $g1.Width=New-Object Windows.GridLength(26)
    $g2=New-Object Windows.Controls.ColumnDefinition; $g2.Width=New-Object Windows.GridLength(1.15,([Windows.GridUnitType]::Star))
    [void]$bodyG.ColumnDefinitions.Add($g0); [void]$bodyG.ColumnDefinitions.Add($g1); [void]$bodyG.ColumnDefinitions.Add($g2)

    $lc = New-Object Windows.Controls.StackPanel
    $lead = $null
    if ($leadIdx -ge 0 -and $entries.Count) {
        $lead = $entries[$leadIdx]
        $hl = New-TB -Text ([string]$lead.headline) -Family 'Georgia, Cambria, serif' -Size 31 -Colour '#120F08' -Bold -Wrap
        $hl.LineHeight = 34
        [void]$lc.Children.Add($hl)
        [void]$lc.Children.Add((New-Rule '#7A5E2E' 1))
        $bd = New-TB -Text ([string]$lead.body) -Family 'Georgia, Cambria, serif' -Size 15 -Colour '#2A2620' -Wrap
        $bd.LineHeight = 24; $bd.Margin = '0,8,0,0'; $bd.TextAlignment = 'Justify'
        [void]$lc.Children.Add($bd)
        # credit the real paper the story came from, as the cables did
        if (($lead.PSObject.Properties.Name -contains 'paper') -and $lead.paper) {
            $src = New-TB -Text ("$([char]0x2014) $($lead.paper), from the London cables") -Family 'Georgia, Cambria, serif' -Size 12.5 -Colour '#6B6250'
            $src.Margin = '0,10,0,0'; $src.FontStyle = 'Italic'
            [void]$lc.Children.Add($src)
        }
    }
    [Windows.Controls.Grid]::SetColumn($lc,0); [void]$bodyG.Children.Add($lc)

    $vr = New-Object Windows.Controls.Border; $vr.Width=1; $vr.Background=B '#3A3324'; $vr.HorizontalAlignment='Center'
    [Windows.Controls.Grid]::SetColumn($vr,1); [void]$bodyG.Children.Add($vr)

    $sc = New-Object Windows.Controls.StackPanel
    [void]$sc.Children.Add((New-TB -Text 'LATEST SIGNALS' -Family $CondFam -Size 12 -Colour '#7A5E2E' -Bold))
    [void]$sc.Children.Add((New-Rule '#7A5E2E' 1))
    $shown = 0
    # the day's own wire items when the entry carries them...
    if ($lead -and ($lead.PSObject.Properties.Name -contains 'signals') -and $lead.signals) {
        foreach ($sg in @($lead.signals)) {
            if ($shown -ge 6) { break }
            $item = New-TB -Text ([string]$sg) -Family 'Georgia, serif' -Size 14 -Colour '#1C1810' -Bold -Wrap
            $item.Margin = '0,0,0,13'; $item.LineHeight = 17
            [void]$sc.Children.Add($item)
            $shown++
        }
    }
    # ...otherwise the last few days' headlines, as before
    for ($k = $leadIdx - 1; ($k -ge 0) -and ($shown -lt 6); $k--) {
        $e = $entries[$k]
        $item = New-Object Windows.Controls.StackPanel; $item.Margin = '0,0,0,13'
        $dt = New-TB -Text (Format-ShortDate ([string]$e.date)) -Family $CondFam -Size 11 -Colour '#7A5E2E' -Bold
        [void]$item.Children.Add($dt)
        $hh = New-TB -Text ([string]$e.headline) -Family 'Georgia, serif' -Size 14 -Colour '#1C1810' -Bold -Wrap
        $hh.Margin = '0,1,0,0'; $hh.LineHeight = 17
        [void]$item.Children.Add($hh)
        [void]$sc.Children.Add($item)
        $shown++
    }
    if ($shown -eq 0) { [void]$sc.Children.Add((New-TB -Text 'Quiet on the wire.' -Family 'Georgia, serif' -Size 13 -Colour '#4A4436')) }
    [Windows.Controls.Grid]::SetColumn($sc,2); [void]$bodyG.Children.Add($sc)

    [void]$col.Children.Add($bodyG)
    [void]$col.Children.Add((New-Rule '#1A1712' 2))
    $paper.Child = $col
    [void]$script:Stage.Children.Add($paper)
}
# =====================================================================
#  Postings: choose your squadron on the plotting map
# =====================================================================
# =====================================================================
#  THE LUFTWAFFE SIDE
#
#  The order of battle is the game's own, out of English\TEXT\LW_OOB.htm
#  and extracted by dev\build_lw_oob.py: 66 Gruppen over Luftflotte 2 and
#  3, of which 32 are fighter units and those are the ones a man can be
#  posted to. The rest fly bombers, which is a crew and a different sort
#  of career, and is not built.
# =====================================================================
$LwOobPath = Join-Path (Join-Path $ModDir 'lw') 'oob.json'
function Get-LwGruppen {
    if ($null -ne $script:LwList) { return $script:LwList }
    $out = @()
    if (Test-Path $LwOobPath) {
        try {
            $all = @(Get-Content $LwOobPath -Raw -Encoding UTF8 | ConvertFrom-Json)
            while ($all.Count -eq 1 -and ($all[0] -is [System.Array])) { $all = $all[0] }
            $out = @($all | Where-Object { $_.fighter })
        } catch { }
    }
    $script:LwList = $out
    $out
}
# A Gruppe is on the Kanalfront from the day it was activated. Before that
# it is not there to be posted to, which is the German equivalent of the
# RAF board's "resting in the north".
function Test-GruppeInLine {
    param($G, $Date)
    if (-not $Date -or -not $G.activation) { return $true }
    try { return ([datetime]::ParseExact("$($G.activation)",'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture) -le $Date) } catch { }
    $true
}
function Format-LwDate {
    param([string]$s)
    try { return ([datetime]::ParseExact($s,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)).ToString('d MMMM') } catch { return $s }
}
# How hard a Gruppe was worked, in the same three-arrow shorthand the RAF
# board uses for its sectors. Luftflotte 2 flew from the Pas de Calais
# against London and the south east, which is where the battle was.
function Get-LwActivity { param($G) if ([int]$G.luftflotte -eq 2) { 3 } else { 2 } }

# The Gruppe's own aircraft. Forty side views arrived, one per Gruppe of
# each fighter Geschwader, named exactly as the Room names a unit's
# roster file - I_JG26 for I./JG 26 - so the lookup is the unit's own key
# and nothing has to be mapped by hand.
#
# The Zerstoerer Gruppen fly Bf 110s and there is no 110 art, so they get
# NOTHING rather than a 109 with somebody else's emblem on it.
# Whether the Gruppe has a profile painted in ITS OWN markings, or is
# falling back to the plain factory scheme. It matters because the unit
# profiles already carry their Geschwader's badge: II./JG 26's aeroplane
# has the Schlageter S on it before the Room draws anything, and drawing
# ours on top puts two of them on one cowling.
# WHICH Bf 110 PROFILE, and it is not a lookup by unit.
#
# The 109 profiles are named for units, so a Gruppe's aeroplane is its own
# key and there is nothing to work out. The twelve 110 profiles are named
# for the game's BASE SKINS, and Me110_MainSkin.ms says which unit flies
# which on which dates - so a Zerstoerer's aeroplane is chosen the way the
# game chooses it, by unit, Staffel and the campaign date.
#
# skins110.json is that file parsed, by dev/build_lw_110_skins.py. Its
# rules are in FILE ORDER and the first that matches wins, because the
# game's conditions overlap and that is how MultiSkin reads them.
$Skins110Path = Join-Path (Join-Path $ModDir 'lw') 'skins110.json'
function Get-Skins110 {
    if ($null -ne $script:Skins110) { return $script:Skins110 }
    $m = $null
    if (Test-Path $Skins110Path) {
        try { $m = Get-Content $Skins110Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    $script:Skins110 = $m
    $m
}
# The Staffel's slot in its Gruppe, 1 to 9, which is what the game's rules
# key on. A man's staffel is already stored as 1-15 by Invoke-GruppeSubmit
# ((gruppe index x 3) + 1..3), so V./LG 1 lands on 13-15 and folds back to
# the 7-8-9 slot, which is exactly what the game does with it.
function Get-StaffelSlot {
    param($Staffel)
    $n = [int]$Staffel
    if ($n -lt 1) { return 1 }
    (($n - 1) % 9) + 1
}
function Get-Profile110 {
    param($G, $Pilot, $Date)
    $m = Get-Skins110
    if (-not $m) { return $null }
    $slot = Get-StaffelSlot $(if ($Pilot) { $Pilot.staffel } else { 1 })
    $key = "$($G.unit)|$slot"
    $rules = @()
    if ($m.by_unit_staffel.PSObject.Properties.Name -contains $key) { $rules += @($m.by_unit_staffel.$key) }
    if ($m.by_unit_staffel.PSObject.Properties.Name -contains '*')   { $rules += @($m.by_unit_staffel.'*') }
    $d = $Date
    foreach ($r in ($rules | Sort-Object { [int]$_.order })) {
        $ok = $true
        if ($d) {
            if ("$($r.from)") { try { if ($d -lt [datetime]::ParseExact("$($r.from)",'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)) { $ok = $false } } catch { } }
            if ($ok -and "$($r.to)") { try { if ($d -ge [datetime]::ParseExact("$($r.to)",'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)) { $ok = $false } } catch { } }
        }
        if (-not $ok) { continue }
        $f = Join-Path $script:AircraftDir "$($r.skin)"
        if (Test-Path $f) { return $f }
    }
    $f = Join-Path $script:AircraftDir "$($m.default)"
    if (Test-Path $f) { return $f }
    $null
}
function Test-GruppeOwnProfile {
    param($G)
    if (-not $G) { return $false }
    # A 110's profile is a base SCHEME rather than a unit's own markings,
    # so it never carries the Geschwader badge the way a 109 profile does
    # and the Room must draw one.
    if ("$($G.type)" -match '110') { return $false }
    if ("$($G.type)" -notmatch '109') { return $false }
    $key = ("$($G.unit)" -replace '\.','' -replace '/','_' -replace ' ','')
    Test-Path (Join-Path $script:AircraftDir ($key + '.png'))
}
function Get-GruppeAircraftPath {
    param($G, $Pilot)
    if (-not $G) { return $null }
    if ("$($G.type)" -match '110') { return (Get-Profile110 -G $G -Pilot $Pilot -Date $script:CampaignDate) }
    if ("$($G.type)" -notmatch '109') { return $null }
    $key = ("$($G.unit)" -replace '\.','' -replace '/','_' -replace ' ','')
    $f = Join-Path $script:AircraftDir ($key + '.png')
    if (Test-Path $f) { return $f }
    # a Gruppe with no profile of its own gets the plain scheme
    $f = Join-Path $script:AircraftDir 'RLM70_71.png'
    if (Test-Path $f) { return $f }
    $null
}
# The card that comes up under the pointer on the plotting table, the
# same idea as Fighter Command's: which Gruppe, what it flies, where it
# stands and how the campaign rates it.
function New-GruppeCard {
    param($G, [bool]$Mine = $false)
    if (-not $G) { return $null }
    $card = New-Object Windows.Controls.Border
    $card.Background = B '#F20B141B'; $card.BorderBrush = B $(if ($Mine) { '#FFE28A' } else { '#2C3A52' })
    $card.BorderThickness = '1'; $card.CornerRadius = '3'; $card.Padding = '0'; $card.MaxWidth = 460
    $col = New-Object Windows.Controls.StackPanel

    $head = New-Object Windows.Controls.Border
    $head.Background = B '#14202B'; $head.Padding = '16,12,16,11'
    $hrow = New-Object Windows.Controls.StackPanel; $hrow.Orientation = 'Horizontal'
    # no pilot here: the hover card on the postings board is about the
    # Gruppe, not about a man, so a 110 falls to its 1. Staffel scheme
    $ap = Get-GruppeAircraftPath -G $G
    if ($ap) {
        $sil = Load-Image -Path $ap -DecodeWidth 340
        if ($sil) {
            $im = New-Object Windows.Controls.Image
            $im.Source = $sil; $im.Width = 130; $im.Stretch = 'Uniform'
            $im.Opacity = 0.92; $im.Margin = '0,0,14,0'; $im.VerticalAlignment = 'Center'
            [void]$hrow.Children.Add($im)
        }
    }
    $hc = New-Object Windows.Controls.StackPanel; $hc.VerticalAlignment = 'Center'
    [void]$hc.Children.Add((New-TB -Text "$($G.unit)" -Family $SerifFam -Size 19 -Colour $(if ($Mine) { '#FFE28A' } else { '#E9E3D4' })))
    [void]$hc.Children.Add((New-TB -Text "$($G.type)   $([char]0x2022)   Luftflotte $($G.luftflotte)" -Family $CondFam -Size 12.5 -Colour '#F8C87E'))
    [void]$hrow.Children.Add($hc)
    $head.Child = $hrow
    [void]$col.Children.Add($head)

    $body = New-Object Windows.Controls.StackPanel; $body.Margin = '16,12,16,14'
    $t = "At $($G.field) since $(Format-LwDate "$($G.activation)"). The campaign rates it " +
         "$("$($G.skill)".ToLower()) with $("$($G.fatigue)".ToLower()) fatigue."
    $tb = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#9FB0B8' -Text $t
    $tb.MaxWidth = 420
    [void]$body.Children.Add($tb)
    # what it has done in this campaign, if the save knows the unit
    $rec = Get-GruppeRecord $G.sqidx
    if ($rec) {
        $r2 = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Text (
            "In this campaign: $($rec.Launched) sorties, $($rec.AcLost) aircraft and " +
            "$($rec.PilotsLost) pilots lost, $($rec.Total) claims.")
        $r2.Margin = '0,8,0,0'; $r2.MaxWidth = 420
        [void]$body.Children.Add($r2)
    }
    $col.Children.Add($body) | Out-Null
    $card.Child = $col
    $card
}

function Show-GruppeSelect {
    if (-not $script:SelPeriod) { $script:SelPeriod = 'P1' }
    $script:Stage.Children.Clear()
    Show-ChromeButtons $false
    Set-ChromeAction -Text 'REPORT TO THIS GRUPPE' -Enabled ([bool]$script:SelSq) -OnClick { if ($script:SelSq) { Show-GruppeCreate } }
    $h = C 'HdrSquadron'; if ($h) { $h.Text = 'Jagdwaffe' }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "LUFTWAFFE  $([char]0x2022)  LUFTFLOTTEN 2 UND 3" }
    if (Get-Pilot) { Set-ChromeBack 'BACK TO THE READY ROOM' { Show-Tab 'dispersal' } }
    else { Set-ChromeBack -Text '' }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'THE CHANNEL FRONT' -Title 'The fighter Gruppen'))

    $segRow = New-Object Windows.Controls.StackPanel; $segRow.Orientation = 'Horizontal'; $segRow.Margin = '0,-10,0,10'
    foreach ($per in $Periods) {
        $seg = New-Object Windows.Controls.Border
        $seg.Padding = '14,8'; $seg.Margin = '0,0,10,0'; $seg.CornerRadius = '3'; $seg.Cursor = 'Hand'; $seg.Tag = $per.Id
        $active = ($per.Id -eq $script:SelPeriod)
        $seg.Background = if ($active) { B '#213540' } else { B '#101B22' }
        $seg.BorderThickness = '0,0,0,2'
        $seg.BorderBrush = if ($active) { Res 'Brass' } else { B '#101B22' }
        $seg.Child = (New-TB -Text $per.Label -Family $CondFam -Size 12.5 -Colour $(if ($active) { '#E9E3D4' } else { '#6F828C' }) -Bold)
        $seg.Add_MouseLeftButtonUp({ param($sender,$e) $script:SelPeriod = "$($sender.Tag)"; Show-GruppeSelect })
        [void]$segRow.Children.Add($seg)
    }
    [void]$script:Stage.Children.Add($segRow)

    $perDef = $Periods | Where-Object { $_.Id -eq $script:SelPeriod } | Select-Object -First 1
    $pd = $null; try { $pd = [datetime]::ParseExact($perDef.Key,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture) } catch { }

    $all = @(Get-LwGruppen)
    $inLine = @($all | Where-Object { Test-GruppeInLine $_ $pd })
    $lead = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Text (
        "The order of battle for $($perDef.Desc), taken from the game's own. " +
        "$($inLine.Count) of the $($all.Count) fighter Gruppen are on the Kanalfront by this date; " +
        'the rest have not been moved up yet. Luftflotte 2 flew from the Pas de Calais against London ' +
        'and the south east, Luftflotte 3 from Normandy and Brittany against the west. ' +
        'Click a Gruppe on the table to choose it, then report to it. The wheel zooms, a drag moves ' +
        'the sheet and a double-click puts it back.')
    $lead.Margin = '0,0,0,16'; $lead.MaxWidth = 940; $lead.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($lead)

    # The plotting table. Same sheet, same plaque machinery and same zoom
    # as Fighter Command's board: only the projection and the labels
    # differ, and both of those come out of the map's own json.
    $W = 1180.0; $H = [math]::Round($W * 1600.0 / 2560.0)
    $mapWrap = New-Object Windows.Controls.Border
    $mapWrap.Width = $W + 2; $mapWrap.Height = $H + 2; $mapWrap.HorizontalAlignment = 'Left'
    $mapWrap.Background = B '#0B141B'; $mapWrap.BorderBrush = Res 'Rule'; $mapWrap.BorderThickness = '1'; $mapWrap.CornerRadius = '3'
    $grid = New-Object Windows.Controls.Grid
    $bg = New-Object Windows.Controls.Image
    $bmp = Load-Image -Path $script:MapImagePath -DecodeWidth 2560
    if ($bmp) { $bg.Source = $bmp }
    $bg.Stretch = 'Uniform'; $bg.Width = $W; $bg.Height = $H
    [void]$grid.Children.Add($bg)
    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $W; $cv.Height = $H; $cv.ClipToBounds = $true
    [void]$grid.Children.Add($cv)
    $mapWrap.Child = $grid
    Enable-MapZoom -Frame $mapWrap -Content $grid

    $script:MapTiles = @()
    $script:GruppeDetail = New-TB -Text $(if ($script:SelSq) { "$($script:SelSq.Unit), $($script:SelSq.Type), at $($script:SelSq.Base)." } else { 'No Gruppe selected.' }) `
                     -Family 'Segoe UI' -Size 14 -Colour '#9FB0B8' -Wrap
    $script:GruppeDetail.Margin = '2,0,0,12'; $script:GruppeDetail.MaxWidth = 1100; $script:GruppeDetail.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($script:GruppeDetail)

    # No .GetNewClosure() and the detail line kept in a script variable,
    # which is how the RAF board does it. A closure gets its own module
    # scope, so "$script:SelSq = ..." inside one writes to the CLOSURE and
    # never reaches the Room: clicking a Gruppe lit the REPORT button and
    # left the selection empty, so nothing could be joined. Same trap that
    # silently ignored -Side lw in the awards preview.
    $script:SelectSq = {
        param($q2)
        $script:SelSq = @{
            Unit = "$($q2.Label)"; Gesch = "$($q2.Gesch)"; Gruppe = "$($q2.Gruppe)"
            Type = "$($q2.Type)"; Base = "$($q2.Base)"; Skill = "$($q2.Skill)"
            Luftflotte = [int]$q2.Luftflotte; Period = "$($script:SelPeriod)"
        }
        foreach ($t in $script:MapTiles) {
            $tg = $t.Tag
            $tg.Sel = ([int]$tg.Num -eq [int]$q2.Num)
            $t.Background = if ($tg.Sel) { B '#33FFC24A' } else { B '#00000000' }
            $tg.Text.Foreground = if ($tg.Sel) { B '#FFE28A' } else { B $tg.Colour }
        }
        foreach ($a in $script:MapAssemblies) { $a.Sel = $false }
        foreach ($t in $script:MapTiles) { if ($t.Tag.Sel) { $t.Tag.Asm.Sel = $true } }
        Set-MapFocus $null
        if ($script:GruppeDetail) {
            $script:GruppeDetail.Text = "$($q2.Label), $($q2.Type), at $($q2.Base). Luftflotte $($q2.Luftflotte), rated $("$($q2.Skill)".ToLower())."
        }
        Set-ChromeActionEnabled $true
    }

    # gather the Gruppen by field, the way the RAF board gathers squadrons
    $byField = @{}
    $offTable = @()
    $num = 0
    foreach ($g in ($inLine | Sort-Object { "$($_.geschwader)" }, { @('I','II','III','IV','V').IndexOf("$($_.gruppe)") })) {
        $num++
        # Num is a unique integer the plaque machinery sorts and compares
        # on; Label is what it prints. A Gruppe has no number of its own.
        $qt = @{ Num = $num; Label = "$($g.unit)"; Type = "$($g.type)"; Base = "$($g.field)"
                 Gesch = "$($g.geschwader)"; Gruppe = "$($g.gruppe)"; Skill = "$($g.skill)"
                 Luftflotte = [int]$g.luftflotte; Act = $(if ([int]$g.luftflotte -eq 2) { 'H' } else { 'M' }) }
        $st = $MapStations["$($g.field)"]
        if (-not $st) { $offTable += $qt; continue }
        $k = "$($g.field)"
        if (-not $byField.ContainsKey($k)) {
            $byField[$k] = @{ Base = $k; X = [double]$st[0] * $W; Y = [double]$st[1] * $H; Sqns = @() }
        }
        $byField[$k].Sqns = @($byField[$k].Sqns) + @($qt)
    }
    $fields = @($byField.Values | Sort-Object @{ e = { $_.X } }, @{ e = { $_.Y } })
    Add-SquadronPlaques -Canvas $cv -Fields $fields -W $W -H $H -Mine 0 -Date $pd `
                        -OnSelect $true -AlwaysName
    [void]$script:Stage.Children.Add($mapWrap)

    if ($offTable.Count) {
        $fl = New-TB -Text 'FIELDS NOT ON THIS SHEET' -Family $CondFam -Size 11.5 -Colour '#8A9689' -Bold
        $fl.Margin = '2,12,0,6'
        [void]$script:Stage.Children.Add($fl)
        $chips = New-Object Windows.Controls.WrapPanel; $chips.HorizontalAlignment = 'Left'
        foreach ($qt in $offTable) {
            $chip = New-Object Windows.Controls.Border
            $chip.Padding = '12,7'; $chip.Margin = '0,0,10,10'; $chip.CornerRadius = '3'; $chip.Cursor = 'Hand'
            $chip.Background = B '#101B22'; $chip.BorderBrush = Res 'Rule'; $chip.BorderThickness = '1.5'
            $chip.Child = (New-TB -Text "$($qt.Label)  $([char]0x2022)  $($qt.Base)" -Family $CondFam -Size 12 -Colour '#F8C87E' -Bold)
            $chip.Tag = $qt
            $chip.Add_MouseLeftButtonUp({ param($sender,$e) & $script:SelectSq $sender.Tag })
            [void]$chips.Children.Add($chip)
        }
        [void]$script:Stage.Children.Add($chips)
    }

    # Say plainly what is not built yet, rather than offering a button that
    # goes nowhere.
    $note = New-Object Windows.Controls.Border
    $note.Background = B '#1A1710'; $note.BorderBrush = $script:BrassBrush
    $note.BorderThickness = '3,0,0,0'; $note.CornerRadius = '0,3,3,0'
    $note.Padding = '16,12'; $note.Margin = '0,16,0,0'; $note.HorizontalAlignment = 'Left'; $note.MaxWidth = 940
    $ns = New-Object Windows.Controls.StackPanel
    [void]$ns.Children.Add((New-TB -Text 'NOT FINISHED' -Family $CondFam -Size 11.5 -Colour '#C8973F' -Bold))
    $nt = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#9FB0B8' -Text (
        'The board, the ready room and the Iron Cross are in. The Flugbuch and the men of the ' +
        'Staffel are not: a German career keeps its own record, so nothing here touches your RAF ' +
        'pilot. The switch by the name at the top takes you back to him.')
    $nt.Margin = '0,5,0,0'
    [void]$ns.Children.Add($nt)
    $note.Child = $ns
    [void]$script:Stage.Children.Add($note)
}

# ---------------------------------------------------------------------
#  Reporting to a Gruppe, and the ready room he reports to.
#
#  Written as their own screens rather than as branches inside
#  Show-Create and Show-Roster. Those two are three hundred lines of RAF
#  furniture apiece - the roster of real men, the losses board, the record
#  of service - and none of it has a German equivalent yet. Threading a
#  side test through all of it would leave two screens that are mostly
#  dead code on either side. The parts that ARE shared, New-Heading,
#  New-Frame, New-Stat, New-BadgeImage and the chrome, are called from
#  here exactly as the RAF screens call them.
# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
#  The Iron Cross ladder.
#
#  Dated with the same care the RAF ladder is. That one leaves out the
#  CGM (Flying) because it was not instituted until November 1942, and
#  the AFC and AFM because they were for non-operational flying. The same
#  test throws three well-known German awards out of a 1940 career:
#
#    Deutsches Kreuz in Gold   instituted 28 September 1941
#    Frontflugspange           instituted 30 January 1941
#    Winterschlacht im Osten   instituted 26 May 1942, and for the East
#
#  The last of those was among the images to hand and is the easiest
#  mistake to make, being unmistakably German and unmistakably a medal.
#  A man flying the Channel in 1940 could not have had any of them.
#
#  What is left, and when:
#
#    Eisernes Kreuz II. Klasse   a first victory, or three sorties
#    Eisernes Kreuz I. Klasse    five victories, or twenty sorties
#    Ritterkreuz                 twenty victories
#
#  Twenty is the right benchmark for the second half of 1940. It was
#  raised to forty in 1941, which is the figure most often quoted and the
#  wrong one for this campaign.
#
#  The Eichenlaub is in, at forty victories. It was instituted on 3 June
#  1940 and Moelders and Galland both had it that September, which is
#  inside this campaign, so it belongs. It REPLACES the plain Ritterkreuz
#  in the row rather than sitting beside it: the oak leaves clasp onto the
#  cross a man already wears, and drawing two would be showing him with
#  two Knight's Crosses.
#
#  Three further grades were to hand and are all out on date. The swords
#  came on 21 June 1941 and the diamonds later still.
$LwHonourSpec = @(
    # Heights are set by how each one READS, not by how big the thing is.
    # The neck orders are tall narrow pictures, cross and ribbon, so at the
    # same height as the others they come out much the smallest on screen.
    @{ Award = 'Eichenlaub'; File = 'eichenlaub.png';  Height = 70; Tip = 'Ritterkreuz des Eisernen Kreuzes mit Eichenlaub' }
    @{ Award = 'Ritterkreuz'; File = 'ritterkreuz.png'; Height = 66; Tip = 'Ritterkreuz des Eisernen Kreuzes' }
    @{ Award = 'EK I';        File = 'ek1.png';         Height = 44; Tip = 'Eisernes Kreuz I. Klasse' }
    @{ Award = 'EK II';       File = 'ek2.png';         Height = 58; Tip = 'Eisernes Kreuz II. Klasse' }
)
function Get-LwHonours {
    param($Pilot, $Career)
    $v = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $v = [int]$Pilot.victories }
    $sorties = 0; if ($Career) { $sorties = [int]$Career.sorties }
    $h = @()
    # what he already holds is kept, exactly as on the RAF side: a
    # decoration is not taken away because a new campaign reset the count
    if (($Pilot.PSObject.Properties.Name -contains 'honours') -and $Pilot.honours) {
        foreach ($a in @($Pilot.honours)) { $h += "$($a.award)" }
    }
    if ((($v -ge 1) -or ($sorties -ge 3))  -and ($h -notcontains 'EK II'))       { $h += 'EK II' }
    if ((($v -ge 5) -or ($sorties -ge 20)) -and ($h -notcontains 'EK I'))        { $h += 'EK I' }
    if (($v -ge 20)                        -and ($h -notcontains 'Ritterkreuz')) { $h += 'Ritterkreuz' }
    if (($v -ge 40)                        -and ($h -notcontains 'Eichenlaub'))  { $h += 'Eichenlaub' }
    $h
}
# Worn, rather than laid out as ribbon chips.
#
# New-RibbonRow puts every RAF decoration in one bar of 15px ribbons, in
# order of precedence, and that is right for the RAF: they ARE ribbons.
# These are not. The EK II hangs from a ribbon, the EK I is pinned flat to
# the breast and has no ribbon at all, and the Ritterkreuz is worn at the
# throat. Rendering the three as identical little strips would be wrong in
# a way anybody who cares about this period would see at once, so they are
# drawn as the objects they are, at the sizes they are.
function New-LwHonourRow {
    param($Honours, [double]$Scale = 1.0)
    $set = @($Honours)
    if (-not $set.Count) { return $null }
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'; $row.VerticalAlignment = 'Center'
    foreach ($spec in $LwHonourSpec) {
        if ($set -notcontains $spec.Award) { continue }
        # a man with the oak leaves wears one Knight's Cross, not two
        if ($spec.Award -eq 'Ritterkreuz' -and ($set -contains 'Eichenlaub')) { continue }
        $bmp = Load-Image -Path (Join-Path $script:BadgeDir $spec.File)
        if (-not $bmp) { continue }
        $img = New-Object Windows.Controls.Image
        $img.Source = $bmp; $img.Stretch = 'Uniform'; $img.Height = [double]$spec.Height * $Scale
        $img.Margin = '0,0,12,0'; $img.ToolTip = $spec.Tip
        [void]$row.Children.Add($img)
    }
    if (-not $row.Children.Count) { return $null }
    $row
}

function Show-GruppeCreate {
    $script:Stage.Children.Clear()
    $script:SelPortrait = $null; $script:SelBorder = $null; $script:SelAcNum = 0
    if (-not $script:SelSq) { Show-GruppeSelect; return }
    Show-ChromeButtons $false
    $h = C 'HdrSquadron'; if ($h) { $h.Text = "$($script:SelSq.Unit)" }
    $m = C 'HdrMotto'
    if ($m) { $m.Text = "LUFTWAFFE  $([char]0x2022)  $($script:SelSq.Type.ToUpper()) AT $($script:SelSq.Base.ToUpper())" }
    Set-ChromeBack 'BACK TO THE BOARD' { Show-GruppeSelect }
    Set-ChromeAction -Text 'REPORT FOR DUTY' -Enabled $false -OnClick { Invoke-GruppeSubmit }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'REPORT TO THE GRUPPE' -Title "A new pilot for $($script:SelSq.Unit)"))
    $lead = New-TB -Wrap -Family 'Segoe UI' -Size 14.5 -Colour '#9FB0B8' -Text (
        'Summer 1940, on the Channel coast. Give your name, say whether you come to the Gruppe as a ' +
        'non-commissioned pilot or with a commission, and pick your photograph.')
    $lead.Margin = '0,-14,0,22'; $lead.MaxWidth = 940; $lead.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($lead)

    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,26'
    $nameCol = New-Object Windows.Controls.StackPanel; $nameCol.Margin = '0,0,36,0'
    [void]$nameCol.Children.Add((New-TB -Text 'NAME' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $script:NameBox = New-Object Windows.Controls.TextBox
    $script:NameBox.Width = 320; $script:NameBox.Margin = '0,7,0,0'; $script:NameBox.MaxLength = 40
    # The campaign save's pilot name is offered on the RAF side. It is NOT
    # offered here: that name belongs to whichever campaign is loaded, and
    # a German career started while an RAF campaign is open would take an
    # English name by default, which is worse than an empty box.
    [void]$nameCol.Children.Add($script:NameBox)
    $script:NameBox.Add_TextChanged({ Update-GruppeCreateValid })
    [void]$row.Children.Add($nameCol)

    # Unteroffizier or Leutnant. The two are separate careers in the
    # Luftwaffe rather than two ends of one ladder, so this choice decides
    # how far a man can rise, not merely where he starts.
    $rkCol = New-Object Windows.Controls.StackPanel
    [void]$rkCol.Children.Add((New-TB -Text 'YOU JOIN AS' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $rkRow = New-Object Windows.Controls.StackPanel; $rkRow.Orientation = 'Horizontal'; $rkRow.Margin = '0,7,0,0'
    $script:LwRankBtns = @{}
    foreach ($r in @('Unteroffizier','Leutnant')) {
        $b = New-Object Windows.Controls.Border
        $b.Padding = '14,9'; $b.Margin = '0,0,10,0'; $b.CornerRadius = '3'; $b.Cursor = 'Hand'; $b.Tag = $r
        $b.BorderThickness = '1'
        $inner = New-Object Windows.Controls.StackPanel; $inner.Orientation = 'Horizontal'
        $bf = Get-RankBadgeFile $r
        if ($bf) {
            $bi = New-BadgeImage -File $bf -Height 30 -Tip $r
            if ($bi) { $bi.Margin = '0,0,9,0'; [void]$inner.Children.Add($bi) }
        }
        [void]$inner.Children.Add((New-TB -Text $r -Family $CondFam -Size 14 -Colour '#E9E3D4'))
        $b.Child = $inner
        $b.Add_MouseLeftButtonUp({ param($sender,$e) $script:SelRank = "$($sender.Tag)"; Update-LwRankButtons; Update-GruppeCreateValid })
        $script:LwRankBtns[$r] = $b
        [void]$rkRow.Children.Add($b)
    }
    [void]$rkCol.Children.Add($rkRow)
    [void]$row.Children.Add($rkCol)
    [void]$script:Stage.Children.Add($row)
    if (-not $script:SelRank -or ($script:SelRank -notin @('Unteroffizier','Leutnant'))) { $script:SelRank = 'Unteroffizier' }
    Update-LwRankButtons

    # THE ONE MARKING THAT WAS HIS. The Gruppe symbol, the Geschwader
    # emblem and any Stab chevron all follow the unit and the
    # appointment, so there is nothing to ask about them. The individual
    # number is the pilot's own and is painted in his Staffel's colour,
    # so the choice is shown as the numbers themselves rather than as a
    # list of bare numerals.
    #
    # The Staffel is not settled until he is posted, so these are shown
    # in white, which is what the 1st, 4th and 7th Staffel wore. Which of
    # the three he lands in is decided in Invoke-GruppeSubmit a moment
    # later, and the number keeps its meaning whichever it is.
    $pickCol = 'white'
    # A ZERSTOERER IS ASKED FOR A LETTER, NOT A NUMBER. A Bf 110 wears a
    # bomber's code - the Geschwader's two characters, the Balkenkreuz,
    # his own letter and the Staffel's - so the one thing that is his is a
    # letter. The picker is the same tiles-in-a-row; only the alphabet
    # changes, and acnum stores the position either way.
    $is110 = ("$($script:SelSq.Type)" -match '110')
    $pickN = if ($is110) { 11 } else { 15 }
    [void]$script:Stage.Children.Add((New-TB -Text $(if ($is110) { 'YOUR LETTER' } else { 'YOUR NUMBER' }) `
                                     -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $numNote = New-TB -Wrap -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Text $(if ($is110) {
        'The letter painted aft of the Balkenkreuz, between the Geschwader''s code and your ' +
        'Staffel''s letter. It is the only part of the code that was ever the pilot''s own: the ' +
        'other two follow the unit. It will be painted in your Staffel''s colour once you have one.'
    } else {
        'The number painted forward of the Balkenkreuz. It is the only marking on the aeroplane that ' +
        'was ever the pilot''s own: the Gruppe symbol, the Geschwader emblem and a staff officer''s ' +
        'chevron all followed the unit. It will be painted in your Staffel''s colour once you have one.'
    })
    $numNote.Margin = '0,6,0,10'; $numNote.MaxWidth = 860; $numNote.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($numNote)
    $numRow = New-Object Windows.Controls.WrapPanel; $numRow.Margin = '0,0,0,18'; $numRow.HorizontalAlignment = 'Left'
    $numRow.MaxWidth = 900
    $script:NumBtns = @{}
    $mk0 = Get-LwMarkings
    foreach ($n in 1..$pickN) {
        $nb = New-Object Windows.Controls.Border
        $nb.Width = 54; $nb.Height = 54; $nb.Margin = '0,0,8,8'; $nb.CornerRadius = '3'
        $nb.BorderThickness = 2; $nb.Background = B '#101B22'; $nb.Cursor = 'Hand'; $nb.Tag = $n
        $nb.BorderBrush = B '#22303C'
        $nf = if (-not $mk0) { $null }
              elseif ($is110) { Get-MarkFile "$($mk0.letters110.($Letters110[$n - 1]).$pickCol)" }
              else { Get-MarkFile "$($mk0.numbers.$n.$pickCol)" }
        $nbmp = if ($nf) { Load-Image -Path $nf -DecodeWidth 96 } else { $null }
        if ($nbmp) {
            $ni = New-Object Windows.Controls.Image
            $ni.Source = $nbmp; $ni.Stretch = 'Uniform'; $ni.Margin = '8'
            $nb.Child = $ni
        } else {
            $nb.Child = (New-TB -Text $(if ($is110) { $Letters110[$n - 1] } else { "$n" }) `
                                -Family $CondFam -Size 18 -Colour '#E9E3D4' -Bold)
        }
        $nb.Add_MouseLeftButtonUp({
            param($sender,$e)
            $script:SelAcNum = [int]$sender.Tag
            Update-NumButtons
            Update-GruppeCreateValid
        })
        $script:NumBtns[$n] = $nb
        [void]$numRow.Children.Add($nb)
    }
    [void]$script:Stage.Children.Add($numRow)
    Update-NumButtons

    [void]$script:Stage.Children.Add((New-TB -Text 'YOUR PHOTOGRAPH' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $wrap = New-Object Windows.Controls.WrapPanel; $wrap.Margin = '0,10,0,0'; $wrap.HorizontalAlignment = 'Left'
    foreach ($pf in (Get-Portraits)) {
        $pb = New-Object Windows.Controls.Border
        $pb.Width = 96; $pb.Height = 120; $pb.Margin = '0,0,12,12'
        $pb.CornerRadius = '2'; $pb.BorderThickness = 3; $pb.BorderBrush = $script:FrameBrush
        $pb.Background = B '#0B1116'; $pb.Cursor = 'Hand'; $pb.Tag = $pf; $pb.ClipToBounds = $true
        $bmp = Load-Portrait -File $pf -DecodeHeight 150
        if ($bmp) {
            $img = New-Object Windows.Controls.Image; $img.Source = $bmp; $img.Stretch = 'UniformToFill'
            $pb.Child = $img
        }
        $pb.Add_MouseLeftButtonUp({
            param($sender,$e)
            if ($script:SelBorder) { $script:SelBorder.BorderBrush = $script:FrameBrush }
            $script:SelBorder = $sender; $sender.BorderBrush = $script:BrassBrush
            $script:SelPortrait = "$($sender.Tag)"
            Update-GruppeCreateValid
        })
        [void]$wrap.Children.Add($pb)
    }
    [void]$script:Stage.Children.Add($wrap)
    Update-GruppeCreateValid
}
function Update-LwRankButtons {
    if (-not $script:LwRankBtns) { return }
    foreach ($k in $script:LwRankBtns.Keys) {
        $on = ($k -eq $script:SelRank)
        $script:LwRankBtns[$k].Background = if ($on) { Res 'PanelHi' } else { B '#101B22' }
        $script:LwRankBtns[$k].BorderBrush = if ($on) { $script:BrassBrush } else { B '#22303C' }
    }
}
function Update-NumButtons {
    if (-not $script:NumBtns) { return }
    foreach ($k in $script:NumBtns.Keys) {
        $on = ([int]$k -eq [int]$script:SelAcNum)
        $script:NumBtns[$k].Background = if ($on) { Res 'PanelHi' } else { B '#101B22' }
        $script:NumBtns[$k].BorderBrush = if ($on) { $script:BrassBrush } else { B '#22303C' }
    }
}
function Update-GruppeCreateValid {
    # The number is part of reporting now, so it is part of the test. A
    # man who has not picked one would otherwise be given one worked out
    # from his own name, which is the right answer for a record made
    # before there was a choice and the wrong one for a new man: he was
    # asked, and he should answer.
    $ok = ($script:NameBox -and $script:NameBox.Text.Trim().Length -ge 2) -and
          ($null -ne $script:SelPortrait) -and ([int]$script:SelAcNum -gt 0)
    Set-ChromeActionEnabled $ok
}
function Invoke-GruppeSubmit {
    Complete-NewCareer
    $q = $script:SelSq
    $rank = if ($script:SelRank) { "$($script:SelRank)" } else { 'Unteroffizier' }
    # A Staffel number, because a man belongs to one and the Gruppe is
    # three of them: I. Gruppe holds 1., 2. and 3. Staffel, II. holds 4.
    # to 6., III. holds 7. to 9.
    $gi = @('I','II','III','IV','V').IndexOf("$($q.Gruppe)"); if ($gi -lt 0) { $gi = 0 }
    $staffel = ($gi * 3) + (Get-Random -Minimum 1 -Maximum 4)
    $pilot = [ordered]@{
        pilot   = $script:NameBox.Text.Trim()
        rank    = $rank
        side    = 'lw'
        status  = 'On strength'
        note    = "Posted to $($q.Unit) at $($q.Base)."
        cmode   = 'pilot'
        unit    = "$($q.Unit)"
        gesch   = "$($q.Gesch)"
        gruppe  = "$($q.Gruppe)"
        staffel = $staffel
        sqn     = 0
        actype  = "$($q.Type)"
        base    = "$($q.Base)"
        luftflotte = [int]$q.Luftflotte
        period  = "$($q.Period)"
        historical = $false
        portrait = $script:SelPortrait
        acnum   = [int]$script:SelAcNum
        created = (Get-Date).ToString('yyyy-MM-dd')
    }
    # THE REST OF THE CREW, for a type that carries one. A 109 gets an
    # empty array and the record is what it has always been.
    $pilot['crew'] = @(New-CrewFor -Unit "$($q.Unit)" -Type "$($q.Type)" `
                                   -Date $script:CampaignDate `
                                   -Seed "$($script:NameBox.Text)$($q.Unit)" -SortiesBase 0)
    $ld0 = Get-LatestSaveDiary
    if ($ld0) {
        $pilot['campaignSorties'] = @($ld0.rows).Count
        $pilot['campaignKills'] = @(0..6 | ForEach-Object { [int]$ld0.kills[$_] })
    } else {
        $pilot['campaignSorties'] = 0
        $pilot['campaignKills'] = @(0,0,0,0,0,0,0)
    }
    Save-Pilot -Pilot $pilot -Shrink
    Show-ReadyRoom -Pilot (Get-Pilot)
}

# The Flugbuch. The German pilot's own Log Book, read out of the campaign
# save exactly as the RAF one is: the same Diary::Player table, the same
# rows, the same New-DiaryRow. Only the aircraft types differ, and those
# come from Get-KillBins.
#
# WHAT IS NOT PROVED HERE, and it matters. Everything below is built on a
# player record read from RAF saves, because no Luftwaffe save exists to
# test against. The squadron tables are settled - two of them, 24 bytes
# and 17, verified against real files by dev/lw_diary_probe.py - but
# whether Diary::Player is laid out the same for a German career is an
# assumption. The save header carries seven German tallies and six
# British ones, so the likeliest shape is the same 25-byte row with only
# the first six used, which is what this reads.
#
# If it turns out otherwise the symptom will be a Flugbuch full of
# nonsense rather than an empty one, so it says plainly at the top that
# it has not been checked against a German campaign.
# The men of the Staffel.
#
# Two different things live in these files and the screen must never
# blur them. A man marked historical was really there and his unit and
# appointment are ordinary record; nothing else is claimed for him, no
# fate and no score, because naming a man who was there is one thing and
# writing him a death he did not have is quite another. Everyone else is
# a period-correct name dealt out from the unit's own seed, and the
# screen says so in as many words.
function Get-LwRoster {
    param([string]$Unit)
    if (-not $Unit) { return @() }
    $f = Join-Path (Join-Path $script:SideModDir 'rosters') (($Unit -replace '\.','' -replace '/','_' -replace ' ','') + '.json')
    if (-not (Test-Path $f)) { return @() }
    try {
        $all = @(Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json)
        while ($all.Count -eq 1 -and ($all[0] -is [System.Array])) { $all = $all[0] }
        return $all
    } catch { }
    @()
}
# One man on the board: rank, name, what he is doing, his score and how
# his war ended. The last two are empty for the men of record, because
# nothing beyond their unit and appointment is claimed for them.
function New-LwRosterRow {
    param($Man, [switch]$IsPlayer, [switch]$Header, [int]$Vics = -1)
    $bd = New-Object Windows.Controls.Border
    $bd.Padding = '14,9'; $bd.BorderBrush = Res 'Rule'; $bd.BorderThickness = '0,0,0,1'
    if ($Header) { $bd.Background = B '#101B22' }
    $g = New-Object Windows.Controls.Grid
    foreach ($wd in @('96','*','200','74','150')) {
        $c = New-Object Windows.Controls.ColumnDefinition
        $c.Width = [Windows.GridLength]$(if ($wd -eq '*') { [Windows.GridLength]::new(1,'Star') } else { [Windows.GridLength]::new([double]$wd) })
        [void]$g.ColumnDefinitions.Add($c)
    }
    if ($Header) {
        $i = 0
        foreach ($t in @('', 'PILOT', 'SEAT', 'VICTORIES', 'STATUS')) {
            $tb = New-TB -Text $t -Family $CondFam -Size 11 -Colour '#6F828C' -Bold
            if ($i -ge 2) { $tb.Margin = '14,0,0,0' }
            [Windows.Controls.Grid]::SetColumn($tb, $i); [void]$g.Children.Add($tb); $i++
        }
        $bd.Child = $g
        return $bd
    }
    $col = if ($IsPlayer) { '#FFC24A' } elseif ($Man.historical) { '#E9E3D4' } else { '#9FB0B8' }
    $r0 = New-TB -Text (Short-Rank "$($Man.rank)") -Family $CondFam -Size 12.5 -Colour '#6F828C'
    [Windows.Controls.Grid]::SetColumn($r0, 0); [void]$g.Children.Add($r0)
    $nm = New-TB -Text "$($Man.pilot)" -Family $CondFam -Size 14 -Colour $col -Bold
    [Windows.Controls.Grid]::SetColumn($nm, 1); [void]$g.Children.Add($nm)
    # The seat comes before the Staffel now, because on a Zerstoerer board
    # half the men are Bordfunker and a column of Staffel numbers does not
    # say which half is which.
    $seat = ''
    if (($Man.PSObject.Properties.Name -contains 'role') -and "$($Man.role)" -and "$($Man.role)" -ne 'Flugzeugfuehrer') {
        $seat = "$($Man.role)"
    }
    $rt = if ($IsPlayer) { 'you' }
          elseif ($Man.appointment) { "$($Man.appointment)" }
          elseif ($seat) { $seat }
          elseif ($Man.staffel) { "$($Man.staffel). Staffel" } else { '' }
    $r2 = New-TB -Text $rt -Family 'Segoe UI' -Size 12 -Colour $(if ($Man.historical) { '#C8973F' } else { '#6F828C' }) -Wrap
    $r2.Margin = '14,0,0,0'
    [Windows.Controls.Grid]::SetColumn($r2, 2); [void]$g.Children.Add($r2)

    $v = if ($IsPlayer) { $Vics } elseif ($null -ne $Man.victories_total) { [int]$Man.victories_total } else { -1 }
    $vt = New-TB -Text $(if ($v -gt 0) { "$v" } else { '' }) -Family $CondFam -Size 13 -Colour $(if ($IsPlayer) { '#FFC24A' } else { '#C8973F' }) -Bold
    $vt.Margin = '14,0,0,0'
    [Windows.Controls.Grid]::SetColumn($vt, 3); [void]$g.Children.Add($vt)

    $st = if ($IsPlayer) { 'On strength' }
          elseif ($Man.fate -and "$($Man.fate.status)") { "$($Man.fate.status)" }
          elseif ($Man.historical) { '' } else { 'On strength' }
    $stc = switch ("$st") {
        'Killed'   { '#E2685A' }
        'Missing'  { '#E2685A' }
        'Prisoner' { '#D9A441' }
        'Wounded'  { '#D9A441' }
        default    { '#8FB56A' }
    }
    $sd = if ($Man.fate -and "$($Man.fate.date)") { ' ' + (Format-ShortDate "$($Man.fate.date)") } else { '' }
    $s4 = New-TB -Text "$st$sd" -Family 'Segoe UI' -Size 12 -Colour $(if ($st) { $stc } else { '#6F828C' })
    $s4.Margin = '14,0,0,0'
    [Windows.Controls.Grid]::SetColumn($s4, 4); [void]$g.Children.Add($s4)
    $bd.Child = $g
    $bd
}

function Show-Flugbuch {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'logbook'))
    Show-ChromeButtons $true
    $h = C 'HdrSquadron'; if ($h) { $h.Text = "$($Pilot.unit)" }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "LUFTWAFFE  $([char]0x2022)  FLUGBUCH" }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'FLUGBUCH' -Title "$($Pilot.pilot)"))

    $cp = Get-CampaignPilot
    if ($cp) {
        $cpl = New-TB -Text "Campaign pilot on record: $($cp.Name)" -Family 'Segoe UI' -Size 13 -Colour '#9FB0B8'
        $cpl.Margin = '0,-12,0,14'
        [void]$script:Stage.Children.Add($cpl)
    }
    # WHO ELSE IS IN THE AEROPLANE. Every sortie in this book was flown by
    # both of them, so both are named at the top of it.
    $crewF = @(Get-Crew $Pilot)
    if ($crewF.Count) {
        $who = @($crewF | ForEach-Object { "$(Short-Rank "$($_.rank)") $($_.pilot), $($_.role)" })
        $cw = New-TB -Wrap -Family 'Segoe UI' -Size 13 -Colour '#9FB0B8' -Text (
            'Flying with him: ' + ($who -join '; ') + '.')
        $cw.Margin = '0,-8,0,4'; $cw.MaxWidth = 900; $cw.HorizontalAlignment = 'Left'
        [void]$script:Stage.Children.Add($cw)
        # Patrick's decision, said on the screen rather than buried in a
        # commit: the save keeps ONE kill tally per sortie and no gun
        # position, so there is nothing to divide between the two of them
        # and nothing here pretends otherwise.
        $cn = New-TB -Wrap -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Text (
            'The claims below are the aircraft''s. The save records one tally for the sortie and ' +
            'does not record which gun fired, so they are not split between the two men. His ' +
            'crewman''s rank and decorations come off sorties flown, and are this Room''s invention.')
        $cn.Margin = '0,0,0,14'; $cn.MaxWidth = 900; $cn.HorizontalAlignment = 'Left'
        [void]$script:Stage.Children.Add($cn)
    }

    $sessions = Get-Sessions
    $ld = Sync-CampaignClaims
    $p2 = Get-Pilot; if ($p2) { $Pilot = $p2 }
    $career = Get-Career $Pilot $sessions -Sorties (Get-SortieCount -Diary $ld -Sessions $sessions -Pilot $Pilot)
    $ld = Get-CareerDiary -Diary $ld -Pilot $Pilot
    $vics = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $vics = [int]$Pilot.victories }
    $bins = Get-KillBins $Pilot

    $tiles = New-Object Windows.Controls.StackPanel; $tiles.Orientation = 'Horizontal'; $tiles.Margin = '0,-6,0,12'
    [void]$tiles.Children.Add((New-Stat 'FEINDFLUEGE' "$($career.sorties)"))
    [void]$tiles.Children.Add((New-Stat 'FLYING HOURS' "$($career.hours)"))
    [void]$tiles.Children.Add((New-Stat 'ABSCHUESSE' "$vics"))
    $honours = @(Get-LwHonours -Pilot $Pilot -Career $career)
    $Pilot = Update-CareerRecord -Pilot $Pilot -Career $career -Honours $honours
    $awTile = if ($honours.Count) { $honours[$honours.Count-1] } else { 'None yet' }
    [void]$tiles.Children.Add((New-Stat 'AWARDS' $awTile -Chip (New-LwHonourRow $honours -Scale 0.30)))
    [void]$tiles.Children.Add((New-Stat 'RANK' (Short-Rank "$($career.rank)") -Chip $(
        $f = Get-RankBadgeFile "$($career.rank)"
        if ($f) { New-BadgeImage -File $f -Height 38 -Tip "$($career.rank)" }
    )))
    [void]$script:Stage.Children.Add($tiles)

    $pn = if ($career.next) { "Next promotion to $($career.next) at $($career.nextAt) Feindfluege." } else { 'At the top of his ladder.' }
    $pnt = New-TB -Text $pn -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Wrap
    $pnt.Margin = '0,2,0,14'; $pnt.MaxWidth = 860; $pnt.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($pnt)

    # Said out loud, because it is the one part of the German side that
    # rests on an assumption rather than on something checked.
    $warn = New-Object Windows.Controls.Border
    $warn.Background = B '#1A1710'; $warn.BorderBrush = $script:BrassBrush
    $warn.BorderThickness = '3,0,0,0'; $warn.CornerRadius = '0,3,3,0'
    $warn.Padding = '16,11'; $warn.Margin = '0,0,0,18'; $warn.HorizontalAlignment = 'Left'; $warn.MaxWidth = 940
    $ws = New-Object Windows.Controls.StackPanel
    [void]$ws.Children.Add((New-TB -Text 'NOT YET CHECKED AGAINST A GERMAN CAMPAIGN' -Family $CondFam -Size 11.5 -Colour '#C8973F' -Bold))
    $wt = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#9FB0B8' -Text (
        'This reads the campaign save the same way the RAF Log Book does, and that part is proved. ' +
        'What is not is whether the game lays a German pilot out identically: no Luftwaffe save has ' +
        'been available to check. If the figures below look like nonsense rather than merely empty, ' +
        'that is why, and it is worth saying so.')
    $wt.Margin = '0,5,0,0'
    [void]$ws.Children.Add($wt)
    $warn.Child = $ws
    [void]$script:Stage.Children.Add($warn)

    [void]$script:Stage.Children.Add((New-TB -Text 'FEINDFLUEGE' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
    if ($ld -and @($ld.rows).Count -gt 0) {
        $lw = New-Object Windows.Controls.Border
        $lw.BorderBrush = Res 'Rule'; $lw.BorderThickness = '1'; $lw.CornerRadius = '3'
        $lw.Margin = '0,10,0,0'; $lw.ClipToBounds = $true
        $ls = New-Object Windows.Controls.StackPanel
        [void]$ls.Children.Add((New-DiaryRow -Header))
        $arr = @($ld.rows); $i = 0
        for ($k = $arr.Count - 1; $k -ge 0; $k--) {
            [void]$ls.Children.Add((New-DiaryRow -R $arr[$k] -Number ($k + 1) -Index $i -Bins $bins)); $i++
        }
        $lw.Child = $ls
        [void]$script:Stage.Children.Add($lw)
    }
    else {
        $none = New-TB -Wrap -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Text (
            'Nothing flown yet. The campaign keeps its own Log Book inside the save, one line a sortie ' +
            'with how it ended and what was shot down, and this fills itself from it.')
        $none.Margin = '0,10,0,0'; $none.MaxWidth = 860; $none.HorizontalAlignment = 'Left'
        [void]$script:Stage.Children.Add($none)
    }
}

# =====================================================================
#  The markings on a Bf 109
#
#  An RAF fighter carries two squadron code letters, an individual
#  letter and a serial, and New-Aircraft paints all four onto the
#  Spitfire as draggable text. A 109 is a different problem, and only
#  one part of it was ever the pilot's own:
#
#    THE INDIVIDUAL NUMBER, forward of the Balkenkreuz, in his STAFFEL's
#    colour: white for the 1st, 4th and 7th Staffel, red for the 2nd,
#    5th and 8th, yellow for the 3rd, 6th and 9th. He picks this.
#
#    THE GRUPPE SYMBOL, aft of the cross. I. Gruppe wore nothing at all,
#    II. a horizontal bar, III. a vertical bar or a wavy line depending
#    on the Geschwader. Follows the unit.
#
#    THE GESCHWADER EMBLEM on the cowling, or, for JG 53, a red band
#    round the rear fuselage. Follows the unit.
#
#    A STAB CHEVRON in place of the number, for the men on the staff.
#    Follows the appointment.
#
#  So the Room offers the number and works the rest out, which is the
#  right way round and happens to be the historically true one.
#
#  These are images rather than glyphs, so they cannot go through
#  Add-AcMark. Add-AcImage is the same idea for a picture: drawn where
#  the table says or where it was last dragged to, moved with the mouse,
#  sized with the wheel, put back with a double-click, and remembered in
#  the same acpos.json under the same per-side key.
# =====================================================================
$MarkPath = Join-Path (Join-Path $ModDir 'lw') 'markings.json'
# Where each marking goes, measured off the game's own MultiSkin rules by
# dev/measure_markings.py rather than placed by eye. Patrick asked the
# obvious question - the game puts these in the right place, is the right
# place written down? It is, in MultiSkin\*.ms, as
#
#     use <tile>.dds, 2048, 2048, <scaleX>, <scaleY>, <x>, <y> if <unit...>
#
# and the measuring script converts those texture coordinates onto each
# profile drawing using the Balkenkreuz as the ruler. Per profile, because
# there are forty of them and they do not all put the cross in the same
# place.
$MarkPosPath = Join-Path $ModDir 'marking-positions.json'
function Get-MarkPositions {
    if ($null -ne $script:MarkPos) { return $script:MarkPos }
    $m = $null
    if (Test-Path $MarkPosPath) {
        try { $m = Get-Content $MarkPosPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    $script:MarkPos = $m
    $m
}
function Get-LwMarkings {
    if ($null -ne $script:LwMarks) { return $script:LwMarks }
    $m = $null
    if (Test-Path $MarkPath) {
        try { $m = Get-Content $MarkPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    $script:LwMarks = $m
    $m
}
# White, red or yellow. The Staffel's colour, not the Gruppe's: 1., 4.
# and 7. Staffel all wore white, and they sit in different Gruppen.
function Get-StaffelColour {
    param($Pilot)
    $n = 1
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'staffel') -and $Pilot.staffel) {
        $n = [int]$Pilot.staffel
    }
    $col = switch ((($n - 1) % 3) + 1) { 1 { 'white' } 2 { 'red' } default { 'yellow' } }

    # Three Gruppen do not follow their Staffel's colour all campaign, and
    # Me109_PlaneID_1.ms is where that is written down. II./JG 26 and
    # I./JG 51 paint their third Staffel brown on black until 18 August;
    # III./JG 27's 8. Staffel is red until 21 August and black on white
    # after it. The rules are read out of the file by
    # dev/build_lw_markings.py rather than typed in here.
    #
    # This is the whole reason the 109 needed the campaign date at all. It
    # never had it: Get-GruppeAircraftPath picks a 109 plate by unit name
    # alone, where a 110 goes through Get-Profile110 with the date, so
    # every one of these was being drawn in the wrong colour before its
    # date. Raised by 33lima on 10 September 2026.
    $m = Get-LwMarkings
    if ($m -and $m.PSObject.Properties.Name -contains 'number_dates' -and $script:CampaignDate) {
        $unit = "$($Pilot.unit)"
        foreach ($r in @($m.number_dates)) {
            if ("$($r.unit)" -ne $unit) { continue }
            if ([int]$r.staffel -ne $n) { continue }
            $d = $null
            try { $d = [datetime]::ParseExact("$($r.date)", 'yyyy-MM-dd', $null) } catch { }
            if (-not $d) { continue }
            $pick = if ($script:CampaignDate -lt $d) { "$($r.before)" } else { "$($r.after)" }
            if ($pick) { $col = $pick }
            break
        }
    }
    $col
}
# The number he flies. Chosen when he reports to the Gruppe; an older
# record made before there was a choice gets one from his own name, so
# it is the same every time rather than a fresh number each opening.
function Get-AcNumber {
    param($Pilot)
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'acnum') -and [int]$Pilot.acnum -gt 0) {
        return [int]$Pilot.acnum
    }
    $seed = 0
    foreach ($c in "$($Pilot.pilot)$($Pilot.unit)".ToCharArray()) { $seed = ($seed * 31 + [int]$c) % 100000 }
    ($seed % 15) + 1
}
# WHO FLIES WITH HIM, drawn from the Gruppe's own roster.
#
# The roster now carries a role on every man, so a Zerstoerer Gruppe has
# twelve pilots and twelve Bordfunker rather than twelve men. This picks
# one for each further seat the aeroplane has.
#
# The choice is SEEDED FROM THE PLAYER'S OWN NAME, so the same man gets
# the same crew every time the Room is opened rather than a fresh one
# each visit. Men whose invented fate has already passed are skipped:
# there is no sense being posted alongside somebody who was killed in
# July when it is September.
function Get-CrewCandidate {
    param($Unit, [string]$Role, $Date, $Seed, $Taken = @())
    $men = @(Get-LwRoster -Unit $Unit | Where-Object {
        ("$($_.role)" -eq $Role) -and ($Taken -notcontains "$($_.pilot)")
    })
    if (-not $men.Count) { return $null }
    $alive = @($men | Where-Object {
        if (-not $_.left -or -not $Date) { return $true }
        try { return ([datetime]::ParseExact("$($_.left)",'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture) -gt $Date) } catch { return $true }
    })
    if ($alive.Count) { $men = $alive }
    $h = 0
    foreach ($c in "$Seed$Role".ToCharArray()) { $h = ($h * 31 + [int]$c) % 100000 }
    $men[$h % $men.Count]
}
# His photograph, settled the same way: from his own name, so it is the
# same face every time and nothing has to be stored beyond the name.
function Get-CrewPortrait {
    param([string]$Name)
    # FLATTENED, with the loop this file uses everywhere else.
    # ConvertFrom-Json hands the portrait list back as ONE element that
    # IS the array, so @(Get-Portraits) counts 1 and index 0 is all 92
    # names - which came out as a portrait field holding every filename
    # joined by spaces. The RAF morning paper shipped broken once for
    # exactly this, with a single flatten where a loop was needed.
    $ps = @(Get-Portraits)
    while ($ps.Count -eq 1 -and ($ps[0] -is [System.Array])) { $ps = $ps[0] }
    if (-not $ps.Count) { return $null }
    $h = 0
    foreach ($c in "$Name".ToCharArray()) { $h = ($h * 31 + [int]$c) % 100000 }
    return [string]$ps[$h % $ps.Count]
}
# The crew a man gets on the day he is posted, one member per further
# seat. Returns an empty array for a single-seat type, so a 109 career is
# exactly what it always was.
function New-CrewFor {
    param($Unit, [string]$Type, $Date, [string]$Seed, [int]$SortiesBase = 0)
    $roles = @(Get-CrewRoles $Type)
    if ($roles.Count -le 1) { return @() }
    $out = @(); $taken = @()
    foreach ($r in $roles[1..($roles.Count - 1)]) {
        $m = Get-CrewCandidate -Unit $Unit -Role $r -Date $Date -Seed $Seed -Taken $taken
        if (-not $m) { continue }
        $taken += "$($m.pilot)"
        # Built with plain statements rather than inline $(if ...) inside
        # the hashtable. Written that way, `rank` came out as the string
        # "1" - the branch's own boolean leaking into the value - and the
        # fault is invisible until a screen shows a man whose rank is a
        # number.
        $mName = "$($m.pilot)"
        $mRank = "$($m.rank)"
        if (-not $mRank) {
            $mRank = 'Unteroffizier'
            if ($CrewEntryRank.ContainsKey($r)) { $mRank = [string]$CrewEntryRank[$r] }
        }
        $mPort = Get-CrewPortrait $mName
        $mJoin = ''
        if ($Date) { $mJoin = $Date.ToString('yyyy-MM-dd') }
        $out += [ordered]@{
            role        = [string]$r
            pilot       = [string]$mName
            rank        = [string]$mRank
            rank_date   = ''
            portrait    = [string]$mPort
            honours     = @()
            sortiesBase = [int]$SortiesBase
            joined      = [string]$mJoin
            src         = 'invented'
        }
    }
    # A PLAIN return. Comma-returning here and collecting with @() at the
    # caller nests the crew one level deep, and the whole array then
    # arrives as a single "member" whose rank reads as 1. Same rule as
    # everywhere else in this file: comma return XOR @() at the caller.
    $out
}
# WHEN A CREWMAN DOES NOT COME BACK.
#
# Every man on the roster carries an invented fate on a dated day, and
# the Bordfunker is drawn from that roster, so his day comes like anyone
# else's. Patrick's decision was that he is replaced and the Room says
# so, rather than being quietly swapped or made unkillable - every other
# man on the board can be killed, and one who cannot reads oddly.
#
# The replacement's sortiesBase is set to the count SO FAR, so he starts
# at nought and does not inherit sorties he did not fly.
#
# Returns the list of losses, so the Ready Room can name them.
function Update-CrewLosses {
    param($Pilot, [int]$Sorties)
    $crew = @(Get-Crew $Pilot)
    if (-not $crew.Count) { return @() }
    $d = $script:CampaignDate
    if (-not $d) { return @() }
    $roster = @(Get-LwRoster -Unit "$($Pilot.unit)")
    $lost = @(); $newCrew = @(); $changed = $false
    $taken = @($crew | ForEach-Object { "$($_.pilot)" })
    foreach ($m in $crew) {
        $man = $roster | Where-Object { "$($_.pilot)" -eq "$($m.pilot)" } | Select-Object -First 1
        $gone = $false; $when = $null; $how = 'did not come back'
        if ($man -and "$($man.left)") {
            try {
                $ld = [datetime]::ParseExact("$($man.left)",'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)
                if ($ld -le $d) {
                    $gone = $true; $when = $ld
                    if ($man.fate -and "$($man.fate.status)") { $how = "$($man.fate.status)".ToLower() }
                }
            } catch { }
        }
        if (-not $gone) { $newCrew += $m; continue }
        $rep = Get-CrewCandidate -Unit "$($Pilot.unit)" -Role "$($m.role)" -Date $d `
                                 -Seed "$($Pilot.pilot)$($m.pilot)" -Taken $taken
        $lost += [ordered]@{ pilot = "$($m.pilot)"; rank = "$($m.rank)"; role = "$($m.role)"
                             date = $when.ToString('yyyy-MM-dd'); how = $how
                             replacedBy = $(if ($rep) { "$($rep.pilot)" } else { '' }) }
        $changed = $true
        if (-not $rep) { continue }
        $taken += "$($rep.pilot)"
        $rk = "$($rep.rank)"
        if (-not $rk) { $rk = 'Unteroffizier' }
        $newCrew += [pscustomobject]([ordered]@{
            role        = [string]$m.role
            pilot       = [string]$rep.pilot
            rank        = [string]$rk
            rank_date   = ''
            portrait    = [string](Get-CrewPortrait "$($rep.pilot)")
            honours     = @()
            sortiesBase = [int]$Sorties
            joined      = [string]$d.ToString('yyyy-MM-dd')
            src         = 'invented'
        })
    }
    if (-not $changed) { return @() }
    $obj = [ordered]@{}
    foreach ($pp in $Pilot.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
    $obj['crew'] = @($newCrew)
    # -Shrink because a man lost and not replaced makes the record
    # genuinely smaller, and that is a real event rather than a mistake.
    Save-Pilot -Pilot $obj -Shrink
    $lost
}
# A Zerstoerer's own letter. The same acnum the adjutant asks for, read
# as a letter instead of a numeral: the fuselage rules run A to K and
# stop there, so eleven letters and no more.
$Letters110 = @('A','B','C','D','E','F','G','H','I','J','K')
function Get-Ac110Letter {
    param($Pilot)
    $n = Get-AcNumber $Pilot
    $i = [math]::Max(0, [math]::Min($Letters110.Count - 1, [int]$n - 1))
    $Letters110[$i]
}
function Get-MarkFile {
    param([string]$Rel)
    if (-not $Rel) { return $null }
    $f = Join-Path (Join-Path (Join-Path $ModDir 'lw') 'markings') ($Rel -replace '/','\')
    if (Test-Path $f) { return $f }
    $null
}
# One picture on the aeroplane. The twin of Add-AcMark, which does the
# same for text: same acpos.json, same drag, same wheel, same
# double-click to put it back. The wheel changes WIDTH here where the
# text version changes FontSize, and the height follows the picture's
# own shape so a chevron cannot be squashed into a square.
function Add-AcImage {
    param($Canvas, [string]$Key, [string]$File, [double]$DX, [double]$DY,
          [double]$DW, [double]$W, [double]$H, [string]$Tip)
    if (-not $File) { return $null }
    $bmp = Load-Image -Path $File -DecodeWidth 320
    if (-not $bmp) { return $null }
    $ratio = if ($bmp.PixelWidth -gt 0) { [double]$bmp.PixelHeight / [double]$bmp.PixelWidth } else { 1.0 }
    $fx = $DX; $fy = $DY; $wf = $DW
    if ($script:AcPos.ContainsKey($Key)) {
        $rec = $script:AcPos[$Key]
        $fx = [double]$rec.x; $fy = [double]$rec.y
        if ($rec.ContainsKey('s') -and [double]$rec.s -gt 0) { $wf = [double]$rec.s }
    }
    $img = New-Object Windows.Controls.Image
    $img.Source = $bmp; $img.Stretch = 'Fill'
    $img.Width = $wf * $W; $img.Height = $img.Width * $ratio
    $img.Cursor = 'SizeAll'
    $img.ToolTip = $(if ($Tip) { "$Tip  Drag to move, roll the wheel to size it, double-click to put it back." }
                     else { 'Drag to move, roll the wheel to size it, double-click to put it back.' })
    [Windows.Controls.Canvas]::SetLeft($img, $fx * $W)
    [Windows.Controls.Canvas]::SetTop($img,  $fy * $H)
    # Everything the handlers need travels in the Tag. A closure would
    # get its own module scope and the $script: writes inside it would
    # never reach the Room.
    $img.Tag = @{ Key = $Key; W = $W; H = $H; DX = $DX; DY = $DY; DW = $DW; Ratio = $ratio
                  Drag = $false; Moved = $false; OX = 0.0; OY = 0.0 }
    $img.Add_MouseWheel({
        param($sender, $e)
        $t = $sender.Tag
        $wf = ($sender.Width / $t.W) * $(if ($e.Delta -gt 0) { 1.06 } else { 1.0 / 1.06 })
        $wf = [math]::Max(0.006, [math]::Min(0.45, $wf))
        $sender.Width = $wf * $t.W; $sender.Height = $sender.Width * $t.Ratio
        Save-AcImage $sender
        $e.Handled = $true
    })
    $img.Add_MouseLeftButtonDown({
        param($sender, $e)
        $t = $sender.Tag
        if ($e.ClickCount -ge 2) {
            [Windows.Controls.Canvas]::SetLeft($sender, $t.DX * $t.W)
            [Windows.Controls.Canvas]::SetTop($sender,  $t.DY * $t.H)
            $sender.Width = $t.DW * $t.W; $sender.Height = $sender.Width * $t.Ratio
            $script:AcPos.Remove($t.Key); Save-AcPos $script:AcPos
            $e.Handled = $true; return
        }
        $p = $e.GetPosition($sender.Parent)
        $t.OX = $p.X - [Windows.Controls.Canvas]::GetLeft($sender)
        $t.OY = $p.Y - [Windows.Controls.Canvas]::GetTop($sender)
        $t.Drag = $true; $t.Moved = $false
        [void]$sender.CaptureMouse(); $e.Handled = $true
    })
    $img.Add_MouseMove({
        param($sender, $e)
        $t = $sender.Tag
        if (-not $t.Drag) { return }
        $p = $e.GetPosition($sender.Parent)
        $nx = $p.X - $t.OX; $ny = $p.Y - $t.OY
        if (-not $t.Moved -and ([math]::Abs($nx - [Windows.Controls.Canvas]::GetLeft($sender)) -le 2) `
                          -and ([math]::Abs($ny - [Windows.Controls.Canvas]::GetTop($sender)) -le 2)) { return }
        $t.Moved = $true
        $nx = [math]::Max(-20.0, [math]::Min($t.W - 10.0, $nx))
        $ny = [math]::Max(-20.0, [math]::Min($t.H - 10.0, $ny))
        [Windows.Controls.Canvas]::SetLeft($sender, $nx)
        [Windows.Controls.Canvas]::SetTop($sender, $ny)
    })
    $img.Add_MouseLeftButtonUp({
        param($sender, $e)
        $t = $sender.Tag
        if (-not $t.Drag) { return }
        $t.Drag = $false; [void]$sender.ReleaseMouseCapture()
        if (-not $t.Moved) { return }
        Save-AcImage $sender
    })
    [void]$Canvas.Children.Add($img)
    $img
}
function Save-AcImage {
    param($Mark)
    $t = $Mark.Tag
    $script:AcPos[$t.Key] = @{
        x = [math]::Round([Windows.Controls.Canvas]::GetLeft($Mark) / $t.W, 4)
        y = [math]::Round([Windows.Controls.Canvas]::GetTop($Mark)  / $t.H, 4)
        s = [math]::Round($Mark.Width / $t.W, 4)
    }
    Save-AcPos $script:AcPos
}
# Which chevron, if any. Only the men on the staff wore one, and only in
# place of a number: a Kommandeur's machine has no individual number at
# all. Get-Appointment already works out what a man is doing from his
# rank and his sorties, so the two agree without a second rule.
function Get-StabChevron {
    param($Pilot, $Career)
    $m = Get-LwMarkings
    if (-not $m) { return $null }
    $appt = ''
    try { $appt = "$(Get-Appointment -Pilot $Pilot -Career $Career)" } catch { }
    $key = switch -Regex ($appt) {
        'Kommodore'   { 'kommandeur2'; break }
        'Kommandeur'  { 'kommandeur';  break }
        'Adjutant'    { 'adjutant';    break }
        'Technischer' { 'technical';   break }
        default       { $null }
    }
    if (-not $key) { return $null }
    Get-MarkFile "$($m.stab.$key)"
}
# The aeroplane with his markings on it. Where each mark starts is a
# fraction of the profile's width, taken off the drawings: the number
# sits just forward of the cross, the Gruppe symbol just aft of it, the
# emblem on the cowling below the exhausts, and the band round the rear
# fuselage. All four can be dragged, because no two of these profiles
# put the cross in quite the same place.
function New-LwAircraft {
    param($Pilot, $Career, $Gruppe)
    $acFile = Get-GruppeAircraftPath -G $Gruppe -Pilot $Pilot
    if (-not $acFile) { return $null }
    $bmp = Load-Image -Path $acFile -DecodeWidth 900
    if (-not $bmp) { return $null }
    $ratio = if ($bmp.PixelWidth -gt 0) { [double]$bmp.PixelHeight / [double]$bmp.PixelWidth } else { 0.29 }
    $acH = $AcW * $ratio
    $wrap = New-Object Windows.Controls.Grid
    $wrap.Width = $AcW; $wrap.Height = $acH; $wrap.HorizontalAlignment = 'Left'; $wrap.Margin = '0,2,0,10'
    $img = New-Object Windows.Controls.Image
    $img.Source = $bmp; $img.Stretch = 'Fill'; $img.Width = $AcW; $img.Height = $acH
    [void]$wrap.Children.Add($img)

    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $AcW; $cv.Height = $acH
    $script:AcPos = Get-AcPos
    $m = Get-LwMarkings
    # the measured placement for THIS profile
    $mp = Get-MarkPositions
    $pk = Split-Path $acFile -Leaf

    # A Bf 110 WEARS LETTERS, NOT A NUMBER, and they are laid out like a
    # bomber's: the Geschwader's two characters, the Balkenkreuz, the
    # individual aircraft letter and the Staffel letter - U8+DH. So it
    # takes a branch of its own rather than the number path with different
    # numbers in it.
    #
    # The individual letter's colour follows the Staffel exactly as the
    # 109's number does, so Get-StaffelColour serves both. The Staffel
    # letter is always black: there is no other colour of one anywhere in
    # the game's rules.
    if ("$($Gruppe.type)" -match '110') {
        $P110 = if ($mp -and $mp.lw -and $mp.lw.profiles110) { $mp.lw.profiles110.$pk } else { $null }
        if ($m -and $P110) {
            $unit = "$($Pilot.unit)"
            $key = 'lw110|' + ($unit -replace '[^A-Za-z0-9]','')
            $col = Get-StaffelColour $Pilot
            $slot = Get-StaffelSlot $Pilot.staffel
            # the Geschwader's two characters, forward of the cross
            $cf = Get-MarkFile "$($m.codes110.$unit)"
            if ($cf) {
                [void](Add-AcImage -Canvas $cv -Key "$key|code" -File $cf `
                                   -DX ([double]$P110.code.dx) -DY ([double]$P110.code.dy) `
                                   -DW ([double]$P110.code.dw) -W $AcW -H $acH `
                                   -Tip "The Geschwader code.")
            }
            # his own letter, aft of the cross
            $L = Get-Ac110Letter $Pilot
            $lf = Get-MarkFile "$($m.letters110.$L.$col)"
            if ($lf) {
                [void](Add-AcImage -Canvas $cv -Key "$key|ind" -File $lf `
                                   -DX ([double]$P110.individual.dx) -DY ([double]$P110.individual.dy) `
                                   -DW ([double]$P110.individual.dw) -W $AcW -H $acH `
                                   -Tip "Your letter, $L, in the $col of the $($Pilot.staffel). Staffel.")
            }
            # and the Staffel's letter behind it, always black
            $sl = "$($m.staffel_letter."$slot")"
            $sf = Get-MarkFile "$($m.letters110.$sl.black)"
            if ($sf) {
                [void](Add-AcImage -Canvas $cv -Key "$key|stf" -File $sf `
                                   -DX ([double]$P110.staffel.dx) -DY ([double]$P110.staffel.dy) `
                                   -DW ([double]$P110.staffel.dw) -W $AcW -H $acH `
                                   -Tip "$($Pilot.staffel). Staffel, which is the letter $sl.")
            }
        }
        [void]$wrap.Children.Add($cv)
        return $wrap
    }
    $P = if ($mp -and $mp.lw -and $mp.lw.profiles) { $mp.lw.profiles.$pk } else { $null }
    # Falling back to a guess would put a marking somewhere plausible and
    # wrong, and nothing on screen would say which it was. A profile that
    # has not been measured gets a bare aeroplane and the note says so.
    if ($m -and $P) {
        $unit = "$($Pilot.unit)"
        $key = 'lw|' + ($unit -replace '[^A-Za-z0-9]','')
        $u = $m.units.$unit
        $col = Get-StaffelColour $Pilot

        # the number, or a chevron in its place for a staff officer
        $chev = Get-StabChevron -Pilot $Pilot -Career $Career
        if ($chev) {
            [void](Add-AcImage -Canvas $cv -Key "$key|chev" -File $chev `
                               -DX ([double]$P.number.dx) -DY ([double]$P.number.dy) `
                               -DW ([double]$P.number.dw) -W $AcW -H $acH `
                               -Tip 'The Stab chevron, worn in place of an individual number.')
        }
        else {
            $n = Get-AcNumber $Pilot
            $nf = Get-MarkFile "$($m.numbers.$n.$col)"
            if ($nf) {
                [void](Add-AcImage -Canvas $cv -Key "$key|num" -File $nf `
                                   -DX ([double]$P.number.dx) -DY ([double]$P.number.dy) `
                                   -DW ([double]$P.number.dw) -W $AcW -H $acH `
                                   -Tip "Your number, in the $col of the $($Pilot.staffel). Staffel.")
            }
        }
        # THE GRUPPE SYMBOL, aft of the cross, taken from the game's own
        # rule FOR THIS UNIT rather than from a table of my own.
        #
        # The table was wrong. It said JG 3, JG 52 and JG 53 wore the
        # wavy line; Me109_PlaneID_2.ms gives III./JG 3, III./JG 51 and
        # III./JG 53 the vertical bar, and names III./JG 2 as the only
        # wavy unit in the file. The three symbols also sit at three
        # different positions - the II. bar at (1500, 202), the III. bar
        # at (1470, 199), the wavy at (1520, 199) - so a single figure
        # was wrong even where the symbol happened to be right. That is
        # what Patrick was looking at.
        #
        # A unit the rules do not name, or name with blank.dds, gets
        # nothing. Its own artwork carries whatever it wore.
        $gu = if ($P.gruppe_by_unit) { $P.gruppe_by_unit.$unit } else { $null }
        if ($gu -and "$($gu.symbol)") {
            $gf = Get-MarkFile "$($m.gruppe."$($gu.symbol)_$col")"
            if (-not $gf) { $gf = Get-MarkFile "$($m.gruppe."$($gu.symbol)_white")" }
            if ($gf) {
                [void](Add-AcImage -Canvas $cv -Key "$key|grp" -File $gf `
                                   -DX ([double]$gu.dx) -DY ([double]$gu.dy) `
                                   -DW ([double]$gu.dw) -W $AcW -H $acH `
                                   -Tip "The $($gu.symbol -replace 'IIIwavy','III') Gruppe symbol.")
            }
        }
        # The Geschwader emblem, but ONLY on the plain factory scheme.
        # Every Gruppe that has a profile of its own already wears its
        # badge in the artwork, and drawing ours over the top gives
        # II./JG 26 two Schlageter shields.
        $ownArt = Test-GruppeOwnProfile $Gruppe
        if ((-not $ownArt) -and $u -and "$($u.emblem)") {
            $ef = Get-MarkFile "$($u.emblem)"
            if ($ef) {
                [void](Add-AcImage -Canvas $cv -Key "$key|emb" -File $ef `
                                   -DX ([double]$P.emblem.dx) -DY ([double]$P.emblem.dy) `
                                   -DW ([double]$P.emblem.dw) -W $AcW -H $acH `
                                   -Tip 'The Geschwader emblem.')
            }
        }
        # JG 53's red band is NOT DRAWN, and that is deliberate.
        #
        # Every other marking here has a MultiSkin rule saying exactly
        # where it goes. The band has none: the game does not place it as
        # a decal at all, it swaps the entire skin, in Me109_Markings.ms:
        #
        #   use ...M109ULF_BARE_DETAIL MARKINGS_JG53.dds, 2048, 2048,
        #       1.000, 1.000, 0, 0 if unit == IJG53 ... and date >= Oct1st1940
        #
        # so there is no position to read. Putting it somewhere plausible
        # is the very thing this whole exercise replaced, and the guess
        # showed: it sat on top of the Gruppe's wavy line. The tile is
        # kept in markings/bands so it can be drawn the day somebody
        # measures where it belongs. The Geschwader still reads from its
        # Gruppe symbol in the meantime.
    }
    [void]$wrap.Children.Add($cv)
    $wrap
}
# =====================================================================
#  What Berlin claimed: the OKW communique, in English, labelled
#
#  Patrick's decision, and it is the right one: an English rendering of
#  what Berlin claimed rather than the German text, with the material
#  labelled for what it is.
#
#  squadronroom/lw/okw.json is built by dev/harvest_okw.py and
#  dev/render_okw.py. The chain is worth knowing before anybody changes
#  a word of what follows.
#
#  There is no free digital edition of the Wehrmachtbericht: both
#  complete printed editions are in copyright as editions, and the
#  Bundesarchiv's own file of them is not digitised. So the text comes
#  from the newspapers that printed it verbatim every morning, out of
#  the Deutsches Zeitungsportal of the Deutsche Digitale Bibliothek,
#  from twelve papers that carry Public Domain Mark 1.0, CC BY-SA 4.0
#  or CC BY-NC-SA 4.0. Most days have five to seven independent
#  readings of the same words.
#
#  The pages are Fraktur and the OCR is imperfect, so NOTHING here is a
#  paraphrase. What is shown is the two figures - British aircraft
#  claimed, German aircraft admitted missing - and the British places
#  named, all pulled out by pattern and checked against a fixed list of
#  real places. A machine paraphrase of a propaganda communique written
#  out in confident English prose is the one thing this must never
#  produce, because it would read as a report of what happened. Each
#  record keeps the German it was read from so any reading can be
#  checked.
#
#  A day with no figures shows nothing rather than a guess.
# =====================================================================
$OkwPath = Join-Path (Join-Path $ModDir 'lw') 'okw.json'
function Get-Okw {
    $out = @()
    if (Test-Path $OkwPath) {
        try { $out = @(Get-Content $OkwPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $out = @() }
    }
    ,$out
}
# ConvertFrom-Json plus the pipeline nests the array several layers deep.
# The RAF paper shipped broken once for exactly this, with a single
# flatten where a loop was needed.
function Get-OkwEntries {
    if ($null -ne $script:OkwCache) { return $script:OkwCache }
    $e = @(Get-Okw)
    while ($e.Count -eq 1 -and ($e[0] -is [System.Array])) { $e = $e[0] }
    $script:OkwCache = $e
    ,$e
}
# The communique for the campaign's day, or the nearest earlier one. The
# same rule the RAF paper uses, and for the same reason: a campaign day
# with no entry should show the last thing that was said, not a blank.
function Get-OkwForDate {
    param($Date)
    $e = Get-OkwEntries
    if (-not $e.Count) { return $null }
    $i = Get-LeadBulletinIndex -Entries $e -Date $Date
    if ($i -lt 0) { return $null }
    $r = $e[$i]
    # A day with no figures can still have named its targets, and what
    # Berlin said it had attacked is worth as much as what it said it had
    # shot down. Only a record with neither is nothing to show.
    if (($null -eq $r.claimed_british) -and ($null -eq $r.admitted_german) -and
        (-not @($r.targets).Count)) { return $null }
    $r
}
# The caption under the heading. Short, unmissable, and on the screen
# every time the column is: a warning at the foot of a page is a warning
# somebody reads after they have already believed the numbers.
$OkwCaption = 'Nazi propaganda. The figures were inflated on purpose.'
# The note is FOLDED AWAY behind a line you click, because open it ran
# to two paragraphs and a source credit and swamped the page it was
# meant to caption. What stays on the screen unfolded is the short
# caption above the figures, which is the part that has to be read
# before the numbers are.
#
# Whether it is open is remembered for the session, so a man who opens
# it once does not have to open it again every time he changes day.
function New-OkwNote {
    param($Rec)
    $b = New-Object Windows.Controls.Border
    $b.Background = B '#241A17'; $b.BorderBrush = B '#7A3E32'; $b.BorderThickness = '3,0,0,0'
    $b.CornerRadius = '0,3,3,0'; $b.Padding = '18,12'; $b.Margin = '0,16,0,0'
    $b.HorizontalAlignment = 'Left'; $b.MaxWidth = 940
    $s = New-Object Windows.Controls.StackPanel

    $hdr = New-Object Windows.Controls.Border
    $hdr.Background = B '#00000000'; $hdr.Cursor = 'Hand'
    $hrow = New-Object Windows.Controls.StackPanel; $hrow.Orientation = 'Horizontal'
    $open = [bool]$script:OkwNoteOpen
    $chev = New-TB -Text $(if ($open) { [string][char]0x25BE } else { [string][char]0x25B8 }) `
                   -Family $CondFam -Size 12 -Colour '#D98E7E' -Bold
    $chev.Margin = '0,0,8,0'
    [void]$hrow.Children.Add($chev)
    [void]$hrow.Children.Add((New-TB -Text 'DISCLAIMER & HISTORICAL CONTEXT' -Family $CondFam -Size 12 -Colour '#D98E7E' -Bold))
    # the hint has to agree with the state it is drawn in, not just with
    # the state the click handler leaves behind
    $hint = New-TB -Text $(if ($open) { 'click to close' } else { 'click to read' }) `
                   -Family $CondFam -Size 11.5 -Colour '#8A7C77'
    $hint.Margin = '12,0,0,0'
    [void]$hrow.Children.Add($hint)
    $hdr.Child = $hrow
    [void]$s.Children.Add($hdr)

    $body = New-Object Windows.Controls.StackPanel
    $body.Visibility = $(if ($open) { 'Visible' } else { 'Collapsed' })
    $t1 = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#C9BDB8' -Text (
        'The Wehrmachtbericht was the daily communique of the German Armed Forces High Command, ' +
        'written by the propaganda department of the OKW and broadcast every day of the war. It was ' +
        'an instrument of the Nazi state and it is not a record of what happened. Victories were ' +
        'inflated on purpose and losses were understated. On 11 August 1940 it claimed 73 British ' +
        'aircraft shot down for 14 German aircraft missing. The real figures were nothing like that, ' +
        'and the men reading it had no way of knowing.')
    $t1.Margin = '0,10,0,0'; $t1.MaxWidth = 880; $t1.LineHeight = 18
    [void]$body.Children.Add($t1)
    $t2 = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#C9BDB8' -Text (
        'It is here for one reason: this is what a Luftwaffe pilot was told that morning, and the ' +
        'distance between what he was told and what his own Gruppe''s diary records is the honest ' +
        'thing to put in front of you. It is shown to be understood, not believed, and nothing in ' +
        'it is endorsed.')
    $t2.Margin = '0,8,0,0'; $t2.MaxWidth = 880; $t2.LineHeight = 18
    [void]$body.Children.Add($t2)
    if ($Rec) {
        $src = New-TB -Wrap -Family 'Segoe UI' -Size 11.5 -Colour '#8A7C77' -Text (
            "Rendered into English from the communique as printed in $($Rec.paper), " +
            "$(Format-ShortDate "$($Rec.date)"), held by the Deutsches Zeitungsportal of the " +
            "Deutsche Digitale Bibliothek under $($Rec.licence).")
        $src.Margin = '0,10,0,0'; $src.MaxWidth = 880; $src.FontStyle = 'Italic'
        [void]$body.Children.Add($src)
    }
    [void]$s.Children.Add($body)

    # The two controls the handler needs travel in the Tag. A scriptblock
    # cannot simply close over them: .GetNewClosure() gives it its own
    # module scope and a $script: write inside one never reaches the Room,
    # which is what made it impossible to join a Gruppe for a while.
    $hdr.Tag = @{ Body = $body; Chev = $chev; Hint = $hint }
    $hdr.Add_MouseLeftButtonUp({
        param($sender, $e)
        $t = $sender.Tag
        $was = ($t.Body.Visibility -eq 'Visible')
        $t.Body.Visibility = $(if ($was) { 'Collapsed' } else { 'Visible' })
        $t.Chev.Text = $(if ($was) { [string][char]0x25B8 } else { [string][char]0x25BE })
        $t.Hint.Text = $(if ($was) { 'click to read' } else { 'click to close' })
        $script:OkwNoteOpen = (-not $was)
    })
    $b.Child = $s
    $b
}
# =====================================================================
#  The Morgenmeldung: the German side's morning bulletin
#
#  Patrick asked where the German morning bulletin was, and said the two
#  sides must be the same. They now are, in shape: same cream page, same
#  masthead, same dateline row, same two columns, same unread strip on the
#  ready room. What is ON the page is necessarily different, and the
#  reason is worth writing down because somebody will otherwise try to
#  "fix" it by pointing the German side at paper.json.
#
#  paper.json is 104 real front pages from New Zealand papers under
#  CC BY-NC-SA. It is Allied press. Running it at a Luftwaffe pilot as HIS
#  morning paper would be nonsense.
#
#  The obvious counterpart is the Wehrmachtbericht, the OKW's daily
#  communique. It is exactly the right thing and it is not in this repo,
#  and writing German communiques myself and putting OKW's name on them
#  would be inventing propaganda and passing it off as the record. So the
#  page is built from two things that are both true:
#
#    THE LEFT COLUMN is the campaign's own figures, read out of the German
#    diary table in the save by Get-GruppeDiary. Sorties put up, aircraft
#    lost, claims by British type, for the whole Jagdwaffe and for your own
#    Gruppe. It is not history, it is the war the player is actually
#    flying, which is the one thing on the page that is his.
#
#    THE RIGHT COLUMN is the British press of that date, out of the same
#    paper.json, and it says so: headed WAS LONDON MELDET and captioned as
#    the British reports monitored that morning. Monitoring the enemy's
#    press and broadcasts is what both sides actually did, so it earns its
#    place rather than being a reuse of convenience.
#
#  Nothing on this page claims to be a German communique.
# =====================================================================
# The day's figures. Cumulative over the campaign, because that is what
# the save records: there is no per-day breakdown in the German table.
function Get-LwDayReport {
    param($Pilot)
    $rows = @(Get-GruppeDiary)
    $all = @(Get-LwGruppen)
    $out = @{
        Rows = $rows.Count; Launched = 0; AcLost = 0; AcDamaged = 0; PilotsLost = 0
        Kills = (New-Object int[] 6); Total = 0
        Mine = $null; MineUnit = "$($Pilot.unit)"; InLine = 0; Fighters = $all.Count
    }
    # Only the fighter Gruppen. The diary carries the bombers and the
    # Stukas too, and folding those in would credit the Jagdwaffe with
    # somebody else's sorties.
    $fighterIdx = @{}
    foreach ($q in $all) { if ($null -ne $q.sqidx) { $fighterIdx["$([int]$q.sqidx)"] = $q } }
    foreach ($r in $rows) {
        if (-not $fighterIdx.ContainsKey("$([int]$r.Idx)")) { continue }
        $out.Launched   += [int]$r.Launched
        $out.AcLost     += [int]$r.AcLost
        $out.AcDamaged  += [int]$r.AcDamaged
        $out.PilotsLost += [int]$r.PilotsLost
        for ($j = 0; $j -lt 6; $j++) { $out.Kills[$j] += [int]$r.Kills[$j]; $out.Total += [int]$r.Kills[$j] }
    }
    $g = $all | Where-Object { "$($_.unit)" -eq "$($Pilot.unit)" } | Select-Object -First 1
    if ($g) { $out.Mine = Get-GruppeRecord $g.sqidx }
    $out.InLine = @($all | Where-Object { Test-GruppeInLine $_ $script:CampaignDate }).Count
    $out
}
# The line the ready room's strip carries, and the page's own headline.
# Built from the largest thing that is actually true this morning, so a
# quiet campaign says so instead of shouting.
function Get-LwLead {
    param($Rep, $Pilot)
    if ($Rep.Mine -and [int]$Rep.Mine.Total -gt 0) {
        return "$($Rep.MineUnit) meldet $([int]$Rep.Mine.Total) Abschuesse"
    }
    if ([int]$Rep.Total -gt 0) {
        return "Jagdwaffe meldet $([int]$Rep.Total) Abschuesse ueber dem Kanal"
    }
    if ([int]$Rep.Launched -gt 0) {
        return "$([int]$Rep.Launched) Feindfluege geflogen, keine Abschuesse gemeldet"
    }
    'Die Gruppen stehen in Bereitschaft'
}
# Today's report counts as unread until it has been opened. The RAF flag
# keys on the front page's own date because the papers are dated; there
# is one report a day here, so it keys on the campaign date. State is
# split per side, so the two flags cannot tread on each other.
function Get-UnreadMeldung {
    param($Pilot)
    if (-not $script:CampaignDate) { return $null }
    $d = $script:CampaignDate.ToString('yyyy-MM-dd')
    $seen = $null
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'paperRead')) { $seen = "$($Pilot.paperRead)" }
    if ($seen -and ($seen -eq $d)) { return $null }
    $d
}
function Show-Morgenmeldung {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'paper'))
    Show-ChromeButtons $true
    $h = C 'HdrSquadron'; if ($h) { $h.Text = "$($Pilot.unit)" }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "LUFTWAFFE  $([char]0x2022)  MORGENMELDUNG" }

    $rep = Get-LwDayReport -Pilot $Pilot
    $lead = Get-LwLead -Rep $rep -Pilot $Pilot
    # opening it is what marks it read, exactly as the RAF page does
    $today = Get-UnreadMeldung -Pilot $Pilot
    if ($today) { Set-BulletinRead -Pilot $Pilot -Date $today }

    $paper = New-Object Windows.Controls.Border
    $paper.Background = B '#E9E0CA'; $paper.CornerRadius = '2'; $paper.Padding = '40,26,40,34'
    $paper.MaxWidth = 940; $paper.HorizontalAlignment = 'Left'
    $paper.BorderBrush = B '#2A2418'; $paper.BorderThickness = '1'
    $col = New-Object Windows.Controls.StackPanel

    # ---- masthead, the same furniture as the RAF page ----
    [void]$col.Children.Add((New-Rule '#1A1712' 3))
    $mh = New-TB -Text 'Morgenmeldung' -Family "Old English Text MT, Blackadder ITC, Georgia, 'Times New Roman', serif" -Size 50 -Colour '#141109'
    $mh.HorizontalAlignment = 'Center'; $mh.Margin = '0,6,0,2'
    [void]$col.Children.Add($mh)
    [void]$col.Children.Add((New-Rule '#1A1712' 1))

    $dstr = if ($script:CampaignDate) { $script:CampaignDate.ToString('dddd, d MMMM yyyy').ToUpper() } else { 'DIE LUFTSCHLACHT UM ENGLAND, 1940' }
    $dl = New-Object Windows.Controls.Grid; $dl.Margin = '0,5,0,5'
    foreach ($w in @('*','*','*')) { $cd=New-Object Windows.Controls.ColumnDefinition; $cd.Width=New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)); [void]$dl.ColumnDefinitions.Add($cd) }
    $dLeft  = New-TB -Text "$($Pilot.unit)" -Family $CondFam -Size 11.5 -Colour '#4A4436' -Bold; $dLeft.VerticalAlignment='Center'
    $dCent  = New-TB -Text ("GEFECHTSSTAND $("$($Pilot.base)".ToUpper())") -Family $CondFam -Size 11.5 -Colour '#4A4436' -Bold; $dCent.HorizontalAlignment='Center'; $dCent.VerticalAlignment='Center'
    $dRight = New-TB -Text $dstr -Family $CondFam -Size 11.5 -Colour '#4A4436' -Bold; $dRight.HorizontalAlignment='Right'; $dRight.VerticalAlignment='Center'
    [Windows.Controls.Grid]::SetColumn($dLeft,0); [Windows.Controls.Grid]::SetColumn($dCent,1); [Windows.Controls.Grid]::SetColumn($dRight,2)
    [void]$dl.Children.Add($dLeft); [void]$dl.Children.Add($dCent); [void]$dl.Children.Add($dRight)
    [void]$col.Children.Add($dl)
    [void]$col.Children.Add((New-Rule '#1A1712' 2.5))

    # ---- two columns: the front's own figures | what London is saying ----
    $bodyG = New-Object Windows.Controls.Grid; $bodyG.Margin = '0,12,0,0'
    $g0=New-Object Windows.Controls.ColumnDefinition; $g0.Width=New-Object Windows.GridLength(2,([Windows.GridUnitType]::Star))
    $g1=New-Object Windows.Controls.ColumnDefinition; $g1.Width=New-Object Windows.GridLength(26)
    $g2=New-Object Windows.Controls.ColumnDefinition; $g2.Width=New-Object Windows.GridLength(1.15,([Windows.GridUnitType]::Star))
    [void]$bodyG.ColumnDefinitions.Add($g0); [void]$bodyG.ColumnDefinitions.Add($g1); [void]$bodyG.ColumnDefinitions.Add($g2)

    $lc = New-Object Windows.Controls.StackPanel
    $hl = New-TB -Text $lead -Family 'Georgia, Cambria, serif' -Size 31 -Colour '#120F08' -Bold -Wrap
    $hl.LineHeight = 34
    [void]$lc.Children.Add($hl)
    [void]$lc.Children.Add((New-Rule '#7A5E2E' 1))

    $bins = Get-KillBins $Pilot
    $byType = @()
    for ($k = 0; $k -lt $bins.Count; $k++) { if ([int]$rep.Kills[$k] -gt 0) { $byType += "$([int]$rep.Kills[$k]) $($bins[$k])" } }
    # A zero is a sentence, not a number. "0 machines have not come back
    # and 0 were brought home damaged. 0 pilots are gone" is what counting
    # into a template reads like, and it is worse than saying nothing.
    $para = @()
    if ([int]$rep.Launched -gt 0) {
        $claims = if ([int]$rep.Total -gt 0) { "and claim $([int]$rep.Total) British aircraft" + $(if ($byType.Count) { ": $($byType -join ', ')." } else { '.' }) }
                  else { 'and have nothing to claim for them yet.' }
        $para += "The fighter Gruppen have put up $([int]$rep.Launched) sorties in this campaign $claims"
        $loss = @()
        if ([int]$rep.AcLost -gt 0)     { $loss += "$([int]$rep.AcLost) machines have not come back" }
        if ([int]$rep.AcDamaged -gt 0)  { $loss += "$([int]$rep.AcDamaged) were brought home damaged" }
        if ([int]$rep.PilotsLost -gt 0) { $loss += "$([int]$rep.PilotsLost) pilots are gone" }
        $para += $(if ($loss.Count) { 'Against that, ' + ($loss -join ', ') + '.' } else { 'Nothing has been lost.' })
    } else {
        $para += 'Nothing has been flown from this Gefechtsstand yet. The figures fill in as the campaign runs.'
    }
    if ($rep.Mine -and [int]$rep.Mine.Launched -gt 0) {
        $mb = @()
        for ($k = 0; $k -lt $bins.Count; $k++) { if ([int]$rep.Mine.Kills[$k] -gt 0) { $mb += "$([int]$rep.Mine.Kills[$k]) $($bins[$k])" } }
        $mine = "$($rep.MineUnit) itself has flown $([int]$rep.Mine.Launched) of them"
        $mine += if ([int]$rep.Mine.Total -gt 0) { ", for $([int]$rep.Mine.Total) claims" + $(if ($mb.Count) { " ($($mb -join ', '))" } else { '' }) } else { ' without a claim so far' }
        $ml = @()
        if ([int]$rep.Mine.AcLost -gt 0)     { $ml += "$([int]$rep.Mine.AcLost) aircraft" }
        if ([int]$rep.Mine.PilotsLost -gt 0) { $ml += "$([int]$rep.Mine.PilotsLost) pilots" }
        $mine += $(if ($ml.Count) { " and the loss of $($ml -join ' and ')." } else { ' and has lost nothing.' })
        $para += $mine
    }
    $para += "$($rep.InLine) of the $($rep.Fighters) fighter Gruppen stand on the Kanalfront this morning."
    $bd = New-TB -Text ($para -join '  ') -Family 'Georgia, Cambria, serif' -Size 15 -Colour '#2A2620' -Wrap
    $bd.LineHeight = 24; $bd.Margin = '0,8,0,0'; $bd.TextAlignment = 'Justify'
    [void]$lc.Children.Add($bd)
    $src = New-TB -Text ("$([char]0x2014) from the campaign's own Gruppen diary, not from the record of 1940") `
                  -Family 'Georgia, Cambria, serif' -Size 12.5 -Colour '#6B6250'
    $src.Margin = '0,10,0,0'; $src.FontStyle = 'Italic'
    [void]$lc.Children.Add($src)
    [Windows.Controls.Grid]::SetColumn($lc,0); [void]$bodyG.Children.Add($lc)

    $vr = New-Object Windows.Controls.Border; $vr.Width=1; $vr.Background=B '#3A3324'; $vr.HorizontalAlignment='Center'
    [Windows.Controls.Grid]::SetColumn($vr,1); [void]$bodyG.Children.Add($vr)

    # What Berlin claimed that morning, in English, and said plainly to
    # be propaganda. This column used to carry the British press instead,
    # which was a stopgap: it was the only thing in the repo that was
    # both dated and honest. Patrick's decision was to go and get the
    # actual OKW communique, render it in English, and label it.
    $okw = Get-OkwForDate $script:CampaignDate
    $sc = New-Object Windows.Controls.StackPanel
    [void]$sc.Children.Add((New-TB -Text 'WHAT BERLIN CLAIMED' -Family $CondFam -Size 12 -Colour '#8C3A2A' -Bold))
    [void]$sc.Children.Add((New-Rule '#8C3A2A' 1))
    # The caption sits ABOVE the figures, not under them. A warning at
    # the foot of a column is a warning somebody reads after they have
    # already believed the numbers.
    $capTop = New-TB -Wrap -Family 'Georgia, serif' -Size 12 -Colour '#8C3A2A' -Text $OkwCaption
    $capTop.FontStyle = 'Italic'; $capTop.Margin = '0,0,0,12'
    [void]$sc.Children.Add($capTop)
    if ($okw) {
        if ($null -ne $okw.claimed_british) {
            $k1 = New-TB -Text "$([int]$okw.claimed_british) British aircraft" -Family 'Georgia, serif' -Size 21 -Colour '#1C1810' -Bold -Wrap
            [void]$sc.Children.Add($k1)
            $k1b = New-TB -Text 'claimed shot down' -Family $CondFam -Size 11.5 -Colour '#6B6250' -Bold
            $k1b.Margin = '0,0,0,12'
            [void]$sc.Children.Add($k1b)
        }
        if ($null -ne $okw.admitted_german) {
            $k2 = New-TB -Text "$([int]$okw.admitted_german) German aircraft" -Family 'Georgia, serif' -Size 21 -Colour '#1C1810' -Bold -Wrap
            [void]$sc.Children.Add($k2)
            $k2b = New-TB -Text 'admitted missing' -Family $CondFam -Size 11.5 -Colour '#6B6250' -Bold
            $k2b.Margin = '0,0,0,12'
            [void]$sc.Children.Add($k2b)
        }
        $tg = @($okw.targets)
        if ($tg.Count) {
            $tt = New-TB -Wrap -Family 'Georgia, serif' -Size 13.5 -Colour '#2A2620' -Text (
                'Targets named: ' + (($tg | Select-Object -First 7) -join ', ') + '.')
            $tt.Margin = '0,0,0,10'; $tt.LineHeight = 18
            [void]$sc.Children.Add($tt)
        }
        # The communique is dated the morning AFTER the fighting it
        # describes, because that is when the papers carried it. Saying
        # so stops the figures being read against the wrong day.
        $dl = New-TB -Wrap -Family $CondFam -Size 11 -Colour '#7A6A62' -Text (
            "Communique of $(Format-ShortDate "$($okw.date)"), covering the day before.")
        [void]$sc.Children.Add($dl)
    }
    else {
        [void]$sc.Children.Add((New-TB -Wrap -Family 'Georgia, serif' -Size 13 -Colour '#4A4436' -Text (
            'No communique has been read for this date. Nothing is shown rather than a guess.')))
    }
    [Windows.Controls.Grid]::SetColumn($sc,2); [void]$bodyG.Children.Add($sc)

    [void]$col.Children.Add($bodyG)
    [void]$col.Children.Add((New-Rule '#1A1712' 2))
    $paper.Child = $col
    [void]$script:Stage.Children.Add($paper)
    # The full note, on the page every time, below the sheet where there
    # is room for it to be read properly.
    [void]$script:Stage.Children.Add((New-OkwNote $okw))
}
function Show-ReadyRoom {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'dispersal'))
    Show-ChromeButtons $true
    $unit = "$($Pilot.unit)"
    # The Gruppe's own record out of the order of battle. Looked up HERE,
    # at the top, because it is wanted by three blocks below and the first
    # of them is the aeroplane. It used to be looked up further down, after
    # the aircraft block had already asked for it, so $g was still null
    # there and the Ready Room drew no aeroplane at all while the RAF
    # dispersal drew its Spitfire. That is one of the differences Patrick
    # was looking at.
    $g = @(Get-LwGruppen) | Where-Object { "$($_.unit)" -eq $unit } | Select-Object -First 1
    $h = C 'HdrSquadron'; if ($h) { $h.Text = $unit }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "LUFTWAFFE  $([char]0x2022)  LUFTFLOTTE $($Pilot.luftflotte)" }

    $sessions = Get-Sessions
    $career = Get-Career $Pilot $sessions
    $honours = @(Get-LwHonours -Pilot $Pilot -Career $career)
    $Pilot = Update-CareerRecord -Pilot $Pilot -Career $career -Honours $honours

    $base = "$($Pilot.base)".ToUpper()
    $eyebrow = if ($script:CampaignDate) { "$base  $([char]0x2022)  $($script:CampaignDate.ToString('dddd d MMMM yyyy').ToUpper())" } else { $base }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow $eyebrow -Title "$unit at readiness"))

    # This morning's Meldung, if he has not read it. Same strip, same
    # newspaper block, same click-to-open as the RAF dispersal: it carries
    # the line itself rather than "you have unread news", because the line
    # is the reason to go and read it.
    $mday = Get-UnreadMeldung -Pilot $Pilot
    if ($mday) {
        $nb = New-Object Windows.Controls.Border
        $nb.Background = B '#1A1710'; $nb.BorderBrush = $script:BrassBrush
        $nb.BorderThickness = '3,0,0,0'; $nb.CornerRadius = '0,3,3,0'
        $nb.Padding = '16,12'; $nb.Margin = '0,0,0,20'
        $nb.HorizontalAlignment = 'Stretch'; $nb.Cursor = 'Hand'
        $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
        $ic = New-NewspaperIcon
        $ic.Margin = '2,3,18,0'; $ic.VerticalAlignment = 'Top'
        [void]$row.Children.Add($ic)
        $ns = New-Object Windows.Controls.StackPanel
        $eb = New-TB -Text ('DIE MORGENMELDUNG  ' + [char]0x2022 + '  ' + (Format-ShortDate $mday)) `
                     -Family $CondFam -Size 11.5 -Colour '#C8973F' -Bold
        [void]$ns.Children.Add($eb)
        $hl0 = New-TB -Text (Get-LwLead -Rep (Get-LwDayReport -Pilot $Pilot) -Pilot $Pilot) -Family $SerifFam -Size 17 -Colour '#E9E3D4' -Wrap
        $hl0.Margin = '0,4,0,0'
        [void]$ns.Children.Add($hl0)
        $go = New-TB -Text 'not yet read - click to open it' -Family $CondFam -Size 12 -Colour '#6F828C'
        $go.Margin = '0,5,0,0'
        [void]$ns.Children.Add($go)
        [void]$row.Children.Add($ns)
        $nb.Child = $row
        $nb.Add_MouseLeftButtonUp({ param($s,$e) Show-Tab 'paper' })
        [void]$script:Stage.Children.Add($nb)
    }

    # the man himself
    # -22 at the foot: New-Frame carries a 26px bottom margin of its own,
    # for the roster grid it was built for, and left alone it opens a hole
    # between the photograph and the counters
    $hero = New-Object Windows.Controls.StackPanel; $hero.Orientation = 'Horizontal'; $hero.Margin = '0,-6,0,-22'
    [void]$hero.Children.Add((New-Frame -Pilot $Pilot -IsPlayer))
    $d = New-Object Windows.Controls.StackPanel; $d.Margin = '30,4,0,0'; $d.VerticalAlignment = 'Top'
    [void]$d.Children.Add((New-TB -Text "$($Pilot.pilot)" -Family $SerifFam -Size 30 -Colour '#E9E3D4' -Bold))
    $appt = Get-Appointment -Pilot $Pilot -Career $career
    $line = "$($Pilot.rank)   $([char]0x2022)   $appt   $([char]0x2022)   $($Pilot.staffel). Staffel"
    $lt = New-TB -Text $line -Family $CondFam -Size 15 -Colour '#9FB0B8'; $lt.Margin = '0,7,0,0'
    [void]$d.Children.Add($lt)
    $chipRow = New-Object Windows.Controls.StackPanel; $chipRow.Orientation = 'Horizontal'; $chipRow.Margin = '0,14,0,0'
    $rbf = Get-RankBadgeFile "$($Pilot.rank)"
    if ($rbf) {
        $cuff = New-BadgeImage -File $rbf -Height 52 -Tip "$($Pilot.rank)"
        if ($cuff) { $cuff.Margin = '0,0,10,0'; [void]$chipRow.Children.Add($cuff) }
    }
    # The pilot's badge, which is the German answer to the RAF's wings.
    # Taller than it is wide where the wings are the opposite, so at the
    # same 52 pixels it reads as much the smaller thing; 62 puts them
    # about level by area.
    $fb = New-BadgeImage -File 'pilot-badge.png' -Height 62 -Tip 'Flugzeugfuehrerabzeichen, the pilot badge'
    if ($fb) { [void]$chipRow.Children.Add($fb) }
    if ($chipRow.Children.Count -gt 0) { [void]$d.Children.Add($chipRow) }
    $hr = New-LwHonourRow $honours
    if ($hr) { $hr.Margin = '0,14,0,0'; [void]$d.Children.Add($hr) }
    [void]$hero.Children.Add($d)

    # Anyone who did not come back is replaced first, so the men drawn
    # below are the men on strength today.
    $lost = @(Update-CrewLosses -Pilot $Pilot -Sorties ([int]$career.sorties))
    if ($lost.Count) {
        $p2 = Get-Pilot; if ($p2) { $Pilot = $p2 }
    }

    # THE REST OF THE CREW, beside him and in the same frame.
    #
    # New-Frame takes a man and reads .pilot and .portrait, which is why a
    # crew member's name field is `pilot` and not `name`: one spelling
    # serves the player, his crew and every man on the Staffel roster.
    # Without -IsPlayer the frame comes out dark rather than brass, which
    # says who the screen is about without a label doing it.
    foreach ($m in (Get-Crew $Pilot)) {
        $cc = Get-CrewCareer -Member $m -Pilot $Pilot -Sorties ([int]$career.sorties) -Hours ([double]$career.hours)
        [void]$hero.Children.Add((New-Frame -Pilot $m))
        $cd = New-Object Windows.Controls.StackPanel; $cd.Margin = '30,4,0,0'; $cd.VerticalAlignment = 'Top'
        [void]$cd.Children.Add((New-TB -Text "$($m.pilot)" -Family $SerifFam -Size 30 -Colour '#E9E3D4' -Bold))
        $cl = "$($cc.rank)   $([char]0x2022)   $(Get-CrewAppointment -Member $m -Career $cc)"
        $clt = New-TB -Text $cl -Family $CondFam -Size 15 -Colour '#9FB0B8'; $clt.Margin = '0,7,0,0'
        [void]$cd.Children.Add($clt)
        $cRow = New-Object Windows.Controls.StackPanel; $cRow.Orientation = 'Horizontal'; $cRow.Margin = '0,14,0,0'
        $crb = Get-RankBadgeFile "$($cc.rank)"
        if ($crb) {
            $ccuff = New-BadgeImage -File $crb -Height 52 -Tip "$($cc.rank)"
            if ($ccuff) { $ccuff.Margin = '0,0,10,0'; [void]$cRow.Children.Add($ccuff) }
        }
        # NOT the pilot's badge. The Flugzeugfuehrerabzeichen is for a man
        # who flies the aeroplane; the man in the back wore the
        # Fliegerschuetzenabzeichen, and giving him the pilot's badge would
        # be as wrong as putting RAF wings on an air gunner.
        $cb = New-BadgeImage -File 'crew-badge.png' -Height 62 -Tip 'Fliegerschuetzenabzeichen, the air crew badge'
        if ($cb) { [void]$cRow.Children.Add($cb) }
        if ($cRow.Children.Count -gt 0) { [void]$cd.Children.Add($cRow) }
        $chr = New-LwHonourRow (@(Get-CrewHonours -Member $m -Career $cc))
        if ($chr) { $chr.Margin = '0,14,0,0'; [void]$cd.Children.Add($chr) }
        $inv = New-TB -Wrap -Family 'Segoe UI' -Size 11.5 -Colour '#6F828C' -Text (
            'Invented. The game keeps no record of a second crewman, so his rank, ' +
            'his sorties and his decorations are this Room''s and not the save''s.')
        $inv.Margin = '0,12,0,0'; $inv.MaxWidth = 260
        [void]$cd.Children.Add($inv)
        [void]$hero.Children.Add($cd)
    }
    [void]$script:Stage.Children.Add($hero)

    # WHO WAS LOST, named, with the day and who took his place.
    foreach ($l in $lost) {
        $lb = New-Object Windows.Controls.Border
        $lb.Background = B '#241A17'; $lb.BorderBrush = B '#7A3E32'
        $lb.BorderThickness = '3,0,0,0'; $lb.CornerRadius = '0,3,3,0'
        $lb.Padding = '16,12'; $lb.Margin = '0,0,0,18'
        $lb.HorizontalAlignment = 'Left'; $lb.MaxWidth = 940
        $txt = "$(Short-Rank "$($l.rank)") $($l.pilot) $($l.how) on $(Format-ShortDate "$($l.date)")."
        if ("$($l.replacedBy)") { $txt += "  $($l.replacedBy) has taken the back seat." }
        else { $txt += '  There is nobody left in the Staffel to replace him.' }
        $lt2 = New-TB -Wrap -Family 'Segoe UI' -Size 13 -Colour '#D9C9C4' -Text $txt
        $lt2.MaxWidth = 880
        $lb.Child = $lt2
        [void]$script:Stage.Children.Add($lb)
    }

    # the counters
    $tiles = New-Object Windows.Controls.StackPanel; $tiles.Orientation = 'Horizontal'; $tiles.Margin = '0,0,0,26'
    [void]$tiles.Children.Add((New-Stat 'SORTIES' "$($career.sorties)"))
    [void]$tiles.Children.Add((New-Stat 'FLYING HOURS' "$($career.hours)"))
    [void]$tiles.Children.Add((New-Stat 'RANK' (Short-Rank "$($Pilot.rank)")))
    $awTile = if ($honours.Count) { $honours[$honours.Count-1] } else { 'None yet' }
    [void]$tiles.Children.Add((New-Stat 'AWARDS' $awTile -Chip (New-LwHonourRow $honours -Scale 0.30)))
    [void]$script:Stage.Children.Add($tiles)
    if ($career.next) {
        $nx = New-TB -Text "Next promotion: $($career.next) at $($career.nextAt) sorties." -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C'
        $nx.Margin = '0,-16,0,22'
        [void]$script:Stage.Children.Add($nx)
    }

    # First-timer's orders, the same box the RAF dispersal puts up until a
    # sortie is in the book. A man posted to a Gruppe has no more idea
    # what to press than a man posted to a squadron does.
    if ([int]$career.sorties -eq 0) {
        $ord = New-Object Windows.Controls.Border
        $ord.Background = B '#1E2A18'; $ord.BorderBrush = B '#4A6B3A'; $ord.BorderThickness = '1'
        $ord.CornerRadius = '3'; $ord.Padding = '16,12'; $ord.Margin = '0,-14,0,24'; $ord.HorizontalAlignment = 'Left'; $ord.MaxWidth = 760
        $os2 = New-Object Windows.Controls.StackPanel
        [void]$os2.Children.Add((New-TB -Text 'YOUR ORDERS' -Family $CondFam -Size 12 -Colour '#8FB56A' -Bold))
        $ot = New-TB -Text "Press PLAY (top right). In the game, start or continue the Campaign as the Luftwaffe and fly the day. When you come back here your first Feindflug will be in the Flugbuch." -Family 'Segoe UI' -Size 13.5 -Colour '#C9D4CE' -Wrap
        $ot.Margin = '0,6,0,0'
        [void]$os2.Children.Add($ot)
        $ord.Child = $os2
        [void]$script:Stage.Children.Add($ord)
    }

    # his aircraft, with his markings on it
    $ac = New-LwAircraft -Pilot $Pilot -Career $career -Gruppe $g
    if ($ac) {
        # Bare on the page, exactly as New-Aircraft puts the Spitfire and
        # the Hurricane. It was in a Panel-coloured card with a border, and
        # that read as the aeroplane sitting on a grey box while the RAF's
        # sits on the room itself. Same Room, same treatment.
        [void]$script:Stage.Children.Add($ac)
        $col = Get-StaffelColour $Pilot
        $parts = @()
        $chev = Get-StabChevron -Pilot $Pilot -Career $career
        if ($chev) { $parts += 'your Stab chevron, worn in place of a number' }
        else { $parts += "your number $(Get-AcNumber $Pilot) in the $col of the $($Pilot.staffel). Staffel" }
        $mk = Get-LwMarkings
        $u = if ($mk) { $mk.units."$($Pilot.unit)" } else { $null }
        $mp2 = Get-MarkPositions
        $pk2 = Split-Path (Get-GruppeAircraftPath -G $g -Pilot $Pilot) -Leaf
        $P2 = if ($mp2 -and $mp2.lw -and $mp2.lw.profiles) { $mp2.lw.profiles.$pk2 } else { $null }
        $ownArt = Test-GruppeOwnProfile $g
        $gu = if ($P2 -and $P2.gruppe_by_unit) { $P2.gruppe_by_unit."$($Pilot.unit)" } else { $null }
        if ($gu -and "$($gu.symbol)") { $parts += 'the Gruppe symbol aft of the cross' }
        if ((-not $ownArt) -and $u -and "$($u.emblem)") { $parts += 'the Geschwader emblem on the cowling' }

        if ($ownArt) { $parts += 'and the Geschwader badge already in its paint' }
        $note = New-TB -Wrap -Family 'Segoe UI' -Size 12 -Colour '#6F828C' -Text (
            "$($Pilot.unit) in its own markings, with " + ($parts -join ', ') + '. ' +
            'Only the number was ever the pilot''s own; the rest followed the unit and the appointment. ' +
            'Each can be dragged to sit better on the aeroplane, and the wheel sizes it. Where you put ' +
            'them is remembered.')
        $note.Margin = '0,-4,0,18'; $note.MaxWidth = 860; $note.HorizontalAlignment = 'Left'
        [void]$script:Stage.Children.Add($note)
    }

    # where the Gruppe stands
    if ($g) {
        $rec = New-Object Windows.Controls.Border
        $rec.Background = Res 'Panel'; $rec.BorderBrush = Res 'Rule'; $rec.BorderThickness = '1'
        $rec.CornerRadius = '3'; $rec.Padding = '20,16'; $rec.Margin = '0,0,0,22'
        $rec.HorizontalAlignment = 'Left'; $rec.MaxWidth = 1080
        $rs = New-Object Windows.Controls.StackPanel
        [void]$rs.Children.Add((New-TB -Text 'THE GRUPPE' -Family $CondFam -Size 13 -Colour '#C8973F' -Bold))
        $txt = "$($g.unit), $($g.type), of $($g.geschwader) in Luftflotte $($g.luftflotte). " +
               "At $($g.field) since $(Format-LwDate "$($g.activation)"). " +
               "The campaign rates it $($g.skill.ToLower()) with $($g.fatigue.ToLower()) fatigue."
        $t = New-TB -Wrap -Family 'Segoe UI' -Size 13 -Colour '#9FB0B8' -Text $txt
        $t.Margin = '0,8,0,0'; $t.MaxWidth = 900
        [void]$rs.Children.Add($t)
        $rec.Child = $rs
        [void]$script:Stage.Children.Add($rec)
    }

    # What the Gruppe has done in THIS campaign, out of the game's own
    # German diary. Not history: this is the war the player is flying.
    $gr = if ($g) { Get-GruppeRecord $g.sqidx } else { $null }
    if ($gr) {
        $card = New-Object Windows.Controls.Border
        $card.Background = Res 'Panel'; $card.BorderBrush = Res 'Rule'; $card.BorderThickness = '1'
        $card.CornerRadius = '3'; $card.Padding = '20,16'; $card.Margin = '0,0,0,22'
        $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 1080
        $cs = New-Object Windows.Controls.StackPanel
        [void]$cs.Children.Add((New-TB -Text 'THE GRUPPE IN THIS CAMPAIGN' -Family $CondFam -Size 13 -Colour '#C8973F' -Bold))
        $gb = Get-KillBins $Pilot
        $byType = @()
        for ($k = 0; $k -lt $gb.Count; $k++) { if ([int]$gr.Kills[$k] -gt 0) { $byType += "$([int]$gr.Kills[$k]) x $($gb[$k])" } }
        # Zeros written out as sentences, not counted into a template.
        # "0 aircraft lost and 0 damaged, 0 pilots gone" is what the
        # template produced and it reads like a form rather than a report.
        $ls = @()
        if ([int]$gr.AcLost -gt 0)     { $ls += "$($gr.AcLost) aircraft lost" }
        if ([int]$gr.AcDamaged -gt 0)  { $ls += "$($gr.AcDamaged) damaged" }
        if ([int]$gr.PilotsLost -gt 0) { $ls += "$($gr.PilotsLost) pilots gone" }
        $t1 = "$($gr.Actions) action$(if ($gr.Actions -ne 1) { 's' } else { '' }) flown, $($gr.Launched) sorties put up. " +
              $(if ($ls.Count) { ($ls -join ', ') + '. ' } else { 'Nothing lost. ' }) +
              $(if ($gr.Total -gt 0) { "Claims: $($gr.Total), $($byType -join ', ')." } else { 'No claims yet.' })
        $tb1 = New-TB -Wrap -Family 'Segoe UI' -Size 13 -Colour '#9FB0B8' -Text $t1
        $tb1.Margin = '0,8,0,0'; $tb1.MaxWidth = 900
        [void]$cs.Children.Add($tb1)
        $card.Child = $cs
        [void]$script:Stage.Children.Add($card)
    }

    # the men he flies with
    $roster = @(Get-LwRoster -Unit $unit)
    if ($roster.Count) {
        [void]$script:Stage.Children.Add((New-TB -Text 'THE STAFFEL' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
        $nHist = @($roster | Where-Object { $_.historical }).Count
        $note = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Text $(
            if ($nHist) {
                "The $nHist name$(if ($nHist -ne 1) { 's' } else { '' }) in white below flew with this unit and held the appointment shown, " +
                'and that is all that is claimed for them: no score and no ending, because those are matters of ' +
                'record and the record is not mine to write. Everyone else is invented, scores and fates and all. ' +
                'There is no German equivalent of the Air Ministry list of the Few, so unlike the RAF boards, ' +
                'where every man is real, this is a Staffel rather than a roll.'
            } else {
                'These men are invented, scores and fates and all. There is no German equivalent of the Air ' +
                'Ministry list of the Few, so unlike the RAF boards, where every man is real, this is a ' +
                'Staffel rather than a roll.'
            })
        $note.Margin = '0,8,0,10'; $note.MaxWidth = 900; $note.HorizontalAlignment = 'Left'
        [void]$script:Stage.Children.Add($note)

        $tbl = New-Object Windows.Controls.Border
        $tbl.BorderBrush = Res 'Rule'; $tbl.BorderThickness = '1'; $tbl.CornerRadius = '3'
        # Width, not MaxWidth: aligned Left with only a maximum, the table
        # shrank to its widest row and the columns collapsed together.
        $tbl.Margin = '0,0,0,20'; $tbl.HorizontalAlignment = 'Left'; $tbl.Width = 1000
        $ts = New-Object Windows.Controls.StackPanel
        [void]$ts.Children.Add((New-LwRosterRow -Header))
        $myV = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $myV = [int]$Pilot.victories }
        [void]$ts.Children.Add((New-LwRosterRow -Man ([pscustomobject]@{
            pilot = "$($Pilot.pilot)"; rank = "$($Pilot.rank)"; historical = $false
            appointment = $null; staffel = $Pilot.staffel; victories_total = $null; fate = $null }) -IsPlayer -Vics $myV))
        foreach ($man in ($roster | Sort-Object @{ e = { -[int][bool]$_.historical } }, @{ e = { "$($_.pilot)" } })) {
            [void]$ts.Children.Add((New-LwRosterRow -Man $man))
        }
        $tbl.Child = $ts
        [void]$script:Stage.Children.Add($tbl)

        # Losses. Not historical fates - there are none for these men -
        # but the pilots the campaign has actually taken from this Gruppe,
        # given names from the Staffel so the cost has faces on it. The
        # RAF board does the same thing for the losses its own records do
        # not name. Seeded on the unit, so the same men are lost each time
        # rather than a fresh draw every time the screen is drawn.
        $lost = if ($gr) { [int]$gr.PilotsLost } else { 0 }
        if ($lost -gt 0) {
            $pool = @($roster | Where-Object { -not $_.historical })
            if ($pool.Count) {
                $take = [math]::Min($lost, $pool.Count)
                $rnd = New-Object System.Random ([int]([math]::Abs("$unit".GetHashCode()) % 100000))
                $picked = @($pool | Sort-Object { $rnd.Next() } | Select-Object -First $take)
                [void]$script:Stage.Children.Add((New-TB -Text 'LOSSES IN THIS CAMPAIGN' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
                $ln = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Text $(
                    "The campaign has taken $lost pilot$(if ($lost -ne 1) { 's' } else { '' }) from this Gruppe. " +
                    'They are named from the Staffel so the cost is not just a number, and they are lost in ' +
                    'YOUR campaign rather than in history.')
                $ln.Margin = '0,8,0,10'; $ln.MaxWidth = 900; $ln.HorizontalAlignment = 'Left'
                [void]$script:Stage.Children.Add($ln)
                $lb = New-Object Windows.Controls.Border
                $lb.BorderBrush = Res 'Rule'; $lb.BorderThickness = '1'; $lb.CornerRadius = '3'
                $lb.Margin = '0,0,0,20'; $lb.HorizontalAlignment = 'Left'; $lb.Width = 760
                $lst = New-Object Windows.Controls.StackPanel
                foreach ($man in $picked) {
                    $row = New-Object Windows.Controls.Border
                    $row.Padding = '14,9'; $row.BorderBrush = Res 'Rule'; $row.BorderThickness = '0,0,0,1'
                    $rg = New-Object Windows.Controls.StackPanel; $rg.Orientation = 'Horizontal'
                    [void]$rg.Children.Add((New-TB -Text (Short-Rank "$($man.rank)") -Family $CondFam -Size 12.5 -Colour '#6F828C'))
                    $nm2 = New-TB -Text "$($man.pilot)" -Family $CondFam -Size 14 -Colour '#E2685A' -Bold
                    $nm2.Margin = '14,0,0,0'
                    [void]$rg.Children.Add($nm2)
                    $row.Child = $rg
                    [void]$lst.Children.Add($row)
                }
                $lb.Child = $lst
                [void]$script:Stage.Children.Add($lb)
            }
        }
    }
    # nothing is returned on purpose: an uncaptured $Pilot here goes down
    # the pipeline and the whole record prints itself into whatever called
    # this, which is how it turned up in the middle of a test run
}
# What a man is doing in the Staffel, as against what he is called. The
# two are different things in the Luftwaffe and the RAF alike, and the
# rank alone reads oddly without it.
function Get-Appointment {
    param($Pilot, $Career)
    if (($Pilot.PSObject.Properties.Name -contains 'cmode') -and ("$($Pilot.cmode)" -eq 'commander')) { return 'Gruppenkommandeur' }
    $n = 0; if ($Career) { $n = [int]$Career.sorties }
    if ($n -ge 24) { return 'Staffelkapitaen' }
    if ($n -ge 12) { return 'Schwarmfuehrer' }
    if ($n -ge 6)  { return 'Rottenfuehrer' }
    'Rottenflieger'
}

function Show-SquadronSelect {
    if (-not $script:SelPeriod) { $script:SelPeriod = 'P1' }
    $script:Stage.Children.Clear()
    Set-Header $null
    Show-ChromeButtons $false
    $h = C 'HdrSquadron'; if ($h) { $h.Text = 'Fighter Command' }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "ROYAL AIR FORCE  $([char]0x2022)  POSTINGS" }
    # a man who opened this board by accident, with a career already
    # running, can go back to it
    if (Get-Pilot) { Set-ChromeBack 'BACK TO THE DISPERSAL' { $script:NewCareerPending = $false; Show-Roster -Pilot (Get-Pilot) } }
    else { Set-ChromeBack -Text '' }
    Set-ChromeAction -Text 'REPORT TO THIS SQUADRON' -Enabled $false -OnClick { if ($script:SelSq) { Show-Create } }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'THE PLOTTING TABLE' -Title 'Choose your campaign and squadron'))

    # campaign period: squadrons moved as the battle moved, so pick the
    # period first and the table repopulates with that phase's postings
    $segRow = New-Object Windows.Controls.StackPanel; $segRow.Orientation = 'Horizontal'; $segRow.Margin = '0,-10,0,10'
    foreach ($per in $Periods) {
        $seg = New-Object Windows.Controls.Border
        $seg.Padding = '14,8'; $seg.Margin = '0,0,10,0'; $seg.CornerRadius = '3'; $seg.Cursor = 'Hand'; $seg.Tag = $per.Id
        $active = ($per.Id -eq $script:SelPeriod)
        $seg.Background = if ($active) { B '#213540' } else { B '#101B22' }
        $seg.BorderThickness = '0,0,0,2'
        $seg.BorderBrush = if ($active) { Res 'Brass' } else { B '#101B22' }
        $seg.Child = (New-TB -Text $per.Label -Family $CondFam -Size 12.5 -Colour $(if ($active) { '#E9E3D4' } else { '#6F828C' }) -Bold)
        $seg.Add_MouseLeftButtonUp({ param($sender,$e) $script:SelPeriod = "$($sender.Tag)"; $script:SelSq = $null; Show-SquadronSelect })
        [void]$segRow.Children.Add($seg)
    }
    [void]$script:Stage.Children.Add($segRow)

    $perDef = $Periods | Where-Object { $_.Id -eq $script:SelPeriod } | Select-Object -First 1
    $lead = New-TB -Text "The board for $($perDef.Desc). $([char]0x25B2)$([char]0x25B2)$([char]0x25B2) heavy fighting  $([char]0x25B2)$([char]0x25B2) steady  $([char]0x25B2) quiet. Click a squadron's number to see it, then report to it. Hold the pointer on a number for the squadron's card." -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Wrap
    $lead.Margin = '0,0,0,12'
    [void]$script:Stage.Children.Add($lead)

    $W = 1180.0; $H = [math]::Round($W * 1600.0 / 2560.0)
    $mapWrap = New-Object Windows.Controls.Border
    $mapWrap.Width = $W + 2; $mapWrap.Height = $H + 2; $mapWrap.HorizontalAlignment = 'Left'
    $mapWrap.Background = B '#0B141B'; $mapWrap.BorderBrush = Res 'Rule'; $mapWrap.BorderThickness = '1'; $mapWrap.CornerRadius = '3'
    $grid = New-Object Windows.Controls.Grid
    $imgPath = Join-Path (Join-Path $ModDir 'map') 'sector-map.jpg'
    $bg = New-Object Windows.Controls.Image
    $bmp = Load-Image -Path $imgPath -DecodeWidth 2560
    if ($bmp) { $bg.Source = $bmp }
    $bg.Stretch = 'Uniform'; $bg.Width = $W; $bg.Height = $H
    [void]$grid.Children.Add($bg)
    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $W; $cv.Height = $H; $cv.ClipToBounds = $true
    [void]$grid.Children.Add($cv)
    $mapWrap.Child = $grid

    Enable-MapZoom -Frame $mapWrap -Content $grid
    $script:SelSq = $null
    $script:MapTiles = @()
    $script:SqChips = @()
    # what you have chosen, said above the table rather than under it: the
    # button that acts on it is in the header now, and the two should not
    # be seven hundred pixels apart
    $detail = New-TB -Text 'No squadron selected.' -Family 'Segoe UI' -Size 14 -Colour '#9FB0B8' -Wrap
    $detail.Margin = '2,0,0,12'
    $script:SqDetail = $detail
    [void]$script:Stage.Children.Add($detail)

    $script:SelectSq = {
        param($q2)
        $script:SelSq = $q2
        foreach ($t in $script:MapTiles) {
            $tg = $t.Tag
            $tg.Sel = ([int]$tg.Num -eq [int]$q2.Num)
            $t.Background = if ($tg.Sel) { B '#33FFC24A' } else { B '#00000000' }
            $tg.Text.Foreground = if ($tg.Sel) { B '#FFE28A' } else { B $tg.Colour }
        }
        # the plaque holding the chosen squadron wears the gold, and no
        # other one does
        foreach ($a in $script:MapAssemblies) { $a.Sel = $false }
        foreach ($t in $script:MapTiles) { if ($t.Tag.Sel) { $t.Tag.Asm.Sel = $true } }
        Set-MapFocus $null
        foreach ($cp in $script:SqChips) {
            $cp.BorderBrush = if ($cp.Tag -and $cp.Tag.Num -eq $q2.Num) { B '#FFE28A' } else { Res 'Rule' }
        }
        $actTxt = switch ("$($q2.Act)") { 'H' { 'in the thick of the fighting' } 'M' { 'steady action' } default { 'a quieter station' } }
        $codeTxt = if ("$($q2.Code)") { "   (codes $($q2.Code)-)" } else { '' }
        $script:SqDetail.Text = "No. $($q2.Num) Squadron  $([char]0x2022)  $($q2.Type)  $([char]0x2022)  $($q2.Base)  $([char]0x2022)  No. $(Get-GroupForBase $q2.Base) Group  $([char]0x2022)  $actTxt$codeTxt"
        Set-ChromeActionEnabled $true
    }

    # the day's postings, gathered by field: the same layer the sector map
    # draws, so the board a man chooses from is the board he will fly from
    $byField = @{}
    $farActive = @(); $resting = @()
    foreach ($q in (Get-Squadrons)) {
        $po = Get-Posting $q $script:SelPeriod
        if (-not $po) { $resting += $q; continue }
        $qt = @{ Num=$q.Num; Code=$q.Code; Type=$q.Type; Base=$po.Base; Act=$po.Act; Period=$script:SelPeriod }
        if ($po.Mx -lt 0) { $farActive += $qt; continue }
        $k = "$($po.Base)"
        if (-not $byField.ContainsKey($k)) {
            $byField[$k] = @{ Base = $k; X = [double]$po.Mx * $W; Y = [double]$po.My * $H; Sqns = @() }
        }
        $byField[$k].Sqns = @($byField[$k].Sqns) + @($qt)
    }
    $perDate = $null
    foreach ($per in $Periods) { if ($per.Id -eq $script:SelPeriod) { try { $perDate = [datetime]$per.Key } catch { } } }
    $fields = @($byField.Values | Sort-Object @{ e = { $_.X } }, @{ e = { $_.Y } })
    Add-SquadronPlaques -Canvas $cv -Fields $fields -W $W -H $H -Mine 0 -Date $perDate `
                        -OnSelect $true -AlwaysName -Activity

    [void]$script:Stage.Children.Add($mapWrap)

    if ($farActive.Count) {
        $fl = New-TB -Text 'POSTINGS BEYOND THIS TABLE' -Family $CondFam -Size 11.5 -Colour '#8A9689' -Bold
        $fl.Margin = '2,12,0,6'
        [void]$script:Stage.Children.Add($fl)
        $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'
        foreach ($qt in $farActive) {
            $isSpit = ("$($qt.Type)" -match 'Spitfire')
            $chip = New-Object Windows.Controls.Border
            $chip.Padding = '12,7'; $chip.Margin = '0,0,10,0'; $chip.CornerRadius = '3'; $chip.Cursor = 'Hand'
            $chip.Background = B '#101B22'; $chip.BorderBrush = Res 'Rule'; $chip.BorderThickness = '1.5'
            $pips3 = switch ("$($qt.Act)") { 'H' { " $([char]0x25B2)$([char]0x25B2)$([char]0x25B2)" } 'M' { " $([char]0x25B2)$([char]0x25B2)" } default { " $([char]0x25B2)" } }
            $chip.Child = (New-TB -Text "No. $($qt.Num)  $([char]0x2022)  $($qt.Base -replace '^RAF ','')$pips3" -Family $CondFam -Size 12 -Colour $(if ($isSpit) { '#9FE0F0' } else { '#F8C87E' }) -Bold)
            $chip.Tag = $qt
            $chip.Add_MouseLeftButtonUp({ param($sender,$e) & $script:SelectSq $sender.Tag })
            $script:SqChips += $chip
            [void]$chips.Children.Add($chip)
        }
        [void]$script:Stage.Children.Add($chips)
    }
    if ($resting.Count) {
        $rl = New-TB -Text ('RESTING IN THE NORTH THIS PERIOD:  ' + (@($resting | ForEach-Object { "No. $($_.Num)" }) -join '   ')) -Family $CondFam -Size 11.5 -Colour '#4E5B63'
        $rl.Margin = '2,10,0,0'
        [void]$script:Stage.Children.Add($rl)
    }

}

function Show-Create {
    $script:Stage.Children.Clear()
    $script:SelPortrait = $null; $script:SelBorder = $null
    if (-not $script:SelSq) {
        $q92 = Get-SquadronDef 92
        $po92 = Get-Posting $q92 'P1'
        $script:SelSq = @{ Num=92; Code='QJ'; Type='Spitfire I'; Base=$po92.Base; Act=$po92.Act; Period='P1' }
    }
    Set-Header $null
    Show-ChromeButtons $false
    $h = C 'HdrSquadron'; if ($h) { $h.Text = "No. $($script:SelSq.Num) Squadron" }
    $perDef2 = $Periods | Where-Object { $_.Id -eq "$($script:SelSq.Period)" } | Select-Object -First 1
    $m = C 'HdrMotto'; if ($m) { $m.Text = "ROYAL AIR FORCE  $([char]0x2022)  $($script:SelSq.Type.ToUpper())S AT $($script:SelSq.Base.ToUpper())$(if ($perDef2) { "  $([char]0x2022)  $($perDef2.Label)" })" }
    Set-ChromeBack 'BACK TO THE BOARD' { Show-SquadronSelect }
    Set-ChromeAction -Text 'REPORT FOR DUTY' -Enabled $false -OnClick { Invoke-Submit }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'REPORT TO THE ADJUTANT' -Title "A new pilot for No. $($script:SelSq.Num)"))
    $lead = New-TB -Text 'Summer 1940. Give your name, say whether you come to the squadron as a sergeant pilot or with a commission, and pick your photograph. Your aircraft and code letter are settled once you have flown your first operation.' -Family 'Segoe UI' -Size 14.5 -Colour '#9FB0B8' -Wrap
    $lead.Margin = '0,-14,0,22'
    [void]$script:Stage.Children.Add($lead)

    # form row
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,26'

    $nameCol = New-Object Windows.Controls.StackPanel; $nameCol.Margin = '0,0,36,0'
    [void]$nameCol.Children.Add((New-TB -Text 'NAME' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $script:NameBox = New-Object Windows.Controls.TextBox
    $script:NameBox.Width = 320; $script:NameBox.Margin = '0,7,0,0'; $script:NameBox.MaxLength = 40
    # one man, one name: if a campaign is under way, offer its pilot's name
    $cp0 = Get-CampaignPilot
    if ($cp0 -and $cp0.Name) { $script:NameBox.Text = "$($cp0.Name)" }
    [void]$nameCol.Children.Add($script:NameBox)
    [void]$row.Children.Add($nameCol)

    # Sergeant or officer. Fighter Command flew the Battle with both on the
    # same squadron, in the same aeroplanes, and they were decorated
    # differently for it: the DFM for a sergeant, the DFC for an officer.
    if (-not $script:SelRank) { $script:SelRank = 'Sergeant' }
    $rankCol = New-Object Windows.Controls.StackPanel
    [void]$rankCol.Children.Add((New-TB -Text 'YOU JOIN AS' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $rankRow = New-Object Windows.Controls.StackPanel; $rankRow.Orientation = 'Horizontal'; $rankRow.Margin = '0,7,0,0'
    $script:RankSegs = @()
    foreach ($opt in @(
        @{ R = 'Sergeant';      L = 'SERGEANT PILOT'; N = 'a non-commissioned pilot; his cross is the DFM' },
        @{ R = 'Pilot Officer'; L = 'PILOT OFFICER';  N = 'commissioned; his cross is the DFC' })) {
        $seg = New-Object Windows.Controls.Border
        $seg.Padding = '14,9'; $seg.Margin = '0,0,10,0'; $seg.CornerRadius = '3'; $seg.Cursor = 'Hand'
        $seg.Tag = $opt.R
        $inner = New-Object Windows.Controls.StackPanel
        [void]$inner.Children.Add((New-TB -Text $opt.L -Family $CondFam -Size 12.5 -Colour '#E9E3D4' -Bold))
        [void]$inner.Children.Add((New-TB -Text $opt.N -Family 'Segoe UI' -Size 11 -Colour '#6F828C'))
        # the cuff badge beside the words, and the panel parented ONCE:
        # setting Child first and then re-parenting throws
        $bf = Get-RankBadgeFile $opt.R
        $bi = if ($bf) { New-BadgeImage -File $bf -Height 30 -Tip $opt.R } else { $null }
        if ($bi) {
            $wrapSeg = New-Object Windows.Controls.StackPanel; $wrapSeg.Orientation = 'Horizontal'
            $bi.Margin = '0,0,10,0'; $bi.VerticalAlignment = 'Center'
            [void]$wrapSeg.Children.Add($bi)
            [void]$wrapSeg.Children.Add($inner)
            $seg.Child = $wrapSeg
        } else { $seg.Child = $inner }
        $seg.Add_MouseLeftButtonUp({ param($sender, $e) $script:SelRank = "$($sender.Tag)"; Update-RankSegs })
        $script:RankSegs += ,$seg
        [void]$rankRow.Children.Add($seg)
    }
    [void]$rankCol.Children.Add($rankRow)
    [void]$row.Children.Add($rankCol)
    Update-RankSegs

    [void]$script:Stage.Children.Add($row)

    [void]$script:Stage.Children.Add((New-TB -Text 'YOUR PHOTOGRAPH' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $picker = New-Object Windows.Controls.WrapPanel; $picker.Orientation = 'Horizontal'; $picker.Margin = '0,12,0,22'
    foreach ($p in (Get-Portraits)) {
        $pb = New-Object Windows.Controls.Border
        $pb.Width = 96; $pb.Height = 120; $pb.Margin = '0,0,12,12'
        $pb.CornerRadius = '2'; $pb.BorderThickness = 3; $pb.BorderBrush = $script:FrameBrush
        $pb.Background = B '#0B1116'; $pb.Cursor = 'Hand'; $pb.Tag = $p; $pb.ClipToBounds = $true
        $bmp = Load-Portrait -File $p -DecodeHeight 150
        if ($bmp) {
            $im = New-Object Windows.Controls.Image; $im.Source = $bmp; $im.Stretch = 'UniformToFill'
            $pb.Child = $im
        }
        $pb.Add_MouseLeftButtonUp({
            param($s,$e)
            if ($script:SelBorder) { $script:SelBorder.BorderBrush = $script:FrameBrush; $script:SelBorder.BorderThickness = 3 }
            $s.BorderBrush = $script:BrassBrush; $s.BorderThickness = 4
            $script:SelBorder = $s; $script:SelPortrait = $s.Tag
            Update-CreateValid
        })
        [void]$picker.Children.Add($pb)
    }
    [void]$script:Stage.Children.Add($picker)

    $foot = New-Object Windows.Controls.StackPanel; $foot.Orientation = 'Horizontal'; $foot.HorizontalAlignment = 'Right'
    $script:SubmitBtn = New-Object Windows.Controls.Button
    $script:SubmitBtn.Content = 'REPORT FOR DUTY'; $script:SubmitBtn.IsEnabled = $false
    [void]$foot.Children.Add($script:SubmitBtn)
    [void]$script:Stage.Children.Add($foot)

    $script:NameBox.Add_TextChanged({ Update-CreateValid })
    $script:SubmitBtn.Add_Click({ Invoke-Submit })
}

# =====================================================================
Finalize-Flight
# Paint the side switch once before anything is shown. It was only ever
# painted BY a side change, and the markup happens to start on the RAF
# segment, so it looked right by luck rather than by saying so.
# ONE LINE, so the test harnesses can take it out.
#
# This used to be three loose statements and each harness stripped them
# with its own regex. Growing it to open on the last side would have left
# those regexes matching nothing, and the harnesses would then have run
# the bootstrap for real: Set-StateSide against the LIVE install, before
# StateRootOverride is set, which is how a pilot record was destroyed
# once already. A named function cannot drift out from under them.
function Start-Room {
    # Open on the side he was last flying, not always on the RAF.
    Set-StateSide (Get-LastSide)
    Update-SideSwitch
    $existing = Get-Pilot
    if ($script:Side -eq 'lw') {
        if ($existing) { Show-ReadyRoom -Pilot $existing } else { Show-GruppeSelect }
    } else {
        if ($existing) { Show-Roster -Pilot $existing } else { Show-SquadronSelect }
    }
}
Start-Room
[void]$Win.ShowDialog()
