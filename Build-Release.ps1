# =====================================================================
#  BUILD A RELEASE ZIP
#  This script is NOT shipped. It builds what is.
# =====================================================================
#
#  WHY IT EXISTS
#    The working folder is a live install: it accumulates the current
#    machine's paths, preferences and logs. Zipping it up and handing it to
#    someone else would ship your game folder path, your text-size choice
#    and your last run log along with the mod. This copies out only what
#    belongs in a release.
#
#  USAGE
#    .\Build-Release.ps1                 build to .\dist
#    .\Build-Release.ps1 -IncludeDxvk    include the DXVK wrapper as well
#    .\Build-Release.ps1 -OutDir X:\rel  build somewhere else
# =====================================================================

param(
    [string]$OutDir,
    # DXVK is 7.5 MB - about two thirds of the whole package - and this mod
    # tells users not to use it, because it crashes this game on entering
    # 3D. Off by default; the graphics screen still offers it for anyone
    # who wants to try, and it degrades to "not installed".
    [switch]$IncludeDxvk
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
if (-not $src) { $src = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $OutDir) { $OutDir = Join-Path $src 'dist' }

# Version comes from the launcher, so a release can never be mislabelled.
$verLine = Select-String -Path (Join-Path $src 'BOB2_Launcher.ps1') -Pattern "^\`$FixVersion\s*=\s*'([^']+)'" | Select-Object -First 1
if (-not $verLine) { throw 'Could not read $FixVersion from BOB2_Launcher.ps1' }
$version = $verLine.Matches[0].Groups[1].Value

# ---------------------------------------------------------------------
#  NEVER SHIP THESE
# ---------------------------------------------------------------------
$excludeFiles = @(
    'BOB2_Config.path'              # this machine's game folder
    'BOB2_Config.textsize'          # this machine's text size
    'BOB2_Profile_last_run.log'     # this machine's last profiling run
    'BOB2-Win11-Fix.tar.gz'         # stale build artifact, 45 bytes, empty
    'Build-Release.ps1'             # this script
    'DESIGN.md'                     # design notes, not user documentation
    'BOB2_UITest.bat'               # menu-rescale prototype, developer only
)
$excludeDirs = @(
    'dist'
    '_ControlsBackup'               # backups of a real install
    '_AxisProfiles'                 # somebody's joystick calibration
    '_ArtBackup'
    'work'
)
if (-not $IncludeDxvk) { $excludeDirs += 'dxvk' }

# Stage INSIDE a wrapper dir, so the zip contains a BOB2-Win11-Fix folder
# rather than 42 loose files.
#
# CreateFromDirectory archives the CONTENTS of the directory it is given,
# not the directory itself. Pointing it at the staging folder therefore
# produced a zip whose root was BOB2.bat, BOB2_Launcher.ps1, ... - so
# extracting it created a folder named after the ZIP and the readme's
# "put the BOB2-Win11-Fix folder beside Bob.exe" was impossible to follow,
# because no such folder existed. A tester hit exactly that and could not
# get past "Bob.exe was not found". Zip the PARENT instead.
$stageRoot = Join-Path $OutDir '_stage'
if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
$stage = Join-Path $stageRoot 'BOB2-Win11-Fix'
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Write-Host "Building $version" -ForegroundColor Cyan

$copied = 0; $skipped = @()
Get-ChildItem $src -Force | ForEach-Object {
    if ($_.PSIsContainer) {
        if ($excludeDirs -contains $_.Name) { $skipped += "$($_.Name)\"; return }
        Copy-Item $_.FullName -Destination $stage -Recurse -Force
        $copied += (Get-ChildItem $_.FullName -Recurse -File).Count
    } else {
        if ($excludeFiles -contains $_.Name) { $skipped += $_.Name; return }
        Copy-Item $_.FullName -Destination $stage -Force
        $copied++
    }
}

# ---------------------------------------------------------------------
#  Licences. Every third-party thing in the package, named, so nobody has
#  to guess what they are allowed to do with it.
# ---------------------------------------------------------------------
@"
BOB2 2.13 MODERN FIX - THIRD PARTY COMPONENTS
=============================================

This package contains no Battle of Britain II game content. It patches a
copy of the game that you already own, and it ships no patches - it applies
the ones you supply.

  dgVoodoo2 2.8.7.3         Dege - https://dege.freeweb.hu
                            Copyright (C) 2013-2026 Dege.
                            Direct3D wrapper, redistributed unmodified.

                            Shipped under the redistribution rights stated
                            in the dgVoodoo readme, section 1:

                              "You can freely ship your game or game mod
                               with individual dgVoodoo files included."

                            The same section's two restrictions do not
                            apply here: this is not a standalone
                            redistribution of dgVoodoo (which would require
                            shipping the full .zip), and it is not a
                            launcher or framework bundling dgVoodoo for
                            general use across multiple applications - it
                            is applied to Battle of Britain II only.

                            Full terms:
                            https://dege.freeweb.hu/dgVoodoo2/ReadmeGeneral/

  Lucide icons              ISC licence - https://lucide.dev
                            Copyright (c) for portions of lucide are held by
                            Cole Bemis 2013-2022 as part of Feather (MIT).
                            All other copyright (c) for Lucide are held by
                            Lucide Contributors 2022.

  Photographs               Imperial War Museums, public domain.
                            IWM HU 54418 - 'B' Flight, No. 32 Squadron RAF,
                            Hawkinge, 29 July 1940.
                            IWM CL186 - RAF Repair and Salvage Unit,
                            Normandy, 19 June 1944.

  dinput8.dll               Built for this mod from dinput8_guard.c.

$(if ($IncludeDxvk) { "  DXVK                      zlib/libpng licence - https://github.com/doitsujin/dxvk`n" } else { "" })
NOT INCLUDED, and needed separately:

  Battle of Britain II: Wings of Victory
      A licensed copy. https://a2asimulations.com/store/

  Patch 2.13, if your game is not already at it
      https://www.a2asimulations.com/bob/downloads/BDG%20v2.13.7z

This mod is not affiliated with, endorsed by or connected to A2A
Simulations, Shockwave Productions or Rowan Software.
"@ | Set-Content -Path (Join-Path $stage 'LICENCES.txt') -Encoding ASCII

# ---------------------------------------------------------------------
$zip = Join-Path $OutDir "BOB2-2.13-Modern-Fix-v$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Write entries by hand rather than CreateFromDirectory.
#
# On .NET Framework that helper writes entry names with BACKSLASHES, which
# the zip spec forbids (APPNOTE 4.4.17.1 requires '/'). Windows Explorer
# tolerates it; unzip on Linux and macOS does not, and produces a single
# flat file literally named "BOB2-Win11-Fix\BOB2.bat". Normalising the
# separator ourselves is the whole fix.
Add-Type -AssemblyName System.IO.Compression | Out-Null
$fsZip = [System.IO.File]::Open($zip, [System.IO.FileMode]::Create)
$arch  = New-Object System.IO.Compression.ZipArchive($fsZip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $stageRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($stageRoot.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $arch, $_.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $arch.Dispose(); $fsZip.Dispose()
}
Remove-Item $stageRoot -Recurse -Force

$mb = [Math]::Round((Get-Item $zip).Length / 1MB, 2)
Write-Host ""
Write-Host "  $copied files, $mb MB" -ForegroundColor Green
Write-Host "  $zip" -ForegroundColor Green
Write-Host ""
Write-Host "  left out:" -ForegroundColor DarkGray
foreach ($s in $skipped) { Write-Host "    $s" -ForegroundColor DarkGray }
Write-Host ""
Write-Host "  Extract into the Battle of Britain II folder, so that" -ForegroundColor Gray
Write-Host "  BOB2-Win11-Fix sits beside Bob.exe, then run BOB2.bat." -ForegroundColor Gray
