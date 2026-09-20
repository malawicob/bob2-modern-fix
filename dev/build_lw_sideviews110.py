#!/usr/bin/env python3
"""Paint the Bf 110 side views from the game's own skins.

    python3 dev/build_lw_sideviews110.py --all
    python3 dev/build_lw_sideviews110.py --skin bf110-greygreen --out /tmp/x.png

The same idea as dev/build_lw_sideviews.py for the 109: Patrick's blank
plate (dev/art/bf110_blank.jpg, 2704x736, plain grey on black) gives the
shape, the panel lines and the shading; the colour of every painted pixel
is looked up in the skin's texture through the 110's UV layout, so the
side view IS the skin and cannot drift from it. No swastika, Patrick's
instruction: it is taken out of the fin before the fin is mapped.

THE 110 SHEET, in 1024 space (the files are 4096 square)

  fuselage   x 192 (nose) to 1024 (tail) in slabs: a top face, the port
             side y 793 to about 872, a belly face centred on y 907, and
             the other side mirrored below. The port Balkenkreuz is
             centred on (741, 831).
  nacelle    x 8..165, y 440 (front) to 750: belly at x 8, the exhaust
             slot at x 98, the top centreline at x 165.
  fin        port fin, outer face: x 592..652, y 432..528, swastika on it.
  wing       port upper surface x 200..440, y 265..395, chord down the sheet.

Spinners are separate textures the game picks by unit; the plate's own
spinner is left as drawn.
"""
import argparse, glob, json, os, sys
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = '/mnt/d/Battle of Britain II_Latest_test/MultiSkin/MultiSkinTextures'

# the plate, native pixels
TOP = [(108, 392), (130, 349), (160, 340), (200, 324), (250, 309), (300, 300), (400, 288), (500, 284),
       (1000, 278), (1085, 262), (1095, 237), (1200, 238), (1300, 241), (1400, 245), (1600, 254),
       (1800, 266), (2000, 279), (2100, 288), (2200, 296)]
BOT = [(108, 400), (130, 431), (160, 448), (200, 462), (250, 472), (300, 478), (700, 495), (1100, 497),
       (1200, 482), (1300, 478), (1400, 473), (1600, 463), (1800, 449), (2000, 433), (2100, 424), (2200, 412)]
X_NOSE, X_TAIL = 108.0, 2200.0
T_NOSE, T_TAIL = 192.0, 1024.0
SCALE_X = (X_TAIL - X_NOSE) / (T_TAIL - T_NOSE)
X_FIN = 2128                                                  # everything painted aft of this is fin and rudder
FIN_BLANK = (2128, 111, 2422, 416)
FIN_TEX = (592, 432, 652, 528)
CANOPY = [(495, 290), (558, 212), (1030, 200), (1092, 240), (1085, 262), (1000, 280), (500, 292)]
NACELLE = [(340, 365), (400, 320), (480, 305), (580, 303), (700, 315), (770, 332), (1290, 455), (1180, 482),
           (1150, 497), (1100, 520), (1050, 545), (950, 562), (700, 565), (600, 557), (540, 537), (460, 527),
           (460, 500), (400, 492), (340, 472)]
N_TOP = [(340, 365), (400, 320), (480, 305), (580, 303), (700, 315), (800, 335), (1180, 470)]
N_BOT = [(340, 472), (400, 492), (460, 514), (540, 537), (600, 557), (700, 565), (950, 562), (1050, 545),
         (1100, 520), (1180, 482)]
WING = [(625, 400), (660, 380), (700, 355), (740, 332), (800, 318), (900, 318), (985, 340), (1050, 372),
        (1100, 400), (1200, 438), (1295, 455), (1230, 466), (1150, 442), (1000, 432), (800, 440),
        (680, 430), (640, 418)]
CROP = (95, 105, 2432, 612)
OUT_W = 996


def interp(x, pts):
    xs, ys = zip(*pts)
    return np.interp(x, xs, ys)


# The 110's fuselage is slab sided and the sheet treats it so: a top face,
# the port side, a separate belly face (the pale band centred on y 907)
# and the other side mirrored below that. A side view shows the SIDE face
# only, y 793 down to its lower edge, which rises toward the tail as the
# fuselage tapers. The Balkenkreuz, centred on y 831, sits mid-side, which
# is where a 110 wears it. Read as one continuous unwrap (spine to belly
# centreline) the first attempt drew half the belly onto the side.
T_SIDE_TOP = 793.0
# The side face is not the whole height of the side view. Mapped over all of
# it the Balkenkreuz came out half as tall again as it was wide; a cross is
# square, and that fixes the scale: the side face is the middle 64% of the
# silhouette, and the rounded shoulders above and below it show the edge of
# the top decking and of the belly, 23 texels of each.
V_SIDE0, V_SIDE1, T_DECK = 0.18, 0.82, 23.0
def t_low(xt):
    return np.interp(xt, [192, 600, 704, 1024], [878.0, 876.0, 872.0, 850.0])


def tex_box_to_profile(box2048):
    """A box on the port fuselage side of the sheet (2048 space, which is
    what dev/measure_markings.py works in) as it lands on a painted side
    view. One plate, one mapping: exact, and the same for every skin."""
    l, t, r, b = [v / 2.0 for v in box2048]
    s = OUT_W / float(CROP[2] - CROP[0])
    def X(xt): return X_NOSE + (xt - T_NOSE) * SCALE_X
    Xc = X((l + r) / 2.0)
    top, bot = float(interp(Xc, TOP)), float(interp(Xc, BOT))
    low = float(t_low((l + r) / 2.0))
    def Y(yt): return top + (V_SIDE0 + (V_SIDE1 - V_SIDE0) * (yt - T_SIDE_TOP) / (low - T_SIDE_TOP)) * (bot - top)
    return [int(round((X(l) - CROP[0]) * s + 2)), int(round((Y(t) - CROP[1]) * s + 2)),
            int(round((X(r) - CROP[0]) * s + 2)), int(round((Y(b) - CROP[1]) * s + 2))]


def blur(arr, r):
    a = arr.astype(np.float32)
    k = 2 * r + 1
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(2)], mode='edge'), axis=ax)
            a = (np.take(c, range(k, c.shape[ax]), axis=ax) - np.take(c, range(0, c.shape[ax] - k), axis=ax)) / k
    return a


def poly_mask(size, pts):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return np.asarray(m) > 0


def build(skin, out, blank):
    cand = [f for f in glob.glob(TEX + '/*.dds') if os.path.splitext(os.path.basename(f))[0].lower() == skin.lower()]
    if not cand:
        return False
    T = np.asarray(Image.open(cand[0]).convert('RGB').resize((1024, 1024), Image.LANCZOS)).astype(np.float32)

    # NO SWASTIKA. A fixed box on the port fin, filled inward in passes from
    # the fin's own paint round about (one pass does not reach the middle).
    fx0, fy0, fx1, fy1 = FIN_TEX
    mark = np.zeros(T.shape[:2], bool)
    mark[470:528, 596:658] = True
    region = np.zeros(T.shape[:2], bool)
    region[fy0 - 4:fy1 + 4, fx0 - 2:662] = True
    todo, known = mark.copy(), region & ~mark
    for _ in range(12):
        if not todo.any():
            break
        valid = known.astype(np.float32)
        ws = blur(valid, 6)
        ok = todo & (ws > 0.08)
        if not ok.any():
            ok = todo & (ws > 0)
            if not ok.any():
                break
        for c in range(3):
            T[..., c] = np.where(ok, blur(T[..., c] * valid, 6) / np.maximum(ws, 1e-4), T[..., c])
        known |= ok
        todo &= ~ok

    B = np.asarray(Image.open(blank).convert('RGB')).astype(np.float32)
    H, W, _ = B.shape
    lum = B.mean(axis=2); sat = B.max(axis=2) - B.min(axis=2)
    fg = lum > 22
    skin_m = fg & (sat < 30) & (lum > 62)                     # painted metal; exhausts, blades and tyres are darker
    skin_m &= ~poly_mask((W, H), CANOPY)
    # the propeller blades and the hub cross the nose and the nacelle, and
    # their highlights are as light as shaded metal: in their column only
    # what is plainly skin counts (the shark mouth ran down a blade)
    XXi = np.arange(W)[None, :].repeat(H, 0)
    skin_m &= ~((XXi > 270) & (XXi < 345) & (lum < 100))
    ref = float(np.median(lum[skin_m]))
    shade = np.clip(lum / ref, 0.30, 1.35)[..., None]

    YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)
    top = interp(XX[0], TOP)[None, :].repeat(H, 0); bot = interp(XX[0], BOT)[None, :].repeat(H, 0)
    v = np.clip((YY - top) / np.maximum(bot - top, 1), 0, 1)
    xt = T_NOSE + (XX - X_NOSE) / SCALE_X
    low = t_low(xt)
    # The shoulder above the side face carries the side's own top edge up to
    # the spine (mirrored a few texels), NOT the sheet above y 793: that is
    # a different island, and sampling it drew pale streaks along the spine
    # of every pale skin.
    yt = np.where(v < V_SIDE0, T_SIDE_TOP + (V_SIDE0 - v) / V_SIDE0 * 8.0,
         np.where(v < V_SIDE1, T_SIDE_TOP + (v - V_SIDE0) / (V_SIDE1 - V_SIDE0) * (low - T_SIDE_TOP),
                  low + (v - V_SIDE1) / (1 - V_SIDE1) * T_DECK))

    nac = skin_m & poly_mask((W, H), NACELLE)
    wing = skin_m & poly_mask((W, H), WING)
    nac &= ~wing
    fin = skin_m & (XX >= X_FIN)
    body = skin_m & ~nac & ~wing & ~fin & (XX >= X_NOSE)

    # nacelle: front to back runs DOWN the sheet; top centreline x 165, the
    # exhaust slot x 98, belly x 8, and the slot sits 0.59 of the way down
    # the plate's nacelle (the radiator bath deepens the lower half)
    nt = interp(XX[0], N_TOP)[None, :].repeat(H, 0); nb = interp(XX[0], N_BOT)[None, :].repeat(H, 0)
    nv = np.clip((YY - nt) / np.maximum(nb - nt, 1), 0, 1)
    n_x = np.interp(nv, [0, 0.59, 1.0], [165.0, 98.0, 10.0])
    n_y = 442 + np.clip((XX - 340) / (1180 - 340), 0, 1) * (748 - 442)
    xt = np.where(nac, n_x, xt); yt = np.where(nac, n_y, yt)
    # wing: what shows in a side view is the tip end-on and the upper skin
    uu = np.clip((XX - 625) / (1295 - 625), 0, 1); ss = np.clip((YY - 318) / (470 - 318), 0, 1)
    xt = np.where(wing, 430 - ss * 200, xt); yt = np.where(wing, 272 + uu * (392 - 272), yt)
    # fin and rudder: box to box
    bx0, by0, bx1, by1 = FIN_BLANK
    xt = np.where(fin, fx0 + (XX - bx0) / (bx1 - bx0) * (fx1 - fx0), xt)
    yt = np.where(fin, fy0 + (YY - by0) / (by1 - by0) * (fy1 - fy0), yt)

    xi = np.clip(xt, 0, 1023).astype(int); yi = np.clip(yt, 0, 1023).astype(int)
    col = T[yi, xi]
    # a sample that fell on the sheet's background is not paint
    bgc = T[700, 520]
    sidec = np.median(T[810:860, 620:700].reshape(-1, 3), axis=0)
    finc = np.median(T[440:470, 600:640].reshape(-1, 3), axis=0)
    topc = np.median(T[300:380, 250:420].reshape(-1, 3), axis=0)
    onbg = np.abs(col - bgc).sum(axis=2) < 14
    col[onbg & (body | nac)] = sidec
    col[onbg & fin] = finc
    col[onbg & wing] = topc

    outp = B.copy()
    m = body | nac | wing | fin
    outp[m] = np.clip(col[m] * shade[m], 0, 255)
    alpha = (fg * 255).astype(np.uint8)
    im = Image.fromarray(np.dstack([outp.astype(np.uint8), alpha]))
    s = OUT_W / float(CROP[2] - CROP[0])
    im = im.crop(CROP).resize((int((CROP[2] - CROP[0]) * s), int((CROP[3] - CROP[1]) * s)), Image.LANCZOS)
    canvas = Image.new('RGBA', (1000, im.size[1] + 4), (0, 0, 0, 0)); canvas.paste(im, (2, 2), im)
    canvas.save(out)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--skin'); ap.add_argument('--out')
    ap.add_argument('--all', action='store_true', help='every 110 side view in --outdir, under its own name')
    ap.add_argument('--outdir', default=os.path.join(ROOT, 'squadronroom/lw/aircraft'))
    ap.add_argument('--blank', default=os.path.join(ROOT, 'dev/art/bf110_blank.jpg'))
    a = ap.parse_args()
    if a.all:
        names = sorted(f for f in os.listdir(os.path.join(ROOT, 'squadronroom/lw/aircraft'))
                       if '110' in f.lower() and f.lower().endswith('.png'))
        os.makedirs(a.outdir, exist_ok=True)
        done, missing = 0, []
        for f in names:
            if build(os.path.splitext(f)[0], os.path.join(a.outdir, f), a.blank):
                done += 1
            else:
                missing.append(f)
        print('%d side views painted into %s; no texture for %d: %s' % (done, a.outdir, len(missing), missing))
        return 0
    if not build(a.skin, a.out, a.blank):
        print('no texture for %s' % a.skin, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
