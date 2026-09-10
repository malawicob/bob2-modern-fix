#!/usr/bin/env python3
"""Turn the harvested German communiques into what Berlin claimed, in English.

    python3 dev/render_okw.py --in /tmp/okw-full.json \
        --out squadronroom/lw/okw.json

Patrick's decision was an ENGLISH rendering rather than the German text,
with the material labelled for what it is. This does the mechanical half
of that: it reads each day's communique and pulls out the things that can
be pulled out and CHECKED, rather than paraphrasing propaganda into
fluent English and hoping.

WHAT IS EXTRACTED, AND WHY THESE THINGS

  claimed   British aircraft the communique says were shot down
  admitted  German aircraft it admits did not come back
  targets   the British places it names

The two numbers are the point of the whole exercise. They are the lie
itself, they are numerals so the OCR either has them or it does not, and
they sit next to the campaign's own diary figures on the same screen.
The place names are matched against a fixed list of British towns,
ports and airfields, so a mangled word matches a real place or it is
dropped; nothing is invented to fill a gap.

Spelled-out numbers are read too. "Acht feindliche Flugzeuge wurden
abgeschossen" is eight, and a script that only looked for digits would
silently record that day as no claim at all, which is worse than
recording nothing.

WHAT IS NOT DONE HERE

No day is given an English sentence by this script. A machine paraphrase
of a propaganda communique, written out in confident English prose, is
the one thing this must not produce: it would read as a report of what
happened. The sentence each day carries is assembled from the extracted
facts alone, in the form "Berlin claimed X for Y", and every record
keeps the German it was read from so the reading can be checked.

A day whose OCR yields no figures at all gets a record with counts of
null. The Room says nothing rather than guessing.
"""
import json, argparse, re, sys, collections, unicodedata

# Spelled-out numbers as they appear in these texts. Only up to twenty
# and the round tens: a communique never spells out 138.
WORDNUM = {
    'ein': 1, 'eins': 1, 'eine': 1, 'einem': 1, 'einen': 1,
    'zwei': 2, 'drei': 3, 'vier': 4, 'fuenf': 5, 'sechs': 6, 'sieben': 7,
    'acht': 8, 'neun': 9, 'zehn': 10, 'elf': 11, 'zwoelf': 12,
    'dreizehn': 13, 'vierzehn': 14, 'fuenfzehn': 15, 'sechzehn': 16,
    'siebzehn': 17, 'achtzehn': 18, 'neunzehn': 19, 'zwanzig': 20,
    'dreissig': 30, 'vierzig': 40, 'fuenfzig': 50,
}

# British places these communiques actually name. Matching against a list
# means a mangled reading either lands on a real place or is dropped.
PLACES = [
    'London', 'Portland', 'Weymouth', 'Dover', 'Portsmouth', 'Southampton',
    'Plymouth', 'Bristol', 'Liverpool', 'Birmingham', 'Coventry', 'Sheffield',
    'Manchester', 'Hull', 'Newcastle', 'Hartlepool', 'Middlesbrough', 'Grimsby',
    'Harwich', 'Ipswich', 'Norwich', 'Yarmouth', 'Dundee', 'Aberdeen', 'Glasgow',
    'Swansea', 'Cardiff', 'Falmouth', 'Exeter', 'Bournemouth', 'Brighton',
    'Ramsgate', 'Margate', 'Folkestone', 'Canterbury', 'Rochester', 'Chatham',
    'Woolwich', 'Bromley', 'Croydon', 'Kenley', 'Biggin Hill', 'Hornchurch',
    'Manston', 'Hawkinge', 'Lympne', 'Detling', 'Eastchurch', 'Tangmere',
    'Thorney Island', 'Middle Wallop', 'Warmwell', 'Odiham', 'Andover',
    'Farnborough', 'Northolt', 'Debden', 'Duxford', 'Martlesham', 'Driffield',
    'Aldershot', 'Dagenham', 'Thameshaven', 'Sheerness', 'Gravesend',
    'Warrington', 'Salisbury', 'Worcester', 'Wallsend', 'Berwick', 'Scapa Flow',
    'Belfast', 'Swindon', 'Reading', 'Filton', 'Yeovil', 'Weybridge',
]

# The sentence shapes the claim is written in. The number may be digits or
# a spelled-out word, and the OCR may have broken the thousands apart.
NUM = r'(\d{1,3}(?:\s?\d{3})?|[A-Za-zäöüÄÖÜß]{3,12})'


def loose(word):
    """A word the OCR is allowed to have broken with spaces.

    Fraktur pages break words across a line and the OCR keeps the break,
    so "betrugen" arrives as "be trugen" and a plain literal misses it.
    Used only on the handful of verbs the patterns hinge on: applied
    everywhere it would match far too much.
    """
    return r'\s*'.join(re.escape(c) for c in word)

# The shapes the day's total is written in, MOST EXPLICIT FIRST, because
# first() takes the first pattern that matches and a communique carries
# both a headline total and smaller claims inside it. "Durch
# Flakartillerie wurden zwei britische Flugzeuge abgeschossen" is a real
# sentence in these texts and it is not the day's figure.
#
# The gap in the first two allows a full stop, which looks wrong and is
# not: the communique writes the date as "am 25. August", so a gap of
# [^.] stops dead at the day number and the total that follows is never
# reached. That one detail cost most of the September readings.
CLAIM_PATTERNS = [
    r'Verluste\s+des\s+(?:Gegners|Feindes)[\s\S]{0,70}?' + loose('betrugen') + r'\s+(?:insgesamt\s+|mindestens\s+)?' + NUM,
    # the gap is generic because the papers set this line differently:
    # "Zahl der am Sonntag vernichteten" in one, "Zahl der Sonntag
    # vernichteten" in another, and a fixed "am \w+" misses the second
    r'(?:Zahl der|insgesamt)[\s\S]{0,30}?(?:vernichteten|abgeschossenen)\s+Feindflugzeuge[\s\S]{0,20}?' + NUM,
    r'Feindflugzeuge\s+(?:betraegt|betrug|auf)\s*' + NUM + r'\b',
    r'verlor\s+der\s+Feind\s+' + NUM + r'\s+' + loose('Flugzeuge'),
    r'(?:Der Feind|Der Gegner)\s+verlor\s+' + NUM,
    r'In\s+Luftkaempfen\s+wurden\s+' + NUM + r'\s+' + loose('Flugzeuge') + r'\s+abgeschossen',
    r'wurden\s+' + NUM + r'\s+(?:britische|feindliche|englische)\s+' + loose('Flugzeuge') + r'\s+abgeschossen',
    NUM + r'\s+(?:britische|feindliche|englische)\s+' + loose('Flugzeuge') + r'\s+(?:wurden\s+)?(?:abgeschossen|vernichtet)',
    r'Feindjaegern\s+wurden\s+' + NUM + r'\s+abgeschossen',
]

LOSS_PATTERNS = [
    NUM + r'\s+(?:deutsche|eigene)\s+' + loose('Flugzeuge') + r'?\s+(?:sind|ist|werden|wurden|gingen)?\s*'
        r'(?:zurzeit\s+)?(?:noch\s+)?(?:nicht\s+zurueckgekehrt|vermisst|verloren(?:gegangen)?)',
    NUM + r'\s+(?:deutsche|eigene)\s+' + loose('Flugzeuge') + r'\s+kehrten\s+nicht\s+zurueck',
    NUM + r'\s+(?:unserer|eigener)\s+' + loose('Flugzeuge') + r'\s+(?:werden\s+)?vermisst',
    r'(?:Wir verloren|Eigene Verluste:?)\s+' + NUM + r'\s+' + loose('Flugzeuge'),
]


def fold(s):
    """Umlauts out, so one spelling of a pattern matches every OCR of it."""
    s = (s.replace('ä', 'ae').replace('ö', 'oe').replace('ü', 'ue')
          .replace('Ä', 'Ae').replace('Ö', 'Oe').replace('Ü', 'Ue')
          .replace('ß', 'ss'))
    # A three-figure number can come out of the scan with a space in it:
    # two of the papers carrying the 19 August communique render 138 as
    # "13 8", and read literally that is a claim of thirteen. The join is
    # allowed only where neither part touches a full stop, so the date
    # "am 15. 8." is left alone - that is two numbers and not one.
    s = re.sub(r'(?<![.\d])(\d{1,2})\s(\d)(?![\d.])', r'\1\2', s)
    return unicodedata.normalize('NFKD', s)


def num(tok):
    tok = tok.strip()
    d = re.sub(r'\s', '', tok)
    if d.isdigit():
        n = int(d)
        return n if 0 < n <= 400 else None      # a day's claim is never 900
    w = fold(tok).lower()
    return WORDNUM.get(w)


def first(text, patterns):
    for p in patterns:
        m = re.search(p, text, re.I)
        if m:
            n = num(m.group(1))
            if n is not None:
                return n, re.sub(r'\s+', ' ', m.group(0))[:110]
    return None, None


def targets(text):
    out = []
    for p in PLACES:
        # the OCR breaks and respaces words, so the test is loose on
        # spacing and exact on the letters
        pat = r'\b' + r'\s*'.join(re.escape(c) for c in fold(p) if c != ' ') + r'\b'
        if re.search(pat, fold(text), re.I):
            out.append(p)
    return out


def line(claimed, admitted, tgts):
    """The one sentence the Room shows. Assembled from the figures, never
    written about them: this says what Berlin claimed, and says who is
    claiming."""
    bits = []
    if claimed is not None and admitted is not None:
        bits.append('Berlin claimed %d British aircraft shot down and admitted %d of its own missing.'
                    % (claimed, admitted))
    elif claimed is not None:
        bits.append('Berlin claimed %d British aircraft shot down.' % claimed)
    elif admitted is not None:
        bits.append('Berlin admitted %d German aircraft missing.' % admitted)
    if tgts:
        named = tgts[:6]
        bits.append('Targets named: ' + ', '.join(named) + '.')
    return ' '.join(bits)


def poll(wits, patterns):
    """Ask every paper the same question and take the answer they agree on.

    This started out taking the first paper that matched, and it was
    quietly wrong: the communique of 19 August 1940 claims 138 British
    aircraft and one paper's scan of it reads 13, so the Room would have
    printed 13 as a historical claim. On a page whose entire purpose is
    to show that these figures were falsified, printing a figure that is
    merely mis-scanned would be the worst possible failure.

    So the figure has to be corroborated. Five to seven papers printed
    the same words on the same morning and were scanned independently
    decades apart; a number two of them agree on is what was printed, and
    a number only one of them has is not good enough to show. Returns the
    value, how many papers had it, and how many had anything at all.
    """
    votes = collections.Counter()
    quotes = {}
    asked = 0
    for w in wits:
        n, q = first(fold(w['text']), patterns)
        if n is None:
            continue
        asked += 1
        votes[n] += 1
        quotes.setdefault(n, q)
    if not votes:
        return None, 0, 0, None
    n, k = votes.most_common(1)[0]
    return n, k, asked, quotes.get(n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='src', default='/tmp/okw-full.json')
    ap.add_argument('--out', default='squadronroom/lw/okw.json')
    ap.add_argument('--min-agree', type=int, default=2,
                    help='papers that must agree before a figure is kept')
    ap.add_argument('--keep-source', action='store_true',
                    help='keep a long German excerpt per day (for checking, '
                         'not for shipping)')
    a = ap.parse_args()

    with open(a.src, encoding='utf-8') as fh:
        days = json.load(fh)

    out = []
    kept = collections.Counter()
    for d in days:
        wits = d.get('all') or [{'text': d['text'], 'paper': d['paper'],
                                 'licence': d['licence'], 'raw': d.get('raw', '')}]
        c, ck, casked, cq = poll(wits, CLAIM_PATTERNS)
        l, lk, lasked, lq = poll(wits, LOSS_PATTERNS)
        if ck < a.min_agree: c, cq = None, None
        if lk < a.min_agree: l, lq = None, None
        # the reading shown is the cleanest paper that HAS the agreed
        # figure, so the German kept beside it is the German the number
        # was actually read from
        used = wits[0]
        for w in wits:
            n, _ = first(fold(w['text']), CLAIM_PATTERNS)
            if c is not None and n == c:
                used = w; break
        tg = targets(used['text'])
        if c is not None or l is not None:
            kept['figures'] += 1
        if c is not None and l is not None:
            kept['both'] += 1
        out.append({
            'date': d['date'],
            'claimed_british': c,
            'admitted_german': l,
            'targets': tg,
            'line': line(c, l, tg),
            'witnesses': d.get('witnesses', len(wits)),
            'agree_claim': ck, 'agree_loss': lk,
            'paper': used.get('paper', ''),
            'licence': used.get('licence', ''),
            # The German that the figures were actually read from, and
            # no more than that. An earlier version shipped 900
            # characters of each day's communique as context; the
            # quotes are the evidence for the numbers and the rest was
            # propaganda text riding along in the download for no
            # purpose it could not serve in one clause. --keep-source
            # puts it back for checking a reading by hand.
            'quote_claim': cq,
            'quote_loss': lq,
            'source_de': (used.get('text', '')[:900] if a.keep_source else None),
        })

    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write('\n')
    print('%d days, %d with a corroborated figure (%d with both), '
          'agreement threshold %d papers -> %s'
          % (len(out), kept['figures'], kept['both'], a.min_agree, a.out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
