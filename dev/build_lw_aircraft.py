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

The background is cleared in TWO passes, and the second one is the whole
point.

A single tolerance cannot do this job. At 26 the aeroplane is safe but a
band of JPEG halo survives around the aerial wire, and on the Room's
near-black panel that reads as a shadow hanging under the aerial. Raise
the tolerance to clear it and the flood finds its way through the dark
propeller blades and eats the spinner cone out from behind them, leaving
the white spiral painted on it floating in mid air. That is exactly what
shipped on 10 September and what Patrick spotted.

So:

  PASS ONE floods in from the edges at tolerance 26. Nothing that matters
  is dark enough to be reached, so the blades, the spinner and the
  Balkenkreuz outline all survive.

  PASS ONE AND A HALF clears black that the aerial wire walled off from
  the edges, found by distance rather than by colour, because the core of
  the Balkenkreuz is pure black too.

  PASS TWO grows that background outward by at most GROW pixels, taking
  only pixels darker than HALO. Distance is what makes it safe: a halo is
  two or three pixels wide and disappears, while the spinner is a solid
  mass and loses at most three pixels off an edge that was antialiased
  into the background anyway.

Flooding from the EDGES rather than clearing every dark pixel is the
other half of it. The propeller blades, the exhaust stubs and the
Balkenkreuz outline are all dark and enclosed by the aeroplane, and
clearing by colour alone punches holes straight through them.
"""
import glob, os, sys
from collections import deque
from PIL import Image

SRC = '/home/patrick_millin/bob2/Me109_Sideviews_GermanCross_Only/me109_sideviews'
OUT = 'squadronroom/lw/aircraft'
TOL  = 26      # definite background, flooded from the edges
HALO = 78      # a dark pixel close to the background is JPEG halo
GROW   = 3     # and it is never more than this many pixels deep
PURE   = 12    # background black; nothing on the aeroplane is this dark
             # except the Balkenkreuz core, which is nowhere near an edge
BRIDGE = 3     # how thin a barrier the background may be trapped behind
WIDTH = 1000


def cut(path):
    im = Image.open(path).convert('RGBA')
    w, h = im.size
    px = im.load()

    def dark(p, t):
        return p[0] <= t and p[1] <= t and p[2] <= t

    seen = bytearray(w * h)
    q = deque()

    def push(x, y):
        i = y * w + x
        if not seen[i] and dark(px[x, y], TOL):
            seen[i] = 1
            q.append((x, y))

    for x in range(w):
        push(x, 0); push(x, h - 1)
    for y in range(h):
        push(0, y); push(w - 1, y)
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and dark(px[nx, ny], TOL):
                seen[ny * w + nx] = 1
                q.append((nx, ny))

    # PASS ONE AND A HALF: background trapped behind the aerial.
    #
    # The wire runs from the canopy to the fin and cuts the black above
    # the fuselage in two. The pocket under it never touches an edge, so
    # the flood cannot reach it, and it shipped as a black wedge across
    # the rear fuselage of III./JG 26 and III./JG 53.
    #
    # It cannot be cleared by colour: the pocket is pure black and so is
    # the CORE OF THE BALKENKREUZ, 800 to 2000 pixels of it in every
    # profile. Clearing pure black everywhere would punch the cross out.
    # Size does not separate them safely either.
    #
    # What does separate them is distance. The pocket is two or three
    # pixels from cleared background, with only the wire in between; the
    # cross is deep inside the fuselage, tens of pixels from anything
    # cleared. So the cleared mask is dilated BRIDGE pixels regardless of
    # colour, and any pure-black region it reaches is background that was
    # walled off. The cross is never reached.
    dil = bytearray(seen)
    for _ in range(BRIDGE):
        add = []
        for y in range(h):
            r = y * w
            for x in range(w):
                if dil[r + x]:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not dil[ny * w + nx]:
                            add.append(ny * w + nx)
        for i in add:
            dil[i] = 1

    checked = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            i = sy * w + sx
            if seen[i] or checked[i] or not dark(px[sx, sy], PURE):
                continue
            blob = []
            touches = False
            q2 = deque([(sx, sy)])
            checked[i] = 1
            while q2:
                x, y = q2.popleft()
                blob.append(y * w + x)
                if dil[y * w + x]:
                    touches = True
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    j = ny * w + nx
                    if 0 <= nx < w and 0 <= ny < h and not checked[j] and not seen[j] \
                            and dark(px[nx, ny], PURE):
                        checked[j] = 1
                        q2.append((nx, ny))
            if touches:
                for j in blob:
                    seen[j] = 1

    # Pass two: grow the background a few pixels into anything still dark.
    # Bounded by DISTANCE, which is what stops it walking down a propeller
    # blade and hollowing out the spinner.
    frontier = [(x, y) for y in range(h) for x in range(w) if seen[y * w + x]]
    for _ in range(GROW):
        nxt = []
        for x, y in frontier:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and dark(px[nx, ny], HALO):
                    seen[ny * w + nx] = 1
                    nxt.append((nx, ny))
        frontier = nxt
        if not frontier:
            break

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
    print('%d profiles cut: flood at %d, halo grown %d px at %d -> %s'
          % (n, TOL, GROW, HALO, OUT))
    return 0


if __name__ == '__main__':
    sys.exit(main())
