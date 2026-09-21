# Renders Squadron Room screens to PNG for the user guide, off-screen, from a
# throwaway state folder. Nothing of the player's is read or written.
#   powershell -File dev\room_shots.ps1 -OutDir <folder>
param([string]$OutDir)
$Room = Join-Path (Split-Path -Parent $PSScriptRoot) 'BOB2_SquadronRoom.ps1'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$src = Get-Content $Room -Raw
$src = $src -replace '(?m)^\[void\]\$Win\.ShowDialog\(\)\s*$', ''
$src = $src -replace '(?m)^Finalize-Flight\s*$', ''
$src = $src -replace '(?m)^Start-Room\s*$', ''
$tmp = Join-Path (Split-Path -Parent $Room) '_roomshots_room.ps1'
Set-Content -Path $tmp -Value $src -Encoding UTF8
try { . $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$script:StateRootOverride = Join-Path ([IO.Path]::GetTempPath()) ('roomshots-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:StateRootOverride -Force | Out-Null
# a campaign morning to draw, since there is no save here to read one from
function Get-CampaignDate { param($Path) [datetime]'1940-08-16' }

function Save-Visual { param($Visual, [string]$Name, [int]$W = 1180, [int]$MaxH = 2600, [string]$Bg = '#131D24')
    $host0 = New-Object Windows.Controls.Border; $host0.Background = B $Bg; $host0.Padding = '24'
    $host0.Child = $Visual
    $host0.Measure([Windows.Size]::new($W, [double]::PositiveInfinity))
    $h = [int][math]::Min($MaxH, [math]::Ceiling($host0.DesiredSize.Height))
    $host0.Arrange([Windows.Rect]::new(0, 0, $W, $h)); $host0.UpdateLayout()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($W, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32); $rtb.Render($host0)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; [void]$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $OutDir $Name)); $enc.Save($fs); $fs.Close()
    $host0.Child = $null
    "  $Name  ${W}x$h"
}
function Save-Stage { param([string]$Name, [int]$MaxH = 2600)
    $sp = New-Object Windows.Controls.StackPanel
    foreach ($k in @($script:Stage.Children)) { $script:Stage.Children.Remove($k); [void]$sp.Children.Add($k) }
    Save-Visual $sp $Name -MaxH $MaxH
}

# ---- RAF ----
Set-StateSide 'raf'
if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }
$ltr = Get-RafLetter -Code 'DW' -Type 'Spitfire I' -PlaneId 0; if (-not $ltr) { $ltr = 'A' }
$rp = [ordered]@{ pilot='Millin'; first='Patrick'; rank='Pilot Officer'; codes="DW-$ltr"; status='On strength'; serials='R6991'; note='Posted to No. 610 Squadron at RAF Biggin Hill.'
                  cmode='pilot'; sqn=610; sqcode='DW'; actype='Spitfire I'; base='Biggin Hill'; period='P2'; historical=$false; portrait='pilot01.jpg'
                  created='1940-08-16'; createdAt=(Get-Date).ToString('s'); campaignSorties=0; campaignKills=@(0,0,0,0,0,0,0) }
Save-Pilot -Pilot $rp -Shrink
try { Show-Roster -Pilot (Get-Pilot); Save-Stage 'raf-dispersal.png' 1500 } catch { "raf dispersal: $($_.Exception.Message)" }
try { Show-Tab 'paper'; Save-Stage 'raf-paper.png' } catch { "raf paper: $($_.Exception.Message)" }

# ---- Luftwaffe, a Bf 110 crew ----
Set-StateSide 'lw'
if (-not (Test-Path $script:StateDir)) { New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null }
$g = @(Get-LwGruppen) | Where-Object { "$($_.unit)" -eq 'III./ZG 26' } | Select-Object -First 1
$lp = [ordered]@{ pilot='Millin'; first='Patrick'; rank='Leutnant'; side='lw'; status='On strength'; note="Posted to III./ZG 26 at $($g.field)."
                  cmode='pilot'; unit='III./ZG 26'; gesch="$($g.geschwader)"; gruppe='III'; staffel=7; sqn=0; actype='Bf 110'; base="$($g.field)"
                  luftflotte=[int]$g.luftflotte; period='P2'; historical=$false; portrait='pilot03.jpg'; acnum=4; created='1940-08-16'
                  createdAt=(Get-Date).ToString('s'); campaignSorties=0; campaignKills=@(0,0,0,0,0,0,0) }
$lp['crew'] = @(New-CrewFor -Unit 'III./ZG 26' -Type 'Bf 110' -Date ([datetime]'1940-08-16') -Seed 'MillinIII./ZG 26')
Save-Pilot -Pilot $lp -Shrink
try { Show-ReadyRoom -Pilot (Get-Pilot); Save-Stage 'lw-readyroom.png' 1500 } catch { "lw ready room: $($_.Exception.Message)" }
try { Show-Tab 'paper'; Save-Stage 'lw-paper.png' } catch { "lw paper: $($_.Exception.Message)" }
try { Show-Tab 'gruppen'; Save-Stage 'lw-gruppen.png' 1400 } catch { "lw gruppen: $($_.Exception.Message)" }
try {
    $bw = New-BackgroundWindow -Pilot (Get-Pilot) -CrewIndex -1
    $content = $bw.Content; $bw.Content = $null
    Save-Visual $content 'personal-record.png' -W 900 -Bg '#0F171D'
} catch { "record: $($_.Exception.Message)" }
Remove-Item $script:StateRootOverride -Recurse -Force -ErrorAction SilentlyContinue
