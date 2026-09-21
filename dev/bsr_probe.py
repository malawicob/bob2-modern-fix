#!/usr/bin/env python3
"""Find where a campaign save keeps the player's squadron.

    python3 dev/bsr_probe.py "D:/Battle of Britain II/SAVEGAME/Millin.bsR" \\
                             "path/to/a/save/from/another/squadron.bsR"

WHAT IS KNOWN AND WHAT IS NOT

The squadron is in the file. CFiling::SaveGame writes bos<<Miss_Man,
Miss_Man.camp is a Campaign, and Campaign carries

    SWord playersquadron, playeracnum;        MISSMAN2.H:302

with the streaming macros in declaration order, so both sit at a stable
offset. That is where knowledge stops. The offset is not pinned, and the
two saves on the development machine are both 32 Squadron, so they cannot
pin it: the "candidate career ints" at 84..99 that BSR_FORMAT.md flags
read identically in both, which is consistent with the squadron living
there and proves nothing.

Pinning it needs ONE save from a different squadron. Given two or more
saves, this prints every byte in the header region that differs, and the
little-endian int16 at every even offset in 84..99, and flags any that
equals a squadron enum value from the game's own NODEBOB.H. If the byte
that differs between a 32 Squadron save and a 501 Squadron save is the
one whose values are SQ_BR_32 and SQ_BR_501, that is the offset.

THE ENUM CANNOT BE COUNTED BY HAND. SQ_BR_START=PT_BADMAX sits mid-enum,
so the RAF squadrons are PT_BADMAX-relative, and the Luftwaffe builder
already found the save uses 160 for SQ_LW_START where the source comment
says 72. So the enum is parsed here and its values are printed as
candidates, not taken as gospel; the save is the authority.
"""
import argparse, os, re, struct, sys

NODEBOB = '/home/patrick_millin/bob2/modernization/reference/SRC/H/NODEBOB.H'
FLYINIT = '/home/patrick_millin/bob2/modernization/reference/SRC/H/FLYINIT.H'
HEADER_END = 300          # the small fields live well inside this
CANDIDATES = range(84, 100, 2)


def read(path):
    b = open(path, 'rb').read()
    if b[1:20] != b'Rowan Savegame: V 0':
        raise SystemExit('%s: not a campaign save (no banner)' % path)
    return b


def ident(b):
    name = b[100:121].split(b'\0')[0].decode('latin-1', 'replace')
    secs = struct.unpack_from('<I', b, 57)[0]
    return name, secs


def enum_values():
    """SQ_* names to values, honouring '= name' and '= N'. Best effort."""
    vals = {}
    try:
        txt = open(FLYINIT, encoding='latin-1', errors='ignore').read()
        cur = -1
        for ln in txt[txt.find('PT_'):txt.find('PT_BADMAX') + 20].splitlines():
            ln = ln.split('//')[0].strip().rstrip(',')
            m = re.match(r'([A-Za-z_]\w*)\s*(?:=\s*([A-Za-z_]\w*|\d+))?$', ln)
            if not m:
                continue
            nm, rhs = m.group(1), m.group(2)
            if rhs is None:
                cur += 1
            elif rhs.isdigit():
                cur = int(rhs)
            else:
                cur = vals.get(rhs, cur)
            vals[nm] = cur
        txt = open(NODEBOB, encoding='latin-1', errors='ignore').read()
        i = txt.find('SQ_ZERO')
        cur = -1
        for ln in txt[i:txt.find('SQ_LW_START', i) + 80].splitlines():
            ln = ln.split('//')[0].strip().rstrip(',')
            m = re.match(r'([A-Za-z_]\w*)\s*(?:=\s*([A-Za-z_]\w*|\d+))?$', ln)
            if not m:
                continue
            nm, rhs = m.group(1), m.group(2)
            if rhs is None:
                cur += 1
            elif rhs.isdigit():
                cur = int(rhs)
            else:
                cur = vals.get(rhs, cur)
            vals[nm] = cur
    except OSError:
        pass
    return {k: v for k, v in vals.items() if k.startswith('SQ_')}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('saves', nargs='+')
    a = ap.parse_args()
    if len(a.saves) < 2:
        print('give at least two saves; one of a different squadron is what pins it',
              file=sys.stderr)
        return 1
    bufs = [read(p) for p in a.saves]
    for p, b in zip(a.saves, bufs):
        nm, secs = ident(b)
        print('%-40s %8d bytes  pilot %-10s date+%d' % (os.path.basename(p), len(b), nm, secs))
    sq = enum_values()
    byval = {}
    for k, v in sq.items():
        if isinstance(v, int) and k.startswith('SQ_BR_'):
            byval.setdefault(v, []).append(k)
    print()
    print('int16 at each candidate offset (84..99), per save; * = equals an SQ_BR_ enum value')
    print('  off   ' + '  '.join('%10s' % os.path.basename(p)[:10] for p in a.saves) + '   differs?')
    for off in CANDIDATES:
        vals = [struct.unpack_from('<h', b, off)[0] for b in bufs]
        flag = '  <-- differs' if len(set(vals)) > 1 else ''
        cells = []
        for v in vals:
            tag = '*' if v in byval else ' '
            cells.append('%9d%s' % (v, tag))
        print('  %3d   ' % off + '  '.join(cells) + flag)
    print()
    n = min(len(b) for b in bufs)
    diff = [i for i in range(40, min(n, HEADER_END)) if len({b[i] for b in bufs}) > 1]
    runs = []
    for i in diff:
        if runs and i == runs[-1][1] + 1:
            runs[-1][1] = i
        else:
            runs.append([i, i])
    print('bytes that differ in the header region 40..%d: %d, as %d run(s)' % (HEADER_END, len(diff), len(runs)))
    for s, e in runs:
        print('  %4d..%-4d  ' % (s, e) + '  '.join(b[s:e + 1][:6].hex().ljust(12) for b in bufs))
    print()
    if byval:
        print('enum values this parse gives (best effort, the save is the authority):')
        for v in sorted(byval)[:6]:
            print('  %4d = %s' % (v, ', '.join(byval[v])))
        for k in ('SQ_BR_32', 'SQ_BR_501', 'SQ_LW_START'):
            if k in sq:
                print('  %-12s = %s' % (k, sq[k]))
    print()
    print('READING IT: the offset whose int16 differs between two saves of different')
    print('squadrons, and whose values match those squadrons\' enum, is playersquadron.')
    print('playeracnum is the SWord immediately after it. Two saves of the SAME')
    print('squadron cannot pin either; that is why the machine\'s own two could not.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
