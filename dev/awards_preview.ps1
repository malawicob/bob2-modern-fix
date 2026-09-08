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
param(
    [string]$Room,
    [string]$Png
)
if (-not $Room) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Room = Join-Path (Split-Path -Parent $here) 'BOB2_SquadronRoom.ps1'
}
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

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
[void]$stack.Children.Add((New-TB -Text 'HOW THE AWARDS COME UP' -Family $CondFam -Size 13 -Colour '#C8973F' -Bold))
$sub = New-TB -Wrap -Family 'Segoe UI' -Size 12.5 -Colour '#6F828C' -Text (
    'A sergeant earns the DFM and an officer the DFC, as the RAF actually did, and a man decorated ' +
    'as a sergeant keeps his DFM when he is commissioned. Mentioned in Despatches at ten sorties, ' +
    'the cross at five victories, a Bar at ten, the DSO at fifteen and its Bar at twenty-five. ' +
    'The DFM is the narrower stripe. A man on a Polish or Czech squadron is decorated by his own ' +
    'government as well, and those ribbons are worn after all the British ones. The VC is the one ' +
    'award no score can earn: it takes a single sortie fought past the point of sense.')
$sub.Margin = '0,4,0,14'; $sub.MaxWidth = 780
[void]$stack.Children.Add($sub)
foreach ($c in $CASES) {
    $sq = if ($c.ContainsKey('Sqn')) { [int]$c.Sqn } else { 92 }
    [void]$stack.Children.Add((New-AwardCard -Rank $c.Rank -Name $c.Name -Vics $c.Vics `
                               -Sorties $c.Sorties -Sqn $sq -VC:([bool]$c.VC)))
}

if ($Png) {
    # Measured and arranged DETACHED. Put in a window first and the
    # window's own layout wins: the panel came out three quarters empty
    # with the last two cards cut off the bottom, because it had already
    # been arranged to the window's 900 x 1100 before this ran.
    [double]$w = 828
    $stack.Width = $w
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
}
else {
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Content = $stack
    $Win.Content = $sv
    $Win.Title = 'Squadron Room - awards preview'
    $Win.Width = 900; $Win.Height = 1000
    [void]$Win.ShowDialog()
}
