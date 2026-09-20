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

| date | label | install | change | frames | avg | median | 1% low | worst | jitter | notes |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-20 | cloud32 | dev | guard `cloudstep=32` (game 256), AA now 4x | 12085 (60 s) | 201.4 | 222.6 | 110.6 | 24.7 ms | 1.0 ms | CPU 4.36 ms against 5.80 (trimmed): -25%. avg +16%, median +32%, 1% low +18%. An earlier 19 s capture of the same setting read 207 / 228 / 105. Clouds looked normal to Patrick. |

**Seam lines, continued.** 4x made no difference; Patrick: the higher he flies the worse they get. That is the signature of texture sampling at tile edges on the lower mip levels, and dgVoodoo is forcing 16x anisotropic filtering (`[DirectX] Filtering = 16`) on a 2005 terrain that was never built for it. Stable has the same setting but runs ReShade's Cinematic preset (SMAA, bloom, grain), which hides them. Next flight: `Filtering = appdriven` on dev.

**2026-09-20, `both` run (cloudstep 32 + line patch).** The line hook installed and ran clean, but the guard counted only ~23,000 lines in the whole session, about 17 a frame, and only in one ten-second spell: a training circuit hardly draws lines at all, so the 23% of the August profile belongs to a combat scene (tracers, smoke trails), and the patch has to be measured there, not here. Capture still locked by PresentMon at the time of writing.
**Seams.** `Filtering = appdriven` did not remove the tile lines and blurred the distance, so forced anisotropic filtering is not the cause; put back to 16. Patrick's photo shows bright, straight, regular tile-grid lines, and he says they were never there before. The remaining graphics change since then is forced multisample antialiasing, which on a fixed-function game samples textures just outside a tile's edge on partly covered pixels. Next flight: `Antialiasing = appdriven` (off), filtering 16.
**2026-09-20, `aa0`: no panel lines.** With `[DirectX] Antialiasing = appdriven` and filtering 16x the tile grid is gone (Patrick, flown with a climb). Forced multisampling is the cause, at 2x and 4x as well as the 8x already known. The package no longer recommends it: Settings marks Off as recommended and Off keeps 16x filtering; Setup's "everything at once" is 16x filtering plus ReShade, whose SMAA smooths edges on the finished picture. `both` capture: 200.3 avg against cloud32's 201.4, i.e. the line patch is neutral in a scene that draws no lines, as expected; one 125 ms frame, cause unknown.

**2026-09-20, `london_on`: heavy battle over London, cloud step 32 and the line patch ON.** 210 s session, no crash, nothing reported drawn wrong. The guard counted **1,343,587 lines** in about 165 s of flying: typically 8,000 to 20,000 a second in the fight, peak 38,742 a second, i.e. roughly 70 to 300 lines a frame against about 17 in a training circuit. Frame rate through the battle 75 to 170 fps in ten-second buckets, mostly 100 to 125; CPU time equals frame time throughout (8 to 13 ms), GPU about 4 ms. The `london_off` run of the same mission, line patch off, is the comparison.
