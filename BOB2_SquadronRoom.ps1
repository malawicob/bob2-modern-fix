# =====================================================================
#  THE SQUADRON ROOM - Phase 1  (No. 92 Squadron RAF)
#  Fullscreen dispersal: the readiness board, framed photographs on the
#  wall, and a joining form for a new pilot.
#
#  Standalone for now (run BOB2_SquadronRoom.vbs). Writes nothing to the
#  game; the only state is your pilot in <GameDir>\SquadronRoom\pilot.json
#  (or beside this script if the game folder is not found). Portraits and
#  the historical roster ship read-only in .\squadronroom\.
# =====================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ModDir      = Join-Path $ScriptDir 'squadronroom'
$PortraitDir = Join-Path $ModDir 'portraits'
$SeedPath    = Join-Path $ModDir 'roster.seed.json'
$PortIndex   = Join-Path $ModDir 'portraits.json'

function Find-GameDir {
    foreach ($d in @($ScriptDir, (Split-Path $ScriptDir -Parent))) {
        if ($d -and (Test-Path (Join-Path $d 'Bob.exe'))) { return $d }
    }
    return $null
}
$GameDir   = Find-GameDir
$StateDir     = if ($GameDir) { Join-Path $GameDir 'SquadronRoom' } else { Join-Path $ModDir 'state' }
$PilotPath    = Join-Path $StateDir 'pilot.json'
$SessionsPath = Join-Path $StateDir 'sessions.json'
$FlightOpen   = Join-Path $StateDir 'flight.open'

# --- squadrons a new pilot may join (bases as the campaign opens) -------
$Squadrons = @(
    @{ Num=19;  Ic='O'; Code='QV'; Type='Spitfire I';  Base='RAF Duxford';       Lon=0.13;  Lat=52.09; Grp=12; Dx=0; Dy=0; Mx=0.565; My=0.075; Px=0 }
    @{ Num=54;  Ic='C'; Code='KL'; Type='Spitfire I';  Base='RAF Rochford';      Lon=0.70;  Lat=51.57; Grp=11; Dx=0; Dy=0; Mx=0.694; My=0.381; Px=0 }
    @{ Num=64;  Ic='O'; Code='SH'; Type='Spitfire I';  Base='RAF Kenley';        Lon=-0.10; Lat=51.30; Grp=11; Dx=0; Dy=0; Mx=0.525; My=0.542; Px=0 }
    @{ Num=65;  Ic='C'; Code='YT'; Type='Spitfire I';  Base='RAF Hornchurch';    Lon=0.21;  Lat=51.53; Grp=11; Dx=0; Dy=-5; Mx=0.599; My=0.396; Px=-11 }
    @{ Num=74;  Ic='C'; Code='ZP'; Type='Spitfire I';  Base='RAF Hornchurch';    Lon=0.21;  Lat=51.53; Grp=11; Dx=0; Dy=5; Mx=0.599; My=0.396; Px=11 }
    @{ Num=92;  Ic='C'; Code='QJ'; Type='Spitfire I';  Base='RAF Pembrey';       Lon=-4.32; Lat=51.71; Grp=10; Dx=0; Dy=0; Mx=-1; My=-1; Px=0 }
    @{ Num=152; Ic='O'; Code='SN'; Type='Spitfire I';  Base='RAF Warmwell';      Lon=-2.32; Lat=50.70; Grp=10; Dx=0; Dy=0; Mx=0.134; My=0.737; Px=0 }
    @{ Num=609; Ic='O'; Code='PR'; Type='Spitfire I';  Base='RAF Middle Wallop'; Lon=-1.57; Lat=51.14; Grp=10; Dx=0; Dy=-5; Mx=0.258; My=0.601; Px=11 }
    @{ Num=610; Ic='C'; Code='DW'; Type='Spitfire I';  Base='RAF Biggin Hill';   Lon=0.03;  Lat=51.33; Grp=11; Dx=0; Dy=-5; Mx=0.553; My=0.547; Px=11 }
    @{ Num=611; Ic='C'; Code='FY'; Type='Spitfire I';  Base='RAF Digby';         Lon=-0.43; Lat=53.09; Grp=12; Dx=0; Dy=0; Mx=-1; My=-1; Px=0 }
    @{ Num=1;   Ic='O'; Code='JX'; Type='Hurricane I'; Base='RAF Northolt';      Lon=-0.42; Lat=51.55; Grp=11; Dx=0; Dy=0; Mx=0.449; My=0.349; Px=0 }
    @{ Num=17;  Ic='C'; Code='YB'; Type='Hurricane I'; Base='RAF Debden';        Lon=0.26;  Lat=51.99; Grp=11; Dx=0; Dy=0; Mx=0.624; My=0.21; Px=0 }
    @{ Num=32;  Ic='C'; Code='GZ'; Type='Hurricane I'; Base='RAF Biggin Hill';   Lon=0.03;  Lat=51.33; Grp=11; Dx=0; Dy=5; Mx=0.553; My=0.547; Px=-11 }
    @{ Num=43;  Ic='O'; Code='FT'; Type='Hurricane I'; Base='RAF Tangmere';      Lon=-0.71; Lat=50.85; Grp=11; Dx=0; Dy=-5; Mx=0.426; My=0.742; Px=-11 }
    @{ Num=56;  Ic='C'; Code='US'; Type='Hurricane I'; Base='RAF North Weald';   Lon=0.10;  Lat=51.72; Grp=11; Dx=0; Dy=-5; Mx=0.57; My=0.288; Px=-11 }
    @{ Num=111; Ic='O'; Code='JU'; Type='Hurricane I'; Base='RAF Croydon';       Lon=-0.12; Lat=51.36; Grp=11; Dx=0; Dy=0; Mx=0.518; My=0.487; Px=0 }
    @{ Num=151; Ic='C'; Code='DZ'; Type='Hurricane I'; Base='RAF North Weald';   Lon=0.10;  Lat=51.72; Grp=11; Dx=0; Dy=5; Mx=0.57; My=0.288; Px=11 }
    @{ Num=213; Ic='O'; Code='AK'; Type='Hurricane I'; Base='RAF Exeter';        Lon=-3.41; Lat=50.73; Grp=10; Dx=0; Dy=0; Mx=-1; My=-1; Px=0 }
    @{ Num=238; Ic='O'; Code='VK'; Type='Hurricane I'; Base='RAF Middle Wallop'; Lon=-1.57; Lat=51.14; Grp=10; Dx=0; Dy=5; Mx=0.258; My=0.601; Px=-11 }
    @{ Num=242; Ic='O'; Code='LE'; Type='Hurricane I'; Base='RAF Coltishall';    Lon=1.36;  Lat=52.75; Grp=12; Dx=0; Dy=0; Mx=-1; My=-1; Px=0 }
    @{ Num=501; Ic='C'; Code='SD'; Type='Hurricane I'; Base='RAF Gravesend';     Lon=0.37;  Lat=51.43; Grp=11; Dx=0; Dy=0; Mx=0.624; My=0.459; Px=0 }
    @{ Num=601; Ic='O'; Code='UF'; Type='Hurricane I'; Base='RAF Tangmere';      Lon=-0.71; Lat=50.85; Grp=11; Dx=0; Dy=5; Mx=0.426; My=0.742; Px=11 }
)
function Get-SquadronDef { param([int]$Num)
    foreach ($q in $Squadrons) { if ($q.Num -eq $Num) { return $q } }
    $null
}

# --- data ---------------------------------------------------------------
function Get-Portraits {
    if (Test-Path $PortIndex) { try { return @(Get-Content $PortIndex -Raw | ConvertFrom-Json) } catch { } }
    @(Get-ChildItem $PortraitDir -Filter '*.jpg' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.Name })
}
function Get-Historical {
    if (Test-Path $SeedPath) { try { return @(Get-Content $SeedPath -Raw | ConvertFrom-Json) } catch { } }
    @()
}
function Get-Pilot {
    if (Test-Path $PilotPath) { try { return (Get-Content $PilotPath -Raw | ConvertFrom-Json) } catch { } }
    $null
}
function Save-Pilot {
    param($Pilot)
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $Pilot | ConvertTo-Json -Depth 6 | Set-Content -Path $PilotPath -Encoding UTF8
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
          <Ellipse Fill="#1C3F94"/>
          <Ellipse Fill="#F2EFE6" Margin="8"/>
          <Ellipse Fill="#C8102E" Margin="17"/>
        </Grid>
        <StackPanel Margin="20,0,0,0" VerticalAlignment="Center">
          <TextBlock Style="{StaticResource Serif}" FontSize="27" FontWeight="Bold"
                     Foreground="{StaticResource Ink}" x:Name="HdrSquadron" Text="No. 92 Squadron"/>
          <TextBlock Style="{StaticResource Cond}" FontSize="13" Foreground="{StaticResource Faint}"
                     x:Name="HdrMotto" Text="ROYAL AIR FORCE  &#x2022;  AUT PUGNA AUT MORERE" Margin="1,3,0,0"/>
        </StackPanel>
      </StackPanel>
      <Border x:Name="RoomPlay" Background="#C8973F" CornerRadius="3" Cursor="Hand"
              HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,84,0" Padding="26,10">
        <TextBlock Text="PLAY" FontFamily="Bahnschrift SemiCondensed, Segoe UI" FontSize="17"
                   FontWeight="Bold" Foreground="#171203"/>
      </Border>
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
            @{ start = (Get-Date).ToString('s'); dateBefore = $before } | ConvertTo-Json | Set-Content -Path $FlightOpen -Encoding UTF8
            $sav0 = Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
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
function New-TB {
    param([string]$Text, [string]$Family = 'Segoe UI', [double]$Size = 15, $Colour, [switch]$Bold, [switch]$Wrap)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontFamily = $Family; $t.FontSize = $Size
    if ($Bold) { $t.FontWeight = 'SemiBold' }
    if ($Colour) { $t.Foreground = B $Colour }
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    $t
}
$SerifFam = 'Rockwell, Georgia, Cambria, serif'
$CondFam  = 'Bahnschrift SemiCondensed, Segoe UI'
function Fate-Colour { param([string]$s)
    if ($s -match 'KIA|Killed|Died|DoW') { return '#D66A5C' }
    if ($s -match 'WIA|Wounded|Injured') { return '#D9A441' }
    if ($s -match 'POW|Captured|Prisoner') { return '#9FB0B8' }
    '#8FB56A'
}

# --- campaign clock: the board is a snapshot of THIS day ----------------
# Reads the newest campaign save the same way BOB2_Setup.ps1 does
# (u32 seconds since 1901-01-01 at offset 61). $null when no campaign.
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
        $secs = [BitConverter]::ToUInt32($b, 61)
        if ($secs % 86400 -ne 0) { return $null }
        $date = ([datetime]'1901-01-01').AddSeconds($secs)
        if ($date.Year -lt 1939 -or $date.Year -gt 1941) { return $null }
        return $date
    } catch { return $null }
}
# Where No. 92 Squadron was based on a given date (1940).
#   Croydon -> Hornchurch (Dunkirk, 23 May) -> Pembrey (Wales, mid-Jun)
#   -> Biggin Hill (the battle proper, 8 Sep).
function Get-Airfield {
    param($Date)
    if (-not $Date) { return $null }
    $moves = @(
        @{ d = [datetime]'1940-01-01'; f = 'RAF Croydon' },
        @{ d = [datetime]'1940-05-23'; f = 'RAF Hornchurch' },
        @{ d = [datetime]'1940-06-18'; f = 'RAF Pembrey' },
        @{ d = [datetime]'1940-09-08'; f = 'RAF Biggin Hill' }
    )
    $cur = $moves[0].f
    foreach ($m in $moves) { if ($Date -ge $m.d) { $cur = $m.f } }
    $cur
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
        $plane = [System.Text.Encoding]::ASCII.GetString($b, 121, 21).TrimEnd([char]0)
        if ($name -notmatch '^[ -~]{2,20}$') { return $null }
        return @{ Name = $name; Plane = $plane }
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
# A pilot's fate date: an explicit fate_date wins, else parsed from status.
function Get-FateDate {
    param($P)
    if (($P.PSObject.Properties.Name -contains 'fate_date') -and $P.fate_date) {
        try { return [datetime]::ParseExact("$($P.fate_date)", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    Parse-FateDate "$($P.status)"
}
# What this pilot's status reads AS OF the campaign date. Before his loss he
# is on strength; on or after, his recorded fate. No date -> final record.
function Resolve-Status {
    param($P, $Date)
    $raw = "$($P.status)"
    if ($Date) {
        $fate = Get-FateDate $P
        if ($fate -and ($Date -lt $fate)) { return @{ Text = 'On strength'; Colour = '#8FB56A' } }
    }
    @{ Text = $raw; Colour = (Fate-Colour $raw) }
}
# Victories credited by the campaign date. Documented for the aces, estimated
# for the others from their combat record; accrued across their 1940 window.
function Accrue-Victories {
    param($P, $Date)
    $total = 0
    if (($P.PSObject.Properties.Name -contains 'victories') -and ($null -ne $P.victories)) { $total = [int]$P.victories }
    if ($total -le 0) { return '' }
    if (-not $Date) { return "$total" }
    $start = [datetime]'1940-05-10'
    $end = Get-FateDate $P; if (-not $end) { $end = [datetime]'1940-10-31' }
    if ($Date -le $start) { return '0' }
    if ($end -le $start) { return "$total" }
    if ($Date -ge $end) { return "$total" }
    $frac = ($Date - $start).TotalDays / ($end - $start).TotalDays
    "$([math]::Round($total * $frac))"
}
# Decorations, shown once the campaign date reaches the (approx) award date.
function Get-Awards {
    param($P, $Date)
    $aw = ''
    if (($P.PSObject.Properties.Name -contains 'awards') -and $P.awards) { $aw = "$($P.awards)" }
    if (-not $aw) { return '' }
    if ($Date -and ($P.PSObject.Properties.Name -contains 'award_date') -and $P.award_date) {
        try {
            $ad = [datetime]::ParseExact("$($P.award_date)", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            if ($Date -lt $ad) { return '' }
        } catch { }
    }
    $aw
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
function Get-AircraftSpec { param([string]$Type)
    if ($Type -match 'Hurricane') {
        return @{ Img='hurricane.png'; Ratio=(300.0/1000.0); SqX=0.4118; SqY=0.3474; IndX=0.6313; IndY=0.3532; SerX=0.7182; SerTy=0.4750; CodeSize=78.0; SerSize=46.0 }
    }
    @{ Img='spitfire.png'; Ratio=(324.0/1000.0); SqX=0.4194; SqY=0.3461; IndX=0.6727; IndY=0.3326; SerX=0.7443; SerTy=0.4487; CodeSize=84.0; SerSize=32.0 }
}
$AircraftImg  = Join-Path (Join-Path $ModDir 'aircraft') 'spitfire.png'
$AcW          = 760.0            # on-screen width; height follows the image
$AcRatio      = 324.0 / 1000.0   # staged spitfire.png aspect
# historically-approximate: RAF 'Sky' grey block codes, black serial
$CodeFont     = 'Bahnschrift SemiBold, Bahnschrift, Franklin Gothic Medium, Arial'
$CodeColour   = '#C3C9B4'
$SerialFont   = 'Bahnschrift Condensed, Arial Narrow, Arial'
$SerialColour = '#171712'
$CodeSize     = 84.0
$SerialSize   = 32.0
$SqX          = 0.415          # QJ left edge (fraction), forward of the roundel
$IndX         = 0.685          # individual letter, aft of the roundel
$SerX         = 0.775          # serial, toward the tail
$FuseY        = 0.51           # fuselage centreline at the roundel (codes)
$SerY         = 0.565          # serial sits lower than the codes, as on the real aircraft
# saved marking position (fraction) or a default
function Mk-Val {
    param($Mk, [string]$Name, [double]$Default)
    if ($Mk -and ($Mk.PSObject.Properties.Name -contains $Name) -and ($null -ne $Mk.$Name)) { return [double]$Mk.$Name }
    $Default
}
# persist one marking's top-left fraction into pilot.json under 'markings'
function Save-Marking {
    param([string]$KeyX, [double]$Vx, [string]$KeyY, [double]$Vy)
    $pilot = Get-Pilot; if (-not $pilot) { return }
    $mk = @{}
    if (($pilot.PSObject.Properties.Name -contains 'markings') -and $pilot.markings) {
        foreach ($p in $pilot.markings.PSObject.Properties) { $mk[$p.Name] = $p.Value }
    }
    $mk[$KeyX] = [math]::Round($Vx, 4); $mk[$KeyY] = [math]::Round($Vy, 4)
    $obj = [ordered]@{}
    foreach ($p in $pilot.PSObject.Properties) { if ($p.Name -ne 'markings') { $obj[$p.Name] = $p.Value } }
    $obj['markings'] = $mk
    Save-Pilot $obj
}
# make a marking draggable on the aircraft canvas; saves where you drop it
function Make-Draggable {
    param($El, [string]$KeyX, [string]$KeyY)
    $El.Cursor = 'SizeAll'
    $El.Background = [Windows.Media.Brushes]::Transparent
    $El.Tag = @{ kx = $KeyX; ky = $KeyY; drag = $false; ox = 0.0; oy = 0.0 }
    $El.Add_MouseLeftButtonDown({
        param($s,$e)
        $t = $s.Tag; $p = $e.GetPosition($script:AcCanvas)
        $t.ox = $p.X - [Windows.Controls.Canvas]::GetLeft($s)
        $t.oy = $p.Y - [Windows.Controls.Canvas]::GetTop($s)
        $t.drag = $true; [void]$s.CaptureMouse(); $e.Handled = $true
    })
    $El.Add_MouseMove({
        param($s,$e)
        $t = $s.Tag
        if ($t.drag) {
            $p = $e.GetPosition($script:AcCanvas)
            [Windows.Controls.Canvas]::SetLeft($s, $p.X - $t.ox)
            [Windows.Controls.Canvas]::SetTop($s, $p.Y - $t.oy)
        }
    })
    $El.Add_MouseLeftButtonUp({
        param($s,$e)
        $t = $s.Tag
        if ($t.drag) {
            $t.drag = $false; [void]$s.ReleaseMouseCapture()
            $lx = [Windows.Controls.Canvas]::GetLeft($s) / $script:AcW
            $ty = [Windows.Controls.Canvas]::GetTop($s) / $script:AcHpx
            Save-Marking $t.kx $lx $t.ky $ty
        }
    })
}
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
    $obj['sqn'] = 92; $obj['sqcode'] = 'QJ'; $obj['actype'] = 'Spitfire I'; $obj['base'] = 'RAF Biggin Hill'
    Save-Pilot $obj
    Get-Pilot
}
function Set-Header {
    param($Pilot)
    $num = 92; $grp = 10
    if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { $num = [int]$Pilot.sqn }
    $def = Get-SquadronDef $num
    if ($def) { $grp = [int]$def.Grp }
    $h = C 'HdrSquadron'; if ($h) { $h.Text = "No. $num Squadron" }
    $m = C 'HdrMotto'
    if ($m) {
        $m.Text = if ($num -eq 92) { "ROYAL AIR FORCE  $([char]0x2022)  AUT PUGNA AUT MORERE" }
                  else { "ROYAL AIR FORCE  $([char]0x2022)  NO. $grp GROUP, FIGHTER COMMAND" }
    }
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

    $tSq = New-TB -Text $sq -Family $CodeFont -Size ([double]$spec.CodeSize) -Colour $CodeColour -Bold
    [Windows.Controls.Canvas]::SetLeft($tSq, [double]$spec.SqX * $AcW)
    [Windows.Controls.Canvas]::SetTop($tSq,  [double]$spec.SqY * $acH)
    [void]$cv.Children.Add($tSq)

    $tInd = New-TB -Text $ind -Family $CodeFont -Size ([double]$spec.CodeSize) -Colour $CodeColour -Bold
    [Windows.Controls.Canvas]::SetLeft($tInd, [double]$spec.IndX * $AcW)
    [Windows.Controls.Canvas]::SetTop($tInd,  [double]$spec.IndY * $acH)
    [void]$cv.Children.Add($tInd)

    $ser = "$($Pilot.serials)"
    if ($ser) {
        $tSer = New-TB -Text $ser -Family $SerialFont -Size ([double]$spec.SerSize) -Colour $SerialColour -Bold
        [Windows.Controls.Canvas]::SetLeft($tSer, [double]$spec.SerX * $AcW)
        [Windows.Controls.Canvas]::SetTop($tSer,  [double]$spec.SerTy * $acH)
        [void]$cv.Children.Add($tSer)
    }
    [void]$wrap.Children.Add($cv)
    $wrap
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
    param($P,[switch]$Header,[int]$Index=0,[switch]$IsPlayer)
    $b = New-Object Windows.Controls.Border
    $b.Padding = '18,10,18,10'; $b.BorderThickness = '0,0,0,1'; $b.BorderBrush = Res 'Rule'
    if ($Header) { $b.Background = B '#101B22' }
    elseif ($IsPlayer) { $b.Background = B '#26313B'; $b.BorderBrush = Res 'BrassDk' }
    elseif ($Index % 2 -eq 1) { $b.Background = Res 'Panel' }
    else { $b.Background = Res 'PanelHi' }

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
        [void]$ns.Children.Add((New-TB -Text ("$($P.pilot)") -Family $SerifFam -Size 15.5 -Colour '#E9E3D4'))
        $rc = "$($P.rank)"; if ($P.codes) { $rc = "$($P.rank)   $([char]0x2022)   $($P.codes)" }
        $rct = New-TB -Text $rc -Family $CondFam -Size 11.5 -Colour '#6F828C'; $rct.Margin = '0,2,0,0'
        [void]$ns.Children.Add($rct)
        [Windows.Controls.Grid]::SetColumn($ns,0); [void]$g.Children.Add($ns)

        $vic = if ($IsPlayer) { $(if ([int]$P.victories -gt 0) { "$($P.victories)" } else { '' }) } else { Accrue-Victories $P $script:CampaignDate }
        Add-Cell $g $vic 1 $CondFam 16 '#D9B45A' -Center -Bold
        $aw = if ($IsPlayer) { "$($P.awards)" } else { Get-Awards $P $script:CampaignDate }
        Add-Cell $g $aw 2 $CondFam 13.5 '#C8973F' -Bold
        $stat = Resolve-Status $P $script:CampaignDate
        Add-Cell $g $stat.Text 3 $CondFam 13.5 $stat.Colour
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
            $j = Get-Content $SessionsPath -Raw | ConvertFrom-Json
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
    try { $mk = Get-Content $FlightOpen -Raw | ConvertFrom-Json } catch { }
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
    Remove-Item $beforeSnap -Force -ErrorAction SilentlyContinue
    $sess = [ordered]@{
        end        = $end.ToString('s')
        minutes    = $mins
        dateBefore = "$($mk.dateBefore)"
        dateAfter  = if ($after) { $after.ToString('yyyy-MM-dd') } else { "$($mk.dateBefore)" }
        mode       = if ($mk.dateBefore) { 'campaign' } else { 'instant' }
        outcome    = $outcome
    }
    Save-Sessions (@(Get-Sessions) + $sess)
    Remove-Item $FlightOpen -Force -ErrorAction SilentlyContinue
}

function Get-Career {
    param($Pilot, $Sessions)
    $sorties = @($Sessions).Count
    $mins = 0; foreach ($s in $Sessions) { $mins += [int]$s.minutes }
    $hours = [math]::Round($mins / 60.0, 1)
    if (($Pilot.PSObject.Properties.Name -contains 'cmode') -and ("$($Pilot.cmode)" -eq 'commander')) {
        return @{ sorties = $sorties; hours = $hours; rank = 'Squadron Leader'; next = $null; nextAt = 0 }
    }
    $ladder = @('Sergeant','Pilot Officer','Flying Officer','Flight Lieutenant')
    $idx = [array]::IndexOf($ladder, "$($Pilot.rank)"); if ($idx -lt 0) { $idx = 0 }
    $step = 12
    $promos = [math]::Floor($sorties / $step)
    $curIdx = [math]::Min($ladder.Count - 1, $idx + $promos)
    $next = $null; $nextAt = 0
    if ($curIdx -lt $ladder.Count - 1) { $next = $ladder[$curIdx + 1]; $nextAt = ($promos + 1) * $step }
    @{ sorties = $sorties; hours = $hours; rank = $ladder[$curIdx]; next = $next; nextAt = $nextAt }
}
# The player's own decoration. Stored award wins; otherwise a DFC once he has
# five victories (a plausible Battle of Britain threshold). "None yet" before.
# Rank-aware honours ladder, computed from the record. Sergeants earn the
# DFM, officers the DFC (as the RAF actually did); a second award of the
# same decoration is a Bar. Mentioned in Despatches for sustained flying.
function Get-PlayerHonours {
    param($Pilot, $Career)
    $v = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $v = [int]$Pilot.victories }
    $sorties = 0; if ($Career) { $sorties = [int]$Career.sorties }
    $isNCO = ("$($Career.rank)" -eq 'Sergeant')
    $cross = if ($isNCO) { 'DFM' } else { 'DFC' }
    $h = @()
    if ($sorties -ge 10) { $h += 'MiD' }
    if ($v -ge 5)  { $h += $cross }
    if ($v -ge 10) { $h += "Bar to $cross" }
    if ($v -ge 15) { $h += 'DSO' }
    if (($Pilot.PSObject.Properties.Name -contains 'awards') -and $Pilot.awards -and ($h -notcontains "$($Pilot.awards)")) { $h = @("$($Pilot.awards)") + $h }
    ,$h
}
# Player-entered victory with the type shot down (auto claims are Tier 4).
function Add-Claim {
    param($Pilot, [string]$Type = '')
    $v = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $v = [int]$Pilot.victories }
    $claims = @(); if (($Pilot.PSObject.Properties.Name -contains 'claims') -and $Pilot.claims) { $claims = @($Pilot.claims) }
    $cd = Get-CampaignDate; $when = if ($cd) { $cd.ToString('yyyy-MM-dd') } else { (Get-Date).ToString('yyyy-MM-dd') }
    $entry = if ($Type) { "$when $Type" } else { "$when" }
    $obj = [ordered]@{}
    foreach ($p in $Pilot.PSObject.Properties) { $obj[$p.Name] = $p.Value }
    $obj['victories'] = $v + 1
    $obj['claims'] = @($claims + $entry)
    Save-Pilot $obj
    Show-Logbook -Pilot (Get-Pilot)
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
    param([string]$Label, [string]$Value)
    $b = New-Object Windows.Controls.Border
    $b.Background = Res 'Panel'; $b.BorderBrush = Res 'Rule'; $b.BorderThickness = '1'; $b.CornerRadius = '4'
    $b.Padding = '20,14'; $b.Margin = '0,0,16,0'; $b.MinWidth = 148
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-TB -Text $Value -Family $SerifFam -Size 30 -Colour '#E9E3D4' -Bold))
    $l = New-TB -Text $Label -Family $CondFam -Size 11.5 -Colour '#C8973F' -Bold; $l.Margin = '0,2,0,0'
    [void]$sp.Children.Add($l)
    $b.Child = $sp; $b
}
function New-Nav {
    param([string]$Current)
    $nav = New-Object Windows.Controls.StackPanel; $nav.Orientation = 'Horizontal'; $nav.Margin = '0,0,0,22'
    foreach ($t in @(@{k='dispersal';l='THE DISPERSAL'}, @{k='logbook';l="PILOT'S LOGBOOK"})) {
        $active = ($t.k -eq $Current)
        $tb = New-Object Windows.Controls.Border
        $tb.Padding = '15,9'; $tb.Margin = '0,0,10,0'; $tb.CornerRadius = '3'; $tb.Cursor = 'Hand'; $tb.Tag = $t.k
        $tb.Background = if ($active) { Res 'PanelHi' } else { B '#101B22' }
        $tb.BorderThickness = '0,0,0,2'
        $tb.BorderBrush = if ($active) { Res 'Brass' } else { B '#101B22' }
        $col = if ($active) { '#E9E3D4' } else { '#6F828C' }
        $tb.Child = (New-TB -Text $t.l -Family $CondFam -Size 12.5 -Colour $col -Bold)
        $tb.Add_MouseLeftButtonUp({
            param($s,$e)
            $pl = Get-Pilot
            if ($s.Tag -eq 'logbook') { Show-Logbook -Pilot $pl } else { Show-Roster -Pilot $pl }
        })
        [void]$nav.Children.Add($tb)
    }
    # start again with a different squadron; the old career is archived
    $nc = New-Object Windows.Controls.Border
    $nc.Padding = '15,9'; $nc.Margin = '18,0,0,0'; $nc.CornerRadius = '3'; $nc.Cursor = 'Hand'
    $nc.Background = B '#101B22'; $nc.BorderThickness = '0,0,0,2'; $nc.BorderBrush = B '#101B22'
    $nc.Child = (New-TB -Text 'START A NEW CAREER' -Family $CondFam -Size 12.5 -Colour '#6F828C' -Bold)
    $nc.Add_MouseLeftButtonUp({
        $ans = [System.Windows.MessageBox]::Show($Win,
            "Start a new career? Your current pilot and logbook are archived (not deleted) and you choose a squadron for the new man.",
            'New career', 'YesNo', 'Question')
        if ($ans -eq 'Yes') {
            try {
                $arch = Join-Path $StateDir ('archive\' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
                New-Item -ItemType Directory -Path $arch -Force | Out-Null
                foreach ($f in @($PilotPath, $SessionsPath)) {
                    if (Test-Path $f) { Move-Item $f (Join-Path $arch (Split-Path $f -Leaf)) -Force }
                }
                # a flight marker or save snapshot from the OLD career must not
                # become the new pilot's phantom first sortie
                foreach ($f in @($FlightOpen, (Join-Path $StateDir 'before.bsr'))) {
                    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
                }
            } catch { }
            Show-SquadronSelect
        }
    })
    [void]$nav.Children.Add($nc)
    $nav
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
function Show-Logbook {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'logbook'))
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow "PILOT'S LOGBOOK" -Title ("$($Pilot.pilot)")))

    $cp = Get-CampaignPilot
    if ($cp) {
        $cpTxt = "Campaign pilot on record: $($cp.Name)"
        if ($cp.Plane) { $cpTxt += ", flying '$($cp.Plane)'" }
        $cpl = New-TB -Text $cpTxt -Family 'Segoe UI' -Size 13 -Colour '#9FB0B8'
        $cpl.Margin = '0,-12,0,14'
        [void]$script:Stage.Children.Add($cpl)
    }

    $sessions = Get-Sessions
    $career = Get-Career $Pilot $sessions
    $vics = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $vics = [int]$Pilot.victories }

    $tiles = New-Object Windows.Controls.StackPanel; $tiles.Orientation = 'Horizontal'; $tiles.Margin = '0,-6,0,12'
    [void]$tiles.Children.Add((New-Stat 'SORTIES' "$($career.sorties)"))
    [void]$tiles.Children.Add((New-Stat 'FLYING HOURS' "$($career.hours)"))
    [void]$tiles.Children.Add((New-Stat 'VICTORIES' "$vics"))
    $honours = @(Get-PlayerHonours $Pilot $career)
    $awTile = if ($honours.Count) { $honours[$honours.Count-1] } else { 'None yet' }
    [void]$tiles.Children.Add((New-Stat 'AWARDS' $awTile))
    [void]$tiles.Children.Add((New-Stat 'RANK' "$($career.rank)"))
    [void]$script:Stage.Children.Add($tiles)

    $isCmdr2 = (($Pilot.PSObject.Properties.Name -contains 'cmode') -and ("$($Pilot.cmode)" -eq 'commander'))
    $pn = if ($isCmdr2) { 'You command the squadron. Its fortunes in the air are yours to answer for.' }
          elseif ($career.next) { "Next promotion to $($career.next) at $($career.nextAt) sorties." } else { 'At the top of the tree.' }
    if ($honours.Count) { $pn = "Honours: $($honours -join ', ').  $pn" }
    $cs = Get-ClaimSummary $Pilot
    if ($cs) { $pn = "Claims: $cs.  $pn" }
    $pnt = New-TB -Text $pn -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Wrap; $pnt.Margin = '0,2,0,18'; $pnt.MaxWidth = 860; $pnt.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($pnt)

    $claimRow = New-Object Windows.Controls.StackPanel; $claimRow.Orientation = 'Horizontal'; $claimRow.Margin = '0,0,0,22'
    $script:ClaimType = New-Object Windows.Controls.ComboBox
    $script:ClaimType.MinWidth = 150; $script:ClaimType.Margin = '0,0,12,0'; $script:ClaimType.VerticalAlignment = 'Center'
    foreach ($t in @('Bf 109E','Bf 110','Do 17','He 111','Ju 87','Ju 88','Other')) { [void]$script:ClaimType.Items.Add($t) }
    $script:ClaimType.SelectedIndex = 0
    [void]$claimRow.Children.Add($script:ClaimType)
    $cbtn = New-Object Windows.Controls.Button; $cbtn.Content = 'LOG A CLAIM'; $cbtn.MinWidth = 130
    $cbtn.Add_Click({ Add-Claim -Pilot (Get-Pilot) -Type ("$($script:ClaimType.SelectedItem)") })
    [void]$claimRow.Children.Add($cbtn)
    $ct = New-TB -Text 'Record a victory you scored on your last sortie. Automatic claims from the game are still to come.' -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Wrap
    $ct.VerticalAlignment = 'Center'; $ct.Margin = '16,0,0,0'; $ct.MaxWidth = 460
    [void]$claimRow.Children.Add($ct)
    [void]$script:Stage.Children.Add($claimRow)

    [void]$script:Stage.Children.Add((New-TB -Text 'SORTIES FLOWN' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
    if (@($sessions).Count -eq 0) {
        $none = New-TB -Text 'No sorties logged yet. Fly from the launcher and your logbook fills itself.' -Family 'Segoe UI' -Size 13.5 -Colour '#9FB0B8' -Wrap
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
    $baseTxt = if ($sqnum -eq 92 -and $script:CampaignDate) { (Get-Airfield $script:CampaignDate).ToUpper() }
               elseif (($Pilot.PSObject.Properties.Name -contains 'base') -and $Pilot.base) { "$($Pilot.base)".ToUpper() }
               else { 'THE DISPERSAL' }
    $eyebrow = if ($script:CampaignDate) { "$baseTxt  $([char]0x2022)  $($script:CampaignDate.ToString('dddd d MMMM yyyy').ToUpper())" } else { $baseTxt }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow $eyebrow -Title "No. $sqnum Squadron at readiness"))

    # the only photograph on the wall is yours
    $hero = New-Object Windows.Controls.StackPanel; $hero.Orientation = 'Horizontal'; $hero.Margin = '0,-6,0,32'
    [void]$hero.Children.Add((New-Frame -Pilot $Pilot -IsPlayer))
    $d = New-Object Windows.Controls.StackPanel; $d.Margin = '30,4,0,0'; $d.VerticalAlignment = 'Top'
    [void]$d.Children.Add((New-TB -Text ("$($Pilot.pilot)") -Family $SerifFam -Size 30 -Colour '#E9E3D4' -Bold))
    $line = if (@(Get-Sessions).Count -gt 0) { "$($Pilot.rank)   $([char]0x2022)   $($Pilot.codes)" } else { "$($Pilot.rank)   $([char]0x2022)   awaiting first operation" }
    $lt = New-TB -Text $line -Family $CondFam -Size 15 -Colour '#9FB0B8'; $lt.Margin = '0,7,0,0'
    [void]$d.Children.Add($lt)
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
    if (@(Get-Sessions).Count -eq 0) {
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
    $flown = (@(Get-Sessions).Count -gt 0)
    $ac = if ($flown) { New-Aircraft -Pilot $Pilot } else { $null }
    if ($ac) {
        [void]$script:Stage.Children.Add($ac)
    }

    # the squadron as a records book: names, victories, fate
    [void]$script:Stage.Children.Add((New-TB -Text 'THE SQUADRON' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
    $subText = if ($script:CampaignDate) {
        "The squadron as it stood on $($script:CampaignDate.ToString('d MMMM yyyy')). Men on strength show as such; losses, victories and awards appear as their day is reached. Victories and decorations are documented for the aces and estimated for the others."
    } else {
        'No campaign in progress, so this shows the final Battle of Britain record. Victories and decorations are documented for the aces and estimated for the others. Start a campaign and the board tracks the squadron day by day.'
    }
    $sub = New-TB -Text $subText -Family 'Segoe UI' -Size 13 -Colour '#6F828C' -Wrap
    $sub.Margin = '0,4,0,14'; $sub.MaxWidth = 720; $sub.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($sub)

    $listWrap = New-Object Windows.Controls.Border
    $listWrap.BorderBrush = Res 'Rule'; $listWrap.BorderThickness = '1'; $listWrap.CornerRadius = '3'; $listWrap.ClipToBounds = $true
    $ls = New-Object Windows.Controls.StackPanel
    [void]$ls.Children.Add((New-RosterRow -Header))
    # you, first on the board, with your LIVE record
    $sessions0 = Get-Sessions
    $career0 = Get-Career $Pilot $sessions0
    $pv = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $pv = [int]$Pilot.victories }
    $ph = @(Get-PlayerHonours $Pilot $career0)
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
    if ($sqnum -eq 92) {
        foreach ($h in (Get-Historical)) { [void]$ls.Children.Add((New-RosterRow -P $h -Index $i)); $i++ }
    }
    $listWrap.Child = $ls
    [void]$script:Stage.Children.Add($listWrap)
    if ($sqnum -ne 92) {
        $nr = New-TB -Text 'Squadron roster research for this unit is still to come; your own record is on the board.' -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C'
        $nr.Margin = '2,8,0,0'
        [void]$script:Stage.Children.Add($nr)
    }
}

function Update-CreateValid {
    $ok = ($script:NameBox.Text.Trim().Length -ge 2) -and ($null -ne $script:SelPortrait)
    $script:SubmitBtn.IsEnabled = $ok
}
function Invoke-Submit {
    $isCmdr = $false
    $rank = 'Sergeant'
    $letter = ('A','B','D','E','F','G','H','J','K','L','N','P','R','S','T','U','V','W','X','Y','Z' | Get-Random)
    $serial = New-Serial -Type ("$($script:SelSq.Type)")
    $pilot = [ordered]@{
        pilot   = $script:NameBox.Text.Trim()
        rank    = $rank
        codes   = "$($script:SelSq.Code)-$letter"
        status  = 'On strength'
        serials = $serial
        note    = "Posted to No. $($script:SelSq.Num) Squadron at $($script:SelSq.Base)."
        cmode   = if ($isCmdr) { 'commander' } else { 'pilot' }
        sqn     = [int]$script:SelSq.Num
        sqcode  = "$($script:SelSq.Code)"
        actype  = "$($script:SelSq.Type)"
        base    = "$($script:SelSq.Base)"
        historical = $false
        portrait = $script:SelPortrait
        created = (Get-Date).ToString('yyyy-MM-dd')
    }
    Save-Pilot -Pilot $pilot
    Show-Roster -Pilot (Get-Pilot)
}

# =====================================================================
#  Postings: choose your squadron on the plotting map
# =====================================================================
function Map-XY { param([double]$Lon,[double]$Lat,[double]$W,[double]$H)
    ,@((($Lon + 5.6) / 7.7 * $W), ((53.8 - $Lat) / 4.3 * $H))
}
function Show-SquadronSelect {
    $script:Stage.Children.Clear()
    Set-Header $null
    $h = C 'HdrSquadron'; if ($h) { $h.Text = 'Fighter Command' }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "ROYAL AIR FORCE  $([char]0x2022)  POSTINGS" }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'THE PLOTTING TABLE' -Title 'Choose your squadron'))
    $lead = New-TB -Text 'Sector and fighter airfields, South East England, 1940. Click a ringed station to see the squadron, then report to it. The key is printed on the table.' -Family 'Segoe UI' -Size 14 -Colour '#9FB0B8' -Wrap
    $lead.Margin = '0,-14,0,4'
    [void]$script:Stage.Children.Add($lead)
    $hint2 = New-TB -Text 'A ring sitting off its station can be dragged onto it; the correction is remembered.' -Family 'Segoe UI' -Size 12 -Colour '#6F828C'
    $hint2.Margin = '0,0,0,12'
    [void]$script:Stage.Children.Add($hint2)

    $W = 1080.0; $H = [math]::Round($W * 805.0 / 1600.0)
    $mapWrap = New-Object Windows.Controls.Border
    $mapWrap.Width = $W + 2; $mapWrap.Height = $H + 2; $mapWrap.HorizontalAlignment = 'Left'
    $mapWrap.Background = B '#0B141B'; $mapWrap.BorderBrush = Res 'Rule'; $mapWrap.BorderThickness = '1'; $mapWrap.CornerRadius = '3'
    $grid = New-Object Windows.Controls.Grid
    $imgPath = Join-Path (Join-Path $ModDir 'map') 'sector-map.jpg'
    $bg = New-Object Windows.Controls.Image
    $bmp = Load-Image -Path $imgPath -DecodeWidth 1600
    if ($bmp) { $bg.Source = $bmp }
    $bg.Stretch = 'Uniform'; $bg.Width = $W; $bg.Height = $H
    [void]$grid.Children.Add($bg)
    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $W; $cv.Height = $H; $cv.ClipToBounds = $true
    [void]$grid.Children.Add($cv)
    $mapWrap.Child = $grid

    $script:SelSq = $null
    $script:SqDots = @()
    $script:SqChips = @()
    $detail = New-TB -Text 'No squadron selected.' -Family 'Segoe UI' -Size 14 -Colour '#9FB0B8' -Wrap
    $btn = New-Object Windows.Controls.Button
    $btn.Content = 'REPORT TO THIS SQUADRON'; $btn.IsEnabled = $false; $btn.MinWidth = 240
    $script:SqDetail = $detail
    $script:SqButton = $btn

    # hand-corrected ring anchors, remembered across sessions and careers
    $script:RingPosPath = Join-Path $StateDir 'ringpos.json'
    $script:RingPos = @{}
    if (Test-Path $script:RingPosPath) {
        try {
            $rp = Get-Content $script:RingPosPath -Raw | ConvertFrom-Json
            foreach ($pp in $rp.PSObject.Properties) { $script:RingPos[$pp.Name] = $pp.Value }
        } catch { }
    }

    $script:SelectSq = {
        param($q2)
        $script:SelSq = $q2
        foreach ($d in $script:SqDots) {
            $d.Stroke = if ("$($d.Tag.Ic)" -eq 'C') { B '#5FD0E8' } else { B '#F5A83C' }
            $d.StrokeThickness = 2.5; $d.Width = 30; $d.Height = 30
            [Windows.Controls.Canvas]::SetLeft($d, $d.Tag.CX - 15); [Windows.Controls.Canvas]::SetTop($d, $d.Tag.CY - 15)
        }
        foreach ($d in $script:SqDots) {
            if ($d.Tag.Num -eq $q2.Num) {
                $d.Stroke = B '#FFE28A'; $d.StrokeThickness = 3.5; $d.Width = 38; $d.Height = 38
                [Windows.Controls.Canvas]::SetLeft($d, $d.Tag.CX - 19); [Windows.Controls.Canvas]::SetTop($d, $d.Tag.CY - 19)
            }
        }
        foreach ($cp in $script:SqChips) {
            $cp.BorderBrush = if ($cp.Tag.Num -eq $q2.Num) { B '#FFE28A' } else { Res 'Rule' }
        }
        $script:SqDetail.Text = "No. $($q2.Num) Squadron  $([char]0x2022)  $($q2.Type)  $([char]0x2022)  $($q2.Base)  $([char]0x2022)  No. $($q2.Grp) Group   (codes $($q2.Code)-)"
        $script:SqButton.IsEnabled = $true
    }

    foreach ($q in $Squadrons) {
        if ([double]$q.Mx -lt 0) { continue }
        $cx = [double]$q.Mx * $W + [double]$q.Px
        $cy = [double]$q.My * $H
        $ov = $script:RingPos["$($q.Num)"]
        if ($ov) { $cx = [double]$ov.x * $W; $cy = [double]$ov.y * $H }
        $ring = New-Object Windows.Shapes.Ellipse
        $ring.Width = 30; $ring.Height = 30; $ring.StrokeThickness = 2.5
        $ring.Stroke = if ("$($q.Ic)" -eq 'C') { B '#5FD0E8' } else { B '#F5A83C' }
        $ring.Fill = B '#01000000'
        $ring.Cursor = 'Hand'
        $qt = @{}; foreach ($k in $q.Keys) { $qt[$k] = $q[$k] }
        $qt.CX = $cx; $qt.CY = $cy
        [Windows.Controls.Canvas]::SetLeft($ring, $cx - 15); [Windows.Controls.Canvas]::SetTop($ring, $cy - 15)
        # click selects; a drag repositions the ring and is remembered
        $nl = New-TB -Text "$($q.Num)" -Family $CondFam -Size 11.5 -Colour '#D8D2BC' -Bold
        $nl.IsHitTestVisible = $false
        [Windows.Controls.Canvas]::SetLeft($nl, $cx - 10); [Windows.Controls.Canvas]::SetTop($nl, $cy + 17)
        $qt.Label = $nl; $qt.MapW = $W; $qt.MapH = $H
        $qt.Drag = $false; $qt.Moved = $false; $qt.OX = 0.0; $qt.OY = 0.0
        $ring.Tag = $qt
        $ring.Add_MouseLeftButtonDown({
            param($sender,$e)
            $t = $sender.Tag
            $pt = $e.GetPosition($sender.Parent)
            $t.Drag = $true; $t.Moved = $false
            $t.OX = $pt.X - $t.CX; $t.OY = $pt.Y - $t.CY
            [void]$sender.CaptureMouse(); $e.Handled = $true
        })
        $ring.Add_MouseMove({
            param($sender,$e)
            $t = $sender.Tag
            if ($t.Drag) {
                $pt = $e.GetPosition($sender.Parent)
                $nx = $pt.X - $t.OX; $ny = $pt.Y - $t.OY
                if ([math]::Abs($nx - $t.CX) -gt 3 -or [math]::Abs($ny - $t.CY) -gt 3) { $t.Moved = $true }
                if ($t.Moved) {
                    $t.CX = $nx; $t.CY = $ny
                    $half = $sender.Width / 2.0
                    [Windows.Controls.Canvas]::SetLeft($sender, $nx - $half); [Windows.Controls.Canvas]::SetTop($sender, $ny - $half)
                    [Windows.Controls.Canvas]::SetLeft($t.Label, $nx - 10); [Windows.Controls.Canvas]::SetTop($t.Label, $ny + 17)
                }
            }
        })
        $ring.Add_MouseLeftButtonUp({
            param($sender,$e)
            $t = $sender.Tag
            if ($t.Drag) {
                $t.Drag = $false; [void]$sender.ReleaseMouseCapture()
                if ($t.Moved) {
                    $script:RingPos["$($t.Num)"] = @{ x = [math]::Round($t.CX / $t.MapW, 4); y = [math]::Round($t.CY / $t.MapH, 4) }
                    try { $script:RingPos | ConvertTo-Json | Set-Content -Path $script:RingPosPath -Encoding UTF8 } catch { }
                } else {
                    & $script:SelectSq $t
                }
            }
        })
        $script:SqDots += $ring
        [void]$cv.Children.Add($ring)
        [void]$cv.Children.Add($nl)
    }

    [void]$script:Stage.Children.Add($mapWrap)

    # postings beyond this table's edge
    $far = @($Squadrons | Where-Object { [double]$_.Mx -lt 0 })
    if ($far.Count) {
        $fl = New-TB -Text 'POSTINGS BEYOND THIS TABLE' -Family $CondFam -Size 11.5 -Colour '#8A9689' -Bold
        $fl.Margin = '2,12,0,6'
        [void]$script:Stage.Children.Add($fl)
        $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'
        foreach ($q in $far) {
            $isSpit = ("$($q.Type)" -match 'Spitfire')
            $chip = New-Object Windows.Controls.Border
            $chip.Padding = '12,7'; $chip.Margin = '0,0,10,0'; $chip.CornerRadius = '3'; $chip.Cursor = 'Hand'
            $chip.Background = B '#101B22'; $chip.BorderBrush = Res 'Rule'; $chip.BorderThickness = '1.5'
            $ct = New-TB -Text "No. $($q.Num)  $([char]0x2022)  $($q.Base -replace '^RAF ','')" -Family $CondFam -Size 12 -Colour $(if ($isSpit) { '#9FE0F0' } else { '#F8C87E' }) -Bold
            $chip.Child = $ct
            $qt = @{}; foreach ($k in $q.Keys) { $qt[$k] = $q[$k] }
            $chip.Tag = $qt
            $chip.Add_MouseLeftButtonUp({ param($sender,$e) & $script:SelectSq $sender.Tag })
            $script:SqChips += $chip
            [void]$chips.Children.Add($chip)
        }
        [void]$script:Stage.Children.Add($chips)
    }

    $detail.Margin = '2,14,0,14'
    [void]$script:Stage.Children.Add($detail)
    $btn.Add_Click({ if ($script:SelSq) { Show-Create } })
    $btnRow = New-Object Windows.Controls.StackPanel; $btnRow.Orientation='Horizontal'
    [void]$btnRow.Children.Add($btn)
    [void]$script:Stage.Children.Add($btnRow)
}

function Show-Create {
    $script:Stage.Children.Clear()
    $script:SelPortrait = $null; $script:SelBorder = $null
    if (-not $script:SelSq) { $script:SelSq = Get-SquadronDef 92 }
    Set-Header $null
    $h = C 'HdrSquadron'; if ($h) { $h.Text = "No. $($script:SelSq.Num) Squadron" }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "ROYAL AIR FORCE  $([char]0x2022)  $($script:SelSq.Type.ToUpper())S AT $($script:SelSq.Base.ToUpper())" }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'REPORT TO THE ADJUTANT' -Title "A new pilot for No. $($script:SelSq.Num)"))
    $lead = New-TB -Text 'Summer 1940. Give your name and pick your photograph. Your aircraft, code letter and rank are settled once you have flown your first operation.' -Family 'Segoe UI' -Size 14.5 -Colour '#9FB0B8' -Wrap
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
$existing = Get-Pilot
if ($existing) { Show-Roster -Pilot $existing } else { Show-SquadronSelect }
[void]$Win.ShowDialog()
