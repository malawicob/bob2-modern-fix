#!/usr/bin/env python3
"""Draw the Squadron Room's sector map from real coastline data.

An image generator draws a pretty coastline that is in the wrong place,
which is useless here: the Room plots squadrons on this map from their
real latitude and longitude, so every mile of it has to be true. This
renders Natural Earth's 1:10m land, coastline and river data straight to
the image, and every airfield and town is placed from its own coordinates.

    python3 dev/fetch_relief.py --out /tmp/relief.npz          (once)
    python3 dev/make_sector_map.py --data /tmp --relief /tmp/relief.npz \
        --out squadronroom/map/sector-map.jpg

  --data is a folder holding Natural Earth's ne_10m_land.geojson,
  ne_10m_coastline.geojson and ne_10m_rivers_lake_centerlines.geojson,
  saved as .json. Without --relief the land is drawn flat.

The projection is written to squadronroom/map/sector-map.json beside it, so
the Room places its rings from the same numbers the map was drawn with,
rather than from a fit of hand-placed anchors.
"""
import json, math, argparse, os

# The extent the order of battle needs: Pembrey in the west, Kirton in
# Lindsey in the north, the Norfolk coast in the east, and the enemy coast
# from Cherbourg to the Scheldt across the Channel.
WEST, EAST = -5.6, 4.0
SOUTH, NORTH = 50.0, 53.8
W, H = 2560, 1600

INK = {
    'sea':      (11, 20, 27),
    'sea_deep': (8, 15, 21),
    'land':     (30, 46, 38),
    'land_hi':  (38, 57, 46),
    'coast':    (95, 208, 232),
    'river':    (46, 84, 104),
    'grid':     (22, 38, 48),
    'boundary': (200, 151, 63),
    'label':    (233, 227, 212),
    'town':     (159, 176, 184),
    'title':    (200, 151, 63),
    'london':   (60, 78, 96),
    'seaname':  (108, 141, 166),
    'tick':     (140, 160, 172),
}

# Waters, lettered the way a chart letters them.
SEAS = [
    ('NORTH SEA', 53.05, 2.55), ('ENGLISH CHANNEL', 50.45, -1.55),
    ("ST GEORGE'S CH.", 52.55, -5.10), ('BRISTOL CHANNEL', 51.35, -4.35),
    ('STRAIT OF DOVER', 50.85, 1.75),
]

# The fields packed into the London approaches and the Sussex coast. Their
# names are the single worst source of clutter on the sheet: a dozen 90px
# boxes inside one 200px square, with the squadron plaques trying to find
# room among them. The Room draws these names on the plaque instead, so the
# sheet keeps only the dot. Every other field still carries its own name.
SUPPRESS_NAMES = {
    'Northolt', 'Croydon', 'Kenley', 'Biggin Hill', 'North Weald', 'Hornchurch',
    'Debden', 'Duxford', 'Fowlmere', 'Rochford', 'Coltishall', 'Tangmere',
    'Westhampnett', 'Castle Camps', 'Stapleford Tawney', 'Gravesend', 'Detling',
    'Hawkinge', 'Lympne', 'Manston', 'Martlesham Heath',
}

# Fighter Command airfields named in the game's order of battle, plus the
# handful of well-known ones that give the map its shape.
AIRFIELDS = [
    ('Pembrey', 51.7139, -4.3208), ('Exeter', 50.7344, -3.4139),
    ('Filton', 51.5194, -2.5908), ('Colerne', 51.4394, -2.2814),
    ('Boscombe Down', 51.1522, -1.7472), ('Warmwell', 50.6928, -2.3500),
    ('Middle Wallop', 51.1508, -1.5686), ('Tangmere', 50.8453, -0.7061),
    ('Westhampnett', 50.8592, -0.7583), ('Northolt', 51.5531, -0.4183),
    ('Hendon', 51.5872, -0.2411), ('Croydon', 51.3562, -0.1108),
    ('Kenley', 51.3047, -0.0950), ('Biggin Hill', 51.3308, 0.0325),
    ('West Malling', 51.2739, 0.4033), ('Gravesend', 51.4142, 0.4022),
    ('Detling', 51.3025, 0.5967), ('Hawkinge', 51.1153, 1.1564),
    ('Lympne', 51.0800, 1.0128), ('Manston', 51.3422, 1.3461),
    ('Hornchurch', 51.5411, 0.2200), ('Rochford', 51.5714, 0.6956),
    ('North Weald', 51.7217, 0.1547), ('Stapleford Tawney', 51.6528, 0.1558),
    ('Debden', 51.9964, 0.2711), ('Castle Camps', 52.0603, 0.3778),
    ('Martlesham Heath', 52.0567, 1.2828), ('Duxford', 52.0931, 0.1289),
    ('Fowlmere', 52.0806, 0.0500), ('Coltishall', 52.7547, 1.3572),
    ('Wittering', 52.6125, -0.4761), ('Digby', 53.0925, -0.4383),
    ('Kirton in Lindsey', 53.4494, -0.5808),
]

TOWNS = [
    ('LONDON', 51.5074, -0.1278), ('BRISTOL', 51.4545, -2.5879),
    ('SOUTHAMPTON', 50.9097, -1.4044), ('PORTSMOUTH', 50.8198, -1.0880),
    ('BRIGHTON', 50.8225, -0.1372), ('EASTBOURNE', 50.7687, 0.2844),
    ('DOVER', 51.1279, 1.3134), ('FOLKESTONE', 51.0810, 1.1690),
    ('CANTERBURY', 51.2802, 1.0789), ('MAIDSTONE', 51.2704, 0.5227),
    ('ASHFORD', 51.1465, 0.8676), ('WEYMOUTH', 50.6144, -2.4570),
    ('PORTLAND', 50.5411, -2.4419), ('YEOVIL', 50.9410, -2.6320),
    ('BOURNEMOUTH', 50.7192, -1.8808), ('NORWICH', 52.6309, 1.2974),
    ('IPSWICH', 52.0567, 1.1482), ('LINCOLN', 53.2307, -0.5406),
    ('CAMBRIDGE', 52.2053, 0.1218), ('SWANSEA', 51.6214, -3.9436),
    ('CARDIFF', 51.4816, -3.1791), ('PLYMOUTH', 50.3755, -4.1427),
    ('CHERBOURG', 49.6337, -1.6221), ('LE HAVRE', 49.4944, 0.1079),
    ('DIEPPE', 49.9229, 1.0777), ('BOULOGNE', 50.7264, 1.6139),
    ('CALAIS', 50.9513, 1.8587), ('DUNKIRK', 51.0343, 2.3768),
    ('OSTEND', 51.2247, 2.9075),
]

# Which sector each field belonged to, July to October 1940, and what it
# was: the sector station holding the operations room, or a satellite or
# forward field working under it.
#
# The letters were confirmed one by one against sources that are not
# Wikipedia where possible - Historic England's listings for the sector
# operations buildings at Northolt, Debden and Kirton in Lindsey among
# them. Northolt was Z, not Y; W and Y were Filton and Middle Wallop,
# and both were No. 11 Group sectors until 10 Group took them over in
# July and August 1940. An old map showing A, B, C, D, F, W, Y and Z
# together is therefore an 11 Group map from before 8 July.
#
# Where a source conflicts with another the entry says so rather than
# picking a side, and a field whose sector is not documented has none.
#   (letter, sector station, role, note)
SECTORS = {
    'Tangmere':          ('A', 'Tangmere', 'sector station', ''),
    'Westhampnett':      ('A', 'Tangmere', 'satellite', ''),
    'Kenley':            ('B', 'Kenley', 'sector station', ''),
    'Croydon':           ('B', 'Kenley', 'satellite', ''),
    'Biggin Hill':       ('C', 'Biggin Hill', 'sector station', ''),
    'Gravesend':         ('C', 'Biggin Hill', 'satellite', 'listed under Hornchurch as well in September'),
    'West Malling':      ('C', 'Biggin Hill', 'advanced airfield', 'bombed repeatedly and barely usable through the Battle'),
    'Hornchurch':        ('D', 'Hornchurch', 'sector station', ''),
    'Rochford':          ('D', 'Hornchurch', 'satellite', ''),
    'Manston':           ('D', 'Hornchurch', 'forward airfield', ''),
    'Hawkinge':          ('D', 'Hornchurch', 'forward airfield', ''),
    'North Weald':       ('E', 'North Weald', 'sector station', ''),
    'Stapleford Tawney': ('E', 'North Weald', 'satellite', ''),
    'Debden':            ('F', 'Debden', 'sector station', ''),
    'Castle Camps':      ('F', 'Debden', 'satellite', 'opened June 1940'),
    'Martlesham Heath':  ('',  '', 'satellite', 'served both Debden and North Weald sectors; sources differ'),
    'Northolt':          ('Z', 'Northolt', 'sector station', ''),
    'Hendon':            ('Z', 'Northolt', 'satellite', ''),
    'Lympne':            ('',  '', 'forward airfield', 'No. 11 Group; no sector named in any source found'),
    'Detling':           ('',  '', 'not Fighter Command', 'Coastal Command, No. 16 Group'),
    'Filton':            ('W', 'Filton', 'sector station', 'a No. 11 Group sector until 10 Group took it over on 8 July 1940'),
    'Colerne':           ('',  '', 'satellite', 'Filton sector or Middle Wallop, sources differ; meant to become a sector station but not until 1941'),
    'Exeter':            ('W', 'Filton', 'satellite', 'the 15 September order of battle puts it under Middle Wallop instead'),
    'Pembrey':           ('',  '', 'sector station', 'No. 10 Group; no letter found in any source'),
    'Middle Wallop':     ('Y', 'Middle Wallop', 'sector station', 'a No. 11 Group sector until 10 Group took it over in the summer of 1940'),
    'Warmwell':          ('Y', 'Middle Wallop', 'forward airfield', ''),
    'Boscombe Down':     ('Y', 'Middle Wallop', 'satellite', ''),
    'Duxford':           ('G', 'Duxford', 'sector station', ''),
    'Fowlmere':          ('G', 'Duxford', 'satellite', "the sector's own designation for it was G1"),
    'Wittering':         ('K', 'Wittering', 'sector station', ''),
    'Coltishall':        ('K', 'Wittering', 'satellite', 'worked as a parent station in practice; when it became a sector of its own is not established'),
    'Digby':             ('L', 'Digby', 'sector station', ''),
    'Kirton in Lindsey': ('M', 'Kirton in Lindsey', 'sector station', ''),
}

# Group boundaries. Only the two that a single line can honestly carry are
# drawn. The 10/11 boundary ran north from the Dorset coast, leaving Middle
# Wallop and Boscombe Down in 10 Group and Tangmere and Northolt in 11; the
# 13 Group boundary is the northern edge of the map's business.
#
# The 11/12 boundary is deliberately NOT drawn. It genuinely wandered:
# Duxford and Fowlmere were 12 Group sectors working over 11 Group's ground,
# and Debden three miles away was 11 Group. No straight line tells that
# truth, so the groups are lettered in open country instead.
BOUNDARIES = [
    [(50.55, -1.85), (51.25, -1.30), (52.10, -1.25), (53.00, -1.70), (53.80, -2.05)],
    [(53.55, -2.05), (53.55, 0.45)],
]
GROUP_LABELS = [
    ('No. 10 GROUP', 51.05, -3.10),
    ('No. 11 GROUP', 51.05, -0.55),
    ('No. 12 GROUP', 52.60, 0.20),
    ('No. 13 GROUP', 53.66, -0.90),
]

# =====================================================================
#  THE OTHER SIDE OF THE CHANNEL
#
#  The same sheet, drawn for the Luftwaffe. The extent is the only real
#  decision: it has to hold Lannion in the west, Sint-Truiden in the east
#  and Orleans-Bricy in the south, and still show enough of England for a
#  German pilot to see what he was flying at.
#
#  The proportions follow the RAF sheet rather than being picked. That one
#  covers 9.6 degrees of longitude and 3.8 of latitude in a 2560 x 1600
#  frame, which is a longitude-to-latitude ratio of 2.53 against an image
#  ratio of 1.6 - in other words the extent, not the code, carries the
#  cosine correction, and at 52 north 1/cos is 1.62. At 49.5 north it is
#  1.54, so this sheet wants 1.6 x 1.54 = 2.46 degrees of longitude for
#  every one of latitude. 4.35 x 2.46 is 10.7. Drawn any other shape,
#  France comes out visibly stretched beside an England that is not.
LW_WEST, LW_EAST = -4.5, 6.2
LW_SOUTH, LW_NORTH = 47.6, 51.95

LW_SEAS = [
    ('ENGLISH CHANNEL', 50.05, -1.30), ('NORTH SEA', 51.75, 3.30),
    ('STRAIT OF DOVER', 50.95, 1.55), ('BAY OF BISCAY', 47.95, -4.10),
]

# The Pas de Calais fields are a dozen villages inside twenty miles, and
# their names collide exactly as the London approaches do on the RAF
# sheet. The Room prints the name on the plaque instead.
LW_SUPPRESS = {
    'Audembert', 'Caffiers', 'Marquise', 'Guines', 'Peuplingues', 'Cocquelles',
    'Marck (Calais)', 'Hermelinghen', 'Colombert', 'Desvres', 'Samer', 'St. Omer',
    'Tramecourt', 'Barley', 'Yvrench',
}

# Towns for shape and for orientation. The English south coast is kept:
# the Channel is the point of this map.
LW_TOWNS = [
    ('CALAIS', 50.9513, 1.8587), ('BOULOGNE', 50.7264, 1.6139),
    ('DUNKIRK', 51.0343, 2.3768), ('OSTEND', 51.2247, 2.9075),
    ('BRUSSELS', 50.8503, 4.3517), ('BRUGES', 51.2093, 3.2247),
    ('LILLE', 50.6292, 3.0573), ('ARRAS', 50.2910, 2.7772),
    ('AMIENS', 49.8942, 2.2957), ('ABBEVILLE', 50.1061, 1.8337),
    ('ROUEN', 49.4432, 1.0993), ('LE HAVRE', 49.4944, 0.1079),
    ('DIEPPE', 49.9229, 1.0777), ('CHERBOURG', 49.6337, -1.6221),
    ('CAEN', 49.1829, -0.3707), ('PARIS', 48.8566, 2.3522),
    ('ORLEANS', 47.9029, 1.9093), ('CHARTRES', 48.4439, 1.4881),
    ('RENNES', 48.1113, -1.6800), ('BREST', 48.3904, -4.4861),
    ('LONDON', 51.5074, -0.1278), ('SOUTHAMPTON', 50.9097, -1.4044),
    ('PORTSMOUTH', 50.8198, -1.0880), ('DOVER', 51.1279, 1.3134),
    ('BRIGHTON', 50.8225, -0.1372), ('PLYMOUTH', 50.3755, -4.1427),
    ('EXETER', 50.7184, -3.5339),
]


def lw_airfields(path):
    """The Gruppen's fields, from the coordinates dev/build_lw_fields.py
    resolved. Read rather than listed here, so the map and the postings
    board can never disagree about where a field is."""
    with open(path, encoding='utf-8') as fh:
        d = json.load(fh)
    return [(name, v[0], v[1]) for name, v in sorted(d.items())]


def load(path, want):
    with open(path, encoding='utf-8') as f:
        gj = json.load(f)
    out = []
    for feat in gj['features']:
        g = feat.get('geometry') or {}
        t = g.get('type')
        if t == want:
            out.append((feat.get('properties', {}), g['coordinates']))
        elif t == 'Multi' + want:
            for part in g['coordinates']:
                out.append((feat.get('properties', {}), part))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default='/tmp')
    ap.add_argument('--relief', default='/tmp/relief.npz')
    ap.add_argument('--out', required=True)
    ap.add_argument('--side', choices=['raf', 'lw'], default='raf')
    ap.add_argument('--fields', default='squadronroom/lw/fields.json')
    a = ap.parse_args()

    # The drawing reads these as module globals throughout, so the German
    # sheet is made by swapping them once here rather than by threading a
    # side through forty call sites.
    global WEST, EAST, SOUTH, NORTH, AIRFIELDS, TOWNS, SEAS, SUPPRESS_NAMES, SECTORS, GROUP_LABELS
    if a.side == 'lw':
        WEST, EAST = LW_WEST, LW_EAST
        SOUTH, NORTH = LW_SOUTH, LW_NORTH
        AIRFIELDS = lw_airfields(a.fields)
        TOWNS = LW_TOWNS
        SEAS = LW_SEAS
        SUPPRESS_NAMES = LW_SUPPRESS
        # The Luftwaffe had no sector letters and no Group boundaries.
        # Emptying these is what stops the German sheet drawing Fighter
        # Command's organisation across northern France.
        SECTORS = {}
        GROUP_LABELS = []
    from PIL import Image, ImageDraw, ImageFont, ImageFilter

    SS = 2                      # draw at double size and shrink: cheap antialiasing
    iw, ih = W * SS, H * SS

    def px(lon, lat):
        x = (lon - WEST) / (EAST - WEST) * iw
        y = (NORTH - lat) / (NORTH - SOUTH) * ih
        return (x, y)

    # --- the ground itself -------------------------------------------
    # The land is shaded from real elevation, lit from the north-west as a
    # relief map is, and the sea is shaded by depth. Flat colour looked
    # like a diagram; this looks like country, without costing an ounce of
    # accuracy, because the elevation grid is on the same projection.
    land = load(os.path.join(a.data, 'ne_10m_land.json'), 'Polygon')
    mask = Image.new('L', (iw, ih), 0)
    md = ImageDraw.Draw(mask)
    drawn = 0
    for _, rings in land:
        pts = [px(c[0], c[1]) for c in rings[0]]
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        if max(xs) < -50 or min(xs) > iw + 50 or max(ys) < -50 or min(ys) > ih + 50:
            continue
        if len(pts) >= 3:
            md.polygon(pts, fill=255); drawn += 1
        for hole in rings[1:]:
            hp = [px(c[0], c[1]) for c in hole]
            if len(hp) >= 3: md.polygon(hp, fill=0)

    ground = None
    if os.path.exists(a.relief):
        import numpy as np
        z = np.load(a.relief)
        # The file records the ground it covers. Sampling it by plain
        # index scaling assumes that ground is THIS map's ground, and the
        # first German sheet was drawn with the RAF sheet's relief
        # stretched across northern France: it read as flat, dull shading
        # rather than as an obvious fault.
        if all(k in z for k in ('west', 'east', 'south', 'north')):
            rw, re_, rs, rn = (float(z['west']), float(z['east']),
                               float(z['south']), float(z['north']))
            if (abs(rw - WEST) > 0.01 or abs(re_ - EAST) > 0.01 or
                    abs(rs - SOUTH) > 0.01 or abs(rn - NORTH) > 0.01):
                print('  ! relief covers %.2f..%.2f / %.2f..%.2f but this map is '
                      '%.2f..%.2f / %.2f..%.2f - drawing flat instead of wrong'
                      % (rw, re_, rs, rn, WEST, EAST, SOUTH, NORTH))
                raise SystemExit(2)
        elev = z['elev']
        eh, ew = elev.shape
        # to the output grid
        yi = np.clip((np.arange(ih) / ih * eh).astype(np.int32), 0, eh - 1)
        xi = np.clip((np.arange(iw) / iw * ew).astype(np.int32), 0, ew - 1)
        E = elev[yi[:, None], xi[None, :]].astype(np.float32)

        # hillshade, light from the north-west
        gy, gx = np.gradient(E)
        scale = 9.0
        slope = np.arctan(np.hypot(gx, gy) / scale)
        aspect = np.arctan2(-gx, gy)
        az, alt = math.radians(315.0), math.radians(45.0)
        shade = (math.sin(alt) * np.cos(slope) +
                 math.cos(alt) * np.sin(slope) * np.cos(az - aspect))
        shade = np.clip(shade, 0.0, 1.0)

        h = np.clip(E, 0, 900) / 900.0            # high ground goes drier and paler
        lo = np.array(INK['land'], dtype=np.float32)
        hi = np.array(INK['land_hi'], dtype=np.float32)
        base = lo[None, None, :] * (1 - h[..., None]) + hi[None, None, :] * h[..., None]
        lit = base * (0.62 + 0.76 * shade[..., None])
        land_rgb = np.clip(lit, 0, 255).astype(np.uint8)

        # the sea, shaded by depth: the shallow Channel and the Dogger reads
        # lighter than the deep water off Brittany
        dep = np.clip(-E, 0, 120) / 120.0
        s_lo = np.array(INK['sea'], dtype=np.float32)
        s_hi = np.array(INK['sea_deep'], dtype=np.float32)
        sea_rgb = np.clip(s_lo[None, None, :] * (1 - dep[..., None]) +
                          s_hi[None, None, :] * dep[..., None], 0, 255).astype(np.uint8)
        ground = Image.composite(Image.fromarray(land_rgb), Image.fromarray(sea_rgb), mask)
    else:
        ground = Image.composite(Image.new('RGB', (iw, ih), INK['land']),
                                 Image.new('RGB', (iw, ih), INK['sea']), mask)
    img = ground
    d = ImageDraw.Draw(img)

    # a faint grid, one degree
    lon = math.ceil(WEST)
    while lon <= EAST:
        x = px(lon, 0)[0]; d.line([(x, 0), (x, ih)], fill=INK['grid'], width=SS); lon += 1
    lat = math.ceil(SOUTH)
    while lat <= NORTH:
        y = px(0, lat)[1]; d.line([(0, y), (iw, y)], fill=INK['grid'], width=SS); lat += 1

    # rivers, the Thames above all
    rivers = load(os.path.join(a.data, 'ne_10m_rivers_lake_centerlines.json'), 'LineString')
    for props, line in rivers:
        pts = [px(c[0], c[1]) for c in line]
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        if max(xs) < 0 or min(xs) > iw or max(ys) < 0 or min(ys) > ih:
            continue
        if len(pts) >= 2:
            d.line(pts, fill=INK['river'], width=int(2 * SS), joint='curve')

    # coastline, the luminous line that gives the table its look
    coast = load(os.path.join(a.data, 'ne_10m_coastline.json'), 'LineString')
    for _, line in coast:
        pts = [px(c[0], c[1]) for c in line]
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        if max(xs) < -20 or min(xs) > iw + 20 or max(ys) < -20 or min(ys) > ih + 20:
            continue
        if len(pts) >= 2:
            d.line(pts, fill=INK['coast'], width=int(1.6 * SS), joint='curve')

    # London's glow
    lx, ly = px(-0.1278, 51.5074)
    for r, alpha in ((70, 26), (52, 34), (36, 44)):
        rr = r * SS
        ov = Image.new('RGBA', (iw, ih), (0, 0, 0, 0))
        ImageDraw.Draw(ov).ellipse([lx - rr, ly - rr, lx + rr, ly + rr],
                                   fill=INK['london'] + (alpha,))
        img = Image.alpha_composite(img.convert('RGBA'), ov).convert('RGB')
        d = ImageDraw.Draw(img)

    # group boundaries, dashed
    def dashed(pts, fill, width, on=int(14 * SS), off=int(11 * SS)):
        for i in range(len(pts) - 1):
            x1, y1 = pts[i]; x2, y2 = pts[i + 1]
            seg = math.hypot(x2 - x1, y2 - y1)
            if seg < 1: continue
            n = int(seg // (on + off)) + 1
            for k in range(n):
                s0 = k * (on + off); s1 = min(s0 + on, seg)
                if s0 >= seg: break
                d.line([(x1 + (x2 - x1) * s0 / seg, y1 + (y2 - y1) * s0 / seg),
                        (x1 + (x2 - x1) * s1 / seg, y1 + (y2 - y1) * s1 / seg)],
                       fill=fill, width=width)
    # The group boundaries are not drawn. They cluttered a table whose job
    # is to carry fifty-two squadron rings, and the two that could honestly
    # be drawn were the least interesting part of it. The groups are still
    # lettered in open country.
    _ = dashed  # kept: the helper is still wanted if they ever come back

    def font(size, bold=False):
        for p in ('/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf' % ('-Bold' if bold else ''),
                  '/mnt/c/Windows/Fonts/%s' % ('seguisb.ttf' if bold else 'segoeui.ttf'),
                  '/mnt/c/Windows/Fonts/%s' % ('arialbd.ttf' if bold else 'arial.ttf')):
            if os.path.exists(p):
                try: return ImageFont.truetype(p, int(size * SS))
                except Exception: pass
        return ImageFont.load_default()

    f_af, f_town, f_grp, f_title = font(15), font(12), font(16, True), font(23, True)
    f_sea, f_tick = font(15), font(11, True)

    # the waters, lettered wide and faint so they sit under everything
    def serif(size):
        for p2 in ('/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf',
                   '/mnt/c/Windows/Fonts/georgiai.ttf', '/mnt/c/Windows/Fonts/timesi.ttf'):
            if os.path.exists(p2):
                try: return ImageFont.truetype(p2, int(size * SS))
                except Exception: pass
        return font(size)
    f_water = serif(19)
    for name, la, lo in SEAS:
        if not (WEST < lo < EAST and SOUTH < la < NORTH): continue
        x, y = px(lo, la)
        spaced = ' '.join(name)
        try: w = d.textbbox((0, 0), spaced, font=f_water)[2]
        except Exception: w = f_water.getsize(spaced)[0]
        tx = min(max(x - w / 2, 12 * SS), iw - w - 12 * SS)
        d.text((tx, y), spaced, font=f_water, fill=INK['seaname'])

    # degrees down the left edge and along the bottom
    lon = math.ceil(WEST)
    while lon <= EAST:
        x = px(lon, 0)[0]
        lab = '0' if lon == 0 else f'{abs(lon)}' + ('W' if lon < 0 else 'E')
        d.text((x + 4 * SS, ih - 20 * SS), lab, font=f_tick, fill=INK['tick'])
        lon += 1
    lat = math.ceil(SOUTH)
    while lat <= NORTH:
        y = px(0, lat)[1]
        d.text((7 * SS, y - 14 * SS), f'{lat}N', font=f_tick, fill=INK['tick'])
        lat += 1

    # Labels are placed so they do not sit on top of one another. Southern
    # England has airfields three miles apart, and set naively the names
    # ran through each other: Boscombe Down through Middle Wallop, Dover
    # through Folkestone, Duxford through Fowlmere.
    taken = []
    def fits(box):
        for t in taken:
            if not (box[2] < t[0] or box[0] > t[2] or box[3] < t[1] or box[1] > t[3]):
                return False
        return 0 <= box[0] and box[2] <= iw and 0 <= box[1] and box[3] <= ih
    def place(x, y, text, fnt, colour, pad=7 * SS):
        try: w, h = d.textbbox((0, 0), text, font=fnt)[2:]
        except Exception: w, h = fnt.getsize(text)
        # right, left, above, below, then the diagonals
        for dx, dy in ((pad, -h / 2), (-w - pad, -h / 2), (-w / 2, -h - pad), (-w / 2, pad),
                       (pad, -h - pad), (-w - pad, -h - pad), (pad, pad), (-w - pad, pad)):
            box = (x + dx, y + dy, x + dx + w, y + dy + h)
            if fits(box):
                taken.append(box); d.text((box[0], box[1]), text, font=fnt, fill=colour)
                return True
        return False

    # airfields first: they are what the Room plots against, so they get
    # the room. A small open square marks each one.
    f_sect = font(12, True)
    marker_r = {}
    for name, la, lo in AIRFIELDS:
        if not (WEST < lo < EAST and SOUTH < la < NORTH): continue
        x, y = px(lo, la)
        sec = SECTORS.get(name)
        is_station = bool(sec and sec[2] == 'sector station')
        r = (5.5 if is_station else 4.0) * SS
        d.ellipse([x - r, y - r, x + r, y + r], fill=INK['label'])
        d.ellipse([x - r - SS, y - r - SS, x + r + SS, y + r + SS],
                  outline=(20, 32, 40), width=int(1.2 * SS))
        if is_station:
            # a sector station held the operations room that fought the
            # sector, so it is drawn ringed
            rr = r + 4.5 * SS
            d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=INK['title'], width=int(1.6 * SS))
            r = rr
        marker_r[name] = r
        taken.append((x - r - 2 * SS, y - r - 2 * SS, x + r + 2 * SS, y + r + 2 * SS))
    # A sector station carries its letter in its own name rather than in a
    # badge beside it. The badge reserved space that pushed the name off
    # the map, and a ringed dot with no name is no use to anybody.
    missed = 0
    for name, la, lo in AIRFIELDS:
        if not (WEST < lo < EAST and SOUTH < la < NORTH): continue
        if name in SUPPRESS_NAMES: continue
        x, y = px(lo, la)
        sec = SECTORS.get(name)
        txt = name
        if sec and sec[2] == 'sector station' and sec[0]:
            txt = f'{name} ({sec[0]})'
        # clear of the marker, whatever size it is: a sector station's ring
        # is wider than a plain field's dot, and a fixed offset put every
        # one of their names inside their own ring, where nothing fits
        if not place(x, y, txt, f_af, INK['label'], marker_r.get(name, 4.0 * SS) + 4 * SS):
            missed += 1

    # then the towns, which give way to them
    # A town that is also one of the fields is drawn once, as the field.
    # Abbeville, Amiens, Arras, Lille, Caen, Le Havre, Chartres and Rennes
    # are all both, and the first German sheet printed each of them twice,
    # a couple of millimetres apart.
    _fieldnames = {n.upper() for n, _, _ in AIRFIELDS}
    for name, la, lo in TOWNS:
        if name.upper() in _fieldnames: continue
        if not (WEST < lo < EAST and SOUTH < la < NORTH): continue
        x, y = px(lo, la)
        if name == 'LONDON':
            place(x, y, name, f_grp, INK['label']); continue
        r = 3.2 * SS
        d.ellipse([x - r, y - r, x + r, y + r], outline=INK['coast'], width=int(1.4 * SS))
        place(x, y, name, f_town, INK['town'])

    for label, la, lo in GROUP_LABELS:
        x, y = px(lo, la)
        d.text((x, y), label, font=f_grp, fill=INK['boundary'])

    if a.side == 'lw':
        d.text((30 * SS, 24 * SS), 'LUFTFLOTTEN 2 UND 3', font=f_title, fill=INK['title'])
        d.text((30 * SS, 55 * SS), 'THE FIELDS ON THE CHANNEL FRONT, 1940', font=f_grp, fill=INK['title'])
        d.line([(30 * SS, 80 * SS), (352 * SS, 80 * SS)], fill=INK['title'], width=int(1.5 * SS))
        d.text((30 * SS, 90 * SS), 'EVERY FIELD NAMED IN THE CAMPAIGN ORDER OF BATTLE, PLACED FROM ITS OWN COORDINATES',
               font=f_tick, fill=INK['tick'])
    else:
        d.text((30 * SS, 24 * SS), 'FIGHTER COMMAND', font=f_title, fill=INK['title'])
        d.text((30 * SS, 55 * SS), 'SECTOR AND FIGHTER AIRFIELDS, 1940', font=f_grp, fill=INK['title'])
        d.line([(30 * SS, 80 * SS), (352 * SS, 80 * SS)], fill=INK['title'], width=int(1.5 * SS))
        d.text((30 * SS, 90 * SS), 'A RINGED FIELD IS A SECTOR STATION, LETTERED AS FIGHTER COMMAND LETTERED IT',
               font=f_tick, fill=INK['tick'])

    img = img.resize((W, H), Image.LANCZOS)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    img.save(a.out, quality=92)

    # Every station's place on the finished map, as a fraction of its width
    # and height, so the Room plots its rings from the same numbers the map
    # was drawn with. The order of battle spells a few of these its own way,
    # and the Room prefixes RAF, so each is written under every name it is
    # known by.
    ALIASES = {'Kirton in Lindsey': ['Kirton'], 'Martlesham Heath': ['Martlesham'],
               'Stapleford Tawney': ['Stapleford'], 'North Weald': ['Northweald']}
    stations = {}
    sectors_out = {}
    for name, sec in SECTORS.items():
        entry = {'letter': sec[0], 'station': sec[1], 'role': sec[2], 'note': sec[3]}
        for n in [name] + ALIASES.get(name, []):
            sectors_out[n] = entry
    for name, la, lo in AIRFIELDS:
        fx = (lo - WEST) / (EAST - WEST)
        fy = (NORTH - la) / (NORTH - SOUTH)
        for n in [name] + ALIASES.get(name, []):
            stations[n] = [round(fx, 5), round(fy, 5)]
            # only the RAF's are ever written "RAF Biggin Hill"
            if a.side == 'raf':
                stations['RAF ' + n] = [round(fx, 5), round(fy, 5)]
    proj = os.path.splitext(a.out)[0] + '.json'
    with open(proj, 'w', encoding='utf-8') as f:
        json.dump({'west': WEST, 'east': EAST, 'south': SOUTH, 'north': NORTH,
                   'width': W, 'height': H,
                   'note': 'x = (lon - west) / (east - west); y = (north - lat) / (north - south)',
                   'unnamed': sorted(SUPPRESS_NAMES),
                   'stations': dict(sorted(stations.items())),
                   'sectors': dict(sorted(sectors_out.items()))},
                  f, indent=1)
        f.write('\n')
    print(f'{a.out}: {W}x{H}, {drawn} land shapes, {len(AIRFIELDS)} airfields, {len(TOWNS)} towns, {missed} label(s) could not be placed clear')
    print(f'{proj}: {WEST} to {EAST} east, {SOUTH} to {NORTH} north')

if __name__ == '__main__':
    main()
