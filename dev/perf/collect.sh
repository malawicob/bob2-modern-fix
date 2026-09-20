#!/bin/sh
# collect.sh <label> [<label>...]
# Finds the newest capture for each label in either game folder (the
# elevated bat writes them beside itself), copies it with shared read
# access (PresentMon may still hold it), trims a whole-session capture to
# the minute of flying before its last ten seconds, and runs analyze_fps.py
# with the first label as the baseline.
PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
HERE=$(dirname "$0"); OUT=/mnt/c/Users/Public/perf; mkdir -p "$OUT"; files=""
for lab in "$@"; do
  if [ -f "$OUT/$lab.csv" ] && [ -z "$(ls "/mnt/d/Battle of Britain II_Latest_test"/fps_"$lab"_*.csv "/mnt/d/Battle of Britain II"/fps_"$lab"_*.csv 2>/dev/null)" ]; then files="$files $OUT/$lab.csv"; continue; fi
  f=$(ls -t "/mnt/d/Battle of Britain II_Latest_test"/fps_"$lab"_*.csv "/mnt/d/Battle of Britain II"/fps_"$lab"_*.csv 2>/dev/null | head -1)
  [ -z "$f" ] && { echo "no capture for label $lab"; continue; }
  w=$(wslpath -w "$f")
  "$PS" -NoProfile -Command "\$i=[IO.File]::Open('$w','Open','Read','ReadWrite'); \$o=[IO.File]::Create('C:\\Users\\Public\\perf\\$lab.raw.csv'); \$i.CopyTo(\$o); \$i.Close(); \$o.Close()" >/dev/null 2>&1
  python3 "$HERE/trim.py" "$OUT/$lab.raw.csv" "$OUT/$lab.csv" 60 10 || continue
  files="$files $OUT/$lab.csv"
done
[ -n "$files" ] && python3 /home/patrick_millin/bob2/analyze_fps.py $files
for f in $files; do python3 - "$f" <<'PY'
import csv,sys,statistics as st
rows=list(csv.DictReader(open(sys.argv[1],encoding='utf-8-sig')))
g=lambda n:[float(r[n]) for r in rows if r.get(n) not in (None,'','NA')]
if rows: print('  %-14s SyncInterval %s  tearing %s  CPU %.2f ms  GPU %.2f ms (medians)' % (sys.argv[1].split('/')[-1], set(r['SyncInterval'] for r in rows), set(r['AllowsTearing'] for r in rows), st.median(g('MsCPUBusy')), st.median(g('MsGPUBusy'))))
PY
done
