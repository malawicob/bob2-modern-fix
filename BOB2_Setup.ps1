# BOB2 2.13 Modern Fix - install and repair
# Automates patching from v2.06 through v2.12/v2.13, dgVoodoo2, and crash fix

param(
    # Define every function and return, without showing the console menu.
    # BOB2_Install.ps1 dot-sources this file that way so the GUI drives the
    # same Step-* code. param() has to be the FIRST executable statement in
    # the file - only comments may come before it.
    [switch]$AsLibrary
)

$ErrorActionPreference = "Stop"

# When dot-sourced by the GUI there is NO CONSOLE. Any prompt that waits for
# a keypress or a line of input therefore blocks forever with nothing on
# screen to explain why, and the window simply freezes - which is exactly
# what a tester reported when his v2.06 install needed a patch file he did
# not have. Every interactive helper below checks this and throws a clear,
# catchable error instead of waiting for input that can never arrive.
$script:NonInteractive = [bool]$AsLibrary
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Version of THIS fix package (not the game version).
# Must match BOB2FIX_VERSION in dinput8_guard.c - the crash guard writes its
# own version into bob2guard.log, so a mismatch means a stale DLL is deployed.

# ONE source of truth for the version number.
#
# This used to be its own literal, and it drifted: the launcher was bumped
# to 1.6.26 while this still said 1.6.21, so every install got stamped
# 1.6.21 and the launcher reported "1.6.21 installed - 1.6.26 available"
# forever, even immediately after a clean install. Read it from the
# launcher instead, so the two cannot disagree.
$FixVersion = '1.6.21'
$FixVersionDate = "2026-08-06"
try {
    $launcherPs1 = Join-Path $PSScriptRoot 'BOB2_Launcher.ps1'
    if (Test-Path $launcherPs1) {
        $m = Select-String -Path $launcherPs1 -Pattern "^\`$FixVersion\s*=\s*'([^']+)'" -ErrorAction Stop |
             Select-Object -First 1
        if ($m) { $FixVersion = $m.Matches[0].Groups[1].Value }
    }
} catch { }
$StampFile = "BOB2-Win11-Fix.version"

# Ensure console window is wide enough. Skipped as a library: there is no
# console to resize, and touching one that does not exist throws.
try {
    if ($AsLibrary) { throw 'library' }
    $minWidth = 90
    $minHeight = 35
    if ($Host.UI.RawUI.WindowSize.Width -lt $minWidth -or $Host.UI.RawUI.WindowSize.Height -lt $minHeight) {
        $bufferSize = $Host.UI.RawUI.BufferSize
        if ($bufferSize.Width -lt $minWidth) {
            $bufferSize.Width = $minWidth
            $Host.UI.RawUI.BufferSize = $bufferSize
        }
        $windowSize = $Host.UI.RawUI.WindowSize
        if ($windowSize.Width -lt $minWidth) { $windowSize.Width = $minWidth }
        if ($windowSize.Height -lt $minHeight) { $windowSize.Height = $minHeight }
        $Host.UI.RawUI.WindowSize = $windowSize
    }
} catch {
    # Ignore - some hosts don't support resizing
}

# Known Bob.exe file sizes for version detection
$BobExeSizes = @{
    4464640 = "2.12"
    4460544 = "2.13"
}
$BobExeMD5_212 = "006280352cf8370a09812f02afe45d47"

# dgVoodoo2 DLLs to install
$DgVoodooDLLs = @("DDraw.dll", "D3DImm.dll", "D3D8.dll", "D3D9.dll")

# ReShade (optional visual enhancement). dxgi.dll hooks dgVoodoo2 D3D11 output.
# Size identifies OUR shipped build; never delete a dxgi.dll of a different size.
$ReShadeDllSize = 4136216
$ReShadeItems = @("dxgi.dll", "ReShade.ini", "reshade-shaders", "reshade-presets", "reshade-screenshots")


# Detected refresh rate (set during install)
$script:DetectedFPS = 60

function Get-MonitorRefreshRate {
    $refreshRate = 60  # safe default
    try {
        $monitor = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($monitor -and $monitor.CurrentRefreshRate -and $monitor.CurrentRefreshRate -gt 0) {
            $refreshRate = [int]$monitor.CurrentRefreshRate
        }
    } catch {}

    if ($refreshRate -le 0 -or $refreshRate -gt 500) { $refreshRate = 60 }

    Write-Host ""
    Write-Host "  Detected monitor refresh rate: $refreshRate Hz" -ForegroundColor Green

    # Detected value is the answer we would recommend anyway, so with no
    # console just take it. This pair of prompts was the last thing hanging
    # the Install and repair window: the DLLs copied, then it stopped dead
    # here waiting to be asked about the FPS limit.
    if ($script:NonInteractive) {
        Write-Host "  FPS limit set to: $refreshRate" -ForegroundColor Green
        $script:DetectedFPS = $refreshRate
        return $refreshRate
    }

    Write-Host ""
    Write-Host "  Use $refreshRate as your FPS limit? (Y/n): " -ForegroundColor Yellow -NoNewline
    $confirm = Read-Host
    if ($confirm -match '^[Nn]') {
        Write-Host "  Enter your preferred FPS limit (e.g. 60, 120, 144, 240): " -ForegroundColor Yellow -NoNewline
        $val = Read-Host
        if ($val -match '^\d+$' -and [int]$val -gt 0 -and [int]$val -le 500) {
            $refreshRate = [int]$val
        } else {
            Write-Host "  Invalid value, keeping $refreshRate" -ForegroundColor DarkYellow
        }
    }
    Write-Host "  FPS limit set to: $refreshRate" -ForegroundColor Green
    $script:DetectedFPS = $refreshRate
    return $refreshRate
}

# dgVoodoo.conf template
$DgVoodooConf = @"
[General]
OutputAPI = d3d11_fl11_0
Adapters = all
FullScreenOutput = default
FullScreenMode = true
ScalingMode = stretched_ar
ProgressiveScanlineOrder = false
EnumerateRefreshRates = true
Brightness = 100
Color = 100
Contrast = 100
InheritColorProfileInFullScreenMode = true
KeepWindowAspectRatio = true
CaptureMouse = true
CenterAppWindow = false
DisableScreenSaver = false

[GeneralExt]
DesktopResolution =
DesktopBitDepth =
DeframerSize = 0
ImageScaleFactor = 1
CursorScaleFactor = 0
DisplayROI =
Resampling = bilinear
PresentationModel = discard
ColorSpace = appdriven
FreeMouse = false
WindowedAttributes =
FullscreenAttributes =
FPSLimit = 60
Environment =
SystemHookFlags =

[Glide]
VideoCard = voodoo_banshee
OnboardRAM = 8
MemorySizeOfTMU = 4096
NumberOfTMUs = 1
TMUFiltering = appdriven
DisableMipmapping = false
Resolution = unforced
Antialiasing = appdriven
EnableGlideGammaRamp = true
ForceVerticalSync = true
ForceEmulatingTruePCIAccess = false
16BitDepthBuffer = false
3DfxWatermark = true
3DfxSplashScreen = false
PointcastPalette = false
EnableInactiveAppState = false

[GlideExt]
DitheringEffect = pure32bit
Dithering = forcealways
DitherOrderedMatrixSizeScale = 0

[DirectX]
DisableAndPassThru = false
VideoCard = internal3D
; VRAM: 4096, matched to the PROVEN working install (audited 2026-08-24).
; An earlier release lowered this to 256 on a theory; the one machine with
; verified full-resolution 3D runs 4096, and a tester on 256 had the game
; fall back to a low-resolution mode. Ship what demonstrably works.
VRAM = 4096
Filtering = appdriven
Mipmapping = appdriven
KeepFilterIfPointSampled = false
Resolution = max
Antialiasing = appdriven
AppControlledScreenMode = true
DisableAltEnterToToggleScreenMode = true
Bilinear2DOperations = true
PhongShadingWhenPossible = false
ForceVerticalSync = true
dgVoodooWatermark = false
FastVideoMemoryAccess = true
DisableD3DTnLDevice = false

[DirectXExt]
AdapterIDType =
VendorID =
DeviceID =
SubsystemID =
RevisionID =
DefaultEnumeratedResolutions = all
ExtraEnumeratedResolutions =
EnumeratedResolutionBitdepths = all
DitheringEffect = high_quality
Dithering = forcealways
DitherOrderedMatrixSizeScale = 0
DepthBuffersBitDepth = forcemin24bit
Default3DRenderFormat = auto
MaxVSConstRegisters = 256
D3D12BoundsChecking = false
NPatchTesselationLevel = 0
DisplayOutputEnableMask = 0xffffffff
MSD3DDeviceNames = false
RTTexturesForceScaleAndMSAA = true
SmoothedDepthSampling = true
DeferredScreenModeSwitch = false
PrimarySurfaceBatchedUpdate = false
SuppressAMDBlacklist = false
"@

# Minimal bdg.txt with critical settings for fresh installs.
#
# NOTE ON DENSITY: OBJECT_DENSITY and PARTICLE_DENSITY are QUALITY settings, and
# their maximum (4) is the single biggest frame-rate cost in this engine. BOB2 is
# CPU-bound - measured 2026-08-03, the CPU spends ~3x longer per frame than the GPU
# even on an RTX 4080 - and ground-object processing is the main CPU load.
# Dropping OBJECT_DENSITY from 4 to 2 (with the two scenery toggles off) was part of
# a change that took median frame rate from 28 to 76 FPS on a 13900HX/RTX 4080.
# So we ship 2, not 4. Users who want maximum scenery can raise it in the Settings
# Tweaker and accept the cost.
$MinimalBdgTxt = @"
SKIP_VIDEOS=ON
SKIP_QUICKVIDEOS=ON
INTRO_VIDEO=OFF
SMOOTHEN_FRAMERATE_MODE=NONE
OBJECT_DENSITY = 2
PARTICLE_DENSITY = 2
LANDSCAPE_TEXTURE_SIZE = 2048
UI_REFRESH = 120.000000
PERIPHERAL_VISION_RANGE = 6000
Your_2dGauges_Work_In_Autopilot=ON
BOB_SMOOTHER_DEADZONE=ON
ENABLE_AUTO_GEN=OFF
ADD_SHEEP_COWS_AND_HAYSTACKS=OFF
"@

# ============================================================
# Helper Functions
# ============================================================

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "--- $Text ---" -ForegroundColor Yellow
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [!!] $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "  [ERROR] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Gray
}

function Pause-Continue {
    # Nothing to acknowledge when there is no console - just carry on.
    if ($script:NonInteractive) { return }
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Pause-WithPrompt {
    param([string]$Text)
    # This always means "something is missing and I cannot continue without
    # it". With a console we wait; without one we must say so, or the caller
    # sits on a dead window.
    if ($script:NonInteractive) { throw "NEEDS-FILE: $Text" }
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor Yellow
    Write-Host "  Press any key once ready, or Ctrl+C to cancel..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Get-YesNo {
    param([string]$Prompt)
    # Read-Host returns empty immediately with no console, so this loop would
    # spin forever rather than block. Worse than a freeze - it pegs a core.
    if ($script:NonInteractive) { throw "NEEDS-ANSWER: $Prompt" }
    do {
        Write-Host ""
        Write-Host "  $Prompt (Y/N): " -ForegroundColor Yellow -NoNewline
        $answer = Read-Host
    } while ($answer -notmatch '^[YyNn]$')
    return $answer -match '^[Yy]$'
}

function Find-GameFolder {
    # Check if script is running from game folder
    if (Test-Path (Join-Path $ScriptDir "Bob.exe")) {
        return $ScriptDir
    }

    # Check if running from BOB2-Win11-Fix subfolder inside game folder
    $parentDir = Split-Path -Parent $ScriptDir
    if (Test-Path (Join-Path $parentDir "Bob.exe")) {
        return $parentDir
    }

    # Check common install locations
    $commonPaths = @(
        "C:\Battle of Britain II",
        "D:\Battle of Britain II",
        "C:\Program Files (x86)\Battle of Britain II",
        "C:\Games\Battle of Britain II",
        "D:\Games\Battle of Britain II"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path (Join-Path $path "Bob.exe")) {
            return $path
        }
    }

    return $null
}

function Validate-GameFolder {
    param([string]$Path)
    $required = @("Bob.exe")
    $optional = @("BoB.tci", "BATTLE.DIR")

    $hasRequired = $true
    foreach ($file in $required) {
        if (-not (Test-Path (Join-Path $Path $file))) {
            $hasRequired = $false
        }
    }

    $optionalCount = 0
    foreach ($file in $optional) {
        if (Test-Path (Join-Path $Path $file)) {
            $optionalCount++
        }
    }

    return $hasRequired -and ($optionalCount -gt 0)
}

function Get-BobVersion {
    param([string]$GameFolder)

    $bobExe = Join-Path $GameFolder "Bob.exe"
    if (-not (Test-Path $bobExe)) { return "unknown" }

    $fileSize = (Get-Item $bobExe).Length

    # Check known sizes
    if ($BobExeSizes.ContainsKey($fileSize)) {
        return $BobExeSizes[$fileSize]
    }

    # Check bob2_ver.txt
    $verFile = Join-Path $GameFolder "bob2_ver.txt"
    if (Test-Path $verFile) {
        $verContent = (Get-Content $verFile -Raw).Trim()
        if ($verContent -match '2\.\d+') {
            return $Matches[0]
        }
    }

    return "unknown (Bob.exe size: $fileSize bytes)"
}

function Get-FileMD5 {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return "" }
    $hash = Get-FileHash -Path $FilePath -Algorithm MD5
    return $hash.Hash.ToLower()
}

function Write-VersionStamp {
    # Record what this run installed, so the game folder always says which
    # fix version it is carrying - independent of the game's own version.
    param([string]$GameFolder)

    $stampPath = Join-Path $GameFolder $StampFile
    $dllPath = Join-Path $GameFolder "dinput8.dll"
    $dllHash = if (Test-Path $dllPath) { Get-FileMD5 $dllPath } else { "not installed" }

    $lines = @(
        "Battle of Britain II - 2.13 Modern Windows Fix",
        "FixVersion   = $FixVersion",
        "Released     = $FixVersionDate",
        "InstalledOn  = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "GameVersion  = $(Get-BobVersion $GameFolder)",
        "CrashGuardMD5= $dllHash",
        "",
        "The crash guard logs the same version into bob2guard.log on every run.",
        "If those two disagree, a stale dinput8.dll is deployed - re-run the",
        "setup tool and choose the crash fix step."
    )
    Set-Content -Path $stampPath -Value $lines -Encoding ASCII
    Write-OK "Stamped install as fix v$FixVersion ($StampFile)"
}

function Find-PatchFile {
    # Search for a file by name in the script dir, game folder, and BOB2-Win11-Fix subfolder
    param([string]$FileName, [string]$GameFolder)

    $searchPaths = @(
        (Join-Path $ScriptDir $FileName),
        (Join-Path $GameFolder $FileName),
        (Join-Path $GameFolder "BOB2-Win11-Fix\$FileName")
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Find-PatchFileByPattern {
    # Search for a file by wildcard pattern in the script dir, game folder, and BOB2-Win11-Fix subfolder
    param([string]$Pattern, [string]$GameFolder)

    $searchDirs = @($ScriptDir, $GameFolder, (Join-Path $GameFolder "BOB2-Win11-Fix"))

    foreach ($dir in $searchDirs) {
        if (Test-Path $dir) {
            $match = Get-ChildItem -Path $dir -Filter $Pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) { return $match.FullName }
        }
    }
    return $null
}

# ============================================================
# Installation Steps
# ============================================================

function Step-DetectGame {
    Write-Step "Step 1: Detect Game Folder"

    $folder = Find-GameFolder
    if ($folder) {
        Write-OK "Found BOB2 at: $folder"
        if (Validate-GameFolder $folder) {
            Write-OK "Game installation validated"
            return $folder
        } else {
            Write-Warn "Folder found but may not be a complete installation"
        }
    }

    Write-Info "Could not auto-detect BOB2 installation."
    if ($script:NonInteractive) {
        throw "NEEDS-ANSWER: Could not find your Battle of Britain II folder. Put the BOB2-Win11-Fix folder next to Bob.exe, or set the folder in Settings."
    }
    Write-Host ""
    Write-Host "  Enter your BOB2 game folder path: " -ForegroundColor Yellow -NoNewline
    $manualPath = Read-Host

    if (-not $manualPath -or -not (Test-Path $manualPath)) {
        Write-Err "Path does not exist: $manualPath"
        return $null
    }

    if (-not (Test-Path (Join-Path $manualPath "Bob.exe"))) {
        Write-Err "Bob.exe not found in: $manualPath"
        Write-Info "Make sure this is your BOB2 game folder (where Bob.exe is located)"
        return $null
    }

    Write-OK "Game folder set to: $manualPath"
    return $manualPath
}

function Step-CheckVersion {
    param([string]$GameFolder)

    Write-Step "Step 2: Check Current Version"

    $version = Get-BobVersion $GameFolder
    Write-Info "Current Bob.exe version: $version"

    $verFile = Join-Path $GameFolder "bob2_ver.txt"
    if (Test-Path $verFile) {
        $verContent = (Get-Content $verFile -Raw).Trim()
        Write-Info "bob2_ver.txt says: $verContent"
    }

    return $version
}

function Step-ApplyV212 {
    param([string]$GameFolder, [string]$CurrentVersion)

    Write-Step "Step 3: Apply v2.12 Patch"

    if ($CurrentVersion -eq "2.12" -or $CurrentVersion -eq "2.13") {
        Write-OK "Already at v$CurrentVersion - skipping v2.12 patch"
        return $true
    }

    # Look for the patch EXE (self-extracting installer)
    $patchExe = Find-PatchFile "bob2_update_v2.12.EXE" $GameFolder
    if (-not $patchExe) {
        $patchExe = Find-PatchFileByPattern "bob2_update_v2.12*" $GameFolder
    }

    if (-not $patchExe) {
        Write-Warn "bob2_update_v2.12.EXE not found"
        Write-Info "Please download the v2.12 update from the A2A Simulations forum"
        Write-Info "and place it in the BOB2-Win11-Fix folder"
        Pause-WithPrompt "Place bob2_update_v2.12.EXE in the BOB2-Win11-Fix folder, then continue"

        $patchExe = Find-PatchFile "bob2_update_v2.12.EXE" $GameFolder
        if (-not $patchExe) {
            $patchExe = Find-PatchFileByPattern "bob2_update_v2.12*" $GameFolder
        }
        if (-not $patchExe) {
            Write-Err "Patch still not found. Skipping v2.12 update."
            return $false
        }
    }

    Write-Info "Found patch: $patchExe"

    # Backup current Bob.exe
    $bobExe = Join-Path $GameFolder "Bob.exe"
    $backup = Join-Path $GameFolder "Bob.exe.v206"
    if (-not (Test-Path $backup)) {
        Copy-Item $bobExe $backup
        Write-OK "Backed up Bob.exe as Bob.exe.v206"
    } else {
        Write-OK "Bob.exe.v206 backup already exists"
    }

    # Run the patch installer
    Write-Info "Running v2.12 patch installer..."
    Write-Info "Follow the installer prompts - point it to: $GameFolder"
    try {
        $proc = Start-Process -FilePath $patchExe -WorkingDirectory $GameFolder -PassThru -Wait
        if ($proc.ExitCode -ne 0) {
            Write-Warn "Installer exited with code $($proc.ExitCode)"
        }
        Write-OK "v2.12 patch installer completed"
    } catch {
        Write-Err "Failed to run patch installer: $_"
        return $false
    }

    # Patching replaced Bob.exe, so any Bob.exe.unscaled kept beside it is now
    # a copy of the PREVIOUS GAME VERSION. Left in place it becomes a downgrade
    # waiting to happen: the menu rescale patches "the pristine original", and
    # uninstall restores it. Drop it so the next rescale takes a fresh one from
    # the newly patched executable.
    $unscaled = Join-Path $GameFolder "Bob.exe.unscaled"
    if (Test-Path $unscaled) {
        Remove-Item $unscaled -Force -ErrorAction SilentlyContinue
        Write-Info "Removed the old Bob.exe.unscaled - it was from the previous game version."
    }

    # Verify
    $newVersion = Get-BobVersion $GameFolder
    Write-Info "Bob.exe version after patching: $newVersion"

    return $true
}

function Step-ApplyMultiSkin {
    param([string]$GameFolder)

    Write-Step "Step 4: Apply MultiSkin v2.12"

    # Check if already installed
    $multiSkinFolder = Join-Path $GameFolder "MultiSkin"
    if (Test-Path $multiSkinFolder) {
        Write-OK "MultiSkin folder already exists - may already be installed"
        # Pressing Fix IS the yes. Re-asking on an invisible console would
        # abort the very thing the user just clicked.
        $goAhead = if ($script:NonInteractive) { $true } else { Get-YesNo "Re-apply MultiSkin patch?" }
        if (-not $goAhead) {
            return $true
        }
    }

    # Look for the MultiSkin patch EXE (self-extracting installer)
    $patchExe = Find-PatchFile "multiskin_v212.EXE" $GameFolder
    if (-not $patchExe) {
        $patchExe = Find-PatchFileByPattern "multiskin_v212*" $GameFolder
    }

    if (-not $patchExe) {
        Write-Warn "multiskin_v212.EXE not found"
        Write-Info "Please download MultiSkin v2.12 from the A2A Simulations forum"
        Write-Info "and place it in the BOB2-Win11-Fix folder"
        Pause-WithPrompt "Place multiskin_v212.EXE in the BOB2-Win11-Fix folder, then continue"

        $patchExe = Find-PatchFile "multiskin_v212.EXE" $GameFolder
        if (-not $patchExe) {
            $patchExe = Find-PatchFileByPattern "multiskin_v212*" $GameFolder
        }
        if (-not $patchExe) {
            Write-Err "Patch not found. Skipping MultiSkin."
            return $false
        }
    }

    Write-Info "Found patch: $patchExe"
    Write-Info "Running MultiSkin installer..."
    Write-Info "Follow the installer prompts - point it to: $GameFolder"
    try {
        $proc = Start-Process -FilePath $patchExe -WorkingDirectory $GameFolder -PassThru -Wait
        if ($proc.ExitCode -ne 0) {
            Write-Warn "Installer exited with code $($proc.ExitCode)"
        }
        Write-OK "MultiSkin v2.12 installed successfully"
    } catch {
        Write-Err "Failed to run MultiSkin installer: $_"
        return $false
    }

    return $true
}

function Step-ApplyV213 {
    param([string]$GameFolder, [switch]$SkipConfirm)

    Write-Step "Apply BDG v2.13"

    $currentVersion = Get-BobVersion $GameFolder
    if ($currentVersion -eq "2.13") {
        Write-OK "Already at v2.13"
        return $true
    }

    if (-not $SkipConfirm) {
        $goAhead = if ($script:NonInteractive) { $true } else { Get-YesNo "Apply BDG v2.13 update? (Recommended - fixes widescreen menus)" }
        if (-not $goAhead) {
            Write-Info "Skipping v2.13 update"
            return $true
        }
    }

    # Look for v2.13 patch - try EXE installer first, then .7z
    # Filenames can have spaces or underscores
    $patchFile = $null
    $patchIsExe = $false

    # Search for EXE installer (preferred)
    $exeNames = @("BDG v2.13.exe", "BDG_v2.13.exe")
    foreach ($name in $exeNames) {
        $patchFile = Find-PatchFile $name $GameFolder
        if ($patchFile) { $patchIsExe = $true; break }
    }

    # Search by pattern if exact names not found
    if (-not $patchFile) {
        $patchFile = Find-PatchFileByPattern "BDG*v2.13*.exe" $GameFolder
        if ($patchFile) { $patchIsExe = $true }
    }

    # Fall back to .7z
    if (-not $patchFile) {
        $sevenZNames = @("BDG v2.13.7z", "BDG_v2.13.7z")
        foreach ($name in $sevenZNames) {
            $patchFile = Find-PatchFile $name $GameFolder
            if ($patchFile) { break }
        }
    }
    if (-not $patchFile) {
        $patchFile = Find-PatchFileByPattern "BDG*v2.13*.7z" $GameFolder
    }

    if (-not $patchFile) {
        Write-Warn "BDG v2.13 patch not found (looked for .exe and .7z)"
        Write-Info "Please download the BDG v2.13 patch from the A2A Simulations forum"
        Write-Info "and place it in the BOB2-Win11-Fix folder"
        Pause-WithPrompt "Place BDG v2.13 patch in the BOB2-Win11-Fix folder, then continue"

        # Retry search
        foreach ($name in $exeNames) {
            $patchFile = Find-PatchFile $name $GameFolder
            if ($patchFile) { $patchIsExe = $true; break }
        }
        if (-not $patchFile) {
            $patchFile = Find-PatchFileByPattern "BDG*v2.13*" $GameFolder
            if ($patchFile -and $patchFile -match '\.exe$') { $patchIsExe = $true }
        }
        if (-not $patchFile) {
            Write-Err "Patch not found. Skipping v2.13."
            return $false
        }
    }

    Write-Info "Found patch: $patchFile"

    # Backup current Bob.exe
    $bobExe = Join-Path $GameFolder "Bob.exe"
    $backup = Join-Path $GameFolder "Bob.exe.v212"
    if (-not (Test-Path $backup)) {
        Copy-Item $bobExe $backup
        Write-OK "Backed up Bob.exe as Bob.exe.v212"
    } else {
        Write-OK "Bob.exe.v212 backup already exists"
    }

    if ($patchIsExe) {
        # Run the EXE installer
        Write-Info "Running v2.13 patch installer..."
        Write-Info "Follow the installer prompts - point it to: $GameFolder"
        try {
            $proc = Start-Process -FilePath $patchFile -WorkingDirectory $GameFolder -PassThru -Wait
            if ($proc.ExitCode -ne 0) {
                Write-Warn "Installer exited with code $($proc.ExitCode)"
            }
            Write-OK "v2.13 patch installer completed"
        } catch {
            Write-Err "Failed to run patch installer: $_"
            return $false
        }
    } else {
        # Extract .7z file
        $sevenZip = Join-Path $ScriptDir "7za.exe"
        if (-not (Test-Path $sevenZip)) {
            $sevenZip = Join-Path $GameFolder "7za.exe"
        }
        if (-not (Test-Path $sevenZip)) {
            $sevenZip = Get-Command "7za.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        }
        if (-not $sevenZip -or -not (Test-Path $sevenZip)) {
            $sevenZip = Get-Command "7z.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        }

        if (-not $sevenZip -or -not (Test-Path $sevenZip)) {
            Write-Err "7za.exe not found. Cannot extract .7z files."
            Write-Info "Please place 7za.exe in the BOB2-Win11-Fix folder"
            Write-Info "Download from: https://www.7-zip.org/download.html (7-Zip Extra)"
            return $false
        }

        Write-Info "Extracting v2.13 patch..."
        try {
            $proc = Start-Process -FilePath $sevenZip -ArgumentList "x", "`"$patchFile`"", "-o`"$GameFolder`"", "-y" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Err "7-Zip extraction failed with exit code $($proc.ExitCode)"
                return $false
            }
            Write-OK "v2.13 patch extracted successfully"
        } catch {
            Write-Err "Failed to extract v2.13 patch: $_"
            return $false
        }
    }

    # Patching replaced Bob.exe, so any Bob.exe.unscaled kept beside it is now
    # a copy of the PREVIOUS GAME VERSION. Left in place it becomes a downgrade
    # waiting to happen: the menu rescale patches "the pristine original", and
    # uninstall restores it. Drop it so the next rescale takes a fresh one from
    # the newly patched executable.
    $unscaled = Join-Path $GameFolder "Bob.exe.unscaled"
    if (Test-Path $unscaled) {
        Remove-Item $unscaled -Force -ErrorAction SilentlyContinue
        Write-Info "Removed the old Bob.exe.unscaled - it was from the previous game version."
    }

    # Verify
    $newVersion = Get-BobVersion $GameFolder
    Write-Info "Bob.exe version after patching: $newVersion"

    return $true
}

function Step-InstallDgVoodoo2 {
    param([string]$GameFolder)

    Write-Step "Step 6: Install dgVoodoo2"

    # Check if already installed
    $existingDLLs = 0
    foreach ($dll in $DgVoodooDLLs) {
        if (Test-Path (Join-Path $GameFolder $dll)) { $existingDLLs++ }
    }
    if ($existingDLLs -eq $DgVoodooDLLs.Count) {
        # Present is not enough - the VERSION matters. 2.8.7.3 (shipped by
        # this mod up to v1.6.26) will not take exclusive fullscreen: the
        # 3D view renders into a corner of the screen. A user updating from
        # an old package still has those DLLs in the game folder, and
        # "already installed - leave them alone" kept the broken version
        # forever. Wrong version now reinstalls without asking.
        $curVer = ''
        try { $curVer = (Get-Item (Join-Path $GameFolder 'D3D9.dll')).VersionInfo.ProductVersion } catch { }
        if ($curVer -ne '2.8.6.5') {
            Write-Warn "dgVoodoo2 $curVer is installed - 2.8.6.5 is required (2.8.7.x breaks fullscreen). Replacing."
            $reinstall = $true
        } else {
            Write-OK "dgVoodoo2 2.8.6.5 already installed"
            $reinstall = if ($script:NonInteractive) { $false } else { Get-YesNo "Re-install dgVoodoo2 files?" }
        }
        if (-not $reinstall) {
            # Ensure config exists AND carries the two load-bearing lines.
            # dgVoodooCpl rewrites this file with plain defaults if a user
            # ever points it at the game folder and presses Apply - the DLLs
            # then look fine while scaling and forced resolution are gone
            # (low-res 3D in a black border). Content is checked, not just
            # presence.
            $confPath = Join-Path $GameFolder "dgVoodoo.conf"
            $confOk = $false
            if (Test-Path $confPath) {
                $confTxt = Get-Content $confPath -Raw
                $confOk = ($confTxt -match 'ScalingMode\s*=\s*stretched_ar') -and ($confTxt -match 'Resolution\s*=\s*max') -and ($confTxt -match 'VRAM\s*=\s*4096')
            }
            if (-not $confOk) {
                if (Test-Path $confPath) {
                    Copy-Item $confPath ($confPath + '.bad-backup') -Force
                    Write-Warn "dgVoodoo.conf was missing the recommended scaling/resolution settings - rewriting (old file kept as .bad-backup)"
                }
                Set-Content -Path $confPath -Value $DgVoodooConf -Encoding ASCII
                Write-OK "Created dgVoodoo.conf with recommended settings"
            }
            return $true
        }
    }

    # Look for dgVoodoo2 folder (already extracted)
    $dgFolderNames = @(
        # dgv2865 is the copy THIS PACKAGE SHIPS, and the version MATTERS.
        #
        # We shipped 2.8.7.3 for several releases. On a DPI-scaled display it
        # will not take exclusive fullscreen: the game renders into a small
        # window in the corner of the screen. 2.8.6.5 does. Verified by A/B
        # test on one machine with every other variable held constant, and
        # it matches a working install that predates this package.
        #
        # Do not "update" this to a newer dgVoodoo without testing fullscreen
        # on a high-DPI display first.
        "dgv2865",
        "dgv2873",
        "dgVoodoo2_86_5",
        "dgVoodoo2_86",
        "dgVoodoo2",
        "dgvoodoo2_86_5",
        "dgvoodoo2"
    )

    $dgFolder = $null
    foreach ($name in $dgFolderNames) {
        $candidate = Join-Path $ScriptDir $name
        if (Test-Path $candidate) { $dgFolder = $candidate; break }
        $candidate = Join-Path $GameFolder $name
        if (Test-Path $candidate) { $dgFolder = $candidate; break }
        $candidate = Join-Path $GameFolder "BOB2-Win11-Fix\$name"
        if (Test-Path $candidate) { $dgFolder = $candidate; break }
    }

    # If no folder found, look for a dgVoodoo2 zip to extract
    if (-not $dgFolder) {
        $dgZip = Find-PatchFileByPattern "dgVoodoo2*.zip" $GameFolder
        if ($dgZip) {
            Write-Info "Found dgVoodoo2 zip: $dgZip"
            Write-Info "Extracting..."
            $extractTo = Join-Path $ScriptDir "dgVoodoo2"
            try {
                Expand-Archive -Path $dgZip -DestinationPath $extractTo -Force
                Write-OK "Extracted dgVoodoo2 to: $extractTo"

                # Check if the zip had a top-level folder inside it
                $subDirs = Get-ChildItem -Path $extractTo -Directory -ErrorAction SilentlyContinue
                if ($subDirs.Count -eq 1 -and (Test-Path (Join-Path $subDirs[0].FullName "MS"))) {
                    $dgFolder = $subDirs[0].FullName
                } else {
                    $dgFolder = $extractTo
                }
            } catch {
                Write-Err "Failed to extract dgVoodoo2 zip: $_"
            }
        }
    }

    if (-not $dgFolder) {
        Write-Warn "dgVoodoo2 not found (no folder or zip)"
        Write-Info "Please download dgVoodoo2 v2.86.5 from:"
        Write-Info "  http://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/"
        Write-Info "Place the zip file in the BOB2-Win11-Fix folder"
        Pause-WithPrompt "Place dgVoodoo2 zip in the BOB2-Win11-Fix folder, then continue"

        # Try again - check for zip first, then folders
        $dgZip = Find-PatchFileByPattern "dgVoodoo2*.zip" $GameFolder
        if ($dgZip) {
            $extractTo = Join-Path $ScriptDir "dgVoodoo2"
            try {
                Expand-Archive -Path $dgZip -DestinationPath $extractTo -Force
                $subDirs = Get-ChildItem -Path $extractTo -Directory -ErrorAction SilentlyContinue
                if ($subDirs.Count -eq 1 -and (Test-Path (Join-Path $subDirs[0].FullName "MS"))) {
                    $dgFolder = $subDirs[0].FullName
                } else {
                    $dgFolder = $extractTo
                }
            } catch {
                Write-Err "Failed to extract: $_"
            }
        }

        if (-not $dgFolder) {
            foreach ($name in $dgFolderNames) {
                $candidate = Join-Path $ScriptDir $name
                if (Test-Path $candidate) { $dgFolder = $candidate; break }
                $candidate = Join-Path $GameFolder $name
                if (Test-Path $candidate) { $dgFolder = $candidate; break }
            }
        }

        if (-not $dgFolder) {
            Write-Err "dgVoodoo2 still not found. Skipping."
            return $false
        }
    }

    Write-Info "Using dgVoodoo2 from: $dgFolder"

    # Find the x86 DLL folder
    $x86Folder = $null
    $candidates = @(
        (Join-Path $dgFolder "MS\x86"),
        (Join-Path $dgFolder "MS/x86"),
        (Join-Path $dgFolder "x86"),
        # A dgVoodoo2 zip nests its DLLs under MS\x86, but the copy WE SHIP
        # (dgv2865) keeps them at the top level. Without this the step found
        # the bundled folder and then failed on "could not find MS\x86".
        $dgFolder
    )
    # Test for an actual DLL rather than just the folder: a stray empty x86
    # directory would otherwise win and silently install nothing.
    foreach ($c in $candidates) {
        if ((Test-Path $c) -and (Test-Path (Join-Path $c 'D3D9.dll'))) { $x86Folder = $c; break }
    }

    if (-not $x86Folder) {
        Write-Err "Could not find MS\x86 folder inside dgVoodoo2 directory"
        Write-Info "Expected structure: dgVoodoo2_86_5\MS\x86\DDraw.dll etc."
        return $false
    }

    # Copy DLLs
    $allCopied = $true
    foreach ($dll in $DgVoodooDLLs) {
        $src = Join-Path $x86Folder $dll
        $dst = Join-Path $GameFolder $dll
        if (Test-Path $src) {
            Copy-Item $src $dst -Force
            Write-OK "Copied $dll"
        } else {
            Write-Warn "$dll not found in $x86Folder"
            $allCopied = $false
        }
    }

    # Copy dgVoodooCpl.exe
    $cplSrc = Join-Path $dgFolder "dgVoodooCpl.exe"
    $cplDst = Join-Path $GameFolder "dgVoodooCpl.exe"
    if (Test-Path $cplSrc) {
        Copy-Item $cplSrc $cplDst -Force
        Write-OK "Copied dgVoodooCpl.exe"
    } else {
        Write-Warn "dgVoodooCpl.exe not found in dgVoodoo2 folder"
    }

    # Create dgVoodoo.conf
    $confPath = Join-Path $GameFolder "dgVoodoo.conf"
    if (Test-Path $confPath) {
        $backupConf = Join-Path $GameFolder "dgVoodoo.conf.backup"
        if (-not (Test-Path $backupConf)) {
            Copy-Item $confPath $backupConf
            Write-OK "Backed up existing dgVoodoo.conf"
        }
    }
    # Detect monitor refresh rate and set FPS limit
    $fpsLimit = Get-MonitorRefreshRate
    $confContent = $DgVoodooConf -replace 'FPSLimit = 60', "FPSLimit = $fpsLimit"
    Set-Content -Path $confPath -Value $confContent -Encoding ASCII
    Write-OK "Created dgVoodoo.conf (FPS limit: $fpsLimit)"

    return $allCopied
}

function Step-ApplyCrashFix {
    param([string]$GameFolder)

    Write-Step "Step 7: Apply Windows 10/11 Crash Fix"

    # Copy dinput8.dll
    $srcDll = Join-Path $ScriptDir "dinput8.dll"
    $dstDll = Join-Path $GameFolder "dinput8.dll"

    if (-not (Test-Path $srcDll)) {
        Write-Err "dinput8.dll not found in: $ScriptDir"
        Write-Info "This file should be included with the BOB2-Win11-Fix package"
        return $false
    }

    # Backup existing dinput8.dll if it's not ours
    if (Test-Path $dstDll) {
        $srcSize = (Get-Item $srcDll).Length
        $dstSize = (Get-Item $dstDll).Length
        if ($srcSize -ne $dstSize) {
            $backupDll = Join-Path $GameFolder "dinput8.dll.original"
            if (-not (Test-Path $backupDll)) {
                Copy-Item $dstDll $backupDll
                Write-OK "Backed up existing dinput8.dll as dinput8.dll.original"
            }
        }
    }

    Copy-Item $srcDll $dstDll -Force
    Write-OK "Installed dinput8.dll crash guard (fix v$FixVersion)"

    # Remove Bob.exe.local if present
    $localFile = Join-Path $GameFolder "Bob.exe.local"
    if (Test-Path $localFile) {
        Remove-Item $localFile -Force
        Write-OK "Removed Bob.exe.local (was causing DLL conflicts)"
    }

    # Handle bdg.txt
    $bdgPath = Join-Path $GameFolder "bdg.txt"
    if (Test-Path $bdgPath) {
        # Backup
        $bdgBackup = Join-Path $GameFolder "bdg.txt.backup"
        if (-not (Test-Path $bdgBackup)) {
            Copy-Item $bdgPath $bdgBackup
            Write-OK "Backed up bdg.txt as bdg.txt.backup"
        }

        # Patch settings
        $content = Get-Content $bdgPath -Raw

        $replacements = @(
            @("SKIP_VIDEOS=OFF", "SKIP_VIDEOS=ON"),
            @("SKIP_QUICKVIDEOS=OFF", "SKIP_QUICKVIDEOS=ON"),
            @("INTRO_VIDEO=ON", "INTRO_VIDEO=OFF")
        )

        foreach ($r in $replacements) {
            $content = $content -replace [regex]::Escape($r[0]), $r[1]
        }

        Set-Content -Path $bdgPath -Value $content -NoNewline
        Write-OK "Patched bdg.txt: SKIP_VIDEOS=ON, SKIP_QUICKVIDEOS=ON, INTRO_VIDEO=OFF"

        # Apply recommended defaults.
        #
        # These are tuned for FRAME RATE, not maximum scenery. BOB2 is CPU-bound -
        # measured on a 13900HX / RTX 4080, the CPU spends ~3x longer per frame than
        # the GPU - and ground-object count is the dominant CPU cost. Shipping
        # OBJECT_DENSITY=4 (the maximum) as a "performance setting" was a bug in
        # earlier versions of this tool: it is the most expensive value, not the best.
        # Density 2 with the scenery generators off measured 28 -> 76 FPS median.
        # Raise them in the Settings Tweaker if you prefer scenery over frame rate.
        $recommended = @(
            @("OBJECT_DENSITY",               "OBJECT_DENSITY = 2"),
            @("PARTICLE_DENSITY",             "PARTICLE_DENSITY = 2"),
            @("UI_REFRESH",                   "UI_REFRESH = 120.000000"),
            @("PERIPHERAL_VISION_RANGE",      "PERIPHERAL_VISION_RANGE = 6000"),
            @("BOB_SMOOTHER_DEADZONE",        "BOB_SMOOTHER_DEADZONE=ON"),
            @("ENABLE_AUTO_GEN",              "ENABLE_AUTO_GEN=OFF"),
            @("ADD_SHEEP_COWS_AND_HAYSTACKS", "ADD_SHEEP_COWS_AND_HAYSTACKS=OFF")
        )

        $content = Get-Content $bdgPath -Raw
        $updated = 0
        $added = 0
        foreach ($setting in $recommended) {
            $key = $setting[0]
            $fullLine = $setting[1]
            # Anchor to line start: an unanchored match would also hit keys that
            # merely CONTAIN this name (e.g. OBJECT_DENSITY inside another key).
            $pattern = "(?m)^[ \t]*$key[ \t]*=[^\r\n]*"
            if ($content -match $pattern) {
                $content = $content -replace $pattern, $fullLine
                $updated++
            } else {
                # Key absent - append it rather than silently skipping.
                if ($content -notmatch "[\r\n]$") { $content += "`r`n" }
                $content += "$fullLine`r`n"
                $added++
            }
        }
        if ($updated -gt 0 -or $added -gt 0) {
            Set-Content -Path $bdgPath -Value $content -NoNewline
            Write-OK "Applied recommended settings ($updated updated, $added added)"
            Write-Info "  Tuned for frame rate: OBJECT_DENSITY=2, PARTICLE_DENSITY=2,"
            Write-Info "  auto-gen scenery and ground clutter OFF."
            Write-Info "  Use the Settings Tweaker to raise these for more scenery."
        }
    } else {
        # bdg.txt doesn't exist - create minimal one
        Write-Warn "bdg.txt not found (normal for fresh installs)"
        Write-Info "Creating minimal bdg.txt with critical settings..."
        Set-Content -Path $bdgPath -Value $MinimalBdgTxt -Encoding ASCII
        Write-OK "Created bdg.txt with video skip and performance settings"
        Write-Info "Note: The game will add its full settings on first launch"
    }

    Write-VersionStamp $GameFolder

    return $true
}

function Step-Win11Tweaks {
    param([string]$GameFolder)

    Write-Step "Step 8: Windows 11 Tweaks"

    $bobExe = Join-Path $GameFolder "Bob.exe"

    # --- Compatibility mode: Windows XP SP3 + Run as Administrator ---
    if (Test-Path $bobExe) {
        try {
            $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            # Deliberately WITH HIGHDPIAWARE. This used to omit it.
            #
            # That flag tells Windows "this program handles DPI itself, do not
            # scale it". BOB2 is from 2005 and does no such thing, so with the
            # flag set its menus are drawn at true pixel size. On a 2560-wide
            # display at 150% scaling that makes them roughly a third smaller
            # than intended, and it silently cancels out the menu rescale in
            # BOB2_MenuScale - the dialogs really are bigger, but Windows is no
            # longer magnifying them, so nothing appears to change.
            #
            # It is easy to acquire by accident: Properties > Compatibility >
            # "Change high DPI settings" > "Override high DPI scaling behaviour"
            # sets exactly this. So strip it rather than merely not adding it.
            $existing = $null
            try { $existing = (Get-ItemProperty -Path $regPath -Name $bobExe -ErrorAction SilentlyContinue).$bobExe } catch { }
            if ($existing -and $existing -match 'HIGHDPIAWARE') {
                Write-Warn "Bob.exe had HIGHDPIAWARE set - removing it."
                Write-Info "  It stops Windows scaling the game, which makes the menus"
                Write-Info "  small on a high-DPI display and defeats the menu rescale."
            }
            Set-ItemProperty -Path $regPath -Name $bobExe -Value "~ DWM8And16BitMitigation WINXPSP3 RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE"
            Write-OK "Set Bob.exe compatibility flags"

            # Silence the Windows Error Reporting DIALOG (reports are still
            # recorded). If the game ever crashes, WER otherwise pops its
            # "check for a solution" window minutes later - often straight
            # over the NEXT game session. The game runs exclusive
            # fullscreen; any window stealing focus makes it drop the
            # display device, show "Please do not Alt Tab", and frequently
            # crash again. One CTD was sabotaging every session after it.
            $werKey = "HKCU:\Software\Microsoft\Windows\Windows Error Reporting"
            if (-not (Test-Path $werKey)) { New-Item -Path $werKey -Force | Out-Null }
            Set-ItemProperty -Path $werKey -Name DontShowUI -Value 1 -Type DWord
            Write-OK "Crash-report dialogs silenced (crashes still logged, no popup over the game)"


            # Also set compatibility on bob2_config.EXE
            $configExe = Join-Path $GameFolder "bob2_config.EXE"
            if (Test-Path $configExe) {
                Set-ItemProperty -Path $regPath -Name $configExe -Value "~ WINXPSP3 RUNASADMIN"
                Write-OK "Set bob2_config.EXE: WinXP SP3 + Admin"
            }
        } catch {
            Write-Warn "Could not set compatibility mode automatically"
            Write-Info "  Right-click Bob.exe > Properties > Compatibility tab"
            Write-Info "  Check 'Run in compatibility mode for Windows XP (SP3)'"
            Write-Info "  Check 'Run this program as an administrator'"
            Write-Info "  Check 'Disable fullscreen optimizations'"
        }
    }

    # --- bdg.txt: Enable 2D gauges in autopilot ---
    $bdgPath = Join-Path $GameFolder "bdg.txt"
    if (Test-Path $bdgPath) {
        $content = Get-Content $bdgPath -Raw
        if ($content -match "Your_2dGauges_Work_In_Autopilot\s*=\s*OFF") {
            $content = $content -replace "Your_2dGauges_Work_In_Autopilot\s*=\s*OFF", "Your_2dGauges_Work_In_Autopilot=ON"
            Set-Content -Path $bdgPath -Value $content -NoNewline
            Write-OK "Enabled 2D gauges in autopilot mode"
        } elseif ($content -match "Your_2dGauges_Work_In_Autopilot\s*=\s*ON") {
            Write-OK "2D gauges in autopilot already enabled"
        } else {
            # Setting not present - append it
            Add-Content -Path $bdgPath -Value "`r`nYour_2dGauges_Work_In_Autopilot=ON"
            Write-OK "Added 2D gauges in autopilot setting"
        }
    }

    # --- bdg.txt: input tweak only ---
    #
    # This step used to also force ENABLE_AUTO_GEN=ON and
    # ADD_SHEEP_COWS_AND_HAYSTACKS=ON. Those are scenery generators, not Win11
    # compatibility fixes, and they add ground objects - the dominant CPU cost in a
    # CPU-bound engine. Bundling them into "Win11 tweaks" silently cost frame rate.
    # They are now left alone here and are set by the Settings Tweaker presets.
    # NOTE: a single-element array of arrays gets flattened by PowerShell, so
    # @( @("KEY","Label") ) becomes a 2-element array of STRINGS and $s[0] then
    # yields the first CHARACTER. The leading comma forces a real nested array.
    # (This produced "[OK] O already enabled" before it was caught.)
    $toggleSettings = @(
        ,@("BOB_SMOOTHER_DEADZONE", "Smoother deadzone")
    )
    if (Test-Path $bdgPath) {
        $content = Get-Content $bdgPath -Raw
        $changed = $false
        foreach ($s in $toggleSettings) {
            $key = $s[0]; $label = $s[1]
            # Anchored so a key name that merely contains this one is not matched.
            if ($content -match "(?m)^[ \t]*$key[ \t]*=[ \t]*OFF") {
                $content = $content -replace "(?m)^[ \t]*$key[ \t]*=[ \t]*OFF", "$key=ON"
                $changed = $true
                Write-OK "Enabled $label"
            } elseif ($content -match "(?m)^[ \t]*$key[ \t]*=[ \t]*ON") {
                Write-OK "$label already enabled"
            } else {
                if ($content -notmatch "[\r\n]$") { $content += "`r`n" }
                $content += "$key=ON`r`n"
                $changed = $true
                Write-OK "Added $label setting"
            }
        }
        if ($changed) {
            Set-Content -Path $bdgPath -Value $content -NoNewline
        }
    }

    # --- Remap Exit key: Alt+X (56+45) → End key (207) ---
    $keysPath = Join-Path $GameFolder "KEYBOARD\keys.txt"
    if (Test-Path $keysPath) {
        $keysContent = Get-Content $keysPath -Raw
        if ($keysContent -match "EXITKEY\s+56\+45") {
            $keysContent = $keysContent -replace "EXITKEY\s+56\+45", "EXITKEY 207"
            Set-Content -Path $keysPath -Value $keysContent -NoNewline
            Write-OK "Remapped Exit key: Alt+X -> End key (prevents accidental CTD)"
        } elseif ($keysContent -match "EXITKEY\s+207") {
            Write-OK "Exit key already remapped to End"
        } else {
            Write-Info "Exit key has custom mapping - not changed"
        }
    } else {
        Write-Warn "KEYBOARD\keys.txt not found - exit key not remapped"
    }
}

function Step-InstallLauncher {
    param([string]$GameFolder)
    Write-Step "Launcher and desktop shortcut"

    # The launcher is the front door: it is what enforces the ordering the
    # loose .bat files never could. Bob.exe rewrites bdg.txt and
    # settings.cfg on exit, so the launcher disables Settings while the
    # game is running rather than relying on the user remembering.
    $required = @('BOB2.bat', 'BOB2_Launcher.ps1')
    foreach ($f in $required) {
        if (-not (Test-Path (Join-Path $ScriptDir $f))) {
            Write-Err "$f is missing from the fix package - cannot install the launcher."
            return $false
        }
    }
    if (-not (Test-Path (Join-Path $ScriptDir 'assets\hu54418.jpg'))) {
        Write-Warn "assets\hu54418.jpg is missing - the launcher will run but with a plain background."
    }

    # The launcher finds Bob.exe by looking in its own folder and then the
    # parent, so running it from inside BOB2-Win11-Fix already works. There
    # is nothing to copy; what is missing is a way to FIND it.
    $target = Join-Path $ScriptDir 'BOB2.bat'
    Write-OK "Launcher present: $target"

    try {
        # GetFolderPath can return an empty string when the Desktop is
        # redirected (OneDrive) or the profile is not fully loaded. Join-Path
        # then fails with "Cannot bind argument to parameter 'Path'", which
        # is what turned a cosmetic shortcut into a visible error.
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not $desktop) { $desktop = [Environment]::GetFolderPath('DesktopDirectory') }
        if (-not $desktop -and $env:USERPROFILE) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
        if (-not $desktop -or -not (Test-Path $desktop)) {
            Write-Info "  No desktop folder found - skipping the shortcut. Run BOB2.bat from $ScriptDir instead."
            return $true
        }
        # The shortcut MUST NOT look like the game's own.
        #
        # It used to be called "Battle of Britain II" and borrowed Bob.exe's
        # icon, which made it pixel-identical to the shortcut the game
        # installer puts on the desktop. A tester reported "the sim loads up
        # directly, the launcher does not appear" - he was clicking the
        # game's shortcut and had no way to tell the two apart. Distinct
        # name, distinct icon (an RAF roundel we ship ourselves).
        $lnk = Join-Path $desktop 'Battle of Britain II - Modern Fix.lnk'

        # Remove the old ambiguous shortcut, but ONLY if it is ours - never
        # touch one that points at the game itself.
        $oldLnk = Join-Path $desktop 'Battle of Britain II.lnk'
        if (Test-Path $oldLnk) {
            try {
                $probe = (New-Object -ComObject WScript.Shell).CreateShortcut($oldLnk)
                if ($probe.TargetPath -eq $target) {
                    Remove-Item $oldLnk -Force
                    Write-Info "  Removed the old shortcut that looked like the game's own."
                }
            } catch { }
        }

        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = $target
        $sc.WorkingDirectory = $ScriptDir
        $sc.Description = 'Battle of Britain II - Modern Fix launcher (play, settings, FPS, wrapper, setup)'
        $ico = Join-Path $ScriptDir 'assets\BOB2ModernFix.ico'
        if (Test-Path $ico) {
            $sc.IconLocation = "$ico,0"
        } else {
            $bobExe = Join-Path $GameFolder 'Bob.exe'
            if (Test-Path $bobExe) { $sc.IconLocation = "$bobExe,0" }
        }
        $sc.Save()
        Write-OK "Desktop shortcut created: $lnk"
    }
    catch {
        Write-Warn "Could not create the desktop shortcut: $($_.Exception.Message)"
        Write-Info "Run BOB2.bat from $ScriptDir instead."
    }
    return $true
}

function Step-GPUReminder {
    Write-Step "Step 9: GPU Assignment"

    # Try to detect multiple GPUs
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
        if ($gpus.Count -gt 1) {
            Write-Warn "Multiple GPUs detected:"
            foreach ($gpu in $gpus) {
                Write-Info "  - $($gpu.Name)"
            }
            Write-Host ""
            Write-Info "BOB2 may default to your integrated GPU (poor performance)."
            Write-Info "To fix this:"
            Write-Info "  1. Open Windows Settings > System > Display > Graphics"
            Write-Info "  2. Click 'Browse' and select Bob.exe"
            Write-Info "  3. Click 'Options' and select 'High performance'"
            Write-Host ""
            # Never pop a Windows settings panel at a GUI user unasked.
            if ((-not $script:NonInteractive) -and (Get-YesNo "Open Windows Graphics Settings now?")) {
                try {
                    Start-Process "ms-settings:display-advancedgraphics"
                    Write-OK "Opened Windows Graphics Settings"
                    Write-Info "Add Bob.exe and set it to 'High performance'"
                } catch {
                    Write-Warn "Could not open Settings automatically"
                    Write-Info "Open manually: Settings > System > Display > Graphics"
                }
            }
        } else {
            Write-OK "Single GPU detected - no assignment needed"
        }
    } catch {
        Write-Info "Could not detect GPUs. If you have a laptop with dual graphics,"
        Write-Info "set Bob.exe to use your dedicated GPU in Windows Graphics Settings."
    }
}

function Step-Validate {
    param([string]$GameFolder)

    Write-Step "Step 10: Validation"

    $allGood = $true

    # Check Bob.exe
    $bobExe = Join-Path $GameFolder "Bob.exe"
    if (Test-Path $bobExe) {
        $version = Get-BobVersion $GameFolder
        Write-OK "Bob.exe present (version: $version)"
    } else {
        Write-Err "Bob.exe not found"
        $allGood = $false
    }

    # Check dgVoodoo2. Only D3D9.dll is load-bearing: BOB2 is a Direct3D 9 game
    # with no DirectDraw/D3D7 imports, so the other three are never loaded.
    # Without D3D9.dll the game fails at device creation and crashes.
    $dgCount = 0
    foreach ($dll in $DgVoodooDLLs) {
        if (Test-Path (Join-Path $GameFolder $dll)) { $dgCount++ }
    }
    if (Test-Path (Join-Path $GameFolder "D3D9.dll")) {
        Write-OK "dgVoodoo2 D3D9.dll installed (the wrapper DLL this game uses)"
        if ($dgCount -lt $DgVoodooDLLs.Count) {
            Write-Info "  $($DgVoodooDLLs.Count - $dgCount) of the other 3 DLLs absent - harmless, BOB2 never loads them"
        }
    } else {
        Write-Err "dgVoodoo2 D3D9.dll NOT installed - the game will crash on startup"
        $allGood = $false
    }

    # Check dgVoodoo.conf
    $confPath = Join-Path $GameFolder "dgVoodoo.conf"
    if (Test-Path $confPath) {
        Write-OK "dgVoodoo.conf present"
    } else {
        Write-Warn "dgVoodoo.conf not found"
    }

    # Check crash guard
    $crashGuard = Join-Path $GameFolder "dinput8.dll"
    if (Test-Path $crashGuard) {
        Write-OK "Crash guard (dinput8.dll) installed"
    } else {
        Write-Err "Crash guard (dinput8.dll) not installed"
        $allGood = $false
    }

    # Check bdg.txt
    $bdgPath = Join-Path $GameFolder "bdg.txt"
    if (Test-Path $bdgPath) {
        $bdgContent = Get-Content $bdgPath -Raw
        $videoOK = ($bdgContent -match "SKIP_VIDEOS=ON") -and ($bdgContent -match "INTRO_VIDEO=OFF")
        if ($videoOK) {
            Write-OK "bdg.txt video settings correct"
        } else {
            Write-Warn "bdg.txt video settings may not be correct"
            $allGood = $false
        }
    } else {
        Write-Warn "bdg.txt not found (will be created on first game launch)"
    }

    # Check for problematic files
    $localFile = Join-Path $GameFolder "Bob.exe.local"
    if (Test-Path $localFile) {
        Write-Warn "Bob.exe.local present (may cause DLL conflicts)"
        $allGood = $false
    }

    Write-Host ""
    if ($allGood) {
        Write-Host "  ========================================" -ForegroundColor Green
        Write-Host "  Installation looks good!" -ForegroundColor Green
        Write-Host "  ========================================" -ForegroundColor Green
    } else {
        Write-Host "  ========================================" -ForegroundColor Yellow
        Write-Host "  Some issues detected - see warnings above" -ForegroundColor Yellow
        Write-Host "  ========================================" -ForegroundColor Yellow
    }

    Write-Host ""
    # Launching the game from inside a repair step would be a surprise.
    if ((-not $script:NonInteractive) -and (Get-YesNo "Launch BOB2 for testing?")) {
        $bobExe = Join-Path $GameFolder "Bob.exe"
        Write-Info "Launching Bob.exe..."
        try {
            Start-Process -FilePath $bobExe -WorkingDirectory $GameFolder
            Write-OK "Game launched. Check for bob2guard.log after exiting to confirm crash guard is active."
        } catch {
            Write-Err "Failed to launch: $_"
        }
    }

    return $allGood
}

# ============================================================
# Check Installation Status
# ============================================================

function Show-Status {
    $gameFolder = Find-GameFolder
    if (-not $gameFolder) {
        Write-Host ""
        Write-Host "  Enter your BOB2 game folder path: " -ForegroundColor Yellow -NoNewline
        $gameFolder = Read-Host
    }

    if (-not $gameFolder -or -not (Test-Path (Join-Path $gameFolder "Bob.exe"))) {
        Write-Err "BOB2 installation not found"
        return
    }

    Write-Header "Installation Status Report"
    Write-Info "Game folder: $gameFolder"
    Write-Info "Setup tool:  fix v$FixVersion ($FixVersionDate)"
    Write-Host ""

    # --- Which fix version is actually deployed in the game folder? ---
    Write-Host "  Installed fix ver:   " -NoNewline
    $stampPath = Join-Path $gameFolder $StampFile
    $installedVer = $null
    if (Test-Path $stampPath) {
        $stamp = Get-Content $stampPath -Raw
        if ($stamp -match 'FixVersion\s*=\s*(\S+)') { $installedVer = $Matches[1] }
    }
    if (-not $installedVer) {
        Write-Host "unknown (installed before versioning)" -ForegroundColor Yellow
    } elseif ($installedVer -eq $FixVersion) {
        Write-Host "v$installedVer (current)" -ForegroundColor Green
    } else {
        Write-Host "v$installedVer (setup tool is v$FixVersion)" -ForegroundColor Yellow
    }

    # --- Is the deployed crash guard the same build we ship? ---
    Write-Host "  Crash guard build:   " -NoNewline
    $srcDll = Join-Path $ScriptDir "dinput8.dll"
    $dstDll = Join-Path $gameFolder "dinput8.dll"
    if (-not (Test-Path $dstDll)) {
        Write-Host "not installed" -ForegroundColor Red
    } elseif (-not (Test-Path $srcDll)) {
        Write-Host "installed (no package copy to compare)" -ForegroundColor Gray
    } elseif ((Get-FileMD5 $srcDll) -eq (Get-FileMD5 $dstDll)) {
        Write-Host "matches package" -ForegroundColor Green
    } else {
        Write-Host "STALE - differs from package copy" -ForegroundColor Yellow
        Write-Info "    Re-run the crash fix step to update it."
    }
    Write-Host ""

    # Version
    $version = Get-BobVersion $gameFolder
    Write-Host "  Bob.exe version:     " -NoNewline
    if ($version -match "2\.\d+") {
        Write-Host $version -ForegroundColor Green
    } else {
        Write-Host $version -ForegroundColor Yellow
    }

    # bob2_ver.txt
    $verFile = Join-Path $gameFolder "bob2_ver.txt"
    Write-Host "  bob2_ver.txt:        " -NoNewline
    if (Test-Path $verFile) {
        Write-Host (Get-Content $verFile -Raw).Trim() -ForegroundColor Green
    } else {
        Write-Host "not found" -ForegroundColor Yellow
    }

    # dgVoodoo2 - D3D9.dll is the only one that actually matters.
    # BOB2 imports d3d9.dll + d3dx9_3x.dll and has NO DirectDraw or D3D7 import,
    # so DDraw.dll / D3DImm.dll / D3D8.dll are never loaded by this game.
    $dgCount = 0
    foreach ($dll in $DgVoodooDLLs) {
        if (Test-Path (Join-Path $gameFolder $dll)) { $dgCount++ }
    }
    $d3d9Path = Join-Path $gameFolder "D3D9.dll"
    $hasD3D9 = Test-Path $d3d9Path

    Write-Host "  dgVoodoo2 wrapper:   " -NoNewline
    if ($hasD3D9) {
        # Report the actual wrapper build - a version mismatch matters more than a file count.
        $dgVer = ""
        try {
            $bytes = [System.IO.File]::ReadAllBytes($d3d9Path)
            $text = [System.Text.Encoding]::Unicode.GetString($bytes)
            $m = [regex]::Match($text, 'dgVoodoo\s+(\d+\.\d+\.\d+)')
            if ($m.Success) { $dgVer = " " + $m.Groups[1].Value }
        } catch {}
        Write-Host "D3D9.dll present$dgVer" -ForegroundColor Green
        Write-Host "                       " -NoNewline
        Write-Host "(the only wrapper DLL this game loads)" -ForegroundColor DarkGray
        $rsState = Get-ReShadeState $gameFolder
        Write-Host "  ReShade (optional):  " -NoNewline
        switch ($rsState) {
            "on"      { $p = Get-ReShadePreset $gameFolder; $lbl = "installed"; if ($p) { $lbl += " (preset: $p)" }; Write-Host $lbl -ForegroundColor Green }
            "off"     { Write-Host "installed but disabled" -ForegroundColor Yellow }
            "partial" { Write-Host "incomplete - run Install ReShade to repair" -ForegroundColor Yellow }
            default   { Write-Host "not installed (optional)" -ForegroundColor DarkGray }
        }
    } else {
        Write-Host "D3D9.dll MISSING - game will not start" -ForegroundColor Red
        Write-Info "  BOB2 is a Direct3D 9 game. Without dgVoodoo2's D3D9.dll it fails"
        Write-Info "  at device creation (D3DERR_INVALIDCALL) and crashes to desktop."
    }

    Write-Host "  other dgVoodoo DLLs: " -NoNewline
    $others = $dgCount - $(if ($hasD3D9) { 1 } else { 0 })
    Write-Host "$others of 3 present (inert - not used by BOB2)" -ForegroundColor DarkGray

    # dgVoodoo.conf
    Write-Host "  dgVoodoo.conf:       " -NoNewline
    $confPath = Join-Path $gameFolder "dgVoodoo.conf"
    if (Test-Path $confPath) {
        $confContent = Get-Content $confPath -Raw
        $apiMatch = [regex]::Match($confContent, "OutputAPI\s*=\s*(\S+)")
        if ($apiMatch.Success) {
            Write-Host "Present (API: $($apiMatch.Groups[1].Value))" -ForegroundColor Green
        } else {
            Write-Host "Present" -ForegroundColor Green
        }
    } else {
        Write-Host "Not found" -ForegroundColor Red
    }

    # Crash guard
    Write-Host "  Crash guard DLL:     " -NoNewline
    if (Test-Path (Join-Path $gameFolder "dinput8.dll")) {
        Write-Host "Installed" -ForegroundColor Green
    } else {
        Write-Host "Not installed" -ForegroundColor Red
    }

    # bdg.txt
    Write-Host "  bdg.txt:             " -NoNewline
    $bdgPath = Join-Path $gameFolder "bdg.txt"
    if (Test-Path $bdgPath) {
        $bdgContent = Get-Content $bdgPath -Raw
        $skipVids = $bdgContent -match "SKIP_VIDEOS=ON"
        $introOff = $bdgContent -match "INTRO_VIDEO=OFF"
        if ($skipVids -and $introOff) {
            Write-Host "Present, video fix applied" -ForegroundColor Green
        } else {
            Write-Host "Present, video fix NOT applied" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Not found" -ForegroundColor Yellow
    }

    # Backups
    Write-Host ""
    Write-Host "  Backups:" -ForegroundColor Cyan
    $backups = @("Bob.exe.v206", "Bob.exe.v212", "bdg.txt.backup", "dinput8.dll.original", "dgVoodoo.conf.backup")
    $foundBackup = $false
    foreach ($b in $backups) {
        if (Test-Path (Join-Path $gameFolder $b)) {
            Write-Info "  - $b"
            $foundBackup = $true
        }
    }
    if (-not $foundBackup) {
        Write-Info "  (none found)"
    }

    # Problematic files
    $localFile = Join-Path $gameFolder "Bob.exe.local"
    if (Test-Path $localFile) {
        Write-Host ""
        Write-Warn "Bob.exe.local exists - may cause DLL loading issues"
    }

    # Guard log
    $guardLog = Join-Path $gameFolder "bob2guard.log"
    if (Test-Path $guardLog) {
        Write-Host ""
        Write-Host "  Crash guard log:" -ForegroundColor Cyan
        $logContent = Get-Content $guardLog -Tail 5
        foreach ($line in $logContent) {
            Write-Info "  $line"
        }
    }
}

# ============================================================
# Uninstall
# ============================================================

# ============================================================
# Flight Training Module (W2). The Tiger Moth is complete on disk but was
# never registered; the 13 aircraft slots are hardcoded, so for a TRAINING
# SESSION the Hurricane1B line in models/model.idx is swapped for TigerMoth.acd
# (it must be a FLYABLE slot: the He 59 slot is compiled non-flyable and the
# game seats the player as a gunner regardless of the flight file)
# and a training quick.dat (stock missions + six EFTS exercises) goes in.
# The launcher restores both automatically when the game exits, on its next
# start if a swap went stale, and Install and repair is the third net.
# ============================================================
$TrainingMarkerName = 'BOB2-Win11-Fix.training'

function Test-TrainingActive {
    param([string]$GameFolder)
    Test-Path (Join-Path $GameFolder $TrainingMarkerName)
}

function Find-TrainingPayload {
    param([string]$GameFolder)
    foreach ($base in @($ScriptDir, (Join-Path $GameFolder 'BOB2-Win11-Fix'))) {
        $cand = Join-Path $base 'training'
        if (Test-Path (Join-Path $cand 'quick.training.dat')) { return $cand }
    }
    return $null
}

function Enable-TrainingModule {
    param([string]$GameFolder)
    if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) { Write-Warn 'Close the game first.'; return $false }
    if (Test-TrainingActive $GameFolder) { Write-OK 'Training module already active'; return $true }
    $payload = Find-TrainingPayload $GameFolder
    if (-not $payload) { Write-Warn 'Training payload not found (training\quick.training.dat).'; return $false }
    $idx = Join-Path $GameFolder 'models\model.idx'
    $qd  = Join-Path $GameFolder 'BFIELDS\quick.dat'
    $tm  = Join-Path $GameFolder 'models\TigerMoth.acd'
    foreach ($p in @($idx, $qd, $tm)) {
        if (-not (Test-Path $p)) { Write-Warn "Missing $p"; return $false }
    }
    # the gauge panel file is a hardcoded path the engine wants for a
    # flyable slot; write it once and leave it (harmless when not training)
    $gauges = Join-Path $GameFolder '2dGauges\TigerMoth_2dGauges.ini'
    if (-not (Test-Path $gauges)) {
        Copy-Item (Join-Path $payload 'TigerMoth_2dGauges.ini') $gauges
        Write-OK 'Installed TigerMoth_2dGauges.ini'
    }
    if (-not (Test-Path ($idx + '.stock-backup'))) { Copy-Item $idx ($idx + '.stock-backup') }
    # The hand-authored TigerMoth.acd points its 30 blrpt_* behaviour keys
    # at donor aircraft (fixed gear etc.). The engine destroys those donor
    # names when it rewrites the file after a session, so keep the pristine
    # copy and re-apply it at EVERY enable.
    if (-not (Test-Path ($tm + '.pristine'))) { Copy-Item $tm ($tm + '.pristine') }
    Copy-Item ($tm + '.pristine') $tm -Force
    Copy-Item $qd ($qd + '.training-backup') -Force   # current missions, restored on exit
    $txt = Get-Content $idx -Raw
    if ($txt -notmatch 'TigerMoth\.acd') {
        $txt = $txt -replace 'Hurricane1B\.acd', 'TigerMoth.acd'
        Set-Content -Path $idx -Value $txt -Encoding ASCII -NoNewline
        Write-OK 'model.idx: Hurricane Ib slot now flies the Tiger Moth'
    }
    Copy-Item (Join-Path $payload 'quick.training.dat') $qd -Force
    Write-OK 'Training missions installed (six EFTS exercises)'
    Set-Content -Path (Join-Path $GameFolder $TrainingMarkerName) -Value (Get-Date -Format s) -Encoding ASCII
    return $true
}

function Disable-TrainingModule {
    param([string]$GameFolder)
    if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) { Write-Warn 'Close the game first.'; return $false }
    $idx = Join-Path $GameFolder 'models\model.idx'
    $qd  = Join-Path $GameFolder 'BFIELDS\quick.dat'
    if (Test-Path ($idx + '.stock-backup')) {
        Copy-Item ($idx + '.stock-backup') $idx -Force
        Write-OK 'model.idx restored (Hurricane Ib back in its slot)'
    }
    if (Test-Path ($qd + '.training-backup')) {
        Copy-Item ($qd + '.training-backup') $qd -Force
        Write-OK 'Mission list restored'
    }
    $m = Join-Path $GameFolder $TrainingMarkerName
    if (Test-Path $m) { Remove-Item $m -Force }
    return $true
}

# ============================================================
# 1940 aircraft variants (W3). Value edits to .acd persist across the
# engine's per-run rewrite; blrpt_* donor edits (Jabo) do NOT and are
# re-applied before every launch via Sync-ActiveVariants, driven by the
# state file. State detection probes signature VALUES (the engine
# rewrites the files every run, so hashes are useless).
# ============================================================
$VariantStateFileName = 'BOB2-Win11-Fix.variants'
$VariantDefs = @(
    @{ Id='mk2';  Name='Spitfire Mk II';          Files=@('Spitfire1B.acd','Spitfire1B.acm'); Sig=@{File='Spitfire1B.acd'; On='^WeightEmpty 246300'; Off='^WeightEmpty 243800'} }
    @{ Id='e7';   Name='Bf 109E-7 extra fuel';    Files=@('Bf109E4.acd');  Sig=@{File='Bf109E4.acd';  On='^MaxIntFuel 50400';  Off='^MaxIntFuel 28800'} }
    @{ Id='d1';   Name='Bf 110D-1 extra fuel';    Files=@('Bf110C4.acd');  Sig=@{File='Bf110C4.acd';  On='^MaxIntFuel 166000'; Off='^MaxIntFuel 91400'} }
    @{ Id='jabo'; Name='Bf 109E-4/B Jabo (experimental)'; Files=@(); Sig=$null }
)

# --- known-good settings.cfg repair (shared: option 14 + launcher Play guard) ---
function Get-CurrentDisplayModeSafe {
    # The ACTUAL current display mode. Windows Forms bounds are DPI-scaled
    # (1920x1080 at 125% reads 1536x864; writing that would recreate the
    # exact invalid-mode bug this repairs), so ask the video controller.
    $w = 0; $h = 0; $hz = 60
    try {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction Stop |
              Where-Object { $_.CurrentHorizontalResolution -ge 800 } | Select-Object -First 1
        if ($vc) {
            $w = [int]$vc.CurrentHorizontalResolution
            $h = [int]$vc.CurrentVerticalResolution
            if ($vc.CurrentRefreshRate -ge 23) { $hz = [int]$vc.CurrentRefreshRate }
        }
    } catch { }
    if ($w -lt 800 -or $h -lt 600) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $w = [int]$scr.Width; $h = [int]$scr.Height
        } catch { }
    }
    if ($w -ge 800 -and $w -le 7680 -and $h -ge 600 -and $h -le 4320) {
        return @{ W = $w; H = $h; Hz = $hz }
    }
    $null
}
function Test-SettingsCfgHealthy {
    param([string]$GameFolder)
    # Healthy = the layout ChangeMode reads (int32 at offsets 1416/1480)
    # holds a plausible display mode. A missing file is left alone (the
    # game writes one); only an EXISTING implausible file is flagged.
    $p = Join-Path $GameFolder 'SAVEGAME\settings.cfg'
    if (-not (Test-Path $p)) { return @{ Exists = $false; Healthy = $true; Reason = 'no file' } }
    try {
        $b = [System.IO.File]::ReadAllBytes($p)
        if ($b.Length -ne 1786) { return @{ Exists = $true; Healthy = $false; Reason = "unexpected size $($b.Length) bytes" } }
        $w = [BitConverter]::ToInt32($b, 1416); $h = [BitConverter]::ToInt32($b, 1480)
        if ($w -lt 800 -or $w -gt 7680 -or $h -lt 600 -or $h -gt 4320) {
            return @{ Exists = $true; Healthy = $false; Reason = "stored mode reads ${w}x${h}" }
        }
        return @{ Exists = $true; Healthy = $true; Reason = "${w}x${h}" }
    } catch { return @{ Exists = $true; Healthy = $true; Reason = 'unreadable, left alone' } }
}
function Repair-KnownGoodSettings {
    param([string]$GameFolder)
    if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) {
        return @{ Ok = $false; Message = 'Close the game first. It rewrites settings.cfg on exit.' }
    }
    $kg = Join-Path $PSScriptRoot 'knowngood\settings.cfg'
    if (-not (Test-Path $kg)) { return @{ Ok = $false; Message = 'knowngood\settings.cfg is missing from the fix folder.' } }
    $bytes = [System.IO.File]::ReadAllBytes($kg)
    if ($bytes.Length -ne 1786) { return @{ Ok = $false; Message = "known-good file is $($bytes.Length) bytes, expected 1786. Not applying." } }
    $mode = Get-CurrentDisplayModeSafe
    $note = 'kept the known-good 1920x1080 @ 60'
    if ($mode) {
        [BitConverter]::GetBytes([int]$mode.W).CopyTo($bytes, 1416)
        [BitConverter]::GetBytes([int]$mode.H).CopyTo($bytes, 1480)
        [BitConverter]::GetBytes([int]$mode.Hz).CopyTo($bytes, 1544)
        $note = "resolution set to your display: $($mode.W)x$($mode.H) @ $($mode.Hz)"
    }
    $dir = Join-Path $GameFolder 'SAVEGAME'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dst = Join-Path $dir 'settings.cfg'
    if (Test-Path $dst) { Copy-Item $dst "$dst.before-knowngood" -Force }
    [System.IO.File]::WriteAllBytes($dst, $bytes)
    return @{ Ok = $true; Message = "Known-good settings.cfg installed, $note. The old file is kept as settings.cfg.before-knowngood." }
}

function Get-VariantStateFile { param([string]$GameFolder) Join-Path $GameFolder $VariantStateFileName }

function Get-ActiveVariantIds {
    param([string]$GameFolder)
    $sf = Get-VariantStateFile $GameFolder
    if (Test-Path $sf) { @(Get-Content $sf | Where-Object { $_ -match '\S' }) } else { @() }
}

function Set-VariantActive {
    param([string]$GameFolder, [string]$Id, [bool]$Active)
    $ids = @(Get-ActiveVariantIds $GameFolder | Where-Object { $_ -ne $Id })
    if ($Active) { $ids += $Id }
    $sf = Get-VariantStateFile $GameFolder
    if ($ids.Count) { Set-Content -Path $sf -Value ($ids -join "`r`n") -Encoding ASCII }
    elseif (Test-Path $sf) { Remove-Item $sf -Force }
}

function Get-VariantState {
    # 'on', 'off', or 'unknown' (file readable but neither signature matches)
    param([string]$GameFolder, [string]$Id)
    $def = $VariantDefs | Where-Object { $_.Id -eq $Id }
    if (-not $def) { return 'unknown' }
    if ($Id -eq 'jabo') {
        if (@(Get-ActiveVariantIds $GameFolder) -contains 'jabo') { return 'on' } else { return 'off' }
    }
    $p = Join-Path $GameFolder ('models\' + $def.Sig.File)
    if (-not (Test-Path $p)) { return 'unknown' }
    if (Select-String -LiteralPath $p -Pattern $def.Sig.On  -Quiet) { return 'on' }
    if (Select-String -LiteralPath $p -Pattern $def.Sig.Off -Quiet) { return 'off' }
    return 'unknown'
}

function Find-VariantPayload {
    param([string]$GameFolder, [string]$Id)
    foreach ($base in @($ScriptDir, (Join-Path $GameFolder 'BOB2-Win11-Fix'))) {
        $cand = Join-Path (Join-Path $base 'variants') $Id
        if (Test-Path $cand) { return $cand }
    }
    return $null
}

function Set-JaboEdit {
    param([string]$GameFolder, [bool]$Enable)
    $p = Join-Path $GameFolder 'models\Bf109E4.acd'
    if (-not (Test-Path $p)) { return $false }
    $txt = Get-Content -LiteralPath $p -Raw
    $want = if ($Enable) { 'blrpt_FighterWithBomb "Ju87B2"' } else { 'blrpt_FighterWithBomb "Bf109E4"' }
    $new = $txt -replace 'blrpt_FighterWithBomb\s+"[^"]+"', $want
    if ($new -ne $txt) { Set-Content -LiteralPath $p -Value $new -Encoding ASCII -NoNewline }
    return $true
}

function Install-Variant {
    param([string]$GameFolder, [string]$Id)
    if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) { Write-Warn 'Close the game first.'; return $false }
    $def = $VariantDefs | Where-Object { $_.Id -eq $Id }
    if (-not $def) { return $false }
    if ($Id -eq 'jabo') {
        if (-not (Set-JaboEdit $GameFolder $true)) { return $false }
        Set-VariantActive $GameFolder 'jabo' $true
        Write-OK 'Jabo behaviour class applied (re-applied automatically before every launch while on)'
        return $true
    }
    $payload = Find-VariantPayload $GameFolder $Id
    if (-not $payload) { Write-Warn "Variant payload '$Id' not found."; return $false }
    foreach ($f in $def.Files) {
        $dst = Join-Path $GameFolder ('models\' + $f)
        if ((Test-Path $dst) -and -not (Test-Path ($dst + '.stock-backup'))) { Copy-Item $dst ($dst + '.stock-backup') }
        Copy-Item (Join-Path $payload $f) $dst -Force
        Write-OK "Installed $f"
    }
    if ($Id -eq 'mk2') {
        $curves = Join-Path $GameFolder 'models\curves.dat'
        if (-not (Test-Path ($curves + '.stock-backup'))) { Copy-Item $curves ($curves + '.stock-backup') }
        if (-not (Select-String -LiteralPath $curves -Pattern 'SPITFIRE2 PowerAlt' -Quiet)) {
            Add-Content -Path $curves -Value (Get-Content (Join-Path $payload 'curves-SPITFIRE2-append.txt') -Raw) -NoNewline
            Write-OK 'Added SPITFIRE2 PowerAlt curve'
        }
        # Coffman-starter cowling blister: a repainted main skin plus a DATED
        # MultiSkin rule, so in the campaign the blister appears from the
        # Mk II's historical introduction (12 August 1940). First match wins
        # in .ms files, so the rule goes at the very top.
        $skinSrc = Join-Path $payload 'Spit_MkII.dds'
        $texDir = Join-Path $GameFolder 'MultiSkin\MultiSkinTextures'
        $msFile = Join-Path $GameFolder 'MultiSkin\SpitMainSkin.ms'
        if ((Test-Path $skinSrc) -and (Test-Path $msFile)) {
            Copy-Item $skinSrc (Join-Path $texDir 'Spit_MkII.dds') -Force
            if (-not (Test-Path ($msFile + '.stock-backup'))) { Copy-Item $msFile ($msFile + '.stock-backup') }
            $ms = Get-Content $msFile -Raw
            if ($ms -notmatch 'Spit_MkII') {
                $rule = 'use MultiSkin\MultiSkinTextures\Spit_MkII.DDS if date >= Aug12th1940 	# Mk II Coffman blister - BOB2 Modern Fix variant'
                Set-Content -Path $msFile -Value ($rule + "`r`n" + $ms) -Encoding ASCII -NoNewline
                Write-OK 'Added dated Mk II skin rule (blister from 12 August 1940)'
            }
        }
    }
    Set-VariantActive $GameFolder $Id $true
    return $true
}

function Restore-Variant {
    param([string]$GameFolder, [string]$Id)
    if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) { Write-Warn 'Close the game first.'; return $false }
    $def = $VariantDefs | Where-Object { $_.Id -eq $Id }
    if (-not $def) { return $false }
    if ($Id -eq 'jabo') {
        Set-JaboEdit $GameFolder $false | Out-Null
        Set-VariantActive $GameFolder 'jabo' $false
        Write-OK 'Jabo behaviour class removed'
        return $true
    }
    foreach ($f in $def.Files) {
        $dst = Join-Path $GameFolder ('models\' + $f)
        if (Test-Path ($dst + '.stock-backup')) { Copy-Item ($dst + '.stock-backup') $dst -Force; Write-OK "Restored $f" }
    }
    if ($Id -eq 'mk2') {
        $msFile = Join-Path $GameFolder 'MultiSkin\SpitMainSkin.ms'
        if (Test-Path ($msFile + '.stock-backup')) {
            Copy-Item ($msFile + '.stock-backup') $msFile -Force
            Write-OK 'Restored stock Spitfire skin rules'
        }
        # the Spit_MkII.dds texture file is left in place: unreferenced once
        # the rule is gone, and deleting shared-folder files is riskier.
    }
    # the appended SPITFIRE2 curve block is left in curves.dat when Mk II is
    # restored: nothing references it once the .acm is stock, and removing
    # lines from a shared file is riskier than leaving an orphan curve.
    Set-VariantActive $GameFolder $Id $false
    return $true
}

function Sync-ActiveVariants {
    # Called by the launcher before every game start. Value variants
    # self-heal if a signature went missing; the Jabo blrpt edit MUST be
    # re-applied every time (the engine renames it back on every exit).
    param([string]$GameFolder)
    foreach ($id in (Get-ActiveVariantIds $GameFolder)) {
        if ($id -eq 'jabo') { Set-JaboEdit $GameFolder $true | Out-Null; continue }
        if ((Get-VariantState $GameFolder $id) -ne 'on') {
            $def = $VariantDefs | Where-Object { $_.Id -eq $id }
            $payload = Find-VariantPayload $GameFolder $id
            if ($def -and $payload) {
                foreach ($f in $def.Files) { Copy-Item (Join-Path $payload $f) (Join-Path $GameFolder ('models\' + $f)) -Force }
            }
        }
    }
}

function Get-ReShadeState {
    param([string]$GameFolder)
    # Returns: 'on', 'off' (disabled, files kept), 'partial', or 'none'
    $dll = Join-Path $GameFolder "dxgi.dll"
    $off = Join-Path $GameFolder "dxgi.dll.disabled"
    $ini = Join-Path $GameFolder "ReShade.ini"
    $sh  = Join-Path $GameFolder "reshade-shaders"
    $hasDll = (Test-Path $dll) -and ((Get-Item $dll).Length -eq $ReShadeDllSize)
    $hasOff = (Test-Path $off) -and ((Get-Item $off).Length -eq $ReShadeDllSize)
    $hasRest = (Test-Path $ini) -and (Test-Path $sh)
    if ($hasDll -and $hasRest) { return 'on' }
    if ($hasOff -and $hasRest) { return 'off' }
    if ($hasDll -or $hasOff -or (Test-Path $ini)) { return 'partial' }
    return 'none'
}

function Get-ReShadePreset {
    param([string]$GameFolder)
    $ini = Join-Path $GameFolder "ReShade.ini"
    if (-not (Test-Path $ini)) { return $null }
    $m = Select-String -Path $ini -Pattern '^PresetPath=.*BOB2-(\w+)\.ini' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return $null
}

function Step-InstallReShade {
    param([string]$GameFolder)
    Write-Step "Install ReShade (optional visual enhancement)"

    # ReShade hooks dgVoodoo2's D3D11 output; without dgVoodoo there is nothing to hook.
    $d3d9 = Join-Path $GameFolder "d3d9.dll"
    if (-not (Test-Path $d3d9)) {
        Write-Warn "dgVoodoo2 (d3d9.dll) is not installed. Install the graphics translator first."
        return $false
    }

    # A disabled install just needs re-enabling.
    $off = Join-Path $GameFolder "dxgi.dll.disabled"
    $dll = Join-Path $GameFolder "dxgi.dll"
    if ((Test-Path $off) -and -not (Test-Path $dll)) {
        Rename-Item $off "dxgi.dll"
        Write-OK "Re-enabled ReShade (dxgi.dll restored)"
    }

    # Locate the payload folder
    $payload = $null
    foreach ($base in @($ScriptDir, $GameFolder, (Join-Path $GameFolder "BOB2-Win11-Fix"))) {
        $cand = Join-Path $base "reshade"
        if (Test-Path (Join-Path $cand "dxgi.dll")) { $payload = $cand; break }
    }
    if (-not $payload) {
        Write-Warn "ReShade payload folder not found (looked for reshade\dxgi.dll beside the fix)."
        return $false
    }

    $ok = $true
    if (-not (Test-Path $dll)) {
        Copy-Item (Join-Path $payload "dxgi.dll") $dll
        Write-OK "Installed dxgi.dll (ReShade 6.8.0)"
    } elseif ((Get-Item $dll).Length -ne $ReShadeDllSize) {
        Write-Warn "A different dxgi.dll is already present. Leaving it strictly alone."
        return $false
    } else {
        Write-OK "dxgi.dll already present"
    }

    # Config and presets are user-tunable: never overwrite, only supply missing files.
    $ini = Join-Path $GameFolder "ReShade.ini"
    if (-not (Test-Path $ini)) {
        Copy-Item (Join-Path $payload "ReShade.ini") $ini
        Write-OK "Installed ReShade.ini (default preset: Balanced)"
    } else {
        Write-OK "ReShade.ini already present, keeping it"
    }
    foreach ($d in @("reshade-shaders", "reshade-presets", "reshade-screenshots")) {
        $dst = Join-Path $GameFolder $d
        if (-not (Test-Path $dst)) {
            Copy-Item (Join-Path $payload $d) $dst -Recurse
            Write-OK "Installed $d"
        } else {
            # supply any missing preset files without touching existing ones
            if ($d -eq "reshade-presets") {
                Get-ChildItem (Join-Path $payload $d) -Filter "BOB2-*.ini" | ForEach-Object {
                    $t = Join-Path $dst $_.Name
                    if (-not (Test-Path $t)) { Copy-Item $_.FullName $t; Write-OK "Added preset $($_.Name)" }
                }
            }
            Write-OK "$d already present"
        }
    }
    Write-Info "ReShade is active on the next launch. DEL opens the overlay, PgUp/PgDn switch presets."
    return $ok
}

function Step-RemoveReShade {
    param([string]$GameFolder)
    Write-Step "Remove ReShade"
    $bob = Get-Process -Name "Bob" -ErrorAction SilentlyContinue
    if ($bob) {
        Write-Warn "The game is running. Close it first."
        return $false
    }
    $dll = Join-Path $GameFolder "dxgi.dll"
    if ((Test-Path $dll) -and ((Get-Item $dll).Length -ne $ReShadeDllSize)) {
        Write-Warn "dxgi.dll is not the one this fix installed. Leaving all ReShade files alone."
        return $false
    }
    foreach ($item in ($ReShadeItems + @("dxgi.dll.disabled", "ReShade.log"))) {
        $p = Join-Path $GameFolder $item
        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force
            Write-OK "Removed $item"
        }
    }
    return $true
}

function Do-Uninstall {
    $gameFolder = Find-GameFolder
    if (-not $gameFolder) {
        if ($script:NonInteractive) {
            throw "NEEDS-ANSWER: Could not find your Battle of Britain II folder, so there is nothing to uninstall from."
        }
        Write-Host ""
        Write-Host "  Enter your BOB2 game folder path: " -ForegroundColor Yellow -NoNewline
        $gameFolder = Read-Host
    }

    if (-not $gameFolder -or -not (Test-Path (Join-Path $gameFolder "Bob.exe"))) {
        Write-Err "BOB2 installation not found"
        return
    }

    Write-Header "Uninstall Modifications"
    Write-Info "Game folder: $gameFolder"

    # The GUI already showed a Yes/No dialog listing exactly what this puts
    # back, and the user said yes. Asking again on a console nobody can see
    # would just abort the uninstall they asked for.
    $goAhead = if ($script:NonInteractive) { $true } else { Get-YesNo "Remove all modifications? (Backups will be restored if available)" }
    if (-not $goAhead) {
        Write-Info "Cancelled."
        return
    }

    # Remove crash guard DLL
    $crashGuard = Join-Path $gameFolder "dinput8.dll"
    if (Test-Path $crashGuard) {
        Remove-Item $crashGuard -Force
        Write-OK "Removed dinput8.dll (crash guard)"

        # Restore original if backed up
        $originalDll = Join-Path $gameFolder "dinput8.dll.original"
        if (Test-Path $originalDll) {
            Rename-Item $originalDll "dinput8.dll"
            Write-OK "Restored original dinput8.dll from backup"
        }
    }

    # Remove dgVoodoo2 files
    foreach ($dll in $DgVoodooDLLs) {
        $dllPath = Join-Path $gameFolder $dll
        if (Test-Path $dllPath) {
            Remove-Item $dllPath -Force
            Write-OK "Removed $dll"
        }
    }

    $dgFiles = @("dgVoodoo.conf", "dgVoodooCpl.exe")
    foreach ($f in $dgFiles) {
        $fPath = Join-Path $gameFolder $f
        if (Test-Path $fPath) {
            Remove-Item $fPath -Force
            Write-OK "Removed $f"
        }
    }

    # Remove ReShade if this fix's build is present (size-checked inside)
    if ((Test-Path (Join-Path $gameFolder "dxgi.dll")) -or (Test-Path (Join-Path $gameFolder "dxgi.dll.disabled"))) {
        Step-RemoveReShade $gameFolder | Out-Null
    }

    # Restore dgVoodoo.conf backup
    $confBackup = Join-Path $gameFolder "dgVoodoo.conf.backup"
    if (Test-Path $confBackup) {
        Rename-Item $confBackup "dgVoodoo.conf"
        Write-OK "Restored dgVoodoo.conf from backup"
    }

    # Restore bdg.txt
    $bdgBackup = Join-Path $gameFolder "bdg.txt.backup"
    if (Test-Path $bdgBackup) {
        $bdgPath = Join-Path $gameFolder "bdg.txt"
        Copy-Item $bdgBackup $bdgPath -Force
        Write-OK "Restored bdg.txt from backup"
    }

    # Restore Bob.exe.
    #
    # ONLY undo what THIS MOD did to it: the menu rescale and the DebugBreak
    # import fix. Bob.exe.unscaled is the pristine copy taken before either,
    # so restoring it returns the executable to how we found it.
    #
    # It used to restore Bob.exe.v212 or Bob.exe.v206 instead. Those are
    # backups of EARLIER GAME VERSIONS taken before applying a patch, so
    # "uninstall the fix" quietly became "downgrade the game to 2.12" -
    # undoing something the user asked for rather than something we imposed.
    # They are left alone; anyone who genuinely wants an older executable can
    # copy one back by hand.
    $bobExe = Join-Path $gameFolder "Bob.exe"
    $unscaled = Join-Path $gameFolder "Bob.exe.unscaled"
    if (Test-Path $unscaled) {
        Copy-Item $unscaled $bobExe -Force
        Remove-Item $unscaled -Force -ErrorAction SilentlyContinue
        Write-OK "Restored Bob.exe from Bob.exe.unscaled (menu rescale and crash fix removed)"
    } else {
        Write-Info "No Bob.exe.unscaled found - Bob.exe left as-is"
    }

    $stale = @("Bob.exe.v212", "Bob.exe.v206") | Where-Object { Test-Path (Join-Path $gameFolder $_) }
    if ($stale) {
        Write-Info "Left in place: $($stale -join ', ') - older GAME versions, not part of this fix."
    }

    # Remove Bob.exe.local
    $localFile = Join-Path $gameFolder "Bob.exe.local"
    if (Test-Path $localFile) {
        Remove-Item $localFile -Force
        Write-OK "Removed Bob.exe.local"
    }

    # Remove version stamp
    $stampPath = Join-Path $gameFolder $StampFile
    if (Test-Path $stampPath) {
        Remove-Item $stampPath -Force
        Write-OK "Removed $StampFile"
    }

    # Remove guard log
    $guardLog = Join-Path $gameFolder "bob2guard.log"
    if (Test-Path $guardLog) {
        Remove-Item $guardLog -Force
        Write-OK "Removed bob2guard.log"
    }

    # Remove compatibility mode registry entries
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
        if (Test-Path $regPath) {
            $bobExe = Join-Path $gameFolder "Bob.exe"
            $configExe = Join-Path $gameFolder "bob2_config.EXE"
            foreach ($exe in @($bobExe, $configExe)) {
                $val = Get-ItemProperty -Path $regPath -Name $exe -ErrorAction SilentlyContinue
                if ($val) {
                    Remove-ItemProperty -Path $regPath -Name $exe -ErrorAction SilentlyContinue
                    Write-OK "Removed compatibility settings for $(Split-Path $exe -Leaf)"
                }
            }
        }
    } catch {}

    # Restore exit key to Alt+X
    $keysPath = Join-Path $gameFolder "KEYBOARD\keys.txt"
    if (Test-Path $keysPath) {
        $keysContent = Get-Content $keysPath -Raw
        if ($keysContent -match "EXITKEY\s+207") {
            $keysContent = $keysContent -replace "EXITKEY\s+207", "EXITKEY 56+45"
            Set-Content -Path $keysPath -Value $keysContent -NoNewline
            Write-OK "Restored exit key to Alt+X"
        }
    }

    Write-Host ""
    Write-OK "Uninstall complete. Backup files have been preserved."
    Write-Info "You can manually delete .v206, .v212, .backup files if no longer needed."
}

# ============================================================
# Settings Tweaker
# ============================================================

function Get-IniValue {
    param([string]$Content, [string]$Section, [string]$Key)
    if ($Content -match "(?ms)\[$Section\].*?$Key\s*=\s*([^\r\n]+)") {
        return $Matches[1].Trim()
    }
    return $null
}

function Set-IniValue {
    param([string]$FilePath, [string]$Key, [string]$Value, [string]$Section)
    $content = Get-Content $FilePath -Raw
    if ($Section) {
        # dgVoodoo.conf reuses key names across sections (e.g. Resolution in
        # both [Glide] and [DirectX]) - only touch the key inside [$Section]
        $pattern = "(?ms)(\[$Section\][^\[]*?^[ \t]*$Key[ \t]*=[ \t]*)[^\r\n]*"
        if ($content -match $pattern) {
            $content = $content -replace $pattern, "`${1}$Value"
            Set-Content -Path $FilePath -Value $content -NoNewline
        }
    } elseif ($content -match "(?m)^[ \t]*$Key[ \t]*=") {
        $content = $content -replace "(?m)(^[ \t]*$Key[ \t]*=[ \t]*)[^\r\n]*", "`${1}$Value"
        Set-Content -Path $FilePath -Value $content -NoNewline
    }
}

function Get-BdgValue {
    param([string]$Content, [string]$Key)
    if ($Content -match "$Key\s*=\s*([^\r\n]+)") {
        return $Matches[1].Trim()
    }
    return $null
}

function Show-PickList {
    param([string]$Label, [string]$Current, [string[]]$Options)
    Write-Host ""
    Write-Host "  $Label (current: $Current)" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = ""
        if ($Options[$i] -eq $Current) { $marker = " <--" }
        Write-Host "    $($i+1). $($Options[$i])$marker" -ForegroundColor White
    }
    Write-Host "    0. Keep current" -ForegroundColor DarkGray
    Write-Host "  Choice: " -ForegroundColor Yellow -NoNewline
    $pick = Read-Host
    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $Options.Count) {
        return $Options[[int]$pick - 1]
    }
    return $null
}

function Do-Settings {
    $gameFolder = Find-GameFolder
    if (-not $gameFolder) {
        Write-Host ""
        Write-Host "  Enter your BOB2 game folder path: " -ForegroundColor Yellow -NoNewline
        $gameFolder = Read-Host
    }

    if (-not $gameFolder -or -not (Test-Path (Join-Path $gameFolder "Bob.exe"))) {
        Write-Err "BOB2 installation not found"
        return
    }

    $confPath = Join-Path $gameFolder "dgVoodoo.conf"
    $bdgPath = Join-Path $gameFolder "bdg.txt"

    $hasConf = Test-Path $confPath
    $hasBdg = Test-Path $bdgPath

    if (-not $hasConf -and -not $hasBdg) {
        Write-Err "No configuration files found in: $gameFolder"
        return
    }

    while ($true) {
        Write-Header "Settings Tweaker"
        Write-Info "Game folder: $gameFolder"
        Write-Host ""

        # Read current values
        $confContent = ""
        $bdgContent = ""
        if ($hasConf) { $confContent = Get-Content $confPath -Raw }
        if ($hasBdg) { $bdgContent = Get-Content $bdgPath -Raw }

        # Display current settings
        Write-Host "  --- dgVoodoo2 (Graphics Wrapper) ---" -ForegroundColor Cyan
        if ($hasConf) {
            $fpsLimit = Get-IniValue $confContent "GeneralExt" "FPSLimit"
            $resolution = Get-IniValue $confContent "DirectX" "Resolution"
            $scalingMode = Get-IniValue $confContent "General" "ScalingMode"
            $vsync = Get-IniValue $confContent "DirectX" "ForceVerticalSync"
            $filtering = Get-IniValue $confContent "DirectX" "Filtering"
            $aa = Get-IniValue $confContent "DirectX" "Antialiasing"
            $watermark = Get-IniValue $confContent "DirectX" "dgVoodooWatermark"

            Write-Host "  1. FPS Limit:         $fpsLimit" -ForegroundColor White
            Write-Host "  2. Resolution:        $resolution" -ForegroundColor White
            Write-Host "  3. Scaling Mode:      $scalingMode" -ForegroundColor White
            Write-Host "  4. VSync:             $vsync" -ForegroundColor White
            Write-Host "  5. Filtering:         $filtering" -ForegroundColor White
            Write-Host "  6. Antialiasing:      $aa" -ForegroundColor White
        } else {
            Write-Warn "dgVoodoo.conf not found"
        }

        Write-Host ""
        Write-Host "  --- Game Settings (bdg.txt) ---" -ForegroundColor Cyan
        if ($hasBdg) {
            $objDensity = Get-BdgValue $bdgContent "OBJECT_DENSITY"
            $partDensity = Get-BdgValue $bdgContent "PARTICLE_DENSITY"
            $uiRefresh = Get-BdgValue $bdgContent "UI_REFRESH"
            $periph = Get-BdgValue $bdgContent "PERIPHERAL_VISION_RANGE"
            $fovMin = Get-BdgValue $bdgContent "FOV_MINIMAL"
            $desktopRes = Get-BdgValue $bdgContent "USE_DESKTOP_RESOLUTION"
            $smoothFR = Get-BdgValue $bdgContent "SMOOTHEN_FRAMERATE_MODE"

            Write-Host "  7.  Object Density:       $objDensity" -ForegroundColor White
            Write-Host "  8.  Particle Density:     $partDensity" -ForegroundColor White
            Write-Host "  9.  UI Refresh Rate:      $uiRefresh" -ForegroundColor White
            Write-Host "  10. Vision Range:         $periph" -ForegroundColor White
            Write-Host "  11. Min FOV:              $fovMin" -ForegroundColor White
            Write-Host "  12. Desktop Resolution:   $desktopRes" -ForegroundColor White
            Write-Host "  13. Frame Smoothing:      $smoothFR" -ForegroundColor White
        } else {
            Write-Warn "bdg.txt not found"
        }
        Write-Host "  14. Reset graphics settings to the known-good file" -ForegroundColor White

        Write-Host ""
        Write-Host "  --- Presets ---" -ForegroundColor Cyan
        Write-Host "  P. Performance (max FPS)" -ForegroundColor White
        Write-Host "  Q. Quality (best visuals)" -ForegroundColor White
        Write-Host "  B. Balanced (recommended)" -ForegroundColor White
        Write-Host ""
        Write-Host "  0. Back to main menu" -ForegroundColor White
        Write-Host ""
        Write-Host "  Select setting to change (0-14, P/Q/B): " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "1" {
                $val = Show-PickList "FPS Limit" $fpsLimit @("0 (unlimited)", "60", "120", "144", "165", "240")
                if ($val) {
                    $val = ($val -split ' ')[0]  # strip description
                    Set-IniValue $confPath "FPSLimit" $val "GeneralExt"
                    Write-OK "FPS Limit set to $val"
                }
            }
            "2" {
                $val = Show-PickList "Resolution" $resolution @("max", "1920x1080", "2560x1440", "2560x1600", "3840x2160")
                if ($val) {
                    Set-IniValue $confPath "Resolution" $val "DirectX"
                    Write-OK "Resolution set to $val"
                }
            }
            "3" {
                $val = Show-PickList "Scaling Mode" $scalingMode @("stretched_ar", "stretched", "centered", "centered_ar")
                if ($val) {
                    Set-IniValue $confPath "ScalingMode" $val "General"
                    Write-OK "Scaling Mode set to $val"
                }
            }
            "4" {
                $val = Show-PickList "VSync" $vsync @("true", "false")
                if ($val) {
                    Set-IniValue $confPath "ForceVerticalSync" $val "DirectX"
                    Write-OK "VSync set to $val"
                }
            }
            "5" {
                $val = Show-PickList "Filtering" $filtering @("appdriven", "bilinear", "trilinear", "4", "8", "16")
                if ($val) {
                    Set-IniValue $confPath "Filtering" $val "DirectX"
                    Write-OK "Filtering set to $val"
                    if ($val -ne "appdriven") {
                        Write-Warn "Forced filtering may cause display issues in some menus"
                    }
                }
            }
            "6" {
                $val = Show-PickList "Antialiasing" $aa @("appdriven", "2x", "4x", "8x")
                if ($val) {
                    Set-IniValue $confPath "Antialiasing" $val "DirectX"
                    Write-OK "Antialiasing set to $val"
                    if ($val -ne "appdriven") {
                        Write-Warn "Forced AA WILL break the options menu! Use at own risk."
                    }
                }
            }
            "7" {
                $val = Show-PickList "Object Density" $objDensity @("1", "2", "3", "4")
                if ($val) {
                    Set-IniValue $bdgPath "OBJECT_DENSITY" $val
                    Write-OK "Object Density set to $val"
                }
            }
            "8" {
                $val = Show-PickList "Particle Density" $partDensity @("1", "2", "3", "4")
                if ($val) {
                    Set-IniValue $bdgPath "PARTICLE_DENSITY" $val
                    Write-OK "Particle Density set to $val"
                }
            }
            "9" {
                $val = Show-PickList "UI Refresh Rate" $uiRefresh @("60.000000", "120.000000", "144.000000", "165.000000", "240.000000")
                if ($val) {
                    Set-IniValue $bdgPath "UI_REFRESH" $val
                    Write-OK "UI Refresh set to $val"
                }
            }
            "10" {
                $val = Show-PickList "Peripheral Vision Range" $periph @("3000", "4000", "5000", "6000", "8000", "10000")
                if ($val) {
                    Set-IniValue $bdgPath "PERIPHERAL_VISION_RANGE" $val
                    Write-OK "Vision Range set to $val"
                }
            }
            "11" {
                $val = Show-PickList "Minimum FOV" $fovMin @("18.000000", "20.000000", "25.000000", "30.000000", "35.000000")
                if ($val) {
                    Set-IniValue $bdgPath "FOV_MINIMAL" $val
                    Write-OK "Min FOV set to $val"
                }
            }
            "12" {
                $val = Show-PickList "Use Desktop Resolution" $desktopRes @("ON", "OFF")
                if ($val) {
                    Set-IniValue $bdgPath "USE_DESKTOP_RESOLUTION" $val
                    Write-OK "Desktop Resolution set to $val"
                    if ($val -eq "ON") {
                        Write-Warn "ON is not recommended for widescreen monitors"
                    }
                }
            }
            "13" {
                $val = Show-PickList "Frame Smoothing" $smoothFR @("NONE", "VSYNC", "FPS")
                if ($val) {
                    Set-IniValue $bdgPath "SMOOTHEN_FRAMERATE_MODE" $val
                    Write-OK "Frame Smoothing set to $val"
                    if ($val -eq "NONE") {
                        Write-Info "Recommended - let dgVoodoo2 handle frame pacing"
                    }
                }
            }
            "14" {
                $r = Repair-KnownGoodSettings -GameFolder $gameFolder
                if ($r.Ok) { Write-OK $r.Message } else { Write-Warn $r.Message }
            }
            "P" {
                Write-Step "Applying Performance Preset"
                if ($hasConf) {
                    Set-IniValue $confPath "FPSLimit" "0" "GeneralExt"
                    Set-IniValue $confPath "ForceVerticalSync" "false" "DirectX"
                    Set-IniValue $confPath "Filtering" "appdriven" "DirectX"
                    Set-IniValue $confPath "Antialiasing" "appdriven" "DirectX"
                    Write-OK "dgVoodoo2: Unlimited FPS, VSync off, app-driven filtering/AA"
                }
                if ($hasBdg) {
                    Set-IniValue $bdgPath "OBJECT_DENSITY" "1"
                    Set-IniValue $bdgPath "PARTICLE_DENSITY" "1"
                    Set-IniValue $bdgPath "SMOOTHEN_FRAMERATE_MODE" "NONE"
                    Set-IniValue $bdgPath "PERIPHERAL_VISION_RANGE" "4000"
                    Set-IniValue $bdgPath "LANDSCAPE_TEXTURE_SIZE" "1024"
                    Set-IniValue $bdgPath "ENABLE_AUTO_GEN" "OFF"
                    Set-IniValue $bdgPath "ADD_SHEEP_COWS_AND_HAYSTACKS" "OFF"
                    Write-OK "Game: minimum density, no generated scenery, 1024 terrain textures"
                }
                Write-OK "Performance preset applied"
            }
            "Q" {
                Write-Step "Applying Quality Preset"
                if ($hasConf) {
                    Set-IniValue $confPath "FPSLimit" "60" "GeneralExt"
                    Set-IniValue $confPath "ForceVerticalSync" "true" "DirectX"
                    Set-IniValue $confPath "Filtering" "appdriven" "DirectX"
                    Set-IniValue $confPath "Antialiasing" "appdriven" "DirectX"
                    Write-OK "dgVoodoo2: 60 FPS cap, VSync on, app-driven filtering/AA"
                }
                if ($hasBdg) {
                    Set-IniValue $bdgPath "OBJECT_DENSITY" "4"
                    Set-IniValue $bdgPath "PARTICLE_DENSITY" "4"
                    Set-IniValue $bdgPath "SMOOTHEN_FRAMERATE_MODE" "NONE"
                    Set-IniValue $bdgPath "PERIPHERAL_VISION_RANGE" "8000"
                    Set-IniValue $bdgPath "ENABLE_AUTO_GEN" "ON"
                    Set-IniValue $bdgPath "ADD_SHEEP_COWS_AND_HAYSTACKS" "ON"
                    Write-OK "Game: Max density, generated scenery on, extended vision range"
                    Write-Warn "Density 4 is the biggest frame-rate cost in this engine."
                    Write-Info "  Expect roughly half the frame rate of the Balanced preset."
                }
                Write-OK "Quality preset applied"
            }
            "B" {
                Write-Step "Applying Balanced Preset"
                if ($hasConf) {
                    Set-IniValue $confPath "FPSLimit" "120" "GeneralExt"
                    Set-IniValue $confPath "ForceVerticalSync" "true" "DirectX"
                    Set-IniValue $confPath "Filtering" "appdriven" "DirectX"
                    Set-IniValue $confPath "Antialiasing" "appdriven" "DirectX"
                    Write-OK "dgVoodoo2: 120 FPS cap, VSync on, app-driven filtering/AA"
                }
                if ($hasBdg) {
                    Set-IniValue $bdgPath "OBJECT_DENSITY" "2"
                    Set-IniValue $bdgPath "PARTICLE_DENSITY" "2"
                    Set-IniValue $bdgPath "SMOOTHEN_FRAMERATE_MODE" "NONE"
                    Set-IniValue $bdgPath "PERIPHERAL_VISION_RANGE" "6000"
                    Set-IniValue $bdgPath "ENABLE_AUTO_GEN" "OFF"
                    Set-IniValue $bdgPath "ADD_SHEEP_COWS_AND_HAYSTACKS" "OFF"
                    Write-OK "Game: mid density, generated scenery off, good vision range"
                    Write-Info "  Measured 28 -> 76 FPS median vs the Quality preset's settings."
                }
                Write-OK "Balanced preset applied"
            }
            "0" { return }
            default { Write-Warn "Invalid option" }
        }

        Pause-Continue
    }
}

# ============================================================
# Full Install Flow
# ============================================================

function Do-FullInstall {
    Write-Header "Full Install"

    # Step 1: Find game
    $gameFolder = Step-DetectGame
    if (-not $gameFolder) {
        Write-Err "Cannot continue without a valid game folder."
        return
    }

    # Step 2: Check version
    $currentVersion = Step-CheckVersion $gameFolder

    # Step 3: Patch to v2.13.
    #
    # BDG's own v2.13 installation notes: "This update will bring *any* previous
    # version up to 2.13. You do not need any previous patches at all." MultiSkin
    # is included too. Earlier versions of this tool chained
    # 2.12 -> MultiSkin -> 2.13, which required ~500 MB of extra downloads and
    # achieved nothing. The 2.12 and MultiSkin steps remain available under
    # "Individual Steps" for anyone who specifically wants them.
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  Patching to v2.13" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Info "BDG v2.13 upgrades ANY earlier version directly and includes"
    Write-Info "MultiSkin, so the v2.12 and MultiSkin patches are not needed."
    Write-Host ""

    if ($currentVersion -eq "2.13") {
        Write-OK "Already at v2.13 - no patching needed"
    } else {
        Write-Warn "Before patching, note two things from BDG's release notes:"
        Write-Info "  - Campaigns from earlier versions will NOT load in 2.13."
        Write-Info "    After patching, clear the SAVEGAME folder except"
        Write-Info "    DIR.DIR, inputcfg.dat and settings.cfg."
        Write-Info "  - Windows text scaling should be 100% (96 DPI)."

        $result = Step-ApplyV213 $gameFolder -SkipConfirm
        if (-not $result) {
            Write-Warn "v2.13 step had issues, but continuing..."
            Write-Info "If you have the older patches, you can apply them from"
            Write-Info "the main menu under 'Individual Steps'."
        }
    }

    # Step 4: dgVoodoo2
    $result = Step-InstallDgVoodoo2 $gameFolder
    if (-not $result) {
        Write-Warn "dgVoodoo2 step had issues, but continuing..."
    }

    # Step 5: Crash fix
    $result = Step-ApplyCrashFix $gameFolder
    if (-not $result) {
        Write-Err "Crash fix installation failed."
    }

    # Step 6: Win11 tweaks
    Step-Win11Tweaks $gameFolder

    # Step 7: GPU
    Step-GPUReminder

    # Step 8: Launcher + desktop shortcut
    Step-InstallLauncher $gameFolder

    # Step 9: Validate
    Step-Validate $gameFolder

    Write-Host ""
    Write-Info "From now on, start the game with the 'Battle of Britain II'"
    Write-Info "shortcut on your desktop (or BOB2.bat in this folder)."
    Write-Info "Change settings from its Settings button, not the in-game"
    Write-Info "options screens - those clip off the right of the window."
}

# ============================================================
# Individual Steps
# ============================================================

function Do-IndividualSteps {
    $gameFolder = Step-DetectGame
    if (-not $gameFolder) {
        Write-Err "Cannot continue without a valid game folder."
        return
    }
    Write-Info "Game folder: $gameFolder"

    while ($true) {
        Write-Host ""
        Write-Host "  ---- Individual Steps ----" -ForegroundColor Cyan
        Write-Host "  1. Apply v2.12 patch" -ForegroundColor White
        Write-Host "  2. Apply MultiSkin v2.12" -ForegroundColor White
        Write-Host "  3. Apply BDG v2.13" -ForegroundColor White
        Write-Host "  4. Install dgVoodoo2" -ForegroundColor White
        Write-Host "  5. Apply crash fix" -ForegroundColor White
        Write-Host "  6. Apply Win11 tweaks" -ForegroundColor White
        Write-Host "  7. Check version" -ForegroundColor White
        Write-Host "  8. Validate installation" -ForegroundColor White
        Write-Host "  9. Launcher desktop shortcut" -ForegroundColor White
        Write-Host " 10. Install ReShade (optional)" -ForegroundColor White
        Write-Host " 11. Back to main menu" -ForegroundColor White
        Write-Host "  ----------------------------" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Select step (1-11): " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            "1" { Step-ApplyV212 $gameFolder (Get-BobVersion $gameFolder); Pause-Continue }
            "2" { Step-ApplyMultiSkin $gameFolder; Pause-Continue }
            "3" { Step-ApplyV213 $gameFolder; Pause-Continue }
            "4" { Step-InstallDgVoodoo2 $gameFolder; Pause-Continue }
            "5" { Step-ApplyCrashFix $gameFolder; Pause-Continue }
            "6" { Step-Win11Tweaks $gameFolder; Pause-Continue }
            "7" { Step-CheckVersion $gameFolder; Pause-Continue }
            "8" { Step-Validate $gameFolder; Pause-Continue }
            "9" { Step-InstallLauncher $gameFolder; Pause-Continue }
            "10" { Step-InstallReShade $gameFolder; Pause-Continue }
            "11" { return }
            default { Write-Warn "Invalid option. Please enter 1-11." }
        }
    }
}

# ============================================================
# Main Menu
# ============================================================

function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  BOB2 2.13 Modern Fix - install and repair" -ForegroundColor Cyan
        Write-Host "  Fix package v$FixVersion ($FixVersionDate)" -ForegroundColor DarkGray
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  1. Full Install (recommended)" -ForegroundColor White
        Write-Host "  2. Check Installation Status" -ForegroundColor White
        Write-Host "  3. Individual Steps" -ForegroundColor White
        Write-Host "  4. Settings Tweaker" -ForegroundColor White
        Write-Host "  5. Uninstall Modifications" -ForegroundColor White
        Write-Host "  6. Exit" -ForegroundColor White
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Select option (1-6): " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            "1" { Do-FullInstall; Pause-Continue }
            "2" { Show-Status; Pause-Continue }
            "3" { Do-IndividualSteps }
            "4" { Do-Settings; Pause-Continue }
            "5" { Do-Uninstall; Pause-Continue }
            "6" { Write-Host ""; Write-Host "  Goodbye!" -ForegroundColor Cyan; return }
            default { Write-Warn "Invalid option. Please enter 1-6." }
        }
    }
}

# Entry point.
#
# With -AsLibrary this file stops here: every function above is defined and
# nothing runs. BOB2_Install.ps1 dot-sources it that way so the GUI drives the
# same Step-* functions rather than reimplementing 2,127 lines of install
# logic that already works.
if (-not $AsLibrary) { Show-Menu }
