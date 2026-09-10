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


def largest_blob(im, box, test):
    """The biggest connected run of matching pixels in a region, boxed.

    Column and row histograms were tried first and were not good enough:
    a Balkenkreuz's white border is broken into corner pieces by its own
    black arms, and the camouflage on a profile drawing is dark enough in
    places to stretch a box across half the aeroplane. A connected
    component cannot do either.

    ALPHA IS TESTED. The profile art is transparent around the aeroplane,
    and converting it to RGB turns all of that into pure black, which
    reads as one enormous marking covering the whole image. That is what
    the first attempt reported.
    """
    from collections import deque
    x0, y0, x1, y1 = box
    c = im.convert('RGBA').crop(box)
    px = c.load()
    w, h = c.size
    seen = bytearray(w * h)
    best, bestn = None, 0
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
            if n > bestn:
                bestn, best = n, (mnx, mny, mxx + 1, mxy + 1)
    if not best:
        return None
    return (x0 + best[0], y0 + best[1], x0 + best[2], y0 + best[3])


# The national marking, found by the one colour that is only ever part of
# it. A Balkenkreuz is the blackest thing on a grey-green fuselage; an RAF
# roundel has an orange-yellow outer ring that appears nowhere else on the
# aeroplane. Both are tested with alpha so the transparent surround is
# never mistaken for black.
BLACK  = lambda r, g, b, a: a > 200 and r < 80 and g < 80 and b < 80
YELLOW = lambda r, g, b, a: a > 200 and r > 165 and 100 < g < 175 and b < 100 and r - b > 90


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
    ref = Image.open(os.path.join(a.tex, 'M109ULF_IIIJG26.png'))
    tex_cross = largest_blob(ref, (1250, 150, 1600, 440), BLACK)
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
    out['lw']['profiles'] = {}
    for f in sorted(os.listdir(a.lw_art)):
        if not f.endswith('.png'):
            continue
        im = Image.open(os.path.join(a.lw_art, f))
        W, H = im.size
        pc = largest_blob(im, (int(W * 0.5), 0, int(W * 0.85), int(H * 0.62)), BLACK)
        if not pc:
            print('  ? %s: no Balkenkreuz found, skipped' % f, file=sys.stderr); continue
        rec = {'marking': list(pc), 'size': [W, H]}
        for k, v in marks.items():
            rec[k] = convert(v['ms'], tex_cross, pc, (W, H))
        out['lw']['profiles'][f] = rec
    print('    %d of the 109 profiles measured' % len(out['lw']['profiles']))

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
        tm = largest_blob(tex, box, YELLOW)
        pim = Image.open(pp)
        W, H = pim.size
        pm = largest_blob(pim, (int(W * 0.40), 0, int(W * 0.85), int(H * 0.75)), YELLOW)
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
