#!/usr/bin/env python3
"""Find the latitude and longitude of every Luftwaffe field in the OOB.

    python3 dev/build_lw_fields.py --out squadronroom/lw/fields.json

The RAF map places every airfield from its own coordinates, and the
German one has to do the same or the Gruppen will sit in the wrong
fields. There is no LW equivalent of the game's RAF Fields.htm, so the
46 names in lw/oob.json have to be resolved from outside.

Most of them are not airfields with an entry anywhere. They are the
villages the fields were named for - Caffiers, Audembert, Peuplingues,
Colembert - so what is looked up is the PLACE, which is where the field
was, to within a mile. That is well inside a dot on a 2560px sheet
covering ten degrees of longitude.

The game's spellings are not always the place's. ALIASES below carries
every one that differs, with the reason, because a silent correction is
how a Gruppe ends up in the wrong country:

    Barley      -> Barly           Pas-de-Calais, not Barley in Herts
    Dinnard     -> Dinard          one N
    Colombert   -> Colembert       Pas-de-Calais
    St. Trond   -> Sint-Truiden    the Flemish name; it is in Belgium
    Orleans-Bricy -> Bricy         the village the air base is named for

Every answer is checked against the theatre's bounding box before it is
written, so a lookup that lands on a same-named place in another country
is reported rather than saved.

Nominatim asks for one request a second and a real user agent, and gets
both. Results are cached in the output file: run it again and it only
looks up what is missing.
"""
import json, argparse, os, sys, time, urllib.parse, urllib.request

UA = 'bob2-squadron-room/1.0 (patmillin@gmail.com)'
URL = 'https://nominatim.openstreetmap.org/search?%s'

# The theatre. Anything outside this is a wrong answer, not a field.
LAT_MIN, LAT_MAX = 46.5, 52.5
LON_MIN, LON_MAX = -5.5, 6.5

# game spelling -> what to actually ask for, and why
ALIASES = {
    'Barley':              ('Barly, Pas-de-Calais, France',        'Pas-de-Calais, not Barley in Hertfordshire'),
    'Dinnard':             ('Dinard, France',                      'one N'),
    'Colombert':           ('Colembert, Pas-de-Calais, France',    'Colembert, not Colombert'),
    'St. Trond':           ('Sint-Truiden, Belgium',               'the Flemish name; it is in Belgium'),
    'St. Omer':            ('Saint-Omer, France',                  ''),
    'St. Malo':            ('Saint-Malo, France',                  ''),
    'Orleans-Bricy':       ('Bricy, Loiret, France',               'the village the air base is named for'),
    'Chateaudun':          ('Chateaudun, France',                  ''),
    'Crepon':              ('Crepon, Calvados, France',            ''),
    'Rosieres-en-Santerre':('Rosieres-en-Santerre, Somme, France',  ''),
    'Etampes':             ('Etampes, Essonne, France',            ''),
    'Epinoy':              ('Epinoy, Nord, France',                ''),
    'Villacoublay':        ('Velizy-Villacoublay, France',         'the commune is Velizy-Villacoublay'),
    'Antwerp':             ('Antwerpen, Belgium',                  ''),
    'Marck (Calais)':      ('Marck, Pas-de-Calais, France',        'the OOB names the town beside it'),
    'Cormeilles-en-Vexin': ('Cormeilles-en-Vexin, France',         ''),
    'Beaumont-le-Roger':   ('Beaumont-le-Roger, Eure, France',     ''),
    'Carquebut':           ('Carquebut, Manche, France',           ''),
    'Plumetot':            ('Plumetot, Calvados, France',          ''),
    'Tramecourt':          ('Tramecourt, Pas-de-Calais, France',   ''),
    'Yvrench':             ('Yvrench, Somme, France',              ''),
    'Peuplingues':         ('Peuplingues, Pas-de-Calais, France',  ''),
    'Cocquelles':          ('Coquelles, Pas-de-Calais, France',    'one C in the middle'),
    'Hermelinghen':        ('Hermelinghen, Pas-de-Calais, France', ''),
    'Audembert':           ('Audembert, Pas-de-Calais, France',    ''),
    'Caffiers':            ('Caffiers, Pas-de-Calais, France',     ''),
    'Marquise':            ('Marquise, Pas-de-Calais, France',     ''),
    'Guines':              ('Guines, Pas-de-Calais, France',       ''),
    'Samer':               ('Samer, Pas-de-Calais, France',        ''),
    'Desvres':             ('Desvres, Pas-de-Calais, France',      ''),
    'Creil':               ('Creil, Oise, France',                 ''),
    'Laval':               ('Laval, Mayenne, France',              'Mayenne, not the Laval in Quebec'),
    'Orly':                ('Orly, Val-de-Marne, France',          ''),
    'Lannion':             ('Lannion, France',                     ''),
    'Montdidier':          ('Montdidier, Somme, France',           ''),
}


# Where the geocoder is confidently wrong. It is not enough for an answer
# to be inside the theatre: Epinoy came back at 50.66, 3.14 with a display
# name full of Belgian hamlets, well north of the Epinoy beside Cambrai
# that the Gruppe actually flew from, and it passed the bounding box test
# without complaint. Anything put here is a coordinate somebody has looked
# at, with the reason it is not the machine's answer.
OVERRIDES = {
    'Epinoy': (50.2242, 3.1522, 'the commune beside Cambrai; the lookup found a hamlet near Lille'),
}


def ask(query):
    q = urllib.parse.urlencode({'q': query, 'format': 'json', 'limit': 1})
    req = urllib.request.Request(URL % q, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=25) as r:
        out = json.loads(r.read().decode('utf-8'))
    if not out:
        return None
    return float(out[0]['lat']), float(out[0]['lon']), out[0].get('display_name', '')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--oob', default='squadronroom/lw/oob.json')
    ap.add_argument('--out', default='squadronroom/lw/fields.json')
    a = ap.parse_args()

    with open(a.oob, encoding='utf-8') as fh:
        oob = json.load(fh)
    names = sorted({r['field'] for r in oob})

    have = {}
    if os.path.exists(a.out):
        with open(a.out, encoding='utf-8') as fh:
            have = json.load(fh)

    bad = []
    for n in names:
        if n in have:
            continue
        if n in OVERRIDES:
            lat, lon, why = OVERRIDES[n]
            have[n] = [lat, lon]
            print('  %-22s %8.4f %8.4f   set by hand   <- %s' % (n, lat, lon, why))
            continue
        query, why = ALIASES.get(n, ('%s, France' % n, ''))
        try:
            got = ask(query)
        except Exception as e:
            print('  ! %-22s lookup failed: %s' % (n, e), file=sys.stderr)
            bad.append(n); time.sleep(1.1); continue
        time.sleep(1.1)
        if not got:
            print('  ? %-22s nothing found for "%s"' % (n, query), file=sys.stderr)
            bad.append(n); continue
        lat, lon, disp = got
        if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
            print('  ! %-22s %.4f,%.4f is outside the theatre: %s' % (n, lat, lon, disp), file=sys.stderr)
            bad.append(n); continue
        have[n] = [round(lat, 4), round(lon, 4)]
        print('  %-22s %8.4f %8.4f   %s%s' % (n, lat, lon, disp[:44], ('   <- ' + why) if why else ''))

    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(have, fh, indent=1, ensure_ascii=False, sort_keys=True)
        fh.write('\n')
    print('\n%d of %d fields placed -> %s' % (len(have), len(names), a.out))
    if bad:
        print('still missing: %s' % ', '.join(bad), file=sys.stderr)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
