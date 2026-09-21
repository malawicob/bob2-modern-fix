#!/usr/bin/env python3
"""Read both squadron diary tables out of a campaign save.

Why this exists: the Squadron Room reads the RAF diary and knows nothing
about the German one, and a plan written on a guess about how to tell the
two apart was wrong in a way that would have failed silently. This proves
the layout against real saves instead.

    python3 dev/lw_diary_probe.py                     every save in SAVEGAME
    python3 dev/lw_diary_probe.py --save "path.BSR"

WHAT WAS FOUND, and how it was checked

The game keeps TWO tables, not one. From the disassembly notes in
modernization/BSR_FORMAT.md, Diary::CreditClaim splits on
"squadnum >= 0x9f", and the reference headers declare two sibling classes:
Diary::Squadron for the RAF and Diary::Gruppen for the Luftwaffe.

    RAF   24-byte records   squadnum 64..116    7 kill bins at +17
    LW    17-byte records   squadnum 159..231   6 kill bins at +11

The RAF pilot shoots at seven German types; the German pilot shoots at
six British ones. The Room's $KillBinsLW pads the British list to seven
with three "Other" entries, which is a guess and is wrong.

The German table is present in an RAF save, because the campaign tracks
both air forces. That is what let all of this be settled without anyone
flying a Luftwaffe career.

WHICH GRUPPE A RECORD IS

reference/SRC/H/NODEBOB.H declares the units in a fixed order after
SQ_LW_START, and

    squadnum = 160 + position in that list

Checked against a real save three times: 166 and 167 came out as I./JG 51
and II./JG 51, and both launch 36 aircraft, which is a fighter Gruppe;
slot 48 is a Stuka Gruppe and launches 30. The launched count is an
independent witness, so this is not circular.

The enum holds 72 units and the campaign's own order of battle holds 66,
because BOB2 dropped some Gruppen. So the map is built by MATCHING NAMES
between the two, never by position in either one alone.
"""
import struct, glob, os, re, json, argparse, sys

RAF_REC, RAF_KILLS, RAF_LO, RAF_HI = 24, 17, 64, 116
LW_REC, LW_KILLS, LW_LO, LW_HI = 17, 11, 159, 231
LW_BASE = 160

ROMAN = {'1': 'I', '2': 'II', '3': 'III'}

# The header abbreviates the Sturzkampfgeschwader as SG; the order of
# battle, and everyone else, writes StG. Reconciled here so the two files
# can be matched by name.
ARM = {'SG': 'StG', 'KGR': 'KGr'}

# an empty slot in either table
EMPTY = 0xFFFF


def lw_enum(path):
    """The Gruppen in the order the game numbers them."""
    with open(path, encoding='latin-1') as fh:
        src = fh.read()
    tail = src[src.index('SQ_LW_START'):]
    tail = tail[:tail.index('SQ_LW_END')] if 'SQ_LW_END' in tail else tail[:6000]
    out = []
    for arm, num, g in re.findall(r'SQ_([A-Z]+)_(\d+)_(\d)', tail):
        if g in ROMAN:
            out.append('%s/%s%s' % (ROMAN[g], ARM.get(arm, arm), num))
    return out


def raf_ok(b, p, n):
    """An RAF row: the u16 at +9 counts the rows up from zero.

    Far stronger than a byte-range test, and much faster: a false table
    would have to count correctly by accident.
    """
    idx = struct.unpack_from('<H', b, p + 9)[0]
    sq = b[p]
    if idx == n and RAF_LO <= sq <= RAF_HI:
        return 'real'
    if idx == EMPTY and sq == 0:
        return 'empty'
    return None


def lw_ok(b, p, n):
    """A German row. The u16 at +9 is NOT a row counter.

    It is the raid group the Gruppe is flying with, so two Gruppen on the
    same raid carry the same number, and an early version of this probe
    that expected it to count found nothing at all. Judge the row on what
    a Gruppe actually is instead: a launch of about thirty aircraft, and
    it cannot lose more than it put up.
    """
    sq = b[p]
    if sq == 0:
        return 'empty'
    launched, lost = b[p + 8], b[p + 1]
    if LW_LO <= sq <= LW_HI and 0 < launched <= 60 and lost <= launched:
        return 'real'
    return None


def find_table(b, rec, ok, start=40000, stop=None):
    """The run holding the most REAL records, not the longest run.

    Scoring on length alone picks the wrong thing: both tables sit in a
    field of zeros, empty slots are legitimate, so a few thousand bytes of
    nothing scores 2461 and beats the real table. What identifies a table
    is how many live squadrons are in it.
    """
    best = (0, 0, None)          # (real rows, total rows, offset)
    limit = min(len(b) - rec, stop or 250000)
    for o in range(start, limit):
        n = real = 0
        while True:
            p = o + n * rec
            if p + rec > len(b):
                break
            v = ok(b, p, n)
            if v is None:
                break
            if v == 'real':
                real += 1
            n += 1
        if real and (real, n) > (best[0], best[1]):
            best = (real, n, o)
    return best[1], best[2]


def rows(b, off, count, rec, killoff, nkills):
    out = []
    for n in range(count):
        p = off + n * rec
        sq = b[p]
        if not sq:
            continue
        out.append({
            'row': n, 'squadnum': sq,
            'aclost': b[p + 1], 'acdmg': b[p + 2], 'pilotslost': b[p + 3],
            'launched': b[p + 8],
            'kills': list(b[p + killoff:p + killoff + nkills]),
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--save')
    ap.add_argument('--dir', default='/mnt/d/Battle of Britain II/SAVEGAME')
    ap.add_argument('--nodebob', default='/home/patrick_millin/bob2/modernization/reference/SRC/H/NODEBOB.H')
    a = ap.parse_args()

    units = lw_enum(a.nodebob) if os.path.exists(a.nodebob) else []
    if units:
        print('%d Gruppen in the game\'s own order; squadnum = %d + position\n' % (len(units), LW_BASE))

    paths = [a.save] if a.save else sorted(glob.glob(os.path.join(a.dir, '*.BSR')))
    if not paths:
        print('No saves found.', file=sys.stderr)
        return 2

    for path in paths:
        b = open(path, 'rb').read()
        print('== %s  (%d bytes)' % (os.path.basename(path), len(b)))
        rn, ro = find_table(b, RAF_REC, raf_ok)
        print('   RAF table: %s' % ('%d rows at %d' % (rn, ro) if ro else 'not found'))
        if ro:
            r = rows(b, ro, rn, RAF_REC, RAF_KILLS, 7)
            print('     %d squadrons in the line: %s' % (len(r), sorted({x['squadnum'] for x in r})))

        # The German table sits IMMEDIATELY below the RAF one, and the
        # search has to be told so. Turned loose on the whole file a
        # 17-byte window finds two convincing frauds: a field of zeros
        # scoring 2461 empty rows, and a region at 40130 whose squadnums
        # step by exactly two with every other value identical, which is
        # some other structure aliasing. Both beat the real table on any
        # score that does not know where to look.
        lostart = max(40000, ro - 4000) if ro else 40000
        ln, lo = find_table(b, LW_REC, lw_ok, start=lostart,
                            stop=(ro if ro else None))
        print('   LW  table: %s' % ('%d rows at %d' % (ln, lo) if lo else 'not found'))
        if lo:
            r = rows(b, lo, ln, LW_REC, LW_KILLS, 6)
            for x in r[:12]:
                slot = x['squadnum'] - LW_BASE
                name = units[slot] if 0 <= slot < len(units) else '?'
                print('     %-10s squadnum %-4d launched %-3d lost %-3d kills %s'
                      % (name, x['squadnum'], x['launched'], x['aclost'], x['kills']))
            if len(r) > 12:
                print('     ... and %d more' % (len(r) - 12))
        print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
