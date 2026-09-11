#!/usr/bin/env python3
"""Work out which Bf 109 skin each aeroplane wears, and when.

    python3 dev/build_lw_109_skins.py --out squadronroom/lw/skins109.json

THE 109 NOW WORKS THE WAY THE 110 ALREADY DID

Until 11 September 2026 the Room had forty 109 plates named per Gruppe,
I_JG26 and the like, and picked one by unit name with no reference to the
campaign date at all. They were also Bf 109Fs. The 110s had always been
better served: named for the game's BASE SKINS, with Me110_MainSkin.ms
saying which unit flies which on which dates.

Patrick redrew the lot, 162 side views named for the .DDS each was drawn
from, so the same thing is now possible here. Me109MainSkin.ms names 126
distinct skins and every one of them has a drawing.

WHAT THIS FILE IS

178 rules, in order, and THE FIRST ONE THAT MATCHES WINS. That is the
whole of the evaluation model and it has to be preserved, because the
conditions overlap heavily: a unit-and-aeroplane rule sits above a
planeid-only rule which sits above "if 1 == 1".

A rule may constrain any of three things, and most constrain two:

  unit      24 units are named. 27 rules name none, and apply to any
            unit whose own rules did not match first.
  planeid   the aeroplane's place in its Gruppe, 1 to 36. One rule
            constrains no planeid: the final catch-all, Replacement.DDS.
  date      5 rules only, using <, <= and >=. There is no > anywhere.

The grammar is the short form, "use <tex>.dds if <cond>", with no
geometry - it selects a whole skin rather than placing a decal, exactly
as Me110_MainSkin.ms does. A parser written for the seven-field form
matches none of it.

A WARNING ABOUT THE CONDITIONS

They are written "planeid == 2 or planeid == 4 or planeid == 9 and
unit == IJG3" with no brackets anywhere. Read strictly by C precedence
that is (planeid==2) or (planeid==4) or (planeid==9 and unit==IJG3),
which would put I./JG 3's skin on everybody's aeroplane number 2. The
intent is plainly "(planeid in the list) and (unit is one of these)", the
comments in the file agree, and that is how it is read here. Where the
two readings differ the game is the authority and this is a guess, so it
is recorded as one.
"""
import argparse, datetime, json, os, re, sys

MONTHS = {'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12}
DATE = re.compile(r'([A-Z][a-z]{2})(\d{1,2})(?:st|nd|rd|th)(\d{4})')
USE  = re.compile(r'^\s*use\s+(?P<tex>.+?\.dds)\s*(?:if\s+(?P<cond>.*))?$', re.I)
GRUPPE_FIRST = {'I': 1, 'II': 4, 'III': 7, 'IV': 10, 'V': 13}


def iso(tok):
    m = DATE.match(tok)
    if not m:
        return None
    mon = MONTHS.get(m.group(1))
    if not mon:
        return None
    return '%s-%02d-%02d' % (m.group(3), mon, int(m.group(2)))


def shift(d, days):
    y, m, dd = (int(x) for x in d.split('-'))
    t = datetime.date(y, m, dd) + datetime.timedelta(days=days)
    return t.isoformat()


def unit_name(u):
    """IIIJG26 -> III./JG 26, and the first Staffel number of that Gruppe."""
    m = re.match(r'(I{1,3}|IV|V)(JG|ZG|LG)(\d+)$', u)
    if not m:
        return None, None
    g, arm, num = m.groups()
    first = GRUPPE_FIRST.get(g)
    if first is None:
        return None, None
    return '%s./%s %s' % (g, arm, num), first


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ms',  default='/mnt/d/Battle of Britain II_Latest_test/MultiSkin/Me109MainSkin.ms')
    ap.add_argument('--art', default='squadronroom/lw/aircraft')
    ap.add_argument('--out', default='squadronroom/lw/skins109.json')
    a = ap.parse_args()

    if not os.path.exists(a.ms):
        print('no rule file at %s' % a.ms, file=sys.stderr)
        return 1

    rules, unknown = [], set()
    for raw in open(a.ms, encoding='latin-1', errors='ignore'):
        line = raw.split('#')[0].rstrip()
        m = USE.match(line)
        if not m:
            continue
        skin = os.path.splitext(os.path.basename(m.group('tex').replace('\\', '/')))[0]
        cond = m.group('cond') or ''
        pids = sorted({int(x) for x in re.findall(r'planeid\s*==\s*(\d+)', cond)})
        units = []
        for u in re.findall(r'unit\s*==\s*(\w+)', cond):
            n, _ = unit_name(u)
            if n:
                if n not in units:
                    units.append(n)
            else:
                unknown.add(u)
        rec = {'skin': skin}
        if units:
            rec['units'] = units
        if pids:
            rec['planeids'] = pids
        for op, tok in re.findall(r'date\s*(>=|<=|<|>|==)\s*([A-Za-z]{3}\d{1,2}(?:st|nd|rd|th)\d{4})', cond):
            d = iso(tok)
            if not d:
                continue
            # Normalised to INCLUSIVE bounds here, so the Room only ever
            # asks "is the campaign date between from and to". The file
            # mixes "date <Aug21st1940" with "date <= Aug31st1940" and a
            # day either way is a day of the wrong aeroplane.
            if op == '>':
                rec['from'] = shift(d, 1)
            elif op == '>=':
                rec['from'] = d
            elif op == '<':
                rec['to'] = shift(d, -1)
            elif op == '<=':
                rec['to'] = d
            else:
                rec['from'] = rec['to'] = d
        rules.append(rec)

    # every skin a rule names must actually have a drawing, or the Room
    # will fall through to a plate that is not the one the game shows
    have = {os.path.splitext(f)[0].lower(): f
            for f in os.listdir(a.art) if f.lower().endswith('.png')}
    def key(s):
        return re.sub(r'[^a-z0-9]', '', re.sub(r'_sideview$', '', s, flags=re.I).lower())
    byk = {key(os.path.splitext(f)[0]): f for f in have.values()}
    missing = []
    for r in rules:
        f = byk.get(key(r['skin']))
        if f:
            r['file'] = f
        else:
            missing.append(r['skin'])

    os.makedirs(os.path.dirname(a.out) or '.', exist_ok=True)
    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump({'note': ('Which Bf 109 skin an aeroplane wears, from the game\'s own '
                            'Me109MainSkin.ms. Rules are IN FILE ORDER and the first '
                            'match wins. A rule with no units applies to any unit whose '
                            'own rules did not match first; one with no planeids applies '
                            'to any aeroplane. Built by dev/build_lw_109_skins.py.'),
                   'rules': rules}, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    named = sorted({u for r in rules for u in r.get('units', [])})
    dated = [r for r in rules if 'from' in r or 'to' in r]
    print('%d rules, %d distinct skins, %d units named -> %s'
          % (len(rules), len({r['skin'] for r in rules}), len(named), a.out))
    print('  %d rules carry a date, %d name no unit, %d name no aeroplane'
          % (len(dated), sum(1 for r in rules if 'units' not in r),
             sum(1 for r in rules if 'planeids' not in r)))
    if missing:
        print('  ! %d skin(s) with no drawing: %s'
              % (len(missing), ', '.join(sorted(set(missing))[:6])), file=sys.stderr)
    for u in sorted(unknown):
        print('  ! unit token not understood: %s' % u, file=sys.stderr)
    return 1 if (missing or unknown) else 0


if __name__ == '__main__':
    sys.exit(main())
