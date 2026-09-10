#!/usr/bin/env python3
"""Cut the Bf 109 markings out of Patrick's skin-preview tiles.

    python3 dev/build_lw_markings.py \
        --src "/mnt/d/BOB2 Files/skin-previews" \
        --out squadronroom/lw/markings

WHAT A GERMAN FIGHTER CARRIED, AND WHO DECIDED IT

An RAF fighter's markings are two squadron code letters, an individual
letter and a serial, and the Room paints them on the Spitfire. A Bf 109
worked differently and only one part of it was the pilot's own:

  THE INDIVIDUAL NUMBER, forward of the Balkenkreuz, in his STAFFEL's
  colour. White for the 1st, 4th and 7th Staffel, red for the 2nd, 5th
  and 8th, yellow for the 3rd, 6th and 9th. This is the one a player
  picks.

  THE GRUPPE SYMBOL, aft of the cross. I. Gruppe carried nothing at all,
  II. a horizontal bar, III. a vertical bar or a wavy line depending on
  the Geschwader. Not a choice: it follows the unit he is posted to.

  THE GESCHWADER EMBLEM on the cowling. Also not a choice.

  A STAB CHEVRON instead of a number, for the handful of men on the
  Geschwader or Gruppe staff. The Kommandeur's double chevron and bar,
  the adjutant's single chevron, the technical officer's chevron and
  circle. Not a choice either: it follows his appointment.

So the Room offers the number and derives the rest, which is the right
way round and also the historically true one.

THE TILES

Patrick's folder holds 1,081 of them at 128 x 128 with transparency,
covering every marking in the game for both sides and all types. This
takes the ones a 109 needs and leaves the rest: the bomber code letters,
the spinners, the Stuka and Do 17 bands, and the RAF sheets.

Numbers 1 to 15 exist in all four colours, which is exactly the range a
Staffel used. 0 and 16 exist in black only and are not offered, because
a number a man cannot have in his own Staffel's colour is not a number
he can have.

Everything is trimmed to its own bounding box before it is saved. The
tiles are mostly empty space and the Room places these by fraction of
the aeroplane's width, so a mark that carries its original padding lands
in the wrong place and cannot be sized against anything.
"""
import argparse, json, os, re, shutil, sys
from PIL import Image

# game spelling is inconsistent about case and spacing, so every lookup
# goes through a folded index rather than an exact filename
def index(d):
    return {f.lower(): f for f in os.listdir(d) if f.lower().endswith('.png')}


def pick(idx, *names):
    for n in names:
        f = idx.get((n + '.png').lower())
        if f:
            return f
    return None


NUMBERS = range(1, 16)
COLOURS = {
    # colour -> the tile to use, best first. The second name in each is the
    # plain fill without an outline, kept as a fallback only.
    'white':  ('%d_white black', '%d_white'),
    'red':    ('%d_Red white', '%d_red white', '%d_red'),
    'yellow': ('%d_yellow black', '%d_yellow'),
    'black':  ('%d_black white', '%d_black'),
}

GRUPPE = {
    'II_white':      ('II_gruppe bar_White black', 'II_gruppe bar _White black', 'II_Gruppe'),
    'II_red':        ('II_gruppe bar_Red White', 'II_gruppe bar _Red White'),
    'II_yellow':     ('II_gruppe bar_Yellow black', 'II_gruppe bar _Yellow black'),
    'II_black':      ('II_gruppe bar_Black White',),
    'III_white':     ('III_gruppe bar_white black', 'III_Gruppe_Bar'),
    'III_red':       ('III_gruppe bar_Red White',),
    'III_yellow':    ('III_gruppe bar_Yellow black',),
    'III_black':     ('III_gruppe bar_Black white',),
    'IIIwavy_white': ('III_Wavy Bar_White Black', 'III_Staffel_Wavy'),
    'IIIwavy_red':   ('III_Wavy Bar_Red White', 'III_Staffel_Wavy_Red'),
    'IIIwavy_yellow':('III_Wavy bar_Yellow black', 'III_Staffel_Wavy_Yellow'),
}

STAB = {
    'kommandeur':  ('Stab_Gruppen Kommandeur V1',),
    'kommandeur2': ('Stab_Gruppen Kommandeur V2',),
    'technical':   ('Stab_Technical Officer',),
    'adjutant':    ('Stab_adjutant',),
    'adjutant2':   ('Stab_adjutant_2',),
}

# Which emblem belongs to which unit. Gruppe first, then the Geschwader as
# a fallback, because several Geschwader had one badge for the whole unit
# and others gave each Gruppe its own. Only units whose badge is actually
# in the folder appear here; the rest get nothing, which is better than
# putting one Geschwader's badge on another's aeroplane.
EMBLEMS = {
    'I./JG 27':   'IJG27',
    'II./JG 27':  'IIJG27',
    'III./JG 27': 'IIIJG27',
    'II./JG 3':   'IIJG3',
    'II./JG 51':  'IIJG51',
    'I./JG 54':   'IJG54',
    'II./JG 54':  'IIJG54',
    'III./JG 54': 'IIIJG54',
    'III./JG 52': 'IIIJG52',
    'I./ZG 26':   'IZG26',
    'II./ZG 26':  'ZG26_II',
    'I./ZG 2':    'ZG2_I',
    'II./ZG 2':   'ZG2_I',
    'I./ZG 52':   'ZG52_I',
    'III./ZG 76': 'IIIZG76',
    # These two are named for a STAFFEL in the tile's own filename, so
    # they are mapped to the Gruppe that Staffel belonged to and no
    # further. 9. Staffel is III. Gruppe and 4. Staffel is II., which is
    # arithmetic rather than a guess.
    'III./JG 3':  '9JG3',
    'II./JG 52':  '4JG52',
}

# JG 53's marking was not a cowling badge. After the ace of spades was
# painted out in the summer of 1940 the Geschwader wore a red band round
# the rear fuselage, and that is what the tile holds. It is carried here
# because it is the unit's identifying marking, and flagged as a band so
# the Room puts it on the fuselage rather than on the nose.
BANDS = {
    'JG 53': 'JG53_Redband_Emblem_thin',
}
GESCHWADER_EMBLEMS = {
    'JG 26': 'JG26',
    'JG 2':  'JG2_Richtofenv1',
    'JG 51': 'JG51_1',
}

# Which of the two III. Gruppe symbols a Geschwader used. The vertical bar
# was the common one; JG 3, JG 52 and JG 53 wore the wavy line. Anything
# not named here gets the bar.
WAVY = ('JG 3', 'JG 52', 'JG 53')


def save(src, dst, maxpx=320):
    im = Image.open(src).convert('RGBA')
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)
    if max(im.size) > maxpx:
        r = maxpx / float(max(im.size))
        im = im.resize((max(1, int(im.size[0] * r)), max(1, int(im.size[1] * r))), Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst)
    return im.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default='/mnt/d/BOB2 Files/skin-previews')
    ap.add_argument('--out', default='squadronroom/lw/markings')
    ap.add_argument('--oob', default='squadronroom/lw/oob.json')
    ap.add_argument('--json', default='squadronroom/lw/markings.json')
    a = ap.parse_args()

    if not os.path.isdir(a.src):
        print('cannot find %s' % a.src, file=sys.stderr)
        return 2
    idx = index(a.src)
    if os.path.isdir(a.out):
        shutil.rmtree(a.out)

    made = {'numbers': {}, 'gruppe': {}, 'stab': {}, 'emblems': {}}
    missing = []

    for n in NUMBERS:
        for col, cands in COLOURS.items():
            f = pick(idx, *[c % n for c in cands])
            if not f:
                missing.append('number %d %s' % (n, col)); continue
            name = 'numbers/%d_%s.png' % (n, col)
            save(os.path.join(a.src, f), os.path.join(a.out, name))
            made['numbers'].setdefault(str(n), {})[col] = name

    for key, cands in GRUPPE.items():
        f = pick(idx, *cands)
        if not f:
            missing.append('gruppe %s' % key); continue
        name = 'gruppe/%s.png' % key
        save(os.path.join(a.src, f), os.path.join(a.out, name))
        made['gruppe'][key] = name

    for key, cands in STAB.items():
        f = pick(idx, *cands)
        if not f:
            missing.append('stab %s' % key); continue
        name = 'stab/%s.png' % key
        save(os.path.join(a.src, f), os.path.join(a.out, name))
        made['stab'][key] = name

    for who, tile in list(EMBLEMS.items()) + list(GESCHWADER_EMBLEMS.items()):
        f = pick(idx, tile)
        if not f:
            missing.append('emblem %s (%s)' % (who, tile)); continue
        name = 'emblems/%s.png' % re.sub(r'[^A-Za-z0-9]', '', who)
        save(os.path.join(a.src, f), os.path.join(a.out, name), maxpx=256)
        made['emblems'][who] = name

    made['bands'] = {}
    for who, tile in BANDS.items():
        f = pick(idx, tile)
        if not f:
            missing.append('band %s (%s)' % (who, tile)); continue
        name = 'bands/%s.png' % re.sub(r'[^A-Za-z0-9]', '', who)
        save(os.path.join(a.src, f), os.path.join(a.out, name), maxpx=256)
        made['bands'][who] = name

    # what the Room needs to know, written beside the folder so nothing in
    # the PowerShell has to carry a table of filenames
    units = []
    if os.path.exists(a.oob):
        with open(a.oob, encoding='utf-8') as fh:
            units = [r for r in json.load(fh) if r.get('fighter')]
    per_unit = {}
    for u in units:
        unit = u['unit']; gesch = u['geschwader']
        emb = made['emblems'].get(unit) or made['emblems'].get(gesch)
        band = made['bands'].get(gesch)
        g = unit.split('.')[0]
        sym = None
        if g == 'II':
            sym = 'II'
        elif g == 'III':
            sym = 'IIIwavy' if gesch in WAVY else 'III'
        per_unit[unit] = {'emblem': emb, 'band': band, 'gruppe_symbol': sym}

    doc = {
        'note': ('Markings for the Bf 109. The individual number is the '
                 'pilot\'s own choice; the Gruppe symbol, the Geschwader '
                 'emblem and any Stab chevron follow the unit and the '
                 'appointment. Built by dev/build_lw_markings.py from '
                 'Patrick\'s skin-preview tiles.'),
        'staffel_colours': {'1': 'white', '2': 'red', '3': 'yellow',
                            '4': 'white', '5': 'red', '6': 'yellow',
                            '7': 'white', '8': 'red', '9': 'yellow'},
        'numbers': made['numbers'],
        'gruppe': made['gruppe'],
        'stab': made['stab'],
        'emblems': made['emblems'],
        'bands': made['bands'],
        'units': per_unit,
    }
    with open(a.json, 'w', encoding='utf-8') as fh:
        json.dump(doc, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    n_files = sum(len(v) for v in made['numbers'].values()) + \
              len(made['gruppe']) + len(made['stab']) + len(made['emblems']) + len(made['bands'])
    withemb = sum(1 for v in per_unit.values() if v['emblem'] or v['band'])
    print('%d tiles cut -> %s' % (n_files, a.out))
    print('  numbers  %d in four colours' % len(made['numbers']))
    print('  gruppe   %d symbols' % len(made['gruppe']))
    print('  stab     %d chevrons' % len(made['stab']))
    print('  emblems  %d and %d fuselage band(s), covering %d of the %d fighter Gruppen'
          % (len(made['emblems']), len(made['bands']), withemb, len(per_unit)))
    if missing:
        print('  not found: %s' % ', '.join(missing), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
