#!/usr/bin/env python3
"""Draw all forty dressed fields on one sheet, seen from above.

    python3 dev/preview_lw_dispersal.py --out /tmp/lw-fields.png

Forty fields is forty sorties to look at, which nobody is going to fly.
This draws each one from the manifest: the runway markers with the
165 m ring round each that nothing may enter, the field's reference
point, every object placed, and anything already in ObjectAdds nearby,
all to the same scale with a bar to read it by.

A tent on the strip is obvious here in a way it is not in a list of
coordinates, which is the whole reason this exists. The same reason
dev/screen_preview.ps1 exists for the Room.
"""
import os, sys, math, json, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
U = 90.0

INK = {
    'bg':      (18, 22, 26),
    'panel':   (26, 32, 38),
    'rule':    (52, 62, 70),
    'runway':  (200, 151, 63),
    'ring':    (96, 74, 34),
    'ref':     (232, 90, 70),
    'grid':    (38, 46, 54),
    'label':   (233, 227, 212),
    'sub':     (140, 156, 166),
    'stock':   (70, 92, 104),
}
# what each thing is, so a glance says what it is looking at
COLOUR = {
    440: (120, 196, 128), 439: (120, 196, 128), 438: (120, 196, 128), 503: (120, 196, 128),
    441: (150, 180, 240), 436: (150, 180, 240), 437: (150, 180, 240),
    431: (188, 154, 108), 432: (188, 154, 108), 433: (188, 154, 108),
    434: (188, 154, 108), 435: (188, 154, 108),
    419: (232, 120, 100), 420: (232, 120, 100), 421: (232, 120, 100),
    427: (232, 120, 100), 429: (232, 120, 100), 430: (232, 120, 100),
    324: (240, 200, 90),
    442: (250, 250, 250), 443: (250, 250, 250), 347: (250, 250, 250),
}
DEFAULT = (170, 178, 186)      # vehicles


def read_objectadds(path):
    out = []
    for ln in open(path, encoding='latin-1', errors='ignore'):
        if 'OBJECT_ADD' not in ln:
            continue
        p = ln.split()
        if len(p) < 2:
            continue
        f = p[1].split(',')
        if len(f) < 4:
            continue
        try:
            out.append((int(f[0]), int(f[1])))
        except ValueError:
            continue
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', default='/mnt/d/Battle of Britain II_Latest_test')
    ap.add_argument('--man',  default=os.path.join(ROOT, 'dispersal/lw-airfields.json'))
    ap.add_argument('--out',  default='/tmp/lw-fields.png')
    ap.add_argument('--span', type=float, default=1600.0, help='metres across a panel')
    a = ap.parse_args()

    from PIL import Image, ImageDraw, ImageFont

    man = json.load(open(a.man, encoding='utf-8'))
    fields = man['fields']

    oa_dir = os.path.join(a.game, 'ObjectAdds')
    stock = []
    if os.path.isdir(oa_dir):
        for fn in sorted(os.listdir(oa_dir)):
            if fn.lower().endswith('.txt') and fn != 'LW_Airfields.txt':
                stock += read_objectadds(os.path.join(oa_dir, fn))

    def font(sz, bold=False):
        for p in ('/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf' % ('-Bold' if bold else ''),
                  '/usr/share/fonts/truetype/liberation/LiberationSans%s.ttf' % ('-Bold' if bold else '')):
            if os.path.exists(p):
                try:
                    return ImageFont.truetype(p, sz)
                except Exception:
                    pass
        return ImageFont.load_default()

    COLS = 5
    P = 300                      # panel side
    HDR = 34
    PAD = 10
    rows = (len(fields) + COLS - 1) // COLS
    W = COLS * (P + PAD) + PAD
    H = rows * (P + HDR + PAD) + PAD + 46
    img = Image.new('RGB', (W, H), INK['bg'])
    d = ImageDraw.Draw(img)
    f9, f11, f13 = font(9), font(11), font(13, True)

    d.text((PAD, 12), 'LUFTWAFFE DISPERSAL  %d fields  %d objects  %g m across each panel'
           % (len(fields), sum(len(x['objects']) for x in fields), a.span),
           font=f13, fill=INK['label'])

    for i, fl in enumerate(fields):
        cx = PAD + (i % COLS) * (P + PAD)
        cy = 46 + PAD + (i // COLS) * (P + HDR + PAD)
        d.rectangle([cx, cy, cx + P, cy + HDR + P], fill=INK['panel'], outline=INK['rule'])
        d.text((cx + 8, cy + 5), fl['field'][:26], font=f11, fill=INK['label'])
        d.text((cx + 8, cy + 19), '%s  %d objects from %s  %d m clear of the markers'
               % (fl['shape'], len(fl['objects']), fl['exemplar'], fl['clearance']),
               font=f9, fill=INK['sub'])
        ox, oy = cx, cy + HDR
        scale = P / (a.span * U)          # pixels per game unit

        # Each panel is drawn on its own canvas and pasted, so a runway
        # line cannot run off into the field next door. The first sheet
        # had them crossing three panels at a time.
        pan = Image.new('RGB', (P, P), INK['panel'])
        pd = ImageDraw.Draw(pan)

        # Centre on the midpoint of the reference point and the kit, so a
        # dispersal 700 m down the axis is not half off the edge.
        pts = [(o['x'], o['z']) for o in fl['objects']] + [(fl['x'], fl['z'])]
        pts += [(m['x'], m['z']) for m in fl.get('markers', [])]
        mx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2.0
        mz = (min(p[1] for p in pts) + max(p[1] for p in pts)) / 2.0

        def px(x, z):
            return (P / 2 + (x - mx) * scale, P / 2 - (z - mz) * scale)

        for g in range(-2000, 2001, 500):          # 500 m grid
            gx, gy = px(mx + g * U, mz + g * U)
            pd.line([0, gy, P, gy], fill=INK['grid'])
            pd.line([gx, 0, gx, P], fill=INK['grid'])

        L = a.span * U
        RING = 165 * U * scale
        for m in fl.get('markers', []):
            mx_, my_ = px(m['x'], m['z'])
            pd.ellipse([mx_ - RING, my_ - RING, mx_ + RING, my_ + RING], outline=INK['ring'])
            pd.line([mx_ - 5, my_ - 5, mx_ + 5, my_ + 5], fill=INK['runway'], width=2)
            pd.line([mx_ - 5, my_ + 5, mx_ + 5, my_ - 5], fill=INK['runway'], width=2)

        for x, z in stock:
            if abs(x - mx) < L and abs(z - mz) < L:
                sx, sy = px(x, z)
                if 0 <= sx < P and 0 <= sy < P:
                    pd.point((sx, sy), fill=INK['stock'])

        rx, ry = px(fl['x'], fl['z'])
        pd.line([rx - 4, ry, rx + 4, ry], fill=INK['ref'])
        pd.line([rx, ry - 4, rx, ry + 4], fill=INK['ref'])

        for o in fl['objects']:
            sx, sy = px(o['x'], o['z'])
            c = COLOUR.get(o['id'], DEFAULT)
            pd.ellipse([sx - 2.5, sy - 2.5, sx + 2.5, sy + 2.5], fill=c)

        img.paste(pan, (ox, oy))
        d = ImageDraw.Draw(img)

        bar = 200 * U * scale             # 200 m scale bar
        d.line([ox + 10, oy + P - 10, ox + 10 + bar, oy + P - 10], fill=INK['sub'], width=2)
        d.text((ox + 12 + bar, oy + P - 17), '200 m', font=f9, fill=INK['sub'])
        d.rectangle([cx, cy, cx + P, cy + HDR + P], outline=INK['rule'])

    img.save(a.out)
    print('%d panels -> %s  (%dx%d)' % (len(fields), a.out, W, H))
    print('  gold crosses = runway markers, with the 165 m ring nothing may enter')
    print('  red cross = the field reference point')
    print('  green = tents and revetments, blue = huts and hangars, brown = barns,')
    print('  red = flak, yellow = bomb dump, white = ground crew, grey = vehicles')
    print('  dark grey dots = scenery already in ObjectAdds')
    return 0


if __name__ == '__main__':
    sys.exit(main())
