#!/usr/bin/env python3
"""Cut a badge out of a flat coloured background.

    python3 dev/cut_badge.py --src "<image>" --out squadronroom/lw/badges/crew-badge.png

Patrick supplies these as renders on a plain ground. The first
Fliegerschuetzen- und Bordfunkerabzeichen came on a transparency
CHECKERBOARD baked in as pixels, which is the awkward case: the pattern
is two neutral greys and the badge is silver, so it passes through both,
and a flood from the edges stalls at every square boundary on the one
pixel of blend between tones. The second came on flat pale blue, which is
the easy case and the one this handles.

A flat, strongly coloured ground needs no flood at all. Silver is
neutral - its blue channel sits within a dozen levels of its red - and
the background here is +64 blue, so the two never overlap and every
background pixel can be cleared wherever it is, INCLUDING the area
enclosed by the wreath that a flood could never reach.

The edge is feathered rather than cut hard: alpha runs from nothing to
full across a band of colour distance, so the badge does not acquire a
ring of background-coloured pixels when it is scaled down to the 62
pixels the Room shows it at.
"""
import argparse, collections, os, sys
from PIL import Image

NEAR, FAR = 34.0, 96.0          # colour distance: all background, all badge


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--out', default='squadronroom/lw/badges/crew-badge.png')
    ap.add_argument('--height', type=int, default=460,
                    help='to match pilot-badge.png, which the Room shows beside it')
    a = ap.parse_args()

    im = Image.open(a.src).convert('RGBA')
    W, H = im.size
    px = im.load()

    # the ground, read off the border rather than assumed
    c = collections.Counter()
    for y in list(range(0, 30)) + list(range(H - 30, H)):
        for x in range(0, W, 4):
            c[px[x, y][:3]] += 1
    for x in list(range(0, 30)) + list(range(W - 30, W)):
        for y in range(0, H, 4):
            c[px[x, y][:3]] += 1
    br, bg_, bb = c.most_common(1)[0][0]

    n = 0
    for y in range(H):
        for x in range(W):
            r, g, b, _ = px[x, y]
            d = ((r - br) ** 2 + (g - bg_) ** 2 + (b - bb) ** 2) ** 0.5
            if d <= NEAR:
                px[x, y] = (r, g, b, 0); n += 1
            elif d < FAR:
                px[x, y] = (r, g, b, int(255 * (d - NEAR) / (FAR - NEAR)))

    bbox = im.split()[3].point(lambda v: 255 if v > 40 else 0).getbbox()
    if not bbox:
        print('nothing left after the cut', file=sys.stderr)
        return 1
    im = im.crop(bbox)
    w, h = im.size
    im = im.resize((max(1, round(w * a.height / float(h))), a.height), Image.LANCZOS)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    im.save(a.out)
    print('ground (%d,%d,%d) cleared from %d px (%.1f%%) -> %s %dx%d'
          % (br, bg_, bb, n, 100.0 * n / (W * H), a.out, im.size[0], im.size[1]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
