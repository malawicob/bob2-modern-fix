#!/usr/bin/env python3
"""Convert Patrick's German pilot headshots into the Room's portrait set.

    python3 dev/make_lw_portraits.py \
        --src /home/patrick_millin/bob2/luftwaffe_pilot_portraits_1940 \
        --out squadronroom/lw/portraits

The Room shows portraits at 280 x 420, which is 2:3, and the RAF set is
the same. Patrick's images arrive at 1152 x 1728, already 2:3, so nothing
has to be cropped; the crop runs anyway rather than scaling to fit,
because squashing a face is worse than losing a few pixels at an edge.

DUPLICATES

Patrick said there may be duplicates and to remove them, and there are.
None are byte-identical: they are the same photograph saved more than
once, so the pixels differ slightly and a checksum finds nothing. Two
hashes are used together and a file has to look like an earlier one on
both before it is dropped:

    average hash    is the picture light or dark in the same places
    difference hash does the brightness run the same way across it

Each is computed on a 12 x 12 grey thumbnail, so both are blind to size,
compression and small tonal differences and neither is blind to a
different face. The thresholds are deliberately loose, because the cost
of dropping one portrait of ninety-odd is nothing and the cost of
shipping the same man twice is that a squadron has two identical faces
in it.

Every group the script drops is written to a contact sheet next to the
output, so the judgement can be looked at rather than trusted. On the
batch of 9 September 2026 it found two groups: one man photographed
twice in a flying helmet, and one photographed five times.

The output is renamed pilot01.jpg upward and portraits.json beside the
folder is rewritten to match, exactly as the RAF set does. Get-Portraits
reads whichever of the two the current side points at.
"""
import argparse, glob, json, os, sys
from PIL import Image

W, H = 280, 420
AH_MAX, DH_MAX = 8, 18          # how alike counts as the same photograph


def ahash(im, n=12):
    g = im.convert('L').resize((n, n), Image.LANCZOS)
    d = list(g.getdata())
    a = sum(d) / float(len(d))
    return ''.join('1' if v > a else '0' for v in d)


def dhash(im, n=12):
    g = im.convert('L').resize((n + 1, n), Image.LANCZOS)
    px = g.load()
    return ''.join('1' if px[x, y] > px[x + 1, y] else '0'
                   for y in range(n) for x in range(n))


def apart(a, b):
    return sum(1 for x, y in zip(a, b) if x != y)


def crop(im):
    w, h = im.size
    want = W / float(H)
    have = w / float(h)
    if have > want:                      # too wide: take the middle
        nw = int(round(h * want))
        im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    elif have < want:                    # too tall: keep the head, drop the feet
        nh = int(round(w / want))
        top = int((h - nh) * 0.25)
        im = im.crop((0, top, w, top + nh))
    return im.resize((W, H), Image.LANCZOS)


def sheet(groups, path):
    """A picture of every group that was collapsed, so the call can be seen."""
    rows = []
    for g in groups:
        tiles = []
        for f in g:
            t = Image.open(f); t.thumbnail((160, 240), Image.LANCZOS)
            tiles.append(t)
        w = sum(t.size[0] + 6 for t in tiles)
        h = max(t.size[1] for t in tiles)
        row = Image.new('RGB', (w, h), (20, 20, 20))
        x = 0
        for t in tiles:
            row.paste(t, (x, 0)); x += t.size[0] + 6
        rows.append(row)
    if not rows:
        return None
    sw = max(r.size[0] for r in rows)
    sh = sum(r.size[1] + 8 for r in rows)
    out = Image.new('RGB', (sw, sh), (20, 20, 20))
    y = 0
    for r in rows:
        out.paste(r, (0, y)); y += r.size[1] + 8
    out.save(path)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default='/home/patrick_millin/bob2/luftwaffe_pilot_portraits_1940')
    ap.add_argument('--out', default='squadronroom/lw/portraits')
    ap.add_argument('--json', default='squadronroom/lw/portraits.json')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    # Windows writes a Zone.Identifier stream beside every downloaded file
    # and it turns up here as its own entry. It is not a picture.
    src = [f for f in sorted(glob.glob(os.path.join(a.src, '*.jpg')))
           if 'Zone.Identifier' not in f]
    if not src:
        print('nothing to convert in %s' % a.src, file=sys.stderr)
        return 2
    print('%d files found' % len(src))

    kept, dropped = [], []
    sigs = {}
    for f in src:
        try:
            im = Image.open(f)
            s = (ahash(im), dhash(im))
        except Exception as e:
            print('  ! %s unreadable: %s' % (os.path.basename(f), e), file=sys.stderr)
            continue
        same = None
        for k in kept:
            if apart(s[0], sigs[k][0]) <= AH_MAX and apart(s[1], sigs[k][1]) <= DH_MAX:
                same = k; break
        if same:
            dropped.append((same, f))
        else:
            kept.append(f); sigs[f] = s

    groups = {}
    for k, f in dropped:
        groups.setdefault(k, [k]).append(f)
    print('%d duplicates removed in %d group(s); %d portraits kept'
          % (len(dropped), len(groups), len(kept)))
    for g in groups.values():
        print('    ' + ' = '.join(os.path.basename(x)[:12] for x in g))

    if a.dry_run:
        return 0

    os.makedirs(a.out, exist_ok=True)
    for old in glob.glob(os.path.join(a.out, 'pilot*.jpg')):
        os.remove(old)
    names = []
    for i, f in enumerate(kept, 1):
        name = 'pilot%02d.jpg' % i
        crop(Image.open(f).convert('RGB')).save(os.path.join(a.out, name),
                                                quality=88, optimize=True)
        names.append(name)
    with open(a.json, 'w', encoding='utf-8') as fh:
        json.dump(names, fh, indent=0)
        fh.write('\n')

    p = sheet(list(groups.values()), os.path.join(a.out, '..', 'portraits-dropped.png'))
    if p:
        print('the groups that were collapsed: %s' % os.path.normpath(p))
    kb = sum(os.path.getsize(os.path.join(a.out, n)) for n in names) // 1024
    print('%d portraits at %dx%d -> %s  (%d KB in total)' % (len(names), W, H, a.out, kb))
    return 0


if __name__ == '__main__':
    sys.exit(main())
