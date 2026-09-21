#!/usr/bin/env python3
"""trim.py in.csv out.csv [window=60] [tail=10]
Keep the <window> seconds of a whole-session PresentMon capture that end
<tail> seconds before the last frame: the flying, not the menus either side."""
import csv, sys
src, dst = sys.argv[1], sys.argv[2]
window = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0
tail = float(sys.argv[4]) if len(sys.argv) > 4 else 10.0
rows = list(csv.DictReader(open(src, encoding='utf-8-sig')))
if not rows: sys.exit('empty capture')
t = 0.0; times = []
for r in rows:
    try: t += float(r['MsBetweenPresents']) / 1000.0
    except Exception: pass
    times.append(t)
end = times[-1] - tail; start = end - window
keep = [r for r, x in zip(rows, times) if start <= x <= end]
with open(dst, 'w', newline='', encoding='utf-8') as fh:
    w = csv.DictWriter(fh, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(keep)
print('%s: session %.0f s, kept %d frames from %.0f s to %.0f s' % (src.split('/')[-1], times[-1], len(keep), max(start, 0), end))
