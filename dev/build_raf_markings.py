#!/usr/bin/env python3
"""Take the RAF code letters out of the game's own skin tiles.

    python3 dev/build_raf_markings.py --out squadronroom/aircraft/markings

The Room has always painted the squadron code, the individual letter and
the serial onto the Spitfire as TEXT, in whatever condensed font the
machine happened to have. The game does not do that. It has a tile per
letter and a tile per squadron code, in RAF Sky grey, in the right
typeface, and MultiSkin places them by exact pixel:

    Spit_Squadron_Code.ms   0.11 x 0.055 at (1100, 768)
    Spit_PlaneID_Letter.ms  0.055 x 0.055 at (1445, 753)

Every one of the 51 codes the Room uses has a tile, and so do all 26
letters, so nothing has to fall back to a font.

The canvas is KEPT, exactly as for the German markings: MultiSkin places
the whole 128 or 256 wide tile and the glyph sits wherever it sits
inside it. Trim the padding and every letter lands somewhere slightly
different.

The serial is NOT here. There is no tile for it, because in the game it
is part of the painted skin rather than a decal, so it stays as drawn
text in the Room.
"""
import argparse, json, os, re, shutil, sys
from PIL import Image


def codes_from_room(path):
    """The squadron codes the Room actually uses, read from its own table
    rather than kept as a second list here that could drift out of step."""
    src = open(path, encoding='utf-8-sig').read()
    m = re.search(r'\$SquadronCodes\s*=\s*@\{(.*?)\n\}', src, re.S)
    if not m:
        return []
    return sorted(set(re.findall(r"=\s*'([A-Z]{2})'", m.group(1))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default='/mnt/d/BOB2 Files/skin-previews')
    ap.add_argument('--room', default='BOB2_SquadronRoom.ps1')
    ap.add_argument('--out', default='squadronroom/aircraft/markings')
    ap.add_argument('--json', default='squadronroom/aircraft/markings.json')
    a = ap.parse_args()

    idx = {f.lower(): f for f in os.listdir(a.src) if f.lower().endswith('.png')}
    if os.path.isdir(a.out):
        shutil.rmtree(a.out)
    os.makedirs(os.path.join(a.out, 'letters'), exist_ok=True)
    os.makedirs(os.path.join(a.out, 'codes'), exist_ok=True)

    made = {'letters': {}, 'codes': {}}
    missing = []
    for L in [chr(c) for c in range(65, 91)]:
        f = idx.get(L.lower() + '.png')
        if not f:
            missing.append('letter ' + L); continue
        name = 'letters/%s.png' % L
        Image.open(os.path.join(a.src, f)).convert('RGBA').save(os.path.join(a.out, name))
        made['letters'][L] = name

    for code in codes_from_room(a.room):
        f = idx.get(code.lower() + '.png')
        if not f:
            missing.append('code ' + code); continue
        name = 'codes/%s.png' % code
        Image.open(os.path.join(a.src, f)).convert('RGBA').save(os.path.join(a.out, name))
        made['codes'][code] = name

    with open(a.json, 'w', encoding='utf-8') as fh:
        json.dump({'note': ("RAF code letters from the game's own skin tiles. "
                            "Canvas kept, because MultiSkin places the whole "
                            "tile. Built by dev/build_raf_markings.py."),
                   'letters': made['letters'], 'codes': made['codes']}, fh,
                  indent=1, ensure_ascii=False)
        fh.write('\n')
    print('%d letters and %d squadron codes -> %s'
          % (len(made['letters']), len(made['codes']), a.out))
    if missing:
        print('  not found: %s' % ', '.join(missing), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
