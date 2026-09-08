#!/usr/bin/env python3
"""Build squadronroom/rosters/32.json from the researched data.

    python3 dev/build_roster32.py --out squadronroom/rosters/32.json
"""
import json, argparse, sys, os, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roster32_data as R

BATTLE_START, BATTLE_END = datetime.date(1940, 7, 10), datetime.date(1940, 10, 31)
SRC = 'bbm.org.uk airmen; Holloway list of the Few via Wikipedia'
# how a man left, from the note's own wording
def fate_for(left, reason, note):
    if reason == 'MIA':
        return {'status': 'MIA', 'date': left, 'note': 'Missing'}
    if reason == 'KIA':
        return {'status': 'KIA', 'date': left, 'note': 'Killed in action'}
    if reason == 'WIA':
        return {'status': 'WIA', 'date': left, 'note': 'Wounded'}
    if reason == 'posted':
        return {'status': 'Posted', 'date': left, 'note': 'Posted to another squadron'}
    return {'status': 'Survived', 'date': None, 'note': 'Survived the Battle with the squadron'}

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--out', required=True)
    a = ap.parse_args()
    out = []
    for (pilot, rank, joined, left, reason, vics, awards, serials, codes, note) in R.MEN:
        # a claim outside a man's time on strength is a research error, not
        # a fact: the validator rejects it, so catch it here where it can
        # be explained rather than silently trimmed
        start = datetime.date.fromisoformat(joined) if joined else BATTLE_START
        # A man whose leaving is not recorded was still there as far as we
        # know, so his claims are not cut off at the end of the Battle.
        end = datetime.date.fromisoformat(left) if left else datetime.date(1945, 1, 1)
        keep = []
        for (vd, vt, vk) in vics:
            d = datetime.date.fromisoformat(vd)
            if d < start or d > end:
                print(f'  ! {pilot}: claim on {vd} outside {start}..{end}, dropped')
                continue
            keep.append({'date': vd, 'type': vt, 'kind': vk})
        out.append({
            'pilot': pilot,
            'rank': rank,
            'historical': True,
            'joined': joined,
            'left': left,
            'left_reason': reason,
            'fate': fate_for(left, reason, note),
            'victories': keep,
            'victories_total': (len([v for v in keep if v['kind'] in ('destroyed', 'shared')]) or None),
            'vic_source': 'documented' if keep else 'none traced',
            'awards': [{'award': n, 'date': d} for (n, d) in awards],
            'codes': codes,
            'serials': serials,
            'portrait': None,
            'src': SRC,
            'note': note,
        })
    out.sort(key=lambda m: m['pilot'])
    with open(a.out, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, ensure_ascii=False); f.write('\n')
    # squadron-level facts live beside the rosters, not among them
    sqdir = os.path.join(os.path.dirname(os.path.dirname(a.out)), 'squadrons')
    os.makedirs(sqdir, exist_ok=True)
    sq = os.path.join(sqdir, '32.json')
    with open(sq, 'w', encoding='utf-8') as f:
        json.dump(R.SQUADRON, f, indent=1, ensure_ascii=False); f.write('\n')
    j = sum(1 for m in out if m['joined']); l = sum(1 for m in out if m['left'])
    v = sum(len(m['victories']) for m in out)
    print(f'{a.out}: {len(out)} men, {j} with a joining date, {l} with a leaving date, '
          f'{v} dated claims, {sum(len(m["awards"]) for m in out)} awards')
    print(f'{sq}: the squadron itself')

if __name__ == '__main__':
    main()
