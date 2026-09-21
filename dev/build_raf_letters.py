#!/usr/bin/env python3
"""Which code letter a squadron's aeroplanes wear, from the game's rules.

    python3 dev/build_raf_letters.py --out squadronroom/raf-letters.json

WHY THIS EXISTS

33lima created a pilot in 501 Squadron, the Room told him he was in
SD-R, and he took off in SD-T. He was right that something had gone
awry, and it was the Room: Invoke-SquadronSubmit picked his letter with

    $letter = ('A','B','D','E', ... | Get-Random)

so it was never going to agree with the game about anything.

The game does not choose at random. MultiSkin\\Hurri_PlaneID_Letter.ms
and Spit_PlaneID_Letter.ms map the aeroplane's PLANEID to a letter, the
same way Me109_PlaneID_1.ms does for the 109s. 21 squadrons have their
own table, keyed on unit == Sq"GZ" and the like; everyone else falls
through to a generic one.

501's code is SD and it is not among the 21, so it takes the generic
table, where planeid 0 is T. 33lima was leading the squadron, which
makes him aeroplane 0, and T is exactly what he flew.

WHAT THIS CANNOT DO

Tell you which planeid a man will be given. That is the game's to
decide when it builds the flight, and nothing in the save has been shown
to carry it. What the Room can do is stop inventing a letter: a squadron
leader is aeroplane 0 and gets 0's letter, and anyone else is shown the
squadron's table rather than a promise.
"""
import argparse, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def read_rules(path):
    """planeid -> letter, per squadron code, plus the generic fallback."""
    per, generic = {}, {}
    if not os.path.exists(path):
        return per, generic
    for ln in open(path, encoding='latin-1', errors='ignore'):
        t = ln.split('#')[0].strip()
        if not t.lower().startswith('use'):
            continue
        m = re.match(r'use\s+(.+?)\.dds\s*,', t, re.I)
        if not m:
            continue
        tex = os.path.basename(m.group(1).replace('\\', '/')).strip()
        # the letter tiles are named for the letter and nothing else
        if not re.fullmatch(r'[A-Z]', tex, re.I):
            continue
        cond = t.split(' if ', 1)[1] if ' if ' in t else ''
        pids = [int(x) for x in re.findall(r'planeid\s*==\s*(\d+)', cond)]
        codes = re.findall(r'unit\s*==\s*Sq"([A-Z0-9]+)"', cond)
        if not pids:
            continue
        for pid in pids:
            if codes:
                for c in codes:
                    per.setdefault(c, {}).setdefault(pid, tex.upper())
            else:
                generic.setdefault(pid, tex.upper())
    return per, generic


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ms',  default='/mnt/d/Battle of Britain II_Latest_test/MultiSkin')
    ap.add_argument('--oob', default=os.path.join(ROOT, 'squadronroom/oob.json'))
    ap.add_argument('--out', default=os.path.join(ROOT, 'squadronroom/raf-letters.json'))
    a = ap.parse_args()

    out = {'note': ("Which code letter each aeroplane of a squadron wears, read from "
                    "MultiSkin's Hurri_PlaneID_Letter.ms and Spit_PlaneID_Letter.ms. "
                    "Keyed on planeid: the squadron leader is aeroplane 0. A squadron "
                    "with no table of its own uses 'generic'. Built by "
                    "dev/build_raf_letters.py."),
           'hurricane': {}, 'spitfire': {}, 'generic': {}}
    for kind, fn in (('hurricane', 'Hurri_PlaneID_Letter.ms'),
                     ('spitfire',  'Spit_PlaneID_Letter.ms')):
        per, generic = read_rules(os.path.join(a.ms, fn))
        out[kind] = {c: {str(k): v for k, v in sorted(d.items())} for c, d in sorted(per.items())}
        if generic and not out['generic']:
            out['generic'] = {str(k): v for k, v in sorted(generic.items())}

    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    nh, ns = len(out['hurricane']), len(out['spitfire'])
    print('%d Hurricane squadrons and %d Spitfire squadrons have their own letters'
          % (nh, ns))
    print('  generic table: %s' % ', '.join('%s=%s' % (k, v)
                                            for k, v in sorted(out['generic'].items(),
                                                               key=lambda kv: int(kv[0]))[:8]))
    print('  aeroplane 0, which is the squadron leader, wears %s'
          % out['generic'].get('0', '?'))
    print('-> %s' % a.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
