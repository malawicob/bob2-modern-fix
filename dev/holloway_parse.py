#!/usr/bin/env python3
"""Read the Air Ministry / Holloway list of the Few into a membership table.

This is the authority on WHO served with WHICH squadron. The Monument's
biographies give the dates, but they mention squadron numbers for all
sorts of reasons - a unit a man joined in 1942, one that shot him down -
so they cannot be trusted to say who was on a squadron's strength. Taking
membership from them put eighty men on a board that held twenty.

Wikipedia carries the list in seven articles, exported as raw wikitext.

    python3 dev/holloway_parse.py --xml /tmp --out ~/bob2/bbm/holloway.json
"""
import re, os, json, glob, html, argparse

# |[[Hubert Adair|Adair, Hubert Hastings "Paddy]]||Sgt||British||
#   [[No. 213 Squadron RAF|213]] &amp; [[No. 151 Squadron RAF|151 Sqns]]||DFC||notes
ROW = re.compile(r'^\|(.+)$')

def unlink(t):
    # Unescape FIRST. The wikitext holds &lt;!-- 42175 --&gt;, so stripping
    # tags before unescaping left the comment behind, and a man's rank read
    # "Plt Off<!-- 42175 -->" on the board.
    t = html.unescape(t)
    t = re.sub(r'\[\[[^|\]]*\|([^\]]*)\]\]', r'\1', t)
    t = re.sub(r'\[\[([^\]]*)\]\]', r'\1', t)
    t = re.sub(r'<ref[^>]*>.*?</ref>|<ref[^>]*/>', '', t, flags=re.S)
    # HTML comments carry the editors' service numbers and were ending up
    # inside a man's rank: "Plt Off<!-- 42175 -->"
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    t = re.sub(r'<[^>]+>', '', t)
    # wikitext emphasis: the list bolds some names, and ''' was ending up
    # in front of a man's surname on the readiness board
    t = t.replace("'''''", '').replace("'''", '').replace("''", '')
    t = re.sub(r'\{\{[^}]*\}\}', '', t)
    return html.unescape(t).strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--xml', default='/tmp')
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    men = []
    for f in sorted(glob.glob(os.path.join(a.xml, 'wp_*.xml'))):
        s = open(f, encoding='utf-8').read()
        for line in s.split('\n'):
            if not line.startswith('|') or 'Sqn' not in line: continue
            cells = [c for c in line[1:].split('||')]
            if len(cells) < 4: continue
            name = unlink(cells[0])
            # "[[Hubert Adair|Adair, Hubert Hastings "Paddy]]" -> surname first
            name = name.strip().strip('"')
            rank = unlink(cells[1])
            country = unlink(cells[2])
            sqtext = unlink(cells[3])
            awards = unlink(cells[4]) if len(cells) > 4 else ''
            notes = unlink(cells[5]) if len(cells) > 5 else ''
            sqns = sorted({int(n) for n in re.findall(r'\b(\d{1,3})\b', sqtext)
                           if 1 <= int(n) <= 700})
            if not sqns: continue
            men.append({'name': name, 'rank': rank, 'country': country,
                        'squadrons': sqns, 'awards': awards, 'notes': notes})
    with open(a.out, 'w', encoding='utf-8') as fo:
        json.dump(men, fo, indent=1, ensure_ascii=False); fo.write('\n')
    from collections import Counter
    c = Counter(s for m in men for s in m['squadrons'])
    print(f'{a.out}: {len(men)} men, {len(c)} squadrons')
    print('  largest rosters:', ', '.join(f'No. {s} ({n})' for s, n in c.most_common(6)))

if __name__ == '__main__':
    main()
