param([string]$Out, [string]$Day = '1940-09-16')
$Room = Join-Path (Split-Path -Parent $PSScriptRoot) 'BOB2_SquadronRoom.ps1'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$src = Get-Content $Room -Raw
$src = $src -replace '(?m)^\[void\]\$Win\.ShowDialog\(\)\s*$', ''
$src = $src -replace '(?m)^Finalize-Flight\s*$', ''
$src = $src -replace '(?m)^Start-Room\s*$', ''
$tmp = Join-Path (Split-Path -Parent $Room) '_paperband_room.ps1'
Set-Content -Path $tmp -Value $src -Encoding UTF8
try { . $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
$ErrorActionPreference = 'Continue'
$root = New-Object Windows.Controls.StackPanel
foreach ($sd in 'raf', 'lw') {
    $paper = New-Object Windows.Controls.Border
    $paper.Background = B '#E9E0CA'; $paper.Padding = '40,10,40,20'; $paper.Width = 940; $paper.Margin = '0,0,0,16'
    $col = New-Object Windows.Controls.StackPanel
    [void]$col.Children.Add((New-TB -Text "($sd edition)" -Family $CondFam -Size 11 -Colour '#6B6250'))
    [void](Add-DaybookBand -Col $col -Side $sd -Date ([datetime]$Day))
    $paper.Child = $col
    [void]$root.Children.Add($paper)
}
$root.Measure([Windows.Size]::new(940, [double]::PositiveInfinity))
$root.Arrange([Windows.Rect]::new(0, 0, 940, $root.DesiredSize.Height))
$root.UpdateLayout()
$rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap(940, [int]$root.DesiredSize.Height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
$rtb.Render($root)
$enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
[void]$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
$fs = [IO.File]::Create($Out); $enc.Save($fs); $fs.Close()
"saved $Out"
