# Performance run log

Same scene every run: Basic Training take-off from Biggin Hill, wide circuit,
`BOB2_MeasureFPS_Armed.bat <label> 240` armed before the game. First 10 s of
each capture discarded by `analyze_fps.py`. One lever per run, put back before
the next. Analyse with `dev/perf/collect.sh <label> [<label>...]`; the first
label is the baseline for the deltas.

| date | label | install | change | frames | avg | median | 1% low | worst | jitter | notes |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-13 | bare | dev | dressing off (191 parked aircraft) | 2750 (19 s) | 145.3 | 159.4 | 73.8 | 24.4 ms | 1.5 ms | short capture, airborne late |
| 2026-09-13 | dressed | dev | dressing on, 191 parked aircraft | 7850 (60 s) | 130.9 | 129.0 | 65.8 | 38.7 ms | 1.4 ms | CPU busy 7.6 ms of 7.8; GPU 4.0 ms; SyncInterval 0, tearing allowed |
| 2026-09-20 | trimmed | dev | dressing trimmed to 95 parked aircraft, guard 1.9.1 patches off | 10320 (60 s) | 173.2 | 169.1 | 93.4 | 48.3 ms | 1.2 ms | CPU 5.8 ms, GPU 3.3 ms; one frame over 33 ms; SyncInterval 0 |
| 2026-09-20 | stable | stable | reference, untouched game | 3444 (20 s) | 168.9 | 151.9 | 115.4 | 14.8 ms | 1.2 ms | CPU 6.5 ms, GPU 3.3 ms; short capture; SyncInterval 0 |

Reading so far: run to run the same scene moves by about 15% (bare 145, trimmed 173 on the same install), so dev trimmed and stable are level. The dressing as first built cost about a tenth; trimmed it costs nothing measurable. Vsync is off on both installs.

**Seam lines, 2026-09-20.** Patrick: many tile seam lines on dev (trimmed run), one or two on stable. Every graphics setting compared: `bdg.txt` identical apart from water colours, `Weather.cfg` identical, the decoded `settings.cfg` graphics bytes identical. Two differences only: dgVoodoo antialiasing **2x on dev, 4x on stable**, and **ReShade on stable, none on dev**. Dev set to 4x (backup `dgVoodoo.conf.before-aa4x`) before the `cloud32` run; if the lines stay, the remaining suspect is ReShade's post-process antialiasing masking them on stable.
