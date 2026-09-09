#!/usr/bin/env python3
"""Extract the Luftwaffe order of battle from the game's own file.

The RAF side of the Squadron Room reads squadronroom/oob.json, which was
lifted out of the game's English/TEXT/RAF_OOB.htm. The game ships a
sibling, LW_OOB.htm, and it is the whole German order of battle: 65
Gruppen across Luftflotte 2 and 3, each with its type, the date it came
into the line, its field, and the skill and fatigue the campaign starts
it on. Nothing here is invented.

    python3 dev/build_lw_oob.py \
        --src "D:/Battle of Britain II/English/TEXT/LW_OOB.htm" \
        --out squadronroom/lw/oob.json

The file is a table with the tags stripped: a Luftflotte heading, six
column names, then six lines per Gruppe, over and over. Reading it as a
flat list of lines and taking six at a time is enough, and is steadier
than trying to parse the 1990s HTML the game ships.

Two things are normalised on the way out and nothing else is:

  The unit. The file writes "I/JG3". A Gruppe is properly written
  "I./JG 3", and the Room needs the Geschwader and the Gruppe numeral
  apart from each other to group the postings board, so both are
  carried alongside the display form.

  The date. "24 July" becomes "1940-07-24", so it can be compared with
  the campaign date the same way the RAF file's period keys are.

The aircraft designation is left as the game gives it, with the hyphen
tidied, EXCEPT the Bf 109, which is marked E. Only the E flew in the
Battle, so that one is safe to state. The He 111 served as both the P
and the H that summer and the file does not say which, so it is left
unmarked rather than guessed at.
"""
import re, json, argparse, os, sys

MONTHS = {'January': 1, 'February': 2, 'March': 3, 'April': 4, 'May': 5,
          'June': 6, 'July': 7, 'August': 8, 'September': 9, 'October': 10,
          'November': 11, 'December': 12}

FIGHTERS = ('Bf-109', 'Bf-110')

# the six column headings, used to find and skip each table's header row
COLUMNS = ('Gruppe', 'Type', 'Activation', 'Field', 'Skill', 'Fatigue')

# The skill column is what tells us the field name has ended. One field,
# "Marck (Calais)", is written over two lines, so taking six lines per
# Gruppe put "(Calais)" in the skill column and pushed that whole record
# one place out. Reading the field until a skill word appears costs
# nothing and cannot be tripped by the next long name someone adds.
SKILLS = ('Veteran', 'Regular', 'Poor', 'Green', 'Novice')

UNIT = re.compile(r'^(Stab|I{1,3}|IV|V)/([A-Za-z]+)(\d+)$')


def text_lines(path):
    """The file's visible text, one item per line, blanks dropped."""
    with open(path, encoding='latin-1') as fh:
        raw = fh.read()
    txt = re.sub(r'<[^>]+>', '\n', raw)
    txt = re.sub(r'&nbsp;?', ' ', txt)
    return [l.strip() for l in txt.split('\n') if l.strip()]


def parse_date(s):
    m = re.match(r'^(\d{1,2})\s+([A-Z][a-z]+)$', s.strip())
    if not m or m.group(2) not in MONTHS:
        return None
    return '1940-%02d-%02d' % (MONTHS[m.group(2)], int(m.group(1)))


def tidy_type(s):
    t = s.replace('-', ' ').strip()
    return 'Bf 109E' if t == 'Bf 109' else t


def parse(lines):
    out = []
    luftflotte = None
    i = 0
    while i < len(lines):
        if lines[i] == 'Luftflotte' and i + 1 < len(lines) and lines[i + 1].isdigit():
            luftflotte = int(lines[i + 1])
            i += 2
            continue
        # the header row of each table: skip the six column names together
        if lines[i] == COLUMNS[0] and lines[i:i + len(COLUMNS)] == list(COLUMNS):
            i += len(COLUMNS)
            continue
        m = UNIT.match(lines[i])
        if m and i + 5 < len(lines):
            gruppe, arm, num = m.group(1), m.group(2), m.group(3)
            typ, act = lines[i + 1], lines[i + 2]
            j = i + 3
            parts = []
            while j < len(lines) and lines[j] not in SKILLS and len(parts) < 4:
                parts.append(lines[j])
                j += 1
            if j + 1 >= len(lines):
                break
            field = ' '.join(parts)
            skill, fatigue = lines[j], lines[j + 1]
            nxt = j + 2
            date = parse_date(act)
            if date is None:
                print('  ? could not read the activation date %r for %s'
                      % (act, lines[i]), file=sys.stderr)
            out.append({
                'unit': '%s./%s %s' % (gruppe, arm, num),
                'geschwader': '%s %s' % (arm, num),
                'gruppe': gruppe,
                'luftflotte': luftflotte,
                'type': tidy_type(typ),
                'fighter': typ in FIGHTERS,
                'activation': date,
                'field': field,
                'skill': skill,
                'fatigue': fatigue,
            })
            i = nxt
            continue
        i += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default='/mnt/d/Battle of Britain II/English/TEXT/LW_OOB.htm')
    ap.add_argument('--out', default='squadronroom/lw/oob.json')
    a = ap.parse_args()

    if not os.path.exists(a.src):
        print('Cannot find %s' % a.src, file=sys.stderr)
        return 2
    recs = parse(text_lines(a.src))
    if not recs:
        print('Parsed nothing. The file layout has changed.', file=sys.stderr)
        return 1

    # A Gruppe with no field or no date would show up on the postings board
    # as an empty row, so say so here rather than letting it through.
    bad = [r for r in recs if not r['field'] or not r['activation'] or not r['luftflotte']]
    for r in bad:
        print('  ! incomplete: %s' % r['unit'], file=sys.stderr)

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, 'w', encoding='utf-8') as fh:
        json.dump(recs, fh, indent=1, ensure_ascii=False)
        fh.write('\n')

    fighters = [r for r in recs if r['fighter']]
    fields = sorted({r['field'] for r in recs})
    print('%d Gruppen, %d of them fighters, over %d fields -> %s'
          % (len(recs), len(fighters), len(fields), a.out))
    print('Luftflotte %s' % ', '.join(str(n) for n in sorted({r['luftflotte'] for r in recs})))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
