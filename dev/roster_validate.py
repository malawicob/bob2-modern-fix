#!/usr/bin/env python3
"""Check a Squadron Room roster before it is committed.

ERRORS make the file unusable and fail the run. WARNINGS are things still
to research, and are expected while a squadron is being worked on.

    python3 dev/roster_validate.py squadronroom/rosters/*.json
"""
import json, sys, glob, datetime, collections

BATTLE_START = datetime.date(1940, 7, 10)
BATTLE_END   = datetime.date(1940, 10, 31)
# A fighter squadron's establishment: about twenty pilots on strength, and
# never the sixty-odd that a full war-long name list would put on one board.
MIN_ON_STRENGTH, MAX_ON_STRENGTH = 12, 26
REASONS = {'KIA', 'MIA', 'POW', 'WIA', 'DoW', 'posted', 'rested', 'promoted'}

def d(s):
    if not s: return None
    try: return datetime.date.fromisoformat(str(s)[:10])
    except ValueError: return None

def check(path):
    errs, warns = [], []
    try:
        men = json.load(open(path, encoding='utf-8'))
    except Exception as e:
        return [f'{path}: not readable as JSON: {e}'], []
    if not isinstance(men, list) or not men:
        return [f'{path}: expected a non-empty list of men'], []

    seen = collections.Counter()
    for i, m in enumerate(men):
        who = m.get('pilot') or f'entry {i}'
        for key in ('pilot', 'rank', 'historical', 'joined', 'left',
                    'left_reason', 'fate', 'victories', 'awards', 'src'):
            if key not in m:
                errs.append(f'{who}: no "{key}" field')
        seen[str(m.get('pilot'))] += 1
        j, l = d(m.get('joined')), d(m.get('left'))
        if j and l and l < j:
            errs.append(f'{who}: left {l} before joining {j}')
        if m.get('left_reason') and m['left_reason'] not in REASONS:
            errs.append(f'{who}: left_reason "{m["left_reason"]}" is not one of {sorted(REASONS)}')
        if l and not m.get('left_reason'):
            errs.append(f'{who}: has a leaving date but no reason')
        f = m.get('fate')
        if f and f.get('date') and l and d(f['date']) != l:
            errs.append(f'{who}: fate date {f["date"]} and leaving date {l} disagree')
        # victories must fall inside his time on strength
        start = j or BATTLE_START
        end = l or BATTLE_END
        for v in (m.get('victories') or []):
            vd = d(v.get('date'))
            if not vd:
                errs.append(f'{who}: a victory with no date')
            elif vd < start or vd > end:
                errs.append(f'{who}: victory on {vd} outside his time with the squadron ({start} to {end})')
        for a in (m.get('awards') or []):
            if not a.get('award'):
                errs.append(f'{who}: an award with no name')
        tot = m.get('victories_total')
        dated = len(m.get('victories') or [])
        if tot is not None and dated > tot:
            errs.append(f'{who}: {dated} dated victories but a total of {tot}')
        if m.get('historical') and not m.get('src'):
            warns.append(f'{who}: a real man with no source')
        if not m.get('joined'):
            warns.append(f'{who}: joining date not researched')
        if tot is None and not dated:
            warns.append(f'{who}: victories not researched')

    for name, n in seen.items():
        if n > 1:
            errs.append(f'{name}: appears {n} times')

    # the board on every day of the Battle
    day, worst_lo, worst_hi = BATTLE_START, None, None
    while day <= BATTLE_END:
        on = 0
        for m in men:
            j, l = d(m.get('joined')) or BATTLE_START, d(m.get('left'))
            if day >= j and (l is None or day < l):
                on += 1
        if worst_lo is None or on < worst_lo[1]: worst_lo = (day, on)
        if worst_hi is None or on > worst_hi[1]: worst_hi = (day, on)
        day += datetime.timedelta(days=1)
    if worst_hi and worst_hi[1] > MAX_ON_STRENGTH:
        warns.append(f'{worst_hi[1]} men on strength on {worst_hi[0]} '
                     f'(a squadron held about {MIN_ON_STRENGTH}-{MAX_ON_STRENGTH}); '
                     f'joining and leaving dates, or the invented men, are still to come')
    if worst_lo and worst_lo[1] < MIN_ON_STRENGTH:
        warns.append(f'only {worst_lo[1]} men on strength on {worst_lo[0]}')
    return errs, warns

def main():
    paths = []
    for a in sys.argv[1:]: paths += sorted(glob.glob(a))
    if not paths:
        print('usage: roster_validate.py <file.json> ...'); return 2
    bad = 0
    for p in paths:
        errs, warns = check(p)
        n = len(json.load(open(p, encoding='utf-8'))) if not errs or 'not readable' not in errs[0] else 0
        print(f'== {p}  ({n} men)')
        for e in errs: print(f'   ERROR   {e}')
        counts = collections.Counter(w.split(': ')[-1] for w in warns)
        for w, c in counts.most_common():
            print(f'   warn    {w}' + (f'  (x{c})' if c > 1 else ''))
        if not errs and not warns: print('   clean')
        bad += len(errs)
    print(f'\n{len(paths)} file(s), {bad} error(s)')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
