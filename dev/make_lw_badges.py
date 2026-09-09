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

Officer patches are NOT drawn. Company officers carried gulls and a
silver cord edge rather than braid, and the number rises with rank, but
the three figures on this plate are too small to count and I would rather
leave a gap than invent a rank badge. The Room shows a rank in words when
its badge is missing, so a Leutnant looks unfinished rather than wrong.
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


def patch(gulls, braid, path, scale=4):
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

    if braid:
        # the Tresse runs down the leading edge and along the bottom
        t = int(w * 0.085)
        d.polygon([(ins + lean, ins), (ins + lean + t, ins),
                   (ins + t, h - ins), (ins, h - ins)], fill=BRAID, outline=BRAID_D)
        d.polygon([(ins, h - ins - t), (w - ins - lean, h - ins - t),
                   (w - ins - lean, h - ins), (ins, h - ins)], fill=BRAID, outline=BRAID_D)

    # the gulls, stacked down the patch and inset clear of the braid
    span = w * 0.56
    thick = h * 0.034
    top, bottom = h * 0.20, h * 0.80
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


RANKS = [
    ('unteroffizier.png', 1, True),
    ('feldwebel.png',     3, True),
    ('oberfeldwebel.png', 4, True),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='squadronroom/lw/badges')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for name, n, braid in RANKS:
        p = patch(n, braid, os.path.join(a.out, name))
        print('  %-22s %d gull%s%s' % (name, n, '' if n == 1 else 's', ', braid' if braid else ''))
    print('%d collar patches in %s' % (len(RANKS), a.out))
    print('Officer patches deliberately not drawn: see the note at the top.')


if __name__ == '__main__':
    main()
