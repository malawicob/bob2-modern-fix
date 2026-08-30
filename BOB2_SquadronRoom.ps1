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
    @{ Num=19;  Code='QV'; Type='Spitfire I';  Base='RAF Duxford';       Lon=0.13;  Lat=52.09; Grp=12; Lx=8;   Ly=-14 }
    @{ Num=54;  Code='KL'; Type='Spitfire I';  Base='RAF Rochford';      Lon=0.70;  Lat=51.57; Grp=11; Lx=8;   Ly=-4 }
    @{ Num=64;  Code='SH'; Type='Spitfire I';  Base='RAF Kenley';        Lon=-0.10; Lat=51.30; Grp=11; Lx=-52; Ly=6 }
    @{ Num=65;  Code='YT'; Type='Spitfire I';  Base='RAF Hornchurch';    Lon=0.21;  Lat=51.53; Grp=11; Lx=8;   Ly=-16 }
    @{ Num=74;  Code='ZP'; Type='Spitfire I';  Base='RAF Hornchurch';    Lon=0.21;  Lat=51.53; Grp=11; Lx=8;   Ly=2 }
    @{ Num=92;  Code='QJ'; Type='Spitfire I';  Base='RAF Pembrey';       Lon=-4.32; Lat=51.71; Grp=10; Lx=8;   Ly=-14 }
    @{ Num=152; Code='SN'; Type='Spitfire I';  Base='RAF Warmwell';      Lon=-2.32; Lat=50.70; Grp=10; Lx=8;   Ly=4 }
    @{ Num=609; Code='PR'; Type='Spitfire I';  Base='RAF Middle Wallop'; Lon=-1.57; Lat=51.14; Grp=10; Lx=8;   Ly=-16 }
    @{ Num=610; Code='DW'; Type='Spitfire I';  Base='RAF Biggin Hill';   Lon=0.03;  Lat=51.33; Grp=11; Lx=8;   Ly=2 }
    @{ Num=611; Code='FY'; Type='Spitfire I';  Base='RAF Digby';         Lon=-0.43; Lat=53.09; Grp=12; Lx=8;   Ly=-14 }
    @{ Num=1;   Code='JX'; Type='Hurricane I'; Base='RAF Northolt';      Lon=-0.42; Lat=51.55; Grp=11; Lx=-46; Ly=-16 }
    @{ Num=17;  Code='YB'; Type='Hurricane I'; Base='RAF Debden';        Lon=0.26;  Lat=51.99; Grp=11; Lx=8;   Ly=-4 }
    @{ Num=32;  Code='GZ'; Type='Hurricane I'; Base='RAF Biggin Hill';   Lon=0.03;  Lat=51.33; Grp=11; Lx=8;   Ly=16 }
    @{ Num=43;  Code='FT'; Type='Hurricane I'; Base='RAF Tangmere';      Lon=-0.71; Lat=50.85; Grp=11; Lx=-46; Ly=2 }
    @{ Num=56;  Code='US'; Type='Hurricane I'; Base='RAF North Weald';   Lon=0.10;  Lat=51.72; Grp=11; Lx=-52; Ly=-14 }
    @{ Num=111; Code='JU'; Type='Hurricane I'; Base='RAF Croydon';       Lon=-0.12; Lat=51.36; Grp=11; Lx=-58; Ly=-16 }
    @{ Num=151; Code='DZ'; Type='Hurricane I'; Base='RAF North Weald';   Lon=0.10;  Lat=51.72; Grp=11; Lx=8;   Ly=-2 }
    @{ Num=213; Code='AK'; Type='Hurricane I'; Base='RAF Exeter';        Lon=-3.41; Lat=50.73; Grp=10; Lx=8;   Ly=-14 }
    @{ Num=238; Code='VK'; Type='Hurricane I'; Base='RAF Middle Wallop'; Lon=-1.57; Lat=51.14; Grp=10; Lx=8;   Ly=2 }
    @{ Num=242; Code='LE'; Type='Hurricane I'; Base='RAF Coltishall';    Lon=1.36;  Lat=52.75; Grp=12; Lx=8;   Ly=-4 }
    @{ Num=501; Code='SD'; Type='Hurricane I'; Base='RAF Gravesend';     Lon=0.37;  Lat=51.43; Grp=11; Lx=8;   Ly=8 }
    @{ Num=601; Code='UF'; Type='Hurricane I'; Base='RAF Tangmere';      Lon=-0.71; Lat=50.85; Grp=11; Lx=-46; Ly=18 }
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
        return @{ Img='hurricane.png'; Ratio=(316.0/1000.0); SqX=0.40; IndX=0.675; SerX=0.775; FuseY=0.565; SerY=0.635; CodeSize=80.0 }
    }
    @{ Img='spitfire.png'; Ratio=(324.0/1000.0); SqX=0.415; IndX=0.685; SerX=0.775; FuseY=0.51; SerY=0.565; CodeSize=84.0 }
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
    $AcRatio = [double]$spec.Ratio
    $SqX = [double]$spec.SqX; $IndX = [double]$spec.IndX; $SerX = [double]$spec.SerX
    $FuseY = [double]$spec.FuseY; $SerY = [double]$spec.SerY; $CodeSize = [double]$spec.CodeSize
    if (-not (Test-Path $AircraftImg)) { return $null }
    $acH = $AcW * $AcRatio
    $script:AcW = $AcW; $script:AcHpx = $acH
    $wrap = New-Object Windows.Controls.Grid
    $wrap.Width = $AcW; $wrap.Height = $acH; $wrap.HorizontalAlignment = 'Left'; $wrap.Margin = '0,2,0,10'
    $img = New-Object Windows.Controls.Image
    $bmp = Load-Image -Path $AircraftImg -DecodeWidth 900
    if ($bmp) { $img.Source = $bmp }
    $img.Stretch = 'Fill'; $img.Width = $AcW; $img.Height = $acH
    [void]$wrap.Children.Add($img)

    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $AcW; $cv.Height = $acH
    $script:AcCanvas = $cv
    $mk = if ($Pilot.PSObject.Properties.Name -contains 'markings') { $Pilot.markings } else { $null }
    $codes = "$($Pilot.codes)"
    $sq = ($codes -replace '-.*','')
    $ind = ''; if ($codes -match '-(.+)$') { $ind = $matches[1] }
    $defCodeTy = ($FuseY * $acH - 0.52 * $CodeSize) / $acH
    $defSerTy  = ($SerY  * $acH - 0.52 * $SerialSize) / $acH

    $tSq = New-TB -Text $sq -Family $CodeFont -Size $CodeSize -Colour $CodeColour -Bold
    [Windows.Controls.Canvas]::SetLeft($tSq, (Mk-Val $mk 'sqx' $SqX) * $AcW)
    [Windows.Controls.Canvas]::SetTop($tSq,  (Mk-Val $mk 'sqy' $defCodeTy) * $acH)
    Make-Draggable $tSq 'sqx' 'sqy'
    [void]$cv.Children.Add($tSq)

    $tInd = New-TB -Text $ind -Family $CodeFont -Size $CodeSize -Colour $CodeColour -Bold
    [Windows.Controls.Canvas]::SetLeft($tInd, (Mk-Val $mk 'indx' $IndX) * $AcW)
    [Windows.Controls.Canvas]::SetTop($tInd,  (Mk-Val $mk 'indy' $defCodeTy) * $acH)
    Make-Draggable $tInd 'indx' 'indy'
    [void]$cv.Children.Add($tInd)

    $ser = "$($Pilot.serials)"
    if ($ser) {
        $tSer = New-TB -Text $ser -Family $SerialFont -Size $SerialSize -Colour $SerialColour -Bold
        [Windows.Controls.Canvas]::SetLeft($tSer, (Mk-Val $mk 'serx' $SerX) * $AcW)
        [Windows.Controls.Canvas]::SetTop($tSer,  (Mk-Val $mk 'sery' $defSerTy) * $acH)
        Make-Draggable $tSer 'serx' 'sery'
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
    $out = @()
    if (Test-Path $SessionsPath) { try { $out = @(Get-Content $SessionsPath -Raw | ConvertFrom-Json) } catch { $out = @() } }
    ,$out
}
function Save-Sessions {
    param($S)
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    ,@($S) | ConvertTo-Json -Depth 6 | Set-Content -Path $SessionsPath -Encoding UTF8
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
    $line = "$($Pilot.rank)   $([char]0x2022)   $($Pilot.codes)"
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
    $Pilot = Ensure-Serial -Pilot $Pilot
    $ac = New-Aircraft -Pilot $Pilot
    if ($ac) {
        [void]$script:Stage.Children.Add($ac)
        $hint = New-TB -Text 'Drag the codes or the serial to reposition them. They stay where you drop them.' -Family 'Segoe UI' -Size 12 -Colour '#6F828C'
        $hint.Margin = '2,0,0,24'
        [void]$script:Stage.Children.Add($hint)
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

    # start again with a different squadron; the old career is archived
    $nc = New-Object Windows.Controls.Border
    $nc.Margin = '0,26,0,0'; $nc.Padding = '12,8'; $nc.CornerRadius = '3'; $nc.HorizontalAlignment = 'Left'
    $nc.Background = B '#101B22'; $nc.BorderBrush = Res 'Rule'; $nc.BorderThickness = '1'; $nc.Cursor = 'Hand'
    $nc.Child = (New-TB -Text 'START A NEW CAREER' -Family $CondFam -Size 12 -Colour '#9FB0B8' -Bold)
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
            } catch { }
            Show-SquadronSelect
        }
    })
    [void]$script:Stage.Children.Add($nc)
}

function Update-CreateValid {
    $ok = ($script:NameBox.Text.Trim().Length -ge 2) -and `
          ($script:LetBox.Text.Trim().Length -eq 1) -and `
          ($null -ne $script:SelPortrait)
    $script:SubmitBtn.IsEnabled = $ok
}
function Invoke-Submit {
    $isCmdr = ($script:RbCmd -and $script:RbCmd.IsChecked)
    $rank = if ($isCmdr) { 'Squadron Leader' } elseif ($script:RbPO.IsChecked) { 'Pilot Officer' } else { 'Sergeant' }
    $serial = New-Serial -Type ("$($script:SelSq.Type)")
    $pilot = [ordered]@{
        pilot   = $script:NameBox.Text.Trim()
        rank    = $rank
        codes   = "$($script:SelSq.Code)-$($script:LetBox.Text.Trim().ToUpper())"
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
    $lead = New-TB -Text 'The board as the battle opens. Pick a squadron to see its aircraft and station, then report to it.' -Family 'Segoe UI' -Size 14 -Colour '#9FB0B8' -Wrap
    $lead.Margin = '0,-14,0,16'
    [void]$script:Stage.Children.Add($lead)

    $W = 900.0; $H = 560.0
    $mapWrap = New-Object Windows.Controls.Border
    $mapWrap.Width = $W + 2; $mapWrap.Height = $H + 2; $mapWrap.HorizontalAlignment = 'Left'
    $mapWrap.Background = B '#0E1A21'; $mapWrap.BorderBrush = Res 'Rule'; $mapWrap.BorderThickness = '1'; $mapWrap.CornerRadius = '3'
    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $W; $cv.Height = $H; $cv.ClipToBounds = $true
    $mapWrap.Child = $cv

    # stylised coastline, enough to read as the map on the ops-room table
    $coast = @(
        @(-4.7,53.2),@(-4.1,52.9),@(-4.1,52.55),@(-4.8,52.3),@(-5.3,51.9),@(-4.9,51.62),@(-4.3,51.56),
        @(-3.9,51.62),@(-3.1,51.5),@(-2.6,51.6),@(-3.0,51.22),@(-3.6,51.22),@(-4.2,51.2),@(-4.6,50.93),
        @(-5.7,50.05),@(-5.0,49.97),@(-4.2,50.3),@(-3.5,50.38),@(-3.0,50.7),@(-2.4,50.6),@(-1.9,50.6),
        @(-1.3,50.75),@(-0.9,50.78),@(-0.2,50.76),@(0.3,50.77),@(0.98,50.92),@(1.4,51.1),@(1.45,51.38),
        @(0.9,51.36),@(0.5,51.48),@(0.7,51.53),@(0.95,51.62),@(1.3,51.95),@(1.63,52.1),@(1.75,52.48),
        @(1.65,52.75),@(1.3,52.96),@(0.5,52.97),@(0.2,52.82),@(0.05,52.9),@(0.35,53.06),@(0.15,53.4),@(0.0,53.63)
    )
    $pl = New-Object Windows.Shapes.Polyline
    $pl.Stroke = B '#3F5D52'; $pl.StrokeThickness = 2
    foreach ($pt in $coast) {
        $xy = Map-XY $pt[0] $pt[1] $W $H
        $pl.Points.Add((New-Object Windows.Point($xy[0], $xy[1])))
    }
    [void]$cv.Children.Add($pl)
    # the French coast, faint
    $fr = New-Object Windows.Shapes.Polyline
    $fr.Stroke = B '#4A3A34'; $fr.StrokeThickness = 1.5
    foreach ($pt in @(@(1.9,51.05),@(1.6,50.9),@(1.2,50.75),@(0.6,49.85),@(0.2,49.7),@(-0.8,49.6),@(-1.5,49.66),@(-1.9,49.72))) {
        $xy = Map-XY $pt[0] $pt[1] $W $H
        $fr.Points.Add((New-Object Windows.Point($xy[0], $xy[1])))
    }
    [void]$cv.Children.Add($fr)

    $script:SelSq = $null
    $script:SqDots = @()
    $detail = New-TB -Text 'No squadron selected.' -Family 'Segoe UI' -Size 14 -Colour '#9FB0B8' -Wrap
    $btn = New-Object Windows.Controls.Button
    $btn.Content = 'REPORT TO THIS SQUADRON'; $btn.IsEnabled = $false; $btn.MinWidth = 240

    foreach ($q in $Squadrons) {
        $xy = Map-XY ([double]$q.Lon) ([double]$q.Lat) $W $H
        $isSpit = ("$($q.Type)" -match 'Spitfire')
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width = 13; $dot.Height = 13; $dot.StrokeThickness = 2
        $dot.Stroke = B '#0E1A21'
        $dot.Fill = if ($isSpit) { B '#C8973F' } else { B '#8FB56A' }
        [Windows.Controls.Canvas]::SetLeft($dot, $xy[0]-6.5); [Windows.Controls.Canvas]::SetTop($dot, $xy[1]-6.5)
        $dot.Cursor = 'Hand'; $dot.Tag = $q
        $lbl = New-TB -Text "$($q.Num)" -Family $CondFam -Size 12 -Colour '#C9D4CE' -Bold
        [Windows.Controls.Canvas]::SetLeft($lbl, $xy[0] + [double]$q.Lx); [Windows.Controls.Canvas]::SetTop($lbl, $xy[1] + [double]$q.Ly)
        $lbl.Cursor = 'Hand'; $lbl.Tag = $q
        $sel = {
            param($sender,$e)
            $q2 = $sender.Tag
            $script:SelSq = $q2
            foreach ($d in $script:SqDots) {
                $isS = ("$($d.Tag.Type)" -match 'Spitfire')
                $d.Fill = if ($isS) { B '#C8973F' } else { B '#8FB56A' }
                $d.Width = 13; $d.Height = 13
            }
            foreach ($d in $script:SqDots) {
                if ($d.Tag.Num -eq $q2.Num) { $d.Fill = B '#E8394F'; $d.Width = 17; $d.Height = 17 }
            }
            $script:SqDetail.Text = "No. $($q2.Num) Squadron  $([char]0x2022)  $($q2.Type)  $([char]0x2022)  $($q2.Base)  $([char]0x2022)  No. $($q2.Grp) Group   (codes $($q2.Code)-)"
            $script:SqButton.IsEnabled = $true
        }
        $dot.Add_MouseLeftButtonUp($sel)
        $lbl.Add_MouseLeftButtonUp($sel)
        $script:SqDots += $dot
        [void]$cv.Children.Add($dot)
        [void]$cv.Children.Add($lbl)
    }
    $script:SqDetail = $detail
    $script:SqButton = $btn
    [void]$script:Stage.Children.Add($mapWrap)

    $legend = New-TB -Text "$([char]0x25CF) Spitfire squadrons (gold)    $([char]0x25CF) Hurricane squadrons (green)" -Family $CondFam -Size 12 -Colour '#6F828C'
    $legend.Margin = '2,8,0,14'
    [void]$script:Stage.Children.Add($legend)
    $detail.Margin = '2,0,0,14'
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
    $lead = New-TB -Text 'Summer 1940. Give your name, take a letter, and pick your photograph from the wall.' -Family 'Segoe UI' -Size 14.5 -Colour '#9FB0B8' -Wrap
    $lead.Margin = '0,-14,0,22'
    [void]$script:Stage.Children.Add($lead)

    # form row
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,0,0,26'

    $nameCol = New-Object Windows.Controls.StackPanel; $nameCol.Margin = '0,0,36,0'
    [void]$nameCol.Children.Add((New-TB -Text 'NAME' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $script:NameBox = New-Object Windows.Controls.TextBox
    $script:NameBox.Width = 320; $script:NameBox.Margin = '0,7,0,0'; $script:NameBox.MaxLength = 40
    [void]$nameCol.Children.Add($script:NameBox)
    [void]$row.Children.Add($nameCol)

    $letCol = New-Object Windows.Controls.StackPanel; $letCol.Margin = '0,0,36,0'
    [void]$letCol.Children.Add((New-TB -Text 'LETTER' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $letWrap = New-Object Windows.Controls.StackPanel; $letWrap.Orientation = 'Horizontal'; $letWrap.Margin = '0,7,0,0'
    $qj = New-TB -Text "$($script:SelSq.Code)-" -Family 'Georgia, serif' -Size 18 -Colour '#9FB0B8'; $qj.VerticalAlignment = 'Bottom'; $qj.Margin = '0,0,4,6'
    [void]$letWrap.Children.Add($qj)
    $script:LetBox = New-Object Windows.Controls.TextBox
    $script:LetBox.Width = 52; $script:LetBox.MaxLength = 1; $script:LetBox.TextAlignment = 'Center'; $script:LetBox.CharacterCasing = 'Upper'
    [void]$letWrap.Children.Add($script:LetBox)
    [void]$letCol.Children.Add($letWrap)
    [void]$row.Children.Add($letCol)

    $rankCol = New-Object Windows.Controls.StackPanel
    [void]$rankCol.Children.Add((New-TB -Text 'RANK' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $rankWrap = New-Object Windows.Controls.StackPanel; $rankWrap.Orientation = 'Horizontal'; $rankWrap.Margin = '0,12,0,0'
    $script:RbSgt = New-Object Windows.Controls.RadioButton
    $script:RbSgt.Content = 'Sergeant'; $script:RbSgt.IsChecked = $true; $script:RbSgt.Margin = '0,0,20,0'; $script:RbSgt.GroupName = 'rank'
    $script:RbPO = New-Object Windows.Controls.RadioButton
    $script:RbPO.Content = 'Pilot Officer'; $script:RbPO.GroupName = 'rank'
    [void]$rankWrap.Children.Add($script:RbSgt); [void]$rankWrap.Children.Add($script:RbPO)
    [void]$rankCol.Children.Add($rankWrap)
    [void]$row.Children.Add($rankCol)

    $modeCol = New-Object Windows.Controls.StackPanel; $modeCol.Margin = '36,0,0,0'
    [void]$modeCol.Children.Add((New-TB -Text 'CAREER' -Family $CondFam -Size 12 -Colour '#C8973F' -Bold))
    $modeWrap = New-Object Windows.Controls.StackPanel; $modeWrap.Orientation = 'Horizontal'; $modeWrap.Margin = '0,12,0,0'
    $script:RbFly = New-Object Windows.Controls.RadioButton
    $script:RbFly.Content = 'Squadron pilot'; $script:RbFly.IsChecked = $true; $script:RbFly.Margin = '0,0,20,0'; $script:RbFly.GroupName = 'mode'
    $script:RbCmd = New-Object Windows.Controls.RadioButton
    $script:RbCmd.Content = 'Squadron commander'; $script:RbCmd.GroupName = 'mode'
    [void]$modeWrap.Children.Add($script:RbFly); [void]$modeWrap.Children.Add($script:RbCmd)
    [void]$modeCol.Children.Add($modeWrap)
    [void]$row.Children.Add($modeCol)
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
    $script:LetBox.Add_TextChanged({ Update-CreateValid })
    $script:SubmitBtn.Add_Click({ Invoke-Submit })
}

# =====================================================================
Finalize-Flight
$existing = Get-Pilot
if ($existing) { Show-Roster -Pilot $existing } else { Show-SquadronSelect }
[void]$Win.ShowDialog()
