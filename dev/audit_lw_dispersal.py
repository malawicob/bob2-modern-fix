#!/usr/bin/env python3
"""Measure the Luftwaffe dispersal rather than look at it.

    python3 dev/audit_lw_dispersal.py

dev/audit_markings.py exists because three faults in the aircraft
markings were invisible from a screenshot and one of them was wrong on
20 of 41 profiles without anything saying so. Scenery is worse: a tent
sitting on a runway is invisible from every screenshot except the one
taken from the cockpit of the aeroplane that hit it.

So everything here is a number. Exit code is 1 if anything failed, so it
can gate a release.

THE CHECK THAT MATTERS is distance from the runway markers. The game
ships FIX_ObjectAdds=ON specifically because objects at certain
airfields caused "collisions and explosion problems on take-off and
landing", and that is the fault this feature could reintroduce forty
times over.

The threshold is not invented. Across the six German fields the BDG
dressed by hand, the closest any of them puts an object to a runway
marker is 165 m, at Wissant. That is the floor used here, and it is a
floor rather than a target: the generator searches for the bearing that
maximises the distance, so the fields it writes clear it several times
over. Everything below this check is hygiene.
"""
import re, os, sys, math, json

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = '/mnt/d/Battle of Britain II_Latest_test'

U = 90.0
MIN_CLEAR = 165       # metres from any runway marker; the least the BDG's own fields keep
FIELD_RADIUS = 1500   # metres from the field reference point
CEILING = 24
FLOOR = 14
CLASH = 25            # metres; closer than this to a stock object is a stack

fails, warns = [], []
def fail(m): fails.append(m); print('  FAIL  %s' % m)
def warn(m): warns.append(m); print('  warn  %s' % m)


def read_objectadds(path):
    out = []
    for ln in open(path, encoding='latin-1', errors='ignore'):
        if 'OBJECT_ADD' not in ln:
            continue
        p = ln.split()
        if len(p) < 2:
            continue
        f = p[1].split(',')
        if len(f) < 4:
            continue
        try:
            out.append((int(f[0]), int(f[1]), float(f[2]), int(f[3])))
        except ValueError:
            continue
    return out


def main():
    man_path = os.path.join(ROOT, 'dispersal/lw-airfields.json')
    txt_path = os.path.join(ROOT, 'dispersal/LW_Airfields.txt')
    for p in (man_path, txt_path):
        if not os.path.exists(p):
            print('missing %s; run dev/build_lw_dispersal.py first' % p, file=sys.stderr)
            return 1
    man = json.load(open(man_path, encoding='utf-8'))

    # ---- the payload parses the way the exe parses it -----------------
    print('THE FORMAT')
    raw = open(txt_path, encoding='ascii', errors='replace').read()
    n_lines = 0
    for ln in raw.splitlines():
        s = ln.strip()
        if not s or s.startswith('#'):
            continue
        m = re.match(r'^OBJECT_ADD (\d+),(\d+),(-?\d+(?:\.\d+)?),(\d+)(?: #.*)?$', s)
        if not m:
            fail('a line the exe would reject: %r' % s[:70])
            continue
        n_lines += 1
    print('  %d object lines, all matching "%%lu,%%lu,%%f,%%lu"' % n_lines)
    total = sum(len(f['objects']) for f in man['fields'])
    if n_lines != total:
        fail('the file has %d objects, the manifest says %d' % (n_lines, total))
    m = re.search(r'# (\d+) fields, (\d+) objects', raw)
    if not m:
        fail('the header does not state its own counts')
    elif int(m.group(1)) != len(man['fields']) or int(m.group(2)) != total:
        fail('the header says %s fields / %s objects, the file has %d / %d'
             % (m.group(1), m.group(2), len(man['fields']), total))

    # ---- distance from the runway markers, which is the point --------
    print('THE RUNWAY')
    worst = (1e9, None, None)
    for f in man['fields']:
        markers = f.get('markers') or []
        if not markers:
            fail('%s: the manifest records no runway markers to have cleared' % f['field'])
            continue
        for o in f['objects']:
            d = min(math.hypot(o['x'] - m['x'], o['z'] - m['z']) / U for m in markers)
            if d < MIN_CLEAR:
                fail('%s: shape %d is %.0f m from a runway marker, inside the %d m floor'
                     % (f['field'], o['id'], d, MIN_CLEAR))
            if d < worst[0]:
                worst = (d, f['field'], o['id'])
        if abs(f.get('clearance', -1) - min(
                min(math.hypot(o['x'] - m['x'], o['z'] - m['z']) / U for m in markers)
                for o in f['objects'])) > 1.0:
            fail('%s: the manifest claims %s m of clearance and does not have it'
                 % (f['field'], f.get('clearance')))
    print('  closest object to any runway marker: %.0f m, at %s (floor is %d m)'
          % (worst[0], worst[1], MIN_CLEAR))

    # ---- the parts exist ---------------------------------------------
    print('THE PARTS')
    cat = {}
    cat_path = os.path.join(GAME, 'Docs/List_From_Bin_catalog.txt')
    for ln in open(cat_path, encoding='latin-1'):
        mm = re.match(r'\s*(\d+)\s+(\S+)', ln)
        if mm:
            cat[int(mm.group(1))] = re.sub(r'\.bin$', '', mm.group(2), flags=re.I)
    have = set()
    for d in ('SHPBIN', 'ShpBin2', 'GRPBIN'):
        p = os.path.join(GAME, d)
        if os.path.isdir(p):
            for fn in os.listdir(p):
                have.add(os.path.splitext(fn)[0].lower())
    used = sorted({o['id'] for f in man['fields'] for o in f['objects']})
    for sid in used:
        if sid not in cat:
            fail('shape %d is not in List_From_Bin_catalog.txt' % sid)
        elif cat[sid].lower() not in have:
            fail('shape %d (%s) has no .bin on disk' % (sid, cat[sid]))
    print('  %d distinct shapes, every one catalogued and present as a .bin' % len(used))

    # ---- coverage and size -------------------------------------------
    print('THE COVERAGE')
    oob = json.load(open(os.path.join(ROOT, 'squadronroom/lw/oob.json'), encoding='utf-8'))
    want = set(r['field'] for r in oob)
    got = set(f['field'] for f in man['fields'])
    oa_dir = os.path.join(GAME, 'ObjectAdds')
    dressed = []
    for fn in sorted(os.listdir(oa_dir)):
        if fn.lower().endswith('.txt') and fn != 'LW_Airfields.txt':
            dressed += [(x, z) for x, z, _, _ in read_objectadds(os.path.join(oa_dir, fn))]
    missing = []
    for name in sorted(want - got):
        missing.append(name)
    if missing:
        print('  %d fields not dressed here (already carrying stock scenery): %s'
              % (len(missing), ', '.join(missing)))
    for f in man['fields']:
        n = len(f['objects'])
        if n > CEILING:
            fail('%s has %d objects, over the ceiling of %d' % (f['field'], n, CEILING))
        elif n < FLOOR:
            warn('%s has only %d objects' % (f['field'], n))
    print('  %d fields, %d objects, %.1f a field' % (len(man['fields']), total, total / len(man['fields'])))

    # ---- nothing stacked on the BDG's work ---------------------------
    print('THE NEIGHBOURS')
    r = CLASH * U
    clashes = 0
    for f in man['fields']:
        near = [(x, z) for x, z in dressed
                if abs(x - f['x']) < 3000 * U and abs(z - f['z']) < 3000 * U]
        for o in f['objects']:
            for x, z in near:
                if abs(o['x'] - x) < r and abs(o['z'] - z) < r:
                    clashes += 1
                    fail('%s: shape %d lands within %d m of a stock object'
                         % (f['field'], o['id'], CLASH))
                    break
    if not clashes:
        print('  no object within %d m of anything already in ObjectAdds' % CLASH)

    # ---- inside its own field ----------------------------------------
    print('THE FOOTPRINT')
    far = 0
    for f in man['fields']:
        for o in f['objects']:
            d = math.hypot(o['x'] - f['x'], o['z'] - f['z']) / U
            if d > FIELD_RADIUS:
                far += 1
                fail('%s: shape %d is %.0f m from the field' % (f['field'], o['id'], d))
            if o['x'] < 0 or o['z'] < 0:
                fail('%s: a negative coordinate, which the exe reads as unsigned' % f['field'])
    if not far:
        print('  every object within %d m of its own field' % FIELD_RADIUS)

    print('')
    if fails:
        print('%d FAILURE(S), %d warning(s)' % (len(fails), len(warns)))
        return 1
    print('ALL CHECKS PASSED (%d warning(s))' % len(warns))
    return 0


if __name__ == '__main__':
    sys.exit(main())
