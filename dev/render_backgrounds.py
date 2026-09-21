#!/usr/bin/env python3
"""Render and check the Squadron Room back stories.

Re-implements the fill logic of New-PilotBackground (BOB2_SquadronRoom.ps1) for
squadronroom/backgrounds.json: one random pick per {token}, the same pick reused
inside one story, list items expanded recursively (three levels), computed
tokens filled with plausible sample values.

    python3 dev/render_backgrounds.py              check, 60 renders per route
    python3 dev/render_backgrounds.py -n 200       more renders
    python3 dev/render_backgrounds.py --show 3     also print 3 stories per route
    python3 dev/render_backgrounds.py --show 3 --route halton

Exit status 1 if any story fails a rule.
"""
import argparse
import calendar
import json
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_JSON = os.path.join(HERE, '..', 'squadronroom', 'backgrounds.json')

FIRST, LAST = 'Patrick', 'Millin'
MIN_WORDS, MAX_WORDS = 200, 360
COMPUTED = {'first', 'last', 'name', 'born', 'year', 'age', 'place', 'joined', 'type',
            'unit', 'base', 'posted', 'hours', 'ontype', 'otu'}
RAF_ONLY = {'posted', 'hours', 'ontype', 'otu'}
MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
          'September', 'October', 'November', 'December']

RAF_UNITS = {
    'Spitfire': [('No. 610 Squadron', 'Biggin Hill'), ('No. 54 Squadron', 'Hornchurch'),
                 ('No. 609 Squadron', 'Middle Wallop'), ('No. 19 Squadron', 'Duxford')],
    'Hurricane': [('No. 32 Squadron', 'Biggin Hill'), ('No. 501 Squadron', 'Gravesend'),
                  ('No. 43 Squadron', 'Tangmere'), ('No. 85 Squadron', 'Debden')],
}
LW_UNITS = {
    'Bf 109 E': [('I./JG 26', 'Audembert'), ('III./JG 52', 'Coquelles'), ('II./JG 2', 'Beaumont-le-Roger')],
    'Bf 110': [('III./ZG 26', 'Arques'), ('I./ZG 2', 'Amiens-Glisy'), ('II./ZG 76', 'Abbeville')],
}
TOKEN = re.compile(r'\{(\w+)\}')


def render(side_key, side, route, rng, actype):
    """One story, the way the engine builds it."""
    who = route['who']
    lo, hi = side['born']['officer' if who == 'officer' else 'nco']
    year = rng.randint(lo, hi)
    jlo, jhi = route['joined']
    joined = rng.randint(jlo, jhi)
    minage = int(route['minage'])
    if year > joined - minage:
        year = joined - minage
    if year < joined - 24:
        year = joined - 24
    month = rng.randint(1, 12)
    day = rng.randint(1, calendar.monthrange(year, month)[1])
    is_lw = side_key == 'lw'
    unit, base = rng.choice((LW_UNITS if is_lw else RAF_UNITS)[actype])
    tok = {
        'first': FIRST, 'last': LAST, 'name': FIRST + ' ' + LAST,
        'born': '%d %s %d' % (day, MONTHS[month - 1], year), 'year': str(year),
        'age': str(1940 - year), 'place': rng.choice(side['places']),
        'joined': str(joined), 'type': actype, 'unit': unit, 'base': base,
    }
    if not is_lw:
        tok['posted'] = rng.choice(['July 1940', 'August 1940', 'September 1940'])
        tok['hours'] = str(150 + rng.randrange(61))
        tok['ontype'] = str(10 + rng.randrange(16))
        tok['otu'] = rng.choice(side['otu'][actype])
    picks = {}

    def fill(text, depth=0):
        def sub(m):
            k = m.group(1)
            if k in tok:
                return tok[k]
            if k in side['lists']:
                v = rng.choice(side['lists'][k])
                if depth < 3:
                    v = fill(v, depth + 1)
                tok[k] = v
                picks[k] = v
                return v
            return m.group(0)          # unknown: left in, so the check catches it
        return TOKEN.sub(sub, text)

    paras = [fill(t) for t in route['text']]
    closing = side.get('closing_crew') if (who == 'crew' and side.get('closing_crew')) else side.get('closing')
    if closing:
        paras.append(fill(closing))
    paras = [re.sub(r'\s{2,}', ' ', p).strip() for p in paras]
    return '\n\n'.join(paras), tok, paras


def sentences(par):
    return [s for s in re.split(r"(?<=[.?!])['\"]?\s+", par) if s]


def check_story(story, tok, paras, raw_paras):
    errs = []
    if '{' in story or '}' in story:
        errs.append('unfilled brace')
    if '\u2014' in story or '\u2013' in story or ' - ' in story or '--' in story:
        errs.append('dash used as punctuation')
    if re.search('[\u2018\u2019\u201c\u201d\u201a\u201e\u00ab\u00bb`\u00b4]', story):
        errs.append('smart quote')
    if (FIRST + ' ' + LAST) not in story:
        errs.append('name missing')
    if not paras[0].startswith(FIRST + ' ' + LAST):
        errs.append('first paragraph does not open with the name')
    if tok['born'] not in paras[0]:
        errs.append('birth date not in first paragraph')
    if tok['joined'] not in story:
        errs.append('joined year missing')
    if any('  ' in p for p in raw_paras):
        errs.append('double space')
    if re.search(r' [,.;:]', story) or re.search(r'[,;:][,.;:]', story) or '..' in story:
        errs.append('stray punctuation')
    for p in paras:
        if p[:1].islower():
            errs.append('paragraph starts lower case: ' + p[:30])
        for m in re.finditer(r"(?<![A-Z]o)(?<!Bf)[.?!]['\"]?\s+([a-z])", p):
            errs.append('sentence starts lower case: ...' + p[max(0, m.start() - 20):m.end() + 15])
    n = len(story.split())
    if n < MIN_WORDS or n > MAX_WORDS:
        errs.append('%d words (want %d to %d)' % (n, MIN_WORDS, MAX_WORDS))
    # a/an agreement
    for m in re.finditer(r'\b([Aa]n?) ([A-Za-z]+)', story):
        art, word = m.group(1).lower(), m.group(2).lower()
        vowel = word[0] in 'aeio' or (word[0] == 'u' and not word.startswith(('uni', 'use', 'usu')))
        if word.startswith(('hour', 'honour', 'heir')):
            vowel = True
        if word in ('one', 'once') or word.startswith('eu'):
            vowel = False
        if len(word) == 1 or word in ('der', 'and') or m.group(1) == 'A' and story[m.end(1)] == ',':
            continue
        if (art == 'an') != vowel:
            errs.append('a/an: "%s"' % m.group(0))
    # editorial: three sentences running that open on the same word
    for p in paras:
        firsts = [s.split()[0].strip(',;') for s in sentences(p) if s.split()]
        for i in range(len(firsts) - 2):
            if firsts[i] == firsts[i + 1] == firsts[i + 2]:
                errs.append('three sentences running open with "%s"' % firsts[i])
                break
    if story.count(LAST) > 5:
        errs.append('surname used %d times' % story.count(LAST))
    return errs, n


def he_pairs(paras):
    c = 0
    for p in paras:
        firsts = [s.split()[0] for s in sentences(p) if s.split()]
        c += sum(1 for a, b in zip(firsts, firsts[1:]) if a == b == 'He')
    return c


def check_structure(data):
    errs, warns = [], []
    want = {'raf': ['rafvr', 'halton', 'ssc', 'cranwell', 'uas'],
            'lw': ['nco109', 'off109', 'nco110', 'off110', 'bordfunker']}
    for sk in ('raf', 'lw'):
        side = data.get(sk)
        if not side:
            errs.append('%s: side missing' % sk)
            continue
        for key in ('born', 'places', 'lists', 'routes', 'closing'):
            if key not in side:
                errs.append('%s: "%s" missing' % (sk, key))
        if sk == 'lw' and 'closing_crew' not in side:
            errs.append('lw: closing_crew missing')
        if sk == 'raf' and 'otu' not in side:
            errs.append('raf: otu missing')
        ids = [r.get('id') for r in side.get('routes', [])]
        for rid in want[sk]:
            if rid not in ids:
                errs.append('%s: route "%s" missing' % (sk, rid))
        lists = side.get('lists', {})
        used = set()
        texts = []
        for r in side.get('routes', []):
            body = '\n'.join(r.get('text', []))
            texts.append((r.get('id'), body))
            if body.count('{joined}') != 1:
                errs.append('%s/%s: {joined} appears %d times, want 1' % (sk, r.get('id'), body.count('{joined}')))
            if len(r.get('text', [])) != 4:
                warns.append('%s/%s: %d paragraphs' % (sk, r.get('id'), len(r.get('text', []))))
        texts.append(('closing', side.get('closing', '')))
        texts.append(('closing_crew', side.get('closing_crew', '')))
        for name, items in lists.items():
            texts.append(('list ' + name, '\n'.join(items)))
            if not 6 <= len(items) <= 14:
                warns.append('%s: list "%s" has %d items' % (sk, name, len(items)))
            if len(set(items)) != len(items):
                errs.append('%s: list "%s" has a duplicate item' % (sk, name))
        for where, body in texts:
            for k in TOKEN.findall(body):
                used.add(k)
                if k in COMPUTED:
                    if sk == 'lw' and k in RAF_ONLY:
                        errs.append('lw/%s: {%s} is a British-only token' % (where, k))
                elif k not in lists:
                    errs.append('%s/%s: unknown token {%s}' % (sk, where, k))
        for name in lists:
            if name not in used:
                warns.append('%s: list "%s" is never used' % (sk, name))
    return errs, warns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-n', type=int, default=60, help='renders per route and type')
    ap.add_argument('--show', type=int, default=0, help='print this many stories per route')
    ap.add_argument('--route', default='', help='only this route id')
    ap.add_argument('--seed', type=int, default=1940)
    ap.add_argument('--json', default=DEFAULT_JSON)
    a = ap.parse_args()

    with open(a.json, encoding='utf-8') as f:
        raw = f.read()
    data = json.loads(raw)
    failures = 0
    if re.search('[\u2014\u2013\u2018\u2019\u201c\u201d]', raw.split('"raf"', 1)[1]):
        print('FAIL file: dash or smart quote somewhere in the templates')
        failures += 1
    serrs, warns = check_structure(data)
    for e in serrs:
        print('FAIL structure:', e)
    failures += len(serrs)
    for w in warns:
        print('note:', w)

    lo_all, hi_all, total = 10 ** 6, 0, 0
    for sk in ('raf', 'lw'):
        side = data[sk]
        for route in side['routes']:
            if a.route and route['id'] != a.route:
                continue
            if sk == 'raf':
                types = ['Spitfire', 'Hurricane']
            else:
                types = ['Bf 110' if route.get('type') == '110' else 'Bf 109 E']
            counts, pairs, seen = [], 0, {}
            shown = 0
            for actype in types:
                for i in range(a.n):
                    rng = random.Random('%s|%s|%s|%d|%d' % (sk, route['id'], actype, i, a.seed))
                    story, tok, paras = render(sk, side, route, rng, actype)
                    raw_paras = paras
                    errs, n = check_story(story, tok, paras, raw_paras)
                    counts.append(n)
                    pairs += he_pairs(paras)
                    total += 1
                    for e in errs:
                        seen.setdefault(e, story)
                    failures += len(errs)
                    if shown < a.show and i < (a.show + len(types) - 1) // len(types):
                        shown += 1
                        print('\n===== %s / %s / %s  (%d words) =====\n' % (sk, route['id'], actype, n))
                        print(story)
            print('%-4s %-11s %4d stories  %3d to %3d words  mean %3d  "He. He" joins per story %.2f'
                  % (sk, route['id'], len(counts), min(counts), max(counts),
                     sum(counts) // len(counts), pairs / len(counts)))
            lo_all, hi_all = min(lo_all, min(counts)), max(hi_all, max(counts))
            for e, story in seen.items():
                print('  FAIL %s: %s' % (route['id'], e))
                if a.show == 0:
                    print('    in: ' + story.replace('\n\n', ' / ')[:400] + ' ...')
    print('\n%d stories, %d to %d words.' % (total, lo_all, hi_all))
    if failures:
        print('FAILED: %d problem(s).' % failures)
        return 1
    print('PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
