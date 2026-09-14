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
