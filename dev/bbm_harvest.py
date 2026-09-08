#!/usr/bin/env python3
"""Collect the Battle of Britain Monument's airman pages, and read the
squadron postings out of them.

Why: a squadron roster of names alone puts every man who ever served on
the board at once, and no squadron ever had sixty pilots on strength. To
show a squadron as it stood on a morning we need the day each man joined
it and the day he left. The Monument's biographies carry those dates in
prose - "joined 19 Squadron at Duxford on 9th June 1940" - and a leaving
date is usually the day he joined his next unit, or the day he was lost.

Facts only. This reads dates and squadron numbers; it never keeps the
site's wording.

    python3 dev/bbm_harvest.py --index   collect the airman page list
    python3 dev/bbm_harvest.py --fetch   download the pages (polite, resumable)
    python3 dev/bbm_harvest.py --parse   read postings out of what was downloaded
"""
import re, os, sys, json, time, html, argparse, urllib.request, urllib.error
import concurrent.futures

UA = 'Mozilla/5.0 (compatible; BOB2 Squadron Room historical research; contact via github.com/malawicob/bob2-modern-fix)'
BASE = 'https://www.bbm.org.uk'
# The British list runs a page per letter; every other nationality is one
# page. Only 'british-airmen-list-a' is linked from the index, which is
# why a first pass found 674 men out of the 2,937 who earned the clasp.
LISTS = [f'british-airmen-list-{c}' for c in 'abcdefghijklmnopqrstuvwxyz'] + \
        [f'{c}-airmen-list' for c in (
    'australia', 'barbados', 'belgium', 'canada', 'czechoslovakia', 'france',
    'ireland', 'jamaica', 'new-zealand', 'newfoundland', 'poland', 'rhodesia',
    'south-africa', 'united-states')]

def get(url, tries=3):
    for n in range(tries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=45) as r:
                return r.read().decode('utf-8', 'replace')
        except urllib.error.HTTPError as e:
            if e.code == 404: return None
            time.sleep(1.5 * (n + 1))
        except Exception:
            time.sleep(1.5 * (n + 1))
    return None

def text_of(page):
    t = re.sub(r'<script.*?</script>|<style.*?</style>', ' ', page, flags=re.S | re.I)
    t = re.sub(r'<[^>]+>', ' ', t)
    return re.sub(r'\s+', ' ', html.unescape(t)).strip()

def do_index(out):
    """Each entry keeps the man's page, and the rank and name the list
    shows against it, so a roster can be built without opening every page
    again just to learn who he was."""
    seen = {}
    for slug in LISTS:
        page = get(f'{BASE}/the-airmen/{slug}/')
        if not page:
            print(f'  {slug}: no such page'); continue
        hits = re.findall(
            r'href="([^"]*?/airmen/([A-Za-z0-9_.\-]+)\.htm)"[^>]*>(.*?)</a>', page, re.I | re.S)
        n = 0
        country = slug.replace('-airmen-list', '').replace('british-list-', 'british')
        country = re.sub(r'^british-?', 'british', country).rstrip('-')
        for href, stem, label in hits:
            if stem.lower() in ('index', 'airmen-ranks'): continue
            url = href if href.startswith('http') else BASE + href
            url = url.replace('http://', 'https://')
            if stem in seen: continue
            txt = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', label))).strip()
            m = re.match(r'^([A-Za-z/12 ]{1,10}?\.?)\s+(.+)$', txt)
            rank, name = (m.group(1).strip(), m.group(2).strip()) if m else ('', txt)
            seen[stem] = {'url': url, 'rank': rank, 'name': name, 'country': country}
            n += 1
        print(f'  {slug}: {n} new, {len(seen)} so far')
        time.sleep(0.4)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(seen, f, indent=1, sort_keys=True)
    print(f'{out}: {len(seen)} airmen')

def do_fetch(index, cache, workers):
    os.makedirs(cache, exist_ok=True)
    men = json.load(open(index, encoding='utf-8'))
    todo = [(s, (v['url'] if isinstance(v, dict) else v)) for s, v in men.items()
            if not os.path.exists(os.path.join(cache, s + '.txt'))]
    print(f'{len(men)} airmen, {len(todo)} still to fetch')
    done = [0]
    def one(item):
        stem, url = item
        page = get(url)
        if page is None: return stem, False
        with open(os.path.join(cache, stem + '.txt'), 'w', encoding='utf-8') as f:
            f.write(text_of(page))
        done[0] += 1
        if done[0] % 100 == 0: print(f'  {done[0]}/{len(todo)}')
        time.sleep(0.15)
        return stem, True
    bad = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        for stem, ok in ex.map(one, todo):
            if not ok: bad.append(stem)
    print(f'fetched {done[0]}, failed {len(bad)}')
    if bad: print('  failed:', ', '.join(bad[:20]))

# --- reading the postings out of the prose -------------------------------
MONTHS = {m: i + 1 for i, m in enumerate(
    ['january','february','march','april','may','june','july','august',
     'september','october','november','december'])}
MON3 = {m[:3]: i + 1 for i, m in enumerate(MONTHS)}
DAY = r'(\d{1,2})(?:st|nd|rd|th)?'
MON = (r'(January|February|March|April|May|June|July|August|September|October|'
       r'November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)')
YEAR = r'(?:\s+(\d{4}))?'
JOINV = (r'(?:joined|re-?joined|posted to|moved to|went to|arrived at|transferred to|'
         r'was posted to|reported to)')
SQN = r'(?:No\.?\s*)?(\d{1,3})\s*(?:\((?:\w|\s)+\)\s*)?(?:Sqn|Squadron)'

# The biographies write a posting four ways, and taking only the first
# form found dates in 1,823 of the 2,937 men. Reading all four, and
# carrying the month forward for a bare "on the 9th", finds far more.
PATTERNS = [
    # joined 19 Squadron at Duxford on 9th June 1940
    ('day', re.compile(JOINV + r'\s+' + SQN + r'(?:[^.;]{0,80}?)\bon\s+' + DAY + r'\s+' + MON + YEAR, re.I)),
    # On 9th June 1940 he joined 19 Squadron
    ('day', re.compile(r'\bOn\s+' + DAY + r'\s+' + MON + YEAR + r'[^.;]{0,70}?' + JOINV + r'\s+' + SQN, re.I)),
    # joined 19 Squadron ... on the 9th   (month carried from earlier in the text)
    ('carry', re.compile(JOINV + r'\s+' + SQN + r'(?:[^.;]{0,80}?)\bon\s+the\s+' + DAY, re.I)),
    # joined 19 Squadron in June 1940   (no day: the 1st, marked as a month)
    ('month', re.compile(JOINV + r'\s+' + SQN + r'(?:[^.;]{0,80}?)\b(?:in|during)\s+(?:early\s+|mid-?\s*|late\s+)?' + MON + YEAR, re.I)),
]
# every date in the text, so a bare "on the 9th" can take the month it follows
ANYDATE = re.compile(DAY + r'\s+' + MON + YEAR, re.I)

def to_date(day, mon, year):
    m = MONTHS.get(str(mon).lower()) or MON3.get(str(mon).lower()[:3])
    if not m: return None
    y = int(year) if year else 1940
    try:
        import datetime
        return datetime.date(y, m, int(day)).isoformat()
    except ValueError:
        return None

# "was killed on 15th September 1940", "died of his wounds on 9th November"
END = re.compile(
    r'\b(?:was\s+)?(killed|died of (?:his\s+)?wounds|died)\b[^.;]{0,60}?\bon\s+'
    + DAY + r'\s+' + MON + YEAR, re.I)
# every squadron the page mentions, for whatever reason
ANYSQN = re.compile(r'(?:No\.?\s*)?(\d{1,3})\s*(?:\(\w+\)\s*)?(?:Sqn|Squadron)', re.I)

def do_parse(cache, out):
    men = {}
    files = sorted(f for f in os.listdir(cache) if f.endswith('.txt'))
    for fn in files:
        t = open(os.path.join(cache, fn), encoding='utf-8').read()
        # the biography starts after the site furniture
        i = t.find("The Airmen's Stories")
        body = t[i:] if i >= 0 else t

        # where each full date sits, so a bare day can borrow its month
        marks = [(m.start(), m.group(2), m.group(3)) for m in ANYDATE.finditer(body)]
        def carried(pos):
            best = None
            for at, mon, yr in marks:
                if at <= pos: best = (mon, yr)
                else: break
            return best

        found = {}
        for kind, pat in PATTERNS:
            for m in pat.finditer(body):
                g = m.groups()
                if kind == 'day':
                    if pat.pattern.startswith(r'\bOn'): day, mon, yr, sqn = g[0], g[1], g[2], g[3]
                    else: sqn, day, mon, yr = g[0], g[1], g[2], g[3]
                    prec = 'day'
                elif kind == 'carry':
                    sqn, day = g[0], g[1]
                    c = carried(m.start())
                    if not c: continue
                    mon, yr = c; prec = 'day'
                else:
                    sqn, mon, yr = g[0], g[1], g[2]; day = 1; prec = 'month'
                d = to_date(day, mon, yr)
                if not d: continue
                key = int(sqn)
                # an exact date beats a month, and the earliest wins: a man
                # joins a squadron once, and later mentions are his return
                cur = found.get(key)
                if cur and (cur['precision'] == 'day' and prec == 'month'): continue
                if cur and cur['precision'] == prec and cur['joined'] <= d: continue
                found[key] = {'sqn': key, 'joined': d, 'precision': prec, 'at': m.start()}

        posts = sorted(found.values(), key=lambda p: p['joined'])
        # a man's leaving date is the day he joined the NEXT unit
        for x, y in zip(posts, posts[1:]):
            if y['joined'] > x['joined']: x['left'] = y['joined']
        for p in posts: p.pop('at', None)
        rec = {'postings': posts,
               'squadrons': sorted({int(x) for x in ANYSQN.findall(body)})}
        em = END.search(body)
        if em:
            ed = to_date(em.group(2), em.group(3), em.group(4))
            if ed: rec['died'] = ed
        if posts or rec['squadrons']: men[fn[:-4]] = rec
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(men, f, indent=1, sort_keys=True)
    tot = sum(len(v['postings']) for v in men.values())
    withleft = sum(1 for v in men.values() for p in v['postings'] if 'left' in p)
    dated = sum(1 for v in men.values() if v['postings'])
    exact = sum(1 for v in men.values() for p in v['postings'] if p['precision'] == 'day')
    died = sum(1 for v in men.values() if 'died' in v)
    print(f'{out}: {len(men)} of {len(files)} men read; {dated} gave a dated posting, '
          f'{tot} postings ({exact} to the day), {withleft} with a leaving date, '
          f'{died} with a date of death')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', default='/home/patrick_millin/bob2/bbm')
    ap.add_argument('--index', action='store_true')
    ap.add_argument('--fetch', action='store_true')
    ap.add_argument('--parse', action='store_true')
    ap.add_argument('--workers', type=int, default=6)
    a = ap.parse_args()
    os.makedirs(a.dir, exist_ok=True)
    idx = os.path.join(a.dir, 'index.json')
    cache = os.path.join(a.dir, 'pages')
    if a.index: do_index(idx)
    if a.fetch: do_fetch(idx, cache, a.workers)
    if a.parse: do_parse(cache, os.path.join(a.dir, 'postings.json'))

if __name__ == '__main__':
    main()
