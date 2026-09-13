#!/usr/bin/env python3
"""Put the Living dispersal on the other thirty RAF fields.

    python3 dev/build_raf_dispersal.py --out dispersal/RAF_Airfields.txt

WHAT IS THERE NOW

Five fields have it: Croydon, Biggin Hill, Debden, Kenley and Hornchurch,
sixteen objects each, hand-extracted from tested files in ce4acfc and
appended to their own ObjectAdds file behind a marker line. The other
thirty nine RAF fields get nothing from us, and thirteen of them have
nothing at all: under ten objects within 2 km, twelve of them with none.
Seventeen of the AF*.BF battlefield files are the same 33-byte stubs the
German fields have.

WHAT THIS ADDS, AND WHERE IT STOPS

Thirty fields: the twenty six that already carry scenery but no
dispersal, and the four bare fighter stations that have runway geometry -
Coltishall, Wittering, Digby and Kirton, all four at zero objects and all
four places a player can be posted to.

Nine bare fields are deliberately left alone: Hendon, Pembrey, Newcastle,
Andover, Odiham, Boscombe Down, Brize Norton, Worthy Down and Detling
have neither runway markers nor the Bearing/Range form, so there is no
way to know where their runways are. Placing blind is how objects end up
on a strip, which is the fault FIX_ObjectAdds exists for.

THE RUNWAY DATA HERE IS BETTER THAN THE GERMAN SIDE EVER HAD

Fourteen RAF fields carry a real centreline in MAINWLD.BFI, two absolute
points with an offset either side:

    Intercept { Posn Abs {37095380,48020799}, Posn Abs {37142440,48071886} }
    Bearing ANGLES_270Deg,  Range METRES180

So Coltishall's runway is a known 772 m strip on a known axis, 180 m
either side, and clearance is a distance to a line segment rather than to
a cloud of markers. Where no centreline exists, the field's existing
scenery is the guide instead: whatever the BDG put there is where it is
safe to be near.

WHERE THE KIT COMES FROM, AND HOW FAR OUT IT SITS

Both are measured off the five that already work rather than chosen. All
five carry the same sixteen objects, and all five sit between 288 and
308 m from their field's reference point, clearing the runway by 120 m at
Kenley, 200 at Hornchurch and 231 at Croydon. So: 300 m out, and never
closer to a runway than Kenley already is.
"""
import argparse, json, math, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

U = 90.0
RADIUS = 300             # metres from the reference, as the five sit
MIN_RUNWAY = 120         # metres from a centreline; Kenley's own figure
CLASH = 30               # metres from anything already on the field
CEILING = 30

MARKER = '# Living dispersal'
DONE = {'CROYDON', 'BIGGINHILL', 'DEBDEN', 'KENLEY', 'HORNCHURCH'}

# The five payloads, and the field each belongs to.
SOURCES = {'Croydon': 'CROYDON', 'Biggin_Hill': 'BIGGINHILL', 'Debden': 'DEBDEN',
           'Kenley': 'KENLEY', 'Hornchurch': 'HORNCHURCH'}

# THE STATIC BLENHEIM, because it is the only British one that works.
#
# 25 SPIT, 44 HURR and 45 BRISTO are in the catalogue with models on disk
# and are placed by nobody, anywhere. Across the 295 shipped ObjectAdds
# files and the whole battlefield source, exactly two aircraft shapes are
# ever placed as ground objects: 21 JU52 and 187 GBRIST. Patrick flew to
# Caffiers, where a 109 had been parked on the same reasoning, and there
# were no aeroplanes on it.
#
# 187 is the one the game itself uses: M1ANDOVE.BFI and its siblings park
# static Blenheims at six RAF stations with it.
PARKED_FIGHTER = [187]
PARKED_BOMBER = [187]
PARK_SPACING = 55

# THE STATIONS NOBODY FLIES FROM, and why they are dressed anyway.
#
# Ten RAF fields have no runway geometry of any kind. Two of them,
# Hendon and Newcastle, carry Shape EMPTY in MAINWLD.BFI, have no B/C/D
# building groups and appear in no squadron's bases: there is no
# aerodrome there to dress, and they are left alone for good.
#
# The other eight are real bomber stations with a ground model and
# buildings, and none is in the RAF order of battle, so no player ever
# takes off from one. What they are is targets. Detling was bombed in
# August 1940 and it should look like an airfield when you bomb it.
#
# The game shows where the safe ground is. M1ANDOVE.BFI and its five
# siblings park static Blenheims using an idiom nothing else here uses:
#
#     Posn { Abs {UID_AF_ANDOVER}, Rel { Bearing ANGLES_35Deg,
#                                        Range METRES50 } }
#
# 50 to 150 m from the reference point at 35, 90, 135 or 225 degrees. You
# do not park a Blenheim on a runway, so that ground is apron, and the
# reference point is on the station. The dressing goes out a little
# further at a bearing clear of the aeroplanes already there.
BOMBER_STATIONS = {
    'ANDOVER':      [35, 135],
    'BOSCOMBEDOWN': [35, 90],
    'BRIZENORTON':  [35, 90, 135],
    'FORD':         [225],
    'ODIHAM':       [90, 135, 35],
    'WORTHYDOWN':   [35, 90, 135],
    'DETLING':      [],          # M1 file is a stub, so nothing is parked
    'SHOREHAM':     [],
}
NO_AERODROME = {'HENDON', 'NEWCASTLE'}
STATION_RADIUS = 240     # metres; the Blenheims sit at 50 to 150

# For a field whose AF*.BF is a 33-byte stub there are no buildings at
# all, so it gets some. Every one of these is in the catalogue with a
# model on disk and has never been placed.
STUB_KIT = [(444, 'atype'), (448, 'bellmn'), (80, 'WTOWER'), (453, 'GUARDH')]


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


def read_world(path):
    """RAF reference points, the band, and a runway centreline if there is one."""
    txt = open(path, encoding='latin-1').read()
    ref = {}
    for b in re.split(r'SimpleItem\s+\w+=', txt):
        m = re.search(r'SetUID\s+UID_AF_(\w+)', b)
        if not m:
            continue
        band = re.search(r'UIDBand\s+(\w+)', b)
        if not band or not band.group(1).startswith('RAF'):
            continue
        x = re.search(r'X\s+(-?\d+)', b)
        z = re.search(r'Z\s*(?:\{Select\s+)?(-?\d+)', b)
        if not (x and z):
            continue
        ref[m.group(1)] = {'x': int(x.group(1)), 'z': int(z.group(1)),
                           'kind': 'bomber' if 'Bomber' in band.group(1) else 'fighter',
                           'runway': None, 'runway_from': None}
    # THE RUNWAY, and there are two ways it is written down.
    #
    # The one found first was the Intercept form, two absolute points with
    # a Bearing and a Range either side, and fourteen RAF fields have it.
    # The other is plainer and far commoner: a RunwaySBAND marker at one
    # end and a RunwayEBAND marker at the other. Twenty nine RAF fields
    # have that pair, including twelve that were being placed on the
    # clash rule alone for want of any geometry, and including Pembrey,
    # the only one of the eleven left-out fields that a squadron in the
    # order of battle actually flies from.
    #
    # RunwayE is a dummy at most German fields, all parked on the same
    # point out in the North Sea, so it is checked against that and
    # discarded when it matches.
    DUMMY = (17248256, 44859392)
    for chunk in re.split(r'\{\s*Target\s+UID_AF_', txt)[1:]:
        nm = re.match(r'(\w+)', chunk).group(1)
        if nm not in ref:
            continue
        fx, fz = ref[nm]['x'], ref[nm]['z']
        starts, ends = [], []
        for si in re.split(r'SimpleItem\s*\w*=?', chunk):
            x = re.search(r'X\s+(-?\d+)', si)
            z = re.search(r'Z\s*(?:\{Select\s+)?(-?\d+)', si)
            if not (x and z):
                continue
            p = (int(x.group(1)), int(z.group(1)))
            if p == DUMMY or math.hypot(p[0] - fx, p[1] - fz) / U > 3000:
                continue
            if 'RunwaySBAND' in si:
                starts.append(p)
            elif 'RunwayEBAND' in si:
                ends.append(p)
        if starts and ends:
            ref[nm]['runway'] = (starts[0], ends[0])
            ref[nm]['runway_from'] = 'start and end markers'
            continue
        ic = re.findall(r'Intercept\s*\{\s*Posn\s*\{\s*Abs\s*\{\s*X\s+(-?\d+),'
                        r'\s*Z\s+(-?\d+)\s*\}\s*\}\s*,?\s*Posn\s*\{\s*Abs\s*\{\s*X\s+(-?\d+),'
                        r'\s*Z\s+(-?\d+)', chunk)
        if ic:
            a, b_, c, d = (int(v) for v in ic[0])
            ref[nm]['runway'] = ((a, b_), (c, d))
            ref[nm]['runway_from'] = 'intercept pair'
    return ref


def seg_dist(p, a, b):
    ax, az = a
    bx, bz = b
    px, pz = p
    dx, dz = bx - ax, bz - az
    L = dx * dx + dz * dz
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz)) / U


def lift(ref, sources_dir):
    """The sixteen objects, in metres from the kit's own centroid."""
    kits = []
    for stem, uid in sorted(SOURCES.items()):
        path = os.path.join(sources_dir, 'AF_%s.dispersal.txt' % stem)
        if not os.path.exists(path) or uid not in ref:
            continue
        fld = ref[uid]
        rows = read_objectadds(path)
        if not rows:
            continue
        cx = sorted(r[0] for r in rows)[len(rows) // 2]
        cz = sorted(r[1] for r in rows)[len(rows) // 2]
        kits.append({'from': stem, 'n': len(rows),
                     'radius': math.hypot(cx - fld['x'], cz - fld['z']) / U,
                     'kit': [{'dx': (r[0] - cx) / U, 'dz': (r[1] - cz) / U,
                              'hdg': r[2] % 360.0, 'id': r[3]} for r in rows]})
    return kits


def place(kit, fld, near, rnd):
    """Bearing at RADIUS that best clears the runway and everything there."""
    best = None
    for deg in range(0, 360, 2):
        th = math.radians(deg)
        cx = fld['x'] + RADIUS * U * math.cos(th)
        cz = fld['z'] + RADIUS * U * math.sin(th)
        pts = [(cx + k['dx'] * U, cz + k['dz'] * U) for k in kit]
        run = min((seg_dist(p, *fld['runway']) for p in pts), default=9e9) \
            if fld['runway'] else 9e9
        if run < MIN_RUNWAY:
            continue
        clash = min((math.hypot(p[0] - q[0], p[1] - q[1]) / U
                     for p in pts for q in near), default=9e9)
        if clash < CLASH:
            continue
        score = min(run, 400.0) + min(clash, 400.0)
        if best is None or score > best[0]:
            best = (score, th, run, clash)
    if best is None:
        return None
    return {'bearing': best[1], 'runway': best[2], 'clash': best[3]}


def place_station(kit, fld, near, parked_at, rnd):
    """A bomber station: out past the aeroplanes the game already parks."""
    best = None
    for deg in range(0, 360, 2):
        if parked_at and min(min(abs(deg - b), 360 - abs(deg - b))
                             for b in parked_at) < 55:
            continue                     # keep off the ones already there
        th = math.radians(deg)
        cx = fld['x'] + STATION_RADIUS * U * math.cos(th)
        cz = fld['z'] + STATION_RADIUS * U * math.sin(th)
        pts = [(cx + k['dx'] * U, cz + k['dz'] * U) for k in kit]
        clash = min((math.hypot(p[0] - q[0], p[1] - q[1]) / U
                     for p in pts for q in near), default=9e9)
        if clash < CLASH:
            continue
        if best is None or clash > best[0]:
            best = (clash, th)
    if best is None:
        return None
    return {'bearing': best[1], 'radius': STATION_RADIUS,
            'runway': 9e9, 'clash': best[0]}


def extras(fld, rnd, stub):
    """Parked aeroplanes, and buildings where the field has none."""
    out = []
    # TRIMMED 2026-09-13. Three Blenheims at every field cost a measured
    # ten per cent over Biggin Hill (131 fps dressed against 145 bare, and
    # the 1% low from 74 to 66): the 191 parked aeroplanes across both
    # sides were nearly the whole cost, the huts and lorries next to
    # nothing. A fighter station had no Blenheims on it anyway, so it now
    # has none; a bomber station keeps two.
    shapes = PARKED_BOMBER if fld['kind'] == 'bomber' else PARKED_FIGHTER
    n_park = 2 if fld['kind'] == 'bomber' else 0
    base = rnd.uniform(0, 360)
    for i in range(n_park):
        a = math.radians(base + i * 5)
        d = (i - 1) * PARK_SPACING
        out.append({'dx': d * math.cos(a) - 110 * math.sin(a) + rnd.uniform(-7, 7),
                    'dz': d * math.sin(a) + 110 * math.cos(a) + rnd.uniform(-7, 7),
                    'hdg': (base + i * 5 + rnd.uniform(-10, 10)) % 360,
                    'id': shapes[i % len(shapes)]})
    if stub:
        for i, (sid, _n) in enumerate(STUB_KIT):
            a = math.radians(rnd.uniform(0, 360))
            r = 150 + i * 38
            out.append({'dx': r * math.cos(a), 'dz': r * math.sin(a),
                        'hdg': rnd.choice([0, 90, 180, 270]) + rnd.uniform(-5, 5),
                        'id': sid})
    return out


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
    ap.add_argument('--src',  default=os.path.join(ROOT, 'dispersal'))
    ap.add_argument('--out',  default=os.path.join(ROOT, 'dispersal/RAF_Airfields.txt'))
    ap.add_argument('--json', default=os.path.join(ROOT, 'dispersal/raf-airfields.json'))
    a = ap.parse_args()

    world = os.path.join(a.game, 'BFIELDS/MAINWLD.BFI')
    if not os.path.exists(world):
        print('no world file at %s' % world, file=sys.stderr)
        return 1
    ref = read_world(world)
    cat = catalogue(os.path.join(a.game, 'Docs/List_From_Bin_catalog.txt'))
    oa_dir = os.path.join(a.game, 'ObjectAdds')

    existing = []
    for fn in sorted(os.listdir(oa_dir)):
        if fn.lower().endswith('.txt') and fn != os.path.basename(a.out):
            existing += [(x, z) for x, z, _, _ in read_objectadds(os.path.join(oa_dir, fn))]

    stubs = set()
    bf = os.path.join(a.game, 'BFIELDS/RAFAF')
    if os.path.isdir(bf):
        for fn in os.listdir(bf):
            if fn.upper().startswith('AF') and fn.upper().endswith('.BF') \
               and os.path.getsize(os.path.join(bf, fn)) <= 40:
                stubs.add(fn[2:-3].upper())

    kits = lift(ref, a.src)
    if not kits:
        print('no dispersal payloads found in %s' % a.src, file=sys.stderr)
        return 1
    print('  lifted %d hand-made blocks, %d objects each, %.0f m out'
          % (len(kits), kits[0]['n'], sum(k['radius'] for k in kits) / len(kits)))

    blocks, manifest, skipped, problems = [], [], [], []
    total = 0
    for name in sorted(ref):
        if name in DONE:
            continue
        fld = ref[name]
        near = [(x, z) for x, z in existing
                if abs(x - fld['x']) < 2500 * U and abs(z - fld['z']) < 2500 * U]
        # A field qualifies on one of two grounds, and "it has some
        # objects somewhere in the county" is neither. Either it has a
        # runway centreline, or it has stock scenery close enough to the
        # reference point to show where the ground is safe. Detling has
        # neither: two objects, the nearest 2.2 km away, and no runway. It
        # slipped in on a 2.5 km count and had to be shut out again.
        close = sum(1 for x, z in near
                    if math.hypot(x - fld['x'], z - fld['z']) / U < 1000)
        station = None
        if name in NO_AERODROME:
            skipped.append((name, 'Shape EMPTY, no buildings, in no squadron\'s bases'))
            continue
        if not fld['runway'] and name in BOMBER_STATIONS:
            station = BOMBER_STATIONS[name]
        elif not fld['runway'] and close < 10:
            skipped.append((name, 'no runway geometry and nothing near the field'))
            continue
        rnd = random.Random('bob2-raf-field-' + name)
        src = kits[hash(name) % len(kits)] if False else rnd.choice(kits)
        stub = name in stubs
        kit = [dict(k) for k in src['kit']] + extras(fld, rnd, stub)
        if station is not None:
            got = place_station(kit, fld, near, station, rnd)
        else:
            got = place(kit, fld, near, rnd)
        if not got:
            problems.append('%s: nowhere at %d m clears the runway by %d m and the '
                            'scenery by %d m, so it is left alone'
                            % (name, RADIUS, MIN_RUNWAY, CLASH))
            continue
        th = got['bearing']
        rad = got.get('radius', RADIUS)
        cx = fld['x'] + rad * U * math.cos(th)
        cz = fld['z'] + rad * U * math.sin(th)
        rows = [(int(round(cx + k['dx'] * U)), int(round(cz + k['dz'] * U)),
                 round(k['hdg']) % 360, k['id']) for k in kit]
        if any(x < 0 or z < 0 for x, z, _, _ in rows):
            problems.append('%s: a negative coordinate' % name)
            continue
        lines = ['%s - %s (BOB2 Modern Fix). Static only.%s'
                 % (MARKER, name.title(), '  No battlefield file, so buildings too.' if stub else '')]
        for x, z, hdg, sid in rows:
            lines.append('OBJECT_ADD %d,%d,%.6f,%d #%s' % (x, z, float(hdg), sid, cat.get(sid, '?')))
        blocks.append('\r\n'.join(lines))
        total += len(rows)
        manifest.append({'field': name, 'kind': fld['kind'], 'from': src['from'],
                         'stub': stub, 'x': fld['x'], 'z': fld['z'],
                         'station': station is not None,
                         'runway': [list(p) for p in fld['runway']] if fld['runway'] else None,
                         'runway_clear': round(got['runway']) if fld['runway'] else None,
                         'runway_from': fld.get('runway_from'),
                         'nearest_stock': round(got['clash']) if got['clash'] < 9e8 else None,
                         'objects': [{'x': x, 'z': z, 'hdg': h, 'id': s} for x, z, h, s in rows]})

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    head = ('%s for the BOB2 Modern Fix.\r\n'
            '# %d RAF fields, %d objects, static only.\r\n'
            '# The same sixteen objects the five hand-made blocks carry, set down\r\n'
            '# 300 m from each reference point at the bearing that best clears the\r\n'
            "# runway and whatever is already there. Written by\r\n"
            '# dev/build_raf_dispersal.py; edit the script, not this file.\r\n'
            '# Delete this file to remove every one of them.\r\n' % (MARKER, len(blocks), total))
    with open(a.out, 'w', encoding='ascii', newline='') as fh:
        fh.write(head + '\r\n' + '\r\n\r\n'.join(blocks) + '\r\n')
    with open(a.json, 'w', encoding='utf-8') as fh:
        json.dump({'fields': manifest}, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    runs = sorted(f['runway_clear'] for f in manifest if f['runway_clear'] is not None)
    print('%d fields dressed, %d objects -> %s' % (len(blocks), total, a.out))
    if runs:
        print('  %d have a real runway: clearance %d m at worst, %d m typical'
              % (len(runs), runs[0], runs[len(runs) // 2]))
    print('  %d had no battlefield file, so they got buildings as well'
          % sum(1 for f in manifest if f['stub']))
    if skipped:
        print('  %d left alone for want of runway geometry: %s'
              % (len(skipped), ', '.join(n for n, _ in skipped)))
    for p in problems:
        print('  ! %s' % p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
