#!/usr/bin/env python3
"""Build a roster of men for every fighter Gruppe.

    python3 dev/build_lw_rosters.py --out squadronroom/lw/rosters

WHAT THESE ARE, AND WHAT THEY ARE NOT

The RAF rosters are real. They are 2,282 men taken from the Air Ministry
list of the Few and the Battle of Britain London Monument's biographies,
and when the Room says a man was killed on 15 August it is because he
was.

There is no equivalent list for the Luftwaffe. So this builds two
different things and the Room must never present them as one:

  KNOWN MEN. A short list, below, of pilots whose unit and appointment in
  the summer of 1940 are a matter of ordinary record - Galland at JG 26,
  Moelders at JG 51, Wick at JG 2. They are marked historical:true. What
  is recorded for them is their name, rank, unit and what they were doing.
  NOTHING ELSE IS INVENTED FOR THEM: no fates, no dates, no scores. It is
  one thing to name a man who was there and quite another to write him a
  death he did not have.

  THE REST OF THE STAFFEL. Period-correct German names, dealt out per
  unit from a seed made of the unit's own name, so a Gruppe's men are the
  same every time the Room is opened. These men DO get a score and a
  fate: a handful of victories, and some of them killed, missing or
  wounded, because a Staffel where nobody is ever hit is not a Staffel.
  They are marked historical:false and the Room says on the screen that
  they are not men who lived.

That division is Patrick's, and it is the right one. A roster of names
with nothing beside them is a phone book; the invention is what makes it
a squadron. The line is drawn at real people: an ace gets only what the
record says, and everyone else is openly fiction.

The RAF side names its sources in every record and so does this: a
generated man carries src 'generated' and there is no pretending.
"""
import json, argparse, os, random, sys

# Surnames common in Germany in the period. Deliberately ordinary: the
# point is a Staffel of plausible names, not a list of famous ones.
SURNAMES = [
    'Bauer', 'Becker', 'Berger', 'Böhm', 'Brandt', 'Braun', 'Busch', 'Dietrich',
    'Eberhardt', 'Engel', 'Fischer', 'Franke', 'Frey', 'Fuchs', 'Gerlach',
    'Graf', 'Gross', 'Haas', 'Hahn', 'Hartmann', 'Heinrich', 'Hein', 'Herrmann',
    'Hoffmann', 'Horn', 'Huber', 'Jung', 'Kaiser', 'Keller', 'Kern', 'Kessler',
    'Kirchner', 'Klein', 'Koch', 'Köhler', 'König', 'Kramer', 'Krause', 'Krüger',
    'Kuhn', 'Lang', 'Lehmann', 'Lindner', 'Lorenz', 'Ludwig', 'Maier', 'Martin',
    'Mayer', 'Meier', 'Meyer', 'Möller', 'Neumann', 'Nowak', 'Peters', 'Pfeiffer',
    'Pohl', 'Reinhardt', 'Richter', 'Riedel', 'Ritter', 'Roth', 'Sauer', 'Schäfer',
    'Schmid', 'Schmidt', 'Schneider', 'Scholz', 'Schröder', 'Schubert', 'Schulz',
    'Schumacher', 'Schuster', 'Schwarz', 'Seidel', 'Simon', 'Sommer', 'Stahl',
    'Stein', 'Stephan', 'Straub', 'Thiel', 'Ulrich', 'Vogel', 'Vogt', 'Voigt',
    'Wagner', 'Walter', 'Weber', 'Wegner', 'Weiss', 'Werner', 'Wilhelm', 'Winkler',
    'Wolf', 'Wolff', 'Zimmermann',
]

FORENAMES = [
    'Adolf', 'Albert', 'Alfred', 'Anton', 'Arnold', 'August', 'Bernhard', 'Bruno',
    'Carl', 'Christian', 'Dieter', 'Eduard', 'Emil', 'Erich', 'Ernst', 'Erwin',
    'Franz', 'Friedrich', 'Fritz', 'Georg', 'Gerhard', 'Gottfried', 'Gunther',
    'Gustav', 'Hans', 'Hein', 'Heinrich', 'Heinz', 'Helmut', 'Herbert', 'Hermann',
    'Horst', 'Hubert', 'Joachim', 'Johann', 'Josef', 'Julius', 'Karl', 'Klaus',
    'Konrad', 'Kurt', 'Leopold', 'Lothar', 'Ludwig', 'Manfred', 'Martin', 'Max',
    'Otto', 'Paul', 'Peter', 'Rainer', 'Richard', 'Rolf', 'Rudolf', 'Rudi',
    'Siegfried', 'Theodor', 'Ulrich', 'Walter', 'Werner', 'Wilhelm', 'Willi',
    'Wolfgang',
]

# Men whose unit and appointment in the summer of 1940 are ordinary
# record. Name, rank, unit, and what they were doing - and nothing else.
#
#   (unit, rank, name, appointment)
#
# Keep this list SHORT and keep it to things that are not in dispute. A
# man is easy to add here and impossible to take back out of somebody's
# saved career.
KNOWN = [
    ('Stab/JG 26',  'Major',        'Galland, Adolf',        'Geschwaderkommodore from August 1940'),
    ('III./JG 26',  'Hauptmann',    'Schoepfel, Gerhard',    'Gruppenkommandeur'),
    ('II./JG 26',   'Hauptmann',    'Ebbighausen, Karl',     'Gruppenkommandeur'),
    ('Stab/JG 51',  'Major',        'Moelders, Werner',      'Geschwaderkommodore'),
    ('III./JG 51',  'Hauptmann',    'Trautloft, Hannes',     'Gruppenkommandeur to August 1940'),
    ('Stab/JG 2',   'Major',        'Wick, Helmut',          'Geschwaderkommodore from October 1940'),
    ('I./JG 2',     'Hauptmann',    'Wick, Helmut',          'Gruppenkommandeur before his promotion'),
    ('Stab/JG 3',   'Major',        'von Berg, Guenther',    'Geschwaderkommodore'),
    ('Stab/JG 27',  'Major',        'Ibel, Max',             'Geschwaderkommodore'),
    ('Stab/JG 53',  'Major',        'von Cramon-Taubadel, Hans-Juergen', 'Geschwaderkommodore'),
    ('I./JG 3',     'Hauptmann',    'von Hahn, Hans',        'Gruppenkommandeur'),
]

# What a Staffel looks like: mostly non-commissioned pilots, a few
# officers, one man in charge.
RANKS = (['Unteroffizier'] * 5 + ['Feldwebel'] * 4 + ['Oberfeldwebel'] * 2 +
         ['Leutnant'] * 3 + ['Oberleutnant'] * 1)

ESTABLISHMENT = 12          # pilots a Gruppe carries on this board

# How a Staffel's summer goes. Weighted so most men are alive with a few
# victories, a good number have none at all, and a minority do not come
# back - which is roughly the shape of a Jagdgruppe over the Channel.
FATES = (['On strength'] * 13 + ['Killed'] * 3 + ['Missing'] * 2 +
         ['Wounded'] * 2 + ['Prisoner'] * 1)


def unit_file(unit):
    """I./JG 26 -> I_JG26.json, which is a filename on every filesystem."""
    return unit.replace('.', '').replace('/', '_').replace(' ', '') + '.json'


def build(unit, known):
    # Seeded from the unit's own name, so a Gruppe's men do not change
    # between one opening of the Room and the next.
    rnd = random.Random('bob2-lw-' + unit)
    out = []
    for k in known:
        out.append({
            'pilot': k[2], 'rank': k[1], 'historical': True,
            'appointment': k[3], 'unit': unit,
            'joined': None, 'left': None, 'left_reason': None,
            'fate': None, 'victories': [], 'victories_total': None,
            'vic_source': 'not traced',
            'awards': [], 'staffel': None, 'portrait': None,
            'src': 'unit and appointment are ordinary record; nothing else recorded',
            'note': '',
        })
    used = {k[2].split(',')[0] for k in known}
    while len(out) < ESTABLISHMENT:
        sur = rnd.choice(SURNAMES)
        fore = rnd.choice(FORENAMES)
        if sur in used:
            continue
        used.add(sur)
        gi = ['I', 'II', 'III', 'IV', 'V'].index(unit.split('.')[0]) if unit.split('.')[0] in ('I','II','III','IV','V') else 0
        # A score, weighted so the Staffel has one or two men worth
        # watching and a good many with nothing yet.
        roll = rnd.random()
        if roll > 0.94:   vics = rnd.randint(9, 17)
        elif roll > 0.78: vics = rnd.randint(4, 8)
        elif roll > 0.45: vics = rnd.randint(1, 3)
        else:             vics = 0
        fate = rnd.choice(FATES)
        # a man is not shot down in July and still flying in October, so
        # anyone who did not come back has a date on it
        left = None
        if fate != 'On strength':
            left = '1940-%02d-%02d' % (rnd.choice([7,8,8,9,9,10]), rnd.randint(1, 28))
        out.append({
            'pilot': '%s, %s' % (sur, fore[0]), 'rank': rnd.choice(RANKS),
            'historical': False, 'appointment': None, 'unit': unit,
            'joined': None, 'left': left, 'left_reason': (None if fate == 'On strength' else fate.lower()),
            'fate': ({'status': fate, 'date': left, 'note': ''} if fate != 'On strength' else None),
            'victories': [], 'victories_total': vics,
            'vic_source': 'assumed',
            'awards': [], 'staffel': gi * 3 + rnd.randint(1, 3), 'portrait': None,
            'src': 'generated', 'note': '',
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--oob', default='squadronroom/lw/oob.json')
    ap.add_argument('--out', default='squadronroom/lw/rosters')
    a = ap.parse_args()
    with open(a.oob, encoding='utf-8') as fh:
        oob = json.load(fh)
    units = [r['unit'] for r in oob if r['fighter']]
    # the Stab flights are not in the order of battle but the known men
    # belong to them, so they are carried on their I. Gruppe's board
    os.makedirs(a.out, exist_ok=True)

    nknown = 0
    for u in sorted(set(units)):
        gesch = u.split('/')[1]
        mine = [k for k in KNOWN if k[0] == u or (k[0] == 'Stab/' + gesch and u.startswith('I.'))]
        recs = build(u, mine)
        nknown += len(mine)
        with open(os.path.join(a.out, unit_file(u)), 'w', encoding='utf-8') as fh:
            json.dump(recs, fh, indent=1, ensure_ascii=False)
            fh.write('\n')
    print('%d Gruppen written to %s' % (len(set(units)), a.out))
    print('%d men of record placed; the rest are generated and say so' % nknown)
    return 0


if __name__ == '__main__':
    sys.exit(main())
