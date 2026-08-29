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
                     Foreground="{StaticResource Ink}" Text="No. 92 Squadron"/>
          <TextBlock Style="{StaticResource Cond}" FontSize="13" Foreground="{StaticResource Faint}"
                     Text="ROYAL AIR FORCE  &#x2022;  AUT PUGNA AUT MORERE" Margin="1,3,0,0"/>
        </StackPanel>
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
function New-Aircraft {
    param($Pilot)
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
    param($P,[switch]$Header,[int]$Index=0)
    $b = New-Object Windows.Controls.Border
    $b.Padding = '18,10,18,10'; $b.BorderThickness = '0,0,0,1'; $b.BorderBrush = Res 'Rule'
    if ($Header) { $b.Background = B '#101B22' }
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

        $vic = Accrue-Victories $P $script:CampaignDate
        Add-Cell $g $vic 1 $CondFam 16 '#D9B45A' -Center -Bold
        $aw = Get-Awards $P $script:CampaignDate
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
    $sess = [ordered]@{
        end        = $end.ToString('s')
        minutes    = $mins
        dateBefore = "$($mk.dateBefore)"
        dateAfter  = if ($after) { $after.ToString('yyyy-MM-dd') } else { "$($mk.dateBefore)" }
        mode       = if ($mk.dateBefore) { 'campaign' } else { 'instant' }
    }
    Save-Sessions (@(Get-Sessions) + $sess)
    Remove-Item $FlightOpen -Force -ErrorAction SilentlyContinue
}

function Get-Career {
    param($Pilot, $Sessions)
    $sorties = @($Sessions).Count
    $mins = 0; foreach ($s in $Sessions) { $mins += [int]$s.minutes }
    $hours = [math]::Round($mins / 60.0, 1)
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
function Get-PlayerAwards {
    param($Pilot)
    if (($Pilot.PSObject.Properties.Name -contains 'awards') -and $Pilot.awards) { return "$($Pilot.awards)" }
    $v = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $v = [int]$Pilot.victories }
    if ($v -ge 5) { return 'DFC' }
    'None yet'
}
# Player-entered victory (auto claims from the game are Tier 4, still ahead).
function Add-Claim {
    param($Pilot)
    $v = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $v = [int]$Pilot.victories }
    $claims = @(); if (($Pilot.PSObject.Properties.Name -contains 'claims') -and $Pilot.claims) { $claims = @($Pilot.claims) }
    $cd = Get-CampaignDate; $when = if ($cd) { $cd.ToString('yyyy-MM-dd') } else { (Get-Date).ToString('yyyy-MM-dd') }
    $obj = [ordered]@{}
    foreach ($p in $Pilot.PSObject.Properties) { $obj[$p.Name] = $p.Value }
    $obj['victories'] = $v + 1
    $obj['claims'] = @($claims + $when)
    Save-Pilot $obj
    Show-Logbook -Pilot (Get-Pilot)
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
    foreach ($t in @(@{k='dispersal';l='THE DISPERSAL'}, @{k='logbook';l="PILOT'S LOGBOOK"}, @{k='paper';l='MORNING BULLETIN'})) {
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
            switch ($s.Tag) {
                'logbook' { Show-Logbook -Pilot $pl }
                'paper'   { Show-Paper -Pilot $pl }
                default   { Show-Roster -Pilot $pl }
            }
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
    foreach ($w in @('*','170','*')) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)) }
        else { $cd.Width = New-Object Windows.GridLength([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    if ($Header) {
        Add-Cell $g 'FLOWN'        0 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'FLIGHT TIME'  1 $CondFam 12 '#C8973F' -Bold
        Add-Cell $g 'CAMPAIGN DAY' 2 $CondFam 12 '#C8973F' -Bold
    } else {
        $flown = "$($S.end)"; try { $flown = ([datetime]$S.end).ToString('ddd d MMM, HH:mm') } catch { }
        Add-Cell $g $flown 0 $CondFam 13.5 '#E9E3D4'
        $mins = [int]$S.minutes
        $ft = if ($mins -ge 60) { '{0}h {1:00}m' -f [int]($mins/60), ($mins%60) } else { "$mins min" }
        Add-Cell $g $ft 1 $CondFam 13.5 '#9FB0B8'
        $day = "$($S.dateAfter)"; if ((-not $day) -or ($S.mode -eq 'instant')) { $day = 'Instant Action' }
        Add-Cell $g $day 2 $CondFam 13.5 '#9FB0B8'
    }
    $b.Child = $g; $b
}
function Show-Logbook {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'logbook'))
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow "PILOT'S LOGBOOK" -Title ("$($Pilot.pilot)")))

    $sessions = Get-Sessions
    $career = Get-Career $Pilot $sessions
    $vics = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $vics = [int]$Pilot.victories }

    $tiles = New-Object Windows.Controls.StackPanel; $tiles.Orientation = 'Horizontal'; $tiles.Margin = '0,-6,0,12'
    [void]$tiles.Children.Add((New-Stat 'SORTIES' "$($career.sorties)"))
    [void]$tiles.Children.Add((New-Stat 'FLYING HOURS' "$($career.hours)"))
    [void]$tiles.Children.Add((New-Stat 'VICTORIES' "$vics"))
    [void]$tiles.Children.Add((New-Stat 'AWARDS' (Get-PlayerAwards $Pilot)))
    [void]$tiles.Children.Add((New-Stat 'RANK' "$($career.rank)"))
    [void]$script:Stage.Children.Add($tiles)

    $pn = if ($career.next) { "Next promotion to $($career.next) at $($career.nextAt) sorties." } else { 'At the top of the tree.' }
    $pnt = New-TB -Text $pn -Family 'Segoe UI' -Size 13 -Colour '#6F828C'; $pnt.Margin = '0,2,0,18'
    [void]$script:Stage.Children.Add($pnt)

    $claimRow = New-Object Windows.Controls.StackPanel; $claimRow.Orientation = 'Horizontal'; $claimRow.Margin = '0,0,0,22'
    $cbtn = New-Object Windows.Controls.Button; $cbtn.Content = 'LOG A CLAIM'; $cbtn.MinWidth = 130
    $cbtn.Add_Click({ Add-Claim -Pilot (Get-Pilot) })
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

# =====================================================================
#  Phase 3: the Morning Bulletin (news by campaign date)
# =====================================================================
$PaperPath = Join-Path $ModDir 'paper.json'
function Get-Paper {
    # The comma keeps the array intact through the function return, so the
    # caller gets 18 entries, not a single wrapped object whose members then
    # enumerate into one mashed string.
    $out = @()
    if (Test-Path $PaperPath) { try { $out = @(Get-Content $PaperPath -Raw | ConvertFrom-Json) } catch { $out = @() } }
    ,$out
}
function Format-ShortDate {
    param([string]$s)
    try { return ([datetime]::ParseExact($s,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)).ToString('d MMM') } catch { return $s }
}
function New-Rule {
    param([string]$Colour = '#221E15', [double]$H = 1.5)
    $r = New-Object Windows.Controls.Border
    $r.Height = $H; $r.Background = B $Colour; $r.Margin = '0,10,0,10'
    $r
}
function Show-Paper {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'paper'))

    $entries = @(Get-Paper)
    if ($entries.Count -eq 1 -and ($entries[0] -isnot [System.Management.Automation.PSCustomObject])) { $entries = @($entries[0]) }

    $leadIdx = -1
    if ($script:CampaignDate) {
        for ($k = 0; $k -lt $entries.Count; $k++) {
            $ed = $null
            try { $ed = [datetime]::ParseExact($entries[$k].date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture) } catch { }
            if ($ed -and ($ed -le $script:CampaignDate)) { $leadIdx = $k }
        }
    }
    if (($leadIdx -lt 0) -and $entries.Count) { $leadIdx = $entries.Count - 1 }

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

    $base = if ($script:CampaignDate) { Get-Airfield $script:CampaignDate } else { $null }
    $centTxt = if ($base) { $base.ToUpper() } else { 'FIGHTER COMMAND' }
    $dstr = if ($script:CampaignDate) { $script:CampaignDate.ToString('dddd, d MMMM yyyy').ToUpper() } else { 'THE BATTLE OF BRITAIN, 1940' }
    $dl = New-Object Windows.Controls.Grid; $dl.Margin = '0,5,0,5'
    foreach ($w in @('*','*','*')) { $cd=New-Object Windows.Controls.ColumnDefinition; $cd.Width=New-Object Windows.GridLength(1,([Windows.GridUnitType]::Star)); [void]$dl.ColumnDefinitions.Add($cd) }
    $dLeft  = New-TB -Text 'No. 92 Squadron R.A.F.' -Family $CondFam -Size 11.5 -Colour '#4A4436' -Bold; $dLeft.VerticalAlignment='Center'
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
    if ($leadIdx -ge 0 -and $entries.Count) {
        $lead = $entries[$leadIdx]
        $hl = New-TB -Text ([string]$lead.headline) -Family 'Georgia, Cambria, serif' -Size 31 -Colour '#120F08' -Bold -Wrap
        $hl.LineHeight = 34
        [void]$lc.Children.Add($hl)
        [void]$lc.Children.Add((New-Rule '#7A5E2E' 1))
        $bd = New-TB -Text ([string]$lead.body) -Family 'Georgia, Cambria, serif' -Size 15 -Colour '#2A2620' -Wrap
        $bd.LineHeight = 24; $bd.Margin = '0,8,0,0'; $bd.TextAlignment = 'Justify'
        [void]$lc.Children.Add($bd)
    }
    [Windows.Controls.Grid]::SetColumn($lc,0); [void]$bodyG.Children.Add($lc)

    $vr = New-Object Windows.Controls.Border; $vr.Width=1; $vr.Background=B '#3A3324'; $vr.HorizontalAlignment='Center'
    [Windows.Controls.Grid]::SetColumn($vr,1); [void]$bodyG.Children.Add($vr)

    $sc = New-Object Windows.Controls.StackPanel
    [void]$sc.Children.Add((New-TB -Text 'LATEST SIGNALS' -Family $CondFam -Size 12 -Colour '#7A5E2E' -Bold))
    [void]$sc.Children.Add((New-Rule '#7A5E2E' 1))
    $shown = 0
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

function Show-Roster {
    param($Pilot)
    $script:Stage.Children.Clear()
    $script:CampaignDate = Get-CampaignDate
    [void]$script:Stage.Children.Add((New-Nav 'dispersal'))
    $eyebrow = if ($script:CampaignDate) {
        "$((Get-Airfield $script:CampaignDate).ToUpper())  $([char]0x2022)  $($script:CampaignDate.ToString('dddd d MMMM yyyy').ToUpper())"
    } else { 'THE DISPERSAL' }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow $eyebrow -Title 'No. 92 Squadron at readiness'))

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
    $i = 0
    foreach ($h in (Get-Historical)) { [void]$ls.Children.Add((New-RosterRow -P $h -Index $i)); $i++ }
    $listWrap.Child = $ls
    [void]$script:Stage.Children.Add($listWrap)
}

function Update-CreateValid {
    $ok = ($script:NameBox.Text.Trim().Length -ge 2) -and `
          ($script:LetBox.Text.Trim().Length -eq 1) -and `
          ($null -ne $script:SelPortrait)
    $script:SubmitBtn.IsEnabled = $ok
}
function Invoke-Submit {
    $rank = if ($script:RbPO.IsChecked) { 'Pilot Officer' } else { 'Sergeant' }
    $serial = New-Serial   # period-correct Spitfire I/II serial
    $pilot = [ordered]@{
        pilot   = $script:NameBox.Text.Trim()
        rank    = $rank
        codes   = "QJ-$($script:LetBox.Text.Trim().ToUpper())"
        status  = 'On strength'
        serials = $serial
        note    = 'Posted to No. 92 Squadron.'
        historical = $false
        portrait = $script:SelPortrait
        created = (Get-Date).ToString('yyyy-MM-dd')
    }
    Save-Pilot -Pilot $pilot
    Show-Roster -Pilot (Get-Pilot)
}

function Show-Create {
    $script:Stage.Children.Clear()
    $script:SelPortrait = $null; $script:SelBorder = $null
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow 'REPORT TO THE ADJUTANT' -Title 'A new pilot for No. 92'))
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
    $qj = New-TB -Text 'QJ-' -Family 'Georgia, serif' -Size 18 -Colour '#9FB0B8'; $qj.VerticalAlignment = 'Bottom'; $qj.Margin = '0,0,4,6'
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
if ($existing) { Show-Roster -Pilot $existing } else { Show-Create }
[void]$Win.ShowDialog()
