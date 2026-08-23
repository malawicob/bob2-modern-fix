# =====================================================================
#  BOB2 Launcher - the front door for Battle of Britain II
#  Part of the BOB2 2.13 Modern Fix
# =====================================================================
#
#  WHY THIS EXISTS
#    The fix package had grown to five loose .bat files sitting in the
#    game folder, and the order you ran them in mattered in ways nothing
#    told you about. The worst case: the game REWRITES bdg.txt and
#    settings.cfg when it exits, so editing settings while it is running
#    silently loses your changes on quit.
#
#    This window makes that impossible rather than merely documented.
#    Settings is disabled while Bob.exe is running; Measure FPS is
#    disabled while it is NOT (a capture taken at the menu is worthless).
#    The state refreshes every two seconds, so the buttons always
#    reflect what is actually safe to do right now.
#
#  BACKGROUND PHOTOGRAPH
#    IWM HU 54418. Pilots of 'B' Flight, No. 32 Squadron RAF relaxing at
#    Hawkinge in front of Hurricane Mk I P3522 'GZ-V', 29 July 1940.
#    Left to right: P/O R F Smythe, P/O K R Gillman, P/O J E Proctor,
#    F/Lt P M Brothers, P/O D H Grice, P/O P M Gardner, P/O A F Eckford.
#    All survived the war except Keith Gillman, posted missing on
#    25 August 1940.
#    Ministry of Information Second World War Press Agency Print
#    Collection, Imperial War Museums. Public domain - UK Crown copyright
#    has expired (work published before 1 June 1957).
#    https://commons.wikimedia.org/wiki/File:The_Battle_of_Britain_HU54418.jpg
#    https://www.iwm.org.uk/collections/item/object/205059622
# =====================================================================

param(
    # Renders the window to a PNG and exits. Used to check the layout
    # without having to eyeball it, and to produce README screenshots.
    [string]$RenderTo
)

$ErrorActionPreference = 'Stop'
$FixVersion = '1.6.27'

# $PSScriptRoot must be read at top level - inside a function it is the
# function's own scope and comes back empty. This has bitten this project
# before; do not move it.
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

# ---------------------------------------------------------------------
# Hide the console window this script was started from.
#
# BOB2.bat already passes -WindowStyle Hidden, but that is ignored when
# Windows Terminal is the default terminal application: WT hosts the
# console in its own window and never applies the requested show state.
# The result was a black "powershell.exe" window sitting behind the
# launcher for the whole session. Hiding our own console window works
# under both conhost and Windows Terminal.
#
# Belt and braces: BOB2.bat now starts us through BOB2_Launcher.vbs,
# which creates the process hidden in the first place, so under a normal
# setup no console is ever drawn at all.
# ---------------------------------------------------------------------
if (-not $RenderTo) {
    try {
        Add-Type -Namespace BOB2 -Name Win -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        $h = [BOB2.Win]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][BOB2.Win]::ShowWindow($h, 0) }   # SW_HIDE
    } catch { }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

# ---------------------------------------------------------------------
#  Locate the game. The launcher may live in the game folder itself or
#  in the BOB2-Win11-Fix subfolder of it.
# ---------------------------------------------------------------------
function Find-GameDir {
    param([string]$Start)
    $candidates = @(
        $Start,
        (Split-Path -Parent $Start),
        'D:\Battle of Britain II',
        'C:\Program Files (x86)\Battle of Britain II',
        'C:\Battle of Britain II'
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'Bob.exe'))) { return $c }
    }
    return $null
}

$GameDir = Find-GameDir -Start $ScriptDir

if (-not $GameDir) {
    [void][System.Windows.MessageBox]::Show(
        "Bob.exe was not found.`n`nPut this launcher in the Battle of Britain II folder, or in the BOB2-Win11-Fix folder inside it, and run it again.",
        'BOB2 Launcher', 'OK', 'Error')
    exit 1
}

# Helper scripts sit beside this launcher; fall back to the game folder.
function Resolve-Helper {
    param([string]$Name)
    foreach ($d in @($ScriptDir, $GameDir)) {
        $p = Join-Path $d $Name
        if (Test-Path $p) { return $p }
    }
    return $null
}

$BgImage = Join-Path $ScriptDir 'assets\hu54418.jpg'

# ---------------------------------------------------------------------
#  State probes
# ---------------------------------------------------------------------
function Test-GameRunning {
    [bool](Get-Process -Name 'Bob' -ErrorAction SilentlyContinue)
}

function Get-GameVersion {
    # BDG stamps the version into its own readme filenames; the .version
    # file written at install time is the authoritative record.
    $vf = Join-Path $GameDir 'BOB2-Win11-Fix.version'
    if (Test-Path $vf) {
        $m = Select-String -Path $vf -Pattern '^GameVersion\s*=\s*(.+)$' -ErrorAction SilentlyContinue
        if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    }
    if (Test-Path (Join-Path $GameDir 'BoBII BDG v2.13 Release Notes.pdf')) { return '2.13' }
    return 'unknown'
}

function Get-InstalledFixVersion {
    $vf = Join-Path $GameDir 'BOB2-Win11-Fix.version'
    if (Test-Path $vf) {
        $m = Select-String -Path $vf -Pattern '^FixVersion\s*=\s*(.+)$' -ErrorAction SilentlyContinue
        if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    }
    return $null
}

function Sync-FixVersion {
    # Re-read the stamp when the file changes. It used to be read once at
    # startup, so after Install and repair updated it the launcher went on
    # reporting the old version until you closed and reopened it - which
    # looked exactly like the update having failed.
    # Keyed on LastWriteTime so this costs a stat, not a file read, per tick.
    $vf = Join-Path $GameDir 'BOB2-Win11-Fix.version'
    $stamp = $null
    try { if (Test-Path $vf) { $stamp = (Get-Item $vf).LastWriteTimeUtc.Ticks } } catch { }
    if ($stamp -ne $script:FixVerStamp) {
        $script:FixVerStamp = $stamp
        $script:FixVer = Get-InstalledFixVersion
    }
}

# ---------------------------------------------------------------------
#  HIGHDPIAWARE must be PRESENT. This function used to remove it.
#
#  The old reasoning: the flag tells Windows the program handles DPI
#  itself and must not be scaled; BOB2 does no such thing, so with it set
#  the menus draw at true pixel size and look small. All true - but only
#  about the 2D menus, and the menu rescale already solves that.
#
#  What it missed is the 3D view. Without the flag Windows DPI-virtualises
#  the process, and dgVoodoo can no longer take exclusive fullscreen: the
#  game renders at its own resolution into a small window in the corner of
#  the screen. On a 2560x1600 display at 150% that is a 1024x768 image
#  scaled to 1536x1152 in the top-left, with the desktop around it.
#
#  So the launcher was removing the flag before every single launch and
#  breaking the 3D view to make the menus bigger - while shipping a menu
#  rescale whose entire purpose is to make the menus bigger. It now
#  ensures the flag instead, and the rescale does its job.
#
#  Verified on a 2560x1600 / 150% display against a working install that
#  predates this package and has the flag set.
# ---------------------------------------------------------------------
function Repair-DpiShim {
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $exe = Join-Path $GameDir 'Bob.exe'
    try {
        if (-not (Test-Path $key)) { return $false }
        $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if (-not $props -or -not ($props.PSObject.Properties.Name -contains $exe)) { return $false }
        $cur = $props.$exe
        if ($cur -match 'HIGHDPIAWARE') { return $false }   # already correct
        $parts = @($cur -split '\s+' | Where-Object { $_ -ne '' })
        if ($parts.Count -eq 0 -or $parts[0] -ne '~') { $parts = @('~') + $parts }
        $new = (($parts + 'HIGHDPIAWARE') -join ' ')
        Set-ItemProperty $key -Name $exe -Value $new
        return $true          # we had to add it
    }
    catch { return $false }
}

function Test-RunAsAdminShim {
    # The UAC prompt before every launch is not the launcher asking for
    # rights - it is the RUNASADMIN compatibility shim on Bob.exe. The game
    # does not need it: "D:\Battle of Britain II" grants Authenticated Users
    # Modify, so the game can write its saves, bdg.txt and logs perfectly well
    # as a normal user. The shim is a leftover from installs under Program
    # Files, where writing to the game folder really did need elevation.
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $exe = Join-Path $GameDir 'Bob.exe'
    try {
        if (-not (Test-Path $key)) { return $false }
        $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if (-not $props -or -not ($props.PSObject.Properties.Name -contains $exe)) { return $false }
        return ($props.$exe -match 'RUNASADMIN')
    } catch { return $false }
}

function Remove-RunAsAdminShim {
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $exe = Join-Path $GameDir 'Bob.exe'
    try {
        $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
        $cur = $props.$exe
        # Keep every other flag - DWM8And16BitMitigation and
        # DISABLEDXMAXIMIZEDWINDOWEDMODE are load bearing for this game.
        $new = (($cur -split '\s+') | Where-Object { $_ -ne 'RUNASADMIN' -and $_ -ne '' }) -join ' '
        if ($new -eq '~' -or -not $new) { Remove-ItemProperty $key -Name $exe -ErrorAction SilentlyContinue }
        else { Set-ItemProperty $key -Name $exe -Value $new }
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------------
# JOYSTICK AXIS DRIFT
#
#   BOB2 rewrites SAVEGAME\inputcfg.dat when it exits, and it rebuilds the
#   axis records from FACTORY DEFAULTS whenever the DirectInput device set
#   changes - stick unplugged, different USB port, different enumeration
#   order. Your tuned deadzones are silently replaced with 750 (7.5%) and
#   the first you know about it is the aircraft feeling wrong in the air.
#
#   That is exactly how the rudder-jerking fix was lost. So the launcher
#   keeps a reference copy and compares against it every refresh.
#
#   Record layout, from SAVEGAME\inputcfg.dat: 18 records of 278 bytes.
#     +8  kind (2 = joystick axis, 1 = mouse, 0 = keyboard)
#     +12 deadzone      (10000 = full scale, so 750 = 7.5%)
#     +16 saturation
#     +20 DirectInput axis index
#     +24 invert
#     +25 device/axis name, NUL terminated
#
#   Only kind 2 records are compared. Keyboard and mouse entries are not
#   tuned by us and change for reasons that are none of our business.
# ---------------------------------------------------------------------
$script:InputCfg = Join-Path $GameDir 'SAVEGAME\inputcfg.dat'
$script:AxisDir  = Join-Path $GameDir '_AxisProfiles'
$script:AxisRef  = Join-Path $script:AxisDir '_reference.dat'

function Get-AxisConfig {
    # Returns a single object, never an array - returning an array from a
    # PowerShell function unrolls it and has already caused one bug in this
    # project. Signature is a scalar string, which compares safely.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $b = [System.IO.File]::ReadAllBytes($Path)
    } catch { return $null }
    $REC = 278
    if ($b.Length -lt $REC) { return $null }
    $first = ''
    $sig = New-Object Text.StringBuilder
    $names = New-Object Text.StringBuilder
    $count = 0
    $max = [Math]::Min(18, [int][Math]::Floor($b.Length / $REC))
    for ($i = 0; $i -lt $max; $i++) {
        $o = $i * $REC
        if ([BitConverter]::ToInt32($b, $o + 8) -ne 2) { continue }
        $nm = ''
        for ($j = $o + 25; $j -lt ($o + 65) -and $b[$j] -ne 0; $j++) { $nm += [char]$b[$j] }
        $dead = [BitConverter]::ToInt32($b, $o + 12)
        $sat  = [BitConverter]::ToInt32($b, $o + 16)
        $ax   = [BitConverter]::ToInt32($b, $o + 20)
        $inv  = $b[$o + 24]
        if (-not $first) { $first = $nm }
        [void]$sig.Append("$nm|$dead|$sat|$ax|$inv;")
        $short = ($nm -split ':\s*')[-1]
        [void]$names.Append("$short $([Math]::Round($dead / 100.0, 1))%, ")
        $count++
    }
    if ($count -eq 0) { return $null }
    # Device name is the part before the colon in "T.16000M: Y Axis".
    $dev = ''
    if ($first -match '^(.*?):') { $dev = $matches[1].Trim() }
    [pscustomobject]@{
        Signature = $sig.ToString()
        Text      = $names.ToString().TrimEnd(', '.ToCharArray())
        Device    = $dev
        Count     = $count
        # Short enough to sit on one line of a nav subtitle.
        Summary   = $(if ($dev) { "$dev - $count axes" } else { "$count axes" })
    }
}

function Get-InputDrift {
    # 'nofile' | 'noref' | 'ok' | 'drifted'
    $cur = Get-AxisConfig $script:InputCfg
    if (-not $cur) { return [pscustomobject]@{ State = 'nofile'; Current = $null; Reference = $null } }
    $ref = Get-AxisConfig $script:AxisRef
    if (-not $ref) { return [pscustomobject]@{ State = 'noref'; Current = $cur; Reference = $null } }
    $state = if ($cur.Signature -eq $ref.Signature) { 'ok' } else { 'drifted' }
    [pscustomobject]@{ State = $state; Current = $cur; Reference = $ref }
}

function Save-AxisReference {
    try {
        if (-not (Test-Path $script:AxisDir)) { New-Item -ItemType Directory -Path $script:AxisDir -Force | Out-Null }
        Copy-Item $script:InputCfg $script:AxisRef -Force
        return $true
    } catch { return $false }
}

function Restore-AxisReference {
    # Never write while the game is up: it rewrites inputcfg.dat on exit and
    # would simply discard whatever we put there.
    if (Test-GameRunning) { return 'running' }
    try {
        $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
        Copy-Item $script:InputCfg (Join-Path $script:AxisDir "before_restore_$stamp.dat") -Force -ErrorAction SilentlyContinue
        Copy-Item $script:AxisRef $script:InputCfg -Force
        return 'ok'
    } catch { return $_.Exception.Message }
}

function Get-MenuScaleState {
    # Do NOT identify the build by hashing the whole file. BOB2_MenuScale.ps1
    # also applies the Windows 10 import fix (DebugBreak -> GetVersion) AFTER
    # the rescale, so the finished Bob.exe can never match the output checksum
    # recorded in the patch file - which made this report "not rescaled" even
    # when the rescale had applied perfectly.
    #
    # Instead, ask the file directly: a patch is applied when its edited
    # 16-bit values are present at their offsets. That stays true no matter
    # what else has since been changed elsewhere in the executable.
    $bob = Join-Path $GameDir 'Bob.exe'
    if (-not (Test-Path $bob)) { return 'unknown' }
    $buf = [System.IO.File]::ReadAllBytes($bob)

    $best = $null; $bestScore = 0
    foreach ($k in @('102','110','125','140')) {
        $p = Join-Path $ScriptDir "menuscale\scale$k.bin"
        if (-not (Test-Path $p)) { continue }
        $b = [System.IO.File]::ReadAllBytes($p)
        if ($b.Length -lt 48) { continue }
        if ([System.Text.Encoding]::ASCII.GetString($b[0..7]) -ne 'BOB2MSC1') { continue }
        $count = [BitConverter]::ToUInt32($b, 12)
        if ($count -le 0 -or (48 + $count * 8) -gt $b.Length) { continue }

        $ok = $true; $changed = 0
        for ($i = 0; $i -lt $count; $i++) {
            $off = 48 + $i * 8
            $o   = [BitConverter]::ToUInt32($b, $off)
            $exp = [BitConverter]::ToUInt16($b, $off + 4)
            $new = [BitConverter]::ToUInt16($b, $off + 6)
            if (($o + 1) -ge $buf.Length) { $ok = $false; break }
            if ([BitConverter]::ToUInt16($buf, $o) -ne $new) { $ok = $false; break }
            if ($new -ne $exp) { $changed++ }
        }
        # Several patches can match a byte they did not alter, so the winner is
        # the one that actually accounts for the most real changes.
        if ($ok -and $changed -gt $bestScore) { $bestScore = $changed; $best = $k }
    }
    if ($best) { return ('{0}.{1:00}x' -f [int]($best.Substring(0,1)), [int]$best.Substring(1)) }

    $orig = Join-Path $GameDir 'Bob.exe.unscaled'
    if (Test-Path $orig) {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $h = { param($x) ($md5.ComputeHash($x) | ForEach-Object { $_.ToString('x2') }) -join '' }
        if ((& $h $buf) -eq (& $h ([System.IO.File]::ReadAllBytes($orig)))) { return 'original size' }
    }
    return 'not rescaled'
}

function Get-WrapperState {
    # Only d3d9.dll is load-bearing - the game imports d3d9.dll and
    # d3dx9_35.dll and nothing from DirectDraw or D3D7.
    $d3d9 = Get-ChildItem -Path $GameDir -Filter 'd3d9.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $d3d9) {
        return [pscustomobject]@{ Name = 'Native Direct3D 9'; Detail = 'no wrapper installed'; Ok = $false }
    }
    $ver = ''
    try { $ver = $d3d9.VersionInfo.ProductVersion } catch { }
    if (Test-Path (Join-Path $GameDir 'dgVoodoo.conf')) {
        $d = if ($ver) { "version $ver" } else { 'version unknown' }
        return [pscustomobject]@{ Name = 'dgVoodoo2'; Detail = $d; Ok = $true }
    }
    if (Test-Path (Join-Path $GameDir 'dxvk.conf')) {
        return [pscustomobject]@{ Name = 'DXVK'; Detail = 'known to crash this game'; Ok = $false }
    }
    return [pscustomobject]@{ Name = 'Unknown d3d9.dll'; Detail = $ver; Ok = $false }
}

# PresentMon is not shipped - it is Intel's, and a separate download. Look
# for it where a user would sensibly put it rather than at one hardcoded
# path, which for anyone but the original machine simply does not exist.
$PresentMon = $null
foreach ($c in @(
    (Join-Path $ScriptDir 'tools\PresentMon.exe'),
    (Join-Path $ScriptDir 'PresentMon.exe'),
    (Join-Path $GameDir  'tools\PresentMon.exe'),
    (Join-Path $GameDir  'PresentMon.exe'),
    'D:\BOB2 Files\tools\PresentMon.exe')) {
    if ($c -and (Test-Path $c)) { $PresentMon = $c; break }
}
if (-not $PresentMon) { $PresentMon = Join-Path $ScriptDir 'tools\PresentMon.exe' }

# ---------------------------------------------------------------------
#  UI
# ---------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battle of Britain II"
        Width="1060" Height="800"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="NoResize"
        Background="#FF050608"
        FontFamily="Bahnschrift SemiCondensed, Segoe UI, Tahoma"
        TextOptions.TextFormattingMode="Ideal"
        TextOptions.TextRenderingMode="ClearType">

  <Window.Resources>

    <!-- Primary and secondary actions differ only in the accent bar and
         type size; the template is shared so hover and disabled states
         can never drift apart between them. -->
    <ControlTemplate x:Key="NavTemplate" TargetType="Button">
      <Grid Background="#01000000">
        <Border x:Name="bg" Background="#00FFFFFF"/>
        <Border x:Name="bar" Width="3" HorizontalAlignment="Left"
                Background="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}"/>
        <ContentPresenter Margin="22,13,16,13" VerticalAlignment="Center"/>
      </Grid>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter TargetName="bg" Property="Background" Value="#22FFFFFF"/>
          <Setter TargetName="bar" Property="Background" Value="#FFC8102E"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter TargetName="bg" Property="Background" Value="#3AFFFFFF"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Opacity" Value="0.30"/>
        </Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>

    <Style x:Key="Nav" TargetType="Button">
      <Setter Property="Template" Value="{StaticResource NavTemplate}"/>
      <Setter Property="Tag" Value="#00C8102E"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Focusable" Value="False"/>
    </Style>

    <Style x:Key="NavPrimary" TargetType="Button" BasedOn="{StaticResource Nav}">
      <Setter Property="Tag" Value="#FFC8102E"/>
    </Style>

    <!-- Lucide icons, ISC licence - https://lucide.dev
         Converted from lucide-static SVG; see assets/lucide-icons.xaml
         for the two conversions that are not obvious. -->
    <PathGeometry x:Key="IcoCompass" Figures="M16.24,7.76 l-1.804 5.411a2 2 0 0 1-1.265 1.265L7.76 16.24l1.804-5.411a2 2 0 0 1 1.265-1.265z M2.0,12.0 A10.0,10.0 0 1 0 22.0,12.0 A10.0,10.0 0 1 0 2.0,12.0 Z"/>
    <PathGeometry x:Key="IcoGauge" Figures="M12,14 l4-4 M3.34 19a10 10 0 1 1 17.32 0"/>
    <PathGeometry x:Key="IcoJoystick" Figures="M21 17a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-2Z M6 15v-2 M12 15V9 M9.0,6.0 A3.0,3.0 0 1 0 15.0,6.0 A3.0,3.0 0 1 0 9.0,6.0 Z"/>
    <PathGeometry x:Key="IcoLayers" Figures="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12 M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/>
    <PathGeometry x:Key="IcoPlay" Figures="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>
    <PathGeometry x:Key="IcoScaling" Figures="M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7 M14 15H9v-5 M16 3h5v5 M21 3 9 15"/>
    <PathGeometry x:Key="IcoSlidersHorizontal" Figures="M10 5H3 M12 19H3 M14 3v4 M16 17v4 M21 12h-9 M21 19h-5 M21 5h-7 M8 10v4 M8 12H3"/>
    <PathGeometry x:Key="IcoWrench" Figures="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.106-3.105c.32-.322.863-.22.983.218a6 6 0 0 1-8.259 7.057l-7.91 7.91a1 1 0 0 1-2.999-3l7.91-7.91a6 6 0 0 1 7.057-8.259c.438.12.54.662.219.984z"/>

    <Style x:Key="NavTitle" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#FFF4F1EB"/>
      <Setter Property="FontSize" Value="18"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="TextOptions.TextFormattingMode" Value="Ideal"/>
    </Style>

    <Style x:Key="NavSub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#FF9A958C"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Margin" Value="0,2,0,0"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>

    <!-- Window chrome buttons -->
    <Style x:Key="Chrome" TargetType="Button">
      <Setter Property="Foreground" Value="#FFB8B2A8"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Width" Value="42"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#00FFFFFF">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#33FFFFFF"/>
                <Setter Property="Foreground" Value="#FFFFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Pill" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#FF8E8880"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="PillSep" TargetType="TextBlock" BasedOn="{StaticResource Pill}">
      <Setter Property="Text" Value="  ·  "/>
      <Setter Property="Foreground" Value="#FF4A4640"/>
    </Style>

  </Window.Resources>

  <Grid x:Name="Root">

    <!-- photograph -->
    <Image x:Name="Bg" Stretch="UniformToFill" HorizontalAlignment="Center" VerticalAlignment="Center"/>

    <!-- scrims: keep the pilots and P3522 legible while giving the
         button column a surface dark enough for small type -->
    <Rectangle HorizontalAlignment="Left" Width="500">
      <Rectangle.Fill>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#F7050608" Offset="0.0"/>
          <GradientStop Color="#EE050608" Offset="0.52"/>
          <GradientStop Color="#00050608" Offset="1.0"/>
        </LinearGradientBrush>
      </Rectangle.Fill>
    </Rectangle>
    <Rectangle VerticalAlignment="Top" Height="110">
      <Rectangle.Fill>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#D0050608" Offset="0.0"/>
          <GradientStop Color="#00050608" Offset="1.0"/>
        </LinearGradientBrush>
      </Rectangle.Fill>
    </Rectangle>
    <Rectangle VerticalAlignment="Bottom" Height="150">
      <Rectangle.Fill>
        <LinearGradientBrush StartPoint="0,1" EndPoint="0,0">
          <GradientStop Color="#F2050608" Offset="0.0"/>
          <GradientStop Color="#D0050608" Offset="0.45"/>
          <GradientStop Color="#00050608" Offset="1.0"/>
        </LinearGradientBrush>
      </Rectangle.Fill>
    </Rectangle>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- ============ header / drag bar ============ -->
      <Grid x:Name="Header" Grid.Row="0" Height="38" Background="#01000000">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
          <Button x:Name="BtnMin"   Style="{StaticResource Chrome}" Content="&#x2013;" ToolTip="Minimise"/>
          <Button x:Name="BtnClose" Style="{StaticResource Chrome}" Content="&#x2715;" ToolTip="Close"/>
        </StackPanel>
      </Grid>

      <!-- ============ body ============ -->
      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="430"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" Margin="40,4,30,0">

          <TextBlock Text="BATTLE OF BRITAIN II"
                     Foreground="#FFF4F1EB" FontSize="34" FontWeight="Bold"
                     LineHeight="38"/>
          <TextBlock Text="WINGS OF VICTORY"
                     Foreground="#FFC8102E" FontSize="19" FontWeight="Bold"
                     Margin="1,3,0,0"/>
          <!-- Filled in from $FixVersion at startup rather than hardcoded,
               so the version on screen cannot drift from the package. -->
          <TextBlock x:Name="LblMod" Text="2.13 MODERN FIX"
                     Foreground="#FF8E8880" FontSize="12" Margin="1,9,0,0"
                     FontFamily="Cascadia Mono, Consolas"/>
          <Rectangle Height="1" Fill="#33FFFFFF" Margin="1,14,0,0"/>

          <StackPanel Margin="-22,16,0,0">

            <Button x:Name="BtnPlay" Style="{StaticResource NavPrimary}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoPlay}" Fill="{x:Null}" Stroke="#FFC8102E"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock Text="PLAY" Style="{StaticResource NavTitle}" FontSize="21"/>
                <TextBlock x:Name="SubPlay" Text="start the game with the performance fixes applied" Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

            <Button x:Name="BtnWizard" Style="{StaticResource Nav}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoCompass}" Fill="{x:Null}" Stroke="#FF8E8880"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock x:Name="TitleWizard" Text="SETUP WIZARD" Style="{StaticResource NavTitle}"/>
                <TextBlock x:Name="SubWizard" Text="six questions and it sets the game up for your PC" Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

            <Button x:Name="BtnSettings" Style="{StaticResource Nav}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoSlidersHorizontal}" Fill="{x:Null}" Stroke="#FF8E8880"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock Text="SETTINGS" Style="{StaticResource NavTitle}"/>
                <TextBlock x:Name="SubSettings" Text="graphics, view, gameplay and key mapping" Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

            <Button x:Name="BtnFps" Style="{StaticResource Nav}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoGauge}" Fill="{x:Null}" Stroke="#FF8E8880"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock Text="FRAME RATE TEST" Style="{StaticResource NavTitle}"/>
                <TextBlock x:Name="SubFps" Text="60-second capture while you fly" Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

            <Button x:Name="BtnWrapper" Style="{StaticResource Nav}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoLayers}" Fill="{x:Null}" Stroke="#FF8E8880"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock Text="GRAPHICS TRANSLATOR" Style="{StaticResource NavTitle}"/>
                <TextBlock x:Name="SubWrapper" Text="checking..." Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

            <Button x:Name="BtnScale" Style="{StaticResource Nav}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoScaling}" Fill="{x:Null}" Stroke="#FF8E8880"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock Text="IN-GAME MENU SIZE" Style="{StaticResource NavTitle}"/>
                <TextBlock x:Name="SubScale" Text="checking..." Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

            <Button x:Name="BtnAxes" Style="{StaticResource Nav}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoJoystick}" Fill="{x:Null}" Stroke="#FF8E8880"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock Text="JOYSTICK SETUP" Style="{StaticResource NavTitle}"/>
                <TextBlock x:Name="SubAxes" Text="checking..." Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

            <Button x:Name="BtnSetup" Style="{StaticResource Nav}">
              <StackPanel>
              <StackPanel Orientation="Horizontal">
                <Viewbox Width="24" Height="24" Margin="0,1,16,0" VerticalAlignment="Center">
                  <Canvas Width="24" Height="24">
                    <Path Data="{StaticResource IcoWrench}" Fill="{x:Null}" Stroke="#FF8E8880"
                          StrokeThickness="1.6" StrokeStartLineCap="Round"
                          StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                  </Canvas>
                </Viewbox>
                <StackPanel VerticalAlignment="Center">
                <TextBlock Text="INSTALL AND REPAIR" Style="{StaticResource NavTitle}"/>
                <TextBlock x:Name="SubSetup" Text="apply the patches and put anything broken back" Style="{StaticResource NavSub}"/>
                </StackPanel>
              </StackPanel>
              </StackPanel>
            </Button>

          </StackPanel>
        </StackPanel>
      </Grid>

      <!-- ============ footer ============ -->
      <Grid Grid.Row="2" Margin="42,0,30,16">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
          <Ellipse x:Name="Dot" Width="7" Height="7" Fill="#FF6B6660" Margin="0,0,8,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="LblState" Style="{StaticResource Pill}" Foreground="#FFB8B2A8" Text="Not running"/>
          <TextBlock Style="{StaticResource PillSep}"/>
          <TextBlock x:Name="LblGame"    Style="{StaticResource Pill}" Text="Game"/>
          <TextBlock Style="{StaticResource PillSep}"/>
          <TextBlock x:Name="LblFix"     Style="{StaticResource Pill}" Text="Fix"/>
          <TextBlock Style="{StaticResource PillSep}"/>
          <TextBlock x:Name="LblWrapper" Style="{StaticResource Pill}" Text="Wrapper"/>
        </StackPanel>

        <StackPanel Grid.Row="1" Orientation="Horizontal">
          <TextBlock x:Name="LblCredit" Foreground="#FF8E8880" FontSize="12" VerticalAlignment="Center"
                     Text="IWM HU 54418 — 'B' Flight, No. 32 Squadron RAF, Hawkinge, 29 July 1940. Public domain."/>
          <Button x:Name="BtnCredit" Style="{StaticResource Chrome}" Content="about this photograph"
                  Width="Auto" Height="22" FontSize="12" Margin="10,0,0,0" Padding="7,0,7,0"
                  Foreground="#FF8E8880"/>
        </StackPanel>

        <!-- Unofficial-mod disclaimer. Short here, in full behind the button:
             the footer states the fact, the dialog carries the detail. -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,6,0,0">
          <TextBlock Foreground="#FF8E8880" FontSize="12" VerticalAlignment="Center"
                     Text="Unofficial community mod. Not affiliated with or endorsed by A2A Simulations. Use at your own risk."/>
          <Button x:Name="BtnLegal" Style="{StaticResource Chrome}" Content="full disclaimer"
                  Width="Auto" Height="22" FontSize="12" Margin="10,0,0,0" Padding="7,0,7,0"
                  Foreground="#FF8E8880"/>
        </StackPanel>
      </Grid>

    </Grid>

    <!-- A borderless window needs an edge of its own or it bleeds into a
         dark desktop with no visible boundary. -->
    <Border BorderBrush="#2EFFFFFF" BorderThickness="1" IsHitTestVisible="False"/>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

function C { param($n) $win.FindName($n) }

# Explicit brush conversion. PowerShell will usually coerce a "#AARRGGBB"
# string via the registered TypeConverter, but it is not guaranteed for
# every property and a silent failure here shows up as an invisible
# control, so convert once and be certain.
$script:BrushCache = @{}
function Brush {
    param([string]$Hex)
    if (-not $script:BrushCache.ContainsKey($Hex)) {
        $script:BrushCache[$Hex] = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Hex)
    }
    return $script:BrushCache[$Hex]
}

# Background photograph. Loaded here rather than in XAML so the path can
# be relative to the script instead of the working directory.
if (Test-Path $BgImage) {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.UriSource = New-Object System.Uri($BgImage)
    $bmp.CacheOption = 'OnLoad'
    $bmp.EndInit()
    (C 'Bg').Source = $bmp
}

(C 'LblMod').Text = "2.13 MODERN FIX v$FixVersion"

# --- window chrome ---
(C 'BtnClose').Add_Click({ $win.Close() })
(C 'BtnMin').Add_Click({ $win.WindowState = 'Minimized' })
(C 'Header').Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })

# ---------------------------------------------------------------------
#  Actions
# ---------------------------------------------------------------------

# Wire our custom title bar. Called after every dialog load - dragging a
# WindowStyle="None" window has to be done by hand, and the close button is
# a Border rather than a Button so it cannot inherit a dialog's button style.
function Add-Chrome {
    param($dlg)
    $bar = $dlg.FindName('ChromeBar')
    if ($bar) { $bar.Add_MouseLeftButtonDown({ param($s,$e) $dlg.DragMove() }.GetNewClosure()) }
    $x = $dlg.FindName('ChromeClose')
    if ($x) {
        $x.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled = $true; $dlg.Close() }.GetNewClosure())
        $x.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#C8102E') })
        $x.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
    }
}

function Show-Note {
    param([string]$Text, [string]$Title = 'BOB2 Launcher', [string]$Icon = 'Information')
    [void][System.Windows.MessageBox]::Show($win, $Text, $Title, 'OK', $Icon)
}

function Show-Ask {
    param([string]$Text, [string]$Title = 'BOB2 Launcher', [string]$Icon = 'Warning')
    return ([System.Windows.MessageBox]::Show($win, $Text, $Title, 'YesNo', $Icon) -eq 'Yes')
}

function Invoke-DriftCheck {
    # Returns $true if it is safe to carry on. Called on startup and again
    # immediately before Play, because the drift happens when the GAME exits
    # - so the state can change while this window is sitting open.
    $d = Get-InputDrift
    switch ($d.State) {
        'drifted' {
            $msg = "Your joystick axis settings have been reset.`n`n" +
                   "now:        $($d.Current.Text)`n" +
                   "reference:  $($d.Reference.Text)`n`n" +
                   "BOB2 rebuilds these from factory defaults whenever the set of " +
                   "connected devices changes - a stick unplugged, or plugged into a " +
                   "different port. It is not something you did.`n`n" +
                   "Put your saved settings back?"
            if (Show-Ask $msg 'Joystick settings were reset') {
                $r = Restore-AxisReference
                if ($r -eq 'ok')          { Show-Note "Restored.`n`n$($d.Reference.Text)" 'Joystick settings' }
                elseif ($r -eq 'running') { Show-Note 'Close the game first - it rewrites this file when it exits.' 'Joystick settings' 'Warning'; return $false }
                else                      { Show-Note "Could not restore.`n`n$r" 'Joystick settings' 'Warning'; return $false }
            }
        }
        'noref' {
            if (Show-Ask ("No reference joystick profile is saved yet, so drift cannot be detected.`n`n" +
                          "current: $($d.Current.Text)`n`n" +
                          "Save these as the reference? Only do this if the controls feel right - " +
                          "saving a reset config would make the reset look correct from now on.") `
                         'Save a reference profile?' 'Question') {
                if (Save-AxisReference) { Show-Note 'Saved as your reference profile.' 'Joystick settings' }
            }
        }
    }
    return $true
}

(C 'BtnPlay').Add_Click({
    # Last chance before the game starts - Windows may have put the shim
    # back since the launcher opened.
    if (Repair-DpiShim) {
        Show-Note ("Bob.exe was missing the HIGHDPIAWARE compatibility flag. Without it Windows " +
                   "scales the whole process, and the 3D view renders into a small window in the " +
                   "corner of the screen instead of filling it.`n`nAdded it. Starting the game now.")
    }
    # Check the axis settings here too, not just at startup: the reset happens
    # when the GAME exits, so a launcher left open across a session would
    # otherwise still be showing the state from before.
    if (-not (Invoke-DriftCheck)) { return }
    $bat = Resolve-Helper 'BOB2_Launch.bat'
    if (-not $bat) { Show-Note "BOB2_Launch.bat is missing from the fix folder." 'Not found' 'Warning'; return }
    try {
        # Only elevate if Bob.exe still carries RUNASADMIN. When it does, we
        # must elevate HERE rather than let the .bat re-spawn itself, because
        # an elevated child does not inherit the affinity mask from
        # "start /affinity" - the pinning would silently not stick. When the
        # shim is gone there is nothing to elevate for, and no UAC prompt.
        if (Test-RunAsAdminShim) {
            Start-Process -FilePath $bat -WorkingDirectory $GameDir -Verb RunAs
        } else {
            Start-Process -FilePath $bat -WorkingDirectory $GameDir
        }
    } catch {
        Show-Note "Launch was cancelled or blocked.`n`n$($_.Exception.Message)" 'Could not launch' 'Warning'
    }
})

function Test-WizardDone {
    # Written by the wizard when it reaches its last screen. Distinct from
    # BOB2-Win11-Fix.setup-done, which only records that we OFFERED setup -
    # declining that is not the same as having been through it.
    Test-Path (Join-Path $GameDir 'BOB2-Win11-Fix.wizard-done')
}

function Start-Wizard {
    # Through the .vbs so no console appears; the .ps1 is the fallback.
    $vbs = Resolve-Helper 'BOB2_Wizard.vbs'
    $ps1 = Resolve-Helper 'BOB2_Wizard.ps1'
    if (-not $ps1) { Show-Note "BOB2_Wizard.ps1 is missing from the fix folder." 'Not found' 'Warning'; return }
    if ($vbs) {
        Start-Process -FilePath 'wscript.exe' -ArgumentList '//nologo', "`"$vbs`"" -WorkingDirectory $GameDir
    } else {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden `
            -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$ps1`"" -WorkingDirectory $GameDir
    }
}

(C 'BtnWizard').Add_Click({ Start-Wizard })

(C 'BtnSettings').Add_Click({
    $ps1 = Resolve-Helper 'BOB2_Config.ps1'
    if (-not $ps1) { Show-Note "BOB2_Config.ps1 is missing from the fix folder." 'Not found' 'Warning'; return }
    # Through the .vbs, not powershell.exe directly. Starting PowerShell here
    # always created a console window, and under Windows Terminal it cannot be
    # hidden after the fact - it sat behind the settings window all session.
    # wscript has no console of its own and starts it hidden from the outset.
    $vbs = Resolve-Helper 'BOB2_Config.vbs'
    if ($vbs) {
        Start-Process -FilePath 'wscript.exe' -ArgumentList '//nologo', "`"$vbs`"" -WorkingDirectory $GameDir
    } else {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$ps1`"" `
            -WorkingDirectory $GameDir
    }
})

$fpsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Measure frame rate" Width="580" SizeToContent="Height"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="None"
        Background="#FF14161A" Foreground="#FFF4F1EB"
        FontFamily="Bahnschrift SemiCondensed, Segoe UI, Tahoma">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFF4F1EB"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#FF22262C" BorderBrush="#FF3A4048" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF313740"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#FFC8102E"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF171A1F"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. The default WPF chrome shows the powershell.exe
         icon and a Windows title bar, which looks nothing like the rest of
         the app and tells the user they are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="MEASURE FRAME RATE" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent"
              HorizontalAlignment="Right" Cursor="Hand">
        <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Grid>

  <Border Background="#FF14161A">
  <StackPanel Margin="26,22,26,20">
    <TextBlock Text="MEASURE FRAME RATE" FontSize="18" FontWeight="Bold"/>
    <Border Background="#22C8102E" BorderBrush="#FFC8102E" BorderThickness="0,0,0,0" Margin="0,14,0,0" Padding="12,9,12,9">
      <StackPanel>
        <TextBlock Text="DO NOT ALT-TAB" FontWeight="Bold" FontSize="13" Foreground="#FFE8586F"/>
        <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="#FFD8D3CA" Margin="0,3,0,0"
                   Text="In exclusive fullscreen this game loses its Direct3D device when it loses focus, and crashes. The capture is armed here and triggered from inside the cockpit, so you never have to leave the game."/>
      </StackPanel>
    </Border>
    <TextBlock Margin="0,16,0,0" TextWrapping="Wrap" FontSize="12.5" Foreground="#FF9A958C"
               Text="Intel PresentMon records every presented frame, which gives you averages and 1% lows you can compare between settings - unlike an on-screen counter."/>
    <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,16,0,16"/>

    <RadioButton x:Name="RbHotkey" Foreground="#FFF4F1EB" FontSize="14" GroupName="m" IsChecked="True">
      <StackPanel Margin="4,0,0,0">
        <TextBlock Text="Hotkey  (recommended)" FontWeight="SemiBold"/>
        <TextBlock TextWrapping="Wrap" FontSize="11.5" Foreground="#FF9A958C" Margin="0,2,0,0"
                   Text="Arms and waits. Once you are flying, press ALT+SHIFT+F11 to record 60 seconds. Scroll Lock lights up while it records and goes out when it is done, so you get feedback without looking away."/>
        <TextBlock TextWrapping="Wrap" FontSize="11.5" Foreground="#FF6B6660" Margin="0,4,0,0"
                   Text="ALT+SHIFT+F11 is unbound in your keys.txt. F11, SHIFT+F11 and CTRL+F11 are all taken by the game, and Windows swallows a registered hotkey rather than passing it on."/>
      </StackPanel>
    </RadioButton>

    <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
      <RadioButton x:Name="RbTimed" Foreground="#FFF4F1EB" FontSize="14" GroupName="m" VerticalAlignment="Center">
        <TextBlock Text="Automatic, starting in" Margin="4,0,0,0" FontWeight="SemiBold"/>
      </RadioButton>
      <TextBox x:Name="TxtDelay" Text="120" Width="52" Margin="8,0,8,0" Height="24"
               Background="#FF22262C" Foreground="#FFF4F1EB" BorderBrush="#FF3A4048"
               VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
      <TextBlock Text="seconds" VerticalAlignment="Center" Foreground="#FF9A958C" FontSize="12.5"/>
    </StackPanel>
    <TextBlock TextWrapping="Wrap" FontSize="11.5" Foreground="#FF9A958C" Margin="26,4,0,0"
               Text="No keypress needed - be airborne before the countdown ends. Use this if the hotkey is awkward on your keyboard."/>

    <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
      <TextBlock Text="Label for this run:" VerticalAlignment="Center" Foreground="#FF9A958C" FontSize="12.5"/>
      <TextBox x:Name="TxtLabel" Text="run" Width="160" Margin="8,0,0,0" Height="24"
               Background="#FF22262C" Foreground="#FFF4F1EB" BorderBrush="#FF3A4048"
               VerticalContentAlignment="Center"/>
      <TextBlock Text="  (appears in the CSV filename)" VerticalAlignment="Center" Foreground="#FF6B6660" FontSize="11.5"/>
    </StackPanel>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
      <Button x:Name="BtnCancel" Content="Cancel" Width="92" Height="30" Margin="0,0,10,0"/>
      <Button x:Name="BtnArm"    Content="Arm capture" Width="118" Height="30" IsDefault="True"/>
    </StackPanel>
  </StackPanel>
  </Border>
    </DockPanel>
  </Border>
</Window>

'@

(C 'BtnFps').Add_Click({
    $bat = Resolve-Helper 'BOB2_MeasureFPS.bat'
    if (-not $bat) { Show-Note "BOB2_MeasureFPS.bat is missing from the fix folder." 'Not found' 'Warning'; return }
    if (-not (Test-Path $PresentMon)) {
        Show-Note "Intel PresentMon was not found at`n  $PresentMon`n`nDownload it from github.com/GameTechDev/PresentMon/releases and put it there, or edit the TOOL line in BOB2_MeasureFPS.bat to point at your copy." 'PresentMon missing' 'Warning'
        return
    }

    $r = New-Object System.Xml.XmlNodeReader ([xml]$fpsXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    $dlg.Owner = $win
    Add-Chrome $dlg
    Add-Chrome $dlg
    $dlg.FindName('BtnCancel').Add_Click({ $dlg.Close() }.GetNewClosure())
    $dlg.FindName('BtnArm').Add_Click({
        $label = $dlg.FindName('TxtLabel').Text.Trim()
        # The label lands in a filename, so keep it to something a
        # filesystem will accept rather than trusting whatever was typed.
        $label = ($label -replace '[^A-Za-z0-9_\-]', '')
        if (-not $label) { $label = 'run' }
        if ($dlg.FindName('RbTimed').IsChecked) {
            $delay = 0
            if (-not [int]::TryParse($dlg.FindName('TxtDelay').Text.Trim(), [ref]$delay) -or $delay -lt 5) {
                [void][System.Windows.MessageBox]::Show($dlg, 'Enter a delay of at least 5 seconds.', 'Measure frame rate', 'OK', 'Warning')
                return
            }
            $args = @($label, 'timed', "$delay")
        }
        else {
            $args = @($label, 'hotkey')
        }
        $dlg.Close()
        try { Start-Process -FilePath $bat -ArgumentList $args -WorkingDirectory $GameDir -Verb RunAs }
        catch { Show-Note "Could not start the capture.`n`n$($_.Exception.Message)" 'Measure frame rate' 'Warning' }
    }.GetNewClosure())
    [void]$dlg.ShowDialog()
}.GetNewClosure())

$scaleXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Menu size" Width="600" SizeToContent="Height"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="None"
        Background="#FF14161A" Foreground="#FFF4F1EB"
        FontFamily="Bahnschrift SemiCondensed, Segoe UI, Tahoma">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFF4F1EB"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#FF22262C" BorderBrush="#FF3A4048" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF313740"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#FFC8102E"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF171A1F"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. The default WPF chrome shows the powershell.exe
         icon and a Windows title bar, which looks nothing like the rest of
         the app and tells the user they are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="MENU SIZE" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent"
              HorizontalAlignment="Right" Cursor="Hand">
        <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Grid>

  <Border Background="#FF14161A">
  <StackPanel Margin="26,22,26,20">
    <TextBlock Text="MENU SIZE" FontSize="18" FontWeight="Bold"/>
    <TextBlock Margin="0,8,0,0" TextWrapping="Wrap" FontSize="12.5" Foreground="#FF9A958C"
               Text="The menus are 154 Windows dialogs laid out at a fixed size, so on a big screen they end up small and marooned. This rescales every one of them, and the font with them."/>
    <Border Background="#22C8102E" Margin="0,14,0,0" Padding="12,9,12,9">
      <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="#FFD8D3CA"
                 Text="This affects the MENU screens only. Text drawn over the 3D view while you are flying - the status line and the warning messages - comes from a different renderer and does not change."/>
    </Border>
    <TextBlock x:Name="Cur" Margin="0,16,0,0" FontSize="12.5" Foreground="#FFB8B2A8"/>
    <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,14,0,14"/>

    <RadioButton x:Name="R102" Foreground="#FFF4F1EB" FontSize="14" GroupName="s">
      <StackPanel Margin="4,0,0,0"><TextBlock Text="1.02x   font 8pt" FontWeight="SemiBold"/>
      <TextBlock Text="Barely changed. For 1280 wide or less." FontSize="11.5" Foreground="#FF9A958C"/></StackPanel>
    </RadioButton>
    <RadioButton x:Name="R110" Foreground="#FFF4F1EB" FontSize="14" GroupName="s" Margin="0,10,0,0">
      <StackPanel Margin="4,0,0,0"><TextBlock Text="1.10x   font 9pt" FontWeight="SemiBold"/>
      <TextBlock Text="Small increase. For 1366 wide and up." FontSize="11.5" Foreground="#FF9A958C"/></StackPanel>
    </RadioButton>
    <RadioButton x:Name="R125" Foreground="#FFF4F1EB" FontSize="14" GroupName="s" Margin="0,10,0,0">
      <StackPanel Margin="4,0,0,0"><TextBlock Text="1.25x   font 10pt" FontWeight="SemiBold"/>
      <TextBlock Text="Comfortable. For 1600 wide and up." FontSize="11.5" Foreground="#FF9A958C"/></StackPanel>
    </RadioButton>
    <RadioButton x:Name="R140" Foreground="#FFF4F1EB" FontSize="14" GroupName="s" Margin="0,10,0,0">
      <StackPanel Margin="4,0,0,0"><TextBlock Text="1.40x   font 11pt   (recommended)" FontWeight="SemiBold"/>
      <TextBlock Text="Largest text. For 1920 wide and up. Needs 1608 px across - anything narrower will clip." FontSize="11.5" Foreground="#FF9A958C" TextWrapping="Wrap"/></StackPanel>
    </RadioButton>
    <RadioButton x:Name="RORG" Foreground="#FFF4F1EB" FontSize="14" GroupName="s" Margin="0,14,0,0">
      <StackPanel Margin="4,0,0,0"><TextBlock Text="Original size" FontWeight="SemiBold"/>
      <TextBlock Text="Undo the rescale and put the stock Bob.exe back." FontSize="11.5" Foreground="#FF9A958C"/></StackPanel>
    </RadioButton>

    <TextBlock x:Name="Msg" Margin="0,16,0,0" FontSize="12" TextWrapping="Wrap" Foreground="#FF9A958C"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="BtnClose" Content="Close" Width="92" Height="30" Margin="0,0,10,0"/>
      <Button x:Name="BtnApply" Content="Apply" Width="102" Height="30" IsDefault="True"/>
    </StackPanel>
  </StackPanel>
  </Border>
    </DockPanel>
  </Border>
</Window>

'@

(C 'BtnScale').Add_Click({
    $ps1 = Resolve-Helper 'BOB2_MenuScale.ps1'
    if (-not $ps1) { Show-Note "BOB2_MenuScale.ps1 is missing from the fix folder." 'Not found' 'Warning'; return }

    $r = New-Object System.Xml.XmlNodeReader ([xml]$scaleXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    $dlg.Owner = $win
    Add-Chrome $dlg
    Add-Chrome $dlg

    $map = @{ '1.02x' = 'R102'; '1.10x' = 'R110'; '1.25x' = 'R125'; '1.40x' = 'R140'; 'original size' = 'RORG' }
    $setCur = {
        $st = Get-MenuScaleState
        $dlg.FindName('Cur').Text = "Currently installed:  $st"
        if ($map.ContainsKey($st)) { $dlg.FindName($map[$st]).IsChecked = $true }
    }
    & $setCur

    $dlg.FindName('BtnClose').Add_Click({ $dlg.Close() }.GetNewClosure())
    $dlg.FindName('BtnApply').Add_Click({
        $sel = $null
        foreach ($pair in @(@('R102','102'), @('R110','110'), @('R125','125'), @('R140','140'), @('RORG','original'))) {
            if ($dlg.FindName($pair[0]).IsChecked) { $sel = $pair[1]; break }
        }
        if (-not $sel) { $dlg.FindName('Msg').Text = 'Pick a size first.'; return }
        if (Test-GameRunning) {
            $dlg.FindName('Msg').Text = 'The game is running. Close it first - Bob.exe cannot be replaced while in use.'
            return
        }
        $dlg.FindName('Msg').Text = 'Applying...'
        $dlg.FindName('BtnApply').IsEnabled = $false
        # The heavy lifting stays in BOB2_MenuScale.ps1 so the console tool and
        # this dialog can never disagree about how a patch is applied.
        $p = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',"`"$ps1`"",'-Scale',$sel `
                -WorkingDirectory (Split-Path -Parent $ps1) -WindowStyle Hidden -Wait -PassThru
        $dlg.FindName('BtnApply').IsEnabled = $true
        & $setCur
        if ($p.ExitCode -eq 0) {
            $dlg.FindName('Msg').Text = 'Done. Start the game to see it. If a menu clips off the right, come back and pick a smaller size.'
            $dlg.FindName('Msg').Foreground = Brush '#FF4CAF50'
        } else {
            $dlg.FindName('Msg').Text = "The patch was refused (exit $($p.ExitCode)). Nothing was written. Run BOB2_MenuScale.bat for the full reason."
            $dlg.FindName('Msg').Foreground = Brush '#FFC8102E'
        }
        Update-State
    }.GetNewClosure())

    [void]$dlg.ShowDialog()
}.GetNewClosure())

(C 'BtnSetup').Add_Click({
    # The GUI, not the console menu. BOB2_Setup.bat still exists for
    # troubleshooting but nothing in normal use opens it any more.
    $vbs = Resolve-Helper 'BOB2_Install.vbs'
    $ps1 = Resolve-Helper 'BOB2_Install.ps1'
    if (-not $ps1) { Show-Note "BOB2_Install.ps1 is missing from the fix folder." 'Not found' 'Warning'; return }
    if ($vbs) {
        Start-Process -FilePath 'wscript.exe' -ArgumentList '//nologo', "`"$vbs`"" -WorkingDirectory $GameDir
    } else {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden `
            -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$ps1`"" -WorkingDirectory $GameDir
    }
})

# ---------------------------------------------------------------------
#  Wrapper chooser
# ---------------------------------------------------------------------
$wrapperXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Graphics wrapper" Width="560" SizeToContent="Height"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="None"
        Background="#FF14161A" Foreground="#FFF4F1EB"
        FontFamily="Bahnschrift SemiCondensed, Segoe UI, Tahoma">
  <Window.Resources>
    <!-- Default WPF buttons are light grey and read as a foreign element
         against this background. Same shape, dark palette. -->
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFF4F1EB"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#FF22262C" BorderBrush="#FF3A4048" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF313740"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#FFC8102E"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF171A1F"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. The default WPF chrome shows the powershell.exe
         icon and a Windows title bar, which looks nothing like the rest of
         the app and tells the user they are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="GRAPHICS WRAPPER" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent"
              HorizontalAlignment="Right" Cursor="Hand">
        <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Grid>

  <Border Background="#FF14161A">
  <StackPanel Margin="26,22,26,20">
    <TextBlock Text="GRAPHICS WRAPPER" FontSize="18" FontWeight="Bold" Foreground="#FFF4F1EB"/>
    <TextBlock Margin="0,8,0,0" TextWrapping="Wrap" FontSize="12.5" Foreground="#FF9A958C"
               Text="BOB2 is a Direct3D 9 game, so the only file that matters is d3d9.dll. The game asks the driver for a 0x0 fullscreen buffer during mode enumeration; native D3D9 and DXVK both reject it and the game crashes dereferencing the null device."/>
    <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,16,0,16"/>
    <TextBlock x:Name="Cur" FontSize="12.5" Foreground="#FFB8B2A8" Margin="0,0,0,14"/>
    <RadioButton x:Name="RbDgv" Foreground="#FFF4F1EB" FontSize="14" GroupName="w">
      <StackPanel Margin="4,0,0,0">
        <TextBlock Text="dgVoodoo2  (recommended)" FontWeight="SemiBold"/>
        <TextBlock Text="Translates D3D9 to D3D11 and handles the legacy mode enumeration. The only configuration this game is known to run reliably on."
                   FontSize="11.5" Foreground="#FF9A958C" TextWrapping="Wrap" Margin="0,2,0,0"/>
      </StackPanel>
    </RadioButton>
    <RadioButton x:Name="RbNative" Foreground="#FFF4F1EB" FontSize="14" GroupName="w" Margin="0,14,0,0">
      <StackPanel Margin="4,0,0,0">
        <TextBlock Text="Native Direct3D 9" FontWeight="SemiBold"/>
        <TextBlock Text="No wrapper. Slightly lower CPU overhead, which matters because this engine is CPU-bound - but it crashes on entering 3D on most modern systems."
                   FontSize="11.5" Foreground="#FF9A958C" TextWrapping="Wrap" Margin="0,2,0,0"/>
      </StackPanel>
    </RadioButton>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
      <Button x:Name="BtnCancel" Content="Cancel" Width="92" Height="30" Margin="0,0,10,0"/>
      <Button x:Name="BtnApply"  Content="Apply"  Width="92" Height="30" IsDefault="True"/>
    </StackPanel>
  </StackPanel>
  </Border>
    </DockPanel>
  </Border>
</Window>

'@

(C 'BtnWrapper').Add_Click({
    $bat = Resolve-Helper 'BOB2_SetWrapper.bat'
    if (-not $bat) { Show-Note "BOB2_SetWrapper.bat is missing from the fix folder." 'Not found' 'Warning'; return }

    $r = New-Object System.Xml.XmlNodeReader ([xml]$wrapperXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    $dlg.Owner = $win
    Add-Chrome $dlg
    Add-Chrome $dlg

    $w = Get-WrapperState
    $dlg.FindName('Cur').Text = "Currently active:  $($w.Name)$(if ($w.Detail) { ",  $($w.Detail)" })"
    if ($w.Name -eq 'dgVoodoo2') { $dlg.FindName('RbDgv').IsChecked = $true }
    elseif ($w.Name -eq 'Native Direct3D 9') { $dlg.FindName('RbNative').IsChecked = $true }

    $dlg.FindName('BtnCancel').Add_Click({ $dlg.Close() })
    $dlg.FindName('BtnApply').Add_Click({
        $mode = if ($dlg.FindName('RbNative').IsChecked) { 'native' } else { 'dgvoodoo' }
        $dlg.Close()
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"`"$bat`" $mode`"" `
            -WorkingDirectory $GameDir -WindowStyle Hidden -Wait
        Update-State
    }.GetNewClosure())

    [void]$dlg.ShowDialog()
}.GetNewClosure())

# ---------------------------------------------------------------------
#  Photograph credit
# ---------------------------------------------------------------------
$axesXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Joystick axes" Width="620" SizeToContent="Height"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="None"
        Background="#FF14161A" Foreground="#FFF4F1EB"
        FontFamily="Bahnschrift SemiCondensed, Segoe UI, Tahoma">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFF4F1EB"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Background" Value="#FF23262C"/>
      <Setter Property="BorderBrush" Value="#FF626A77"/>
      <Setter Property="Padding" Value="10,4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <!-- Without a Template the system one is used, and a focused button
           turns Aero blue - which looked like a different app entirely. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1"
                    CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#FF2C313A"/></Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="B" Property="Background" Value="#FF3A404A"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. The default WPF chrome shows the powershell.exe
         icon and a Windows title bar, which looks nothing like the rest of
         the app and tells the user they are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="JOYSTICK AXES" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent"
              HorizontalAlignment="Right" Cursor="Hand">
        <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Grid>

  <Border Padding="26">
  <StackPanel>
    <TextBlock Text="JOYSTICK AXES" FontSize="17" FontWeight="Bold"/>
    <TextBlock Margin="0,10,0,0" TextWrapping="Wrap" FontSize="12.5" Foreground="#FF9A958C"
               Text="BOB2 rewrites SAVEGAME\inputcfg.dat when it exits, and rebuilds these from factory defaults whenever the set of connected devices changes - a stick unplugged, or moved to another USB port. Your tuned deadzones silently become 7.5%. The reference below is what the launcher compares against so it can tell you when that has happened."/>

    <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,18,0,14"/>
    <TextBlock Text="Now" FontSize="11.5" Foreground="#FF9A958C"/>
    <TextBlock x:Name="TxtNow" Margin="0,2,0,0" FontSize="13" TextWrapping="Wrap"/>
    <TextBlock Text="Reference" FontSize="11.5" Foreground="#FF9A958C" Margin="0,12,0,0"/>
    <TextBlock x:Name="TxtRef" Margin="0,2,0,0" FontSize="13" TextWrapping="Wrap"/>
    <TextBlock x:Name="TxtState" Margin="0,14,0,0" FontSize="12.5" TextWrapping="Wrap"/>

    <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,18,0,16"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnJoyConfig"  Content="Configure buttons and axes" Height="30" Margin="0,0,8,0"/>
      <Button x:Name="BtnSaveRef"    Content="Save current as reference" Height="30" Margin="0,0,8,0"/>
      <Button x:Name="BtnRestoreRef" Content="Restore reference"         Height="30" Margin="0,0,8,0"/>
      <Button x:Name="BtnClose"      Content="Close" Width="92" Height="30" IsDefault="True"/>
    </StackPanel>
    <TextBlock x:Name="Msg" Margin="0,14,0,0" FontSize="12" TextWrapping="Wrap" Foreground="#FF9A958C"/>
  </StackPanel>
  </Border>
    </DockPanel>
  </Border>
</Window>

'@

(C 'BtnAxes').Add_Click({
    $r = New-Object System.Xml.XmlNodeReader ([xml]$axesXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    $dlg.Owner = $win
    Add-Chrome $dlg
    Add-Chrome $dlg

    $refresh = {
        $d = Get-InputDrift
        $dlg.FindName('TxtNow').Text = $(if ($d.Current) { $d.Current.Text } else { 'no joystick axes configured' })
        $dlg.FindName('TxtRef').Text = $(if ($d.Reference) { $d.Reference.Text } else { 'none saved' })
        $st = $dlg.FindName('TxtState')
        switch ($d.State) {
            'drifted' { $st.Text = 'These do not match. The game has reset your settings.'
                        $st.Foreground = Brush '#FFD08A2E' }
            'noref'   { $st.Text = 'No reference saved yet, so drift cannot be detected. Save one only if the controls feel right - saving a reset config would make the reset look correct from then on.'
                        $st.Foreground = Brush '#FF9A958C' }
            'nofile'  { $st.Text = 'No joystick axes are configured. Plug the stick in and start the game once.'
                        $st.Foreground = Brush '#FF9A958C' }
            default   { $st.Text = 'These match. Nothing to do.'
                        $st.Foreground = Brush '#FF4CAF50' }
        }
        $dlg.FindName('BtnRestoreRef').IsEnabled = ($d.State -eq 'drifted')
        $dlg.FindName('BtnSaveRef').IsEnabled    = ($null -ne $d.Current)
    }
    & $refresh

    $dlg.FindName('BtnSaveRef').Add_Click({
        # Deliberately confirmed. Saving a reset config as the reference is
        # the one action here that could quietly enshrine the wrong values.
        if ([System.Windows.MessageBox]::Show($dlg,
                "Save the CURRENT axis settings as your reference?`n`nOnly do this if the controls feel right.",
                'Save reference', 'YesNo', 'Question') -ne 'Yes') { return }
        if (Save-AxisReference) { $dlg.FindName('Msg').Text = 'Saved. This is what the launcher will compare against from now on.' }
        else { $dlg.FindName('Msg').Text = 'Could not write the reference file.' }
        & $refresh
    }.GetNewClosure())

    $dlg.FindName('BtnRestoreRef').Add_Click({
        $res = Restore-AxisReference
        if ($res -eq 'ok')          { $dlg.FindName('Msg').Text = 'Restored. The old file was kept in _AxisProfiles.' }
        elseif ($res -eq 'running') { $dlg.FindName('Msg').Text = 'Close the game first - it rewrites this file on exit.' }
        else                        { $dlg.FindName('Msg').Text = "Could not restore. $res" }
        & $refresh
    }.GetNewClosure())

    # Straight into the controls page, rather than "now close this and go to
    # Settings and find the joystick page".
    $dlg.FindName('BtnJoyConfig').Add_Click({
        $ps1 = Resolve-Helper 'BOB2_Config.ps1'
        if (-not $ps1) { Show-Note 'BOB2_Config.ps1 is missing from the fix folder.' 'Not found' 'Warning'; return }
        # The page name contains spaces. Unquoted, PowerShell binds "Joystick"
        # to -Page and then treats "and" and "axes" as stray positional
        # arguments, so the configurator never starts and the button looks dead.
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden `
            -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$ps1`"",'-Page','"Joystick and axes"' `
            -WorkingDirectory $GameDir
        $dlg.Close()
    }.GetNewClosure())

    $dlg.FindName('BtnClose').Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
    Update-State
})

$legalXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Disclaimer" Width="640" SizeToContent="Height"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="None"
        Background="#FF14161A" Foreground="#FFF4F1EB"
        FontFamily="Bahnschrift SemiCondensed, Segoe UI, Tahoma">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFF4F1EB"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Background" Value="#FF23262C"/>
      <Setter Property="BorderBrush" Value="#FF626A77"/>
      <Setter Property="Padding" Value="10,4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1"
                    CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#FF2C313A"/></Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="B" Property="Background" Value="#FF3A404A"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Body" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI, Tahoma"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="#FFAEB6C2"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="LineHeight" Value="20"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
    </Style>
    <Style x:Key="Head" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#FFC8973F"/>
      <Setter Property="Margin" Value="0,4,0,6"/>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. The default WPF chrome shows the powershell.exe
         icon and a Windows title bar, which looks nothing like the rest of
         the app and tells the user they are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="DISCLAIMER" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent"
              HorizontalAlignment="Right" Cursor="Hand">
        <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Grid>

  <Border Padding="26">
  <StackPanel>
    <TextBlock Text="DISCLAIMER" FontSize="19" FontWeight="Bold"/>

    <TextBlock Style="{StaticResource Head}" Text="This is an unofficial community mod" Margin="0,16,0,6"/>
    <TextBlock Style="{StaticResource Body}"
               Text="It is not affiliated with, endorsed by, sponsored by or connected to A2A Simulations, Shockwave Productions, Rowan Software, or any current or former rights holder in Battle of Britain II: Wings of Victory. All trademarks and copyrights belong to their respective owners."/>

    <TextBlock Style="{StaticResource Head}" Text="Not the community Windows 10 Patch"/>
    <TextBlock Style="{StaticResource Body}"
               Text="This is a separate project. The community &quot;BOB2 Windows 10 Patch&quot; is built on the 2.01 executable and replaces textures, sounds and aircraft models. This mod is for patch 2.13, keeps the 2.13 AI, ground objects and MultiSkin, and replaces no game content at all."/>

    <TextBlock Style="{StaticResource Head}" Text="Use at your own risk"/>
    <TextBlock Style="{StaticResource Body}"
               Text="This software is provided as is, without warranty of any kind, express or implied. The authors accept no liability for any damage, data loss or lost progress arising from its use. You are responsible for keeping your own backups."/>

    <TextBlock Style="{StaticResource Head}" Text="What it changes"/>
    <TextBlock Style="{StaticResource Body}"
               Text="This mod modifies files inside your Battle of Britain II installation, including the game executable, configuration files and control bindings. Every file it changes is backed up first, and every change can be undone from this launcher. Even so, a full copy of the game folder before you start is the only backup nobody regrets."/>

    <TextBlock Style="{StaticResource Head}" Text="You need a legitimate copy"/>
    <TextBlock Style="{StaticResource Body}"
               Text="This mod contains no game content. It patches a copy of Battle of Britain II that you already own. It is distributed free of charge and must never be sold."/>

    <TextBlock Style="{StaticResource Head}" Text="Credits"/>
    <TextBlock Style="{StaticResource Body}"
               Text="Battle of Britain II: Wings of Victory by Rowan Software and Shockwave Productions. Patch 2.13 by the BOB2 Development Group. dgVoodoo2 by Dege. Icons by Lucide (ISC licence). Photograph © IWM, public domain."/>

    <Button x:Name="BtnOk" Content="Close" Width="92" Height="30" HorizontalAlignment="Right" Margin="0,10,0,0" IsDefault="True"/>
  </StackPanel>
  </Border>
    </DockPanel>
  </Border>
</Window>

'@

(C 'BtnLegal').Add_Click({
    $r = New-Object System.Xml.XmlNodeReader ([xml]$legalXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    $dlg.Owner = $win
    Add-Chrome $dlg
    Add-Chrome $dlg
    $dlg.FindName('BtnOk').Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
})

$creditXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="About this photograph" Width="600" SizeToContent="Height"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="None"
        Background="#FF14161A" Foreground="#FFF4F1EB"
        FontFamily="Bahnschrift SemiCondensed, Segoe UI, Tahoma">
  <Window.Resources>
    <!-- Default WPF buttons are light grey and read as a foreign element
         against this background. Same shape, dark palette. -->
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#FFF4F1EB"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="#FF22262C" BorderBrush="#FF3A4048" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF313740"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#FFC8102E"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF171A1F"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. The default WPF chrome shows the powershell.exe
         icon and a Windows title bar, which looks nothing like the rest of
         the app and tells the user they are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="ABOUT THIS PHOTOGRAPH" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent"
              HorizontalAlignment="Right" Cursor="Hand">
        <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Grid>

  <Border Background="#FF14161A">
  <StackPanel Margin="26,22,26,20">
    <TextBlock Text="IWM HU 54418" FontSize="18" FontWeight="Bold"/>
    <TextBlock Margin="0,10,0,0" TextWrapping="Wrap" FontSize="13" Foreground="#FFD8D3CA"
               Text="Pilots of 'B' Flight, No. 32 Squadron RAF relax on the grass at Hawkinge in front of Hawker Hurricane Mk I P3522, coded GZ-V, on 29 July 1940. The squadron was based at Biggin Hill and flew daily from Hawkinge as a forward airfield during the opening weeks of the Battle of Britain."/>
    <TextBlock Margin="0,14,0,0" TextWrapping="Wrap" FontSize="12.5" Foreground="#FF9A958C"
               Text="Left to right: Pilot Officer R F Smythe; Pilot Officer K R Gillman; Pilot Officer J E Proctor; Flight Lieutenant P M Brothers; Pilot Officer D H Grice; Pilot Officer P M Gardner; Pilot Officer A F Eckford."/>
    <TextBlock Margin="0,14,0,0" TextWrapping="Wrap" FontSize="12.5" Foreground="#FFC8102E"
               Text="All seven survived the war except Keith Gillman, who was posted missing on 25 August 1940, aged 19."/>
    <Rectangle Height="1" Fill="#33FFFFFF" Margin="0,18,0,16"/>
    <TextBlock TextWrapping="Wrap" FontSize="11.5" Foreground="#FF8E8880"
               Text="Ministry of Information Second World War Press Agency Print Collection, Imperial War Museums. Public domain: created by the United Kingdom Government and published before 1 June 1957, so UK Crown copyright has expired."/>
    <TextBlock Margin="0,12,0,0" FontSize="11.5" Foreground="#FF8E8880" Text="Sources"/>
    <TextBlock Margin="0,4,0,0" FontSize="11.5">
      <Hyperlink x:Name="L1" Foreground="#FF7FA6D8"
                 NavigateUri="https://commons.wikimedia.org/wiki/File:The_Battle_of_Britain_HU54418.jpg">Wikimedia Commons — file page and licence</Hyperlink>
    </TextBlock>
    <TextBlock Margin="0,4,0,0" FontSize="11.5">
      <Hyperlink x:Name="L2" Foreground="#FF7FA6D8"
                 NavigateUri="https://www.iwm.org.uk/collections/item/object/205059622">Imperial War Museums — catalogue entry</Hyperlink>
    </TextBlock>
    <TextBlock Margin="0,4,0,0" FontSize="11.5">
      <Hyperlink x:Name="L3" Foreground="#FF7FA6D8"
                 NavigateUri="https://en.wikipedia.org/wiki/Battle_of_Britain">Wikipedia — Battle of Britain</Hyperlink>
    </TextBlock>
    <Button x:Name="BtnOk" Content="Close" Width="92" Height="30" HorizontalAlignment="Right" Margin="0,20,0,0" IsDefault="True"/>
  </StackPanel>
  </Border>
    </DockPanel>
  </Border>
</Window>

'@

(C 'BtnCredit').Add_Click({
    $r = New-Object System.Xml.XmlNodeReader ([xml]$creditXaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    $dlg.Owner = $win
    Add-Chrome $dlg
    Add-Chrome $dlg
    $nav = { param($s, $e) Start-Process $e.Uri.AbsoluteUri; $e.Handled = $true }
    foreach ($n in 'L1', 'L2', 'L3') { $dlg.FindName($n).Add_RequestNavigate($nav) }
    $dlg.FindName('BtnOk').Add_Click({ $dlg.Close() }.GetNewClosure())
    [void]$dlg.ShowDialog()
})

# ---------------------------------------------------------------------
#  Live state. This is the whole point of the launcher: the buttons that
#  are unsafe right now are not merely discouraged, they are unavailable.
# ---------------------------------------------------------------------
$script:GameVer = Get-GameVersion
$script:FixVer  = Get-InstalledFixVersion
# Strip it once at startup too, so the status bar tells the truth.
$script:DpiFixed = Repair-DpiShim

function Update-State {
    $running = Test-GameRunning
    $w = Get-WrapperState

    $wizDone = Test-WizardDone
    # PLAY stays shut until the wizard has been through once. Everything it
    # sets - the graphics translator, the menu size, the frame-rate floor -
    # is what makes the game start and stay started.
    (C 'BtnPlay').IsEnabled     = (-not $running) -and $wizDone
    (C 'BtnSettings').IsEnabled = -not $running
    (C 'BtnSetup').IsEnabled    = -not $running
    (C 'BtnWrapper').IsEnabled  = -not $running
    (C 'BtnScale').IsEnabled    = -not $running
    (C 'BtnAxes').IsEnabled     = -not $running
    (C 'BtnWizard').IsEnabled   = -not $running

    # Always available. It used to be enabled only while the game was
    # running, which was wrong: the capture is ARMED from here and then
    # triggered by a hotkey from inside the cockpit. Requiring the game to
    # be up meant Alt-Tabbing to reach this button - and Alt-Tab crashes
    # this game, because it cannot survive losing the D3D9 device.
    (C 'BtnFps').IsEnabled = $true

    if ($running) {
        (C 'SubPlay').Text     = 'the game is already running'
        # The game rewrites bdg.txt and settings.cfg on exit, so anything
        # changed underneath it is discarded on quit.
        (C 'SubSettings').Text = 'unavailable while the game is running — it rewrites its config on exit'
        (C 'SubFps').Text      = 'fly for 60 seconds and get a report on how smooth it was'
        (C 'SubWrapper').Text  = 'unavailable while the game is running'
        (C 'SubSetup').Text    = 'unavailable while the game is running'
        (C 'SubScale').Text    = 'unavailable while the game is running'
        (C 'SubAxes').Text     = 'unavailable while the game is running — it rewrites inputcfg.dat on exit'
        (C 'SubWizard').Text   = 'unavailable while the game is running'
        (C 'SubAxes').Foreground = Brush '#FF9A958C'
        (C 'Dot').Fill      = Brush '#FF4CAF50'
        (C 'LblState').Text = 'Running'
    }
    else {
        (C 'SubPlay').Text     = $(if ($wizDone) { 'start the game with the performance fixes applied' }
                                   else { 'complete the Setup wizard first' })
        (C 'SubPlay').Foreground = $(if ($wizDone) { Brush '#FF9A958C' } else { Brush '#FFE8394F' })
        (C 'TitleWizard').Text = $(if ($wizDone) { 'SETUP WIZARD' } else { '!  SETUP WIZARD' })
        (C 'SubWizard').Text   = $(if ($wizDone) { 'run it again to change any of your answers' }
                                   else { 'not done yet - six questions, about three minutes' })
        (C 'SubWizard').Foreground = $(if ($wizDone) { Brush '#FF9A958C' } else { Brush '#FFE8394F' })
        (C 'SubSettings').Text = 'graphics, view, controls and difficulty - all in one place'
        (C 'SubFps').Text      = 'fly for 60 seconds and get a report on how smooth it was'
        (C 'SubWrapper').Text  = "$($w.Name)$(if ($w.Detail) { " — $($w.Detail)" })"
        (C 'SubSetup').Text    = 'apply the patches and put anything broken back'
        (C 'SubScale').Text    = "in-game menu and text size — currently $(Get-MenuScaleState)$(if ($script:DpiFixed) { '  ·  removed a DPI flag that was hiding it' })"
        $drift = Get-InputDrift
        switch ($drift.State) {
            'drifted' {
                (C 'SubAxes').Text = "$($drift.Current.Summary) — settings were RESET, click to put them back"
                (C 'SubAxes').Foreground = Brush '#FFD08A2E'
            }
            'noref' {
                (C 'SubAxes').Text = "$($drift.Current.Summary) — no reference saved yet"
                (C 'SubAxes').Foreground = Brush '#FF9A958C'
            }
            'nofile' {
                (C 'SubAxes').Text = 'no joystick axes configured'
                (C 'SubAxes').Foreground = Brush '#FF9A958C'
            }
            default {
                (C 'SubAxes').Text = "$($drift.Current.Summary) — matches your saved reference"
                (C 'SubAxes').Foreground = Brush '#FF9A958C'
            }
        }
        (C 'Dot').Fill      = Brush '#FF6B6660'
        (C 'LblState').Text = 'Not running'
    }

    Sync-FixVersion
    (C 'LblGame').Text = "Game $script:GameVer"

    (C 'LblWrapper').Text = $w.Name
    (C 'LblWrapper').Foreground = $(if ($w.Ok) { Brush '#FF8E8880' } else { Brush '#FFC8102E' })

    # Reset the colour every tick - a warning that is set but never cleared
    # keeps shouting after the thing it warned about has been fixed.
    if (-not $script:FixVer) {
        (C 'LblFix').Text = 'Mod not installed'
        (C 'LblFix').Foreground = Brush '#FFC8102E'
    }
    elseif ($script:FixVer -ne $FixVersion) {
        # "Fix 1.5.0 (package is 1.6.8)" meant nothing unless you already knew
        # how this thing is built. Two versions exist: the one recorded in the
        # game folder as installed, and the one in the files you are running.
        # Say which is which, and say what to do about it.
        (C 'LblFix').Text = "Mod $script:FixVer installed - $FixVersion available"
        (C 'LblFix').Foreground = Brush '#FFD08A2E'
    }
    else {
        (C 'LblFix').Text = "Mod $script:FixVer"
        (C 'LblFix').Foreground = Brush '#FF8E8880'
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Update-State })

# Pulse the marker beside SETUP WIZARD until it has been run. Slow and
# two-state - a fast blink in the corner of the eye is an irritation, not a
# prompt. Stops the moment the wizard is finished.
$script:Pulse = $false
$pulseTimer = New-Object System.Windows.Threading.DispatcherTimer
$pulseTimer.Interval = [TimeSpan]::FromMilliseconds(750)
$pulseTimer.Add_Tick({
    if (Test-WizardDone) { (C 'BtnWizard').Tag = '#00C8102E'; return }
    $script:Pulse = -not $script:Pulse
    (C 'BtnWizard').Tag = $(if ($script:Pulse) { '#FFC8102E' } else { '#33C8102E' })
})
$win.Add_ContentRendered({
    Update-State
    if ($RenderTo) {
        $root = $win.Content
        # Update-State has just changed text that affects layout. Without an
        # explicit pass the bitmap captures the pre-update arrangement, which
        # is how the first screenshot came out still showing the XAML
        # placeholder strings.
        $root.UpdateLayout()
        $w = [int][Math]::Ceiling($root.ActualWidth)
        $h = [int][Math]::Ceiling($root.ActualHeight)
        $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, 'Pbgra32')
        $rtb.Render($root)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [System.IO.File]::Create($RenderTo)
        $enc.Save($fs); $fs.Close()
        Write-Host "rendered $w x $h -> $RenderTo"
        $win.Close()
        return
    }
    $timer.Start()
    $pulseTimer.Start()
    # After the window is on screen, so the dialog has an owner to sit over.
    # Never during -RenderTo: a screenshot run must not block on a prompt.

    # First run goes straight to guided setup. The marker lives beside the
    # game, not in the fix folder, so reinstalling the fix over the top does
    # not make an existing install look new again.
    $firstRunMark = Join-Path $GameDir 'BOB2-Win11-Fix.setup-done'
    if (-not (Test-Path $firstRunMark)) {
        $ans = [System.Windows.MessageBox]::Show($win,
            "It looks like this is a fresh install.`n`nShall I walk you through setting it up? Six questions, about three minutes - and you can change any of it afterwards.",
            'Set up Battle of Britain II', 'YesNo', 'Question')
        # Written either way. Saying no once should not mean being asked
        # every single time the launcher opens.
        try { Set-Content -Path $firstRunMark -Value (Get-Date -Format 's') -Encoding ASCII } catch { }
        if ($ans -eq 'Yes') { Start-Wizard; return }
    }
    [void](Invoke-DriftCheck)
})
$win.Add_Closed({ $timer.Stop(); $pulseTimer.Stop() })

[void]$win.ShowDialog()
