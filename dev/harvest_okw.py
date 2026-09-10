#!/usr/bin/env python3
"""Harvest the OKW daily communique from contemporary newspapers.

    python3 dev/harvest_okw.py --from 1940-07-10 --to 1940-10-31 \
        --out /tmp/okw-sample.json

WHERE IT COMES FROM

The Wehrmachtbericht was read on the radio and printed the next morning
in every paper in the Reich. There is no free digital edition of the
communiques themselves: the two complete printed editions (Wegmann's
"Das Oberkommando der Wehrmacht gibt bekannt...", 1982, and the dtv
"Die Wehrmachtberichte 1939-1945", 1985) are both in copyright as
editions. So this goes to the newspapers, which are not.

The Deutsches Zeitungsportal of the Deutsche Digitale Bibliothek holds
33.9 million newspaper pages with ALTO full text, and its Solr API is
open and needs no key:

    https://api.deutsche-digitale-bibliothek.de/search/index/newspaper-issues/select

For 10 May to 31 October 1940 it has 19,456 issues. Of those, 2,895
carry a licence that permits reuse - Public Domain Mark 1.0, CC BY-SA
4.0 or CC BY-NC-SA 4.0 - and the rest are "rights unknown" or
"in copyright", which is why PAPERS below is a fixed list rather than
whatever the search happens to return. Every paper in it has been
checked to carry one of those three licences.

THE CATCH, STATED PLAINLY

These are Fraktur pages OCR'd by machine, and the OCR is not clean. It
ranges from about 90 per cent right on a good paper and a good day down
to unusable. The systematic errors are correctable - Fraktur long s
reads as a plain s, V reads as B, words break across a line - and this
script fixes those. What it CANNOT fix is a word the OCR simply got
wrong, and a script that quietly repaired those into plausible German
would be writing the communique rather than reading it.

So nothing here is presented as a clean text. Each day carries:

    conf   how many of the day's papers were found, and how much of the
           text survives the junk test
    src    which paper this reading came from, with its licence
    raw    the OCR as it came, so the tidying can always be checked

WHAT IS NOT DONE

Where the communique ends is guessed, and the guess is not always right.
On 24 August 1940 the reading still runs on into the paper's own next
headline ("Eine Milchmaedchenrechnung der britischen Propaganda"), which
is the paper talking and not Berlin. Any day that goes into the mod has
to have its tail looked at by a person. There is no clever fix for this:
the OCR carries no headline markup, only words.

WHAT THIS MATERIAL IS

It is Nazi state propaganda. The loss figures in it are not merely
inaccurate, they were inflated deliberately: on 11 August 1940 the
communique claims 73 British aircraft shot down for 14 German aircraft
missing, and the real figures for that day were nothing like it. That
is the whole reason it is worth having in the Room next to the
campaign's own numbers, and the whole reason it must never be shown
without saying what it is. The Deutsche Digitale Bibliothek flags
19,366 of those 19,456 issues as requiring a disclaimer for exactly
this reason, and any screen that uses this data must carry one too.
"""
import json, argparse, sys, re, time, urllib.parse, urllib.request, datetime

API = "https://api.deutsche-digitale-bibliothek.de/search/index/newspaper-issues/select"
UA  = "bob2-squadron-room/1.0 (patmillin@gmail.com)"

# Papers checked to carry a reusable licence, best OCR first. The score is
# from dev/ scoring over July-October 1940: how often the words that MUST
# appear in an air communique actually appear, against how much OCR junk
# comes with them.
PAPERS = [
    ('Mitteldeutsche Nationalzeitung', 'Public Domain Mark 1.0'),
    ('Gießener Anzeiger',              'CC BY-SA 4.0'),
    ('Neue Mannheimer Zeitung',        'CC BY-SA 4.0'),
    ('Hakenkreuzbanner',               'CC BY-SA 4.0'),
    ('Neckar-Bote',                    'CC BY-SA 4.0'),
    ('Jeversches Wochenblatt',         'CC BY-SA 4.0'),
    ('Nationale Rundschau',            'Public Domain Mark 1.0'),
    ('Neckar-Bergstrass-Post',         'Public Domain Mark 1.0'),
    ('Durlacher Tagblatt',             'CC BY-SA 4.0'),
    ('Hallische Nachrichten',          'Public Domain Mark 1.0'),
    ('Der Führer',                     'CC BY-SA 4.0'),
    ('Badische Presse',                'CC BY-SA 4.0'),
]

OPENING = 'Oberkommando der Wehrmacht gibt bekannt'
OPEN_RE = re.compile(OPENING)
# where the communique ends and the paper's own writing begins
# Where the communique stops and the paper's own writing starts. The OKW
# text is a run of plain paragraphs; what follows it is a headline, and a
# headline in this OCR shows up as a run of Capitalised Words with no
# full stop. Without this the 24 August reading ran straight on into
# "Eine Milchmaedchenrechnung der britischen Propaganda", which is the
# paper talking, not Berlin.
END_RE  = re.compile(r'(?:\bDNB\b|Berlin\s*,\s*\d|\bWTB\b|Unser[e]? Berichterstatter'
                     r'|(?<=[a-zäöüß] )(?:[A-ZÄÖÜ][a-zäöüß]+ ){3,}(?=[A-ZÄÖÜ]))')
JUNK_RE = re.compile(r'[«»§¤¦°„“”\|\\~^_]')

# Words the OCR gets wrong the SAME way every time, because of how the
# Fraktur letter is cut. Nothing here is a guess: each is a real word the
# OCR maps to a non-word, and only exact non-words are replaced.
FIXES = [
    # Fraktur capital I and J are near enough the same cut that the OCR
    # reads almost every "Im", "In" and "Ihre" as a J. It is the single
    # commonest error in these pages and it is entirely mechanical.
    ('Jm ',          'Im '),
    ('Jn ',          'In '),
    ('Jhre',         'Ihre'),
    ('Jnsel',        'Insel'),
    ('Jndustrie',    'Industrie'),
    ('Bergeltung',   'Vergeltung'),     # Fraktur V read as B
    ('Bersenkung',   'Versenkung'),
    ('bersenkt',     'versenkt'),
    ('Berbänden',    'Verbänden'),
    ('Berluste',     'Verluste'),
    ('Hasenanlagen', 'Hafenanlagen'),   # long s read as an s, then f as s
    ('Hasenplätze',  'Hafenplätze'),
    ('Kampsflieger', 'Kampfflieger'),
    ('Kampsflugzeuge','Kampfflugzeuge'),
    ('Lause',        'Laufe'),
    ('sortgesetzt',  'fortgesetzt'),
    ('Luftkämpsen',  'Luftkämpfen'),
    ('Flugzeugsührer','Flugzeugführer'),
]


def tidy(s):
    """Undo what is mechanical, and nothing else.

    The long s and the double-oblique hyphen are FAITHFUL readings of
    Fraktur, not damage. Letter-spacing (k ä m p f e n) is the original's
    own emphasis and is closed up. Words broken over a line are rejoined.
    Everything past that is left exactly as the OCR had it.
    """
    s = s.replace('ſ', 's').replace('⸗', '-').replace('⁊', '&')
    s = re.sub(r'\s+', ' ', s)
    # letter-spaced emphasis: three or more single letters in a row
    s = re.sub(r'\b(?:[A-Za-zÄÖÜäöüß] ){2,}[A-Za-zÄÖÜäöüß]\b',
               lambda m: m.group(0).replace(' ', ''), s)
    s = re.sub(r'(\w)- (\w)', r'\1\2', s)      # hyphenated over a line break
    s = re.sub(r'\s+([,.;:!?])', r'\1', s)
    for bad, good in FIXES:
        s = s.replace(bad, good)
    return s.strip(' :.-')


def api(query, rows=20):
    p = {'q': query, 'rows': rows, 'wt': 'json'}
    req = urllib.request.Request(API + '?' + urllib.parse.urlencode(p), headers={'User-Agent': UA})
    return json.loads(urllib.request.urlopen(req, timeout=90).read())


def day(date):
    """Every reading of one day's communique, best paper first."""
    sel = ' OR '.join('paper_title:"%s"' % p for p, _ in PAPERS)
    q = ('type:page AND plainpagefulltext:"%s" '
         'AND publication_date:[%sT00:00:00Z TO %sT23:59:59Z] AND (%s)'
         % (OPENING, date, date, sel))
    try:
        docs = api(q)['response']['docs']
    except Exception as e:
        print('  ! %s lookup failed: %s' % (date, e), file=sys.stderr)
        return []
    order = {p: i for i, (p, _) in enumerate(PAPERS)}
    def rank(d):
        for p, i in order.items():
            if d.get('paper_title', '').startswith(p):
                return i
        return 99
    out = []
    for d in sorted(docs, key=rank):
        t = d.get('plainpagefulltext', '')
        m = OPEN_RE.search(t)
        if not m:
            continue
        seg = t[m.end():m.end() + 1600]
        e = END_RE.search(seg, 200)
        if e:
            seg = seg[:e.start()]
        txt = tidy(seg)
        if len(txt) < 120:
            continue
        toks = txt.split()
        junk = len(JUNK_RE.findall(txt))
        out.append({
            'paper': d.get('paper_title', '')[:60],
            'licence': next((l for p, l in PAPERS if d.get('paper_title', '').startswith(p)), '?'),
            'page': d.get('pagenumber'),
            'text': txt,
            'raw': re.sub(r'\s+', ' ', seg).strip(),
            'junk_per_1k': round(1000.0 * junk / max(1, len(toks)), 1),
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--from', dest='d0', default='1940-07-10')
    ap.add_argument('--to',   dest='d1', default='1940-10-31')
    ap.add_argument('--out',  default='/tmp/okw.json')
    ap.add_argument('--all-witnesses', action='store_true',
                    help='keep every paper, not just the best reading')
    a = ap.parse_args()

    d0 = datetime.date.fromisoformat(a.d0)
    d1 = datetime.date.fromisoformat(a.d1)
    out = []
    d = d0
    while d <= d1:
        ds = d.isoformat()
        w = day(ds)
        if w:
            best = min(w, key=lambda x: x['junk_per_1k'])
            rec = {'date': ds, 'witnesses': len(w), 'paper': best['paper'],
                   'licence': best['licence'], 'junk_per_1k': best['junk_per_1k'],
                   'text': best['text'], 'raw': best['raw']}
            if a.all_witnesses:
                rec['all'] = w
            out.append(rec)
            print('  %s  %d paper(s)  junk %5.1f/1k  %s'
                  % (ds, len(w), best['junk_per_1k'], best['paper'][:34]))
        else:
            print('  %s  nothing found' % ds)
        d += datetime.timedelta(days=1)
        time.sleep(0.4)

    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write('\n')
    print('\n%d of %d days -> %s' % (len(out), (d1 - d0).days + 1, a.out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
