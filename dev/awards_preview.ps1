# Awards preview: every rung of the honours ladder, side by side.
#
# Why it exists: the decorations only appear on a career that has EARNED
# them, so seeing what a Bar or a DSO actually looks like meant flying
# forty sorties first. This asks Get-PlayerHonours for a set of imagined
# careers and lays the answers out, using the Room's own badge, ribbon
# and rank drawing, so what you see here is what the dispersal will show.
#
# Easiest way to run it: double-click dev\Awards Preview.bat.
#
# From a prompt, the whole line, with powershell at the front:
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File "dev\awards_preview.ps1"
#
# Add -Png <path> to write it to a file instead of opening a window.
#
# The Room is found NEXT DOOR by default rather than at a hard-coded D:,
# so this works wherever the fix folder has been put.
#
# -Side lw shows the German ladder instead: the Iron Cross, dated the same
# careful way, and worn as the objects they are rather than as ribbon bars.
param(
    [string]$Room,
    [string]$Png,
    [ValidateSet('raf','lw')]
    [string]$Side = 'raf'
)
if (-not $Room) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Room = Join-Path (Split-Path -Parent $here) 'BOB2_SquadronRoom.ps1'
}
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Keep the choice somewhere the Room cannot reach.
#
# A script's param() block declares its variables at SCRIPT scope, which
# is the very scope the Room is about to be dot-sourced into, and one of
# the first things the Room does is $script:Side = 'raf'. So -Side lw was
# silently overwritten and this tool drew the RAF ladder however it was
# asked. Anything taken from the command line and used after the
# dot-source has to be copied aside first.
$WantSide = $Side

if (-not (Test-Path $Room)) {
    Write-Host "Cannot find the Squadron Room script at:" -ForegroundColor Red
    Write-Host "  $Room" -ForegroundColor Red
    Write-Host "Pass its path with -Room, or run this from the fix folder's dev\ directory."
    Read-Host 'Press Enter to close'
    exit 1
}
# the same trick the smoke test uses: dot-source a copy with the lines
# that SHOW the Room's own window taken out, so only its functions load
$src = Get-Content $Room -Raw
$src = $src -replace '(?m)^\[void\]\$Win\.ShowDialog\(\)\s*$', ''
$src = $src -replace '(?m)^Finalize-Flight\s*$', ''
$src = $src -replace '(?m)^\$existing = Get-Pilot\s*$', ''
$src = $src -replace '(?m)^if \(\$existing\) \{ Show-Roster -Pilot \$existing \} else \{ Show-SquadronSelect \}\s*$', ''
$tmp = Join-Path (Split-Path -Parent $Room) '_awardspreview.ps1'
Set-Content -Path $tmp -Value $src -Encoding UTF8
try { . $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

# Point the state somewhere disposable BEFORE anything else. Nothing here
# is meant to save, but Set-StateSide also moves the badge folder, and a
# preview that quietly wrote to a real career would be the third time
# that has happened. See dev\README-testing.md.
$script:StateRootOverride = Join-Path ([IO.Path]::GetTempPath()) ('awprev-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:StateRootOverride -Force | Out-Null
Set-StateSide $WantSide

# One imagined career per rung, chosen to cross each threshold in turn.
# Sqn matters: an allied government decorated the men of its own units.
# VC is the one award a score cannot earn, so it is asked for with a
# sortie rather than a number.
$CASES = @(
    @{ Rank = 'Sergeant';          Name = 'Hobbs';     Vics = 0;  Sorties = 3  },
    @{ Rank = 'Sergeant';          Name = 'Wilkinson'; Vics = 2;  Sorties = 11 },
    @{ Rank = 'Sergeant';          Name = 'Unwin';     Vics = 6;  Sorties = 14 },
    @{ Rank = 'Sergeant';          Name = 'Lacey';     Vics = 11; Sorties = 30 },
    @{ Rank = 'Pilot Officer';     Name = 'Millin';    Vics = 5;  Sorties = 12 },
    @{ Rank = 'Flying Officer';    Name = 'Kingcome';  Vics = 10; Sorties = 26 },
    @{ Rank = 'Flight Lieutenant'; Name = 'Tuck';      Vics = 16; Sorties = 40 },
    @{ Rank = 'Flight Lieutenant'; Name = 'Bader';     Vics = 26; Sorties = 60 },
    @{ Rank = 'Sergeant';          Name = 'Frantisek'; Vics = 4;  Sorties = 14; Sqn = 303 },
    @{ Rank = 'Flying Officer';    Name = 'Urbanowicz'; Vics = 9; Sorties = 28; Sqn = 303 },
    @{ Rank = 'Sergeant';          Name = 'Prihoda';   Vics = 4;  Sorties = 15; Sqn = 310 },
    @{ Rank = 'Flight Lieutenant'; Name = 'Nicolson';  Vics = 3;  Sorties = 9;  VC = $true }
)
# a Log Book holding one sortie he should not have come back from
function New-VcDiary {
    $row = [pscustomobject]@{ ended = 9; kills = @(1, 0, 1, 1, 0, 0, 0) }
    [pscustomobject]@{ rows = @($row); kills = (New-Object int[] 7); total = 3 }
}

# The German ladder. Sorties matter as much as victories here: the EK II
# comes early to a man who is simply flying, and the EK I at twenty
# sorties even without a score, which is why the first three cases have no
# victories at all.
$LW_CASES = @(
    @{ Rank = 'Unteroffizier'; Name = 'Bergmann';  Vics = 0;  Sorties = 2  ; Unit = 'I./JG 26' }
    @{ Rank = 'Unteroffizier'; Name = 'Kessler';   Vics = 0;  Sorties = 4  ; Unit = 'I./JG 26' }
    @{ Rank = 'Feldwebel';     Name = 'Roth';      Vics = 2;  Sorties = 14 ; Unit = 'II./JG 51' }
    @{ Rank = 'Feldwebel';     Name = 'Stahl';     Vics = 3;  Sorties = 22 ; Unit = 'II./JG 51' }
    @{ Rank = 'Oberfeldwebel'; Name = 'Brandt';    Vics = 7;  Sorties = 30 ; Unit = 'III./JG 3' }
    @{ Rank = 'Leutnant';      Name = 'Hoffmann';  Vics = 1;  Sorties = 5  ; Unit = 'II./JG 26' }
    @{ Rank = 'Leutnant';      Name = 'Wendel';    Vics = 6;  Sorties = 16 ; Unit = 'II./JG 26' }
    @{ Rank = 'Oberleutnant';  Name = 'Falkenberg'; Vics = 14; Sorties = 34 ; Unit = 'I./JG 2' }
    @{ Rank = 'Oberleutnant';  Name = 'Reinhardt'; Vics = 20; Sorties = 41 ; Unit = 'I./JG 2' }
    @{ Rank = 'Hauptmann';     Name = 'von Below'; Vics = 27; Sorties = 55 ; Unit = 'Stab/JG 26'; Cmdr = $true }
    @{ Rank = 'Hauptmann';     Name = 'Moelders';  Vics = 41; Sorties = 68 ; Unit = 'Stab/JG 51'; Cmdr = $true }
)
function New-LwAwardCard {
    param([string]$Rank, [string]$Name, [int]$Vics, [int]$Sorties, [string]$Unit, [switch]$Cmdr)
    $p = [pscustomobject]@{ pilot = $Name; rank = $Rank; victories = $Vics; side = 'lw'
                            unit = $Unit; staffel = 4; cmode = $(if ($Cmdr) { 'commander' } else { 'pilot' }) }
    $career = Get-Career $p @() -Sorties $Sorties
    $h = @(Get-LwHonours -Pilot $p -Career $career)

    $bd = New-Object Windows.Controls.Border
    $bd.Background = Res 'Panel'; $bd.BorderBrush = Res 'Rule'; $bd.BorderThickness = '1'
    $bd.CornerRadius = '3'; $bd.Padding = '18,14'; $bd.Margin = '0,0,0,12'
    $bd.Width = 780; $bd.HorizontalAlignment = 'Left'
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-TB -Text "$($career.rank) $Name" -Family $SerifFam -Size 21 -Colour '#E9E3D4'))
    $line = "$Unit   $([char]0x2022)   $(Get-Appointment -Pilot $p -Career $career)   $([char]0x2022)   " +
            "$Sorties sorties   $([char]0x2022)   $Vics victor$(if ($Vics -eq 1) { 'y' } else { 'ies' })   $([char]0x2022)   " +
            $(if ($h.Count) { $h -join ', ' } else { 'no decorations' })
    [void]$sp.Children.Add((New-TB -Text $line -Family $CondFam -Size 12.5 -Colour '#9FB0B8' -Wrap))

    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,12,0,0'
    $bf = Get-RankBadgeFile $career.rank
    if ($bf) {
        $c = New-BadgeImage -File $bf -Height 46 -Tip $career.rank
        if ($c) { $c.Margin = '0,0,10,0'; [void]$row.Children.Add($c) }
    }
    $fb = New-BadgeImage -File 'pilot-badge.png' -Height 54 -Tip 'Flugzeugfuehrerabzeichen'
    if ($fb) { $fb.Margin = '0,0,18,0'; [void]$row.Children.Add($fb) }
    $hr = New-LwHonourRow $h
    if ($hr) { $hr.VerticalAlignment = 'Center'; [void]$row.Children.Add($hr) }
    [void]$sp.Children.Add($row)
    $bd.Child = $sp
    $bd
}

function New-AwardCard {
    param([string]$Rank, [string]$Name, [int]$Vics, [int]$Sorties, [int]$Sqn = 92, [switch]$VC)
    $p = [pscustomobject]@{ pilot = $Name; rank = $Rank; victories = $Vics; codes = 'QJ-K'; status = 'On strength'; sqn = $Sqn }
    $career = @{ sorties = $Sorties; hours = [math]::Round($Sorties * 1.4, 1); rank = $Rank; next = $null; nextAt = 0 }
    $h = @(Get-PlayerHonours $p $career -Diary $(if ($VC) { New-VcDiary } else { $null }))

    $bd = New-Object Windows.Controls.Border
    $bd.Background = Res 'Panel'; $bd.BorderBrush = Res 'Rule'; $bd.BorderThickness = '1'
    $bd.CornerRadius = '3'; $bd.Padding = '18,14'; $bd.Margin = '0,0,0,12'
    $bd.Width = 780; $bd.HorizontalAlignment = 'Left'
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-TB -Text "$Rank $Name" -Family $SerifFam -Size 21 -Colour '#E9E3D4'))
    $line = "No. $Sqn Sqn   $([char]0x2022)   $Sorties sorties   $([char]0x2022)   $Vics victories   $([char]0x2022)   " +
            $(if ($h.Count) { $h -join ', ' } else { 'no decorations' })
    [void]$sp.Children.Add((New-TB -Text $line -Family $CondFam -Size 12.5 -Colour '#9FB0B8'))

    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = '0,12,0,0'
    $bf = Get-RankBadgeFile $Rank
    if ($bf) {
        $c = New-BadgeImage -File $bf -Height 46 -Tip $Rank
        if ($c) { $c.Margin = '0,0,10,0'; [void]$row.Children.Add($c) }
    }
    $wg = New-BadgeImage -File 'wings.png' -Height 46 -Tip "Qualified pilot's flying badge"
    if ($wg) { $wg.Margin = '0,0,18,0'; [void]$row.Children.Add($wg) }
    $rb = New-RibbonRow $h -Height 30
    if ($rb) { $rb.VerticalAlignment = 'Center'; [void]$row.Children.Add($rb) }
    [void]$sp.Children.Add($row)
    $bd.Child = $sp
    $bd
}

$stack = New-Object Windows.Controls.StackPanel
$stack.Background = Res 'Base'; $stack.Margin = '24'
[void]$stack.Children.Add((New-TB -Text $(if ($WantSide -eq 'lw') { 'HOW THE GERMAN AWARDS COME UP' } else { 'HOW THE AWARDS COME UP' }) -Family $CondFam -Size 13 -Colour '#C8973F' -Bold))
$LW_BLURB = (
    'The Iron Cross II at a first victory or three sorties, the Iron Cross I at five victories or ' +
    'twenty sorties, and the Ritterkreuz at twenty victories. Twenty is the benchmark for the second ' +
    'half of 1940: it was raised to forty in 1941, which is the figure usually quoted and the wrong ' +
    'one for this campaign. They are drawn as they were worn rather than as a row of ribbon bars, ' +
    'because only the Iron Cross II is worn on a ribbon: the Iron Cross I is pinned flat to the ' +
    'breast and the Ritterkreuz hangs at the throat. Three awards a man of 1940 could not have are ' +
    'deliberately absent, all of them instituted later: the Deutsches Kreuz in Gold, the ' +
    'Frontflugspange, and the Winterschlacht im Osten medal, and so are the swords and the ' +
    'diamonds, which came in 1941. The oak leaves ARE here, at forty victories: they were ' +
    'instituted in June 1940 and Moelders and Galland both had them that September. They replace ' +
    'the plain Knight\u0027s Cross in the row rather than joining it, because the leaves clasp onto ' +
    'the cross a man already wears. Non-commissioned and commissioned ' +
    'pilots are separate careers in the Luftwaffe, not two ends of one ladder, so an Unteroffizier ' +
    'rises to Oberfeldwebel and a Leutnant to Oberleutnant. Hauptmann is a command.')
$sub = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Text (
    'A sergeant earns the DFM and an officer the DFC, as the RAF actually did, and a man decorated ' +
    'as a sergeant keeps his DFM when he is commissioned. Mentioned in Despatches at ten sorties, ' +
    'the cross at five victories, a Bar at ten, the DSO at fifteen and its Bar at twenty-five. ' +
    'The DFM is the narrower stripe. A man on a Polish or Czech squadron is decorated by his own ' +
    'government as well, and those ribbons are worn after all the British ones. The VC is the one ' +
    'award no score can earn: it takes a single sortie fought past the point of sense.')
if ($WantSide -eq 'lw') { $sub.Text = $LW_BLURB }
$sub.Margin = '0,4,0,14'; $sub.MaxWidth = 756
[void]$stack.Children.Add($sub)
if ($WantSide -eq 'lw') {
    foreach ($c in $LW_CASES) {
        [void]$stack.Children.Add((New-LwAwardCard -Rank $c.Rank -Name $c.Name -Vics $c.Vics `
                                   -Sorties $c.Sorties -Unit $c.Unit -Cmdr:([bool]$c.Cmdr)))
    }
}
else {
    foreach ($c in $CASES) {
        $sq = if ($c.ContainsKey('Sqn')) { [int]$c.Sqn } else { 92 }
        [void]$stack.Children.Add((New-AwardCard -Rank $c.Rank -Name $c.Name -Vics $c.Vics `
                                   -Sorties $c.Sorties -Sqn $sq -VC:([bool]$c.VC)))
    }
}

if ($Png) {
    # Measured and arranged DETACHED. Put in a window first and the
    # window's own layout wins: the panel came out three quarters empty
    # with the last two cards cut off the bottom, because it had already
    # been arranged to the window's 900 x 1100 before this ran.
    [double]$w = 828
    # Width is the CONTENT box; the panel's 24px margin sits outside it.
    # Setting Width = $w meant the panel needed 828 + 48 and the right
    # 48 pixels were arranged off the edge, which showed up as the last
    # character of every long line being shaved off. Nothing to do with
    # MaxWidth, which is where I looked first.
    $stack.Width = $w - 48
    $stack.Measure((New-Object Windows.Size ($w, [double]::PositiveInfinity)))
    [double]$h = [math]::Ceiling($stack.DesiredSize.Height)
    $stack.Arrange((New-Object Windows.Rect (0, 0, $w, $h)))
    $stack.UpdateLayout()
    $vb = New-Object Windows.Media.VisualBrush $stack; $vb.Stretch = 'None'
    $dv = New-Object Windows.Media.DrawingVisual; $dc = $dv.RenderOpen()
    # the panel's own margin is not painted by its Background, and came
    # out as a white band down the edge
    $dc.DrawRectangle((Res 'Base'), $null, (New-Object Windows.Rect (0, 0, $w, $h)))
    $dc.DrawRectangle($vb, $null, (New-Object Windows.Rect (0, 0, $w, $h))); $dc.Close()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap (([int]($w * 2)), ([int]($h * 2)), 192, 192, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    [void]$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($Png); $enc.Save($fs); $fs.Close()
    Write-Host "wrote $Png  ($([int]$w) x $([int]$h))"
    Remove-Item $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Content = $stack
    $Win.Content = $sv
    $Win.Title = $(if ($WantSide -eq 'lw') { 'Squadron Room - German awards preview' } else { 'Squadron Room - awards preview' })
    $Win.Width = 900; $Win.Height = 1000
    [void]$Win.ShowDialog()
}
