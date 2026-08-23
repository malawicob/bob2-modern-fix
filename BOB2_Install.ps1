# =====================================================================
#  INSTALL AND REPAIR - BOB2 2.13 Modern Fix
# =====================================================================
#
#  WHY THIS EXISTS
#    Install and repair used to be a numbered menu in a black console
#    window - and the wizard opened it at step 2, so a first-time user
#    being walked through setup was suddenly handed a DOS prompt.
#
#  WHAT IT IS NOT
#    It is NOT a reimplementation of the installer. BOB2_Setup.ps1 is
#    2,127 lines of install logic that works, already organised into the
#    right units (Step-ApplyV213, Step-InstallDgVoodoo2, Step-ApplyCrashFix,
#    Step-Win11Tweaks, Do-Uninstall...). This dot-sources that file with
#    -AsLibrary, which defines every function and runs nothing, and then
#    drives it. One implementation of each step, not two.
#
#  THE SHAPE OF THE SCREEN
#    One row per thing, showing its real state - not a menu of verbs. You
#    read what is wrong before choosing to fix it, and a row that is fine
#    offers no button at all. The console detail still exists, collapsed
#    behind "Details", because it is evidence rather than an interface.
# =====================================================================

param(
    [string]$RenderTo,
    # Who opened this window, so Done can go back where you came from
    # rather than always to the launcher.
    [ValidateSet('launcher','wizard')]
    [string]$From = 'launcher'
)

$ErrorActionPreference = 'Stop'

if (-not $RenderTo) {
    try {
        Add-Type -Namespace BOB2I -Name Win -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        $h = [BOB2I.Win]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][BOB2I.Win]::ShowWindow($h, 0) }
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
$script:SingleInstance = New-Object System.Threading.Mutex($false, 'Global\BOB2InstallRepair')
if (-not $script:SingleInstance.WaitOne(0)) {
    try {
        Add-Type -Namespace BOB2S -Name Fg -MemberDefinition @'
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        foreach ($p in (Get-Process powershell -ErrorAction SilentlyContinue)) {
            if ($p.MainWindowTitle -eq 'Install and repair') {
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
        'Install and repair', 'OK', 'Error')
    break
}

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
$GameDir = Find-GameDir -Start $ScriptDir
if (-not $GameDir) {
    [void][System.Windows.MessageBox]::Show(
        'Battle of Britain II was not found. Put this folder inside the game folder and try again.',
        'Game not found', 'OK', 'Warning')
    exit 1
}

# ---------------------------------------------------------------------
#  Bring in the installer as a library. Its Write-* helpers go to the
#  console; we capture that stream into the Details pane instead.
# ---------------------------------------------------------------------
$script:LogLines = New-Object Collections.Generic.List[string]
$SetupPs1 = Join-Path $ScriptDir 'BOB2_Setup.ps1'
$script:HaveSetup = Test-Path $SetupPs1
if ($script:HaveSetup) {
    try { . $SetupPs1 -AsLibrary } catch {
        $script:HaveSetup = $false
        $script:LogLines.Add("Could not load BOB2_Setup.ps1: $($_.Exception.Message)")
    }
}

# =====================================================================
#  CHECKS - read-only. Each returns state, a one-line detail, and the
#  action that would put it right.
# =====================================================================

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
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public delegate bool EnumProc(IntPtr h, IntPtr p);
'@ -ErrorAction SilentlyContinue

function Find-Window {
    param([string]$Title)
    $script:WantTitle = $Title
    $script:FoundHwnd = [IntPtr]::Zero
    $cb = [BOB2N.Nav+EnumProc]{
        param($h, $p)
        if ([BOB2N.Nav]::IsWindowVisible($h)) {
            $sb = New-Object Text.StringBuilder 256
            [void][BOB2N.Nav]::GetWindowText($h, $sb, $sb.Capacity)
            if ($sb.ToString() -eq $script:WantTitle) { $script:FoundHwnd = $h; return $false }
        }
        return $true
    }
    [void][BOB2N.Nav]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:FoundHwnd
}

function Return-ToCaller {
    # Done means "I have finished here, take me home" - always the main
    # screen, whichever window opened this one. An earlier version returned
    # to the wizard when the wizard had opened it, which is not what Done
    # says and left the user one step further from where they wanted to be.
    #
    # The wizard, if it is open, is closed rather than left behind: it was
    # only ever a route to this window, and an abandoned wizard sitting
    # half-finished behind the launcher is exactly the thing being fixed.
    $wiz = Find-Window 'First Flight - Battle of Britain II'
    if ($wiz -ne [IntPtr]::Zero) {
        [void][BOB2N.Nav]::PostMessage($wiz, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CLOSE
    }

    $h = Find-Window 'Battle of Britain II'
    if ($h -ne [IntPtr]::Zero) {
        [void][BOB2N.Nav]::ShowWindow($h, 9)      # SW_RESTORE
        [void][BOB2N.Nav]::SetForegroundWindow($h)
        return
    }
    $bat = Join-Path $ScriptDir 'BOB2.bat'
    if (Test-Path $bat) { Start-Process -FilePath $bat -WorkingDirectory (Split-Path -Parent $bat) }
}

function Get-FixVersion {
    $vf = Join-Path $GameDir 'BOB2-Win11-Fix.version'
    if (Test-Path $vf) {
        $m = Select-String -Path $vf -Pattern '^FixVersion\s*=\s*(.+)$' -ErrorAction SilentlyContinue
        if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    }
    return $null
}

function Get-Checks {
    $out = New-Object Collections.Generic.List[object]

    $os = Get-WindowsRelease
    $out.Add([pscustomobject]@{
        Name='Windows'; Ok=$os.Supported
        Detail=$(if ($os.Supported) { "$($os.Full) - supported" } else { "$($os.Full). $($os.Why)" })
        Fix=$null })

    $ver = 'unknown'
    if (Test-Path (Join-Path $GameDir 'BoBII BDG v2.13 Release Notes.pdf')) { $ver = '2.13' }
    elseif (Test-Path (Join-Path $GameDir 'bob2_ver.txt')) {
        $t = (Get-Content (Join-Path $GameDir 'bob2_ver.txt') -First 4) -join ' '
        if ($t -match '(\d+\.\d+)') { $ver = $matches[1] }
    }
    $out.Add([pscustomobject]@{ Name='Game found'; Ok=$true; Detail="$GameDir  -  version $ver"; Fix=$null })

    $out.Add([pscustomobject]@{
        Name='Patch 2.13'; Ok=($ver -eq '2.13')
        Detail=$(if ($ver -eq '2.13') { 'applied' } else { "the game reports $ver - 2.13 is the community's final patch" })
        Fix=$(if ($ver -eq '2.13') { $null } else { 'Step-ApplyV213' }) })

    $ms = Join-Path $GameDir 'MultiSkin'
    $n = if (Test-Path $ms) { (Get-ChildItem $ms -Filter *.ms -ErrorAction SilentlyContinue).Count } else { 0 }
    $out.Add([pscustomobject]@{
        Name='MultiSkin'; Ok=($n -gt 0)
        Detail=$(if ($n -gt 0) { "$n skin files" } else { 'not installed - squadrons will all share one skin' })
        Fix=$(if ($n -gt 0) { $null } else { 'Step-ApplyMultiSkin' }) })

    $d3d9 = Join-Path $GameDir 'd3d9.dll'
    $wrap = 'none - the game will not start on most modern cards'
    $wok = $false
    if (Test-Path $d3d9) {
        if (Test-Path (Join-Path $GameDir 'dgVoodoo.conf')) {
            $v = ''
            try { $v = (Get-Item $d3d9).VersionInfo.ProductVersion } catch { }
            if ($v -eq '2.8.6.5') {
                $wrap = "dgVoodoo2 $v"; $wok = $true
            } else {
                # 2.8.7.x was shipped up to v1.6.26 and breaks exclusive
                # fullscreen - the 3D view renders into a corner. Flag it.
                $wrap = "dgVoodoo2 $v - wrong version, 3D renders in a corner of the screen; 2.8.6.5 needed"
                $wok = $false
            }
        } elseif (Test-Path (Join-Path $GameDir 'dxvk.conf')) {
            $wrap = 'DXVK - known to crash this game in 3D'
        } else { $wrap = 'an unrecognised d3d9.dll'; $wok = $true }
    }
    $out.Add([pscustomobject]@{
        Name='Graphics translator'; Ok=$wok; Detail=$wrap
        Fix=$(if ($wok) { $null } else { 'Step-InstallDgVoodoo2' }) })

    # ------------------------------------------------------------------
    # CAMPAIGN RESOLUTION. If settings.cfg asks for a display mode the
    # pipeline will not hold, the game silently falls back to a 1024x768
    # menu surface: the rescaled menus overflow, briefing text overlaps
    # its own tab row, and every MENU SIZE option "does nothing". The
    # game then records the failure as a degraded mode (refresh 0).
    # Cost a full day to trace; checking four ints prevents it.
    # ------------------------------------------------------------------
    $cfgP = Join-Path $GameDir 'SAVEGAME\settings.cfg'
    if (Test-Path $cfgP) {
        $cb = [System.IO.File]::ReadAllBytes($cfgP)
        if ($cb.Length -ge 1612) {
            $rw  = [BitConverter]::ToInt32($cb, 1416)
            $rh  = [BitConverter]::ToInt32($cb, 1480)
            $rhz = [BitConverter]::ToInt32($cb, 1544)
            $resOk = $true; $why = "$rw x $rh @ $rhz Hz"
            if ($rhz -le 0 -or $rw -lt 800 -or $rh -lt 600) {
                $resOk = $false; $why = "$rw x $rh @ $rhz Hz - a degraded fallback the game wrote after a failed mode switch"
            } elseif ($rhz -gt 60) {
                # High-refresh modes are what failed to hold in practice
                # (2560x1600@240 -> 1024x768 fallback). 60Hz exists at
                # every resolution this game can use.
                $resOk = $false; $why = "$rw x $rh @ $rhz Hz - high refresh rates can fail to hold and drop the menus to 1024x768"
            }
            $out.Add([pscustomobject]@{
                Name='Campaign resolution'; Ok=$resOk; Detail=$why
                Fix=$(if ($resOk) { $null } else { 'FixCampaignRes' }) })
        }
    }

    $di = Test-Path (Join-Path $GameDir 'dinput8.dll')
    $out.Add([pscustomobject]@{
        Name='Startup crash fix'; Ok=$di
        Detail=$(if ($di) { 'dinput8.dll present' } else { 'missing - the game can crash on the way into a mission' })
        Fix=$(if ($di) { $null } else { 'Step-ApplyCrashFix' }) })

    # HIGHDPIAWARE is applied again by the Program Compatibility Assistant,
    # so this one genuinely does come back on its own.
    $layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $exe = Join-Path $GameDir 'Bob.exe'
    $dpi = $false
    try {
        $props = Get-ItemProperty $layers -ErrorAction SilentlyContinue
        if ($props -and ($props.PSObject.Properties.Name -contains $exe)) { $dpi = $props.$exe -match 'HIGHDPIAWARE' }
    } catch { }
    $out.Add([pscustomobject]@{
        Name='Windows 11 flags'; Ok=(-not $dpi)
        Detail=$(if ($dpi) { 'HIGHDPIAWARE has come back - it makes the menus draw small' } else { 'correct' })
        Fix=$(if ($dpi) { 'DpiShim' } else { $null }) })

    # $FixVersion comes from BOB2_Setup.ps1, loaded as a library above, so
    # the package version and the installed stamp cannot drift apart here.
    $fv = Get-FixVersion
    $pkg = $null
    try { $pkg = $FixVersion } catch { }
    $stale = ($fv -and $pkg -and $fv -ne $pkg)
    $out.Add([pscustomobject]@{
        Name='Mod version'; Ok=($null -ne $fv -and -not $stale)
        Detail=$(if (-not $fv) { 'not recorded as installed' }
                 elseif ($stale) { "version $fv is installed. Version $pkg is in this folder, ready to apply - press Fix to update." }
                 else { "version $fv - up to date" })
        Fix=$(if ($fv -and -not $stale) { $null } else { 'StampVersion' }) })

    return $out
}

function Repair-DpiShim {
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    $exe = Join-Path $GameDir 'Bob.exe'
    try {
        $cur = (Get-ItemProperty $key -ErrorAction SilentlyContinue).$exe
        if (-not $cur) { return }
        $new = (($cur -split '\s+') | Where-Object { $_ -ne 'HIGHDPIAWARE' -and $_ -ne '' }) -join ' '
        if ($new -eq '~' -or -not $new) { Remove-ItemProperty $key -Name $exe -ErrorAction SilentlyContinue }
        else { Set-ItemProperty $key -Name $exe -Value $new }
    } catch { }
}

# =====================================================================
#  UI
# =====================================================================
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Install and repair"
        Width="900" Height="790" MinWidth="820" MinHeight="640"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        Background="#12161C" Foreground="#E4DFD4"
        UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Ideal"
        TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI Variable Text, Segoe UI, Tahoma">
  <Window.Resources>
    <SolidColorBrush x:Key="Card"      Color="#171C24"/>
    <SolidColorBrush x:Key="Rule"      Color="#232A34"/>
    <SolidColorBrush x:Key="Edge"      Color="#626A77"/>
    <SolidColorBrush x:Key="Text"      Color="#E4DFD4"/>
    <SolidColorBrush x:Key="Secondary" Color="#AEB6C2"/>
    <SolidColorBrush x:Key="Tertiary"  Color="#949DAC"/>
    <SolidColorBrush x:Key="Brass"     Color="#C8973F"/>
    <SolidColorBrush x:Key="Good"      Color="#8FB56A"/>
    <SolidColorBrush x:Key="Warn"      Color="#D9A441"/>
    <SolidColorBrush x:Key="Danger"    Color="#E2685A"/>
    <Style TargetType="Button">
      <Setter Property="FontFamily" Value="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
      <Setter Property="FontSize" Value="15"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Padding" Value="16,7"/><Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="#23262C" BorderBrush="{StaticResource Edge}"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#2C313A"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="#171203"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{StaticResource Brass}" BorderBrush="{StaticResource Brass}"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#DCA84B"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Quiet" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="{StaticResource Secondary}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent" BorderBrush="Transparent"
                    BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource Edge}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="BOB2 2.13 MODERN FIX  -  INSTALL AND REPAIR" Foreground="#AEB6C2"
                 FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Border x:Name="ChromeMin" Width="40" Height="34" Background="Transparent" Cursor="Hand">
          <TextBlock Text="&#x2013;" Foreground="#AEB6C2" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent" Cursor="Hand">
          <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </StackPanel>
    </Grid>

    <Grid Margin="34,26,34,22">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0">
        <TextBlock Text="Install and repair" FontSize="26" FontWeight="Bold" Foreground="#E4DFD4"
                   FontFamily="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
        <TextBlock Margin="0,8,0,0" FontSize="15" Foreground="#AEB6C2" TextWrapping="Wrap"
                   MaxWidth="620" HorizontalAlignment="Left" LineHeight="23"
                   Text="Everything needed to run Battle of Britain II on Windows 11. Nothing is written until you press a button, and every file is backed up before it changes."/>
      </StackPanel>

      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,22,0,0">
        <StackPanel x:Name="Rows"/>
      </ScrollViewer>

      <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,18,0,0">
        <Button x:Name="BtnAll"   Content="Install everything" Style="{StaticResource Primary}"/>
        <Button x:Name="BtnCheck" Content="Check again"/>
        <Button x:Name="BtnUninstall" Content="Uninstall..." Style="{StaticResource Quiet}" HorizontalAlignment="Right"/>
      </StackPanel>

      <Border x:Name="AllGood" Grid.Row="2" Visibility="Collapsed" Background="#16231A"
              BorderBrush="#8FB56A" BorderThickness="1" CornerRadius="5" Padding="14,11"
              Margin="0,18,0,0" HorizontalAlignment="Left">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="&#x2713;" Foreground="#8FB56A" FontSize="17" Margin="0,0,12,0" VerticalAlignment="Center"/>
          <TextBlock Foreground="#D4E4C4" FontSize="15" VerticalAlignment="Center" TextWrapping="Wrap"
                     Text="The game is correctly patched and ready to fly."/>
        </StackPanel>
      </Border>

      <StackPanel Grid.Row="4" Margin="0,14,0,0">
        <TextBlock x:Name="ResultText" Visibility="Collapsed" FontSize="14" Foreground="#8FB56A"
                   TextWrapping="Wrap" Margin="0,0,0,10" MaxWidth="640" HorizontalAlignment="Left"/>
        <Button x:Name="BtnDetails" Content="&#x25B8; Details" Style="{StaticResource Quiet}"
                HorizontalAlignment="Left" Padding="0,4"/>
        <Border x:Name="LogBox" Visibility="Collapsed" Background="#0D1116" BorderBrush="#232A34"
                BorderThickness="1" CornerRadius="4" Margin="0,8,0,0" Height="150">
          <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto" Padding="12,8">
            <TextBlock x:Name="LogText" FontFamily="Cascadia Mono, Consolas" FontSize="12"
                       Foreground="#949DAC" TextWrapping="Wrap"/>
          </ScrollViewer>
        </Border>
      </StackPanel>
    </Grid>
  </DockPanel>
  </Border>
</Window>
'@

$Win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$Xaml)))
function C { param($n) $Win.FindName($n) }
function Res { param($k) $Win.FindResource($k) }

$bar = C 'ChromeBar'
if ($bar) { $bar.Add_MouseLeftButtonDown({ $Win.DragMove() }) }
# Each chrome button marks its event handled, or it bubbles up to the title
# bar's DragMove and the bar captures the mouse instead.
foreach ($pair in @(@('ChromeClose', { param($s,$e) $e.Handled = $true; $Win.Close() }),
                    @('ChromeMin',   { param($s,$e) $e.Handled = $true; $Win.WindowState = 'Minimized' }))) {
    $el = C $pair[0]
    if ($el) {
        $el.Add_MouseLeftButtonDown($pair[1])
        $el.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#2C313A') })
        $el.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
    }
}

function Set-Result {
    # Always derived from a FRESH check, never from a captured variable, so
    # this line cannot disagree with the button beside it - which is how
    # "Done" ended up sitting next to "1 still needs attention".
    param([string]$Did)
    $t = C 'ResultText'
    if (-not $t) { return }
    $bad = @($script:Checks | Where-Object { -not $_.Ok })
    if ($bad.Count -eq 0) {
        $t.Text = "$Did Everything is installed."
        $t.Foreground = Res 'Good'
    } else {
        $names = ($bad | ForEach-Object { $_.Name }) -join ', '
        $t.Text = "$Did $names still needs attention. Press Check again, or close this and re-open it - some steps only take effect once the file is released."
        $t.Foreground = Res 'Warn'
    }
    $t.Visibility = 'Visible'
}

function Add-Log {
    param([string[]]$Lines)
    foreach ($l in $Lines) { if ($l) { $script:LogLines.Add($l) } }
    (C 'LogText').Text = ($script:LogLines -join "`n")
}

function Invoke-Step {
    # The Step-* functions talk to the console. Capture that and put it in
    # Details rather than throwing it away - it is the evidence that used to
    # fill the whole screen.
    param([string]$Name)
    if ($Name -eq 'DpiShim') { Repair-DpiShim; Add-Log 'Removed the HIGHDPIAWARE compatibility flag.'; return }
    if ($Name -eq 'FixCampaignRes') {
        # Write a mode that holds: the display's native W x H at 60Hz.
        # 60Hz is enumerated at every resolution on every display seen so
        # far; native size keeps the menus as large as the panel allows.
        $cfgP = Join-Path $GameDir 'SAVEGAME\settings.cfg'
        if (-not (Test-Path $cfgP)) { Add-Log 'settings.cfg not found.'; return }
        $w = 1920; $h = 1080
        try {
            $vc = Get-CimInstance Win32_VideoController | Select-Object -First 1
            if ($vc.CurrentHorizontalResolution -ge 800) { $w = [int]$vc.CurrentHorizontalResolution; $h = [int]$vc.CurrentVerticalResolution }
        } catch { }
        $cb = [System.IO.File]::ReadAllBytes($cfgP)
        Copy-Item $cfgP "$cfgP.before-resfix" -Force
        [Array]::Copy([BitConverter]::GetBytes([int]$w),  0, $cb, 1416, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]$h),  0, $cb, 1480, 4)
        [Array]::Copy([BitConverter]::GetBytes([int]60),  0, $cb, 1544, 4)
        [System.IO.File]::WriteAllBytes($cfgP, $cb)
        Add-Log "Campaign resolution set to $w x $h @ 60 Hz (settings.cfg backed up as .before-resfix)."
        return
    }
    if ($Name -eq 'StampVersion') {
        # A stale stamp almost always means a stale dinput8.dll too - the
        # stamp records that file's MD5 - so refresh the guard first, then
        # rewrite the stamp. Step-InstallLauncher does neither, which is why
        # pressing Fix appeared to do nothing.
        Add-Log '--- Updating this install to the current version'
        try { Add-Log ((Step-ApplyCrashFix -GameFolder $GameDir 6>&1 4>&1 3>&1 2>&1 | Out-String) -split "`r?`n") } catch { Add-Log "  crash fix: $($_.Exception.Message)" }
        try {
            Add-Log ((Write-VersionStamp -GameFolder $GameDir 6>&1 4>&1 3>&1 2>&1 | Out-String) -split "`r?`n")
        } catch { Add-Log "  stamp: $($_.Exception.Message)" }
        return
    }
    if (-not $script:HaveSetup) { Add-Log "Cannot run $Name - BOB2_Setup.ps1 did not load."; return }
    $fn = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $fn) { Add-Log "Cannot run $Name - no such step in BOB2_Setup.ps1."; return }
    Add-Log "--- $Name"
    # Nearly every Step-* takes -GameFolder. Calling them bare left it empty
    # and produced "Cannot bind argument to parameter 'Path'" from the first
    # Join-Path inside - which read as the step doing nothing.
    $splat = @{}
    if ($fn.Parameters.ContainsKey('GameFolder')) { $splat['GameFolder'] = $GameDir }
    try { Add-Log ((& $Name @splat 6>&1 4>&1 3>&1 2>&1 | Out-String) -split "`r?`n") }
    catch {
        $msg = $_.Exception.Message
        Add-Log "  failed: $msg"
        # A step that needs a file or an answer used to call Read-Host, which
        # with no console blocks forever on a dead window - the "I click Fix
        # and nothing happens" a tester hit on a v2.06 install that needed a
        # patch file he did not have. Those now throw a marked error, and it
        # has to be SEEN: putting it in the collapsed Details panel is barely
        # better than the freeze it replaced.
        if ($msg -match '^NEEDS-(FILE|ANSWER):\s*(.+)$') {
            [void][System.Windows.MessageBox]::Show(
                $Matches[2],
                'Something is needed before this can run',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information)
        }
    }
}

function New-Row {
    param($Check)
    $card = New-Object Windows.Controls.Border
    $card.Background = Res 'Card'
    $card.BorderBrush = Res 'Rule'
    $card.BorderThickness = 1
    $card.CornerRadius = 5
    $card.Padding = '14,11'
    $card.Margin = '0,0,0,8'

    $g = New-Object Windows.Controls.Grid
    foreach ($w in @('26','220','*','Auto')) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = [Windows.GridLength]::new(1, $(if ($w -eq '*') { 'Star' } elseif ($w -eq 'Auto') { 'Auto' } else { 'Pixel' }))
        if ($w -notin @('*','Auto')) { $cd.Width = [Windows.GridLength]::new([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }

    $mark = New-Object Windows.Controls.TextBlock
    $mark.Text = $(if ($Check.Ok) { [char]0x2713 } else { '!' })
    $mark.Foreground = $(if ($Check.Ok) { Res 'Good' } else { Res 'Warn' })
    $mark.FontSize = 16; $mark.VerticalAlignment = 'Center'
    [void]$g.Children.Add($mark)

    $name = New-Object Windows.Controls.TextBlock
    $name.Text = $Check.Name; $name.FontSize = 15; $name.FontWeight = 'SemiBold'
    $name.Foreground = Res 'Text'; $name.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($name, 1)
    [void]$g.Children.Add($name)

    $det = New-Object Windows.Controls.TextBlock
    $det.Text = $Check.Detail; $det.FontSize = 13.5
    $det.Foreground = $(if ($Check.Ok) { Res 'Secondary' } else { Res 'Warn' })
    $det.TextWrapping = 'Wrap'; $det.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($det, 2)
    [void]$g.Children.Add($det)

    # A row that is fine offers no button. Only problems get an action.
    if ($Check.Fix) {
        $b = New-Object Windows.Controls.Button
        $b.Content = 'Fix'; $b.MinWidth = 74; $b.Margin = '12,0,0,0'
        $b.Tag = $Check.Fix
        $b.Add_Click({
            param($s,$e)
            Invoke-Step $s.Tag
            Refresh-Rows
            Set-Result 'Done.'
        }.GetNewClosure())
        [Windows.Controls.Grid]::SetColumn($b, 3)
        [void]$g.Children.Add($b)
    }
    $card.Child = $g
    return $card
}

function Refresh-Rows {
    $rows = C 'Rows'
    $rows.Children.Clear()
    $script:Checks = Get-Checks
    foreach ($c in $script:Checks) { [void]$rows.Children.Add((New-Row $c)) }
    $bad = @($script:Checks | Where-Object { -not $_.Ok }).Count
    (C 'AllGood').Visibility = $(if ($bad -eq 0) { 'Visible' } else { 'Collapsed' })
    # With nothing to fix, the primary button's job is to let you leave.
    # A button whose only outcome is a dialog saying "nothing happened" is
    # an interruption pretending to be an action.
    (C 'BtnAll').Content = $(if ($bad -eq 0) { 'Done' } else { "Fix $bad " + $(if ($bad -eq 1) { 'thing' } else { 'things' }) })
}

(C 'BtnCheck').Add_Click({ Add-Log '--- checked again'; Refresh-Rows })

(C 'BtnAll').Add_Click({
    $os = Get-WindowsRelease
    if (-not $os.Supported) {
        [void][Windows.MessageBox]::Show($Win,
            "$($os.Full)`n`n$($os.Why)`n`nNothing has been changed.",
            'Not a supported version of Windows', 'OK', 'Warning')
        return
    }
    $bad = @($script:Checks | Where-Object { -not $_.Ok -and $_.Fix })
    if ($bad.Count -eq 0) { Return-ToCaller; $Win.Close(); return }
    $n = $bad.Count
    foreach ($c in $bad) { Invoke-Step $c.Fix }
    Refresh-Rows
    Set-Result "Applied $n of $n."
})

(C 'BtnUninstall').Add_Click({
    $r = [Windows.MessageBox]::Show($Win,
        "This puts back the files this mod replaced: Bob.exe, the graphics translator, dinput8.dll and the Windows compatibility flags.`n`nYour settings, key bindings and saved games are not touched.`n`nCarry on?",
        'Uninstall the fix', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }
    Invoke-Step 'Do-Uninstall'
    Refresh-Rows
    Set-Result 'Uninstall finished.'
})

(C 'BtnDetails').Add_Click({
    $box = C 'LogBox'
    $open = $box.Visibility -eq 'Visible'
    $box.Visibility = $(if ($open) { 'Collapsed' } else { 'Visible' })
    (C 'BtnDetails').Content = $(if ($open) { [char]0x25B8 + ' Details' } else { [char]0x25BE + ' Details' })
})

$Win.Add_ContentRendered({
    Refresh-Rows
    Add-Log "Install and repair opened. Game folder: $GameDir"
    if ($RenderTo) {
        $root = $Win.Content; $root.UpdateLayout()
        $w = [int][Math]::Ceiling($root.ActualWidth); $h = [int][Math]::Ceiling($root.ActualHeight)
        $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, 'Pbgra32')
        $rtb.Render($root)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($RenderTo); $enc.Save($fs); $fs.Close()
        Write-Host "rendered -> $RenderTo"
        $Win.Close()
    }
})

[void]$Win.ShowDialog()

try { $script:SingleInstance.ReleaseMutex() } catch { }
