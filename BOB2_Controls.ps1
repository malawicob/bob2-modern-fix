# =====================================================================
#  BOB2 controls - detect your stick and set it up properly
#  Part of BOB2 Windows 10/11 Fix v1.5.0
# =====================================================================
#
#  WHY THIS EXISTS
#    The game's own controls screen is from 2005 and predates every stick
#    you are likely to own. Axis assignment lives in DeviceDefaults.txt,
#    a plain-text file keyed by DirectInput device GUID - and the shipped
#    copy lists a Saitek X36, a Saitek X45 and a Logitech WingMan. If
#    your device is not in there, the game has no idea which physical
#    axis is pitch and which is throttle, and you are left dragging
#    things around in a dialog that barely fits on screen.
#
#    This detects what is actually plugged in, works out the DirectInput
#    GUID, and writes a correct entry.
#
#  TWO FILES, TWO SEPARATE THINGS
#    DeviceDefaults.txt   which physical AXIS drives which control
#    KEYBOARD\keys.txt    which BUTTON fires which action
#    Both are backed up before anything is written.
#
#  WHAT IS NOT HERE
#    Per-axis sensitivity and curves. Those live in SAVEGAME\inputcfg.dat,
#    a binary this project has not decoded. bdg.txt offers only
#    BOB_SMOOTHER_DEADZONE=ON/OFF. Mouse and keyboard sensitivity are
#    adjustable in flight - they are bindable actions, not settings.
# =====================================================================

param(
    [switch]$Apply,        # write the changes; without it this only reports
    [switch]$Axes,         # DeviceDefaults.txt only
    [switch]$Buttons       # keys.txt button preset only
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Write-Head { param($m) Write-Host ''; Write-Host "  $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  $m" -ForegroundColor Red }
function Write-Info { param($m) Write-Host "  $m" -ForegroundColor Gray }

function Find-GameDir {
    foreach ($c in @($ScriptDir, (Split-Path -Parent $ScriptDir),
                     'D:\Battle of Britain II', 'C:\Battle of Britain II',
                     'C:\Program Files (x86)\Battle of Britain II')) {
        if ($c -and (Test-Path (Join-Path $c 'Bob.exe'))) { return $c }
    }
    return $null
}

# ---------------------------------------------------------------------
#  Detection
#
#  winmm tells us how many axes and buttons a device really has, but its
#  name is generic ("Microsoft PC-joystick driver"). The real product
#  name and the VID/PID live in the registry. A DirectInput product GUID
#  is simply PID then VID followed by a fixed tail whose bytes spell
#  "PIDVID" - which is how the shipped Saitek entries are formed.
# ---------------------------------------------------------------------
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class BOB2Joy2 {
  [StructLayout(LayoutKind.Sequential)] public struct JOYCAPS {
    public ushort wMid, wPid;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szPname;
    public uint wXmin,wXmax,wYmin,wYmax,wZmin,wZmax,wNumButtons,wPeriodMin,wPeriodMax;
    public uint wRmin,wRmax,wUmin,wUmax,wVmin,wVmax,wCaps,wMaxAxes,wNumAxes,wMaxButtons;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szRegKey;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szOEMVxD;
  }
  [DllImport("winmm.dll", CharSet=CharSet.Ansi)] public static extern uint joyGetDevCapsA(uint id, ref JOYCAPS c, uint size);
}
'@ -ErrorAction SilentlyContinue

function Get-OemNames {
    # VID_xxxx&PID_xxxx -> friendly name, as recorded by the driver.
    $map = @{}
    foreach ($root in @('HKLM:\SYSTEM\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM',
                        'HKCU:\System\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM')) {
        if (-not (Test-Path $root)) { continue }
        foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $n = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).OEMName
            if ($n) { $map[$k.PSChildName.ToUpper()] = $n }
        }
    }
    return $map
}

function ConvertTo-DIGuid {
    param([string]$Vid, [string]$ProductId)
    # e.g. VID 044F, PID B10A -> {B10A044F-0000-0000-0000-504944564944}
    ('{{{0}{1}-0000-0000-0000-504944564944}}' -f $ProductId.ToUpper(), $Vid.ToUpper())
}

function Get-Controllers {
    $oem = Get-OemNames
    $out = @()

    # Which VID/PID are actually present right now, per PnP.
    $present = @()
    foreach ($d in (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                    Where-Object { $_.DeviceID -match 'HID\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})' })) {
        if ($d.DeviceID -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
            $key = "VID_$($Matches[1])&PID_$($Matches[2])"
            if ($oem.ContainsKey($key.ToUpper())) {
                $present += [pscustomobject]@{ Vid = $Matches[1]; Pid = $Matches[2]; Key = $key; Name = $oem[$key.ToUpper()] }
            }
        }
    }
    $present = $present | Sort-Object Key -Unique

    # winmm gives the live axis/button counts, in the ID order the game sees.
    for ($i = 0; $i -lt 16; $i++) {
        $c = New-Object BOB2Joy2+JOYCAPS
        $r = [BOB2Joy2]::joyGetDevCapsA($i, [ref]$c, [System.Runtime.InteropServices.Marshal]::SizeOf($c))
        if ($r -ne 0 -or -not $c.szPname) { continue }
        $devVid = '{0:X4}' -f $c.wMid
        $devPid = '{0:X4}' -f $c.wPid      # NOT $pid - that is PowerShell's own process id
        $key = "VID_$devVid&PID_$devPid"
        $name = $(if ($oem.ContainsKey($key.ToUpper())) { $oem[$key.ToUpper()] } else { $c.szPname })
        $out += [pscustomobject]@{
            Index    = $i
            Name     = $name
            Vid      = $devVid
            Pid      = $devPid
            Guid     = ConvertTo-DIGuid $devVid $devPid
            Buttons  = [int]$c.wNumButtons
            Axes     = [int]$c.wNumAxes
            HasPov   = [bool]($c.wCaps -band 1)
        }
    }
    ,$out
}

# ---------------------------------------------------------------------
#  Axis layouts
#
#  Physical names the game accepts: X Y Z RX RY RZ SLIDER0 SLIDER1
#  In-game axes: AU_PITCH AU_ROLL AU_YAW AU_THROTTLE AU_THROTTLE2
#                AU_PROPPITCH AU_PROPPITCH2 AU_GUNNER_X AU_GUNNER_Y
#                AU_VIEW_X AU_VIEW_Y AU_VIEW_ZOOM AU_VIEW_FOV
# ---------------------------------------------------------------------
function Get-AxisLayout {
    param($Dev, [bool]$ThrottlePresent)

    # A twist-rudder stick flown on its own has to carry throttle on its
    # slider. With a separate throttle unit attached, the stick gives up
    # the throttle so the real lever owns it.
    if ($Dev.Name -match 'T\.?16000') {
        $m = [ordered]@{
            AU_PITCH = 'Y'; AU_ROLL = 'X'; AU_YAW = 'RZ'
            AU_THROTTLE = $(if ($ThrottlePresent) { '' } else { 'SLIDER0' })
        }
        return @{ Map = $m; Why = 'T.16000M: twist grip is rudder, slider is throttle' }
    }
    if ($Dev.Name -match 'TWCS|Throttle') {
        $m = [ordered]@{
            AU_THROTTLE = 'Z'; AU_YAW = 'X'; AU_PROPPITCH = 'SLIDER0'
        }
        return @{ Map = $m; Why = 'TWCS: main lever is throttle, rocker is rudder, slider is prop pitch' }
    }
    # Generic stick - the arrangement almost every stick since 1998 uses.
    $m = [ordered]@{
        AU_PITCH = 'Y'; AU_ROLL = 'X'; AU_YAW = 'RZ'
        AU_THROTTLE = $(if ($ThrottlePresent) { '' } else { 'SLIDER0' })
    }
    return @{ Map = $m; Why = 'generic stick layout' }
}

$ALL_AXES = @('AU_PITCH','AU_ROLL','AU_YAW','AU_THROTTLE','AU_THROTTLE2',
              'AU_PROPPITCH','AU_PROPPITCH2','AU_GUNNER_X','AU_GUNNER_Y',
              'AU_VIEW_X','AU_VIEW_Y','AU_VIEW_ZOOM','AU_VIEW_FOV')

# ---------------------------------------------------------------------
#  Button preset - 16 buttons, ordered by how urgently you need them.
#  Buttons 1-4 are the ones your thumb can reach without letting go, so
#  they carry the combat actions. The base bank takes everything else.
# ---------------------------------------------------------------------
$BUTTON_PRESET = @(
    @{ B = 1;  A = 'SHOOT';         Why = 'trigger' }
    @{ B = 2;  A = 'PADLOCKTOG';    Why = 'padlock the target - the most used combat key' }
    @{ B = 3;  A = 'RESETVIEW';     Why = 'snap back to forward view, the partner to padlock' }
    @{ B = 4;  A = 'FOV_TOGGLE';    Why = 'gunsight zoom toggle' }
    @{ B = 5;  A = 'FLAPSDOWN';     Why = '' }
    @{ B = 6;  A = 'FLAPSUP';       Why = '' }
    @{ B = 7;  A = 'GEARUPDOWN';    Why = '' }
    @{ B = 8;  A = 'SPEEDBRAKE';    Why = '' }
    @{ B = 9;  A = 'ELEVTRIMUP';    Why = '' }
    @{ B = 10; A = 'ELEVTRIMDOWN';  Why = '' }
    @{ B = 11; A = 'PROPPITCHUP';   Why = '' }
    @{ B = 12; A = 'PROPPITCHDOWN'; Why = '' }
    @{ B = 13; A = 'PCENEMY';       Why = 'nearest enemy' }
    @{ B = 14; A = 'ENEMYVIEW';     Why = 'cycle enemy view' }
    @{ B = 15; A = 'DROPBOMB';      Why = '' }
    @{ B = 16; A = 'RESETALLTRIM';  Why = '' }
)

# The eight hat directions the game already understands. Left alone by
# default - the stock mapping is correct and worth keeping.
$HAT_ACTIONS = @('ROTUP','ROTUPRIGHT','ROTRIGHT','ROTDNRIGHT','ROTDOWN','ROTDNLEFT','ROTLEFT','ROTUPLEFT')

function ConvertTo-JoyCode { param([int]$Device, [int]$Button) 260 + (40 * $Device) + $Button }

# ---------------------------------------------------------------------
$GameDir = Find-GameDir
if (-not $GameDir) { Write-Err 'Could not find Bob.exe.'; exit 1 }

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '  BOB2 CONTROLS' -ForegroundColor Cyan
Write-Host '========================================================' -ForegroundColor Cyan
Write-Info "Game folder: $GameDir"

$devs = Get-Controllers
Write-Head 'DETECTED CONTROLLERS'
if ($devs.Count -eq 0) {
    Write-Warn 'No game controller is connected.'
    Write-Info 'Plug your stick in and run this again.'
    exit 1
}
foreach ($d in $devs) {
    Write-OK ("[{0}] {1}" -f ($d.Index + 1), $d.Name)
    Write-Info ("     {0} buttons, {1} axes{2}" -f $d.Buttons, $d.Axes, $(if ($d.HasPov) { ', 1 hat' } else { '' }))
    Write-Info ("     VID_{0}&PID_{1}   GUID {2}" -f $d.Vid, $d.Pid, $d.Guid)
}

$throttle = [bool]($devs | Where-Object { $_.Name -match 'TWCS|Throttle|Quadrant' })
if (-not $throttle -and ($devs | Where-Object { $_.Name -match 'T\.?16000' })) {
    Write-Info ''
    Write-Info 'No separate throttle detected, so the stick keeps throttle on its slider.'
    Write-Info 'Plug a throttle in and re-run to move it onto the real lever.'
}

# ---------------------------------------------------------------------
Write-Head 'AXIS MAPPING  (DeviceDefaults.txt)'
$ddPath = Join-Path $GameDir 'DeviceDefaults.txt'
$blocks = @()
foreach ($d in $devs) {
    $lay = Get-AxisLayout $d $throttle
    Write-OK ("{0}   - {1}" -f $d.Name, $lay.Why)
    $lines = @("# $($d.Name)  (added by BOB2-Win11-Fix)", "GUID = $($d.Guid)")
    foreach ($a in $ALL_AXES) {
        $v = $(if ($lay.Map.Contains($a)) { $lay.Map[$a] } else { '' })
        $lines += ("{0} = {1}" -f $a, $v)
        if ($v) { Write-Info ("     {0,-14} = {1}" -f $a, $v) }
    }
    $blocks += , $lines
}

# ---------------------------------------------------------------------
Write-Head 'BUTTON PRESET  (KEYBOARD\keys.txt)'
$stick = $devs | Select-Object -First 1
Write-Info ("For device 1: {0} ({1} buttons)" -f $stick.Name, $stick.Buttons)
foreach ($b in $BUTTON_PRESET) {
    if ($b.B -gt $stick.Buttons) { continue }
    Write-Info ("     Button {0,-3} {1,-16} {2}" -f $b.B, $b.A, $b.Why)
}
Write-Info '     Hat            look direction (unchanged - the stock mapping is right)'

if (-not $Apply) {
    Write-Host ''
    Write-Warn 'This was a dry run. Nothing has been written.'
    Write-Info 'Run with -Apply to write the axis mapping and the button preset.'
    Write-Host ''
    exit 0
}

# ---------------------------------------------------------------------
#  Write
# ---------------------------------------------------------------------
$stamp  = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$backup = Join-Path $GameDir "_ControlsBackup\$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$enc = [System.Text.Encoding]::GetEncoding(1252)

$doAxes    = (-not $Buttons) -or $Axes
$doButtons = (-not $Axes) -or $Buttons

if ($doAxes) {
    Copy-Item $ddPath (Join-Path $backup 'DeviceDefaults.txt') -Force
    $text = $enc.GetString([System.IO.File]::ReadAllBytes($ddPath))
    $lines = $text -split "`r`n", 0

    # Drop any block we previously added for these GUIDs, so re-running
    # replaces rather than accumulates.
    $ours = $devs | ForEach-Object { $_.Guid }
    $kept = New-Object System.Collections.ArrayList
    $skip = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*GUID\s*=\s*(\{[^}]+\})') {
            $skip = $ours -contains $Matches[1]
            if ($skip) {
                # also drop the comment line immediately above it
                if ($kept.Count -gt 0 -and $kept[$kept.Count-1] -match '^\s*#') { $kept.RemoveAt($kept.Count-1) }
            }
        }
        elseif ($skip -and $l -match '^\s*$') { $skip = $false }
        if (-not $skip) { [void]$kept.Add($l) }
    }
    while ($kept.Count -gt 0 -and $kept[$kept.Count-1] -match '^\s*$') { $kept.RemoveAt($kept.Count-1) }
    foreach ($b in $blocks) { [void]$kept.Add(''); foreach ($l in $b) { [void]$kept.Add($l) } }
    [void]$kept.Add('')
    [System.IO.File]::WriteAllBytes($ddPath, $enc.GetBytes(($kept -join "`r`n")))
    Write-OK "Wrote axis mapping for $($devs.Count) device(s) to DeviceDefaults.txt"
}

if ($doButtons) {
    $keysPath = Join-Path $GameDir 'KEYBOARD\keys.txt'
    Copy-Item $keysPath (Join-Path $backup 'keys.txt') -Force
    $text = $enc.GetString([System.IO.File]::ReadAllBytes($keysPath))
    $lines = $text -split "`r`n", 0

    # Same discipline the configurator uses: rebuild a line from its parts
    # so spacing, comments and every code we are not touching survive.
    $rx = [regex]'^(\S+)([ \t]*)(.*?)([ \t]*)$'
    $want = @{}
    foreach ($b in $BUTTON_PRESET) {
        if ($b.B -gt $stick.Buttons) { continue }
        $want[$b.A] = (ConvertTo-JoyCode 0 ($b.B - 1)).ToString()
    }
    $assigned = ($want.Values)

    $changed = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $rx.Match($lines[$i])
        if (-not $m.Success -or $lines[$i].Trim() -eq '') { continue }
        $action = $m.Groups[1].Value
        $kb = @(); $dev = @()
        foreach ($tok in ($m.Groups[3].Value -split '\s+')) {
            if ($tok -eq '') { continue }
            $isDev = $false
            foreach ($part in ($tok -split '\+')) { if ([int]$part -ge 256) { $isDev = $true } }
            if ($isDev) { $dev += $tok } else { $kb += $tok }
        }
        # Remove any device code this preset is about to hand to someone
        # else, otherwise one button would fire two actions.
        $dev = @($dev | Where-Object { $assigned -notcontains $_ })
        if ($want.ContainsKey($action)) {
            # Exactly one device code for a preset action, not a pile of
            # leftovers. The stock file binds each action across four
            # notional sticks (260/300/340/380); keeping those means that
            # plugging a throttle in later silently makes ITS button 5 do
            # whatever the stick's button 5 used to do.
            $dev = @($want[$action])
        }
        $body = (@($kb) + @($dev)) -join ' '
        $new = $(if ($body -eq '') { $action + $m.Groups[2].Value }
                 else { $action + $m.Groups[2].Value + $body + $m.Groups[4].Value })
        if ($new -ne $lines[$i]) { $lines[$i] = $new; $changed++ }
    }
    [System.IO.File]::WriteAllBytes($keysPath, $enc.GetBytes(($lines -join "`r`n")))
    Write-OK "Applied the button preset - $changed lines changed in keys.txt"
}

Write-Host ''
Write-OK "Backups: $backup"
Write-Info 'Start the game and check the controls screen. To undo, copy the files'
Write-Info 'from that backup folder back over the originals.'
Write-Host ''
