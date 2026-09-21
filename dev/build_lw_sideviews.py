#!/usr/bin/env python3
"""Side views painted from the game's own textures.

    python3 dev/build_lw_sideviews.py --skin M109ULF_IIJG26_camo --out /tmp/x.png

PROTOTYPE. Patrick's hand-made side views do not always match the texture
the game paints (58 of 126 share one grey plate). The textures themselves
lay the fuselage out as a side projection: nose left, spine at the top of
the upper strip, belly centreline in the middle of the sheet, a wedge cut
out toward the tail, and the fin and tail cone as their own island top
right. So a blank, unpainted side view (dev/art/bf109e_blank.jpg, neutral
grey, Patrick's) supplies shape, panel lines and shading, and the texture
supplies every colour: result = texture colour x (blank luminance / its
median). Canopy, exhausts, propeller, wheel and the aerial stay as drawn.
Coordinates below are for the 1872x1056 blank and a 1024 texture.
"""
import argparse, os, glob
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = '/mnt/d/Battle of Britain II_Latest_test/MultiSkin/MultiSkinTextures'

def interp(x, pts):
    xs, ys = zip(*pts); return np.interp(x, xs, ys)

# blank plate: fuselage top and bottom, canopy, aerial and wing excluded
TOP = [(170,452),(200,448),(300,433),(400,423),(500,417),(600,412),(650,409),(950,379),(1200,400),(1540,431),(1720,446)]
BOT = [(170,600),(200,620),(300,640),(480,652),(960,645),(1200,616),(1400,586),(1600,553),(1720,530)]
X_NOSE, X_FINROOT, SCALE_X = 170.0, 1540.0, 1.957          # blank x = 170 + (tex x - 165) * 1.957
T_NOSE, T_SPINE = 165.0, 64.0                                 # texture, 1024 space
def t_low(xt):                                                # bottom of the side strip: belly turn, then the wedge edge
    return np.where(xt < 610, 203.0, np.interp(xt, [610, 865], [195.0, 150.0]))
FIN_BLANK = (1540, 250, 1848, 556)                            # x0,y0,x1,y1 of fin, rudder and tail cone on the blank

def tex_box_to_profile(box2048):
    """A box on the fuselage side of the 2048 skin sheet, as it lands on a
    generated 1000x295 side view. Every generated side view is the same
    plate through the same mapping, so this is exact and the same for all
    of them; dev/measure_markings.py uses it rather than hunting for the
    cross in 125 different paint schemes, which found it within 3 px on 87
    of them and somewhere else entirely on the rest."""
    l, t, r, b = [v / 2.0 for v in box2048]
    xc = (l + r) / 2.0
    low = float(t_low(np.array(xc)))
    s = 993.0 / (1844 - 51)
    def X(xt): return X_NOSE + (xt - T_NOSE) * SCALE_X
    Xc = X(xc)
    top, bot = float(np.interp(Xc, *zip(*TOP))), float(np.interp(Xc, *zip(*BOT)))
    def Y(yt): return top + (yt - T_SPINE) / (low - T_SPINE) * (bot - top)
    return [int(round((X(l) - 51) * s + 2)), int(round((Y(t) - 250) * s + 1)),
            int(round((X(r) - 51) * s + 2)), int(round((Y(b) - 250) * s + 1))]

FIN_REF = 'M109ULF_IIJG54_6_Joachim_Schypek_7U'              # pale fin on the olive sheet: its outline is everybody's
_fin_shape = None
def fin_shape():
    global _fin_shape
    if _fin_shape is None:
        cand = [f for f in glob.glob(TEX + '/*') if os.path.splitext(os.path.basename(f))[0].lower() == FIN_REF.lower()]
        R = np.asarray(Image.open(cand[0]).convert('RGB').resize((1024, 1024), Image.LANCZOS)).astype(np.float32)
        m = np.abs(R - R[300, 140]).sum(axis=2) > 60
        m[:, :868] = False; m[150:, :] = False
        from scipy import ndimage as ndi
        _fin_shape = ndi.binary_fill_holes(m)
    return _fin_shape

def build(a):
    cand = [f for f in glob.glob(TEX + '/*') if os.path.splitext(os.path.basename(f))[0].lower() == a.skin.lower()]
    if not cand:
        return False
    tex = Image.open(cand[0]).convert('RGB').resize((1024, 1024), Image.LANCZOS)
    T = np.asarray(tex).astype(np.float32)
    # NO SWASTIKA, Patrick's instruction. It is painted into the fin island
    # of every texture, so it is taken out of the sample before anything is
    # mapped: the black of it (and, by growing the mask, its white outline)
    # is filled from the fin's own colours round about, so the camouflage
    # carries across where the marking was.
    from PIL import ImageFilter
    # A FIXED BOX, not a search for black. The first version masked only
    # what was darker than 50 and grew it: on a dark green fin that missed
    # grey or outline-only swastikas and left white corners on others, and
    # Patrick could still see them. Every skin shares one UV layout, so the
    # marking always sits in the same place on the fin, forward of the
    # rudder hinge (x 958): the whole box goes, and is filled from the fin's
    # own paint around it, never from the sheet's olive background.
    bg0 = T[300, 140]
    notbg = np.abs(T - bg0).sum(axis=2) > 60
    # FIND IT, because it is not always in the same place: on most skins it
    # sits on the fin forward of the hinge, on some across the hinge and on
    # a few on the rudder itself, so a fixed box left it standing on those.
    # It is the one squarish, high-contrast shape of its size on the fin;
    # the rudder hinge is a long thin line and victory bars are small, so
    # neither qualifies. Where nothing qualifies the usual box is cleared.
    from scipy import ndimage as ndi
    lumT = T.mean(axis=2)
    y0, y1, x0, x1 = 0, 150, 876, 1020
    reg = lumT[y0:y1, x0:x1]
    contrast = np.abs(reg - ndi.uniform_filter(reg, 21)) > 34
    contrast &= ndi.binary_erosion(notbg[y0:y1, x0:x1], iterations=4)      # not the island's own edge
    # TWO PLACES, always cleared, plus anything black and squarish of the
    # right size. Looked at across all 126 fins: the marking is either on
    # the fin forward of the hinge or across the top of the hinge onto the
    # rudder, and those second ones defeated every shape test because they
    # run into the hinge line and read as one long object. Contrast
    # detection was dropped: it took victory bars and camouflage edges.
    mark = np.zeros(T.shape[:2], bool)
    mark[8:94, 891:956] = True
    # The second place, across the hinge onto the rudder, is cleared only
    # when the fin itself carries no marking: victory bars live on the
    # rudder at the same height and a box laid over them left half a tally.
    on_fin = int((lumT[20:90, 893:935] < 46).sum())
    if on_fin < 150:
        mark[8:82, 936:986] = True
    # Masked by the SHAPE of the fin, not by "differs from the sheet colour":
    # an all-green fin IS the sheet colour, that mask came back empty and the
    # marking stood untouched on every dark skin. Every skin shares one UV
    # layout, so the shape is read once from a pale-finned skin. Going the
    # other way and clearing the sheet above the fin as well dragged the
    # yellow rudder tip down over the fin.
    paint = notbg | fin_shape()
    mark &= paint
    # Filled SEPARATELY either side of the rudder hinge (x 957), so a yellow
    # rudder does not bleed onto the fin nor the fin's blue onto the rudder.
    def blur(arr, r=16):
        a = arr.astype(np.float32)
        k = 2 * r + 1
        for _ in range(3):
            for ax in (0, 1):
                c = np.cumsum(np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(2)], mode='edge'), axis=ax)
                a = (np.take(c, range(k, c.shape[ax]), axis=ax) - np.take(c, range(0, c.shape[ax] - k), axis=ax)) / k
        return a
    xs_all = np.arange(T.shape[1])[None, :].repeat(T.shape[0], 0)
    for side in (xs_all < 957, xs_all >= 957):
        todo = mark & side
        known = paint & ~mark & side
        # worked inward in passes: the middle of the box is further from any
        # real paint than one blur reaches, and a single pass left the centre
        # of the marking standing
        for _ in range(12):
            if not todo.any():
                break
            valid = known.astype(np.float32)
            wsum = blur(valid, 8)
            ok = todo & (wsum > 0.08)
            if not ok.any():
                ok = todo & (wsum > 0.0)
                if not ok.any():
                    break
            for c in range(3):
                fill = blur(T[..., c] * valid, 8) / np.maximum(wsum, 1e-4)
                T[..., c] = np.where(ok, fill, T[..., c])
            known = known | ok
            todo = todo & ~ok
    B = np.asarray(Image.open(a.blank).convert('RGB')).astype(np.float32)
    H, W, _ = B.shape
    lum = B.mean(axis=2); sat = B.max(axis=2) - B.min(axis=2)
    fg = lum > 22
    skin = fg & (sat < 30) & (lum > 95)                       # painted metal: neutral and light
    # the canopy and its frames are neutral grey too, and are not skin
    cm = Image.new('L', (W, H), 0)
    ImageDraw.Draw(cm).polygon([(652, 468), (688, 372), (872, 366), (950, 376), (905, 432), (872, 468)], fill=255)
    skin &= ~(np.asarray(cm) > 0)
    ref = float(np.median(lum[skin]))
    shade = np.clip(lum / ref, 0.30, 1.30)[..., None]

    # fin island in the texture: everything that is not the olive sheet colour, right of the fuselage strip
    bgc = T[300, 140]
    isl = (np.abs(T - bgc).sum(axis=2) > 60)
    isl[:, :868] = False; isl[215:, :] = False
    ys, xs = np.where(isl); fx0, fx1, fy0, fy1 = xs.min(), xs.max(), ys.min(), ys.max()

    YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)
    top = interp(XX[0], TOP)[None, :].repeat(H, 0); bot = interp(XX[0], BOT)[None, :].repeat(H, 0)
    xt = T_NOSE + (XX - X_NOSE) / SCALE_X
    v = (YY - top) / np.maximum(bot - top, 1)
    yt = T_SPINE + np.clip(v, 0, 1) * (t_low(xt) - T_SPINE)
    body = skin & (XX >= X_NOSE) & (XX < X_FINROOT) & (v >= -0.02) & (v <= 1.03)
    # fin, rudder and tail cone: island box to blank box
    bx0, by0, bx1, by1 = FIN_BLANK
    fin = skin & (XX >= bx0) & (XX <= bx1) & (YY >= by0) & (YY <= by1)
    xt_f = fx0 + (XX - bx0) / (bx1 - bx0) * (fx1 - fx0); yt_f = fy0 + (YY - by0) / (by1 - by0) * (fy1 - fy0)
    xt = np.where(fin, xt_f, xt); yt = np.where(fin, yt_f, yt)
    # THE WING, which lies across the fuselage in a side view and is not
    # fuselage: its own polygon on the blank, painted from the texture's
    # port upper wing (chord runs down the sheet there, root at the right),
    # so the splinter pattern is the skin's own and not one flat colour.
    wm = Image.new('L', (W, H), 0)
    ImageDraw.Draw(wm).polygon([(478, 642), (545, 546), (612, 534), (760, 560), (905, 626), (962, 650),
                                (900, 657), (705, 682), (690, 662), (520, 662)], fill=255)
    wing = skin & (np.asarray(wm) > 0)
    body &= ~wing
    uu = np.clip((XX - 478) / (962 - 478), 0, 1); ss = np.clip((YY - 534) / (682 - 534), 0, 1)
    xt = np.where(wing, 470 - ss * 170, xt); yt = np.where(wing, 452 + uu * (634 - 452), yt)
    # the spinner: the texture's own spinner island, top left of the sheet,
    # as one colour (its median, sheet background and the dark hub left out)
    sp = T[12:90, 30:118].reshape(-1, 3)
    keep = (np.abs(sp - bgc).sum(axis=1) > 60) & (sp.mean(axis=1) > 60)
    spinc = np.median(sp[keep], axis=0) if keep.sum() > 50 else np.array([150., 150., 150.])
    spinner = skin & (XX < X_NOSE) & (YY > 468) & (YY < 610)     # the cone only: the blade roots above and below it stay as drawn
    # anything else painted but outside all of these (tailplane, fairings): the upper wing's colour
    rest = skin & ~body & ~fin & ~wing & (XX >= X_NOSE)
    wingc = np.median(T[470:600, 80:380].reshape(-1, 3), axis=0)

    xi = np.clip(xt, 0, 1023).astype(int); yi = np.clip(yt, 0, 1023).astype(int)
    col = T[yi, xi]
    # a sample that landed on the sheet's olive background is not paint:
    # give it the fuselage side's own colour instead
    sidec = np.median(T[110:170, 300:600].reshape(-1, 3), axis=0)
    # ONLY in the fin island's box, which is the one mapping that takes in
    # sheet background. On the body the spine's dark green is close to the
    # sheet's olive, and treating it as background ate the camouflage.
    onbg = fin & (np.abs(col - bgc).sum(axis=2) < 60)
    col[onbg] = sidec
    out = B.copy()
    m = body | fin | wing
    out[m] = np.clip(col[m] * shade[m], 0, 255)
    out[rest] = np.clip(wingc * shade[rest], 0, 255)
    out[spinner] = np.clip(spinc * shade[spinner], 0, 255)
    alpha = (fg * 255).astype(np.uint8)
    rgba = np.dstack([out.astype(np.uint8), alpha])
    im = Image.fromarray(rgba)
    # to the Room's frame: 1000x295, spinner tip at x 2, fin top at y 5
    s = 993.0 / (1844 - 51)
    im = im.crop((51, 250, 1845, 781)).resize((int((1845 - 51) * s), int((781 - 250) * s)), Image.LANCZOS)
    canvas = Image.new('RGBA', (1000, 295), (0, 0, 0, 0)); canvas.paste(im, (2, 1), im)
    canvas.save(a.out)
    return True


def main():
    import json, types
    ap = argparse.ArgumentParser()
    ap.add_argument('--skin'); ap.add_argument('--out')
    ap.add_argument('--all', action='store_true', help='every skin in skins109.json, into --outdir under its side view file name')
    ap.add_argument('--outdir', default=os.path.join(ROOT, 'squadronroom/lw/aircraft'))
    ap.add_argument('--blank', default=os.path.join(ROOT, 'dev/art/bf109e_blank.jpg'))
    a = ap.parse_args()
    if not a.all:
        print('ok' if build(a) else 'no texture for ' + str(a.skin)); return
    rules = json.load(open(os.path.join(ROOT, 'squadronroom/lw/skins109.json'), encoding='utf-8-sig'))['rules']
    os.makedirs(a.outdir, exist_ok=True)
    done, missing = 0, []
    for skin, fname in sorted({(r['skin'], r.get('file')) for r in rules if r.get('file')}):
        b = types.SimpleNamespace(skin=skin, out=os.path.join(a.outdir, fname), blank=a.blank)
        if build(b): done += 1
        else: missing.append(skin)
    print('%d side views painted into %s; no texture for %d: %s' % (done, a.outdir, len(missing), missing[:6]))

if __name__ == '__main__':
    main()
