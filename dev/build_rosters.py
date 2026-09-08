#!/usr/bin/env python3
"""Build a roster for every squadron from two sources.

WHO was on a squadron comes from the Air Ministry / Holloway list of the
Few, which is the authority on it. WHEN each man joined and left comes
from the Battle of Britain Monument's biographies, matched to him by name.

Taking membership from the biographies instead put eighty-seven men on a
board that held twenty: they mention squadron numbers for all sorts of
reasons, a unit a man joined in 1942 among them, so a mention is not
evidence that he served there during the Battle.

A squadron already researched by hand is left alone: this never overwrites
a roster whose men carry dated claims.

    python3 dev/holloway_parse.py --xml /tmp --out ~/bob2/bbm/holloway.json
    python3 dev/build_rosters.py --bbm ~/bob2/bbm --out squadronroom/rosters
"""
import json, os, re, argparse, datetime, collections

BATTLE_START, BATTLE_END = datetime.date(1940, 7, 10), datetime.date(1940, 10, 31)
SRC = 'Holloway list of the Few via Wikipedia (who served); bbm.org.uk airmen (dates)'
FATE_WORDS = {'KIA': 'Killed in action', 'MIA': 'Missing', 'POW': 'Prisoner of war',
              'WIA': 'Wounded', 'DoW': 'Died of wounds'}

def dd(x):
    try: return datetime.date.fromisoformat(str(x)[:10])
    except Exception: return None

def tidy_name(raw):
    """'H H ADAIR' -> 'Adair, H.H.' - the shape the board already uses."""
    t = re.sub(r'\s+', ' ', raw or '').strip().rstrip(',')
    if not t: return ''
    parts = t.split(' ')
    # the surname is the trailing run of capitals
    tail = []
    while parts and parts[-1].isupper() and len(parts[-1]) > 1:
        tail.insert(0, parts.pop())
    if not tail:
        tail = [parts.pop()] if parts else ['']
    surname = ' '.join(w.capitalize() if w.isupper() else w for w in tail)
    surname = re.sub(r"\bMc([a-z])", lambda m: 'Mc' + m.group(1).upper(), surname)
    initials = '.'.join(p.strip('.') for p in parts if p) 
    return f'{surname}, {initials}.' if initials else surname

RANKS = {'sgt': 'Sergeant', 'flt sgt': 'Flight Sergeant', 'f/sgt': 'Flight Sergeant',
         'p/o': 'Pilot Officer', 'f/o': 'Flying Officer', 'f/lt': 'Flight Lieutenant',
         's/ldr': 'Squadron Leader', 'w/cdr': 'Wing Commander', 'g/capt': 'Group Captain',
         'ac1': 'Aircraftman 1st Class', 'ac2': 'Aircraftman 2nd Class', 'lac': 'Leading Aircraftman',
         'sub-lt': 'Sub-Lieutenant RN', 'lt': 'Lieutenant', 'mid': 'Midshipman',
         'p/off': 'Pilot Officer', 'cpl': 'Corporal'}
def tidy_rank(raw):
    t = (raw or '').strip().rstrip('.').lower()
    return RANKS.get(t, (raw or '').strip().rstrip('.'))

def name_key(surname, initials):
    """A man is the same man in both lists when his surname and initials
    agree. Nothing else is reliable: one list gives forenames, the other
    initials, and the spellings of both wander."""
    sur = re.sub(r"[^a-z]", '', (surname or '').lower())
    ini = re.sub(r"[^a-z]", '', (initials or '').lower())
    return sur, ini

def split_holloway(name):
    """'Adair, Hubert Hastings' -> ('Adair', 'HH')"""
    name = (name or '').strip()
    if not name: return '', ''
    if ',' in name:
        sur, rest = name.split(',', 1)
    else:
        parts = name.split()
        if not parts: return '', ''
        sur, rest = parts[-1], ' '.join(parts[:-1])
    ini = ''.join(w[0] for w in re.findall(r"[A-Za-z][A-Za-z'-]*", rest))
    return sur.strip(), ini

def split_bbm(label):
    """'H H ADAIR' -> ('ADAIR', 'HH')"""
    t = re.sub(r'\s+', ' ', (label or '')).strip()
    parts = t.split(' ')
    tail = []
    while parts and parts[-1].isupper() and len(parts[-1]) > 1:
        tail.insert(0, parts.pop())
    if not tail and parts: tail = [parts.pop()]
    return ' '.join(tail), ''.join(p[0] for p in parts if p)

# The list abbreviates rank; the board spells it out, as the researched
# rosters do.
RANK_FULL = {
    'sgt': 'Sergeant', 'flt sgt': 'Flight Sergeant', 'f/sgt': 'Flight Sergeant',
    'plt off': 'Pilot Officer', 'p/o': 'Pilot Officer', 'fg off': 'Flying Officer',
    'f/o': 'Flying Officer', 'flt lt': 'Flight Lieutenant', 'f/lt': 'Flight Lieutenant',
    'sqn ldr': 'Squadron Leader', 's/ldr': 'Squadron Leader',
    'wg cdr': 'Wing Commander', 'w/cdr': 'Wing Commander',
    'gp capt': 'Group Captain', 'ac1': 'Aircraftman 1st Class',
    'ac2': 'Aircraftman 2nd Class', 'lac': 'Leading Aircraftman',
    'sub lt': 'Sub-Lieutenant RN', 'sub-lt': 'Sub-Lieutenant RN',
    'lt': 'Lieutenant', 'mid': 'Midshipman', 'cpl': 'Corporal',
    'p off': 'Pilot Officer', 'act sqn ldr': 'Squadron Leader',
}
def full_rank(r):
    t = re.sub(r'[.]', '', (r or '')).strip().lower()
    return RANK_FULL.get(t, (r or '').strip())

def pretty(name):
    """'Adair, Hubert Hastings' -> 'Adair, H.H.'"""
    sur, ini = split_holloway(name)
    sur = ' '.join(w.capitalize() if w.isupper() else w for w in sur.split())
    sur = re.sub(r"\bMc([a-z])", lambda m: 'Mc' + m.group(1).upper(), sur)
    return f'{sur}, ' + '.'.join(ini) + '.' if ini else sur

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bbm', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--oob', default='squadronroom/oob.json')
    ap.add_argument('--skip', default='32,92', help='rosters researched by hand, left alone')
    ap.add_argument('--claims', action='store_true',
                    help='attach machine-read claims (about half of them are wrong)')
    a = ap.parse_args()

    index = json.load(open(os.path.join(a.bbm, 'index.json'), encoding='utf-8'))
    posts = json.load(open(os.path.join(a.bbm, 'postings.json'), encoding='utf-8'))
    holl = json.load(open(os.path.join(a.bbm, 'holloway.json'), encoding='utf-8'))
    # Claims are NOT read in by default. dev/bbm_claims.py can read them
    # out of the same biographies, but measured against the hand-researched
    # No. 32 it gets about half of them right and misses about half, and
    # a squadron board naming real men cannot carry that. Pass --claims to
    # use it anyway, for experiments.
    claims = {}
    if a.claims:
        cpath = os.path.join(a.bbm, 'claims.json')
        claims = json.load(open(cpath, encoding='utf-8')) if os.path.exists(cpath) else {}
    want = {int(o['num']) for o in json.load(open(a.oob, encoding='utf-8'))}
    skip = {int(x) for x in a.skip.split(',') if x.strip()}

    # bbm biographies, keyed by surname and initials
    bybbm = {}
    for stem, meta in index.items():
        if not isinstance(meta, dict): continue
        sur, ini = split_bbm(meta.get('name', ''))
        if sur: bybbm.setdefault(name_key(sur, ini), stem)

    bysqn = collections.defaultdict(list)
    matched = unmatched = 0
    for man in holl:
        sur, ini = split_holloway(man['name'])
        stem = bybbm.get(name_key(sur, ini))
        rec = posts.get(stem) if stem else None
        if rec: matched += 1
        else: unmatched += 1
        dated = {p['sqn']: p for p in (rec or {}).get('postings', [])}
        died = (rec or {}).get('died')
        myclaims = claims.get(stem, []) if stem else []
        # a fate the Holloway list itself records, e.g. "KIA 6 September 1940"
        hfate = None
        mm = re.search(r'\b(KIA|KIFA|POW|MIA|WIA|DoW)\b[^,;.]{0,40}?'
                       r'(\d{1,2}\s+[A-Z][a-z]+\s+19\d\d)', man.get('notes', ''))
        if mm:
            try:
                hfate = (mm.group(1), datetime.datetime.strptime(
                    mm.group(2), '%d %B %Y').date().isoformat())
            except ValueError: hfate = None
        if not sur: continue          # an empty row in the list
        for sqn in man['squadrons']:
            if sqn not in want: continue
            p = dated.get(sqn)
            joined = p.get('joined') if p else None
            left = p.get('left') if p else None
            reason = 'posted' if left else None
            later_death = None
            end_date = died or (hfate[1] if hfate else None)
            if end_date:
                ed = dd(end_date)
                dj, dl = dd(joined), dd(left)
                inside = ((dj is None or ed >= dj) and (dl is None or ed <= dl))
                if inside and BATTLE_START <= ed <= BATTLE_END:
                    left = end_date
                    reason = hfate[0] if hfate and hfate[0] in ('KIA', 'MIA', 'POW', 'WIA', 'DoW') else 'KIA'
                    if reason == 'KIFA': reason = 'KIA'
                elif ed > BATTLE_END:
                    later_death = end_date
            if joined and dd(joined) and dd(joined) > BATTLE_END: continue
            if left and dd(left) and dd(left) < BATTLE_START: continue
            # A claim belongs to whichever squadron he was flying with that
            # day. Without a joining date we cannot say, so his claims stay
            # off the board rather than being credited to a guess.
            vics = []
            if joined:
                lo, hi = dd(joined), (dd(left) or BATTLE_END)
                for c in myclaims:
                    cd = dd(c['date'])
                    if cd and lo <= cd <= hi and BATTLE_START <= cd <= BATTLE_END:
                        vics.append(c)
                vics.sort(key=lambda c: (c['date'], c['type']))
            scored = len([v for v in vics if v['kind'] in ('destroyed', 'shared')])
            fate = ({'status': reason, 'date': left, 'note': FATE_WORDS.get(reason, reason)}
                    if reason in ('KIA', 'MIA', 'POW', 'WIA', 'DoW')
                    else {'status': 'Posted', 'date': left, 'note': 'Posted to another squadron'} if left
                    else {'status': 'Survived', 'date': None,
                          'note': 'Survived the Battle with the squadron'})
            bysqn[sqn].append({
                'pilot': pretty(man['name']), 'rank': full_rank(man.get('rank')),
                'historical': True,
                'joined': joined, 'left': left, 'left_reason': reason,
                'fate': fate,
                'victories': vics,
                'victories_total': (scored or None),
                'vic_source': ('read from his biography' if vics else 'not researched'),
                'awards': ([{'award': x.strip(), 'date': None}
                            for x in re.split(r'[,&]', man.get('awards', '')) if x.strip()]),
                'codes': '', 'serials': '', 'portrait': None,
                'src': SRC,
                'note': (f'Died {later_death}, after the Battle.' if later_death else ''),
            })

    print(f'{matched} of {matched + unmatched} men in the list have a biography')
    os.makedirs(a.out, exist_ok=True)
    wrote = 0
    for sqn in sorted(want):
        men = bysqn.get(sqn, [])
        if sqn in skip:
            print(f'  No. {sqn:3d}: left alone (researched by hand)'); continue
        if not men:
            print(f'  No. {sqn:3d}: nobody in the list'); continue
        men.sort(key=lambda m: m['pilot'])
        seen = collections.Counter(m['pilot'] for m in men)
        used = collections.Counter()
        for m in men:
            if seen[m['pilot']] > 1:
                used[m['pilot']] += 1
                m['note'] = (m['note'] + ' ' if m['note'] else '') + \
                    f'Two men of this name and initials served with the squadron; this is the {"first" if used[m["pilot"]] == 1 else "second"} of them.'
                m['pilot'] = f'{m["pilot"]} ({used[m["pilot"]]})'
        with open(os.path.join(a.out, f'{sqn}.json'), 'w', encoding='utf-8') as f:
            json.dump(men, f, indent=1, ensure_ascii=False); f.write('\n')
        j = sum(1 for m in men if m['joined'])
        l = sum(1 for m in men if m['left'])
        print(f'  No. {sqn:3d}: {len(men):3d} men, {j:3d} joined, {l:3d} left')
        wrote += 1
    print(f'{wrote} rosters written')

if __name__ == '__main__':
    main()
