#!/usr/bin/env python3
"""Draw the Fliegerschuetzenabzeichen, the air crew badge.

    python3 dev/make_crew_badge.py --out squadronroom/lw/badges/crew-badge.png

WHY IT HAS TO EXIST

The Ready Room hard-codes pilot-badge.png, the Flugzeugfuehrerabzeichen,
under the player's name. On a Bf 110 the man in the back is not a pilot
and did not wear it. Giving him the pilot's badge would be as wrong as
putting RAF wings on an air gunner, and it is the sort of wrong that the
people who care about this period notice first.

WHAT THE BADGE IS

The Fliegerschuetzenabzeichen - the air gunner's and flight engineer's
badge - is the same silver oval wreath of oak and laurel as the pilot's,
with a different device inside it. The pilot's carries a diving eagle
across the whole oval. The gunner's carries a smaller eagle with a
lightning bolt in its claws, set low and to one side, with the wreath
left plainer. That difference is the whole point of drawing it rather
than reusing the other one.

ITS OUTPUT IS NOT SHIPPED, AND SHOULD NOT BE UNTIL IT IS BETTER.

The collar patches in dev/make_lw_badges.py are drawn and they work,
because a collar patch IS flat shapes: a coloured lozenge, some braid,
a few gulls. This badge is not. The real thing is a silver oval wreath
of oak and laurel with a modelled eagle across it, and pilot-badge.png
beside it in the Room is a photographic-quality render of exactly that.
Drawn from primitives, this comes out as a ring of triangles around a
dark blob, and put next to the pilot's badge the difference is the first
thing anybody sees.

So the file is left here, the Room looks for crew-badge.png, and
New-BadgeImage returns nothing when it is absent - the crewman simply
shows his rank cuff and no badge, which is a gap rather than an error.
The proper fix is a real image of the Fliegerschuetzenabzeichen, the way
Patrick supplied the pilot's badge and the medals. Run this only if you
mean to improve it first.
"""
import argparse, math, os
from PIL import Image, ImageDraw

W, H = 560, 460
SCALE = 4

SILVER    = (208, 208, 202)
SILVER_D  = (128, 128, 124)
SILVER_HI = (238, 238, 232)
DARK      = (58, 58, 54)


def wreath(d, cx, cy, rx, ry, n=34):
    """The oval wreath: oak on one side, laurel on the other, as the real
    badge has it. At this size the two read as one ring of leaves, which
    is what matters; the join at top and bottom is what says 'wreath'."""
    for i in range(n):
        t = (i / float(n)) * 2 * math.pi - math.pi / 2
        x = cx + rx * math.cos(t)
        y = cy + ry * math.sin(t)
        # leaves lie along the ring, tilted with it
        lr = rx * 0.085
        tilt = t + math.pi / 2
        pts = []
        for k, (a, b) in enumerate(((0.0, 1.0), (0.75, 0.45), (1.6, 0.0), (0.75, -0.45), (0.0, -1.0))):
            px = x + math.cos(tilt) * lr * a - math.sin(tilt) * lr * b * 0.9
            py = y + math.sin(tilt) * lr * a + math.cos(tilt) * lr * b * 0.9
            pts.append((px, py))
        d.polygon(pts, fill=SILVER, outline=SILVER_D)
    # the band that binds the wreath at the foot
    d.ellipse([cx - rx * 0.16, cy + ry - rx * 0.10, cx + rx * 0.16, cy + ry + rx * 0.10],
              fill=SILVER_HI, outline=SILVER_D)


def eagle(d, cx, cy, span):
    """A small eagle with a lightning bolt, set low in the oval.

    The pilot's badge has a big diving eagle filling the wreath. This one
    is smaller, level rather than diving, and sits below centre, which is
    the difference a reader actually sees between the two badges.
    """
    s = span
    # body
    d.polygon([(cx, cy - s * 0.16), (cx + s * 0.055, cy + s * 0.10),
               (cx, cy + s * 0.30), (cx - s * 0.055, cy + s * 0.10)],
              fill=DARK, outline=(20, 20, 18))
    # head, turned to the bird's right as the badge has it
    d.ellipse([cx - s * 0.10, cy - s * 0.30, cx + s * 0.03, cy - s * 0.15],
              fill=DARK, outline=(20, 20, 18))
    d.polygon([(cx - s * 0.10, cy - s * 0.245), (cx - s * 0.20, cy - s * 0.225),
               (cx - s * 0.10, cy - s * 0.195)], fill=(20, 20, 18))
    # wings, swept and level
    for sgn in (-1, 1):
        d.polygon([(cx + sgn * s * 0.04, cy - s * 0.10),
                   (cx + sgn * s * 0.62, cy - s * 0.26),
                   (cx + sgn * s * 0.72, cy - s * 0.05),
                   (cx + sgn * s * 0.30, cy + s * 0.10)],
                  fill=DARK, outline=(20, 20, 18))
    # the lightning bolt in the claws, which the pilot's badge has not got
    bx, by = cx + s * 0.02, cy + s * 0.26
    d.polygon([(bx - s * 0.20, by), (bx - s * 0.02, by - s * 0.07),
               (bx - s * 0.06, by + s * 0.01), (bx + s * 0.20, by - s * 0.06),
               (bx + s * 0.01, by + s * 0.08), (bx + s * 0.05, by + s * 0.005)],
              fill=SILVER_HI, outline=SILVER_D)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='squadronroom/lw/badges/crew-badge.png')
    a = ap.parse_args()
    w, h = W * SCALE, H * SCALE
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = w * 0.5, h * 0.5
    wreath(d, cx, cy, w * 0.40, h * 0.44)
    eagle(d, cx, cy + h * 0.02, w * 0.30)
    im = im.resize((W, H), Image.LANCZOS)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    im.save(a.out)
    print('the air crew badge -> %s (%d x %d)' % (a.out, W, H))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
