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

Numbers 1 to 15 exist in the Staffel colours, which is exactly the range
a Staffel used. 0 and 16 exist in black only and are not offered, because
a number a man cannot have in his own Staffel's colour is not a number
he can have. Brown on black is cut as well, for the three Gruppen whose
numbers change colour partway through the campaign; see number_dates
below.

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
    # Brown on black, worn by 3. Staffel of II./JG 26 and I./JG 51 until
    # 18 August 1940 and by nobody else. It is here because
    # Me109_PlaneID_1.ms says so, not because it looks likely.
    'brown':  ('%d_brown black', '%d_Brown black', '%d_Brown Black', '%d_brown blackv3'),
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

# WHICH GRUPPE SYMBOL A UNIT WEARS IS NOT DECIDED HERE ANY MORE.
#
# There was a table here saying JG 3, JG 52 and JG 53 wore the wavy line
# and everyone else the bar. It was written from memory and it was wrong.
# Me109_PlaneID_2.ms gives III./JG 3, III./JG 51 and III./JG 53 the
# VERTICAL BAR, and the only wavy rules in the file name III./JG 2. It
# also gives each symbol its own position, so the table was wrong twice
# over.
#
# dev/measure_markings.py now reads the assignment straight out of those
# rules into marking-positions.json, and the Room uses that. This script
# only cuts the tiles.


# =====================================================================
#  THE Bf 110, which wears letters where a 109 wears a number
#
#  A Zerstoerer carries a bomber-style code: the Geschwader's two
#  characters, the Balkenkreuz, the individual aircraft letter and the
#  Staffel letter - U8+DH. Nothing about it resembles the 109's single
#  numeral, and all of it comes out of the Me110_*.ms rules.
#
#  The individual letter's COLOUR follows the Staffel exactly as the
#  109's number does: the 1st, 4th and 7th Staffel white, the 2nd, 5th
#  and 8th red, the 3rd, 6th and 9th yellow. The Staffel letter is always
#  black - there is no white, red or yellow Staffel letter anywhere in
#  the rules.
# =====================================================================
LETTERS_110 = 'ABCDEFGHIJK'          # the fuselage rules stop at K
# The STAFFEL letter is a different alphabet from the individual letter,
# and cutting only A to K left every Zerstoerer without one: the Staffel
# letters are H K L for the 1st to 3rd, M N P for the 4th to 6th, R S T
# for the 7th to 9th, with B C D for the Stab machines. I, O and Q are
# skipped, as the Luftwaffe skipped them. They exist in black only.
STAFFEL_LETTERS_110 = 'BCDHKLMNPRST'
LETTER_COLOUR_110 = {
    'white':  'LW_White_%s',
    'red':    'LW_Red_White_%s',
    'yellow': 'LW_Yellow_%s',
    'black':  'LW_Black_%s',
}
# The Staffel letter by its slot in the Gruppe. I, O and Q are skipped,
# as the Luftwaffe skipped them.
STAFFEL_LETTER = {1: 'H', 2: 'K', 3: 'L', 4: 'M', 5: 'N', 6: 'P',
                  7: 'R', 8: 'S', 9: 'T'}
# Which two characters each unit painted, from Me110_Geshwader_Code.ms.
# Note the painted code is NOT the Staffel key's prefix: the 2S* units
# wear 3M, A2 or L1 depending on the Gruppe.
GESCHWADER_CODE_110 = {
    'I./ZG 2':    '3M_Code',
    'II./ZG 2':   'A2_Code2',
    'V./LG 1':    'L1_Code',
    'I./ZG 26':   'U8_Code',
    'II./ZG 26':  '3U_Code',
    'III./ZG 26': '3U_Code',
    'EG 210':     'S9_Code',
    'II./ZG 76':  'M8_Code',
    'III./ZG 76': '2N_Code2',
}



# ---------------------------------------------------------------------
#  The number's colour changes with the date, for three Gruppen
# ---------------------------------------------------------------------
# The Staffel's colour is the rule almost everywhere: 1., 4. and 7. wore
# white, 2., 5. and 8. red, 3., 6. and 9. yellow. Me109_PlaneID_1.ms
# names three Gruppen where the date overrides that, and the Room was
# ignoring all of it because the 109 never looked at the campaign date at
# all. Derived here rather than typed, so it stays true if the rules move.
#
# planeid is the aeroplane's place in the Gruppe, 1 to 36, so the Staffel
# it belongs to is ((planeid - 1) // 12) + 1 counted within the Gruppe,
# and the Gruppe's own numeral turns that into 1 to 9.
GRUPPE_FIRST = {'I': 1, 'II': 4, 'III': 7, 'IV': 10, 'V': 13}
MS_DATES = {
    'May1st1940':  '1940-05-01', 'Aug18th1940': '1940-08-18',
    'Aug21st1940': '1940-08-21', 'Aug31st1940': '1940-08-31',
    'Sep1st1940':  '1940-09-01', 'Oct1st1940':  '1940-10-01',
    'Oct31st1940': '1940-10-31',
}
# tile suffix in the .ms -> the colour key this script cuts
MS_COLOUR = {
    'brown black': 'brown', 'brown blackv3': 'brown',
    'black white': 'black', 'white black': 'white',
    'red white': 'red', 'red': 'red', 'yellow black': 'yellow',
}


def ms_unit_to_room(u):
    """IIIJG27 -> III./JG 27, and the Staffel numbers of that Gruppe."""
    m = re.match(r'(I{1,3}|IV|V)(JG|ZG|LG)(\d+)$', u)
    if not m:
        return None, None
    g, arm, num = m.group(1), m.group(2), m.group(3)
    first = GRUPPE_FIRST.get(g)
    if first is None:
        return None, None
    return '%s./%s %s' % (g, arm, num), first


def number_dates(ms_dir):
    """Where the number's colour depends on the date, both sides of it.

    A dated rule only ever says what is worn on ONE side of the date. The
    other side comes from the undated rule for the same aeroplane, which
    is why both are collected: III./JG 27's 8. Staffel is red until 21
    August because a dated rule says so, and black on white afterwards
    because that is what it falls through to.
    """
    path = os.path.join(ms_dir, 'Me109_PlaneID_1.ms')
    if not os.path.exists(path):
        return []

    def rule(s):
        if not s.lower().startswith('use') or ' if ' not in s:
            return None
        m = re.match(r'use\s+(.+?)\.dds\s*,', s, re.I)
        if not m:
            return None
        tile = os.path.basename(m.group(1).replace('\\', '/'))
        colour = MS_COLOUR.get(re.sub(r'^\d+_?', '', tile).strip().lower())
        cond = s.split(' if ', 1)[1]
        pids = [int(x) for x in re.findall(r'planeid\s*==\s*(\d+)', cond)]
        units = re.findall(r'unit\s*==\s*(\w+)', cond)
        dts = re.findall(r'date\s*(<=|>=|<|>)\s*(\w+)', cond)
        if not (colour and pids and units):
            return None
        return colour, units, pids, dts

    # The colour an aeroplane gets when no rule names its unit. Every
    # such rule in the file is white on black, but it is read rather than
    # assumed, because that is the point of doing any of this.
    generic = None
    for ln in open(path, encoding='latin-1', errors='ignore'):
        t = ln.strip()
        if not t.lower().startswith('use') or ' if ' not in t or 'unit ==' in t:
            continue
        m = re.match(r'use\s+(.+?)\.dds\s*,', t, re.I)
        if m and 'planeid' in t:
            tile = os.path.basename(m.group(1).replace('\\', '/'))
            c = MS_COLOUR.get(re.sub(r'^\d+_?', '', tile).strip().lower())
            if c:
                generic = c
                break

    dated, plain = {}, {}
    for ln in open(path, encoding='latin-1', errors='ignore'):
        r = rule(ln.strip())
        if not r:
            continue
        colour, units, pids, dts = r
        for u in units:
            unit, first = ms_unit_to_room(u)
            if not unit:
                continue
            for pid in pids:
                key = (unit, first + (pid - 1) // 12)
                if dts:
                    for op, tok in dts:
                        d = MS_DATES.get(tok)
                        if d:
                            dated.setdefault(key, (colour, op, d))
                else:
                    plain.setdefault(key, colour)

    out = []
    for key in sorted(dated):
        colour, op, d = dated[key]
        other = plain.get(key) or generic
        row = {'unit': key[0], 'staffel': key[1], 'date': d}
        if op in ('<', '<='):
            row['before'], row['after'] = colour, other
        else:
            row['before'], row['after'] = other, colour
        out.append(row)
    return out

def save(src, dst, maxpx=320, keep_canvas=True):
    """Copy one tile, KEEPING ITS CANVAS.

    The tiles were trimmed to their own bounding box at first, and that
    was wrong. MultiSkin places these by the corner of the WHOLE 128 x 128
    tile and sizes them as a fraction of it: "1_yellow black.dds, 2048,
    2048, 0.070, 0.068, 1165, 190" means the tile goes at (1165, 190) at
    seven per cent of the canvas wide, and the numeral sits wherever it
    sits inside that tile. Trim the padding away and both the position and
    the size are wrong, and wrong by a different amount for every digit,
    because a 1 is narrow and a 7 is not.

    Keeping the canvas means the game's own coordinates can be used
    directly and every digit lands in the same place.
    """
    im = Image.open(src).convert('RGBA')
    if not keep_canvas:
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
    ap.add_argument('--ms',  default='/mnt/d/Battle of Britain II_Latest_test/MultiSkin')
    ap.add_argument('--out', default='squadronroom/lw/markings')
    ap.add_argument('--oob', default='squadronroom/lw/oob.json')
    ap.add_argument('--json', default='squadronroom/lw/markings.json')
    a = ap.parse_args()

    if not os.path.isdir(a.src):
        print('cannot find %s' % a.src, file=sys.stderr)
        return 2
    idx = index(a.src)
    nd = number_dates(a.ms)
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

    # ---- the Bf 110's letters and codes -----------------------------
    made['letters110'] = {}
    for col, pat in LETTER_COLOUR_110.items():
        letters = LETTERS_110 if col != 'black' else sorted(set(LETTERS_110 + STAFFEL_LETTERS_110))
        for L in letters:
            f = pick(idx, pat % L)
            if not f:
                missing.append('110 letter %s %s' % (L, col)); continue
            name = 'letters110/%s_%s.png' % (L, col)
            save(os.path.join(a.src, f), os.path.join(a.out, name))
            made['letters110'].setdefault(L, {})[col] = name
    made['codes110'] = {}
    for unit, tile in GESCHWADER_CODE_110.items():
        f = pick(idx, tile)
        if not f:
            missing.append('110 code %s (%s)' % (unit, tile)); continue
        name = 'codes110/%s.png' % re.sub(r'[^A-Za-z0-9]', '', unit)
        save(os.path.join(a.src, f), os.path.join(a.out, name))
        made['codes110'][unit] = name
    made['staffel_letter'] = {str(k): v for k, v in STAFFEL_LETTER.items()}

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
        # no gruppe_symbol here: it comes from the game's own rules,
        # via dev/measure_markings.py
        per_unit[unit] = {'emblem': emb, 'band': band}

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
        'number_dates': nd,
        'gruppe': made['gruppe'],
        'stab': made['stab'],
        'emblems': made['emblems'],
        'bands': made['bands'],
        'letters110': made['letters110'],
        'codes110': made['codes110'],
        'staffel_letter': made['staffel_letter'],
        'units': per_unit,
    }
    with open(a.json, 'w', encoding='utf-8') as fh:
        json.dump(doc, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    # The README is WRITTEN, not kept by hand, because this script wipes
    # the folder before it rebuilds it and a hand-written one is deleted
    # the first time anybody re-runs it. That happened.
    readme = """Markings for the Bf 109, cut from Patrick's skin-preview tiles by
dev/build_lw_markings.py. This file is written by that script; edit the
script, not this.

  numbers/   1 to 15 in white, red, yellow and black
  gruppe/    the II. and III. Gruppe symbols, bar and wavy, in each colour
  stab/      the staff chevrons: Kommandeur, adjutant, technical officer
  emblems/   Geschwader and Gruppe badges
  bands/     JG 53's red fuselage band

Only the NUMBER was ever the pilot's own. The Gruppe symbol follows the
unit, the emblem follows the unit, and a chevron follows the appointment,
so the Room asks about the number and works the rest out.

The colour is the STAFFEL's, not the Gruppe's: white for the 1st, 4th and
7th Staffel, red for the 2nd, 5th and 8th, yellow for the 3rd, 6th and
9th. That is why 1., 4. and 7. all come out white although they sit in
three different Gruppen.

Numbers 1 to 15 exist in the Staffel colours and 0 and 16 in black only, so
0 and 16 are not offered: a number a man cannot have in his own Staffel's
colour is not a number he can have.

THE CANVAS IS KEPT. MultiSkin places the whole tile and sizes it as a
fraction of the 2048 skin sheet, and the glyph sits wherever it sits
inside it. Trim the padding and every digit lands somewhere different,
because a 1 is narrow and a 7 is not.

WHERE THEY GO IS NOT DECIDED HERE. ../marking-positions.json carries it,
read out of the game's own MultiSkin rules by dev/measure_markings.py,
and that includes WHICH symbol each unit wears. A table in this script
once said JG 3, JG 52 and JG 53 wore the wavy line; the rules give
III./JG 3, III./JG 51 and III./JG 53 the vertical bar and name III./JG 2
as the only wavy unit, and each symbol sits at its own position.

WHERE THE EMBLEMS DO AND DO NOT APPEAR

Every Gruppe with a profile painted in its own markings already wears its
badge in the artwork. II./JG 26's aeroplane has the Schlageter S on it
before the Room draws anything, and drawing ours on top gives it two. So
the emblem is drawn ONLY on the plain factory scheme, which is what a
Gruppe with no profile of its own falls back to.

JG 53's red band is cut but NOT DRAWN. It has no MultiSkin rule: the game
swaps the whole skin for it, so there is no position to read, and a guess
put it on top of the Gruppe's own symbol.

PROVENANCE, NOW SETTLED

These are BOB2's OWN textures. The skin-previews folder is a PNG
conversion of MultiSkin\\MultiSkinTextures in the game install: 1,080 of
its 1,081 filenames match that folder exactly, with one extra. MultiSkin
is not a stray third-party pack either; it is a feature of the official
BDG patch from 2.08 onward, documented in the game's own
Docs\\Multiskin\\README - 2.08 Multiskin feature summary.txt, dated 2008.

So the question is not "where did these come from", it is "may a mod
redistribute 97 small crops of the game's own art". The mod is useless to
anyone who does not own BOB2, which is the ordinary footing for this, but
it is still somebody else's work and the BDG is a real and contactable
group. Credit them in the release notes, and ask if in any doubt.
"""
    with open(os.path.join(a.out, 'README.txt'), 'w', encoding='utf-8') as fh:
        fh.write(readme)

    n_files = sum(len(v) for v in made['numbers'].values()) + \
              len(made['gruppe']) + len(made['stab']) + len(made['emblems']) + len(made['bands'])
    withemb = sum(1 for v in per_unit.values() if v['emblem'] or v['band'])
    print('%d tiles cut -> %s' % (n_files, a.out))
    ncol = len(set(c for v in made['numbers'].values() for c in v))
    print('  numbers  %d in %d colours' % (len(made['numbers']), ncol))
    print('  gruppe   %d symbols' % len(made['gruppe']))
    print('  stab     %d chevrons' % len(made['stab']))
    print('  110      %d letters in %d colours, %d Geschwader codes'
          % (len(made['letters110']),
             len(next(iter(made['letters110'].values()), {})), len(made['codes110'])))
    print('  emblems  %d and %d fuselage band(s), covering %d of the %d fighter Gruppen'
          % (len(made['emblems']), len(made['bands']), withemb, len(per_unit)))
    if missing:
        print('  not found: %s' % ', '.join(missing), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
