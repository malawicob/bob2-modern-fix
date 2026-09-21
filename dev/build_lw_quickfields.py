#!/usr/bin/env python3
"""Spread the newly dressed airfields across the quick missions.

    python3 dev/build_lw_quickfields.py

The Basic Training and Familiarisation missions let you take off from a
Luftwaffe airfield, and the I.D. list offers four: Marck, Abbeville,
Wissant and Le Havre. Those are four of the six German fields that
already had scenery, so they are the four that test nothing new.

The list cannot be made longer. H/SQUICK1.H declares

    FixString   targtypeIDs[4];
    UniqueID    targets[4][4];

so four is the size of the array, not a choice, and the shipped
quick.dat agrees: nine identical quartets of Marck, Abbeville, Wissant
and Le Havre, 4-byte little endian UIDs, one per mission at a stride of
1134 bytes. With the Dunkirk pack installed there are ten.

What can be changed is WHICH four, and there are nine of them all
spending their four slots on the same fields. Give each mission a
different quartet and 36 airfields become reachable instead of 4, or 40
with the Dunkirk pack.

The order is worked out, not typed. Fighter fields come first, because
that is where a Bf 109 career actually flies from and so what anybody
testing this wants to see, and within each group the fields nearest
England come first, since those are the ones in the campaign. The
UID for each is read from the game's own UIDVALS.G.
"""
import re, os, sys, json, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# The four the game ships in every one of these missions.
STOCK = ['Marck', 'Abbeville', 'Wissant', 'LeHarve']


def read_uids(path):
    u = {}
    for ln in open(path, encoding='latin-1'):
        m = re.match(r'\s*UID_AF_(\w+)\s*=\s*(0x[0-9a-fA-F]+)', ln)
        if m:
            u[m.group(1)] = int(m.group(2), 16)
    return u


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--uidvals', default='/home/patrick_millin/bob2/modernization/reference/SRC/H/UIDVALS.G')
    ap.add_argument('--man',  default=os.path.join(ROOT, 'dispersal/lw-airfields.json'))
    ap.add_argument('--oob',  default=os.path.join(ROOT, 'squadronroom/lw/oob.json'))
    ap.add_argument('--geo',  default=os.path.join(ROOT, 'squadronroom/lw/fields.json'))
    ap.add_argument('--out',  default=os.path.join(ROOT, 'dispersal/lw-quickfields.json'))
    a = ap.parse_args()

    if not os.path.exists(a.uidvals):
        print('no UIDVALS.G at %s' % a.uidvals, file=sys.stderr)
        return 1
    uids = read_uids(a.uidvals)
    man = json.load(open(a.man, encoding='utf-8'))
    oob = json.load(open(a.oob, encoding='utf-8'))
    geo = json.load(open(a.geo, encoding='utf-8'))

    types = {}
    for r in oob:
        types.setdefault(r['field'], []).append(r['type'])

    rows = []
    for f in man['fields']:
        uid = uids.get(f['uid'])
        if uid is None:
            print('  ! %s has no UID_AF_ value' % f['field'], file=sys.stderr)
            continue
        t = types.get(f['field'], [])
        fighter = any(x.startswith('Bf') for x in t)
        lat = (geo.get(f['field']) or [0, 0])[0]
        rows.append({'field': f['field'], 'uid': uid, 'uid_name': f['uid'],
                     'fighter': fighter, 'lat': lat,
                     'based': sorted(set(t))})
    # fighters first, then north to south: nearest England is most used
    rows.sort(key=lambda r: (not r['fighter'], -r['lat']))

    quartets = [rows[i:i + 4] for i in range(0, len(rows), 4)]
    while quartets and len(quartets[-1]) < 4:            # only whole quartets fit
        short = quartets.pop()
        for r in short:
            print('  no slot for %s' % r['field'])

    out = {
        'stock': [{'name': n, 'uid': uids[n]} for n in STOCK],
        'quartets': [{'fields': [q['field'] for q in grp],
                      'uids': [q['uid'] for q in grp],
                      'based': sorted({b for q in grp for b in q['based']})}
                     for grp in quartets],
    }
    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    for i, grp in enumerate(quartets, 1):
        print('  %2d  %s' % (i, ', '.join('%s (%04x)' % (q['field'], q['uid']) for q in grp)))
    print('%d quartets, %d airfields -> %s' % (len(quartets), len(quartets) * 4, a.out))
    print('  the game has 9 of these missions, or 10 with the Dunkirk pack;')
    print('  quartets beyond that many are simply not used.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
