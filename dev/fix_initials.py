#!/usr/bin/env python3
"""Repair the names an ASCII-only regex mangled.

build_rosters.py abbreviated forenames with [A-Za-z]+, which stops dead
at a diacritic: Frantisek split into "Franti" and "ek" and came out as
"F.e.", Vaclav as "V.c.", Bolesław as "B.a.". The builder is fixed, but
the rosters it already wrote carry the damage, and regenerating them
would throw away the campaign casualties and the hand research merged in
since. This repairs the machine-abbreviated names in place, taking each
man's real forename from the Holloway list he came from.

A hand-researched roster spells its forenames out ("Andrews, Sydney E.")
and is left exactly as it is. So are the particles: Hartland de
Montarville Molson really is H.d.M.
"""
import json, glob, re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROSTERS = os.path.join(os.path.dirname(HERE), 'squadronroom', 'rosters')
HOLLOWAY = os.path.expanduser('~/bob2/bbm/holloway.json')

WORD = r"[^\W\d_][\w'’-]*"

def initials(rest):
    return ''.join(w[0] for w in re.findall(WORD, rest, re.UNICODE))

def clean_forenames(rest):
    """Holloway carries titles and nicknames in the forename field.

    'Sir John William Maxwell "Max", 2nd Baron Beaverbrook' is one man's
    entry; his initials are J.W.M., not S.J.W.M.M.n.B.B."""
    rest = rest.split(',', 1)[0]                                  # ', 2nd Baron ...'
    rest = re.sub(r'"[^"]*"|“[^”]*”', ' ', rest)   # '"Max"'
    rest = re.sub(r'^\s*(Sir|The\s+Hon\.?|Hon\.?|Lord)\s+', ' ', rest, flags=re.I)
    return rest.strip()

def main():
    men = json.load(open(HOLLOWAY, encoding='utf-8'))
    if isinstance(men, dict):
        men = men.get('men', [])
    by_sur = {}
    for m in men:
        n = m.get('name', '')
        if ',' not in n:
            continue
        sur, rest = n.split(',', 1)
        by_sur.setdefault(sur.strip(), []).append(rest.strip())

    machine = re.compile(r"^(.*?),\s*((?:[A-Za-z]\.)+)$")
    suspect = re.compile(r"[A-Z]\.[a-z]")
    fixed = unresolved = 0
    for path in sorted(glob.glob(os.path.join(ROSTERS, '*.json'))):
        roster = json.load(open(path, encoding='utf-8'))
        touched = False
        for p in roster:
            mm = machine.match(p.get('pilot', ''))
            if not mm:
                continue
            sur, first = mm.group(1), mm.group(2)[:1].upper()
            # match on the cleaned forename OR the raw one: a man recorded
            # as "Sir John ..." was abbreviated to S. by the old rule, so
            # his roster entry starts with the title's letter, not his own
            cands = [r for r in by_sur.get(sur, [])
                     if first in (clean_forenames(r)[:1].upper(), r[:1].upper())]
            if len(cands) != 1:
                # nothing to check it against, and nothing that looks wrong
                if not suspect.search(p['pilot']):
                    continue
                print('  ? %-28s %d candidates in %s' % (p['pilot'], len(cands), os.path.basename(path)))
                unresolved += 1
                continue
            new = '%s, %s.' % (sur, '.'.join(initials(clean_forenames(cands[0]))))
            if new != p['pilot']:
                print('  %-28s -> %-24s (%s, %s)' % (p['pilot'], new, os.path.basename(path), cands[0]))
                p['pilot'] = new
                touched = True
                fixed += 1
        if touched:
            with open(path, 'w', encoding='utf-8') as fh:
                json.dump(roster, fh, ensure_ascii=False, indent=1)
                fh.write('\n')
    print('repaired %d names, %d could not be resolved' % (fixed, unresolved))
    return 0

if __name__ == '__main__':
    sys.exit(main())
