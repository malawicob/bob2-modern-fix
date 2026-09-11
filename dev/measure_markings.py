#!/usr/bin/env python3
"""Work out where a marking really goes, from the game's own MultiSkin rules.

    python3 dev/measure_markings.py

WHY THIS EXISTS

The Room paints markings onto side-view profile artwork, and the first
version placed them by eye. Patrick asked the obvious question: the game
puts them in the right place, so is the right place written down
somewhere? It is.

BOB2 ships MultiSkin, and MultiSkin\\*.ms are plain text rules of the form

    use <texture>.dds, <canvasW>, <canvasH>, <scaleX>, <scaleY>, <x>, <y> if <condition>

so "1_yellow black.dds, 2048, 2048, 0.070, 0.068, 1165, 190" means: draw
that numeral on the 2048-square skin with its top-left corner at pixel
(1165, 190), at seven per cent of the canvas wide. That is the game's own
answer, per aircraft type, and it is the same answer for every squadron
because the skin layout does not move.

THE ONE THING THAT HAS TO BE BRIDGED

Those coordinates are in TEXTURE space, and the Room draws on a side-view
DRAWING. The two are not the same picture. What they share is the
national marking: the Balkenkreuz on a 109, the roundel on a Spitfire or
a Hurricane, painted in both and painted in the same place on the real
aeroplane.

So the marking is found in both images and used as the ruler. A position
in the texture becomes a position on the profile by

    profile_x = cross_profile_left
                + (texture_x - cross_texture_left) * scale
    scale     = cross_profile_width / cross_texture_width

and a size converts the same way. Nothing is measured by hand and nothing
is guessed; the only assumption is that both pictures are true side views
of the same aeroplane, which is what both are for.

Doing it per profile also fixes a real problem. There are forty 109
profiles and they do not all put the cross in the same place, so one set
of fractions cannot be right for all of them. Each profile is measured on
its own and gets its own answer.
"""
import argparse, json, os, re, sys, collections

ROOTDIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
from PIL import Image

MS_RE = re.compile(
    r'^\s*use\s+(?P<tex>.+?\.dds)\s*,\s*(?P<cw>\d+)\s*,\s*(?P<ch>\d+)\s*,'
    r'\s*(?P<sx>[\d.]+)\s*,\s*(?P<sy>[\d.]+)\s*,\s*(?P<x>-?\d+)\s*,\s*(?P<y>-?\d+)\s*'
    r'(?:if\s*(?P<cond>.*))?$', re.I)


def ms_positions(path):
    """Every placement in one rule file, commonest first.

    A rule file holds one line per unit and date, and they nearly all
    repeat the same coordinates: the differences are which numeral to
    draw, not where. So the commonest placement IS the placement, and the
    outliers are the handful of aircraft somebody nudged by hand.
    """
    if not os.path.exists(path):
        return []
    got = collections.Counter()
    for line in open(path, encoding='latin-1'):
        if line.lstrip().startswith('#'):
            continue
        m = MS_RE.match(line.rstrip())
        if not m:
            continue
        got[(int(m.group('cw')), int(m.group('ch')), float(m.group('sx')),
             float(m.group('sy')), int(m.group('x')), int(m.group('y')))] += 1
    return got.most_common()


def components(im, box, test, min_px=200):
    """Every connected run of matching pixels in a region, with its box."""
    from collections import deque
    x0, y0, x1, y1 = box
    c = im.convert('RGBA').crop(box)
    px = c.load()
    w, h = c.size
    seen = bytearray(w * h)
    out = []
    for sy in range(h):
        for sx in range(w):
            i = sy * w + sx
            if seen[i] or not test(*px[sx, sy]):
                continue
            q = deque([(sx, sy)])
            seen[i] = 1
            mnx = mxx = sx; mny = mxy = sy; n = 0
            while q:
                x, y = q.popleft(); n += 1
                if x < mnx: mnx = x
                if x > mxx: mxx = x
                if y < mny: mny = y
                if y > mxy: mxy = y
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and test(*px[nx, ny]):
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            if n >= min_px:
                out.append(((x0 + mnx, y0 + mny, x0 + mxx + 1, y0 + mxy + 1), n))
    return out


def haloed(im, bb, light=150):
    """How much of a box's border is nearly white.

    Used on the SKIN SHEET only, where the cross sits on a pale fuselage
    and 84 per cent of its box edge is white. It does not work on the
    profile drawings: there the cross's own white border IS the edge of
    the box, and two pixels further out is camouflage, so a real cross
    scores 0.06 and would be thrown away.

    On the drawings the cross is told apart by shape instead - the right
    size, nearly square, and solidly filled. That matters because taking
    simply the biggest dark blob was wrong on 20 of the 41 profiles and
    was not obviously wrong: it returned a box the exact size of the
    search area, having joined the canopy, its shadow and the dark
    camouflage into one region, and every marking was then drawn at a
    wild scale off the end of the aeroplane.
    """
    x0, y0, x1, y1 = bb
    px = im.convert('RGBA').load()
    W, H = im.size
    hit = tot = 0
    for x in range(x0, x1):
        for y in (y0 - 2, y1 + 1):
            if 0 <= y < H:
                r, g, b, al = px[x, y]
                tot += 1
                if al > 200 and r > light and g > light and b > light:
                    hit += 1
    for y in range(y0, y1):
        for x in (x0 - 2, x1 + 1):
            if 0 <= x < W:
                r, g, b, al = px[x, y]
                tot += 1
                if al > 200 and r > light and g > light and b > light:
                    hit += 1
    return hit / float(tot) if tot else 0.0


def find_marking(im, box, test, want=(0.06, 0.16), aspect=(0.82, 1.30), need_halo=0.0):
    """The national marking: the candidate that is the right size, the
    right shape, and - for a Balkenkreuz - ringed in white.

    Anything that fails is not returned. A wrong answer here is far worse
    than none: the whole conversion is scaled off this box, so a box that
    is twice too small puts every marking at twice the size, somewhere
    off the tail. A profile with no answer simply gets no markings.
    """
    W, H = im.size
    best, bestscore = None, -1.0
    for bb, n in components(im, box, test):
        w, h = bb[2] - bb[0], bb[3] - bb[1]
        if not (want[0] * W <= w <= want[1] * W):
            continue
        if not (aspect[0] <= w / float(h) <= aspect[1]):
            continue
        # BIGGEST wins, not best-filled. Scoring by how solidly a
        # candidate fills its box picked a 61 x 38 patch of dark canopy on
        # II./JG 26 over the real 99 x 98 cross, because the patch was the
        # denser of the two. Once the shape gate has thrown out the merged
        # camouflage regions, the Balkenkreuz is simply the largest
        # compact dark thing on the fuselage, and area says so plainly.
        score = float(n)
        if need_halo > 0:
            hal = haloed(im, bb)
            if hal < need_halo:
                continue
        if score > bestscore:
            bestscore, best = score, bb
    return best


# The national marking, found by the one colour that is only ever part of
# it. A Balkenkreuz is the blackest thing on a grey-green fuselage; an RAF
# roundel has an orange-yellow outer ring that appears nowhere else on the
# aeroplane. Both are tested with alpha so the transparent surround is
# never mistaken for black.
BLACK  = lambda r, g, b, a: a > 200 and r < 80 and g < 80 and b < 80
# Tighter, for telling a Balkenkreuz core from dark camouflage. See the
# 109 profile loop for why 80 was not enough.
CROSS_CORE = lambda r, g, b, a: a > 200 and r < 50 and g < 50 and b < 50
YELLOW = lambda r, g, b, a: a > 200 and r > 165 and 100 < g < 175 and b < 100 and r - b > 90


# The Balkenkreuz by its WHITE BORDER, taken as the union of the corner
# pieces the border breaks into.
#
# The black-core detector works on a 109, whose camouflage is pale enough
# to leave the cross the darkest thing on the fuselage. It does NOT work
# on a Bf 110: the 110's dark green sits under the same threshold, so the
# cross merges with the camouflage into one 356 x 165 region and the
# reading is nonsense.
#
# The white border is unambiguous on both. It is not one shape - the
# cross's own black arms cut it into four corner blocks - so the box is
# the union of them, which is the cross plus its border and is exactly
# what is wanted as a ruler.
WHITE_EDGE = lambda r, g, b, a: a > 200 and r > 195 and g > 195 and b > 195


def find_cross_corners(im, box, want=(0.02, 0.14), min_px=80):
    W, H = im.size
    parts = [bb for bb, n in components(im, box, WHITE_EDGE, min_px=min_px)]
    if len(parts) < 3:
        return None
    # keep the four that sit together: the corners of one cross are all
    # within a couple of cross-widths of each other, while a patch of
    # white elsewhere on the sheet is not
    parts.sort(key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), reverse=True)
    ax = (parts[0][0] + parts[0][2]) / 2.0
    ay = (parts[0][1] + parts[0][3]) / 2.0
    near = [b for b in parts
            if abs((b[0] + b[2]) / 2.0 - ax) < 0.09 * W and abs((b[1] + b[3]) / 2.0 - ay) < 0.35 * H]
    if len(near) < 3:
        return None
    bb = (min(b[0] for b in near), min(b[1] for b in near),
          max(b[2] for b in near), max(b[3] for b in near))
    w = bb[2] - bb[0]
    if not (want[0] * W <= w <= want[1] * W):
        return None
    return bb


def convert(ms, tex_mark, prof_mark, prof_size):
    """One MultiSkin placement as fractions of a profile drawing.

    x and y are scaled SEPARATELY. The marking is square on the skin
    sheet and is not square on the drawing - the 109's cross measures
    146 x 151 in the texture and 99 x 81 on the profile - because the
    drawing is a true side view of a round fuselage and the texture is it
    unwrapped. One combined scale puts everything at the wrong height.
    """
    cw, ch, sx, sy, x, y = ms
    tl, tt, tr, tb = tex_mark
    pl, pt, pr, pb = prof_mark
    kx = (pr - pl) / float(tr - tl)
    ky = (pb - pt) / float(tb - tt)
    W, H = prof_size
    return {'dx': round((pl + (x - tl) * kx) / W, 4),
            'dy': round((pt + (y - tt) * ky) / H, 4),
            'dw': round(sx * cw * kx / W, 4),
            'dh': round(sy * ch * ky / H, 4),
            'kx': round(kx, 4), 'ky': round(ky, 4)}



# The darkness ladder the 109 detector walks. A Balkenkreuz core is dark
# on every skin, but "dark" is relative: on the pale mottled schemes the
# camouflage is 150 and up so almost anything separates them, while on
# RLM 70/71 the camouflage itself is 50 to 70 and only a tight threshold
# will do. One fixed number cannot serve 162 different paint schemes.
CROSS_LADDER = (30, 40, 50, 65, 80)


def _dark(t):
    return lambda r, g, b, a: a > 200 and r < t and g < t and b < t


def find_cross_109(im, box):
    """The Balkenkreuz on any of the 162 skins, by whichever way works.

    Two detectors, because neither is enough on its own across this many
    paint schemes. Measured over all 162:

      the white border alone   150 found, 19 of them not square
      the darkness ladder      162 found, a few clipped where an arm
                               runs into dark camouflage

    RLM70_71 is the case that needs the border: its cross sits half on
    dark green and half on light blue, so at any threshold loose enough
    to catch the top arm the camouflage joins in, and the reading comes
    out 87 x 68. The border gives 86 x 86.

    So both are tried and the squarest plausible answer wins. A
    Balkenkreuz is square; anything that is not was something else.
    """
    W = im.size[0]
    best = None
    cands = []
    c = find_cross_corners(im, box)
    if c:
        cands.append(c)
    for t in CROSS_LADDER:
        c = find_marking(im, box, _dark(t), want=(0.06, 0.16))
        if c:
            cands.append(c)
    for pc in cands:
        w, h = pc[2] - pc[0], pc[3] - pc[1]
        if w <= 0 or h <= 0:
            continue
        aspect = w / float(h)
        if not (0.80 <= aspect <= 1.25):
            continue
        if not (0.05 <= w / float(W) <= 0.16):
            continue
        s = abs(aspect - 1.0)
        if best is None or s < best[0]:
            best = (s, pc)
    return best[1] if best else None


def best_pos(ms_dir, files):
    """The commonest placement across one or more rule files.

    A rule file holds a line per unit, per aircraft and per date, and they
    nearly all repeat the same coordinates: what changes between lines is
    WHICH numeral to draw, not where it goes. So the placement most lines
    agree on is the placement, and the handful of outliers are aircraft
    somebody nudged by hand.
    """
    got = collections.Counter()
    for f in files:
        for pos, n in ms_positions(os.path.join(ms_dir, f)):
            got[pos] += n
    if not got:
        return None, 0
    pos, n = got.most_common(1)[0]
    return pos, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ms', default='/mnt/d/Battle of Britain II_Latest_test/MultiSkin')
    ap.add_argument('--tex', default='/mnt/d/BOB2 Files/skin-previews')
    ap.add_argument('--lw-art', default='squadronroom/lw/aircraft')
    ap.add_argument('--raf-art', default='squadronroom/aircraft')
    ap.add_argument('--out', default='squadronroom/marking-positions.json')
    a = ap.parse_args()

    out = {'note': ("Where every marking goes, taken from the game's own "
                    "MultiSkin rules (MultiSkin\\*.ms) and converted onto the "
                    "Room's profile artwork using the national marking as the "
                    "ruler. Nothing here was placed by eye. Rebuild with "
                    "dev/measure_markings.py."),
           'lw': {}, 'raf': {}}

    # ---- the Bf 109 -------------------------------------------------
    # The reference skin is a real III./JG 26 machine because the bare
    # sheet carries only stencils and has no Balkenkreuz to measure from.
    oobp = os.path.join(ROOTDIR, 'squadronroom', 'lw', 'oob.json')
    units = [r for r in json.load(open(oobp, encoding='utf-8')) if r.get('fighter')] \
        if os.path.exists(oobp) else []

    ref = Image.open(os.path.join(a.tex, 'M109ULF_IIIJG26.png'))
    tex_cross = find_marking(ref, (1250, 150, 1600, 440), BLACK,
                             want=(0.05, 0.10), need_halo=0.35)
    if not tex_cross:
        print('  ! no Balkenkreuz found in the reference skin', file=sys.stderr)
        return 1
    print('109 skin: Balkenkreuz at %s  (%d x %d)'
          % (tex_cross, tex_cross[2] - tex_cross[0], tex_cross[3] - tex_cross[1]))

    marks = {}
    for key, files in (('number', ['Me109_PlaneID_1.ms', '2ndMe109_PlaneID_1.ms']),
                       ('gruppe', ['Me109_PlaneID_2.ms']),
                       ('emblem', ['Me109_Emblem.ms'])):
        pos, n = best_pos(a.ms, files)
        if not pos:
            print('  ! no rule for %s' % key, file=sys.stderr); continue
        marks[key] = {'ms': pos, 'rules_agreeing': n}
        print('    %-7s (%4d,%4d) scale %.3f x %.3f   [%d rules agree]'
              % (key, pos[4], pos[5], pos[2], pos[3], n))
    out['lw']['reference_skin'] = 'M109ULF_IIIJG26.png'
    out['lw']['skin_marking'] = list(tex_cross)
    out['lw']['rules'] = {k: {'x': v['ms'][4], 'y': v['ms'][5],
                              'scale_x': v['ms'][2], 'scale_y': v['ms'][3],
                              'rules_agreeing': v['rules_agreeing']}
                          for k, v in marks.items()}

    # Every profile measured on its own: there are forty of them and they
    # do not all put the cross in the same place, so one set of fractions
    # cannot be right for all of them.
    # WHICH GRUPPE SYMBOL EACH UNIT WEARS, and where.
    #
    # This was a table I wrote from memory - "JG 3, JG 52 and JG 53 wore
    # the wavy line" - and the game says otherwise. Me109_PlaneID_2.ms
    # gives III./JG 3, III./JG 51 and III./JG 53 the VERTICAL BAR at
    # (1470, 199), and the only wavy rules in the file name III./JG 2.
    # Several units get blank.dds, which means no symbol from this layer
    # at all because their own skin already carries it.
    #
    # Three different symbols, three different positions, so one figure
    # for all of them was wrong even where the symbol was right. Read it
    # from the rules and there is nothing left to get wrong.
    #
    # MultiSkin's precedence between rules is not documented anywhere I
    # can see, so FIRST match wins here, which is the ordinary reading.
    # It only matters for III./JG 2, which has both a blank rule and a
    # wavy rule; taken this way it gets no symbol, which is also what its
    # own artwork suggests.
    def famof(t):
        t = t.replace('\\', '/').split('/')[-1].lower()
        if t.startswith('blank'):
            return None
        if 'wavy' in t:
            return 'IIIwavy'
        if t.startswith('ii_'):
            return 'II'
        if t.startswith('iii_'):
            return 'III'
        return 'unit'          # a badge of the unit's own, not a Gruppe bar
    per_unit = {}
    for line in open(os.path.join(a.ms, 'Me109_PlaneID_2.ms'), encoding='latin-1'):
        if line.lstrip().startswith('#'):
            continue
        m = MS_RE.match(line.rstrip())
        if not m:
            continue
        rule = (int(m.group('cw')), int(m.group('ch')), float(m.group('sx')),
                float(m.group('sy')), int(m.group('x')), int(m.group('y')))
        f = famof(m.group('tex'))
        for u in re.findall(r'unit\s*==\s*(\w+)', m.group('cond') or ''):
            per_unit.setdefault(u, (f, rule))
    def pretty(u):
        mm = re.match(r'^(IV|I{1,3}|V)(JG|ZG|LG)(\d+)$', u)
        return '%s./%s %s' % (mm.group(1), mm.group(2), mm.group(3)) if mm else u
    out['lw']['gruppe_by_unit'] = {}
    for u, (f, rule) in per_unit.items():
        out['lw']['gruppe_by_unit'][pretty(u)] = {
            'symbol': f,
            'ms': {'x': rule[4], 'y': rule[5], 'scale_x': rule[2], 'scale_y': rule[3]},
        }
    # WHERE THE RULES ARE SILENT.
    #
    # Most units get blank.dds, which does NOT mean they wore no Gruppe
    # symbol. It means the game's own main skin for that unit already has
    # one painted on, so nothing needs adding as a decal. Our profile
    # artwork is a different set of drawings and carries no bar at all: I
    # looked at II./JG 2, II./JG 3, II./JG 52, II./JG 53, II./JG 54,
    # III./JG 2, III./JG 27 and III./JG 54 and every one is bare aft of
    # the cross. Left as it stood, 24 of the 32 fighter Gruppen would show
    # no symbol whatever.
    #
    # So a unit the rules do not give a symbol to gets the one its Gruppe
    # numeral implies - II. a horizontal bar, III. a vertical bar, I.
    # nothing - drawn at the position the rules give for THAT symbol.
    # This is the one inference in the whole file and it is a small one:
    # the numeral-to-symbol rule is ordinary Luftwaffe practice, and the
    # position is still the game's. Each entry says which it is, so the
    # inferred ones can be told from the read ones.
    for v in out['lw']['gruppe_by_unit'].values():
        v['from_rules'] = True
    # Every symbol's position, from EVERY rule line rather than only the
    # first one that matches each unit. Built the narrow way, the wavy
    # line's position at (1520, 199) never appeared at all: the one unit
    # that wears it, III./JG 2, is blanked by an earlier line, so no
    # first-match entry carried it and III./JG 2 ended up with no symbol.
    bysym = {}
    for line in open(os.path.join(a.ms, 'Me109_PlaneID_2.ms'), encoding='latin-1'):
        if line.lstrip().startswith('#'):
            continue
        mm = MS_RE.match(line.rstrip())
        if not mm:
            continue
        f2 = famof(mm.group('tex'))
        if f2 and f2 != 'unit':
            bysym.setdefault(f2, {'x': int(mm.group('x')), 'y': int(mm.group('y')),
                                  'scale_x': float(mm.group('sx')),
                                  'scale_y': float(mm.group('sy'))})
    wavy_units = set()
    for line in open(os.path.join(a.ms, 'Me109_PlaneID_2.ms'), encoding='latin-1'):
        if 'wavy' in line.lower():
            wavy_units.update(re.findall(r'unit\s*==\s*(\w+)', line))
    inferred = 0
    for u in units:
        unit = u['unit']
        cur = out['lw']['gruppe_by_unit'].get(unit)
        if cur and cur['symbol'] and cur['symbol'] != 'unit':
            continue
        g = unit.split('.')[0]
        key = unit.replace('.', '').replace('/', '').replace(' ', '')
        sym = None
        if g == 'II':
            sym = 'II'
        elif g == 'III':
            sym = 'IIIwavy' if key in wavy_units else 'III'
        if not sym or sym not in bysym:
            continue
        out['lw']['gruppe_by_unit'][unit] = {'symbol': sym, 'ms': bysym[sym],
                                             'from_rules': False}
        inferred += 1
    named = sorted(set(v['symbol'] for v in out['lw']['gruppe_by_unit'].values()) - {None})
    fromrules = sum(1 for v in out['lw']['gruppe_by_unit'].values() if v.get('from_rules'))
    print('    gruppe symbols: %d read from the rules, %d taken from the Gruppe '
          'numeral where the rules are silent (%s)'
          % (fromrules, inferred, ', '.join(named)))

    out['lw']['profiles'] = {}
    for f in sorted(os.listdir(a.lw_art)):
        if not f.endswith('.png'):
            continue
        # The 110s live in the same folder and are measured separately
        # below: their cross is 67 px against the 109's 99, and their dark
        # camouflage defeats the black-core detector entirely. Left in
        # here they are flagged as bad readings, which is the consistency
        # check doing its job on the wrong aeroplane.
        if '110' in f.lower():
            continue
        im = Image.open(os.path.join(a.lw_art, f))
        W, H = im.size
        # BLACK calls anything under 80 dark, which was safe while every
        # 109 plate was the same pale drawing. The late Bf 109E, the one
        # with the yellow cowl, is painted in a much darker grey: its
        # camouflage sits around 50 to 70 and its cross core around 20 to
        # 30, so at 80 the two run together and the cross was read as a
        # 77 x 63 patch of canopy. 50 separates them on that drawing and
        # changes the pale one by a pixel.
        pc = find_cross_109(im, (int(W * 0.5), 0, int(W * 0.85), int(H * 0.75)))
        if not pc:
            print('  ? %s: no Balkenkreuz found, skipped' % f, file=sys.stderr); continue
        rec = {'marking': list(pc), 'size': [W, H]}
        for k, v in marks.items():
            rec[k] = convert(v['ms'], tex_cross, pc, (W, H))
        # and every Gruppe symbol at ITS OWN position, converted onto
        # this profile, so the Room never has to pick between them
        rec['gruppe_by_unit'] = {}
        for unit, g in out['lw']['gruppe_by_unit'].items():
            if not g['symbol'] or g['symbol'] == 'unit':
                continue
            ms = (2048, 2048, g['ms']['scale_x'], g['ms']['scale_y'], g['ms']['x'], g['ms']['y'])
            rec['gruppe_by_unit'][unit] = dict(convert(ms, tex_cross, pc, (W, H)),
                                               symbol=g['symbol'])
        out['lw']['profiles'][f] = rec
    # A BAD READING IS SILENT, SO IT IS CHECKED. But not against the
    # other plates any more.
    #
    # This used to drop any cross more than 15% off the median, and that
    # was right while all forty plates were copies of one drawing. From
    # 11 September 2026 they are 162 different skins drawn from the
    # game's own textures and their crosses genuinely differ:
    # M109ULF_IIIJG26_Bartels_G is painted with a bigger one, 97 px
    # against the usual 82, and the rule threw away a correct reading and
    # left that aeroplane with no markings at all.
    #
    # find_cross_109 already refuses anything that is not square and of a
    # plausible size, which is what a misreading actually looks like, so
    # the judgement belongs there and is not repeated here.
    widths = sorted(r['marking'][2] - r['marking'][0] for r in out['lw']['profiles'].values())
    if widths:
        mid = widths[len(widths) // 2]
        print('    %d of the 109 profiles measured, cross %d px median (%d to %d)'
              % (len(out['lw']['profiles']), mid, widths[0], widths[-1]))

    # ---- the Bf 110 --------------------------------------------------
    #
    # Its rules declare a canvas of 4048 and the actual skin sheets are
    # 2048, so every coordinate and every tile size has to be scaled by
    # 2048/4048 before it can be compared with a cross measured on the
    # real sheet. The 109 files declare 2048 and match 1:1; this one does
    # not, and taking the declared canvas at face value puts every code
    # letter twice as far aft as it belongs.
    K110 = 2048.0 / 4048.0
    MS110 = {
        'code':       (2474, 3200, 0.080),   # Me110_Geshwader_Code.ms
        'individual': (3025, 3196, 0.043),   # Me110_Aircraft_Code.ms
        'staffel':    (3175, 3196, 0.043),   # Me110_Staffel_Code.ms
    }
    ref110 = os.path.join(a.tex, 'Bf110_70_71_1940.png')
    if os.path.exists(ref110):
        r110 = Image.open(ref110)
        sk = find_cross_corners(r110, (1200, 1520, 1900, 1800))
        if not sk:
            print('  ! no Balkenkreuz found on the 110 reference skin', file=sys.stderr)
        else:
            out['lw']['skin110'] = {'reference_skin': 'Bf110_70_71_1940.png',
                                    'marking': list(sk), 'ms_canvas': 4048,
                                    'skin_px': 2048}
            print('110 skin: Balkenkreuz at %s  (%d x %d), rules on a 4048 canvas '
                  'scaled by %.4f' % (sk, sk[2] - sk[0], sk[3] - sk[1], K110))
            out['lw']['profiles110'] = {}
            for f in sorted(os.listdir(a.lw_art)):
                if not f.lower().startswith(('bf110', 'bf110-')) and '110' not in f.lower():
                    continue
                im = Image.open(os.path.join(a.lw_art, f))
                W, H = im.size
                pc = find_cross_corners(im, (int(W * 0.30), 0, int(W * 0.90), H))
                if not pc:
                    print('  ? %s: no Balkenkreuz found, skipped' % f, file=sys.stderr)
                    continue
                rec = {'marking': list(pc), 'size': [W, H]}
                for k, (x, y, sx) in MS110.items():
                    ms = (4048, 4048, sx, sx, x, y)
                    # convert() works in the SHEET's pixels, so scale first
                    ms = (int(4048 * K110), int(4048 * K110), sx, sx,
                          int(round(x * K110)), int(round(y * K110)))
                    rec[k] = convert(ms, sk, pc, (W, H))
                out['lw']['profiles110'][f] = rec
            print('    %d of the 110 profiles measured' % len(out['lw']['profiles110']))

    # ---- the Spitfire and the Hurricane ------------------------------
    for name, skin, box, art, idf, codef in (
            ('spitfire',  'Spit_June1940.png',  (1000, 600, 1800, 950), 'spitfire.png',
             ['Spit_PlaneID_Letter.ms'],  'Spit_Squadron_Code.ms'),
            ('hurricane', 'Hurri_July1940.png', (1100, 380, 1900, 700), 'hurricane.png',
             ['Hurri_PlaneID_Letter.ms'], 'Hurri_Squadron_Code.ms')):
        sp = os.path.join(a.tex, skin)
        pp = os.path.join(a.raf_art, art)
        if not (os.path.exists(sp) and os.path.exists(pp)):
            print('  ! %s: missing skin or profile' % name, file=sys.stderr); continue
        tex = Image.open(sp)
        tm = find_marking(tex, box, YELLOW, want=(0.05, 0.12))
        pim = Image.open(pp)
        W, H = pim.size
        pm = find_marking(pim, (int(W * 0.40), 0, int(W * 0.85), int(H * 0.75)), YELLOW,
                          want=(0.06, 0.16))
        if not (tm and pm):
            print('  ! %s: roundel not found (skin %s, profile %s)' % (name, tm, pm), file=sys.stderr); continue
        rec = {'reference_skin': skin, 'skin_marking': list(tm),
               'marking': list(pm), 'size': [W, H], 'rules': {}}
        idpos, idn = best_pos(a.ms, idf)
        cpos, cn = best_pos(a.ms, [codef])
        if idpos:
            rec['letter'] = convert(idpos, tm, pm, (W, H))
            rec['rules']['letter'] = {'x': idpos[4], 'y': idpos[5], 'scale_x': idpos[2],
                                      'scale_y': idpos[3], 'rules_agreeing': idn}
        if cpos:
            rec['code'] = convert(cpos, tm, pm, (W, H))
            rec['rules']['code'] = {'x': cpos[4], 'y': cpos[5], 'scale_x': cpos[2],
                                    'scale_y': cpos[3], 'rules_agreeing': cn}
        out['raf'][name] = rec
        print('%-10s roundel skin %s -> profile %s' % (name, tm, pm))
        for k in ('code', 'letter'):
            if k in rec:
                print('    %-7s dx %.4f dy %.4f dw %.4f dh %.4f'
                      % (k, rec[k]['dx'], rec[k]['dy'], rec[k]['dw'], rec[k]['dh']))

    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write('\n')
    print('\n-> %s' % a.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
