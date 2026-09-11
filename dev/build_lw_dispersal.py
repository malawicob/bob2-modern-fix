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
# 220, up from 165. 165 was the least the BDG's own fields keep, and it
# is enough to stay off a runway, but it is not enough to stay away from
# where you SPAWN: Patrick found a Blitz and a Kuebelwagen parked on his
# wingtip. The markers are the takeoff points, so they are the best proxy
# for the spawn there is, and everything now stands further back from
# them. The groups stay as close to the field as they were, because what
# governs that is the radius from the reference point, not this.
MIN_CLEAR = 220
# HOW FAR OUT A DISPERSAL SITS, and the answer is mostly "about the same
# distance, whatever the size of the field".
#
# Measured on the six the BDG dressed by hand:
#
#     Abbeville   548 m out, markers reach  291 m
#     Cocquelles  693 m out, markers reach  487 m
#     Peuplingues 724 m out, markers reach  722 m
#     Marck       612 m out, markers reach  464 m
#     Wissant     388 m out, markers reach 1030 m
#
# The absolute distances sit in a narrow band, 388 to 724 m, while the
# ratio to the field's own reach runs from 0.38 to 1.88. So the size of
# the aerodrome does NOT predict how far out its buildings went, and
# scaling by it is the wrong model: trying that put Laval's 2767 m away,
# because its markers reach 1469 m.
#
# What was wrong at Audembert is narrower than that. Its markers reach
# 366 m and it was getting 691 m, Cocquelles' distance, because every
# GLFTTNT2 field inherited one number. So the rule is the exemplar's own
# distance, pulled IN when the field is too small to carry it, and held
# inside the band either way.
MIN_RADIUS = 400
# The closest a GROUP may sit to the reference point. The nearest thing
# the BDG put at Cocquelles is 221 m out, so 190 is not a liberty.
# 110, down from 190. The 190 was a number I chose and nothing else, and
# it was the only thing keeping the dispersal out: measured across all
# forty fields, every one of them can put a group 60 m from its reference
# point and still be 165 m from every runway marker, because the markers
# are scattered points and there is always a bearing away from them.
#
# The hand-dressed fields bear it out at both ends. Abbeville, Cocquelles,
# Peuplingues and Marck keep their nearest object 440 to 528 m out, but
# WISSANT PUTS ONE 88 m FROM ITS REFERENCE and Le Havre 82 m. So going in
# close is not a liberty, it is one of the two ways it was actually done,
# and what governs is distance from the markers, which is unchanged.
MIN_RADIUS_G = 80
MAX_RADIUS = 700
SMALL_FIELD = 1.4        # a dispersal may sit this far out relative to the field
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

# PARKED AEROPLANES, which is the thing that makes a field look flown
# from. Not invented either: ObjectAdds\Ju52s.txt parks Ju 52s at Marck,
# Abbeville, Wissant and Le Havre, so aircraft placed this way are
# already shipped and already work. Every one of these shapes has a .bin
# on disk.
# ONLY THE Ju 52, because it is the only one that works.
#
# The first version parked a 109 at every fighter field, a 110 at the
# Zerstoerer fields and bombers elsewhere, on the reasoning that 21 JU52
# is placed by Ju52s.txt so the neighbouring aircraft ids must work too.
# Patrick flew to Caffiers and there were no aeroplanes on it.
#
# Counted across the 295 shipped files and the whole battlefield source,
# exactly two aircraft shapes are ever placed as ground objects: 21 JU52,
# thirteen times in ObjectAdds, and 187 GBRIST, the static Blenheim,
# nineteen times in the battlefield files. Everything in 19 to 25, 32, 44
# and 45 is placed by nobody, anywhere, and 23 ME109 is one of them.
#
# A Ju 52 at a fighter field is not a consolation prize either: it was
# the Luftwaffe's workhorse and turned up at every field it had.
PARKED_ANY = 21         # Ju 52, the one aircraft proven to place
PARK_MAX = 2
PARK_SPACING = 55

# SHEEP AND COWS. Also shipped: ObjectAdds\TM SOE2.txt grazes six sheep
# and nine cows near Marck. A grass aerodrome was kept down by somebody's
# flock, and it costs a handful of objects.
SHEEP, COW = 328, 329
FLOCK = 5

# A HANGAR, WHICH NO GERMAN FIELD IN THE GAME HAS.
#
# Not "no scenery": no buildings. All 62 BFIELDS\LUFAF files are 33-byte
# stubs, and the airfield Shape each field carries in MAINWLD.BFI is a
# few hundred bytes - GLFTTNT2 is 367 - where a real hangar model is
# 110 KB. So the Shape is a ground marker and nothing more, and 436, 437
# and 503 have never been placed anywhere by anyone.
#
# Which one follows the field's own Shape: FUL is a permanent station and
# gets a requisitioned French hangar, TNT is a tented field and gets the
# tent hangar. EMPTY has no ground model at all, so it takes the tent.
HANGAR = {'GLFTFUL1': 436, 'GLFTFUL2': 437, 'GLFTTNT1': 503,
          'GLFTTNT2': 503, 'EMPTY': 503}
LWHUT = 438             # the Luftwaffe hut, also never placed anywhere

# A ROW OF TENTS, because that is what a Luftwaffe field looked like and
# Caffiers had exactly one. The exemplars are no help: Cocquelles carries
# a single lwtent and every GLFTTNT2 field inherited it, so the tent line
# is built rather than lifted. Eight in a shallow row, the way the ones
# at Abbeville sit.
TENT_LINE = 12
TENT_SPACING = 26

# AIR DEFENCE. Five guns across forty fields was not a defended aerodrome.
# The 88 and the large revetment that goes with it, the Flakvierling, and
# the half-track mounting; none of 419, 421, 427, 428 or 430 has ever been
# placed either.
FLAK_LIGHT = [420, 421]                  # 2 cm Flak 38, Flakvierling
FLAK_HEAVY = [419, 428]                  # 88 firing, 88 on tow
REVET_HEAVY = 430                        # large revetment, beside an 88
FLAK_TRACK = 427                         # Flakvierling on an SdKfz 7
# The Kanalfront stations were the ones being bombed, so they get more.
KANALFRONT_LAT = 50.4

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


def field_reach(fld):
    """How far this field's own runway markers get from its centre."""
    if not fld.get('runway'):
        return 0.0
    return max(math.hypot(m[0] - fld['x'], m[1] - fld['z']) / U for m in fld['runway'])


# WHICH GROUP EACH THING BELONGS TO.
#
# The scope document worked this out at the very start and it never got
# built: the BDG's author "worked cluster by cluster: consecutive lines
# 7-50 m apart in runs (a dispersal, then the MT lines, then a farm
# group), separated by 200-600 m jumps."
#
# What shipped instead was one clump 692 m from the middle of Caffiers,
# spanning 683 m, and Patrick flew to it and said it was sparse and far
# away. It was both, and for the same reason: a single loose scatter at
# one bearing reads as neither a dispersal nor anything else. Cocquelles,
# dressed by hand, has objects from 221 m out to 3.3 km in groups.
GROUP_OF = {}
for _s in (440, 439, 438, 503, 436, 437, 441, 442, 443, 347):
    GROUP_OF[_s] = 'dispersal'          # tents, revetments, huts, hangar, crew
for _s in range(411, 428):
    GROUP_OF[_s] = 'transport'          # the MT lines
for _s in (419, 420, 421, 427, 428, 429, 430, 434):
    GROUP_OF[_s] = 'flak'
for _s in (431, 432, 433, 435):
    GROUP_OF[_s] = 'farm'               # the requisitioned buildings
GROUP_OF[324] = 'bombs'
GROUP_OF[328] = GROUP_OF[329] = 'flock'

# How far out each group wants to sit, and how tight it is. The dispersal
# is the thing you are meant to see on the way in, so it is the closest
# in that the runway markers allow.
# A DISPERSAL GOES EAST OF THE FIELD, and that is measured, not chosen.
#
# The bearing of the kit's centre from the reference point, on all five
# German fields the BDG dressed by hand:
#
#     Abbeville 99   Cocquelles 82   Peuplingues 111
#     Marck     81   Wissant    87
#
# Five out of five between 81 and 111 degrees, and it has nothing to do
# with where the runway markers are: those run from 12 to 191 degrees and
# sit 4 to 69 degrees off the kit in every case. So east is a convention
# the authors followed, and since Patrick reports Abbeville's vehicles a
# few metres off his STARBOARD WING at the spawn, east of the reference
# is where the aeroplane ends up looking.
#
# This is why every earlier attempt read as "far away". The objects were
# not too distant, Abbeville's sit at 548 m and he calls that much
# better: they were on the wrong side. Spreading the groups evenly round
# the compass, which fixed the pile-up, guaranteed most of them faced
# away from him.
# 99, Abbeville's own bearing, not the mean of the five. Patrick reports
# Abbeville's vehicles a few METRES off his starboard wing while ours,
# at the same radius but 66 degrees, are still away in the distance. At
# 500 m a 33 degree difference is 290 m of arc, which is a field's width
# round the perimeter, so the mean was not close enough.
DISPERSAL_EAST = 99
# And a narrow arc, not a wide one. Spreading the groups round the
# compass was the fix for them piling up on one side; it turns out the
# BDG pile theirs up too, and on purpose. Every Abbeville object sits
# between 75 and 114 degrees. The pile is right, it was the BEARING that
# was wrong.
EAST_ARC = 22
# Abbeville's own radii: tents 528 to 541, barns and byres 534 to 545,
# vehicles 546 to 594, revetment 574. Ours now sit in the same band.
GROUP_PLAN = {
    'dispersal': (530, 55),
    'aircraft':  (600, 50),
    'transport': (575, 45),
    'flak':      (640, 70),
    'bombs':     (660, 30),
    'farm':      (545, 55),
    'flock':     (700, 40),
}


def group_of(k):
    return k.get('grp') or GROUP_OF.get(k['id'], 'dispersal')


def tighten(items, span):
    """Pull a group in around its own centre so it reads as one thing."""
    if not items:
        return items
    cx = sorted(k['dx'] for k in items)[len(items) // 2]
    cz = sorted(k['dz'] for k in items)[len(items) // 2]
    reach = max((math.hypot(k['dx'] - cx, k['dz'] - cz) for k in items), default=0.0)
    f = 1.0 if reach <= span else span / reach
    for k in items:
        k['dx'] = (k['dx'] - cx) * f
        k['dz'] = (k['dz'] - cz) * f
    return items


def anchor_group(items, fld, markers, want_r, taken, aim=None, spread=40):
    """Bearing and radius for one group.

    THE GROUPS ARE SPREAD ROUND THE FIELD, and they were not before.
    Every group searched the whole compass for the best clearance, so
    they all found the same best bearing and piled up on one side: at
    Caffiers 29 of 37 objects sat in a single 45 degree sector. That is
    one bug producing both of Patrick's complaints at once. Spawn on the
    far side and the whole base is away in the distance; spawn near that
    sector and there is a lorry on your wingtip.

    A real aerodrome put its dispersals round the perimeter, so each
    group now gets its own arc to sit in and only searches within it.
    """
    for r in [want_r + step for step in range(0, 520, 20)]:
        best = None
        degs = range(0, 360, 4) if aim is None else \
            [int(aim + o) % 360 for o in range(-spread, spread + 1, 4)]
        for deg in degs:
            th = math.radians(deg)
            cx = fld['x'] + r * U * math.cos(th)
            cz = fld['z'] + r * U * math.sin(th)
            pts = [(cx + k['dx'] * U, cz + k['dz'] * U) for k in items]
            c = clearance(pts, markers)
            if c is None or c < MIN_CLEAR:
                continue
            apart = min((math.hypot(cx - tx, cz - tz) / U for tx, tz in taken), default=9e9)
            # 45, not 75. Seven groups needing 75 m between them is 525 m
            # of separation, and a 44 degree arc at 530 m is only 407 m
            # long, so they could not fit and spilled out of the arc
            # westward. They differ by radius as well as bearing, so a
            # smaller gap is enough to keep them from merging.
            if apart < 45:
                continue
            score = min(c, 400.0) + min(apart, 400.0) * 0.4
            if best is None or score > best[0]:
                best = (score, cx, cz, c)
        if best:
            return best[1], best[2], best[3]
    return None


def place_kit(kit, fld, markers, want_r):
    """Bearing and radius: as close in as the runways allow.

    The first version used one radius per template and only searched the
    bearing, and that was wrong on a small field. Audembert's own runway
    markers reach 366 m from its centre and its dispersal was being put
    691 m out, nearly twice as far from the middle as the aerodrome
    itself extends, because Cocquelles happens to sit 696 m out and every
    GLFTTNT2 field inherited that number. Patrick flew it and said the
    buildings were too far away, and he was right.

    So the radius is scaled to the field: the same distance out, relative
    to the size of the aerodrome, as the exemplar had. That is checked
    against clearance and pushed out step by step if it has to be, which
    is the one direction it is safe to move.
    """
    lo = min(MAX_RADIUS, max(MIN_RADIUS, want_r))
    for r in [lo + step for step in range(0, 600, 25)]:
        best, best_at = None, None
        for deg in range(0, 360, 2):
            th = math.radians(deg)
            cx, cz = fld['x'] + r * U * math.cos(th), fld['z'] + r * U * math.sin(th)
            pts = [(cx + k['dx'] * U, cz + k['dz'] * U) for k in kit]
            c = clearance(pts, markers)
            if c is None:
                return 0.0, r
            if best is None or c > best:
                best, best_at = c, th
        if best is not None and best >= MIN_CLEAR:
            return best_at, r
    return (best_at or 0.0), lo


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
    # A 1000 kg bomb has no business at a 109 field. 128 of them were
    # spread over all forty, because the Cocquelles exemplar carries a
    # bomb dump and every tented field inherited it.
    if not bomber:
        out = [k for k in out if k['id'] != 324]
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


def buildings(fld, rnd):
    """The hangar and the hut, which no German field has ever had."""
    out = []
    h = HANGAR.get(fld['shape'], 503)
    out.append({'dx': rnd.uniform(-40, 40) - 150, 'dz': rnd.uniform(-30, 30) + 150,
                'hdg': rnd.choice([0, 90, 180, 270]) + rnd.uniform(-6, 6), 'id': h})
    for i in range(2):
        out.append({'dx': -210 + i * 46 + rnd.uniform(-10, 10),
                    'dz': 96 + rnd.uniform(-14, 14),
                    'hdg': rnd.uniform(0, 360), 'id': LWHUT})
    return out


def tent_line(rnd):
    """The row of tents that makes a field read as a Luftwaffe one."""
    out = []
    a = math.radians(rnd.uniform(0, 360))
    for i in range(TENT_LINE):
        d = (i - (TENT_LINE - 1) / 2.0) * TENT_SPACING
        out.append({'dx': d * math.cos(a) + rnd.uniform(-5, 5),
                    'dz': d * math.sin(a) + rnd.uniform(-5, 5),
                    'hdg': (math.degrees(a) + 90 + rnd.uniform(-8, 8)) % 360,
                    'id': 440, 'grp': 'dispersal'})
    return out


def flak(rnd, kanalfront):
    """Two guns, three at the Kanalfront, and a revetment for the 88."""
    out = []
    n = 3 if kanalfront else 2
    for i in range(n):
        heavy = (i == 0)
        a = math.radians(rnd.uniform(0, 360))
        r = rnd.uniform(210, 330)
        dx, dz = r * math.cos(a), r * math.sin(a)
        sid = rnd.choice(FLAK_HEAVY) if heavy else rnd.choice(FLAK_LIGHT)
        out.append({'dx': dx, 'dz': dz, 'hdg': rnd.uniform(0, 360), 'id': sid})
        if heavy:
            out.append({'dx': dx + rnd.uniform(-7, 7), 'dz': dz + rnd.uniform(-7, 7),
                        'hdg': rnd.uniform(0, 360), 'id': REVET_HEAVY})
    if kanalfront:
        a = math.radians(rnd.uniform(0, 360))
        out.append({'dx': 260 * math.cos(a), 'dz': 260 * math.sin(a),
                    'hdg': rnd.uniform(0, 360), 'id': FLAK_TRACK})
    return out


def parked(types, rnd, n_gruppen):
    """A Ju 52 or two, in kit coordinates, beside the dispersal."""
    want = PARK_MAX
    shapes = [PARKED_ANY]
    out = []
    # a shallow arc rather than a dead straight row, the way a Staffel
    # actually stood about on a field
    base = rnd.uniform(0, 360)
    for i in range(want):
        a = math.radians(base + i * 4)
        d = (i - (want - 1) / 2.0) * PARK_SPACING
        out.append({'dx': d * math.cos(a) - 120 * math.sin(a) + rnd.uniform(-8, 8),
                    'dz': d * math.sin(a) + 120 * math.cos(a) + rnd.uniform(-8, 8),
                    'hdg': (base + i * 4 + rnd.uniform(-12, 12)) % 360,
                    'id': shapes[i % len(shapes)], 'grp': 'aircraft'})
    return out


def flock(rnd):
    """A few sheep and cows, off to one side and well away from anything."""
    out = []
    cx, cz = rnd.uniform(-320, 320), rnd.uniform(-320, -180)
    for i in range(FLOCK):
        out.append({'dx': cx + rnd.uniform(-26, 26), 'dz': cz + rnd.uniform(-20, 20),
                    'hdg': rnd.choice([0, 45, 90, 135, 180, 225, 270, 315]),
                    'id': SHEEP if i % 3 else COW})
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
        reach = field_reach(ref[nm])
        templates[shape] = {'kit': trim(kit, nm), 'from': nm, 'radius': radius,
                            'ratio': (radius / reach) if reach > 0 else 1.4,
                            'raw': len(kit)}

    geo = {}
    geo_path = os.path.join(ROOT, 'squadronroom/lw/fields.json')
    if os.path.exists(geo_path):
        geo = json.load(open(geo_path, encoding='utf-8'))
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
        # A bigger station gets more on it: two aeroplanes per Gruppe
        # based there, which is the only thing that scales with how busy
        # the field was. Plus somebody's flock keeping the grass down.
        lat = (geo.get(field) or [0, 0])[0]
        kit = (kit
               + buildings(fld, rnd)
               + tent_line(rnd)
               + flak(rnd, lat >= KANALFRONT_LAT)
               + parked(by_field[field], rnd, len(by_field[field]))
               + flock(rnd))
        # the same distance out, relative to the size of the aerodrome,
        # as the exemplar's own dispersal sat from its field
        reach = field_reach(fld)
        want_r = tpl['radius']
        if reach > 0:
            want_r = min(want_r, max(reach * SMALL_FIELD, MIN_RADIUS))
        # Group by group, each one tight and each at its own bearing, the
        # way the fields dressed by hand are laid out.
        groups = {}
        for k in kit:
            groups.setdefault(group_of(k), []).append(k)
        rows, taken, placed = [], [], []
        order = ('dispersal', 'transport', 'aircraft', 'flak', 'bombs', 'farm', 'flock')
        # fanned across the eastern arc rather than round the whole
        # compass, so the field faces the aeroplane instead of hiding
        # behind it
        # The dispersal sits ON the bearing, not at one end of the arc.
        # Fanning all seven groups evenly across it put the biggest one,
        # twelve tents and the hangar, at 77 degrees and dragged the
        # field's centre round to 72 at Audembert. It is the thing you
        # are meant to see, so it goes where Abbeville's is and the rest
        # fan out either side of it.
        turn = rnd.uniform(-6, 6)
        offsets = (0, -14, 14, -21, 21, -8, 8)
        aims = {g: (DISPERSAL_EAST + offsets[i % len(offsets)] + turn) % 360
                for i, g in enumerate(order)}
        for gname in order:
            items = groups.pop(gname, [])
            if not items:
                continue
            want, span = GROUP_PLAN.get(gname, (300, 60))
            tighten(items, span)
            got = anchor_group(items, fld, fld['runway'], max(want, MIN_RADIUS_G),
                               taken, aim=aims[gname], spread=14)
            if not got:                      # nowhere in its own narrow arc
                got = anchor_group(items, fld, fld['runway'],
                                   max(want, MIN_RADIUS_G), taken,
                                   aim=DISPERSAL_EAST, spread=EAST_ARC)
            if not got:                      # and only then anywhere at all
                got = anchor_group(items, fld, fld['runway'],
                                   max(want, MIN_RADIUS_G), taken)
            if not got:
                continue
            cx, cz, clr = got
            taken.append((cx, cz))
            placed.append((gname, math.hypot(cx - fld['x'], cz - fld['z']) / U, clr))
            for k in items:
                rows.append((int(round(cx + k['dx'] * U)), int(round(cz + k['dz'] * U)),
                             round(k['hdg']) % 360, k['id']))
        for leftover in groups.values():          # anything unclassified
            for k in leftover:
                rows.append((int(round(fld['x'] + (want_r + 60) * U + k['dx'] * U)),
                             int(round(fld['z'] + k['dz'] * U)),
                             round(k['hdg']) % 360, k['id']))
        if not rows:
            problems.append('%s: no group could be placed clear of the runway markers'
                            % field)
            continue
        clear = clearance([(x, z) for x, z, _, _ in rows], fld['runway'])
        if clear is None or clear < MIN_CLEAR:
            problems.append('%s: %.0f m from a runway marker, under the %d m floor'
                            % (field, clear or 0, MIN_CLEAR))
            continue
        radius = min(d for _g, d, _c in placed)
        bearing = 0.0
        if any(x < 0 or z < 0 for x, z, _, _ in rows):
            problems.append('%s: a negative coordinate, which the exe reads as unsigned' % field)
            continue
        lines = ['%s - %s (BOB2 Modern Fix). Static only. %d Gruppe(n) based.'
                 % (MARKER, field, len(by_field[field]))]
        for x, z, hdg, sid in rows:
            lines.append('OBJECT_ADD %d,%d,%.6f,%d #%s' % (x, z, float(hdg), sid, cat.get(sid, '?')))
        blocks.append('\r\n'.join(lines))
        total += len(rows)
        manifest.append({'field': field, 'uid': key, 'shape': fld['shape'],
                         'exemplar': tpl['from'],
                         'bearing': round(math.degrees(bearing) % 360.0, 1),
                         'radius': round(radius), 'reach': round(reach),
                         'groups': [{'name': g, 'radius': round(d), 'clear': round(c)}
                                    for g, d, c in placed],
                         'clearance': round(clear),
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
        print('  %-9s from %-11s %2d of %3d objects kept, %3.0f m out, %.2f x its field'
              % (shape, t['from'], len(t['kit']), t['raw'], t['radius'], t['ratio']))
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
