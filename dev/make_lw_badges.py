#!/usr/bin/env python3
"""Draw the Luftwaffe collar patches the Squadron Room needs.

    python3 dev/make_lw_badges.py --out squadronroom/lw/badges

WHY THEY ARE DRAWN AND NOT COPIED

The reference Patrick supplied is a Moritz Ruhl uniform plate of the
1930s, "Die wichtigsten Uniformen und Abzeichen der Luftwaffe". It is
exactly the right source and it settles the design, but the copy of it
is an Alamy scan with the agency's watermark across it, and the ribbon
bar beside it is a dealer photograph watermarked LAKESIDE TRADER. Neither
can go into a mod that is downloaded from a public release page. So the
plate is used the way a reference is meant to be used: to get the thing
right, and then draw it.

WHAT THE PLATE ACTUALLY SAYS

Read off the labelled row, for the Fliegertruppe, whose Waffenfarbe is
yellow:

    Unteroffizier    1 gull    braid down the leading and bottom edges
    Feldwebel        3 gulls   braid
    Oberfeldwebel    4 gulls   braid
    Hauptgefreiter   4 gulls   NO braid

The braid, the Tresse, is what separates a non-commissioned officer from
a senior aircraftman with the same number of gulls, which is why the
Hauptgefreiter has four and no braid. It is drawn here.

Unterfeldwebel, at two gulls, is on the plate but is not in the Room's
ladder, so it is not drawn.

OFFICER PATCHES

Two scans were too small to count the officer gulls from, so those
counts started as the standard pattern rather than as anything read off a
source. They have since been CHECKED against the collar tab drawings on
the Wikipedia article "Ranks and insignia of the Luftwaffe (1935-1945)",
fetched at 500px, and they were right:

    Unteroffizier   1 gull    flat braid, no wreath
    Feldwebel       3 gulls   flat braid
    Oberfeldwebel   4 gulls   flat braid
    Leutnant        1 gull    oak-leaf wreath, twisted silver cord
    Oberleutnant    2 gulls   wreath and cord
    Hauptmann       3 gulls   wreath and cord

Those drawings also confirm the yellow: the Oberfeldwebel tab is shown in
the Fliegertruppe's yellow, which is what a flying man wore.

Hauptmann is still not drawn. It is a command in this Room, reached
through cmode, not a rung anybody is promoted to.
"""
import argparse, os

from PIL import Image, ImageDraw

# The colours, kept together so the next person can argue with them in
# one place rather than five.
YELLOW  = (232, 186, 22)     # Waffenfarbe of the Fliegertruppe
YELL_HI = (245, 205, 60)
BRAID   = (206, 206, 200)    # the silver Tresse
BRAID_D = (150, 150, 146)
GULL    = (246, 245, 238)
GULL_ED = (120, 120, 112)
EDGE    = (60, 55, 40)

W, H = 240, 300
INSET = 10


def gull(d, cx, cy, span, thick):
    """One stylised gull: two swept wings from a shallow central dip.

    Drawn as a filled polygon rather than two arcs, because at the size
    this appears in the Room (about 40px tall) an outline stroke turns to
    mud and the silhouette is the only part that reads.
    """
    # Fuller and flatter than the first attempt, which came out as thin
    # spikes: on the plate the wings are broad and nearly horizontal,
    # with only a small notch where the body would be.
    half = span / 2.0
    rise = span * 0.22
    tip_drop = span * 0.06
    pts = [
        (cx - half, cy - rise),                       # left tip, high
        (cx - half * 0.55, cy - rise * 0.15),
        (cx, cy + tip_drop * 0.6),                    # the dip in the middle
        (cx + half * 0.55, cy - rise * 0.15),
        (cx + half, cy - rise),                       # right tip, high
        (cx + half * 0.60, cy - rise + thick * 1.15),
        (cx, cy + tip_drop * 0.6 + thick),
        (cx - half * 0.60, cy - rise + thick * 1.15),
    ]
    d.polygon(pts, fill=GULL, outline=GULL_ED)
    # the small ring at the centre of each gull, which the reference
    # drawings all carry and which is the one detail still legible when
    # the patch is down at the 46 pixels the Room shows it at
    r = thick * 0.62
    d.ellipse([cx - r, cy + tip_drop * 0.6 + thick * 0.35 - r,
               cx + r, cy + tip_drop * 0.6 + thick * 0.35 + r],
              fill=None, outline=GULL_ED, width=max(1, int(thick * 0.28)))


def wreath(d, cx, cy, span):
    """The oak-leaf spray across the foot of an officer's patch.

    Two sprays rising from the centre. Not botanically anything, but at
    the size this is seen the silhouette is what says "officer" and the
    leaves are a texture rather than a shape anyone reads.
    """
    # A first attempt drew four big leaves a side with a heavy stem line
    # between them, and it came out as a V of grey blobs. The stems are
    # gone and the leaves are smaller, more numerous and set along a
    # shallow curve, which at this size reads as a wreath rather than as
    # anything in particular - which is exactly what it should do.
    n = 7
    for side in (-1, 1):
        for i in range(n):
            t = (i + 1) / float(n)
            bx = cx + side * span * 0.46 * t
            by = cy - span * 0.30 * (t ** 1.35)
            r = span * (0.070 - i * 0.0045)
            # each leaf tilted along the sweep, drawn as a squashed
            # ellipse; a rotated polygon would be truer and invisible
            d.ellipse([bx - r * 1.25, by - r * 0.60, bx + r * 1.25, by + r * 0.60],
                      fill=GULL, outline=GULL_ED)


def patch(gulls, braid, path, scale=4, wreathed=False, cord=False):
    """One collar patch, drawn big and shrunk, which is the cheapest
    antialiasing there is and needs no extra library."""
    w, h = W * scale, H * scale
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    ins = INSET * scale
    # The patch itself. Slightly leaning, as a collar patch sits.
    lean = int(w * 0.06)
    body = [(ins + lean, ins), (w - ins, ins), (w - ins - lean, h - ins), (ins, h - ins)]
    d.polygon(body, fill=YELLOW, outline=EDGE, width=max(1, scale))
    # A highlight was tried along the top edge and read as a separate
    # yellow band stuck across the patch rather than as light on cloth,
    # so there is none. Flat is better than wrong.

    if cord:
        # An officer's patch is edged all round in twisted silver cord,
        # not braided down two sides like an NCO's. Drawn as an outline
        # rather than filled bands, which is the whole visual difference.
        d.polygon(body, fill=None, outline=BRAID, width=max(2, int(w * 0.030)))
        d.polygon(body, fill=None, outline=BRAID_D, width=max(1, scale))

    if braid:
        # the Tresse runs down the leading edge and along the bottom
        t = int(w * 0.085)
        d.polygon([(ins + lean, ins), (ins + lean + t, ins),
                   (ins + t, h - ins), (ins, h - ins)], fill=BRAID, outline=BRAID_D)
        d.polygon([(ins, h - ins - t), (w - ins - lean, h - ins - t),
                   (w - ins - lean, h - ins), (ins, h - ins)], fill=BRAID, outline=BRAID_D)

    if wreathed:
        wreath(d, w * 0.52, h * 0.82, w * 0.72)

    # the gulls, stacked down the patch and inset clear of the braid
    span = w * 0.56
    thick = h * 0.034
    # an officer's gulls sit above the wreath, so they use the upper part
    top, bottom = (h * 0.22, h * 0.52) if wreathed else (h * 0.20, h * 0.80)
    if gulls == 1:
        ys = [h * 0.50]
    else:
        step = (bottom - top) / (gulls - 1)
        ys = [top + i * step for i in range(gulls)]
    for y in ys:
        gull(d, w * 0.55, y, span, thick)

    im = im.resize((W, H), Image.LANCZOS)
    im.save(path)
    return path


# name, gulls, braid (NCO), wreath+cord (officer)
RANKS = [
    ('unteroffizier.png', 1, True,  False),
    ('feldwebel.png',     3, True,  False),
    ('oberfeldwebel.png', 4, True,  False),
    ('leutnant.png',      1, False, True),
    ('oberleutnant.png',  2, False, True),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='squadronroom/lw/badges')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for name, n, braid, off in RANKS:
        patch(n, braid, os.path.join(a.out, name), wreathed=off, cord=off)
        print('  %-22s %d gull%s  %s' % (name, n, '' if n == 1 else 's',
                                         'wreath and cord (officer)' if off else 'braid (NCO)'))
    print('%d collar patches in %s' % (len(RANKS), a.out))


if __name__ == '__main__':
    main()
