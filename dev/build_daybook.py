#!/usr/bin/env python3
"""Merge the researched month files into the Room's daybook.

    python3 dev/build_daybook.py

dev/daybook/1940-07.json .. 1940-10.json are the research, one record a
day with the sources it was read from. This checks them and writes
squadronroom/daybook.json, the same records without the source lists
(they stay here, where anybody checking a line can find them).

WHAT IS CHECKED, because a paper that is wrong in a confident voice is
worse than a thin one:

  every date from 10 July to 31 October 1940 present, once
  figures are whole numbers or absent, and inside what the Battle allows
    (no day cost either side 200 aircraft; a claim above 200 is a typo)
  a claim is never BELOW what the records later showed by a wide margin
    flagged, not dropped: on a few days the Air Ministry under-claimed
  no dash used as punctuation (Patrick's rule for anything a player reads)
  no smart quotes, no unfilled text

A figure that fails is set to null rather than guessed at, and said so.
"""
import datetime, glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'dev', 'daybook')
OUT = os.path.join(ROOT, 'squadronroom', 'daybook.json')
FIGS = ('raf_claimed', 'raf_lost_announced', 'lw_lost_actual', 'raf_lost_actual')


def clean(t):
    if t is None:
        return None
    t = str(t).replace('’', "'").replace('‘', "'").replace('“', '"').replace('”', '"')
    t = re.sub(r'\s*[—–]\s*', ', ', t)          # a dash as punctuation becomes a comma
    t = re.sub(r'\s+-\s+', ', ', t)
    t = re.sub(r'\s{2,}', ' ', t).strip()
    return t or None


def main():
    recs, notes = {}, []
    for f in sorted(glob.glob(os.path.join(SRC, '1940-*.json'))):
        for r in json.load(open(f, encoding='utf-8')):
            d = r.get('date')
            if d in recs:
                notes.append('%s appears twice; the first is kept' % d)
                continue
            recs[d] = r
    day, end = datetime.date(1940, 7, 10), datetime.date(1940, 10, 31)
    out, missing = [], []
    while day <= end:
        k = day.isoformat()
        r = recs.get(k)
        day += datetime.timedelta(days=1)
        if not r:
            missing.append(k)
            continue
        o = {'date': k, 'weather': clean(r.get('weather')), 'air': clean(r.get('air'))}
        for fk in FIGS:
            v = r.get(fk)
            if isinstance(v, bool) or not isinstance(v, int):
                if v is not None:
                    notes.append('%s %s: %r is not a whole number, dropped' % (k, fk, v))
                v = None
            elif v < 0 or v > 200:
                notes.append('%s %s: %d is outside anything the Battle saw, dropped' % (k, fk, v))
                v = None
            o[fk] = v
        # October's contemporary figures come from one secondary site that
        # could not be checked against the RAF's own diary (both archive
        # copies refused automated reading). Where its "announced" loss is
        # the very number in its post-war box it is probably the reconciled
        # figure and not what was given out in 1940, so it is not printed as
        # an announcement. September came from the diary itself and is left.
        if k.startswith('1940-10') and o['raf_lost_announced'] is not None and o['raf_lost_announced'] == o['raf_lost_actual']:
            notes.append('%s: announced loss %d equals the post-war count, from a single source; not printed' % (k, o['raf_lost_announced']))
            o['raf_lost_announced'] = None
        if o['raf_claimed'] is not None and o['lw_lost_actual'] is not None and o['raf_claimed'] < o['lw_lost_actual'] - 10:
            notes.append('%s: claimed %d against %d actually lost; kept, worth a second look'
                         % (k, o['raf_claimed'], o['lw_lost_actual']))
        for lk in ('home', 'reich'):
            items = [clean(x) for x in (r.get(lk) or [])]
            o[lk] = [x for x in items if x][:3]
        out.append(o)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
        fh.write('\n')
    n = len(out)
    print('%d days -> %s' % (n, OUT))
    for fk in FIGS:
        print('  %-20s on %3d days' % (fk, sum(1 for o in out if o[fk] is not None)))
    print('  air text on %d days, weather on %d, home items %d, reich items %d'
          % (sum(1 for o in out if o['air']), sum(1 for o in out if o['weather']),
             sum(len(o['home']) for o in out), sum(len(o['reich']) for o in out)))
    if missing:
        print('  ! %d dates missing: %s' % (len(missing), ', '.join(missing[:8])), file=sys.stderr)
    for x in notes:
        print('  ? ' + x, file=sys.stderr)
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
