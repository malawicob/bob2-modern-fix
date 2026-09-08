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
$PortraitDir = Join-Path $ModDir 'portraits'
$PortIndex   = Join-Path $ModDir 'portraits.json'
$BadgeDir    = Join-Path $ModDir 'badges'

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

# --- squadrons a new pilot may join --------------------------------------
# Postings are PER CAMPAIGN PERIOD: P1 = the Channel battles (10 Jul),
# P2 = Eagle Day and the airfields (13 Aug), P3 = London (7 Sep).
# Each period entry is 'Station,ActionRating' or '-' when the squadron is
# resting in the north. Station anchors are image fractions on the table.
$MapStations = @{
    'RAF Duxford'       = @(0.565, 0.075)
    'RAF Debden'        = @(0.624, 0.210)
    'RAF North Weald'   = @(0.570, 0.288)
    'RAF Rochford'      = @(0.694, 0.381)
    'RAF Hornchurch'    = @(0.599, 0.396)
    'RAF Northolt'      = @(0.449, 0.349)
    'RAF Croydon'       = @(0.518, 0.487)
    'RAF Kenley'        = @(0.525, 0.542)
    'RAF Biggin Hill'   = @(0.553, 0.547)
    'RAF Gravesend'     = @(0.624, 0.459)
    'RAF Tangmere'      = @(0.426, 0.742)
    'RAF Middle Wallop' = @(0.258, 0.601)
    'RAF Warmwell'      = @(0.134, 0.737)
    # The thirteen above were placed by hand on the map image. The rest are
    # placed from their real latitude and longitude, through a straight-line
    # fit of those thirteen (x = 0.1832*lon + 0.5501, y = -0.4813*lat +
    # 25.2022; worst residual 0.06 of the image width). Six of the order of
    # battle's stations fall outside the table altogether and are listed as
    # off-table postings instead, which is what the map already does for a
    # squadron resting in the north.
    'RAF Colerne'       = @(0.132, 0.442)
    'RAF Fowlmere'      = @(0.559, 0.133)
    'RAF Hawkinge'      = @(0.762, 0.598)
    'RAF Martlesham'    = @(0.785, 0.145)
    'RAF Stapleford'    = @(0.579, 0.339)
    'RAF West Malling'  = @(0.624, 0.522)
    'RAF Westhampnett'  = @(0.411, 0.721)
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
        $all = @(Get-Content $OobPath -Raw | ConvertFrom-Json)
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
    if (Test-Path $PortIndex) { try { return @(Get-Content $PortIndex -Raw | ConvertFrom-Json) } catch { } }
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
        $men = @(Get-Content $path -Raw | ConvertFrom-Json)
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
        $all = @(Get-Content $OobPath -Raw | ConvertFrom-Json)
        while ($all.Count -eq 1 -and ($all[0] -is [System.Array])) { $all = $all[0] }
        foreach ($o in $all) { if ([int]$o.num -eq $Sqn) { return $o } }
    } catch { }
    $null
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
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,84,0">
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
    if (-not $pl) { Show-SquadronSelect; return }
    switch ($Tab) {
        'logbook' { Show-Logbook -Pilot $pl }
        'map'     { Show-Map -Pilot $pl }
        'paper'   { Show-Paper -Pilot $pl }
        default   { Show-Roster -Pilot $pl }
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
function New-RibbonRow {
    param($Honours, [double]$Height = 15)
    $set = @($Honours)
    $items = @()
    if ($set -contains 'VC')  { $items += @{ f='ribbon-vc.png';  t='Victoria Cross' } }
    if ($set -contains 'DSO') { $items += @{ f='ribbon-dso.png'; t='Distinguished Service Order' } }
    if ($set -contains 'Bar to DFC')     { $items += @{ f='ribbon-dfc-bar.png'; t='Distinguished Flying Cross and Bar' } }
    elseif ($set -contains 'DFC')        { $items += @{ f='ribbon-dfc.png';     t='Distinguished Flying Cross' } }
    if ($set -contains 'Bar to DFM')     { $items += @{ f='ribbon-dfm-bar.png'; t='Distinguished Flying Medal and Bar' } }
    elseif ($set -contains 'DFM')        { $items += @{ f='ribbon-dfm.png';     t='Distinguished Flying Medal' } }
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
function Get-AircraftSpec { param([string]$Type)
    if ($Type -match 'Hurricane') {
        return @{ Img='hurricane.png'; Ratio=(300.0/1000.0); SqX=0.4118; SqY=0.3474; IndX=0.6313; IndY=0.3532; SerX=0.7182; SerTy=0.4750; CodeSize=78.0; SerSize=46.0 }
    }
    @{ Img='spitfire.png'; Ratio=(324.0/1000.0); SqX=0.4194; SqY=0.3461; IndX=0.6727; IndY=0.3326; SerX=0.7443; SerTy=0.4487; CodeSize=84.0; SerSize=32.0 }
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
function Set-Header {
    param($Pilot)
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
        return @{ sorties = $sorties; hours = $hours; rank = 'Squadron Leader'; next = $null; nextAt = 0 }
    }
    $ladder = $RankLadder
    # The stored rank is a FLOOR, not a starting point: a man promoted at
    # twelve sorties keeps his rank even if a new campaign resets the count.
    $idx = [array]::IndexOf($ladder, "$($Pilot.rank)"); if ($idx -lt 0) { $idx = 0 }
    $step = 12
    $promos = [math]::Floor($sorties / $step)
    $curIdx = [math]::Min($ladder.Count - 1, [math]::Max($idx, $promos))
    $next = $null; $nextAt = 0
    if ($curIdx -lt $ladder.Count - 1) { $next = $ladder[$curIdx + 1]; $nextAt = ($promos + 1) * $step }
    @{ sorties = $sorties; hours = $hours; rank = $ladder[$curIdx]; next = $next; nextAt = $nextAt }
}
# Rank and decorations are PERSISTED the first time they are earned, with
# the date, and never taken away. Without this a pilot who starts a fresh
# campaign in the game drops from Flight Lieutenant back to Sergeant, and
# his DFC silently becomes a DFM, because both were recomputed from the
# sortie count every time the screen was drawn.
$RankLadder = @('Sergeant','Pilot Officer','Flying Officer','Flight Lieutenant')
function Update-CareerRecord {
    param($Pilot, $Career, $Honours)
    if (-not $Pilot -or -not $Career) { return $Pilot }
    $changed = $false
    $obj = [ordered]@{}
    foreach ($pp in $Pilot.PSObject.Properties) { $obj[$pp.Name] = $pp.Value }
    $storedIdx = [array]::IndexOf($RankLadder, "$($Pilot.rank)")
    $earnedIdx = [array]::IndexOf($RankLadder, "$($Career.rank)")
    if ($earnedIdx -gt $storedIdx) {
        $obj['rank'] = $RankLadder[$earnedIdx]
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
function Get-PlayerHonours {
    param($Pilot, $Career)
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
    if (($Pilot.PSObject.Properties.Name -contains 'awards') -and $Pilot.awards -and ($h -notcontains "$($Pilot.awards)")) { $h = @("$($Pilot.awards)") + $h }
    # no comma return: every caller collects with @(...), and comma + @()
    # double-wraps into the System.Object[] display bug
    $h
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
$AutoClaimPath   = Join-Path $StateDir 'autoclaim.json'
$DiaryRowSize    = 25
$DiaryTableGuess = 99047
$DiaryMaxRows    = 200
# STATISTICS_TYPE bins for what an RAF pilot shoots down, and for a
# Luftwaffe pilot (the last three of those are dummies in the game).
$KillBinsRAF = @('Bf 109E','Bf 110','Ju 87','Do 17','Ju 88','He 111','He 59')
$KillBinsLW  = @('Spitfire','Hurricane','Defiant','Blenheim','Other','Other','Other')
function Get-AutoClaim {
    if (Test-Path $AutoClaimPath) {
        try { return (Get-Content $AutoClaimPath -Raw | ConvertFrom-Json) } catch { }
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
# The newest campaign save's Log Book, for the logbook screen.
function Get-LatestSaveDiary {
    if (-not $GameDir) { return $null }
    $sav = Get-ChildItem (Join-Path $GameDir 'SAVEGAME') -Filter '*.BSR' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $sav) { return $null }
    Get-SaveDiary -Path $sav.FullName
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
    $bins = $KillBinsRAF
    if (($p.PSObject.Properties.Name -contains 'side') -and ("$($p.side)" -match '^(lw|luftwaffe|german)')) { $bins = $KillBinsLW }
    $newTypes = @()
    if (-not $lower) {
        for ($k = 0; $k -lt 7; $k++) {
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
    foreach ($t in @(@{k='dispersal';l='THE DISPERSAL'}, @{k='logbook';l="PILOT'S LOGBOOK"}, @{k='map';l='MAP'}, @{k='paper';l='MORNING BULLETIN'})) {
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
    Show-SquadronSelect
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
        for ($k = 0; $k -lt 7; $k++) { if ([int]$R.kills[$k] -gt 0) { $parts += "$([int]$R.kills[$k]) x $($Bins[$k])" } }
        $cl = if ($parts.Count) { $parts -join ', ' } else { [string][char]0x2014 }
        Add-Cell $g $cl 2 $CondFam 13.5 $(if ($parts.Count) { '#E9E3D4' } else { '#6F828C' })
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
    # The campaign's own Log Book is the record of sorties when it can be
    # read; the launcher's timed sessions only supply the flying hours.
    # Level the record with it first, so victories scored in a game started
    # any way at all are in before the tiles are drawn.
    $ld = Sync-CampaignClaims
    $p2 = Get-Pilot; if ($p2) { $Pilot = $p2 }
    $career = Get-Career $Pilot $sessions -Sorties (Get-SortieCount -Diary $ld -Sessions $sessions -Pilot $Pilot)
    $vics = 0; if (($Pilot.PSObject.Properties.Name -contains 'victories') -and $Pilot.victories) { $vics = [int]$Pilot.victories }

    $tiles = New-Object Windows.Controls.StackPanel; $tiles.Orientation = 'Horizontal'; $tiles.Margin = '0,-6,0,12'
    [void]$tiles.Children.Add((New-Stat 'SORTIES' "$($career.sorties)"))
    [void]$tiles.Children.Add((New-Stat 'FLYING HOURS' "$($career.hours)"))
    [void]$tiles.Children.Add((New-Stat 'VICTORIES' "$vics"))
    $honours = @(Get-PlayerHonours $Pilot $career)
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
    $binsL = $KillBinsRAF
    if (($Pilot.PSObject.Properties.Name -contains 'side') -and ("$($Pilot.side)" -match '^(lw|luftwaffe|german)')) { $binsL = $KillBinsLW }
    if ($ld) {
        $byType = @()
        for ($k = 0; $k -lt 7; $k++) { if ([int]$ld.kills[$k] -gt 0) { $byType += "$([int]$ld.kills[$k]) x $($binsL[$k])" } }
        $acTxt = "Automatic claims are on: the campaign's Log Book credits you with " +
                 $(if ([int]$ld.total -eq 1) { 'one victory' } elseif ([int]$ld.total -eq 0) { 'no victories yet' } else { "$([int]$ld.total) victories" }) +
                 $(if ($byType.Count) { ', ' + ($byType -join ', ') } else { '' }) +
                 ". Every victory the campaign credits you with is entered here by itself, whichever way the game was started."
    } elseif ($ld) {
        $acTxt = "Automatic claims are on. The campaign's Log Book has no sorties in it yet; fly one and it appears here by itself."
    } else {
        $acTxt = 'Automatic claims are on, but no campaign save could be read yet. Victories the campaign credits you with are entered here by themselves once there is one.'
    }
    $lk = New-TB -Text $acTxt -Family 'Segoe UI' -Size 12.5 -Colour '#9FB0B8' -Wrap
    $lk.Margin = '0,0,0,22'; $lk.MaxWidth = 860; $lk.HorizontalAlignment = 'Left'
    [void]$script:Stage.Children.Add($lk)

    [void]$script:Stage.Children.Add((New-TB -Text 'SORTIES FLOWN' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
    if ($ld -and @($ld.rows).Count -gt 0) {
        # the game's own Log Book, newest first
        $lw = New-Object Windows.Controls.Border; $lw.BorderBrush = Res 'Rule'; $lw.BorderThickness = '1'; $lw.CornerRadius = '3'; $lw.Margin = '0,10,0,0'; $lw.ClipToBounds = $true
        $ls = New-Object Windows.Controls.StackPanel
        [void]$ls.Children.Add((New-DiaryRow -Header))
        $arr = @($ld.rows); $i = 0
        for ($k = $arr.Count - 1; $k -ge 0; $k--) {
            $num = if ($arr[$k].PSObject.Properties.Name -contains 'slot') { [int]$arr[$k].slot } else { $k + 1 }
            [void]$ls.Children.Add((New-DiaryRow -R $arr[$k] -Number $num -Index $i -Bins $binsL)); $i++
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
    } elseif (@($sessions).Count -eq 0) {
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
    # Every screen counts sorties from the same place: the campaign's own
    # Log Book. The dispersal used to count the launcher's timed sessions,
    # so the hero card and the roster row could disagree about your rank.
    $ld0 = Get-LatestSaveDiary
    $sessions0 = Get-Sessions
    $flownCount = Get-SortieCount -Diary $ld0 -Sessions $sessions0 -Pilot $Pilot
    $career0 = Get-Career $Pilot $sessions0 -Sorties $flownCount
    $ph0 = @(Get-PlayerHonours $Pilot $career0)
    $Pilot = Update-CareerRecord -Pilot $Pilot -Career $career0 -Honours $ph0
    $bs = Get-SquadronBase -Sqn $sqnum -Date $script:CampaignDate -Pilot $Pilot
    $baseTxt = if ($bs) { $bs.ToUpper() } else { 'THE DISPERSAL' }
    $eyebrow = if ($script:CampaignDate) { "$baseTxt  $([char]0x2022)  $($script:CampaignDate.ToString('dddd d MMMM yyyy').ToUpper())" } else { $baseTxt }
    [void]$script:Stage.Children.Add((New-Heading -Eyebrow $eyebrow -Title "No. $sqnum Squadron at readiness"))

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
    $heroHon = @(Get-PlayerHonours $Pilot (Get-Career $Pilot @(Get-Sessions)))
    $heroRib = New-RibbonRow $heroHon
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
    }

    # the squadron as a records book: names, victories, fate
    [void]$script:Stage.Children.Add((New-TB -Text 'THE SQUADRON' -Family $CondFam -Size 12.5 -Colour '#C8973F' -Bold))
    $men = @(Get-Historical -Sqn $sqnum)
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
    foreach ($h in $onStrength) { [void]$ls.Children.Add((New-RosterRow -P $h -Index $i)); $i++ }
    $listWrap.Child = $ls
    [void]$script:Stage.Children.Add($listWrap)

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

function Update-CreateValid {
    $ok = ($script:NameBox.Text.Trim().Length -ge 2) -and ($null -ne $script:SelPortrait)
    $script:SubmitBtn.IsEnabled = $ok
}
function Invoke-Submit {
    Complete-NewCareer
    $isCmdr = $false
    $rank = 'Sergeant'
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
    Save-Pilot -Pilot $pilot
    Show-Roster -Pilot (Get-Pilot)
}

# =====================================================================
#  The map: the plotting table with your own station ringed
# =====================================================================
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
    $leadTxt = if ($onTable) { "No. $(Get-GroupForBase $base) Group, Fighter Command. Your station today is ringed on the table." }
               else { "No. $(Get-GroupForBase $base) Group, Fighter Command. $base lies beyond the edge of this table." }
    $lead = New-TB -Text $leadTxt -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Wrap
    $lead.Margin = '0,0,0,12'
    [void]$script:Stage.Children.Add($lead)

    $W = 1080.0; $H = [math]::Round($W * 800.0 / 1600.0)
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

    if ($onTable) {
        $st = $MapStations[$base]
        $cx = [double]$st[0] * $W; $cy = [double]$st[1] * $H
        # honour a hand-corrected ring anchor from the plotting table
        $rpPath = Join-Path $StateDir 'ringpos.json'
        if (Test-Path $rpPath) {
            try {
                $rp = Get-Content $rpPath -Raw | ConvertFrom-Json
                $ovp = $rp.PSObject.Properties["$base|$sqnum"]
                if ($ovp -and $ovp.Value) { $cx = [double]$ovp.Value.x * $W; $cy = [double]$ovp.Value.y * $H }
            } catch { }
        }
        # a breathing gold halo round the station, a firm ring inside it
        $halo = New-Object Windows.Shapes.Ellipse
        $halo.Width = 64; $halo.Height = 64; $halo.StrokeThickness = 3
        $halo.Stroke = B '#FFE28A'; $halo.Fill = B '#22FFE28A'
        [Windows.Controls.Canvas]::SetLeft($halo, $cx - 32); [Windows.Controls.Canvas]::SetTop($halo, $cy - 32)
        $pulse = New-Object Windows.Media.Animation.DoubleAnimation(0.25, 0.95, [Windows.Duration]::new([TimeSpan]::FromSeconds(1.1)))
        $pulse.AutoReverse = $true
        $pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $halo.BeginAnimation([Windows.UIElement]::OpacityProperty, $pulse)
        [void]$cv.Children.Add($halo)
        $ring = New-Object Windows.Shapes.Ellipse
        $ring.Width = 30; $ring.Height = 30; $ring.StrokeThickness = 3.5
        $ring.Stroke = B '#FFE28A'; $ring.Fill = B '#01000000'
        [Windows.Controls.Canvas]::SetLeft($ring, $cx - 15); [Windows.Controls.Canvas]::SetTop($ring, $cy - 15)
        [void]$cv.Children.Add($ring)
        # no caption: the station's name is already printed on the map,
        # and the rings' open centres leave it readable
    }
    [void]$script:Stage.Children.Add($mapWrap)

    if (-not $onTable) {
        $chip = New-Object Windows.Controls.Border
        $chip.Padding = '14,9'; $chip.Margin = '0,14,0,0'; $chip.CornerRadius = '3'; $chip.HorizontalAlignment = 'Left'
        $chip.Background = B '#101B22'; $chip.BorderBrush = B '#FFE28A'; $chip.BorderThickness = '1.5'
        $chip.Child = (New-TB -Text "No. $sqnum SQUADRON  $([char]0x2022)  $($base.ToUpper())  $([char]0x2022)  BEYOND THIS TABLE" -Family $CondFam -Size 12.5 -Colour '#FFE28A' -Bold)
        [void]$script:Stage.Children.Add($chip)
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
    $Pilot = Ensure-Squadron -Pilot $Pilot
    $sqnum = 92; if ($Pilot -and ($Pilot.PSObject.Properties.Name -contains 'sqn') -and $Pilot.sqn) { $sqnum = [int]$Pilot.sqn }

    $entries = @(Get-Paper)
    # ConvertFrom-Json plus the pipeline can nest the entry array several
    # layers deep (a single flatten once shipped broken); peel until the
    # real entries appear
    while ($entries.Count -eq 1 -and ($entries[0] -is [System.Array])) { $entries = $entries[0] }

    $leadIdx = -1
    if ($script:CampaignDate) {
        for ($k = 0; $k -lt $entries.Count; $k++) {
            $ed = $null
            try { $ed = [datetime]::ParseExact($entries[$k].date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture) } catch { }
            if ($ed -and ($ed -le $script:CampaignDate)) { $leadIdx = $k }
        }
    }
    # a campaign day before the first paper reads the first paper; no
    # campaign at all shows the latest front page
    if (($leadIdx -lt 0) -and $entries.Count) { $leadIdx = if ($script:CampaignDate) { 0 } else { $entries.Count - 1 } }

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
function Show-SquadronSelect {
    if (-not $script:SelPeriod) { $script:SelPeriod = 'P1' }
    $script:Stage.Children.Clear()
    Set-Header $null
    $h = C 'HdrSquadron'; if ($h) { $h.Text = 'Fighter Command' }
    $m = C 'HdrMotto'; if ($m) { $m.Text = "ROYAL AIR FORCE  $([char]0x2022)  POSTINGS" }
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
    $lead = New-TB -Text "The board for $($perDef.Desc). $([char]0x25B2)$([char]0x25B2)$([char]0x25B2) heavy fighting  $([char]0x25B2)$([char]0x25B2) steady  $([char]0x25B2) quiet. Click a ring to see the squadron, then report to it. A ring off its station can be dragged onto it." -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Wrap
    $lead.Margin = '0,0,0,12'
    [void]$script:Stage.Children.Add($lead)

    $W = 1080.0; $H = [math]::Round($W * 800.0 / 1600.0)
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

    # hand-corrected ring anchors (per station name, so they hold across periods)
    $script:RingPosPath = Join-Path $StateDir 'ringpos.json'
    $script:RingPos = @{}
    if (Test-Path $script:RingPosPath) {
        try {
            $rp = Get-Content $script:RingPosPath -Raw | ConvertFrom-Json
            foreach ($pp in $rp.PSObject.Properties) { $script:RingPos[$pp.Name] = $pp.Value }
        } catch { }
    }

    $script:SelSq = $null
    $script:SqDots = @()
    $script:SqChips = @()
    $detail = New-TB -Text 'No squadron selected.' -Family 'Segoe UI' -Size 14 -Colour '#9FB0B8' -Wrap
    $btn = New-Object Windows.Controls.Button
    $btn.Content = 'REPORT TO THIS SQUADRON'; $btn.IsEnabled = $false; $btn.MinWidth = 240
    $script:SqDetail = $detail
    $script:SqButton = $btn

    $script:SelectSq = {
        param($q2)
        $script:SelSq = $q2
        foreach ($d in $script:SqDots) {
            $d.Stroke = if ("$($d.Tag.Type)" -match 'Spitfire') { B '#5FD0E8' } else { B '#F5A83C' }
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
            $cp.BorderBrush = if ($cp.Tag -and $cp.Tag.Num -eq $q2.Num) { B '#FFE28A' } else { Res 'Rule' }
        }
        $actTxt = switch ("$($q2.Act)") { 'H' { 'in the thick of the fighting' } 'M' { 'steady action' } default { 'a quieter station' } }
        $codeTxt = if ("$($q2.Code)") { "   (codes $($q2.Code)-)" } else { '' }
        $script:SqDetail.Text = "No. $($q2.Num) Squadron  $([char]0x2022)  $($q2.Type)  $([char]0x2022)  $($q2.Base)  $([char]0x2022)  No. $(Get-GroupForBase $q2.Base) Group  $([char]0x2022)  $actTxt$codeTxt"
        $script:SqButton.IsEnabled = $true
    }

    # shared-station fan-out: count squadrons per station this period
    $stationCount = @{}
    foreach ($q in (Get-Squadrons)) {
        $po = Get-Posting $q $script:SelPeriod
        if ($po -and $po.Mx -ge 0) { $stationCount[$po.Base] = 1 + [int]$stationCount[$po.Base] }
    }
    $stationSeen = @{}
    $farActive = @(); $resting = @()
    foreach ($q in (Get-Squadrons)) {
        $po = Get-Posting $q $script:SelPeriod
        if (-not $po) { $resting += $q; continue }
        $qt = @{ Num=$q.Num; Code=$q.Code; Type=$q.Type; Base=$po.Base; Act=$po.Act; Period=$script:SelPeriod }
        if ($po.Mx -lt 0) { $farActive += $qt; continue }
        # Several squadrons at one station are fanned out around it. This
        # used to offset the first left and EVERY other one right, so a
        # third squadron sat exactly on top of the second.
        $offX = 0.0; $offY = 0.0
        $nAt = [int]$stationCount[$po.Base]
        if ($nAt -gt 1) {
            $ix = [int]$stationSeen[$po.Base]; $stationSeen[$po.Base] = $ix + 1
            if ($nAt -eq 2) { $offX = $(if ($ix -eq 0) { -13.0 } else { 13.0 }) }
            else {
                $ang = (2.0 * [math]::PI * $ix / $nAt) - ([math]::PI / 2.0)
                $rad = 15.0 + 3.0 * $nAt
                $offX = $rad * [math]::Cos($ang); $offY = $rad * [math]::Sin($ang)
            }
        }
        $cx = $po.Mx * $W + $offX
        $cy = $po.My * $H + $offY
        $ov = $script:RingPos["$($po.Base)|$($q.Num)"]
        if ($ov) { $cx = [double]$ov.x * $W; $cy = [double]$ov.y * $H }
        $isSpit = ("$($q.Type)" -match 'Spitfire')
        $ring = New-Object Windows.Shapes.Ellipse
        $ring.Width = 30; $ring.Height = 30; $ring.StrokeThickness = 2.5
        $ring.Stroke = if ($isSpit) { B '#5FD0E8' } else { B '#F5A83C' }
        $ring.Fill = B '#01000000'
        $ring.Cursor = 'Hand'
        $qt.CX = $cx; $qt.CY = $cy; $qt.MapW = $W; $qt.MapH = $H
        $qt.Drag = $false; $qt.Moved = $false; $qt.OX = 0.0; $qt.OY = 0.0
        [Windows.Controls.Canvas]::SetLeft($ring, $cx - 15); [Windows.Controls.Canvas]::SetTop($ring, $cy - 15)
        $pips = switch ("$($po.Act)") { 'H' { " $([char]0x25B2)$([char]0x25B2)$([char]0x25B2)" } 'M' { " $([char]0x25B2)$([char]0x25B2)" } default { " $([char]0x25B2)" } }
        $nl = New-TB -Text "$($q.Num)$pips" -Family $CondFam -Size 11.5 -Colour $(if ($isSpit) { '#9FE0F0' } else { '#F8C87E' }) -Bold
        $nl.IsHitTestVisible = $false
        [Windows.Controls.Canvas]::SetLeft($nl, $cx - 10); [Windows.Controls.Canvas]::SetTop($nl, $cy + 17)
        $qt.Label = $nl
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
                    $script:RingPos["$($t.Base)|$($t.Num)"] = @{ x = [math]::Round($t.CX / $t.MapW, 4); y = [math]::Round($t.CY / $t.MapH, 4) }
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
    if (-not $script:SelSq) {
        $q92 = Get-SquadronDef 92
        $po92 = Get-Posting $q92 'P1'
        $script:SelSq = @{ Num=92; Code='QJ'; Type='Spitfire I'; Base=$po92.Base; Act=$po92.Act; Period='P1' }
    }
    Set-Header $null
    $h = C 'HdrSquadron'; if ($h) { $h.Text = "No. $($script:SelSq.Num) Squadron" }
    $perDef2 = $Periods | Where-Object { $_.Id -eq "$($script:SelSq.Period)" } | Select-Object -First 1
    $m = C 'HdrMotto'; if ($m) { $m.Text = "ROYAL AIR FORCE  $([char]0x2022)  $($script:SelSq.Type.ToUpper())S AT $($script:SelSq.Base.ToUpper())$(if ($perDef2) { "  $([char]0x2022)  $($perDef2.Label)" })" }
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
