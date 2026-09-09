# Testing the Squadron Room without eating a pilot

The Room keeps its state in a real folder:

    $StateDir = <GameDir>\SquadronRoom     (or squadronroom\state with no game)

`Save-Pilot`, and anything that calls it, writes `pilot.json` there for
real. On 9 September 2026 a throwaway test harness called
`Set-BulletinRead`, which calls `Save-Pilot`, and overwrote the dev
install's pilot record with a stub named "Test". Nothing warned, because
nothing was wrong: the function did exactly what it says.

## The rule

A harness that dot-sources the Room and then calls anything that might
save must point `$StateDir` somewhere disposable FIRST:

```powershell
. $tmp                       # dot-source the Room's functions
$StateDir  = Join-Path $env:TEMP ('roomtest-' + [guid]::NewGuid())
$PilotPath = Join-Path $StateDir 'pilot.json'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
```

Both variables, not just the first: `$PilotPath` is computed from
`$StateDir` when the script loads, so moving `$StateDir` afterwards does
not move the file with it.

## Which functions write

Anything reaching `Save-Pilot`, which today is `Set-BulletinRead`,
`Update-CareerRecord`, `Save-AcMark`, `Save-AcPos` and the career and
posting flows. `Show-Paper` writes too, because opening the bulletin is
what marks it read. When in doubt, redirect.

`room_smoketest.ps1` writes too, and the comment that used to sit here
saying it was safe was wrong. Opening the Log Book runs
`Sync-CampaignClaims`, which levels the pilot's `campaignKills` baseline
against that install's own campaign save and saves the record. Against
the install it belongs to that is correct and self-correcting. Against a
record copied in from a DIFFERENT install it silently re-derives the
baseline from the wrong campaign, which is how a restored pilot came back
with an empty claims baseline. Redirect for that too, or accept it.

The short version: assume every screen can save.
