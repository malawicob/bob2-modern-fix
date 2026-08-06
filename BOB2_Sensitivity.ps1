# =====================================================================
#  BOB2 axis sensitivity - deadzone, saturation and inversion
#  Part of BOB2 Windows 10/11 Fix v1.5.0
# =====================================================================
#
#  THE HONEST HEADLINE: BOB2 HAS NO JOYSTICK RESPONSE CURVES.
#
#    The whole input path is deadzone followed by a linear scale. The
#    engine's only shaping calls are ApplyDeadZone / ApplyDeadZone2 and
#    then CalibrationScaler / CalibrationConstant - a multiply and an
#    offset. There is no exponent, no curve table, no shaping of any
#    kind on a joystick axis.
#
#    The game DOES contain a Curve class, in CURVES.CPP, and it is easy
#    to mistake for what you want. It is not: it lives under
#    Release\model\ and is used by Engine::SetCurves and
#    ModelGenerator::ParseCurves - aerodynamic and engine data for the
#    flight model. Nothing to do with your stick.
#
#    setMouseSensitivity exists but is MOUSE only.
#
#    So a genuine response curve has to come from outside the game.
#    See the note at the bottom.
#
#  WHAT THIS TOOL CAN DO
#    SAVEGAME\inputcfg.dat, decoded here for the first time:
#      18 records of 278 bytes, one per in-game axis, in AU_ order.
#        +0   int32  reserved / device instance
#        +8   int32  device kind   2 = joystick, 1 = mouse, 0 = none
#        +12  int32  DEADZONE      0..10000, DirectInput units
#        +16  int32  SATURATION    0..10000
#        +20  int32  DirectInput axis index, -1 when unassigned
#        +24  byte   INVERT        0 or 1
#        +25  char[] physical axis name, null terminated
#
#    Record order matches the AU_ axis list exactly, which is how the
#    four joystick records line up with pitch, roll, yaw and throttle.
# =====================================================================

param(
    [ValidateSet('show','precision','standard','target','stock','pedals','save','load','list')]
    [string]$Action = 'show',
    [string]$Name                     # profile name for save / load
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Write-Head { param($m) Write-Host ''; Write-Host "  $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  $m" -ForegroundColor Red }
function Write-Info { param($m) Write-Host "  $m" -ForegroundColor Gray }

$STRIDE = 278
$AU = @('Pitch','Roll','Yaw','Throttle','Throttle 2','Prop pitch','Prop pitch 2',
        'Gunner X','Gunner Y','View X','View Y','View zoom','View FOV',
        'spare 13','spare 14','spare 15','spare 16','spare 17')
$DIAXIS = @('X','Y','Z','Rx','Ry','Rz','Slider0','Slider1')

# Presets. Only deadzone is really worth moving: saturation below 100%
# throws away stick travel, and there is no curve to trade it against.
# Deadzone is set PER AXIS, and the rudder is deliberately not the same as
# pitch and roll.
#
# A twist-grip rudder shares a limb with the roll axis. Pushing the stick
# sideways rotates your wrist a little whether you mean it to or not, so a
# twist axis picks up a few percent of unintended input on every roll. Give it
# the same 1% as pitch and roll and the aeroplane hunts and jerks in yaw
# throughout every turn - which is exactly what a Spitfire does when it is fed
# a constant trickle of rudder.
#
# Pitch and roll want the deadzone as small as the hardware allows; yaw wants
# enough to swallow the crosstalk. They are different problems.
$PRESETS = @{
    'precision' = @{ Dead = 100; Yaw = 500; Sat = 10000
        Why = 'Fighters - Spitfire, Hurricane, Bf109. Pitch and roll at 1%: the T.16000M uses Hall-effect sensors and barely drifts, so fine tracking stays alive near centre where gunnery happens. Rudder at 5% to absorb the wrist twist that comes with every roll input.' }
    'standard'  = @{ Dead = 300; Yaw = 600; Sat = 10000
        Why = 'Twins and bombers - Bf110, Ju88, Heinkel. A little more centre slop suits a heavy aeroplane you trim and hold rather than fly on the sight.' }
    'target'    = @{ Dead = 0; Yaw = 0; Sat = 10000
        Why = 'Use when TARGET or Joystick Gremlin is shaping the axis. The external tool owns the deadzone, rudder included; leaving one here as well stacks them.' }
    'stock'     = @{ Dead = 750; Yaw = 750; Sat = 10000
        Why = 'What the game ships. 7.5% everywhere - far more than a Hall sensor needs on pitch and roll, and about right on a twist rudder by accident.' }
    'pedals'    = @{ Dead = 100; Yaw = 100; Sat = 10000
        Why = 'For real rudder pedals. Pedals do not suffer the wrist crosstalk a twist grip does, so yaw can be as tight as pitch and roll.' }
}
# Record 2 is yaw - the record order follows the AU_ axis list exactly.
$YAW_RECORD = 2

function Find-GameDir {
    foreach ($c in @($ScriptDir, (Split-Path -Parent $ScriptDir),
                     'D:\Battle of Britain II', 'C:\Battle of Britain II',
                     'C:\Program Files (x86)\Battle of Britain II')) {
        if ($c -and (Test-Path (Join-Path $c 'Bob.exe'))) { return $c }
    }
    return $null
}

$GameDir = Find-GameDir
if (-not $GameDir) { Write-Err 'Could not find Bob.exe.'; exit 1 }
$Cfg = Join-Path $GameDir 'SAVEGAME\inputcfg.dat'
if (-not (Test-Path $Cfg)) { Write-Err "Not found: $Cfg"; exit 1 }
$ProfileDir = Join-Path $GameDir '_AxisProfiles'

function Read-Records {
    $b = [System.IO.File]::ReadAllBytes($Cfg)
    $n = [math]::Floor($b.Length / $STRIDE)
    $recs = @()
    for ($i = 0; $i -lt $n; $i++) {
        $o = $i * $STRIDE
        $nameBytes = $b[($o+25)..($o+70)]
        $z = [Array]::IndexOf($nameBytes, [byte]0)
        if ($z -lt 0) { $z = $nameBytes.Length }
        $recs += [pscustomobject]@{
            Index = $i
            Use   = $(if ($i -lt $AU.Count) { $AU[$i] } else { "axis $i" })
            Kind  = [BitConverter]::ToInt32($b, $o + 8)
            Dead  = [BitConverter]::ToInt32($b, $o + 12)
            Sat   = [BitConverter]::ToInt32($b, $o + 16)
            DiAx  = [BitConverter]::ToInt32($b, $o + 20)
            Inv   = $b[$o + 24]
            Name  = [System.Text.Encoding]::ASCII.GetString($nameBytes, 0, $z)
        }
    }
    return @{ Bytes = $b; Recs = $recs }
}

function Show-Records {
    param($d)
    Write-Head 'CURRENT AXIS SETTINGS   (SAVEGAME\inputcfg.dat)'
    Write-Info ('{0,-12} {1,-22} {2,-9} {3,-10} {4,-7} {5}' -f 'IN-GAME','PHYSICAL','DEADZONE','SATURATION','INVERT','SOURCE')
    foreach ($r in $d.Recs) {
        if ($r.Kind -eq 0 -and $r.DiAx -lt 0) { continue }   # unassigned
        $kind = switch ($r.Kind) { 2 { 'joystick' } 1 { 'mouse' } default { '-' } }
        $ax = $(if ($r.DiAx -ge 0 -and $r.DiAx -lt $DIAXIS.Count) { $DIAXIS[$r.DiAx] } else { '?' })
        $col = $(if ($r.Kind -eq 2) { 'White' } else { 'DarkGray' })
        Write-Host ('  {0,-12} {1,-22} {2,-9} {3,-10} {4,-7} {5}' -f `
            $r.Use, ("$($r.Name) [$ax]"), ('{0:0.0}%' -f ($r.Dead/100)), ('{0:0.0}%' -f ($r.Sat/100)),
            $(if ($r.Inv) { 'yes' } else { 'no' }), $kind) -ForegroundColor $col
    }
}

function Set-Preset {
    param($d, [string]$Key)
    $p = $PRESETS[$Key]
    $b = $d.Bytes
    $changed = 0
    foreach ($r in $d.Recs) {
        # Joystick axes only. The mouse has its own sensitivity controls in
        # flight, and touching keyboard rows would be meaningless.
        if ($r.Kind -ne 2) { continue }
        $o = $r.Index * $STRIDE
        $dz = $(if ($r.Index -eq $YAW_RECORD) { $p.Yaw } else { $p.Dead })
        [Array]::Copy([BitConverter]::GetBytes([int]$dz),    0, $b, $o + 12, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$p.Sat), 0, $b, $o + 16, 4)
        $changed++
    }
    if ($changed -eq 0) {
        Write-Warn 'No joystick axes are configured, so there was nothing to change.'
        Write-Info 'Run BOB2_Controls.ps1 -Apply first, then start the game once.'
        return $false
    }
    $bk = Join-Path $ProfileDir ('backup_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.dat')
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    Copy-Item $Cfg $bk -Force
    [System.IO.File]::WriteAllBytes($Cfg, $b)
    Write-OK ("Applied '{0}' to {1} joystick axes - pitch/roll {2:0.0}%, rudder {3:0.0}%" -f $Key, $changed, ($p.Dead/100), ($p.Yaw/100))
    Write-Info ("Previous settings saved to {0}" -f $bk)
    return $true
}

# ---------------------------------------------------------------------
Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '  BOB2 AXIS SENSITIVITY' -ForegroundColor Cyan
Write-Host '========================================================' -ForegroundColor Cyan

if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) {
    Write-Err 'The game is running. It rewrites inputcfg.dat when it exits, so'
    Write-Err 'anything changed now would be discarded. Close it first.'
    exit 1
}

$d = Read-Records

switch ($Action) {
    'show' {
        Show-Records $d
        Write-Head 'PRESETS'
        foreach ($k in @('precision','standard','target','stock','pedals')) {
            Write-Host ("  {0,-11} pitch/roll {1,4:0.0}%   rudder {2,4:0.0}%" -f $k, ($PRESETS[$k].Dead/100), ($PRESETS[$k].Yaw/100)) -ForegroundColor White
            Write-Info ("              {0}" -f $PRESETS[$k].Why)
        }
        Write-Head 'HOW TO USE'
        Write-Info '  BOB2_Sensitivity.ps1 precision      apply the fighter preset'
        Write-Info '  BOB2_Sensitivity.ps1 save -Name spit   save current as a profile'
        Write-Info '  BOB2_Sensitivity.ps1 load -Name spit   load it back'
        Write-Info '  BOB2_Sensitivity.ps1 list           show saved profiles'
        Write-Head 'ABOUT CURVES'
        Write-Warn '  This game has no joystick response curves - see the header of'
        Write-Warn '  this script for the evidence. Deadzone is the only real lever.'
        Write-Info '  For actual curves, shape the axis before it reaches the game:'
        Write-Info '    Thrustmaster TARGET  - supports the T.16000M, has a curve editor'
        Write-Info '    Joystick Gremlin + vJoy - free, open source, per-axis curves'
        Write-Info '  Both present a virtual stick that BOB2 then sees as linear.'
    }
    'precision' { Set-Preset $d 'precision' | Out-Null }
    'standard'  { Set-Preset $d 'standard'  | Out-Null }
    'target'    { Set-Preset $d 'target'    | Out-Null }
    'pedals'    { Set-Preset $d 'pedals'    | Out-Null }
    'stock'     { Set-Preset $d 'stock'     | Out-Null }
    'save' {
        if (-not $Name) { Write-Err 'Give a name: -Name spitfire'; exit 1 }
        New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
        $p = Join-Path $ProfileDir "$Name.dat"
        Copy-Item $Cfg $p -Force
        Write-OK "Saved profile '$Name'"
        Write-Info $p
    }
    'load' {
        if (-not $Name) { Write-Err 'Give a name: -Name spitfire'; exit 1 }
        $p = Join-Path $ProfileDir "$Name.dat"
        if (-not (Test-Path $p)) { Write-Err "No profile called '$Name'."; exit 1 }
        Copy-Item $p $Cfg -Force
        Write-OK "Loaded profile '$Name'"
        Show-Records (Read-Records)
    }
    'list' {
        if (-not (Test-Path $ProfileDir)) { Write-Info 'No profiles saved yet.'; break }
        Write-Head 'SAVED PROFILES'
        Get-ChildItem $ProfileDir -Filter *.dat | ForEach-Object {
            Write-Info ('  {0,-24} {1}' -f $_.BaseName, $_.LastWriteTime)
        }
    }
}
Write-Host ''
