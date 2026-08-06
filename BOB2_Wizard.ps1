# =====================================================================
#  FIRST FLIGHT - guided setup for Battle of Britain II
#  Part of the BOB2 Windows 10/11 Fix
# =====================================================================
#
#  WHY THIS EXISTS
#    The launcher is a good control panel and a bad teacher. It assumes
#    you already know what a graphics wrapper is, that menu scaling is a
#    thing, and that your joystick needs checking. Someone installing this
#    for the first time has no way to know what order any of it goes in.
#
#    This asks six questions, in the order they actually depend on each
#    other, and does the work. Pressing Next six times produces a good
#    result: every step already has the right answer selected. It is a
#    review, not an interrogation.
#
#  THE FOUR RULES IT IS BUILT ON
#    1. Every step has a correct answer already chosen.
#    2. No step is a dead end - every one has a "leave it alone" option.
#    3. Nothing is irreversible, and every step says so.
#    4. It is re-runnable, and it knows it: on a second run each step
#       reports what is currently set.
#
#  WHERE THE WORK HAPPENS
#    Detection here is read-only and deliberately small. Anything that
#    WRITES is delegated to the script that already owns that job -
#    BOB2_MenuScale.ps1, BOB2_SetWrapper.bat, BOB2_Setup.ps1 - so there
#    is one implementation of each change, not two that drift apart.
# =====================================================================

param(
    # Renders a given step to a PNG and exits. For checking layout without
    # clicking through. 0 = welcome, 1-6 = steps, 7 = done.
    [string]$RenderTo,
    [int]$RenderStep = 0
)

$ErrorActionPreference = 'Stop'

# Hide our own console. BOB2_Wizard.vbs normally starts us hidden, but this
# covers running the .ps1 directly - and Windows Terminal ignores
# -WindowStyle Hidden, so it cannot be fixed from the caller alone.
if (-not $RenderTo) {
    try {
        Add-Type -Namespace BOB2W -Name Win -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        $h = [BOB2W.Win]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][BOB2W.Win]::ShowWindow($h, 0) }
    } catch { }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------------------------------------------------------------------
# One window at a time. Every click of the launcher button started another
# process, so it was easy to end up with three of these stacked on top of
# each other. A named mutex is the cheapest reliable guard, and if one is
# already up we bring it to the front rather than silently doing nothing.
# ---------------------------------------------------------------------
if (-not $RenderTo) {
$script:SingleInstance = New-Object System.Threading.Mutex($false, 'Global\BOB2FirstFlight')
if (-not $script:SingleInstance.WaitOne(0)) {
    try {
        Add-Type -Namespace BOB2S -Name Fg -MemberDefinition @'
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        foreach ($p in (Get-Process powershell -ErrorAction SilentlyContinue)) {
            if ($p.MainWindowTitle -eq 'First Flight - Battle of Britain II') {
                [void][BOB2S.Fg]::ShowWindow($p.MainWindowHandle, 9)   # SW_RESTORE
                [void][BOB2S.Fg]::SetForegroundWindow($p.MainWindowHandle)
                break
            }
        }
    } catch { }
    exit 0
}
}

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

trap {
    [void][System.Windows.MessageBox]::Show(
        ($_.Exception.Message + "`n`n" + $_.InvocationInfo.PositionMessage),
        'First Flight', 'OK', 'Error')
    break
}

# ---------------------------------------------------------------------
#  DETECTION - read-only, no side effects
# ---------------------------------------------------------------------
function Find-GameDir {
    param([string]$Start)
    foreach ($c in @($Start, (Split-Path -Parent $Start),
                     'D:\Battle of Britain II',
                     'C:\Program Files (x86)\Battle of Britain II',
                     'C:\Battle of Britain II')) {
        if ($c -and (Test-Path (Join-Path $c 'Bob.exe'))) { return $c }
    }
    return $null
}


# ---------------------------------------------------------------------
#  WHICH WINDOWS IS THIS?
#
#  Use the BUILD NUMBER, never ProductName. On a Windows 11 25H2 machine
#  the registry still reports ProductName = "Windows 10 Home Single
#  Language" - Microsoft never updated that value, and a check written
#  against it would tell every Windows 11 user they were on Windows 10.
#
#      build >= 22000   Windows 11
#      build 10240..21999   Windows 10
#      anything lower   older, and not supported
#
#  Supported here means Windows 10 1809 (build 17763) and later, plus every
#  Windows 11. That is what dgVoodoo2's D3D11 path and the compatibility
#  shims this mod removes actually need.
# ---------------------------------------------------------------------
function Get-WindowsRelease {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = 0; $disp = ''; $ubr = 0
    try {
        $p = Get-ItemProperty $k -ErrorAction Stop
        $build = [int]$p.CurrentBuild
        $disp  = $(if ($p.DisplayVersion) { $p.DisplayVersion } else { $p.ReleaseId })
        $ubr   = [int]$p.UBR
    } catch { }
    if ($build -le 0) {
        try { $build = [Environment]::OSVersion.Version.Build } catch { }
    }
    $name = if ($build -ge 22000) { 'Windows 11' }
            elseif ($build -ge 10240) { 'Windows 10' }
            elseif ($build -ge 9600) { 'Windows 8.1' }
            elseif ($build -ge 7600) { 'Windows 7' }
            else { 'an older Windows' }
    $supported = ($build -ge 17763)
    [pscustomobject]@{
        Name      = $name
        Build     = $build
        Display   = $disp
        Full      = $("$name" + $(if ($disp) { " $disp" } else { '' }) + " (build $build" + $(if ($ubr) { ".$ubr" } else { '' }) + ')')
        Supported = $supported
        Why       = $(if ($supported) { '' }
                      elseif ($build -ge 10240) { 'This mod needs Windows 10 version 1809 (build 17763) or later.' }
                      else { "This mod is for Windows 10 and Windows 11. $name cannot run it - the graphics translator needs Direct3D 11 and the compatibility flags it removes do not exist here." })
    }
}

function Get-GameVersion {
    param([string]$Dir)
    $v = Join-Path $Dir 'bob2_ver.txt'
    if (Test-Path $v) {
        $t = (Get-Content $v -First 4 -ErrorAction SilentlyContinue) -join ' '
        if ($t -match '(\d+\.\d+)') { return $matches[1] }
    }
    return '?'
}

function Get-WrapperName {
    # Identified by its config file, not by the DLL version. dgVoodoo's
    # d3d9.dll reports 4.9.0.904 - the D3D9 version it impersonates - which
    # is not the dgVoodoo release and would be nonsense on screen. Same test
    # the launcher uses, so the two windows always agree.
    param([string]$Dir)
    $d3d9 = Join-Path $Dir 'd3d9.dll'
    if (-not (Test-Path $d3d9)) { return "Windows' own Direct3D" }
    $ver = ''
    try { $ver = (Get-Item $d3d9).VersionInfo.ProductVersion } catch { }
    if (Test-Path (Join-Path $Dir 'dgVoodoo.conf')) {
        return $(if ($ver) { "dgVoodoo2 $ver" } else { 'dgVoodoo2' })
    }
    if (Test-Path (Join-Path $Dir 'dxvk.conf')) { return 'DXVK' }
    return 'an unrecognised d3d9.dll'
}

function Get-MenuScalePct {
    param([string]$Dir)
    $bob = Join-Path $Dir 'Bob.exe'
    if (-not (Test-Path $bob)) { return $null }
    $buf = [IO.File]::ReadAllBytes($bob)
    foreach ($k in @('140','125','110','102')) {
        $p = Join-Path $ScriptDir "menuscale\scale$k.bin"
        if (-not (Test-Path $p)) { continue }
        $b = [IO.File]::ReadAllBytes($p)
        if ($b.Length -lt 48 -or [Text.Encoding]::ASCII.GetString($b[0..7]) -ne 'BOB2MSC1') { continue }
        $count = [BitConverter]::ToUInt32($b, 12)
        if ($count -le 0 -or (48 + $count * 8) -gt $b.Length) { continue }
        $ok = $true
        for ($i = 0; $i -lt $count; $i++) {
            $off = 48 + $i * 8
            $o = [BitConverter]::ToUInt32($b, $off)
            $new = [BitConverter]::ToUInt16($b, $off + 6)
            if (($o + 1) -ge $buf.Length -or [BitConverter]::ToUInt16($buf, $o) -ne $new) { $ok = $false; break }
        }
        if ($ok) { return [int]$k }
    }
    return 100
}

function Get-Joystick {
    # winmm rather than DirectInput: it needs no interop beyond two calls and
    # gives real axis and button counts.
    try {
        Add-Type -Namespace BOB2W -Name Joy -MemberDefinition @'
    [StructLayout(LayoutKind.Sequential)] public struct JOYCAPS {
        public ushort wMid, wPid;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szPname;
        public uint wXmin, wXmax, wYmin, wYmax, wZmin, wZmax;
        public uint wNumButtons, wPeriodMin, wPeriodMax;
        public uint wRmin, wRmax, wUmin, wUmax, wVmin, wVmax;
        public uint wCaps, wMaxAxes, wNumAxes, wMaxButtons;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szRegKey;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szOEMVxD;
    }
    [StructLayout(LayoutKind.Sequential)] public struct JOYINFOEX {
        public uint dwSize, dwFlags, dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos;
        public uint dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2;
    }
    [DllImport("winmm.dll")] public static extern uint joyGetDevCaps(uint id, ref JOYCAPS c, uint size);
    [DllImport("winmm.dll")] public static extern uint joyGetPosEx(uint id, ref JOYINFOEX i);
'@ -ErrorAction Stop
    } catch { }
    for ($id = 0; $id -lt 16; $id++) {
        $c = New-Object BOB2W.Joy+JOYCAPS
        if ([BOB2W.Joy]::joyGetDevCaps($id, [ref]$c, [Runtime.InteropServices.Marshal]::SizeOf($c)) -ne 0) { continue }
        $i = New-Object BOB2W.Joy+JOYINFOEX
        $i.dwSize = [Runtime.InteropServices.Marshal]::SizeOf($i); $i.dwFlags = 0xFF
        if ([BOB2W.Joy]::joyGetPosEx($id, [ref]$i) -ne 0) { continue }
        return [pscustomobject]@{ Id = $id; Name = $c.szPname; Axes = $c.wNumAxes; Buttons = $c.wNumButtons }
    }
    return $null
}

function Get-JoyPos {
    param([int]$Id)
    $i = New-Object BOB2W.Joy+JOYINFOEX
    $i.dwSize = [Runtime.InteropServices.Marshal]::SizeOf($i); $i.dwFlags = 0xFF
    if ([BOB2W.Joy]::joyGetPosEx($Id, [ref]$i) -ne 0) { return $null }
    $pc = { param($v) [int](($v / 65535.0) * 200 - 100) }
    [pscustomobject]@{
        X = (& $pc $i.dwXpos); Y = (& $pc $i.dwYpos)
        R = (& $pc $i.dwRpos); Z = (& $pc $i.dwZpos)
        Buttons = $i.dwButtons
    }
}

function Get-BdgValue {
    param([string]$Dir, [string]$Key)
    $f = Join-Path $Dir 'bdg.txt'
    if (-not (Test-Path $f)) { return $null }
    foreach ($line in [IO.File]::ReadAllLines($f, [Text.Encoding]::GetEncoding(1252))) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*([^#]*)") { return $matches[1].Trim() }
    }
    return $null
}



# ---------------------------------------------------------------------
#  BACK TO THE MAIN SCREEN
#
#  Get-Process ... MainWindowTitle is not reliable here: the launcher runs
#  inside powershell.exe with its console hidden, and the console can be
#  reported as the process's main window, so the WPF window is never found.
#  Enumerate top-level windows and match on the title instead.
#
#  Raising it matters as much as finding it. The launcher is usually still
#  open BEHIND this window - closing without bringing it forward just
#  reveals the desktop, which does not feel like going back at all.
# ---------------------------------------------------------------------
Add-Type -Namespace BOB2N -Name Nav -MemberDefinition @'
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    public delegate bool EnumProc(IntPtr h, IntPtr p);
'@ -ErrorAction SilentlyContinue

function Find-LauncherWindow {
    $found = [IntPtr]::Zero
    $cb = [BOB2N.Nav+EnumProc]{
        param($h, $p)
        if ([BOB2N.Nav]::IsWindowVisible($h)) {
            $sb = New-Object Text.StringBuilder 256
            [void][BOB2N.Nav]::GetWindowText($h, $sb, $sb.Capacity)
            if ($sb.ToString() -eq 'Battle of Britain II') { $script:FoundHwnd = $h; return $false }
        }
        return $true
    }
    $script:FoundHwnd = [IntPtr]::Zero
    [void][BOB2N.Nav]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:FoundHwnd
}

function Return-ToLauncher {
    $h = Find-LauncherWindow
    if ($h -ne [IntPtr]::Zero) {
        [void][BOB2N.Nav]::ShowWindow($h, 9)      # SW_RESTORE
        [void][BOB2N.Nav]::SetForegroundWindow($h)
        return
    }
    $bat = Join-Path $ScriptDir 'BOB2.bat'
    if (Test-Path $bat) { Start-Process -FilePath $bat -WorkingDirectory (Split-Path -Parent $bat) }
}

function Get-Prerequisites {
    # What the user has to bring. The mod ships no game content and no
    # patches - BOB2_Setup.ps1 looks for the patch installers in the fix
    # folder, the game folder, or BOB2-Win11-Fix\ under it. If the game is
    # already at 2.13 none of them are needed, which is the common case for
    # anyone who has been playing.
    $dir = $script:State.GameDir
    $ver = if ($dir) { Get-GameVersion $dir } else { '?' }
    $need = @()
    if ($dir -and $ver -ne '2.13') {
        foreach ($f in @(
            @{ Pattern = 'bob2_update_v2.12*'; What = 'Patch 2.12' }
            @{ Pattern = 'multiskin_v212*';    What = 'MultiSkin pack' }
            @{ Pattern = 'BDG*v2.13*';         What = 'Patch 2.13' })) {
            $found = $false
            foreach ($p in @($ScriptDir, $dir, (Join-Path $dir 'BOB2-Win11-Fix'))) {
                if ($p -and (Get-ChildItem -Path $p -Filter $f.Pattern -ErrorAction SilentlyContinue)) { $found = $true; break }
            }
            $need += [pscustomobject]@{ What = $f.What; Have = $found }
        }
    }
    [pscustomobject]@{
        GameFound   = [bool]$dir
        GameVersion = $ver
        UpToDate    = ($ver -eq '2.13')
        Files       = $need
    }
}

function Open-Url {
    param([string]$Url)
    try { Start-Process $Url } catch { }
}

$GameDir = Find-GameDir -Start $ScriptDir
if (-not $GameDir) { $GameDir = '' }

$script:State = [ordered]@{
    GameDir = $GameDir
    Wrapper = 'dgvoodoo'
    Scale   = 125
    Joy     = $null
    Perf    = $true
    Done    = @()
}

# Screen width decides the recommended menu scale - there is no point
# recommending 140% to someone on a 1366-wide laptop, it clips.
$ScreenW = [int][System.Windows.SystemParameters]::PrimaryScreenWidth
$script:State.Scale = if ($ScreenW -ge 1920) { 140 } elseif ($ScreenW -ge 1600) { 125 } elseif ($ScreenW -ge 1366) { 110 } else { 102 }

# =====================================================================
#  UI
# =====================================================================
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="First Flight - Battle of Britain II"
        Width="900" Height="680" MinWidth="820" MinHeight="620"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        Background="#12161C" Foreground="#E4DFD4"
        UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Ideal"
        TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI Variable Text, Segoe UI, Tahoma">
  <Window.Resources>
    <SolidColorBrush x:Key="Card"      Color="#171C24"/>
    <SolidColorBrush x:Key="CardHi"    Color="#1E242E"/>
    <SolidColorBrush x:Key="Rule"      Color="#232A34"/>
    <SolidColorBrush x:Key="Edge"      Color="#626A77"/>
    <SolidColorBrush x:Key="Text"      Color="#E4DFD4"/>
    <SolidColorBrush x:Key="Secondary" Color="#AEB6C2"/>
    <SolidColorBrush x:Key="Tertiary"  Color="#949DAC"/>
    <SolidColorBrush x:Key="Brass"     Color="#C8973F"/>
    <SolidColorBrush x:Key="BrassWash" Color="#2A2114"/>
    <SolidColorBrush x:Key="Good"      Color="#8FB56A"/>
    <SolidColorBrush x:Key="Warn"      Color="#D9A441"/>
    <SolidColorBrush x:Key="Danger"    Color="#E2685A"/>

    <Style x:Key="Display" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock" BasedOn="{StaticResource Display}">
      <Setter Property="FontSize" Value="26"/><Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="LineHeight" Value="31"/>
    </Style>
    <Style x:Key="Body" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/><Setter Property="Foreground" Value="{StaticResource Secondary}"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="LineHeight" Value="23"/>
      <Setter Property="MaxWidth" Value="640"/><Setter Property="Margin" Value="0,0,0,14"/>
      <Setter Property="HorizontalAlignment" Value="Left"/>
    </Style>
    <Style x:Key="Eyebrow" TargetType="TextBlock" BasedOn="{StaticResource Display}">
      <Setter Property="FontSize" Value="12"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Tertiary}"/>
    </Style>
    <Style x:Key="Note" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13.5"/><Setter Property="Foreground" Value="{StaticResource Tertiary}"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="MaxWidth" Value="640"/>
      <Setter Property="HorizontalAlignment" Value="Left"/>
    </Style>
    <Style x:Key="Mono" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Cascadia Mono, Consolas"/>
      <Setter Property="FontSize" Value="13"/><Setter Property="Foreground" Value="{StaticResource Secondary}"/>
    </Style>

    <Style TargetType="Button">
      <Setter Property="FontFamily" Value="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
      <Setter Property="FontSize" Value="15"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Padding" Value="16,7"/><Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="MinWidth" Value="104"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="#23262C" BorderBrush="{StaticResource Edge}"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#2C313A"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{StaticResource Brass}" BorderBrush="{StaticResource Brass}"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#DCA84B"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Setter Property="Foreground" Value="#171203"/>
    </Style>

    <!-- A choice: big hit area, the whole card is the control -->
    <Style x:Key="Choice" TargetType="RadioButton">
      <Setter Property="Margin" Value="0,0,0,10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="B" Background="{StaticResource Card}" BorderBrush="{StaticResource Rule}"
                    BorderThickness="1" CornerRadius="5" Padding="14,11" MaxWidth="640"
                    HorizontalAlignment="Left">
              <StackPanel Orientation="Horizontal">
                <Ellipse x:Name="Dot" Width="15" Height="15" Margin="0,2,12,0"
                         Stroke="{StaticResource Edge}" StrokeThickness="1.5" VerticalAlignment="Top"/>
                <ContentPresenter VerticalAlignment="Center"/>
              </StackPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Brass}"/>
                <Setter TargetName="B" Property="Background" Value="{StaticResource BrassWash}"/>
                <Setter TargetName="Dot" Property="Fill" Value="{StaticResource Brass}"/>
                <Setter TargetName="Dot" Property="Stroke" Value="{StaticResource Brass}"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Edge}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. Default WPF chrome shows the powershell.exe icon
         and a Windows title bar, which looks nothing like the rest of the
         app and announces that you are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="FIRST FLIGHT" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Border x:Name="ChromeMin" Width="40" Height="34" Background="Transparent" Cursor="Hand">
          <TextBlock Text="&#x2013;" Foreground="#AEB6C2" FontSize="14"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent" Cursor="Hand">
          <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </StackPanel>
    </Grid>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- header -->
    <Grid Grid.Row="0" Margin="36,26,36,0">
      <StackPanel>
        <TextBlock x:Name="Eyebrow" Style="{StaticResource Eyebrow}" Text="FIRST FLIGHT"/>
        <StackPanel x:Name="Dots" Orientation="Horizontal" Margin="0,8,0,0"/>
      </StackPanel>
      <TextBlock x:Name="StepNo" Style="{StaticResource Eyebrow}" HorizontalAlignment="Right"
                 VerticalAlignment="Top" Text=""/>
    </Grid>
    <Rectangle Grid.Row="0" Height="1" Fill="#232A34" VerticalAlignment="Bottom" Margin="36,0,36,0"/>

    <!-- body -->
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="36,22,36,0">
      <StackPanel x:Name="Body"/>
    </ScrollViewer>

    <!-- footer -->
    <Grid Grid.Row="2" Margin="36,16,36,24">
      <TextBlock x:Name="FootNote" Style="{StaticResource Note}" VerticalAlignment="Center"
                 MaxWidth="440" HorizontalAlignment="Left"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnBack" Content="Back"/>
        <Button x:Name="BtnAlt"  Content=""/>
        <Button x:Name="BtnNext" Content="Next" Style="{StaticResource Primary}"/>
      </StackPanel>
    </Grid>
  </Grid>
  </DockPanel>
  </Border>
</Window>

'@

$Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$Xaml)))
function C { param($n) $Win.FindName($n) }
# Custom title bar: dragging a WindowStyle="None" window is manual, and the
# buttons are Borders so they cannot inherit a dialog's Button style.
$bar = $Win.FindName('ChromeBar')
if ($bar) { $bar.Add_MouseLeftButtonDown({ $Win.DragMove() }) }
$cx = $Win.FindName('ChromeClose')
if ($cx) {
    $cx.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled = $true; $Win.Close() })
    $cx.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#C8102E') })
    $cx.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
}
$cm = $Win.FindName('ChromeMin')
if ($cm) {
    $cm.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled = $true; $Win.WindowState = 'Minimized' })
    $cm.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#2C313A') })
    $cm.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
}

function Res { param($k) $Win.FindResource($k) }

# ---- small builders so each step reads as content, not plumbing --------
function TB { param([string]$Text, [string]$Style = 'Body')
    $t = New-Object Windows.Controls.TextBlock
    $t.Style = Res $Style; $t.Text = $Text; return $t }

function Choice {
    param([string]$Title, [string]$Desc, [string]$Tag, [bool]$Checked, [string]$Badge)
    $r = New-Object Windows.Controls.RadioButton
    $r.Style = Res 'Choice'; $r.GroupName = 'g'; $r.Tag = $Tag; $r.IsChecked = $Checked
    $sp = New-Object Windows.Controls.StackPanel
    $head = New-Object Windows.Controls.StackPanel; $head.Orientation = 'Horizontal'
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Title; $t.FontSize = 15; $t.FontWeight = 'SemiBold'; $t.Foreground = Res 'Text'
    [void]$head.Children.Add($t)
    if ($Badge) {
        $b = New-Object Windows.Controls.TextBlock
        $b.Text = $Badge; $b.FontSize = 12; $b.FontWeight = 'SemiBold'
        $b.Foreground = Res 'Brass'; $b.Margin = '10,2,0,0'
        [void]$head.Children.Add($b)
    }
    [void]$sp.Children.Add($head)
    if ($Desc) {
        $d = New-Object Windows.Controls.TextBlock
        $d.Text = $Desc; $d.FontSize = 13.5; $d.Foreground = Res 'Secondary'
        $d.TextWrapping = 'Wrap'; $d.MaxWidth = 560; $d.Margin = '0,3,0,0'; $d.LineHeight = 19
        [void]$sp.Children.Add($d)
    }
    $r.Content = $sp
    return $r
}

function Line { param([string]$Text, [string]$Colour = 'Good', [string]$Mark = $([char]0x2713))
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $sp.Margin = '0,0,0,7'
    $m = New-Object Windows.Controls.TextBlock
    $m.Text = $Mark; $m.Foreground = Res $Colour; $m.FontSize = 15; $m.Margin = '0,0,10,0'
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = 14.5; $t.Foreground = Res 'Secondary'
    $t.TextWrapping = 'Wrap'; $t.MaxWidth = 600
    [void]$sp.Children.Add($m); [void]$sp.Children.Add($t)
    return $sp }

$script:Step = 0
$script:Total = 6

function Set-Dots {
    (C 'Dots').Children.Clear()
    if ($script:Step -lt 1 -or $script:Step -gt $script:Total) { return }
    for ($i = 1; $i -le $script:Total; $i++) {
        $e = New-Object Windows.Shapes.Ellipse
        $e.Width = 8; $e.Height = 8; $e.Margin = '0,0,7,0'
        $e.Fill = if ($i -le $script:Step) { Res 'Brass' } else { Res 'Rule' }
        [void](C 'Dots').Children.Add($e)
    }
}

function Get-Checked {
    foreach ($c in (C 'Body').Children) {
        if ($c -is [Windows.Controls.RadioButton] -and $c.IsChecked) { return $c.Tag }
    }
    return $null
}

# Navigate. Show-Step RETURNS the button handlers for the step it drew, so
# every transition has to go through here - calling Show-Step directly draws
# the new step but leaves the buttons wired to the old one, which froze the
# wizard on step 1.
function Go {
    param([int]$N)
    # Show-Step must yield exactly ONE hashtable. If any statement inside a
    # step leaks a value to the pipeline, PowerShell returns an ARRAY - and
    # $Handlers.Next then comes back $null, so every button silently does
    # nothing. Take the last hashtable and ignore anything else that leaked.
    $r = Show-Step $N
    $script:Handlers = @($r) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
    if (-not $script:Handlers -and -not $RenderTo) {
        [void][Windows.MessageBox]::Show(
            "Step $N did not return its buttons. This is a bug - please report it.",
            'First Flight', 'OK', 'Warning')
    }
}

# =====================================================================
#  STEPS
#  Each returns a hashtable: Next = what the primary button does,
#  Alt = optional secondary. Nothing writes until a button is pressed.
# =====================================================================
function Show-Step {
    param([int]$N)
    $script:Step = $N
    $b = C 'Body'; $b.Children.Clear()
    (C 'StepNo').Text = if ($N -ge 1 -and $N -le $script:Total) { "Step $N of $script:Total" } else { '' }
    (C 'BtnBack').Visibility = if ($N -gt 0 -and $N -le $script:Total) { 'Visible' } else { 'Collapsed' }
    (C 'BtnAlt').Visibility = 'Collapsed'
    (C 'FootNote').Text = ''
    (C 'BtnNext').Content = 'Next'
    (C 'BtnNext').IsEnabled = $true
    Set-Dots
    Stop-JoyTimer

    switch ($N) {

    0 {
        (C 'Eyebrow').Text = 'FIRST FLIGHT'
        $rerun = $script:State.Done.Count -gt 0
        [void]$b.Children.Add((TB $(if ($rerun) { 'Setup' } else { 'First flight' }) 'H1'))
        if ($rerun) {
            [void]$b.Children.Add((TB 'Run through all six steps again to change any of your answers. Everything you set last time is shown as you go.'))
        } else {
            [void]$b.Children.Add((TB 'This will get Battle of Britain II running properly on this PC. Six questions, about three minutes.'))
            [void]$b.Children.Add((TB 'I will make a backup of every file before I change it, and nothing here is permanent - you can run this again at any time to change your answers.'))

            [void]$b.Children.Add((TB 'WHAT YOU NEED' 'Eyebrow'))
            $pre = Get-Prerequisites

            if ($pre.GameFound) {
                [void]$b.Children.Add((Line "Battle of Britain II, installed. Found version $($pre.GameVersion)."))
            } else {
                [void]$b.Children.Add((Line 'A licensed copy of Battle of Britain II: Wings of Victory. I cannot find one on this PC.' 'Warn' '-'))
                $buy = New-Object Windows.Controls.Button
                $buy.Content = 'Where to buy it'
                $buy.HorizontalAlignment = 'Left'; $buy.Margin = '0,4,0,12'
                $buy.Add_Click({ Open-Url 'https://a2asimulations.com/store/' })
                [void]$b.Children.Add($buy)
            }

            if ($pre.UpToDate) {
                [void]$b.Children.Add((Line 'Patch 2.13 is already applied. You do not need any patch files.'))
            } elseif ($pre.GameFound) {
                [void]$b.Children.Add((TB ("The game is at $($pre.GameVersion). Getting to 2.13 needs the community patch " +
                    "installers. This mod does not include them - it applies the ones you supply. Put them in this folder " +
                    "and they will be found automatically.") 'Note'))
                foreach ($f in $pre.Files) {
                    if ($f.Have) { [void]$b.Children.Add((Line "$($f.What) - found")) }
                    else         { [void]$b.Children.Add((Line "$($f.What) - not here yet" 'Warn' '-')) }
                }
                # Patch 2.13 is hosted by A2A themselves, and the file they
                # serve is named BDG v2.13.7z - which is exactly what
                # BOB2_Setup.ps1 already looks for. Downloading it into this
                # folder is all that is needed.
                if ($pre.Files | Where-Object { $_.What -eq 'Patch 2.13' -and -not $_.Have }) {
                    $dl = New-Object Windows.Controls.Button
                    $dl.Content = 'Download patch 2.13 from A2A'
                    $dl.HorizontalAlignment = 'Left'; $dl.Margin = '0,10,0,0'
                    $dl.Add_Click({ Open-Url 'https://www.a2asimulations.com/bob/downloads/BDG%20v2.13.7z' })
                    [void]$b.Children.Add($dl)
                    [void]$b.Children.Add((TB "Save it into this folder - $ScriptDir - and it will be found automatically." 'Note'))
                }
            }
        }
        (C 'BtnNext').Content = 'Start'
        (C 'BtnAlt').Content = 'Not now'; (C 'BtnAlt').Visibility = 'Visible'
        return @{ Next = { Go 1 }; Alt = { $Win.Close() } }
    }

    1 {
        (C 'Eyebrow').Text = 'FIND THE GAME'
        [void]$b.Children.Add((TB 'Where is Battle of Britain II installed?' 'H1'))
        if ($script:State.GameDir) {
            [void]$b.Children.Add((TB 'Found it.'))
            $p = TB $script:State.GameDir 'Mono'; $p.Margin = '0,0,0,10'
            [void]$b.Children.Add($p)
            $v = Get-GameVersion $script:State.GameDir
            [void]$b.Children.Add((Line "Version $v. This looks right."))
            (C 'BtnNext').Content = 'Use this folder'
            (C 'BtnAlt').Content = 'Choose another'; (C 'BtnAlt').Visibility = 'Visible'
        } else {
            [void]$b.Children.Add((TB 'I could not find Battle of Britain II on this PC. Point me at the folder that contains Bob.exe and I will take it from there.'))
            (C 'BtnNext').Content = 'Browse'
            (C 'BtnNext').IsEnabled = $true
        }
        return @{
            Next = {
                if (-not $script:State.GameDir) { Browse-Game } else { Go 2 }
            }
            Alt = { Browse-Game }
        }
    }

    2 {
        (C 'Eyebrow').Text = 'INSTALL THE FIX'
        [void]$b.Children.Add((TB 'Get the game running on Windows 11' 'H1'))
        $os = Get-WindowsRelease
        if (-not $os.Supported) {
            [void]$b.Children.Add((Line "$($os.Full)" 'Danger' '!'))
            [void]$b.Children.Add((TB $os.Why))
            [void]$b.Children.Add((TB 'Nothing will be changed. You can carry on through the rest of the questions, but do not install the fix on this PC.' 'Note'))
            (C 'BtnNext').Content = 'Carry on anyway'
            (C 'BtnAlt').Content = 'Stop here'; (C 'BtnAlt').Visibility = 'Visible'
            return @{ Next = { Go 3 }; Alt = { $Win.Close() } }
        }
        [void]$b.Children.Add((Line "$($os.Full) - supported."))
        [void]$b.Children.Add((TB 'Battle of Britain II was written for Windows XP. A few things have to change before it runs properly on a modern PC. Every file I touch is backed up first.'))
        # Parse the FixVersion line, not line 1 - line 1 is the PRODUCT NAME,
        # which is why this used to read "version BOB2 Windows 10/11 Fix".
        # Same parse the launcher's Get-InstalledFixVersion uses.
        $fix = Join-Path $script:State.GameDir 'BOB2-Win11-Fix.version'
        $have = Test-Path $fix
        $ver = ''
        if ($have) {
            $m = Select-String -Path $fix -Pattern '^FixVersion\s*=\s*(.+)$' -ErrorAction SilentlyContinue
            if ($m) { $ver = $m.Matches[0].Groups[1].Value.Trim() }
        }
        if ($have) {
            [void]$b.Children.Add((Line $("The fix is already installed" + $(if ($ver) { " - version $ver" } else { "" }) + ". Nothing to do here.")))
            (C 'BtnNext').Content = 'Next'
            (C 'BtnAlt').Content = 'Open install and repair'; (C 'BtnAlt').Visibility = 'Visible'
        } else {
            [void]$b.Children.Add((Line 'Startup crash fix - stops the crash on the way into a mission.' 'Warn' '-'))
            [void]$b.Children.Add((Line 'Windows 11 compatibility flags - stops two behaviours this game predates.' 'Warn' '-'))
            [void]$b.Children.Add((Line 'Graphics translator - so the game can talk to a modern card.' 'Warn' '-'))
            (C 'BtnNext').Content = 'Open install and repair'
            (C 'BtnAlt').Content = 'Skip'; (C 'BtnAlt').Visibility = 'Visible'
            (C 'FootNote').Text = 'Install and repair opens in its own window. Come back here when it finishes.'
        }
        return @{
            Next = {
                if ($have) { Go 3 } else { Run-Setup }
            }
            Alt = { if ($have) { Run-Setup } else { Go 3 } }
        }
    }

    3 {
        (C 'Eyebrow').Text = 'GRAPHICS'
        [void]$b.Children.Add((TB 'How should the game talk to your graphics card?' 'H1'))
        [void]$b.Children.Add((TB 'This game asks for a graphics feature that Windows removed years ago. A small translator sits in between and answers for it. Without one, the game will not start at all.'))
        $cur = $script:State.Wrapper
        [void]$b.Children.Add((Choice 'dgVoodoo2' 'Works on every graphics card we have tested. Use this one.' 'dgvoodoo' ($cur -eq 'dgvoodoo') 'Recommended'))
        [void]$b.Children.Add((Choice "Windows' own Direct3D" 'No translator at all. In theory the fastest, but this game fails to start on most modern cards without one.' 'native' ($cur -eq 'native') ''))
        [void]$b.Children.Add((Choice 'DXVK' 'Known to crash this game the moment you enter the cockpit. Here for completeness.' 'dxvk' ($cur -eq 'dxvk') ''))
        [void]$b.Children.Add((TB ("Currently: " + (Get-WrapperName $script:State.GameDir)) 'Note'))
        (C 'FootNote').Text = 'You can change this later from GRAPHICS TRANSLATOR.'
        return @{ Next = { Apply-Wrapper } }
    }

    4 {
        (C 'Eyebrow').Text = 'MENU SIZE'
        [void]$b.Children.Add((TB "How big should the game's own menus be?" 'H1'))
        [void]$b.Children.Add((TB "The briefing and options screens inside the game were drawn for a monitor 1024 pixels wide. Yours is $ScreenW pixels wide, so they come out very small. I can enlarge them."))
        $rec = $script:State.Scale
        foreach ($o in @(
            @{ V=102; T='102%'; D='Barely changed. For monitors 1280 wide or less.' },
            @{ V=110; T='110%'; D='A small increase. For 1366 wide and up.' },
            @{ V=125; T='125%'; D='Comfortable. For 1600 wide and up.' },
            @{ V=140; T='140%'; D='Largest. For 1920 wide and up. Needs 1608 pixels across - anything narrower will clip.' })) {
            $badge = if ($o.V -eq $rec) { 'Recommended for your monitor' } else { '' }
            [void]$b.Children.Add((Choice $o.T $o.D ([string]$o.V) ($o.V -eq $rec) $badge))
        }
        $now = Get-MenuScalePct $script:State.GameDir
        [void]$b.Children.Add((TB ("Currently: " + $(if ($now -and $now -ne 100) { "$now%" } else { 'original size' })) 'Note'))
        (C 'FootNote').Text = 'This changes the game menus only, not what you see while flying.'
        return @{ Next = { Apply-Scale } }
    }

    5 {
        (C 'Eyebrow').Text = 'JOYSTICK'
        [void]$b.Children.Add((TB "Let's check your joystick" 'H1'))
        $j = Get-Joystick
        $script:State.Joy = $j
        if ($j) {
            [void]$b.Children.Add((Line "Found: $($j.Name) - $($j.Axes) axes, $($j.Buttons) buttons."))
            [void]$b.Children.Add((TB 'Move the stick around and press a couple of buttons, so you can see Windows is reading it.'))
            $grid = New-Object Windows.Controls.StackPanel
            $grid.Name = 'JoyBars'
            foreach ($ax in @('Pitch','Roll','Rudder','Throttle')) {
                $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'
                $row.Margin = '0,0,0,8'
                $lab = New-Object Windows.Controls.TextBlock
                $lab.Text = $ax; $lab.Width = 82; $lab.FontSize = 14; $lab.Foreground = Res 'Secondary'
                $bar = New-Object Windows.Controls.ProgressBar
                $bar.Name = "Bar$ax"; $bar.Width = 300; $bar.Height = 14
                $bar.Minimum = -100; $bar.Maximum = 100; $bar.Value = 0
                $bar.Foreground = Res 'Brass'; $bar.Background = Res 'Card'
                $bar.BorderBrush = Res 'Rule'
                $val = New-Object Windows.Controls.TextBlock
                $val.Name = "Val$ax"; $val.Width = 60; $val.Margin = '12,0,0,0'
                $val.FontFamily = 'Cascadia Mono, Consolas'; $val.FontSize = 13
                $val.Foreground = Res 'Tertiary'; $val.Text = '0%'
                [void]$row.Children.Add($lab); [void]$row.Children.Add($bar); [void]$row.Children.Add($val)
                [void]$grid.Children.Add($row)
            }
            $btns = New-Object Windows.Controls.TextBlock
            $btns.Name = 'JoyButtons'; $btns.FontFamily = 'Cascadia Mono, Consolas'
            $btns.FontSize = 14; $btns.Foreground = Res 'Tertiary'; $btns.Margin = '0,6,0,0'
            $btns.Text = 'Buttons  ' + ('.' * [Math]::Min(16, [int]$j.Buttons))
            [void]$grid.Children.Add($btns)
            [void]$b.Children.Add($grid)
            $script:JoyUi = $grid
            Start-JoyTimer
            (C 'BtnNext').Content = 'Looks right'
        } else {
            [void]$b.Children.Add((Line 'I cannot see a joystick attached to this PC.' 'Warn' '!'))
            [void]$b.Children.Add((TB 'You can fly with the keyboard and mouse - the game supports it and the bindings are already set up. If you have a stick, plug it in and press Look again, or run this later.'))
            (C 'BtnNext').Content = 'Carry on without one'
            (C 'BtnAlt').Content = 'Look again'; (C 'BtnAlt').Visibility = 'Visible'
        }
        return @{ Next = { Go 6 }; Alt = { Go 5 } }
    }

    6 {
        (C 'Eyebrow').Text = 'FRAME RATE'
        [void]$b.Children.Add((TB 'A sensible starting point for frame rate' 'H1'))
        [void]$b.Children.Add((TB 'A few settings in this game cost more than everything else in it put together. Setting them sensibly roughly triples the frame rate on most PCs, and costs detail you would have to go looking for to notice.'))
        # Key names verified against the real bdg.txt, not guessed:
        # LANDSCAPE_TEXTURE_SIZE, not TERRAIN_*; SMOOTHEN_FRAMERATE_MODE and
        # ENABLE_AUTO_GEN are written without spaces around '='.
        $rows = $script:PerfRows
        foreach ($r in $rows) {
            $now = Get-BdgValue $script:State.GameDir $r.K
            $txt = "$($r.L) - now $(if ($now) { $now } else { 'unset' }), proposed $($r.P)"
            [void]$b.Children.Add((Line $txt 'Brass' '-'))
        }
        [void]$b.Children.Add((TB 'Every one of these is reversible from SETTINGS, and bdg.txt is backed up before I touch it.' 'Note'))
        (C 'BtnNext').Content = 'Apply these'
        (C 'BtnAlt').Content = 'Leave my settings alone'; (C 'BtnAlt').Visibility = 'Visible'
        return @{ Next = { Apply-Perf $true }; Alt = { Apply-Perf $false } }
    }

    7 {
        (C 'Eyebrow').Text = 'FORM 700 - SERVICING RECORD'
        (C 'StepNo').Text = ''
        [void]$b.Children.Add((TB "You're ready to fly." 'H1'))
        foreach ($d in $script:State.Done) { [void]$b.Children.Add((Line $d)) }
        [void]$b.Children.Add((TB 'Once you have flown, use FRAME RATE TEST on the main screen to see what you are actually getting.' 'Note'))
        (C 'BtnNext').Content = 'Finish'
        (C 'FootNote').Text = 'Run SETUP WIZARD again at any time to change any of this.'
        # Reaching this screen is what unlocks PLAY on the launcher.
        try {
            Set-Content -Path (Join-Path $script:State.GameDir 'BOB2-Win11-Fix.wizard-done') `
                        -Value (Get-Date -Format 's') -Encoding ASCII
        } catch { }
        return @{ Next = { Return-ToLauncher; $Win.Close() } }
    }

    }
}

# =====================================================================
#  ACTIONS - everything that writes
# =====================================================================

# The four settings that dominate frame rate, with the real bdg.txt key
# names. Profiling showed this game is CPU-bound on rendering, so these are
# the ones worth touching; everything else is noise by comparison.
$script:PerfRows = @(
    @{ K='OBJECT_DENSITY';          L='Ground object density'; P='2' }
    @{ K='LANDSCAPE_TEXTURE_SIZE';  L='Terrain texture size';  P='1024' }
    @{ K='SMOOTHEN_FRAMERATE_MODE'; L='Frame smoothing';       P='NONE' }
    @{ K='ENABLE_AUTO_GEN';         L='Auto-generated scenery'; P='OFF' }
)

function Set-BdgValues {
    param([string]$Dir, [hashtable]$Values)
    # Only the VALUE on a matched line is replaced. Indentation, the spacing
    # around '=', trailing spaces, inline comments, line order and the
    # Windows-1252 / CRLF encoding all survive - the same rule the
    # configurator observes, because the game re-reads this file verbatim.
    $f = Join-Path $Dir 'bdg.txt'
    if (-not (Test-Path $f)) { return 0 }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $bak = Join-Path $Dir "_WizardBackup\$stamp"
    New-Item -ItemType Directory -Path $bak -Force | Out-Null
    Copy-Item $f (Join-Path $bak 'bdg.txt') -Force

    $enc = [Text.Encoding]::GetEncoding(1252)
    $lines = [IO.File]::ReadAllLines($f, $enc)
    $n = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($k in $Values.Keys) {
            $rx = "^(\s*$([regex]::Escape($k))\s*=\s*)([^#\r\n]*?)(\s*)(#.*)?$"
            $m = [regex]::Match($lines[$i], $rx)
            if ($m.Success) {
                $lines[$i] = $m.Groups[1].Value + $Values[$k] + $m.Groups[3].Value + $m.Groups[4].Value
                $n++
                break
            }
        }
    }
    [IO.File]::WriteAllLines($f, $lines, $enc)
    return $n
}

function Browse-Game {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = 'Select the folder that contains Bob.exe'
    if ($d.ShowDialog() -ne 'OK') { return }
    if (-not (Test-Path (Join-Path $d.SelectedPath 'Bob.exe'))) {
        [void][Windows.MessageBox]::Show(
            "That folder does not contain Bob.exe.`n`nThe game is usually somewhere like C:\Program Files (x86)\Battle of Britain II, or wherever you installed it from GOG.",
            'Not the game folder', 'OK', 'Warning')
        return
    }
    $script:State.GameDir = $d.SelectedPath
    Go 1
}

function Run-Setup {
    # The GUI. This used to launch BOB2_Setup.bat, which dropped a first-time
    # user into a black console menu in the middle of the wizard.
    # Launched directly rather than through the .vbs so -From can be passed;
    # BOB2_Install.ps1 hides its own console, so no window appears either way.
    $ps1 = Join-Path $ScriptDir 'BOB2_Install.ps1'
    if (Test-Path $ps1) {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden `
            -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$ps1`"",'-From','wizard' `
            -WorkingDirectory $script:State.GameDir
        (C 'FootNote').Text = 'Install and repair is open in its own window. Press Next when it has finished.'
        (C 'BtnNext').Content = 'Next'
    } else {
        [void][Windows.MessageBox]::Show('BOB2_Install.ps1 is missing from the fix folder.', 'Not found', 'OK', 'Warning')
    }
}

function Apply-Wrapper {
    $choice = Get-Checked
    if (-not $choice) { $choice = 'dgvoodoo' }
    if ($choice -eq 'dxvk') {
        $r = [Windows.MessageBox]::Show(
            "DXVK crashes this game when you enter 3D.`n`nIf it does, come back here and choose dgVoodoo2.",
            'Are you sure?', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
    }
    $script:State.Wrapper = $choice
    $bat = Join-Path $ScriptDir 'BOB2_SetWrapper.bat'
    if (Test-Path $bat) {
        $p = Start-Process -FilePath $bat -ArgumentList $choice -WorkingDirectory $script:State.GameDir `
                           -WindowStyle Hidden -Wait -PassThru
    }
    $script:State.Done += "Graphics translator - " + (Get-WrapperName $script:State.GameDir)
    Go 4
}

function Apply-Scale {
    $choice = Get-Checked
    if (-not $choice) { $choice = [string]$script:State.Scale }
    $script:State.Scale = [int]$choice
    $ps1 = Join-Path $ScriptDir 'BOB2_MenuScale.ps1'
    if (Test-Path $ps1) {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -Wait `
            -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$ps1`"",'-Scale',$choice `
            -WorkingDirectory $script:State.GameDir
    }
    $now = Get-MenuScalePct $script:State.GameDir
    $script:State.Done += "In-game menus - $(if ($now -and $now -ne 100) { "$now%" } else { 'original size' })"
    Go 5
}

function Apply-Perf {
    param([bool]$Apply)
    if ($Apply) {
        $vals = @{}
        foreach ($r in $script:PerfRows) { $vals[$r.K] = $r.P }
        $n = Set-BdgValues $script:State.GameDir $vals
        $script:State.Done += "Frame rate settings - $n changed, bdg.txt backed up"
    } else {
        $script:State.Done += 'Frame rate settings - left as they were'
    }
    Go 7
}

# ---- live joystick readout -------------------------------------------
$script:JoyTimer = $null
function Start-JoyTimer {
    Stop-JoyTimer
    if (-not $script:State.Joy) { return }
    $script:JoyTimer = New-Object Windows.Threading.DispatcherTimer
    $script:JoyTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $script:JoyTimer.Add_Tick({
        $p = Get-JoyPos $script:State.Joy.Id
        if (-not $p -or -not $script:JoyUi) { return }
        $map = @{ Pitch = $p.Y; Roll = $p.X; Rudder = $p.R; Throttle = $p.Z }
        foreach ($row in $script:JoyUi.Children) {
            if ($row -isnot [Windows.Controls.StackPanel]) { continue }
            $lab = $row.Children[0]
            if ($lab -isnot [Windows.Controls.TextBlock]) { continue }
            $k = $lab.Text
            if (-not $map.ContainsKey($k)) { continue }
            $row.Children[1].Value = [Math]::Max(-100, [Math]::Min(100, $map[$k]))
            $row.Children[2].Text  = ('{0,4}%' -f $map[$k])
        }
        $bt = $script:JoyUi.Children | Where-Object { $_ -is [Windows.Controls.TextBlock] } | Select-Object -First 1
        if ($bt) {
            $n = [Math]::Min(16, [int]$script:State.Joy.Buttons)
            $sb = New-Object Text.StringBuilder
            [void]$sb.Append('Buttons  ')
            for ($i = 0; $i -lt $n; $i++) {
                [void]$sb.Append($(if ($p.Buttons -band (1 -shl $i)) { '#' } else { '.' }))
            }
            $bt.Text = $sb.ToString()
        }
    })
    $script:JoyTimer.Start()
}
function Stop-JoyTimer {
    if ($script:JoyTimer) { $script:JoyTimer.Stop(); $script:JoyTimer = $null }
}

# =====================================================================
#  NAVIGATION
# =====================================================================
$script:Handlers = @{}

(C 'BtnNext').Add_Click({ if ($script:Handlers.Next) { & $script:Handlers.Next } })
(C 'BtnAlt').Add_Click({  if ($script:Handlers.Alt)  { & $script:Handlers.Alt  } })
(C 'BtnBack').Add_Click({
    Stop-JoyTimer
    if ($script:Step -gt 0) { Go ($script:Step - 1) }
})

# Steps 3, 4 and 6 commit on Next; the rest just advance. Wiring it here
# rather than inside each step keeps the step bodies about content.
$Win.Add_Closed({ Stop-JoyTimer })

$Win.Add_ContentRendered({
    Go $RenderStep
    if ($RenderTo) {
        $root = $Win.Content
        $root.UpdateLayout()
        $w = [int][Math]::Ceiling($root.ActualWidth); $h = [int][Math]::Ceiling($root.ActualHeight)
        $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, 'Pbgra32')
        $rtb.Render($root)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($RenderTo); $enc.Save($fs); $fs.Close()
        Write-Host "rendered step $RenderStep -> $RenderTo"
        $Win.Close()
    }
})

[void]$Win.ShowDialog()

try { $script:SingleInstance.ReleaseMutex() } catch { }
