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
    a = ap.parse_args()
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
    for pts in BOUNDARIES:
        dashed([px(lo, la) for la, lo in pts], INK['boundary'], int(2 * SS))

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
    for name, la, lo in AIRFIELDS:
        if not (WEST < lo < EAST and SOUTH < la < NORTH): continue
        x, y = px(lo, la)
        r = 4.0 * SS
        d.ellipse([x - r, y - r, x + r, y + r], fill=INK['label'])
        d.ellipse([x - r - SS, y - r - SS, x + r + SS, y + r + SS],
                  outline=(20, 32, 40), width=int(1.2 * SS))
        taken.append((x - r - 2 * SS, y - r - 2 * SS, x + r + 2 * SS, y + r + 2 * SS))
    missed = 0
    for name, la, lo in AIRFIELDS:
        if not (WEST < lo < EAST and SOUTH < la < NORTH): continue
        x, y = px(lo, la)
        if not place(x, y, name, f_af, INK['label']): missed += 1

    # then the towns, which give way to them
    for name, la, lo in TOWNS:
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

    d.text((30 * SS, 24 * SS), 'FIGHTER COMMAND', font=f_title, fill=INK['title'])
    d.text((30 * SS, 55 * SS), 'SECTOR AND FIGHTER AIRFIELDS, 1940', font=f_grp, fill=INK['title'])
    d.line([(30 * SS, 80 * SS), (352 * SS, 80 * SS)], fill=INK['title'], width=int(1.5 * SS))

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
    for name, la, lo in AIRFIELDS:
        fx = (lo - WEST) / (EAST - WEST)
        fy = (NORTH - la) / (NORTH - SOUTH)
        for n in [name] + ALIASES.get(name, []):
            stations[n] = [round(fx, 5), round(fy, 5)]
            stations['RAF ' + n] = [round(fx, 5), round(fy, 5)]
    proj = os.path.splitext(a.out)[0] + '.json'
    with open(proj, 'w', encoding='utf-8') as f:
        json.dump({'west': WEST, 'east': EAST, 'south': SOUTH, 'north': NORTH,
                   'width': W, 'height': H,
                   'note': 'x = (lon - west) / (east - west); y = (north - lat) / (north - south)',
                   'stations': dict(sorted(stations.items()))},
                  f, indent=1)
        f.write('\n')
    print(f'{a.out}: {W}x{H}, {drawn} land shapes, {len(AIRFIELDS)} airfields, {len(TOWNS)} towns, {missed} label(s) could not be placed clear')
    print(f'{proj}: {WEST} to {EAST} east, {SOUTH} to {NORTH} north')

if __name__ == '__main__':
    main()
