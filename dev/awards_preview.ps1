# Awards preview: every rung of the honours ladder, side by side.
#
# Why it exists: the decorations only appear on a career that has EARNED
# them, so seeing what a Bar or a DSO actually looks like meant flying
# forty sorties first. This asks Get-PlayerHonours for a set of imagined
# careers and lays the answers out, using the Room's own badge, ribbon
# and rank drawing, so what you see here is what the dispersal will show.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File dev\awards_preview.ps1 `
#       -Room "D:\Battle of Britain II\BOB2-Win11-Fix\BOB2_SquadronRoom.ps1"
#
# Add -Png <path> to write it to a file instead of opening a window.
param(
    [string]$Room = 'D:\Battle of Britain II\BOB2-Win11-Fix\BOB2_SquadronRoom.ps1',
    [string]$Png
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

if (-not (Test-Path $Room)) { Write-Host "Cannot find $Room" -ForegroundColor Red; exit 1 }
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
$CASES = @(
    @{ Rank = 'Sergeant';          Name = 'Hobbs';    Vics = 0;  Sorties = 3  },
    @{ Rank = 'Sergeant';          Name = 'Wilkinson'; Vics = 2; Sorties = 11 },
    @{ Rank = 'Sergeant';          Name = 'Unwin';    Vics = 6;  Sorties = 14 },
    @{ Rank = 'Sergeant';          Name = 'Lacey';    Vics = 11; Sorties = 30 },
    @{ Rank = 'Pilot Officer';     Name = 'Millin';   Vics = 5;  Sorties = 12 },
    @{ Rank = 'Flying Officer';    Name = 'Kingcome'; Vics = 10; Sorties = 26 },
    @{ Rank = 'Flight Lieutenant'; Name = 'Tuck';     Vics = 16; Sorties = 40 },
    @{ Rank = 'Flight Lieutenant'; Name = 'Bader';    Vics = 22; Sorties = 52 }
)

function New-AwardCard {
    param([string]$Rank, [string]$Name, [int]$Vics, [int]$Sorties)
    $p = [pscustomobject]@{ pilot = $Name; rank = $Rank; victories = $Vics; codes = 'QJ-K'; status = 'On strength' }
    $career = @{ sorties = $Sorties; hours = [math]::Round($Sorties * 1.4, 1); rank = $Rank; next = $null; nextAt = 0 }
    $h = @(Get-PlayerHonours $p $career)

    $bd = New-Object Windows.Controls.Border
    $bd.Background = Res 'Panel'; $bd.BorderBrush = Res 'Rule'; $bd.BorderThickness = '1'
    $bd.CornerRadius = '3'; $bd.Padding = '18,14'; $bd.Margin = '0,0,0,12'
    $bd.Width = 780; $bd.HorizontalAlignment = 'Left'
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-TB -Text "$Rank $Name" -Family $SerifFam -Size 21 -Colour '#E9E3D4'))
    $line = "$Sorties sorties   $([char]0x2022)   $Vics victories   $([char]0x2022)   " +
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
    'the cross at five victories, a Bar at ten, the DSO at fifteen. The DFM is the narrower stripe.')
$sub.Margin = '0,4,0,14'; $sub.MaxWidth = 780
[void]$stack.Children.Add($sub)
foreach ($c in $CASES) {
    [void]$stack.Children.Add((New-AwardCard -Rank $c.Rank -Name $c.Name -Vics $c.Vics -Sorties $c.Sorties))
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
