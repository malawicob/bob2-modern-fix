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
    seen = {}
    for slug in LISTS:
        page = get(f'{BASE}/the-airmen/{slug}/')
        if not page:
            print(f'  {slug}: no such page'); continue
        hits = re.findall(r'href="([^"]*?/airmen/([A-Za-z0-9_.\-]+)\.htm)"', page, re.I)
        n = 0
        for href, stem in hits:
            if stem.lower() in ('index', 'airmen-ranks'): continue
            url = href if href.startswith('http') else BASE + href
            url = url.replace('http://', 'https://')
            if stem not in seen: seen[stem] = url; n += 1
        print(f'  {slug}: {n} new, {len(seen)} so far')
        time.sleep(0.4)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(seen, f, indent=1, sort_keys=True)
    print(f'{out}: {len(seen)} airmen')

def do_fetch(index, cache, workers):
    os.makedirs(cache, exist_ok=True)
    men = json.load(open(index, encoding='utf-8'))
    todo = [(s, u) for s, u in men.items()
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
DATE = r'(\d{1,2})(?:st|nd|rd|th)?\s+([A-Z][a-z]+)(?:\s+(\d{4}))?'
# "joined 19 Squadron at Duxford on 9th June 1940", "posted to 92 Squadron
# on 6th September", "rejoined 605 Squadron on 15th October 1940"
JOIN = re.compile(
    r'(?:joined|re-?joined|posted to|moved to|went to|arrived at|transferred to)\s+'
    r'(?:No\.?\s*)?(\d{1,3})\s*(?:\(\w+\)\s*)?Squadron'
    r'(?:[^.;]{0,80}?)\bon\s+' + DATE, re.I)

def to_date(day, mon, year):
    m = MONTHS.get(mon.lower()) or MON3.get(mon.lower()[:3])
    if not m: return None
    y = int(year) if year else 1940
    try:
        import datetime
        return datetime.date(y, m, int(day)).isoformat()
    except ValueError:
        return None

def do_parse(cache, out):
    men = {}
    files = sorted(f for f in os.listdir(cache) if f.endswith('.txt'))
    for fn in files:
        t = open(os.path.join(cache, fn), encoding='utf-8').read()
        # the biography starts after the site furniture
        i = t.find("The Airmen's Stories")
        body = t[i:] if i >= 0 else t
        posts = []
        for m in JOIN.finditer(body):
            d = to_date(m.group(2), m.group(3), m.group(4))
            if d: posts.append({'sqn': int(m.group(1)), 'joined': d, 'at': m.start()})
        if not posts: continue
        posts.sort(key=lambda p: p['at'])
        # a man's leaving date is the day he joined the NEXT unit
        for a, b in zip(posts, posts[1:]):
            if b['joined'] > a['joined']: a['left'] = b['joined']
        for p in posts: p.pop('at', None)
        men[fn[:-4]] = posts
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(men, f, indent=1, sort_keys=True)
    tot = sum(len(v) for v in men.values())
    withleft = sum(1 for v in men.values() for p in v if 'left' in p)
    print(f'{out}: {len(men)} of {len(files)} men gave a dated posting, '
          f'{tot} postings, {withleft} with a leaving date')

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
