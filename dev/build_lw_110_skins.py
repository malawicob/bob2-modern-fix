#!/usr/bin/env python3
"""Work out which Bf 110 profile each Zerstoerer Gruppe flies, and when.

    python3 dev/build_lw_110_skins.py --out squadronroom/lw/skins110.json

THE 109s ARE NAMED FOR UNITS, THE 110s ARE NOT

There are forty 109 profiles named I_JG26, II_JG2 and so on, so the Room
looks a unit's aeroplane up by its own key and there is nothing to decide.
The twelve 110 profiles are named for the game's BASE SKINS -
Bf110_70_71_1940, bf110_Shark, bf110-IZG26 - because that is how BOB2
names them, and MultiSkin\\Me110_MainSkin.ms says which unit flies which,
on which dates. So the Room can pick a Zerstoerer's aeroplane the way the
game picks it, which is better than the 109 side manages.

FOUR THINGS THAT MAKE THIS FILE UNLIKE THE OTHER .ms PARSERS

  A DIFFERENT GRAMMAR. Every other MultiSkin file writes
  "use <tex>.dds, <canvasW>, <canvasH>, <sx>, <sy>, <x>, <y> if ...".
  Me110_MainSkin.ms writes "use <tex>.dds if ..." with no geometry at
  all - it selects a whole skin rather than placing a decal. A parser
  written against the seven-field form matches none of its 114 lines.

  THE UNIT IS A STAFFEL, NOT A GRUPPE. The condition reads
  unit == Gruppe"2SH", and 2SH is a Staffel key: a two-character slot
  prefix and a Staffel letter. H/K/L is the 1st, 2nd and 3rd Staffel of
  the Gruppe, M/N/P the 4th to 6th, R/S/T the 7th to 9th. I, O and Q are
  skipped, as the Luftwaffe skipped them.

  THE CASE IS INCONSISTENT. The same Staffel is written 2SH in some
  lines and 2Sh in others - 33 raw spellings for 27 real keys - so every
  comparison folds case.

  ORDER MATTERS. Conditions overlap and the first matching line wins, so
  the rules are kept in file order and read in that order.

Dates are written May1st1940, Aug21st1940, Sep8th1940. Only >=, < and ==
are used; there is no > and no <=. A whitespace-tolerant parser is needed
because the file has "date <Aug8th1940" without a space in 96 places.
"""
import argparse, json, os, re, sys

MONTHS = {'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12}
DATE = re.compile(r'([A-Z][a-z]{2})(\d{1,2})(?:st|nd|rd|th)(\d{4})')
USE  = re.compile(r'^\s*use\s+(?P<tex>[^,]+?\.dds)\s*(?:if\s+(?P<cond>.*))?$', re.I)
UNIT = re.compile(r'unit\s*==\s*Gruppe"(\w+)"', re.I)
COND = re.compile(r'date\s*(>=|<=|<|>|==)\s*([A-Z][a-z]{2}\d{1,2}(?:st|nd|rd|th)\d{4})')

# Which real unit each Staffel key belongs to, and which Staffel it is.
# Taken from the comments in Me110_MainSkin.ms itself, not from memory:
# 2SR/2SS/2ST are commented "#13LG1 #14LG1 #15LG1", so V.(Z)/LG 1 wears
# the seven-eight-nine slot letters while being the 13th to 15th Staffel.
SLOT = {'H': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 6, 'R': 7, 'S': 8, 'T': 9}
UNITS = {
    '2S': ({'H': 'I./ZG 2',  'K': 'I./ZG 2',  'L': 'I./ZG 2',
            'M': 'II./ZG 2', 'N': 'II./ZG 2', 'P': 'II./ZG 2',
            'R': 'V./LG 1',  'S': 'V./LG 1',  'T': 'V./LG 1'}),
    'U8': ({'H': 'I./ZG 26',  'K': 'I./ZG 26',  'L': 'I./ZG 26',
            'M': 'II./ZG 26', 'N': 'II./ZG 26', 'P': 'II./ZG 26',
            'R': 'III./ZG 26','S': 'III./ZG 26','T': 'III./ZG 26'}),
    'M8': ({'H': 'EG 210',    'K': 'EG 210',    'L': 'EG 210',
            'M': 'II./ZG 76', 'N': 'II./ZG 76', 'P': 'II./ZG 76',
            'R': 'III./ZG 76','S': 'III./ZG 76','T': 'III./ZG 76'}),
}


def as_date(tok):
    m = DATE.match(tok)
    if not m or m.group(1) not in MONTHS:
        return None
    return '%s-%02d-%02d' % (m.group(3), MONTHS[m.group(1)], int(m.group(2)))


def unit_of(key):
    k = key.upper()
    pre, letter = k[:2], k[2:3]
    tab = UNITS.get(pre)
    if not tab:
        return None, None
    return tab.get(letter), SLOT.get(letter)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ms', default='/mnt/d/Battle of Britain II_Latest_test/MultiSkin/Me110_MainSkin.ms')
    ap.add_argument('--art', default='squadronroom/lw/aircraft')
    ap.add_argument('--out', default='squadronroom/lw/skins110.json')
    a = ap.parse_args()

    if not os.path.exists(a.ms):
        print('cannot find %s' % a.ms, file=sys.stderr)
        return 2
    have = {os.path.splitext(f)[0].lower(): f
            for f in os.listdir(a.art) if f.lower().endswith('.png')}

    rules = []
    missing = set()
    for line in open(a.ms, encoding='latin-1'):
        line = line.split('#')[0].rstrip()
        m = USE.match(line)
        if not m:
            continue
        tex = m.group('tex').replace('\\', '/').split('/')[-1]
        tex = os.path.splitext(tex)[0]
        cond = m.group('cond') or ''
        keys = [k.upper() for k in UNIT.findall(cond)]
        dates = [(op, as_date(tok)) for op, tok in COND.findall(cond)]
        png = have.get(tex.lower())
        if not png:
            missing.add(tex)
            continue
        rules.append({'skin': png, 'staffel_keys': keys,
                      'from': next((d for o, d in dates if o == '>='), None),
                      'to':   next((d for o, d in dates if o in ('<', '<=')), None)})

    # unit + staffel slot -> the rules that can serve it, in file order
    per = {}
    for i, r in enumerate(rules):
        for k in (r['staffel_keys'] or ['*']):
            unit, slot = unit_of(k) if k != '*' else (None, None)
            key = '*' if k == '*' else ('%s|%d' % (unit, slot) if unit else None)
            if key is None:
                continue
            per.setdefault(key, []).append(
                {'order': i, 'skin': r['skin'], 'from': r['from'], 'to': r['to']})

    doc = {'note': ("Which Bf 110 profile a Zerstoerer Gruppe flies, and when, "
                    "read out of MultiSkin/Me110_MainSkin.ms. Keys are "
                    "'<unit>|<staffel slot 1-9>'; '*' holds the date-only "
                    "fallbacks the file ends with. Rules are in FILE ORDER and "
                    "the first that matches wins, because the conditions "
                    "overlap. Built by dev/build_lw_110_skins.py."),
           'default': 'Bf110_70_71_1940.png',
           'by_unit_staffel': per}
    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(doc, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    units = sorted({k.split('|')[0] for k in per if k != '*'})
    print('%d rules over %d unit/Staffel keys -> %s' % (len(rules), len(per), a.out))
    print('  units covered: %s' % ', '.join(units))
    print('  date-only fallbacks: %d' % len(per.get('*', [])))
    if missing:
        print('  skins named in the rules with no profile cut: %s'
              % ', '.join(sorted(missing)), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
