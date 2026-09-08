#!/usr/bin/env python3
"""Take the artwork backdrops out of the menu rescale.

BOB2's menus are 154 dialog templates, and the rescale enlarges every
coordinate in them. Eleven of those dialogs hold NO CONTROLS at all:
they are frames the game paints its own artwork into, and dialog 143 is
805 x 604 pixels, exactly four by three. Enlarging such a frame moves
nothing whose text needed to be bigger -- the whole point of the rescale
-- and grows the frame away from the picture, which the game still draws
at its own fixed size. The photograph then sits in a sea of white with
torn edges, which is what a player sees on the loading screen.

This edits the four shipped patch files in place, dropping only the
edits that land on a control-free dialog. Every other edit is left byte
for byte as it was, so the tested rescale of the other 143 dialogs is
untouched. The output checksum in each header is recomputed, because the
tool that applies these verifies it.

  python3 dev/menuscale_leave_backdrops.py \
      --exe "D:/Battle of Britain II/Bob.exe.unscaled"
"""
import argparse, hashlib, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def read_pe(path):
    d = open(path, 'rb').read()
    e_lfanew = struct.unpack_from('<I', d, 0x3C)[0]
    assert d[e_lfanew:e_lfanew + 4] == b'PE\0\0', 'not a PE'
    coff = e_lfanew + 4
    nsec, = struct.unpack_from('<H', d, coff + 2)
    optsz, = struct.unpack_from('<H', d, coff + 16)
    opt = coff + 20
    magic, = struct.unpack_from('<H', d, opt)
    dd = opt + (96 if magic == 0x10b else 112)
    rsrc_rva, _ = struct.unpack_from('<II', d, dd + 2 * 8)
    secs, so = [], opt + optsz
    for _ in range(nsec):
        vsz, va, rsz, raw = struct.unpack_from('<IIII', d, so + 8)
        secs.append((va, vsz, raw, rsz))
        so += 40

    def rva2off(rva):
        for va, vsz, raw, rsz in secs:
            if va <= rva < va + max(vsz, rsz):
                return raw + (rva - va)
        return None
    return d, rsrc_rva, rva2off


def walk(d, base, off, path=()):
    nname, nid = struct.unpack_from('<HH', d, base + off + 12)
    ent = base + off + 16
    for _ in range(nname + nid):
        nameid, offset = struct.unpack_from('<II', d, ent)
        ent += 8
        if offset & 0x80000000:
            yield from walk(d, base, offset & 0x7fffffff, path + (nameid,))
        else:
            data_rva, size = struct.unpack_from('<II', d, base + offset)
            yield path + (nameid,), data_rva, size


def _sz_or_ord(d, o):
    v, = struct.unpack_from('<H', d, o)
    if v == 0xFFFF:
        return o + 4
    while True:
        c, = struct.unpack_from('<H', d, o)
        o += 2
        if c == 0:
            return o


def dialog_fields(d, off):
    """Geometry and font field offsets, and how many controls it holds."""
    o = off
    ver, sig = struct.unpack_from('<HH', d, o)
    ex = (ver == 1 and sig == 0xFFFF)
    if ex:
        style, = struct.unpack_from('<I', d, off + 12)
        o += 16
        n, = struct.unpack_from('<H', d, o); o += 2
        geom = o; o += 8
    else:
        style, = struct.unpack_from('<I', d, o)
        o += 8
        n, = struct.unpack_from('<H', d, o); o += 2
        geom = o; o += 8
    for _ in range(3):
        o = _sz_or_ord(d, o)
    font = None
    if style & 0x40:                       # DS_SETFONT
        font = o
    return n, geom, font


def backdrop_fields(exe):
    d, rsrc_rva, rva2off = read_pe(exe)
    base = rva2off(rsrc_rva)
    fields, ids = set(), []
    for path, data_rva, _size in walk(d, base, 0):
        if path[0] != 5:                   # RT_DIALOG
            continue
        n, geom, font = dialog_fields(d, rva2off(data_rva))
        if n:
            continue
        ids.append(path[1])
        for i in range(4):
            fields.add(geom + 2 * i)
        if font is not None:
            fields.add(font)
    return fields, sorted(ids), d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--exe', default='D:/Battle of Britain II/Bob.exe.unscaled')
    ap.add_argument('--dir', default=os.path.join(os.path.dirname(HERE), 'menuscale'))
    a = ap.parse_args()

    fields, ids, orig = backdrop_fields(a.exe)
    print('control-free dialogs left alone: %s' % (ids,))

    for name in ('102', '110', '125', '140'):
        path = os.path.join(a.dir, 'scale%s.bin' % name)
        p = bytearray(open(path, 'rb').read())
        assert p[:8] == b'BOB2MSC1', path
        count = struct.unpack_from('<I', p, 12)[0]
        kept, dropped = [], 0
        o = 48
        for _ in range(count):
            off, exp, new = struct.unpack_from('<IHH', p, o); o += 8
            if off in fields:
                dropped += 1
                continue
            kept.append((off, exp, new))

        buf = bytearray(orig)
        for off, exp, new in kept:
            assert struct.unpack_from('<H', buf, off)[0] == exp, 'expectation failed'
            struct.pack_into('<H', buf, off, new)
        out_md5 = hashlib.md5(bytes(buf)).digest()

        head = bytearray(p[:48])
        struct.pack_into('<I', head, 12, len(kept))
        head[32:48] = out_md5
        body = b''.join(struct.pack('<IHH', *e) for e in kept)
        open(path, 'wb').write(bytes(head) + body)
        print('  scale%s: dropped %d, kept %d, new md5 %s'
              % (name, dropped, len(kept), out_md5.hex()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
