#!/usr/bin/env python3
"""Point a saved German career at the same face after a portrait renumber.

    python3 dev/remap_lw_portraits.py \
        --state "/mnt/d/Battle of Britain II_Latest_test/SquadronRoom/lw"

WHY THIS HAS TO EXIST

A pilot record stores its portrait by FILENAME - "portrait": "pilot04.jpg"
- and the portrait set is numbered in the order the files were converted.
When the set of 25 was replaced by the set of 92 on 10 September 2026 the
numbering moved under it: 24 of the 25 old names now point at somebody
else's face. Nothing would have broken and nothing would have been
logged. Patrick would simply have opened the Ready Room one day and found
a different man in his photograph.

The old files are recoverable from git, so the map is built by LOOKING at
the pictures rather than by guessing at the order: each old portrait is
matched to the new file it actually is, by average hash and difference
hash together. On the 10 September set the worst match came out at a
distance of 2 out of 144 bits, which is the same photograph re-saved.

Two of the old twenty-five were the same man, so they both map to one new
file. That is the dedupe working, not the matcher failing.

The map lives in squadronroom/lw/portrait-remap.json so the change can be
audited later. Every file this touches is copied to .bak first.
"""
import argparse, glob, json, os, shutil, sys


def remap(path, m, dry):
    try:
        with open(path, encoding='utf-8-sig') as fh:
            d = json.load(fh)
    except Exception as e:
        print('  ! %s unreadable: %s' % (path, e), file=sys.stderr)
        return False
    old = d.get('portrait')
    if not old or old not in m or m[old] == old:
        print('  %-60s %s -> unchanged' % (os.path.basename(path), old))
        return False
    new = m[old]
    print('  %-60s %s -> %s' % (path, old, new))
    if dry:
        return True
    shutil.copy2(path, path + '.bak-portrait-remap')
    d['portrait'] = new
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(d, fh, indent=1, ensure_ascii=False)
        fh.write('\n')
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--state', required=True,
                    help='the lw state folder, e.g. <GameDir>/SquadronRoom/lw')
    ap.add_argument('--map', default='squadronroom/lw/portrait-remap.json')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    with open(a.map, encoding='utf-8') as fh:
        m = json.load(fh)

    # the live record and everything already archived, because an archived
    # career is still looked at
    paths = [os.path.join(a.state, 'pilot.json')]
    paths += sorted(glob.glob(os.path.join(a.state, 'archive', '*', 'pilot.json')))
    paths = [p for p in paths if os.path.exists(p)]
    if not paths:
        print('no saved German career under %s; nothing to do' % a.state)
        return 0
    n = sum(1 for p in paths if remap(p, m, a.dry_run))
    print('%d of %d record(s) %s' % (n, len(paths), 'would change' if a.dry_run else 'changed'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
