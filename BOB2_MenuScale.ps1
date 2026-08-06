# =====================================================================
#  BOB2 menu scale - resize the in-game menus for your screen
#  Part of BOB2 Windows 10/11 Fix v1.5.0
# =====================================================================
#
#  WHAT THIS DOES
#    BOB2's menus are 154 Win32 dialog templates stored as resources
#    inside Bob.exe. Their layout is fixed in dialog units against an
#    8pt MS Sans Serif baseline, so on a high-resolution screen they
#    occupy a small part of the display and the text is tiny.
#
#    Every coordinate in those templates, and the font point size, is a
#    fixed-width 16-bit field. So rescaling is an IN-PLACE edit: nothing
#    is resized, no section is rebuilt, no address moves, and the
#    patched Bob.exe is exactly the same length as the original.
#
#  WHY PATCH FILES RATHER THAN PRE-BUILT EXECUTABLES
#    Shipping four 4.4 MB copies of Bob.exe would be 18 MB of duplicated
#    game code that goes stale the moment the game is re-patched. Each
#    scale is instead a list of 16-bit edits, and every edit carries the
#    value it EXPECTS to find. If a single expectation fails, nothing is
#    written. That makes it impossible to apply a patch to the wrong
#    build, or to apply one twice on top of itself.
#
#    Patches are always applied to the pristine Bob.exe.unscaled, never
#    to whatever Bob.exe currently is, so scales never compound.
#
#  IF YOU RE-PATCH THE GAME
#    Applying BDG v2.13 again, or anything else that replaces Bob.exe,
#    wipes the rescale. Re-run this afterwards. Do NOT let a patch
#    overwrite Bob.exe.unscaled - delete it first if unsure, and this
#    tool will make a fresh one from the newly patched Bob.exe.
# =====================================================================

param(
    # 102, 110, 125, 140, or 'original'. Omit for an interactive menu.
    [string]$Scale
)

$ErrorActionPreference = 'Stop'
# -Scale supplied means a caller drove this, so never block on a prompt.
$script:Interactive = -not $PSBoundParameters.ContainsKey('Scale')
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$SCALES = [ordered]@{
    '102' = @{ Label = '1.02x'; Font = '8pt';  Width = 1171; Note = 'barely changed - for 1280 wide or less' }
    '110' = @{ Label = '1.10x'; Font = '9pt';  Width = 1264; Note = 'small increase - 1366 wide and up' }
    '125' = @{ Label = '1.25x'; Font = '10pt'; Width = 1437; Note = 'comfortable - 1600 wide and up' }
    '140' = @{ Label = '1.40x'; Font = '11pt'; Width = 1608; Note = 'largest text - 1920 wide and up' }
}
$DEFAULT = '140'

function Find-GameDir {
    foreach ($c in @($ScriptDir, (Split-Path -Parent $ScriptDir),
                     'D:\Battle of Britain II', 'C:\Battle of Britain II',
                     'C:\Program Files (x86)\Battle of Britain II',
                     'C:\Program Files (x86)\Shockwave\Battle of Britain II')) {
        if ($c -and (Test-Path (Join-Path $c 'Bob.exe'))) { return $c }
    }
    return $null
}

function Get-Md5 {
    param([byte[]]$Bytes)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    ($md5.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

# Only pause when a human is watching. Launched from the launcher this runs
# with a hidden window, and an unanswerable prompt there hangs forever - which
# is exactly how it would look if the tool had simply stopped working.
function Wait-IfInteractive {
    if (-not $script:Interactive) { return }
    Read-Host '  Press Enter' | Out-Null
}

function Write-Err  { param($m) Write-Host "  $m" -ForegroundColor Red }
function Write-OK   { param($m) Write-Host "  $m" -ForegroundColor Green }
function Write-Info { param($m) Write-Host "  $m" -ForegroundColor Gray }

# ---------------------------------------------------------------------
$GameDir = Find-GameDir
if (-not $GameDir) {
    Write-Err 'Could not find Bob.exe.'
    Write-Info 'Put this script in the Battle of Britain II folder, or in the'
    Write-Info 'BOB2-Win11-Fix folder inside it.'
    Wait-IfInteractive
    exit 1
}

$BobPath  = Join-Path $GameDir 'Bob.exe'
$OrigPath = Join-Path $GameDir 'Bob.exe.unscaled'

if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) {
    Write-Err 'The game is running. Close it first - Bob.exe cannot be replaced while in use.'
    Wait-IfInteractive
    exit 1
}

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host '  BOB2 MENU SCALE' -ForegroundColor Cyan
Write-Host '========================================================' -ForegroundColor Cyan
Write-Info "Game folder: $GameDir"

# Establish the pristine original. Without it nothing can be applied
# safely, because a patch must start from known bytes.
if (-not (Test-Path $OrigPath)) {
    Write-Info 'No Bob.exe.unscaled yet - creating one from the current Bob.exe.'
    Copy-Item $BobPath $OrigPath
    Write-OK "Backed up to $OrigPath"
}

$orig = [System.IO.File]::ReadAllBytes($OrigPath)
$origMd5 = Get-Md5 $orig
$curMd5  = Get-Md5 ([System.IO.File]::ReadAllBytes($BobPath))

# Work out what is installed right now by comparing against each patch's
# recorded result, rather than trusting a stored setting that could be stale.
$current = $(if ($curMd5 -eq $origMd5) { 'original' } else { 'unknown' })
foreach ($k in $SCALES.Keys) {
    $p = Join-Path $ScriptDir "menuscale\scale$k.bin"
    if (-not (Test-Path $p)) { continue }
    $b = [System.IO.File]::ReadAllBytes($p)
    # Header is magic(8) + factor(2) + pad(2) + count(4) = 16, then the
    # source md5 at 16..31 and the RESULT md5 at 32..47. Reading 24..39
    # straddled the two and never matched anything.
    $want = ($b[32..47] | ForEach-Object { $_.ToString('x2') }) -join ''
    if ($want -eq $curMd5) { $current = $k; break }
}
Write-Info ("Currently installed: " + $(if ($current -eq 'original') { 'original (unscaled)' }
            elseif ($current -eq 'unknown') { 'not recognised - a patch replaced Bob.exe' }
            else { $SCALES[$current].Label }))

# ---------------------------------------------------------------------
if (-not $Scale) {
    Write-Host ''
    Write-Host '  Choose a menu size for your screen:' -ForegroundColor Yellow
    Write-Host ''
    $i = 0
    foreach ($k in $SCALES.Keys) {
        $i++
        $s = $SCALES[$k]
        $mark = $(if ($k -eq $current) { ' <- installed' } else { '' })
        $def  = $(if ($k -eq $DEFAULT) { ' [default]' } else { '' })
        Write-Host ("   {0}.  {1}  font {2}  needs {3} px across{4}{5}" -f $i, $s.Label, $s.Font, $s.Width, $def, $mark) -ForegroundColor White
        Write-Host ("       {0}" -f $s.Note) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '   5.  Original size (undo the rescale)' -ForegroundColor White
    Write-Host '   6.  Cancel' -ForegroundColor White
    Write-Host ''
    Write-Info 'Pick the largest one that does not clip off the right of your screen.'
    Write-Host ''
    $pick = Read-Host "  Choose 1-6 (Enter for the default, $($SCALES[$DEFAULT].Label))"
    if ($pick -eq '') { $Scale = $DEFAULT }
    else {
        switch ($pick) {
            '1' { $Scale = '102' }
            '2' { $Scale = '110' }
            '3' { $Scale = '125' }
            '4' { $Scale = '140' }
            '5' { $Scale = 'original' }
            '6' { Write-Info 'Nothing changed.'; exit 0 }
            default { Write-Err 'Not a valid choice.'; Wait-IfInteractive; exit 1 }
        }
    }
}

# ---------------------------------------------------------------------
if ($Scale -eq 'original') {
    [System.IO.File]::WriteAllBytes($BobPath, $orig)
    Write-Host ''
    Write-OK 'Restored the original Bob.exe. Menus are back to their stock size.'
    Write-Info 'Bob.exe.unscaled has been left in place so a scale can be reapplied.'
    Write-Host ''
    Wait-IfInteractive
    exit 0
}

if (-not $SCALES.Contains($Scale)) {
    Write-Err "Unknown scale '$Scale'. Use 102, 110, 125, 140 or original."
    exit 1
}

$patchPath = Join-Path $ScriptDir "menuscale\scale$Scale.bin"
if (-not (Test-Path $patchPath)) {
    Write-Err "Patch file missing: $patchPath"
    Wait-IfInteractive
    exit 1
}

$p = [System.IO.File]::ReadAllBytes($patchPath)
if ([System.Text.Encoding]::ASCII.GetString($p[0..7]) -ne 'BOB2MSC1') {
    Write-Err 'Patch file is not a BOB2 menu-scale patch.'
    exit 1
}
$count      = [BitConverter]::ToUInt32($p, 12)
$wantSrcMd5 = ($p[16..31] | ForEach-Object { $_.ToString('x2') }) -join ''
$wantOutMd5 = ($p[32..47] | ForEach-Object { $_.ToString('x2') }) -join ''

if ($wantSrcMd5 -ne $origMd5) {
    Write-Host ''
    Write-Err 'Bob.exe.unscaled is not the build this patch was made for.'
    Write-Info "  expected md5 $wantSrcMd5"
    Write-Info "  found    md5 $origMd5"
    Write-Info 'This usually means the game was re-patched. Delete Bob.exe.unscaled,'
    Write-Info 'run this again to make a fresh backup, and ask for rebuilt patches.'
    Write-Host ''
    Wait-IfInteractive
    exit 1
}

# Apply. Every edit states the value it expects; one mismatch aborts the
# whole thing before a single byte is written to disk.
$buf = [byte[]]::new($orig.Length)
[Array]::Copy($orig, $buf, $orig.Length)
$off = 48
$bad = 0
for ($i = 0; $i -lt $count; $i++) {
    $o   = [BitConverter]::ToUInt32($p, $off)
    $exp = [BitConverter]::ToUInt16($p, $off + 4)
    $new = [BitConverter]::ToUInt16($p, $off + 6)
    $off += 8
    if ([BitConverter]::ToUInt16($buf, $o) -ne $exp) { $bad++; continue }
    [Array]::Copy([BitConverter]::GetBytes([uint16]$new), 0, $buf, $o, 2)
}
if ($bad -gt 0) {
    Write-Err "$bad of $count edits did not match what they expected. Nothing was written."
    Wait-IfInteractive
    exit 1
}

# Checksum the rescale BEFORE the import fix, since that is what the patch
# file recorded. The import edit is verified separately, by its own search.
$outMd5 = Get-Md5 $buf
if ($outMd5 -ne $wantOutMd5) {
    Write-Err 'Result does not match the expected checksum. Nothing was written.'
    Write-Info "  expected $wantOutMd5"
    Write-Info "  produced $outMd5"
    Wait-IfInteractive
    exit 1
}

# ---------------------------------------------------------------------
# While we are writing Bob.exe anyway, apply the community Windows 10
# import fix: rename the imported DebugBreak to GetVersion.
#
# The game calls DebugBreak() somewhere. That raises EXCEPTION_BREAKPOINT,
# which on Windows XP was usually survivable and on Windows 10/11, with no
# debugger attached, kills the process. Both names are ten characters,
# take no arguments and return a value the caller ignores, so redirecting
# the import makes the call harmless.
#
# This is the same crash the dinput8.dll guard catches in a vectored
# handler. Doing it here stops the exception being raised at all; the
# guard stays as a backstop and still handles the SxS case. Applied on
# every write so it cannot be lost when the menu scale changes.
$dbg = [System.Text.Encoding]::ASCII.GetBytes('DebugBreak')
$gv  = [System.Text.Encoding]::ASCII.GetBytes('GetVersion')
$patchedImport = $false
for ($i = 0; $i -lt ($buf.Length - $dbg.Length); $i++) {
    if ($buf[$i] -ne $dbg[0]) { continue }
    $match = $true
    for ($j = 1; $j -lt $dbg.Length; $j++) {
        if ($buf[$i + $j] -ne $dbg[$j]) { $match = $false; break }
    }
    if ($match) {
        [Array]::Copy($gv, 0, $buf, $i, $gv.Length)
        $patchedImport = $true
        break
    }
}

[System.IO.File]::WriteAllBytes($BobPath, $buf)

$s = $SCALES[$Scale]
Write-Host ''
Write-OK ("Menus rescaled to {0}, dialog font {1}." -f $s.Label, $s.Font)
Write-Info ("$count edits applied and verified. Bob.exe is {0} bytes, same as the original." -f $buf.Length)
Write-Info ("Widest menu page is now about {0} px across." -f $s.Width)
if ($patchedImport) {
    Write-OK 'Also applied the Windows 10 import fix: DebugBreak -> GetVersion.'
    Write-Info 'That call raises a breakpoint exception which modern Windows treats as fatal.'
}
Write-Info 'If anything clips off the right of your screen, run this again and pick a smaller one.'
Write-Host ''
Wait-IfInteractive
