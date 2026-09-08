#!/usr/bin/env python3
"""Read combat claims, with their dates, out of the harvested biographies.

NOT ACCURATE ENOUGH TO USE. Measured against No. 32 Squadron, whose
claims were researched by hand from the same pages, this gets 49 per cent
of what it produces right and finds 43 per cent of what is there. Reading
only sentences that name one aircraft and one date lifts precision to 80
per cent but finds 8 per cent of the claims. One wrong victory in five,
against a named man, is worse than a blank column.

Why it fails: the prose chains claims off one date, in either order, and
an outcome word can govern one aircraft or all of them.

    "two Ju88s, a Do17 and another Do17 shared, on the 16th a Me109, a
     Me110 and a Ju88 destroyed"

Deciding which of those five aircraft the word "shared" governs, and
which date each belongs to, is the whole problem, and no rule tried here
does it reliably. It is kept because the harvest and the date handling
are sound and worth building on, and because the measurement is worth
having on record.

The prose runs them together, chained off one opening date:

    On 20th July 1940 Crossley claimed a Me109 destroyed and shared a
    Me110, on the 25th he got a probable Me109, on 12th August two Me109s
    destroyed, on the 15th two Ju88s, a Do17 and another Do17 shared...

So the text is cut at every date, and each piece is read for aircraft
types, how many of each, and whether they were destroyed, shared,
probable or damaged. A piece that names no kind is a destroyed claim,
which is how this prose is written.

Claims are attributed to whichever squadron the man was with on the day,
using the postings already harvested. Nothing is invented: a claim with
no date is dropped, and one that falls outside his service is dropped.

    python3 dev/bbm_claims.py --bbm ~/bob2/bbm
"""
import re, os, json, argparse, datetime, collections

MONTHS = {m: i + 1 for i, m in enumerate(
    ['january','february','march','april','may','june','july','august',
     'september','october','november','december'])}
MON3 = {m[:3]: i + 1 for i, m in enumerate(MONTHS)}
MONRE = (r'(January|February|March|April|May|June|July|August|September|October|'
         r'November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)')

# a full date, or a bare day that carries the month from the one before it
FULL = re.compile(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+' + MONRE + r'(?:\s+(\d{4}))?', re.I)
# the other way round: "on May 18th", "on July 19th, 20th and 29th"
MONFIRST = re.compile(r'\b' + MONRE + r'\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(\d{4}))?', re.I)
# an aircraft claimed BEFORE its date: "claimed a Me109 on May 18th, a
# Me110 on the 23rd". Whole biographies are written this way round, and
# reading only the other order missed every claim on them.
TYPE_THEN_DATE = None  # built below, once TYPE_RE exists
BARE = re.compile(r'\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)?\b', re.I)

# what the Luftwaffe was flying, as these pages spell it
TYPES = [
    (r'\bMe\s?109s?\b|\bBf\s?109s?\b', 'Bf 109'), (r'\bMe\s?110s?\b|\bBf\s?110s?\b', 'Bf 110'),
    (r'\bJu\s?87s?\b', 'Ju 87'), (r'\bJu\s?88s?\b', 'Ju 88'), (r'\bJu\s?52s?\b', 'Ju 52'),
    (r'\bHe\s?111s?\b', 'He 111'), (r'\bHe\s?115s?\b', 'He 115'), (r'\bHe\s?59s?\b', 'He 59'),
    (r'\bDo\s?17s?\b', 'Do 17'), (r'\bDo\s?215s?\b', 'Do 215'), (r'\bDo\s?18s?\b', 'Do 18'),
    (r'\bHs\s?126s?\b', 'Hs 126'), (r'\bMe\s?108s?\b', 'Me 108'),
]
TYPE_RE = re.compile('|'.join(f'({p})' for p, _ in TYPES), re.I)
COUNT = {'a': 1, 'an': 1, 'another': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
         'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10}
COUNT_RE = re.compile(r'\b(a|an|another|one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})\s+$', re.I)
KIND = [
    (r'\bprobabl', 'probable'), (r'\bdamaged?\b', 'damaged'),
    (r'\bshared?\b|\bshare\b', 'shared'), (r'\bdestroyed\b|\bshot down\b', 'destroyed'),
]
CLAIMY = re.compile(r'\b(destroy|shot down|damag|probabl|shared?|claim|got|sent down)\w*\b', re.I)

def to_date(day, mon, year):
    m = MONTHS.get(str(mon).lower()) or MON3.get(str(mon).lower()[:3])
    if not m: return None
    try: return datetime.date(int(year) if year else 1940, m, int(day))
    except ValueError: return None

def date_anchors(body):
    """Every date the page states, in the order it states them, however it
    writes them: 18th May, May 18th, or a bare "on the 23rd" carrying the
    month from the last full date before it."""
    full = []
    for m in FULL.finditer(body):
        d = to_date(m.group(1), m.group(2), m.group(3))
        if d: full.append((m.start(), m.end(), d))
    for m in MONFIRST.finditer(body):
        d = to_date(m.group(2), m.group(1), m.group(3))
        if d and not any(f[0] <= m.start() < f[1] for f in full):
            full.append((m.start(), m.end(), d))
    full.sort()
    anchors = list(full)
    for m in BARE.finditer(body):
        prev = [f for f in full if f[0] < m.start()]
        if not prev: continue
        try: d = prev[-1][2].replace(day=int(m.group(1)))
        except ValueError: continue
        anchors.append((m.start(), m.end(), d))
    anchors.sort()
    return anchors

STRICT = False

def claims_in(body):
    """[(date, type, kind)] for every claim the page dates.

    The pages write a combat two ways round, and often both on one page:

        On 20th July 1940 Crossley claimed a Me109 destroyed and shared a
        Me110, on the 25th he got a probable Me109...

        Brothers claimed a Me109 on May 18th, a Me110 on the 23rd,
        Me109's on July 19th, 20th and 29th...

    So rather than reading the text in one direction, every aircraft is
    found first and then given its own date: the one written just after
    it if there is one, otherwise the last date before it. A claim word
    must appear in the same sentence, or it is not a combat at all.
    """
    anchors = date_anchors(body)
    if not anchors: return []
    starts = [a[0] for a in anchors]

    # sentence bounds, so a claim word in a neighbouring sentence cannot
    # turn a mention into a victory
    stops = [m.start() for m in re.finditer(r'[.]\s', body)]
    def sentence(pos):
        lo = max([s for s in stops if s < pos], default=-1) + 1
        hi = min([s for s in stops if s >= pos], default=len(body))
        return body[lo:hi + 1]

    out = []
    for tm in TYPE_RE.finditer(body):
        if STRICT:
            # Only a sentence that names ONE aircraft and one date is read.
            # Chained sentences - "two Ju88s, a Do17 and another Do17
            # shared, on the 16th a Me109, a Me110 and a Ju88 destroyed" -
            # are where the reading goes wrong, and they cannot be told
            # apart from the simple ones after the fact.
            sent0 = None
        idx = next(j for j, g in enumerate(tm.groups()) if g)
        typ = TYPES[idx][1]
        sent = sentence(tm.start())
        if not CLAIMY.search(sent): continue
        if STRICT:
            if len(TYPE_RE.findall(sent)) != 1: continue
            if len([a for a in anchors if sent and body.find(sent) <= a[0] < body.find(sent) + len(sent)]) != 1:
                continue
        # his attacker, not his victim
        before = body[max(0, tm.start() - 24): tm.start()]
        if re.search(r'\bby\s+(?:a\s+|an\s+|two\s+|three\s+)?$', before, re.I): continue
        if re.search(r'\b(?:was|were|been|being)\s+(?:shot down|hit|damaged)\b[^.]{0,30}$', before, re.I):
            continue

        # its date: written just after it, else the last one before it
        d = None
        after = body[tm.end(): tm.end() + 30]
        am = re.match(r"(?:'s|s)?\s+on\s+(?:the\s+)?", after, re.I)
        if am:
            at = tm.end() + am.end()
            hit = [x for x in anchors if abs(x[0] - at) <= 2]
            if hit: d = hit[0][2]
        if d is None:
            prev = [x for x in anchors if x[1] <= tm.start()]
            if prev: d = prev[-1][2]
        if d is None: continue

        # how many of them, and what became of them
        cm = COUNT_RE.search(before)
        n = 1
        if cm:
            w = cm.group(1).lower()
            n = int(w) if w.isdigit() else COUNT.get(w, 1)
        n = max(1, min(n, 6))
        kind = 'destroyed'
        window = body[max(0, tm.start() - 45): tm.end() + 45]
        best = None
        for pat, k in KIND:
            for km in re.finditer(pat, window, re.I):
                # the outcome nearest this aircraft, and nearer to it than
                # to any other aircraft in the window
                pos = max(0, tm.start() - 45) + km.start()
                mine = abs(pos - tm.start())
                others = [abs(pos - o.start()) for o in TYPE_RE.finditer(window)
                          if max(0, tm.start() - 45) + o.start() != tm.start()]
                if others and min(others) < mine: continue
                if best is None or mine < best[0]: best = (mine, k)
        if best: kind = best[1]
        for _ in range(n):
            out.append((d.isoformat(), typ, kind))

        # "Me109's on July 19th, 20th and 29th" - the same aircraft again
        if am:
            at = tm.end() + am.end()
            hit = [x for x in anchors if abs(x[0] - at) <= 2]
            if hit:
                run = body[hit[0][1]: hit[0][1] + 60]
                for rm in re.finditer(r'(?:,|\sand)\s+(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b', run):
                    if TYPE_RE.search(run[:rm.start()]): break
                    try: out.append((hit[0][2].replace(day=int(rm.group(1))).isoformat(), typ, kind))
                    except ValueError: pass
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bbm', required=True)
    ap.add_argument('--test', help='one page stem, printed rather than saved')
    ap.add_argument('--strict', action='store_true',
                    help='only sentences naming one aircraft and one date')
    a = ap.parse_args()
    globals()['STRICT'] = a.strict
    cache = os.path.join(a.bbm, 'pages')
    if a.test:
        t = open(os.path.join(cache, a.test + '.txt'), encoding='utf-8').read()
        i = t.find("The Airmen's Stories"); b = t[i:] if i >= 0 else t
        for c in claims_in(b): print(' ', c)
        return
    out = {}
    for fn in sorted(os.listdir(cache)):
        if not fn.endswith('.txt'): continue
        t = open(os.path.join(cache, fn), encoding='utf-8').read()
        i = t.find("The Airmen's Stories"); b = t[i:] if i >= 0 else t
        c = claims_in(b)
        if c: out[fn[:-4]] = [{'date': d, 'type': ty, 'kind': k} for d, ty, k in c]
    path = os.path.join(a.bbm, 'claims-strict.json' if a.strict else 'claims.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, sort_keys=True)
    n = sum(len(v) for v in out.values())
    inbob = sum(1 for v in out.values() for c in v if '1940-07-10' <= c['date'] <= '1940-10-31')
    print(f'{path}: {len(out)} men, {n} dated claims, {inbob} of them inside the Battle')

if __name__ == '__main__':
    main()
