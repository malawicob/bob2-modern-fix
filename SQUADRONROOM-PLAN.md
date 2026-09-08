# Squadron Room: the living squadrons plan

Approved in principle by Patrick, 8 September 2026. This file tracks the
work; it is not shipped (Build-Release leaves it out).

## The goal in one paragraph

Every squadron the player can join carries the men who really flew in it.
The known men, the aces above all, score their real victories on the real
dates, are wounded, captured or killed when history says so, and arrive
and leave when they did. Around them the squadron is brought up to its
real strength for the date with invented pilots, who live the war the
squadron is actually having in the player's campaign: they claim, are
shot down, are wounded and are replaced in step with what the game's own
records say the squadron did. The player looks at the dispersal board on
any day of the Battle and sees a squadron of the right size, with the right
faces, doing what that squadron was doing that week.

## Part A. Data

### A1. What a roster record becomes

One file per squadron, `squadronroom/rosters/<num>.json`, one record per
man:

    pilot        "Crossley, Michael N."           surname first, as now
    rank         "Flight Lieutenant"               rank on joining the Battle
    historical   true | false
    joined       "1940-07-10" | earlier date       first day on strength in the window
    left         null | "1940-09-04"               last day on strength
    left_reason  null | "posted" | "rested" | "KIA" | "WIA" | "POW" | "MIA" | "DoW" | "promoted"
    fate         { "status": "KIA", "date": "1940-08-18", "note": "..." }   optional
    victories    [ { "date": "1940-07-20", "type": "Bf 109E", "kind": "destroyed" }, ... ]
    awards       [ { "award": "DFC", "date": "1940-07-16" }, ... ]
    codes        "GZ-K" | ""                        where known
    serials      "P3522" | ""                       where known
    src          "Holloway list (Wikipedia)" | "Wikipedia biography" | "IWM caption" | "invented"
    note         free text, one line

`victories` replaces the single `victories` integer. `joined`/`left`
replace the all-men-all-days board.

### A2. Real men: sources and method

1. Names, squadrons and fates for all 22 postings-map squadrons from the
   Air Ministry / Holloway list of the Few as carried by Wikipedia's "List
   of RAF aircrew in the Battle of Britain" (CC BY-SA, already the source
   for No. 32). Harvest with the Special:Export route that worked for 32:
   one wikitext fetch per letter page, parse the table rows, keep every
   row whose squadron list includes one of ours. Expected 700 to 900 men.
2. Aces and decorated men: for every name with a Wikipedia biography
   (the list links them), fetch the article and extract: victory count
   and, where the article gives them, dated claims; awards with gazette
   dates; posting dates in and out of the squadron; wound, capture and
   death dates. Structured where the infobox has it, otherwise from the
   prose by hand for the 60 or so aces that matter most.
3. Join and leave dates for the rest: the Holloway list gives the
   squadrons each man served with but not the dates. The Battle of
   Britain London Monument's per-pilot biographies (bbm.org.uk) give
   posting dates in prose; facts are not copyrightable, wording is, so
   dates are transcribed, never text. Where no date can be found, the man
   is on strength from 10 July or from his first known event, and leaves
   at his fate date or at 31 October.
4. Squadron codes and serials from the same biographies where present,
   otherwise blank; the Room already invents a letter for the player only.
5. Every record keeps its `src`. A man with an invented date gets
   `"src": "Holloway list (Wikipedia); dates assumed"` so the board can
   be honest on request.

Order of work: the player's own squadron first (No. 32), then 92 (the
seed becomes a proper file), then the other 20 by the order they appear
on the postings map.

### A3. Squadron strength by date

Establishment for a 1940 fighter squadron: 12 aircraft on the line plus
reserves, and between 18 and 26 pilots on strength; 20 is the working
figure. For each squadron and each campaign day the board shows:

    real men on strength that day (joined <= day < left)
    + invented men to bring the total to the target strength

The target follows the squadron's phase in `oob.json`: 20 while in the
line, 24 in the first week after a move to 13 Group (resting squadrons
were topped up with new pilots), 16 in the last days before a squadron
was pulled out exhausted. Those three figures are the tuning knobs.

### A4. Invented men

Generated once per squadron and stored in the same file with
`"historical": false`, so they are stable across sessions and screens.
Names drawn from period-plausible British, Commonwealth, Polish and Czech
name lists in the proportions each squadron actually had (the Holloway
list gives nationality per man, so the mix is per squadron, not guessed).
Rank mostly Sergeant and Pilot Officer, one Flying Officer in ten, no
invented Flight Lieutenants (the flight commanders are always real).
Each gets a code letter not used by a real man, and a serial from the
squadron's real block.

### A5. What the invented men do

A deterministic daily simulation, seeded by squadron number and campaign
date, so the same day always shows the same board:

- Source of truth for the player's own squadron is the game. The save
  carries the squadron's victory tally (the field at 11100 that was
  mistaken for the player's) and the Diary keeps per-squadron records of
  aircraft lost and pilots lost; those are decoded next (they are the
  same Diary tables the Log Book came from). Each day, the squadron's
  new victories minus the real men's dated victories minus the player's
  are shared among the invented men, weighted by rank and time with the
  squadron; the squadron's losses minus the real men's dated fates land
  on invented men as wounded, missing or killed, and a replacement
  arrives three to six days later.
- For every other squadron, the same simulation runs on the squadron's
  historical weekly claim and loss rates, tabulated once from the
  research in A2 (a squadron's total claims and losses in the window,
  spread by the Battle's known phases: quiet July, the airfield attacks
  of late August, 15 September).
- The real men never move: their victories and fates are dated facts and
  the simulation only fills the space around them.

### A6. Data checks

A validator script (repo, not shipped) that fails the build if any roster
file has: a man with `left` before `joined`; a victory or award dated
outside his time on strength; a fate date with no matching `left`; more
than 26 or fewer than 12 men on strength on any campaign day; a duplicate
name within a squadron; or a real ace with zero victories.

## Part B. The Room

### B1. Fixes from the audit (all approved)

1. Phantom sorties: a missing snapshot no longer counts as a flight.
2. One source for sorties, rank and honours on every screen: the save's
   diary rows; the launcher's sessions only time flying hours.
3. Every squadron moves with the campaign: `Get-OobBase -Sqn -Date` from
   `oob.json` replaces the three 92-only special cases (header, map,
   paper), and `Ensure-Squadron`'s Biggin Hill default goes.
4. Board status as of the date: "On strength" until a man's fate date;
   MIA and "failed to return" coloured as losses; died-of-wounds shown on
   the date of death, not the shoot-down.
5. An empty diary table (new campaign, no sortie yet) is recognised.
6. Claims dated by the sortie they came from, not the day of the sync
   (needs the per-row date: the row's squadron index leads to the
   Diary's intercept and raid-pack records, which carry take-off time and
   date; decode and verify against the game's Log Book).
7. A null pilot record can never be overwritten with a stub.
8. New career archives the old pilot only when the new posting is chosen.
9. Dead code out: aircraft-marking drag, old victory reader, unused map
   projection, nine superseded globals, stale comments and the header
   that claims the Room writes nothing.
10. Re-check the flight marker when the window is activated, so a flight
    started from PLAY shows up without restarting the Room.
11. Luftwaffe bins respected on the logbook screen as they are in the
    sync (no UI reaches them yet; consistency only).
12. Diary table search window widened to the whole file, row cap raised
    to 200, sortie numbers taken from the game's slot index.

### B2. Features (all approved)

1. "Losses this week" line under the roster board.
2. Combat claims panel on the dispersal: dated rows with type.
3. "From the squadron" paragraph in the Morning Bulletin about the last
   sortie.
4. Rank and honours persisted with the date earned; a new campaign no
   longer demotes.
5. Per-sortie date column in the logbook (from B1.6).
6. Squadron scoreboard tile once real scores exist for the squadron.
7. Squadron confirmed from the save with a one-click adopt.
8. Pilot detail on click: biography line, victories to date, fate,
   source. Real men and invented men alike, the invented ones with their
   simulated record.
9. The bulletin lead shows its own date when it is not today's paper.

### B3. Dunkirk

1. Install button on the Install screen's "Dunkirk missions (optional)"
   row when the pack is absent; Remove when present.
2. A "Dunkirk, May 1940" card on the dispersal naming the four missions
   and where they sit in the game's Instant Action menu.
3. README and changelog entries for the pack, the Squadron Room and the
   Flight Training Module, none of which the shipped docs mention.

## Part C. Order and effort

| Step | What | Days |
|---|---|---|
| 1 | B1 fixes 1 to 5, 7 to 12, and the dead code | DONE 2026-09-08 |
| 2 | Roster schema (A1), loader, validator (A6); No. 32 converted | DONE 2026-09-08 |
| 3 | No. 32 research: aces, dates, codes (A2) | 1 to 2 |
| 4 | Strength model and invented men (A3, A4); board by date; features B2.1, B2.2, B2.8 | 2 |
| 5 | Decode the Diary's squadron records; per-row dates (B1.6, B2.5); simulation for the player's squadron (A5) | 2 |
| 6 | Harvest the other 21 squadrons (A2 step 1), aces pass (step 2) | 3 to 4 |
| 7 | Historical rates and simulation for the other squadrons (A5) | 1 |
| 8 | B2.3, B2.4, B2.6, B2.7, B2.9; Dunkirk B3 | 1 to 2 |
| 9 | Docs, release 1.7.9 | 0.5 |

Roughly three working weeks of sessions. Steps 1 and 2 first, then No. 32
end to end (3, 4, 5) so the whole idea is proven on the player's own
squadron before the other 21 are researched.

## Done so far

- **Step 1** (commit 49f8fa8, plus aba1c91 for the new-career baseline):
  every audit fix. Squadrons move with the campaign, the board no longer
  gives the war away, one source for a career, rank and honours persisted.
- **The postings map** (commit 7f0a2b0): opened to all 52 squadrons from
  the game's own order of battle, four campaign periods, fifteen more
  stations placed from latitude and longitude.
- **Squadron codes**: all 52 confirmed against two dated sources each.
  One correction found: No. 152 carried UM, not the SN we held. The
  September 1939 reallocation is the trap - BL for 609, AW for 504, TM
  for 111 and their like are 1938-39 codes.
- **Step 2**: the schema above is live. tools/roster_convert.py converts
  a roster to it, tools/roster_validate.py checks one before it is
  committed (neither ships). No. 32 and No. 92 are on it; the 92 seed
  file is gone and 92 is now an ordinary roster. The board shows the men
  on strength on the day and names the losses beneath it.

## Rules

- Facts from sources, wording our own; every record carries its source.
- Invented men are marked invented in the data and can be shown as such.
- Real men's dated events are never altered by the simulation.
- Every roster file passes the validator before it is committed.
- Nothing ships until No. 32 has been flown against for a campaign week.
