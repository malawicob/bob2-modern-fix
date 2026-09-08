#!/usr/bin/env python3
"""Convert a Squadron Room roster to the living-squadrons schema.

The old shape carried one integer of victories, a free-text status and at
most one award. The new one carries the things the board actually needs to
show a squadron AS IT STOOD ON A DAY: when a man joined, when he left and
why, his victories with their dates, and his awards with theirs.

Nothing is invented here. What the old file did not know comes across as
null, and the validator lists what is still missing.

    python3 tools/roster_convert.py squadronroom/rosters/32.json
    python3 tools/roster_convert.py squadronroom/roster.seed.json -o squadronroom/rosters/92.json
"""
import json, re, sys, argparse, datetime, os

MONTHS = {m: i + 1 for i, m in enumerate(
    ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])}

def parse_date(text):
    """'KIA 19 Oct 1940' / '24 Sept 1940' -> '1940-10-19'. None if absent."""
    if not text:
        return None
    m = re.search(r'(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{4})', str(text))
    if not m:
        return None
    mon = MONTHS.get(m.group(2)[:3].lower())
    if not mon:
        return None
    try:
        return datetime.date(int(m.group(3)), mon, int(m.group(1))).isoformat()
    except ValueError:
        return None

# How a man left the squadron, read from the old status text.
REASONS = [
    (r'\bDied of wounds\b|\bDoW\b', 'DoW'),
    (r'\bKIA\b|\bKilled\b', 'KIA'),
    (r'\bMIA\b|\bMissing\b|Failed to return', 'MIA'),
    (r'\bPOW\b|Captured|Prisoner', 'POW'),
    (r'\bWIA\b|Wounded|Injured', 'WIA'),
]

def reason_for(status):
    for pat, code in REASONS:
        if re.search(pat, status, re.I):
            return code
    return None

def convert_one(m):
    status = str(m.get('status') or '')
    fate_date = m.get('fate_date') or parse_date(status)
    reason = reason_for(status)
    survived = bool(re.search(r'Survived', status, re.I))

    # A survivor's status text is an outcome, not an event with a date: he
    # is on strength until the Battle ends. Only a man who was lost has a
    # leaving date, and it is the day he was lost.
    fate = None
    if reason and not survived:
        fate = {'status': reason, 'date': fate_date, 'note': status}
    elif reason and survived:
        # "Survived BoB (Later WIA/POW)" - it happened after the Battle
        fate = {'status': 'Survived', 'date': None, 'note': status}
    elif survived:
        fate = {'status': 'Survived', 'date': None, 'note': status}
    elif status:
        fate = {'status': 'Unknown', 'date': fate_date, 'note': status}

    total = m.get('victories')
    total = int(total) if total not in (None, '', 0) else (0 if total == 0 else None)
    vsrc = m.get('vic_source') or ''
    if vsrc == 'not researched':
        total = None

    awards = []
    aw = str(m.get('awards') or '').strip()
    if aw:
        for one in [a.strip() for a in aw.split(',') if a.strip()]:
            awards.append({'award': one, 'date': m.get('award_date')})

    return {
        'pilot': m.get('pilot'),
        'rank': m.get('rank'),
        'historical': bool(m.get('historical', True)),
        # Not researched yet: null means "on strength from the start of the
        # window", and the validator counts how many are still unknown.
        'joined': None,
        'left': fate_date if (fate and fate['status'] not in ('Survived',)) else None,
        'left_reason': (fate['status'] if fate and fate['status'] not in ('Survived', 'Unknown') else None),
        'fate': fate,
        'victories': [],                 # dated claims, when researched
        'victories_total': total,        # the Battle total when only that is known
        'vic_source': vsrc or None,
        'awards': awards,
        'codes': m.get('codes') or '',
        'serials': m.get('serials') or '',
        'portrait': m.get('portrait'),
        'src': m.get('src') or None,
        'note': m.get('note') or '',
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('infile')
    ap.add_argument('-o', '--out')
    a = ap.parse_args()
    men = json.load(open(a.infile, encoding='utf-8'))
    out = [convert_one(m) for m in men]
    dest = a.out or a.infile
    with open(dest, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write('\n')
    dated = sum(1 for m in out if m['left'])
    tot = sum(1 for m in out if m['victories_total'] is not None)
    print(f'{a.infile} -> {dest}: {len(out)} men, {dated} with a leaving date, '
          f'{tot} with a victory total, 0 with dated victories, 0 with joining dates')

if __name__ == '__main__':
    main()
