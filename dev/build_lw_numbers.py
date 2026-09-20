#!/usr/bin/env python3
"""Which number, in which colour, each Bf 109 of each Gruppe wears.

    python3 dev/build_lw_numbers.py [--ms <MultiSkin folder>]

The game does not store "your aeroplane". Each sortie it takes some of the
Gruppe's 36 aircraft, counted from 1, and puts the player in one of them;
the save records which (Campaign::playeracnum, zero based, so the rules'
planeid is playeracnum + 1: planeid 1 is the Kommandeur's machine, whose
number tile is blank.dds because the chevron is in the skin). What that
aeroplane wears is decided by MultiSkin's Me109_PlaneID_1.ms, first match
wins, some rules dated. This lifts those rules into
squadronroom/lw/planeid-numbers.json so the Room can paint the aeroplane
the game actually gave the man instead of the one he asked for.

"""
import argparse, datetime, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MONTHS = {m: i + 1 for i, m in enumerate(
    ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'])}


def room_unit(u):
    m = re.match(r'(I{1,3}|IV|V)(JG|ZG|LG)(\d+)$', u)
    return '%s./%s %s' % (m.group(1), m.group(2), m.group(3)) if m else None


def iso(tok):
    m = re.match(r'([A-Za-z]{3})(\d{1,2})(?:st|nd|rd|th)(\d{4})$', tok)
    if not m or m.group(1).lower() not in MONTHS:
        return None
    return datetime.date(int(m.group(3)), MONTHS[m.group(1).lower()], int(m.group(2)))


USE = re.compile(r'^\s*use\s+(?P<tex>[^,]+),[^i]*?(?:\bif\b(?P<cond>.*))?$', re.I)


def parse(path):
    """Same reading of a rule as build_lw_109_skins.py: every 'unit == X' in
    the condition is one of the units it applies to (they are or'd in the
    file), every 'planeid == N' one of the aeroplanes, and the dates are
    normalised to inclusive from/to bounds."""
    rules = []
    for raw in open(path, encoding='latin-1', errors='ignore'):
        line = raw.split('#')[0].rstrip()
        m = USE.match(line)
        if not m:
            continue
        tex = os.path.basename(m.group('tex').replace('\\', '/')).lower()
        cond = m.group('cond') or ''
        named = re.findall(r'unit\s*==\s*(\w+)', cond)
        units = [u for u in (room_unit(x) for x in named) if u]
        if named and not units:
            continue                    # only Stab or units the Room does not post men to
        pids = sorted({int(x) for x in re.findall(r'planeid\s*==\s*(\d+)', cond)})
        rec = {}
        if units: rec['units'] = sorted(set(units), key=units.index)
        if pids: rec['planeids'] = pids
        for op, tok in re.findall(r'date\s*(>=|<=|<|>|==)\s*([A-Za-z]{3}\d{1,2}(?:st|nd|rd|th)\d{4})', cond):
            d = iso(tok)
            if not d: continue
            one = datetime.timedelta(days=1)
            if op == '>': rec['from'] = (d + one).isoformat()
            elif op == '>=': rec['from'] = d.isoformat()
            elif op == '<': rec['to'] = (d - one).isoformat()
            elif op == '<=': rec['to'] = d.isoformat()
            else: rec['from'] = rec['to'] = d.isoformat()
        if tex.startswith('blank'):
            rec['blank'] = True
        else:
            mm = re.match(r'(\d+)(?:_([a-z]+))?', tex)
            if not mm:
                continue
            rec['number'] = int(mm.group(1))
            if mm.group(2): rec['colour'] = mm.group(2)
        rec['tex'] = tex
        rules.append(rec)
    return rules


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ms', default='/mnt/d/Battle of Britain II_Latest_test/MultiSkin')
    ap.add_argument('--out', default=os.path.join(ROOT, 'squadronroom/lw/planeid-numbers.json'))
    a = ap.parse_args()
    rules = []
    # Me109_PlaneID_1.ms only, as the other builders do: 2ndMe109_PlaneID_1.ms
    # is a second decal with rules of its own and is not the fuselage number.
    for f in ('Me109_PlaneID_1.ms',):
        p = os.path.join(a.ms, f)
        if os.path.exists(p):
            got = parse(p); rules += got
            print('%s: %d rules' % (f, len(got)))
    out = {'note': ("Which number and colour each Bf 109 of each Gruppe wears, from the game's own "
                    "Me109_PlaneID_1.ms. Rules are IN FILE ORDER and the "
                    "first match wins; a rule with no units applies to any unit, one with no planeids to any "
                    "aeroplane; from/to are inclusive dates; planeid is the save's playeracnum + 1. Built by dev/build_lw_numbers.py."),
           'rules': rules}
    json.dump(out, open(a.out, 'w', encoding='utf-8'), indent=1)
    units = sorted(set(u for r in rules for u in r.get('units', [])))
    print('%d rules, %d units, colours %s -> %s' % (len(rules), len(units), sorted(set(r.get('colour') for r in rules if r.get('colour'))), a.out))


if __name__ == '__main__':
    main()
