#!/usr/bin/env python3
"""Fetch elevation for the sector map's extent and save it as a plain grid.

Run this before make_sector_map.py; the map falls back to flat colour when
the file is absent, so it is not needed to draw a usable map, only a
good-looking one. Roughly 140 tiles, a minute over a normal connection.

Natural Earth's shaded relief is a world raster at two arc-minutes, which
works out at 576 pixels across the area this map covers: far too coarse
to enlarge to a 2560-pixel map. These are Terrarium elevation tiles, which
are public and need no key, at a little over 3,500 pixels across the same
ground.

    python3 dev/fetch_relief.py --out /tmp/relief.npz
"""
import math, os, io, json, argparse, urllib.request, concurrent.futures
import numpy as np

WEST, EAST, SOUTH, NORTH = -5.6, 4.0, 50.0, 53.8
ZOOM = 9
URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'

def lon2x(lon, z): return (lon + 180.0) / 360.0 * (1 << z)
def lat2y(lat, z):
    r = math.radians(lat)
    return (1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * (1 << z)
def y2lat(y, z):
    n = math.pi - 2.0 * math.pi * y / (1 << z)
    return math.degrees(math.atan(math.sinh(n)))

def get(args):
    z, x, y = args
    from PIL import Image
    for attempt in range(4):
        try:
            with urllib.request.urlopen(URL.format(z=z, x=x, y=y), timeout=30) as r:
                return (x, y, np.asarray(Image.open(io.BytesIO(r.read())).convert('RGB'), dtype=np.float32))
        except Exception:
            if attempt == 3: return (x, y, None)
    return (x, y, None)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    a = ap.parse_args()

    x0, x1 = int(math.floor(lon2x(WEST, ZOOM))), int(math.floor(lon2x(EAST, ZOOM)))
    y0, y1 = int(math.floor(lat2y(NORTH, ZOOM))), int(math.floor(lat2y(SOUTH, ZOOM)))
    tiles = [(ZOOM, x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
    print(f'{len(tiles)} tiles at zoom {ZOOM}: x {x0}-{x1}, y {y0}-{y1}')

    tw, th = (x1 - x0 + 1) * 256, (y1 - y0 + 1) * 256
    merc = np.zeros((th, tw), dtype=np.float32)
    got = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for x, y, arr in ex.map(get, tiles):
            if arr is None: continue
            elev = arr[:, :, 0] * 256.0 + arr[:, :, 1] + arr[:, :, 2] / 256.0 - 32768.0
            merc[(y - y0) * 256:(y - y0 + 1) * 256, (x - x0) * 256:(x - x0 + 1) * 256] = elev
            got += 1
    print(f'{got} tiles fetched, mosaic {tw}x{th}')

    # Web Mercator to the plain latitude/longitude grid the map is drawn on
    OW, OH = tw, int(tw * (NORTH - SOUTH) / (EAST - WEST))
    lons = WEST + (np.arange(OW) + 0.5) / OW * (EAST - WEST)
    lats = NORTH - (np.arange(OH) + 0.5) / OH * (NORTH - SOUTH)
    sx = np.clip(((lon2x(lons, ZOOM) - x0) * 256).astype(np.int32), 0, tw - 1)
    my = np.array([lat2y(la, ZOOM) for la in lats])
    sy = np.clip(((my - y0) * 256).astype(np.int32), 0, th - 1)
    out = merc[sy[:, None], sx[None, :]]
    np.savez_compressed(a.out, elev=out.astype(np.float32),
                        west=WEST, east=EAST, south=SOUTH, north=NORTH)
    land = out > 0
    print(f'{a.out}: {OW}x{OH}, land {land.mean()*100:.0f}% of the frame, '
          f'highest {out.max():.0f} m')

if __name__ == '__main__':
    main()
