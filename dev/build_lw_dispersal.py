#!/usr/bin/env python3
"""Dress the Luftwaffe airfields from the game's own tested placements.

    python3 dev/build_lw_dispersal.py --out dispersal/LW_Airfields.txt

Forty of the forty six fields in the German order of battle carry no
scenery at all. The RAF side has had the Living dispersal at five fields
since ce4acfc; this is the same idea for the other air force, and it is
built the same way: nothing here is invented, every object is lifted
from a field the BDG dressed by hand and shipped, so the layouts have
flown for twenty years before they get copied anywhere.

WHERE A KIT IS ALLOWED TO STAND

Every German field carries RunwaySBAND markers, and the obvious reading
is that they are points along a strip, so that fitting a line to them
gives a runway to keep clear of. That reading does not survive contact
with the data. At Abbeville the three markers sit at bearings of 94, 141
and 191 degrees from the reference point at much the same distance, so
they are three places around the field and not three points on a line.
Villacoublay's four give pairwise bearings of 13, 15, 18, 99, 131 and
153. A fitted centreline is an inference on top of an inference, and
being wrong about it is exactly the fault FIX_ObjectAdds exists for.

So the rule is taken from what already flies instead. Measured across
the fields the BDG dressed by hand, every one of them keeps its kit at
least 165 m from the nearest runway marker:

    Abbeville 239 m   Cocquelles 345 m   Peuplingues 427 m
    Marck     171 m   Wissant    165 m

Nothing else about them is consistent. The angle between the kit and the
nearest marker runs from 2 degrees at Abbeville to 63 at Peuplingues, and
Wissant has an object a metre off the line from a marker to the field
centre, so neither bearing nor that line is what the authors were
respecting. Distance from the markers is.

A kit is therefore planted at the bearing, around its target field, that
puts it FURTHEST from every one of that field's markers, at the radius
its exemplar used. The result is checked, not assumed, and a field where
nothing clears 165 m is refused rather than dressed.

THE EXEMPLARS

One per airfield Shape, filtered to the German airfield kit so that
Wissant contributes its aerodrome and not the village of Wissant, which
is 285 of its objects and includes the church.

    GLFTTNT2  Cocquelles   23 objects   axis  61.3
    GLFTTNT1  Wissant      81 objects   axis  16.5
    GLFTFUL2  Abbeville    32 objects   axis  58.5
    GLFTFUL1  Marck        56 objects   axis  91.4
    EMPTY     Abbeville, substituted, and the reason is below.

Le Havre is the natural EMPTY exemplar and cannot be used. Its three
RunwaySBAND markers sit on the same point as its reference, so it has no
derivable axis, so its kit cannot be resolved into runway coordinates at
all. An exemplar that has to be oriented by guesswork is worse than a
well oriented substitute, so EMPTY fields take Abbeville. Le Havre is
already dressed, so it is not a target and nothing is lost.

Every one of the 40 target fields does have a usable axis. That was
checked before this was written, not assumed.

THE CEILING, WHICH IS THE POINT

Ground object count is the dominant CPU load in this engine. It is the
single biggest frame rate cost, it is what took this project's own
measurement from 28 to 76 FPS, and the tool tells the player so in three
different places. Handing that back as scenery would be absurd.

So: no scatter trees, which are half to two thirds of the BDG's German
files and the expensive part; a hard ceiling of 24 objects a field; and
a number measured before and after rather than an assurance. The RAF
Living dispersal is 16 objects a field and says "Static only" at the top
of every block. This stays in that spirit.
"""
import re, os, sys, math, json, random, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

U = 90.0                 # game units per metre, as make_dispersal.py had it
CEILING = 24             # hard cap on objects per field
FIELD_RADIUS = 1500      # metres from the reference point; beyond this is landscape
KIT_RADIUS = 400         # metres from the kit's own centroid; beyond this is an outlier
MARKER_RADIUS = 3000     # metres; a RunwayS marker further out belongs to another field
MIN_CLEAR = 165          # metres from any runway marker; the least the BDG's own fields keep
JITTER = 15              # metres, vehicles and figures only

MARKER = '# Luftwaffe dispersal'

# The German airfield kit, from Docs/List_From_Bin_catalog.txt. SHAPENUM.G
# is no help: it stops at 393, so the whole of 400-450 is absent from it
# and the catalogue is the only authority for these ids.
KIT = set([324, 347, 503]) | set(range(411, 444))

# Objects that may be nudged. A tent, a revetment, a hangar or a barn is
# built where it is built; a lorry is parked where it happens to be.
MOVEABLE = set(range(411, 428)) | {442, 443, 347}

# Ground crew. Every field gets some, because they are what makes a field
# look inhabited rather than merely built on.
CREW = (442, 443)

# What is based at a field changes what is standing about on it. These
# swap shape ids in place, never positions, so the geometry that was
# proved at the exemplar is never disturbed.
BOMBER_KIT   = [424, 411, 412, 426]   # fuel bowser, lorries, half track
FIGHTER_KIT  = [418, 417, 423, 411]   # Kuebelwagen, staff car, lorry

# Per shape id caps applied when an exemplar is trimmed to the ceiling.
# Marck's 21 tents and Wissant's 25 are a whole camp; a handful reads the
# same from a cockpit at a tenth of the cost.
CAPS = {440: 6, 439: 5, 324: 4, 435: 3, 433: 2, 434: 1, 411: 2, 412: 2}

# game spelling -> the world file's UID, and why it differs
ALIASES = {
    'Antwerp':        ('AntwerpDeurne', 'the world file names the aerodrome, not the city'),
    'Dinnard':        ('Dinard',        'one N'),
    'Le Havre':       ('LeHarve',       "the world file's own misspelling; it is the key, so it stays"),
    'Marck (Calais)': ('Marck',         'the OOB names the town beside it'),
}

EXEMPLARS = {
    'GLFTTNT2': ('Cocquelles', 'FRANCE_Coquelles.txt'),
    'GLFTTNT1': ('Wissant',    'FRANCE_Wissant_few.txt'),
    'GLFTFUL2': ('Abbeville',  'FRANCE_Abbeville.txt'),
    'GLFTFUL1': ('Marck',      'FRANCE_Marck.txt'),
    'EMPTY':    ('Abbeville',  'FRANCE_Abbeville.txt'),
}


def norm(s):
    return re.sub(r'[^a-z]', '', s.lower())


def read_world(path):
    """Reference point, Shape and runway markers for all 56 German fields."""
    txt = open(path, encoding='latin-1').read()
    ref = {}
    for b in re.split(r'SimpleItem\s+\w+=', txt):
        m = re.search(r'SetUID\s+UID_AF_(\w+)', b)
        if not m:
            continue
        band = re.search(r'UIDBand\s+(\w+)', b)
        if not band or not band.group(1).startswith('LUF'):
            continue
        x = re.search(r'X\s+(-?\d+)', b)
        z = re.search(r'Z\s*(?:\{Select\s+)?(-?\d+)', b)
        shp = re.search(r'Shape\s+(\w+)', b)
        if not (x and z):
            continue
        ref[m.group(1)] = {'x': int(x.group(1)), 'z': int(z.group(1)),
                           'shape': shp.group(1) if shp else 'EMPTY'}
    for chunk in re.split(r'\{\s*Target\s+UID_AF_', txt)[1:]:
        nm = re.match(r'(\w+)', chunk).group(1)
        if nm not in ref:
            continue
        fx, fz = ref[nm]['x'], ref[nm]['z']
        pts = []
        for si in re.split(r'SimpleItem\s+\w+=', chunk):
            if 'RunwaySBAND' not in si:
                continue
            x = re.search(r'X\s+(-?\d+)', si)
            z = re.search(r'Z\s*(?:\{Select\s+)?(-?\d+)', si)
            if not (x and z):
                continue
            p = (int(x.group(1)), int(z.group(1)))
            # Caffiers carries a fourth marker 11,951 m away that belongs
            # to Cocquelles, which is why Cocquelles has only two.
            if math.hypot(p[0] - fx, p[1] - fz) / U < MARKER_RADIUS:
                pts.append(p)
        ref[nm]['runway'] = pts
    for v in ref.values():
        v.setdefault('runway', [])
    return ref


def clearance(pts, markers):
    """Metres from the nearest runway marker to the nearest object."""
    if not markers:
        return None
    return min(math.hypot(x - m[0], z - m[1]) / U for x, z in pts for m in markers)


def best_bearing(kit, fld, markers):
    """The bearing that puts this kit furthest from every marker.

    A whole turn at one degree, which is 360 cheap evaluations and needs
    no assumption about what the markers mean beyond "aeroplanes go
    there". Ties break toward the exemplar's own bearing so a field with
    no markers worth avoiding still looks like the field it came from.
    """
    r = math.hypot(fld['kit_dx'], fld['kit_dz'])
    best, best_at = None, 0.0
    for deg in range(0, 360):
        th = math.radians(deg)
        cx, cz = fld['x'] + r * math.cos(th), fld['z'] + r * math.sin(th)
        pts = [(cx + k['dx'] * U, cz + k['dz'] * U) for k in kit]
        c = clearance(pts, markers)
        if c is None:
            return 0.0
        if best is None or c > best:
            best, best_at = c, th
    return best_at


def read_objectadds(path):
    out = []
    for ln in open(path, encoding='latin-1', errors='ignore'):
        if 'OBJECT_ADD' not in ln:
            continue
        parts = ln.split()
        if len(parts) < 2:
            continue
        f = parts[1].split(',')
        if len(f) < 4:
            continue
        try:
            out.append((int(f[0]), int(f[1]), float(f[2]), int(f[3])))
        except ValueError:
            continue
    return out


def lift(ref, name, oa_path):
    """An exemplar's kit, in metres from its own centroid.

    The kit is NOT rotated. An airfield item in MAINWLD.BFI carries a
    position, a band, a UID and a Shape and nothing else, verified across
    all 56, so the ground model is planted the same way up at every field
    that shares a Shape. What moves is where the kit sits around the
    field, not which way it faces.

    The radius that decides an outlier is measured from the kit's own
    centroid, not from the field's reference point. A dispersal sits at
    the edge of an aerodrome, not in the middle of it: Cocquelles' is
    700 m down the field from its reference. Measuring from the centre
    would throw the whole thing away.
    """
    fld = ref[name]
    kit = []
    for x, z, hdg, sid in read_objectadds(oa_path):
        if sid not in KIT:
            continue
        dx, dz = (x - fld['x']) / U, (z - fld['z']) / U
        if math.hypot(dx, dz) > FIELD_RADIUS:
            continue
        kit.append({'dx': dx, 'dz': dz, 'hdg': hdg % 360.0, 'id': sid})
    if not kit:
        raise SystemExit('%s contributed no kit at all' % name)
    cx = sorted(k['dx'] for k in kit)[len(kit) // 2]
    cz = sorted(k['dz'] for k in kit)[len(kit) // 2]
    out = [k for k in kit if math.hypot(k['dx'] - cx, k['dz'] - cz) <= KIT_RADIUS]
    for k in out:
        k['dx'] -= cx
        k['dz'] -= cz
    return out, math.hypot(cx, cz)


def trim(kit, name):
    """Down to the ceiling, keeping one of everything and the tight groups."""
    if len(kit) <= CEILING:
        return list(kit)
    order = sorted(kit, key=lambda k: math.hypot(k['dx'], k['dz']))
    seen, out = {}, []
    for k in order:                      # one of every distinct type first
        if k['id'] not in seen:
            seen[k['id']] = 1
            out.append(k)
    for k in order:                      # then fill up to the per id caps
        if len(out) >= CEILING:
            break
        if k in out:
            continue
        cap = CAPS.get(k['id'], 2)
        if seen.get(k['id'], 0) < cap:
            seen[k['id']] = seen.get(k['id'], 0) + 1
            out.append(k)
    return out[:CEILING]


def dress(kit, types, rnd):
    """Give the field the character of what is based on it."""
    out = [dict(k) for k in kit]
    bomber = any(t.split()[0] in ('He', 'Ju', 'Do') for t in types)
    swaps = BOMBER_KIT if bomber else FIGHTER_KIT
    vehicles = [k for k in out if k['id'] in MOVEABLE and k['id'] not in CREW]
    rnd.shuffle(vehicles)
    for i, k in enumerate(vehicles[:len(swaps)]):
        k['id'] = swaps[i]
    for i, k in enumerate(vehicles[len(swaps):len(swaps) + 2]):
        k['id'] = CREW[i % len(CREW)]    # every field gets ground crew
    for k in out:
        if k['id'] in MOVEABLE:
            k['dx'] += rnd.uniform(-JITTER, JITTER)
            k['dz'] += rnd.uniform(-JITTER, JITTER)
    return out


def plant(kit, fld, bearing, radius):
    """The kit's centroid at that bearing and radius from the reference."""
    cx = fld['x'] + radius * U * math.cos(bearing)
    cz = fld['z'] + radius * U * math.sin(bearing)
    return [(int(round(cx + k['dx'] * U)), int(round(cz + k['dz'] * U)),
             round(k['hdg']) % 360, k['id']) for k in kit]


def catalogue(path):
    cat = {}
    for ln in open(path, encoding='latin-1'):
        m = re.match(r'\s*(\d+)\s+(\S+)', ln)
        if m:
            cat[int(m.group(1))] = re.sub(r'\.bin$', '', m.group(2), flags=re.I)
    return cat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', default='/mnt/d/Battle of Britain II_Latest_test')
    ap.add_argument('--oob',  default=os.path.join(ROOT, 'squadronroom/lw/oob.json'))
    ap.add_argument('--out',  default=os.path.join(ROOT, 'dispersal/LW_Airfields.txt'))
    ap.add_argument('--json', default=os.path.join(ROOT, 'dispersal/lw-airfields.json'))
    a = ap.parse_args()

    world = os.path.join(a.game, 'BFIELDS/MAINWLD.BFI')
    if not os.path.exists(world):
        print('no world file at %s' % world, file=sys.stderr)
        return 1
    ref = read_world(world)
    cat = catalogue(os.path.join(a.game, 'Docs/List_From_Bin_catalog.txt'))
    oa_dir = os.path.join(a.game, 'ObjectAdds')

    # What is already on the ground, so nothing is dressed twice. Our own
    # output is skipped by name: once it is installed the game folder
    # contains it, and counting it would make the second run decide every
    # field was already dressed and write an empty file over a good one.
    existing = []
    for fn in sorted(os.listdir(oa_dir)):
        if fn.lower().endswith('.txt') and fn != os.path.basename(a.out):
            existing += [(x, z) for x, z, _, _ in read_objectadds(os.path.join(oa_dir, fn))]

    templates = {}
    for shape, (nm, fn) in EXEMPLARS.items():
        kit, radius = lift(ref, nm, os.path.join(oa_dir, fn))
        templates[shape] = {'kit': trim(kit, nm), 'from': nm,
                            'radius': radius, 'raw': len(kit)}

    oob = json.load(open(a.oob, encoding='utf-8'))
    by_field = {}
    for r in oob:
        by_field.setdefault(r['field'], []).append(r['type'])

    wn = {norm(k): k for k in ref}
    blocks, manifest, skipped, problems, notes = [], [], [], [], []
    total = 0
    for field in sorted(by_field):
        alias = ALIASES.get(field)
        key = alias[0] if alias else wn.get(norm(field))
        if not key or key not in ref:
            problems.append('%s: no UID_AF_ entry in the world file' % field)
            continue
        fld = ref[key]
        near = sum(1 for x, z in existing
                   if abs(x - fld['x']) < 2000 * U and abs(z - fld['z']) < 2000 * U)
        if near >= 10:
            skipped.append((field, near))
            continue
        if not fld['runway']:
            problems.append('%s: no runway markers at all, so it is left alone' % field)
            continue
        tpl = templates.get(fld['shape']) or templates['EMPTY']
        rnd = random.Random('bob2-lw-field-' + key)
        kit = dress(tpl['kit'], by_field[field], rnd)
        fld['kit_dx'] = tpl['radius'] * U
        fld['kit_dz'] = 0.0
        bearing = best_bearing(kit, fld, fld['runway'])
        rows = plant(kit, fld, bearing, tpl['radius'])
        clear = clearance([(x, z) for x, z, _, _ in rows], fld['runway'])
        if clear is None or clear < MIN_CLEAR:
            problems.append('%s: the best bearing still leaves only %.0f m from a runway '
                            'marker, under the %d m the BDG\'s own fields keep, so it is '
                            'left alone' % (field, clear or 0, MIN_CLEAR))
            continue
        if any(x < 0 or z < 0 for x, z, _, _ in rows):
            problems.append('%s: a negative coordinate, which the exe reads as unsigned' % field)
            continue
        lines = ['%s - %s (BOB2 Modern Fix). Static only.' % (MARKER, field)]
        for x, z, hdg, sid in rows:
            lines.append('OBJECT_ADD %d,%d,%.6f,%d #%s' % (x, z, float(hdg), sid, cat.get(sid, '?')))
        blocks.append('\r\n'.join(lines))
        total += len(rows)
        manifest.append({'field': field, 'uid': key, 'shape': fld['shape'],
                         'exemplar': tpl['from'],
                         'bearing': round(math.degrees(bearing) % 360.0, 1),
                         'radius': round(tpl['radius']), 'clearance': round(clear),
                         'x': fld['x'], 'z': fld['z'],
                         'markers': [{'x': m[0], 'z': m[1]} for m in fld['runway']],
                         'objects': [{'x': x, 'z': z, 'hdg': round(h, 3), 'id': s}
                                     for x, z, h, s in rows]})

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    head = ('%s for the BOB2 Modern Fix.\r\n'
            '# %d fields, %d objects, static only, no scatter trees.\r\n'
            '# Lifted from the fields the BDG dressed by hand, and set down at the\r\n'
            '# bearing that keeps each one furthest from its own runway markers in\r\n'
            '# BFIELDS/MAINWLD.BFI. Written by dev/build_lw_dispersal.py; edit the\r\n'
            '# script, not this file.\r\n'
            '# Delete this file to remove every one of them.\r\n' % (MARKER, len(blocks), total))
    with open(a.out, 'w', encoding='ascii', newline='') as fh:
        fh.write(head + '\r\n' + '\r\n\r\n'.join(blocks) + '\r\n')
    with open(a.json, 'w', encoding='utf-8') as fh:
        json.dump({'fields': manifest,
                   'templates': {k: {'from': v['from'], 'radius': round(v['radius']),
                                     'raw': v['raw'], 'kept': len(v['kit'])}
                                 for k, v in templates.items()}},
                  fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    for shape, t in sorted(templates.items()):
        print('  %-9s from %-11s %2d of %3d objects kept, %3.0f m out from the reference'
              % (shape, t['from'], len(t['kit']), t['raw'], t['radius']))
    clears = sorted(f['clearance'] for f in manifest)
    print('%d fields dressed, %d objects -> %s' % (len(blocks), total, a.out))
    if clears:
        print('  clearance from the nearest runway marker: %d m at worst, %d m typical'
              % (clears[0], clears[len(clears) // 2]))
    if skipped:
        print('%d already dressed and left alone: %s'
              % (len(skipped), ', '.join('%s (%d)' % s for s in skipped)))
    for n in notes:
        print('  %s' % n)
    for p in problems:
        print('  ! %s' % p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
