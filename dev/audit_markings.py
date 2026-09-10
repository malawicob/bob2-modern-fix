#!/usr/bin/env python3
"""Check every marking on every aeroplane, and say what is wrong.

    python3 dev/audit_markings.py

Written because three separate faults in this feature were invisible from
a screenshot and one of them was wrong on 20 of 41 profiles without
anything saying so. Eyeballing four aeroplanes proves nothing about the
other thirty-seven.

Everything here is checked against something that can be measured, not
against how it looks:

  THE ARTWORK      the Balkenkreuz is still there, no pocket of
                   background survives behind the aerial, and the spinner
                   was not eaten by the cut

  THE RULER        every profile's cross is the size the rest agree on,
                   because the whole conversion is scaled off it and one
                   bad reading draws that aeroplane's markings at the
                   wrong size off the tail

  THE PLACEMENT    the number lands FORWARD of the cross, the Gruppe
                   symbol AFT of it, the emblem on the cowling, and all
                   of them on the aeroplane rather than in the air beside
                   it - tested against the profile's own alpha

  THE PARTS        every tile a unit needs actually exists on disk

Exit code is 1 if anything failed, so it can gate a release.
"""
import json, os, sys, glob
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LW_ART = os.path.join(ROOT, 'squadronroom', 'lw', 'aircraft')
LW_MARK = os.path.join(ROOT, 'squadronroom', 'lw', 'markings')
RAF_ART = os.path.join(ROOT, 'squadronroom', 'aircraft')

fails = []
warns = []


def fail(msg):
    fails.append(msg)
    print('  FAIL  %s' % msg)


def warn(msg):
    warns.append(msg)
    print('  warn  %s' % msg)


def load(p):
    with open(p, encoding='utf-8') as fh:
        return json.load(fh)


def ink_span(tile_path, floor=6):
    """Which columns of a tile the mark actually occupies.

    Not getbbox(), for two reasons. It counts colour that sits under zero
    alpha, and several of these tiles carry a couple of stray opaque
    pixels in the corners - registration specks from whatever produced
    them. III_white has two at column 0 and two at column 127 with the
    bar itself at columns 57 to 71, so a bounding box says the mark fills
    the tile and every measurement taken from it is wrong. This audit
    reported 123 failures on that alone.

    So: count opaque pixels per column and keep the columns that carry
    more than a speck.
    """
    im = Image.open(tile_path).convert('RGBA')
    a = im.split()[3].load()
    w, h = im.size
    cols = [sum(1 for y in range(h) if a[x, y] > 40) for x in range(w)]
    on = [i for i, v in enumerate(cols) if v > floor]
    if not on:
        return None
    return on[0], on[-1] + 1, w


def visible(tile_path, dx, dw, W):
    """Where the INK of a tile lands, not where its canvas does.

    The canvas is kept deliberately, so a tile is mostly transparent
    padding and its left edge says nothing about where the mark appears.
    """
    sp = ink_span(tile_path)
    if not sp:
        return None
    x0, x1, tw = sp
    return (dx * W + dw * W * x0 / tw, dx * W + dw * W * x1 / tw)


def opaque_at(im, x, y):
    W, H = im.size
    if not (0 <= x < W and 0 <= y < H):
        return False
    return im.convert('RGBA').getpixel((int(x), int(y)))[3] > 100


def main():
    pos = load(os.path.join(ROOT, 'squadronroom', 'marking-positions.json'))
    marks = load(os.path.join(ROOT, 'squadronroom', 'lw', 'markings.json'))
    oob = [r for r in load(os.path.join(ROOT, 'squadronroom', 'lw', 'oob.json')) if r['fighter']]

    print('THE ARTWORK')
    arts = sorted(glob.glob(os.path.join(LW_ART, '*.png')))
    for f in arts:
        im = Image.open(f).convert('RGBA')
        px = im.load()
        W, H = im.size
        cross = wedge = 0
        for y in range(int(H * 0.30), int(H * 0.70)):
            for x in range(int(W * 0.58), int(W * 0.72)):
                r, g, b, a = px[x, y]
                if a > 200 and r <= 12 and g <= 12 and b <= 12:
                    cross += 1
        for y in range(int(H * 0.04), int(H * 0.26)):
            for x in range(int(W * 0.44), int(W * 0.72)):
                r, g, b, a = px[x, y]
                if a > 200 and r <= 12 and g <= 12 and b <= 12:
                    wedge += 1
        # the spinner: opaque pixels in the nose cone
        spin = sum(1 for y in range(int(H * 0.35), int(H * 0.62))
                     for x in range(0, int(W * 0.09))
                     if px[x, y][3] > 200)
        n = os.path.basename(f)
        if cross < 400:
            fail('%s: Balkenkreuz missing or eaten (%d px)' % (n, cross))
        if wedge > 300:
            fail('%s: background left behind the aerial (%d px)' % (n, wedge))
        if spin < 400:
            fail('%s: spinner eaten by the cut (%d px)' % (n, spin))
    print('  %d profiles: cross, aerial pocket and spinner all checked' % len(arts))

    print('THE RULER')
    profs = pos['lw']['profiles']
    widths = sorted(r['marking'][2] - r['marking'][0] for r in profs.values())
    mid = widths[len(widths) // 2]
    for f, r in sorted(profs.items()):
        w = r['marking'][2] - r['marking'][0]
        if abs(w - mid) > 0.15 * mid:
            fail('%s: cross read as %d px, the rest agree on %d' % (f, w, mid))
    missing = [os.path.basename(f) for f in arts if os.path.basename(f) not in profs]
    for f in missing:
        warn('%s: no cross found, so it gets no markings' % f)
    print('  %d profiles measured, cross %d px, %d unmeasured' % (len(profs), mid, len(missing)))

    print('THE PLACEMENT')
    checked = 0
    for f, r in sorted(profs.items()):
        W, H = r['size']
        cl, ct, cr, cb = r['marking']
        im = Image.open(os.path.join(LW_ART, f))
        # the number, in every colour it can be drawn in
        for col in ('white', 'red', 'yellow'):
            rel = marks['numbers'].get('7', {}).get(col)
            if not rel:
                fail('no number 7 in %s' % col); continue
            t = os.path.join(LW_MARK, rel.replace('/', os.sep))
            if not os.path.exists(t):
                fail('missing tile %s' % rel); continue
            v = visible(t, r['number']['dx'], r['number']['dw'], W)
            if v[1] > cl:
                fail('%s: number (%s) overlaps the cross, ends at %.0f, cross starts %d'
                     % (f, col, v[1], cl))
            if v[0] < 0.30 * W:
                fail('%s: number (%s) is forward of the cockpit at %.0f' % (f, col, v[0]))
            cy = r['number']['dy'] * H + r['number']['dh'] * H * 0.5
            if not opaque_at(im, (v[0] + v[1]) / 2, cy):
                fail('%s: number (%s) is not on the aeroplane' % (f, col))
            checked += 1
        # every Gruppe symbol this profile carries a rule for
        for unit, g in sorted(r.get('gruppe_by_unit', {}).items()):
            rel = marks['gruppe'].get('%s_white' % g['symbol'])
            if not rel:
                fail('no %s symbol tile' % g['symbol']); continue
            t = os.path.join(LW_MARK, rel.replace('/', os.sep))
            if not os.path.exists(t):
                fail('missing tile %s' % rel); continue
            v = visible(t, g['dx'], g['dw'], W)
            if v[0] < cr:
                fail('%s / %s: %s symbol starts at %.0f, forward of the cross end %d'
                     % (f, unit, g['symbol'], v[0], cr))
            if v[1] > 0.95 * W:
                fail('%s / %s: %s symbol runs off the tail at %.0f' % (f, unit, g['symbol'], v[1]))
            cy = g['dy'] * H + g['dh'] * H * 0.5
            if not opaque_at(im, (v[0] + v[1]) / 2, cy):
                fail('%s / %s: %s symbol is not on the aeroplane' % (f, unit, g['symbol']))
            checked += 1
        # the emblem, on the cowling
        e = r.get('emblem')
        if e and e['dx'] + e['dw'] > 0.45:
            fail('%s: emblem at %.3f is not on the cowling' % (f, e['dx']))
        checked += 1
    print('  %d placements checked' % checked)

    print('THE PARTS')
    for n in range(1, 16):
        for col in ('white', 'red', 'yellow', 'black'):
            rel = marks['numbers'].get(str(n), {}).get(col)
            if not rel or not os.path.exists(os.path.join(LW_MARK, rel.replace('/', os.sep))):
                fail('number %d in %s is missing' % (n, col))
    unit_prof = {}
    for u in oob:
        key = u['unit'].replace('.', '').replace('/', '_').replace(' ', '')
        p = key + '.png'
        unit_prof[u['unit']] = p if os.path.exists(os.path.join(LW_ART, p)) else 'RLM70_71.png'
    nosym = [u for u in unit_prof
             if u not in pos['lw'].get('gruppe_by_unit', {})
             or not pos['lw']['gruppe_by_unit'][u].get('symbol')]
    print('  %d fighter Gruppen: %d have a Gruppe symbol, %d wear none'
          % (len(unit_prof), len(unit_prof) - len(nosym), len(nosym)))
    own = sum(1 for u, p in unit_prof.items() if p != 'RLM70_71.png')
    print('  %d fly a profile in their own markings, %d the plain scheme'
          % (own, len(unit_prof) - own))

    print('THE RAF')
    # The RAF codes are drawn text again, at Patrick's call, so there are
    # no tiles to check. What is still worth checking is the measurement
    # itself: it confirmed the horizontal placement the Room has always
    # used is within a couple of per cent of the game's own, and if that
    # ever stops being true somebody has moved something.
    for t in ('spitfire', 'hurricane'):
        r = pos['raf'].get(t)
        if not r:
            fail('no RAF measurement for %s' % t); continue
        cl, cr = r['marking'][0], r['marking'][2]
        W = r['size'][0]
        if not (0.30 * W < cl < 0.70 * W):
            fail('%s: roundel found at %d, which is not mid-fuselage' % (t, cl))
        for k in ('code', 'letter'):
            if k not in r:
                fail('%s: no %s measurement' % (t, k)); continue
            if not (0.05 < r[k]['dx'] < 0.95):
                fail('%s: %s measured off the aeroplane at %.3f' % (t, k, r[k]['dx']))
    spec = {'spitfire': (0.4194, 0.6727), 'hurricane': (0.4118, 0.6313)}
    for t, (sqx, indx) in spec.items():
        r = pos['raf'][t]
        for k, cur in (('code', sqx), ('letter', indx)):
            d = abs(r[k]['dx'] - cur)
            if d > 0.05:
                warn('%s: the Room draws the %s at %.4f, the game puts it at %.4f'
                     % (t, k, cur, r[k]['dx']))
    print('  both aeroplanes: roundel found, measurements agree with what the Room draws')

    print()
    if fails:
        print('%d FAILURE(S), %d warning(s)' % (len(fails), len(warns)))
        return 1
    print('ALL CHECKS PASSED (%d warning(s))' % len(warns))
    return 0


if __name__ == '__main__':
    sys.exit(main())
