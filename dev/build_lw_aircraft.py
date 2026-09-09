#!/usr/bin/env python3
"""Cut the Bf 109 side views out of their black ground.

    python3 dev/build_lw_aircraft.py

Forty profiles, one per Gruppe of each fighter Geschwader, named exactly
as the Room names a unit's roster file - I_JG26 for I./JG 26 - so the
lookup needs nothing mapped by hand.

The background is removed by flooding INWARD FROM THE EDGES rather than
by clearing every dark pixel. The propeller blades, the exhaust stubs and
the Balkenkreuz outline are all dark and enclosed by the aeroplane, and
clearing by colour alone punches holes straight through them.

The tolerance is 60 and that number was arrived at by looking. These are
JPEGs, so there is a compression halo around the aerial wire where it
crosses the black, and at a tight tolerance that halo survives as an
opaque grey wedge between the wire and the fuselage spine. On white it is
invisible; on the Room's near-black panel it reads as a shadow hanging
under the aerial, which is what Patrick spotted. Sixty clears it. Above
about seventy the propeller blades start to thin out, so it is a window
rather than a bigger-is-better.
"""
import glob, os, sys
from collections import deque
from PIL import Image

SRC = '/home/patrick_millin/bob2/Me109_Sideviews_GermanCross_Only/me109_sideviews'
OUT = 'squadronroom/lw/aircraft'
TOL = 60
WIDTH = 1000


def cut(path):
    im = Image.open(path).convert('RGBA')
    w, h = im.size
    px = im.load()

    def dark(p):
        return p[0] <= TOL and p[1] <= TOL and p[2] <= TOL

    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if dark(px[x, y]) and not seen[y * w + x]:
                seen[y * w + x] = 1; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if dark(px[x, y]) and not seen[y * w + x]:
                seen[y * w + x] = 1; q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and dark(px[nx, ny]):
                seen[ny * w + nx] = 1; q.append((nx, ny))
    for y in range(h):
        r = y * w
        for x in range(w):
            if seen[r + x]:
                px[x, y] = (0, 0, 0, 0)
    im = im.crop(im.getbbox())
    return im.resize((WIDTH, max(1, round(im.size[1] * WIDTH / im.size[0]))), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for f in sorted(glob.glob(os.path.join(SRC, '*.jpg'))):
        base = os.path.splitext(os.path.basename(f))[0]
        cut(f).save(os.path.join(OUT, base + '.png'))
        n += 1
    print('%d profiles cut at tolerance %d -> %s' % (n, TOL, OUT))
    return 0


if __name__ == '__main__':
    sys.exit(main())
