# Screen preview: render any one screen of the Room to a PNG.
#
# Why it exists: Patrick asked whether the British and the German sides
# look the same, and the only way to answer that was to launch the game,
# open the Room, and remember what the other side looked like. Now both
# can be put side by side on the desk.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File dev\screen_preview.ps1 `
#       -Side lw -Tab paper -Png C:\temp\meldung.png
#
# -Side  raf or lw
# -Tab   dispersal, logbook, map, paper, or postings
# -Png   where to write it; without one a window opens instead
#
# It draws against a THROWAWAY COPY of the state folder, for the reason
# written at length in room_smoketest.ps1: drawing is not read-only, and
# a harness that ran against the real install once read Patrick's morning
# bulletin for him and once destroyed a pilot record outright.
param(
    [ValidateSet('raf','lw')][string]$Side = 'raf',
    [ValidateSet('dispersal','logbook','map','paper','postings')][string]$Tab = 'dispersal',
    [string]$Room,
    [string]$Png
)
if (-not $Room) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Room = Join-Path (Split-Path -Parent $here) 'BOB2_SquadronRoom.ps1'
}
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
# Copied aside before the dot-source: a script's param() declares at
# SCRIPT scope, which is the scope the Room loads into, and the Room sets
# $script:Side itself. This is the trap that made the awards preview
# ignore -Side lw however it was asked.
$WantSide = $Side
$WantTab  = $Tab
$WantPng  = $Png
if (-not (Test-Path $Room)) { Write-Host "Cannot find the Room at $Room" -ForegroundColor Red; exit 1 }
$src = Get-Content $Room -Raw
$src = $src -replace '(?m)^\[void\]\$Win\.ShowDialog\(\)\s*$', ''
$src = $src -replace '(?m)^Finalize-Flight\s*$', ''
$src = $src -replace '(?m)^\$existing = Get-Pilot\s*$', ''
$src = $src -replace '(?m)^if \(\$existing\) \{ Show-Roster -Pilot \$existing \} else \{ Show-SquadronSelect \}\s*$', ''
$tmp = Join-Path (Split-Path -Parent $Room) '_screenpreview.ps1'
Set-Content -Path $tmp -Value $src -Encoding UTF8
try { . $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

$realRoot = Split-Path -Parent $StateDir
$script:StateRootOverride = Join-Path ([IO.Path]::GetTempPath()) ('roompreview-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:StateRootOverride -Force | Out-Null
if (Test-Path $realRoot) { Copy-Item (Join-Path $realRoot '*') $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue }
Set-StateSide $WantSide
$script:Side = $WantSide
if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }

$pl = Get-Pilot
# The German side may have no career on this machine yet. Post a man to
# the first Gruppe in the line so there is a ready room to look at,
# rather than falling back to the postings board and pretending that is
# what was asked for.
if (-not $pl -and $WantSide -eq 'lw' -and $WantTab -ne 'postings') {
    $u = @(Get-LwGruppen)[0]
    $script:SelSq = @{
        Unit = "$($u.unit)"; Gesch = "$($u.geschwader)"; Gruppe = "$($u.gruppe)"
        Type = "$($u.type)"; Base = "$($u.field)"; Skill = "$($u.skill)"
        Luftflotte = [int]$u.luftflotte; Period = 'P2'
    }
    Show-GruppeCreate
    $script:NameBox.Text = 'Vorschau'
    $script:SelPortrait = 'pilot01.jpg'
    $script:SelRank = 'Leutnant'
    Invoke-GruppeSubmit
    $pl = Get-Pilot
}
if ($WantTab -eq 'postings') {
    if ($WantSide -eq 'lw') { Show-GruppeSelect } else { Show-SquadronSelect }
} else {
    Show-Tab $WantTab
}
Write-Host "$WantSide / $WantTab : $($script:Stage.Children.Count) blocks"

if ($WantPng) {
    # Measured and arranged DETACHED, for the reason spelled out in
    # awards_preview.ps1: put it in a window first and the window's own
    # layout wins and the page comes out cropped.
    [double]$w = 1280
    $stack = $script:Stage
    # The stage carries a margin of its own inside the Room's scroller,
    # and a VisualBrush at Stretch None samples from the visual's bounds,
    # margin included: the first render came out shifted left with the
    # first characters of every line shaved off. Zero the margin and give
    # the page its padding here instead.
    $stack.Margin = '24,16,24,16'
    $stack.Width = $w - 48
    $stack.Measure((New-Object Windows.Size ($w, [double]::PositiveInfinity)))
    [double]$h = [math]::Ceiling($stack.DesiredSize.Height) + 24
    $stack.Arrange((New-Object Windows.Rect (0, 0, $w, $h)))
    $stack.UpdateLayout()
    $vb = New-Object Windows.Media.VisualBrush $stack; $vb.Stretch = 'None'
    $dv = New-Object Windows.Media.DrawingVisual; $dc = $dv.RenderOpen()
    $dc.DrawRectangle((Res 'Base'), $null, (New-Object Windows.Rect (0, 0, $w, $h)))
    $dc.DrawRectangle($vb, $null, (New-Object Windows.Rect (0, 0, $w, $h))); $dc.Close()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap (([int]$w), ([int]$h), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    [void]$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($WantPng); $enc.Save($fs); $fs.Close()
    Write-Host "wrote $WantPng  ($([int]$w) x $([int]$h))"
    Remove-Item $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Content = $script:Stage
    $Win.Content = $sv
    [void]$Win.ShowDialog()
    Remove-Item $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue
}
