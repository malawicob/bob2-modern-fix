# Proves the elevated write in Enable-ExternalManifests, WITHOUT touching
# the real PreferExternalManifest value. Same key, same route, throwaway
# value name. Two UAC prompts: one to write it, one to take it away.
$key  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide'
$name = 'BOB2FixElevationTest'

Write-Host "The real setting, before anything:" -ForegroundColor Cyan
$real = (Get-ItemProperty $key -Name PreferExternalManifest -ErrorAction SilentlyContinue).PreferExternalManifest
Write-Host "  PreferExternalManifest = $real"

# --- exactly the shape Enable-ExternalManifests uses ---
$cur = $null
try { $cur = (Get-ItemProperty $key -Name $name -ErrorAction SilentlyContinue).$name } catch { }
if ($cur -eq 1) { Write-Host "  test value already there; removing first" ; }

Write-Host "`nStep 1: try to write it directly, unelevated (this SHOULD fail)" -ForegroundColor Cyan
$direct = $false
try {
    New-ItemProperty -Path $key -Name $name -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
    $direct = $true
} catch { }
Write-Host "  direct write succeeded: $direct"

if (-not $direct) {
    Write-Host "`nStep 2: hand it to an elevated reg.exe - SAY YES TO THE PROMPT" -ForegroundColor Yellow
    try {
        Start-Process reg.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList @(
            'add', "`"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide`"",
            '/v', $name, '/t', 'REG_DWORD', '/d', '1', '/f') | Out-Null
    } catch { Write-Host "  Start-Process threw: $($_.Exception.Message)" -ForegroundColor Red }
}

$after = $null
try { $after = (Get-ItemProperty $key -Name $name -ErrorAction SilentlyContinue).$name } catch { }
Write-Host "`nRESULT" -ForegroundColor Cyan
if ($after -eq 1) {
    Write-Host "  the elevated write WORKED - value is $after" -ForegroundColor Green
    Write-Host "  so the DPI manifest step can now finish on a machine that needs it."
} else {
    Write-Host "  the elevated write FAILED - value is '$after'" -ForegroundColor Red
    Write-Host "  (if you clicked No on the prompt, that is expected and is the right answer too)"
}

Write-Host "`nCleaning up - SAY YES TO THE SECOND PROMPT" -ForegroundColor Yellow
try {
    Start-Process reg.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList @(
        'delete', "`"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide`"",
        '/v', $name, '/f') | Out-Null
} catch { }
$gone = $null
try { $gone = (Get-ItemProperty $key -Name $name -ErrorAction SilentlyContinue).$name } catch { }
Write-Host "  test value removed: $($null -eq $gone)"

$realAfter = (Get-ItemProperty $key -Name PreferExternalManifest -ErrorAction SilentlyContinue).PreferExternalManifest
Write-Host "`nThe real setting, after: PreferExternalManifest = $realAfter" -ForegroundColor Cyan
if ("$realAfter" -eq "$real") { Write-Host "  unchanged, as intended." -ForegroundColor Green }
else { Write-Host "  CHANGED - that should not have happened." -ForegroundColor Red }
