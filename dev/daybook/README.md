# The daybook: where each month came from, and what is not certain

`squadronroom/daybook.json` is built from these four files by
`dev/build_daybook.py`. Each record here keeps the URLs it was read from.
Researched on 21 September 2026. Text is in our own words; facts only.

## What the four figures are

| field | what it is | how it is labelled on the page |
|---|---|---|
| `raf_claimed` | Fighter Command's daily summary: destroyed by fighters plus by guns | "claimed at the time" |
| `raf_lost_announced` | the "own losses" line of the same summary | "announced lost" |
| `lw_lost_actual`, `raf_lost_actual` | per-day totals from battleofbritain1940.com (Fighter Command only on the British side) | "the records, after the war" |

These are NOT the figures of the next morning's newspapers, which often ran
higher and were revised. 15 August is the plain case: 161 here, 144 in the
Daily Mirror headline of 16 August, 169 in that day's communique, 180 in the
1941 pamphlet. The page says "claimed at the time" and nothing stronger.

## By month

- **July (10 to 31).** Post-war losses on all 22 days. Contemporary claims on
  one day only (25 July, 28, from a London cable in The Mercury, Hobart, 27
  July 1940): the RAF diary and the newspaper archives refused automated
  reading. The 10 July British loss of 2 looks low against other accounts.
- **August.** All four figures on all 31 days, contemporary ones from the
  archived RAF Campaign Diary. 8 and 11 August are "confirmed" only. 19 and 20
  August carry identical loss text in the archive and one may be a duplicate.
- **September.** Contemporary figures from the RAF diary on 29 of 30 days (5
  September is empty in every archive copy). 10 September British loss left
  out, the sources contradict each other. 15 September post-war count 61 and
  31 here; other sources give 58 and 29, older books about 56 and 26.
- **October.** One secondary site for everything; both archive copies of the
  RAF diary refused automated reading. Where its "announced" loss equals its
  post-war count the build does not print it as an announcement.

## Left out on purpose

Anything a source gave without a date, death tolls where sources disagree
(Woolston, Yeovil), convoy names where sources disagree (13, 14, 27 July),
the Vichy statute of 3 October, and "Hitler at Bayreuth" on 23 July, which
rested on photo captions. Some "reich" items are facts now known to history
that no German paper printed then (the Sea Lion directives and postponements,
the Berghof meeting of 31 July); the band is headed "from the record of 1940"
for that reason.

## To improve it

A person with a browser can open the RAF diary pages that refused the
researchers (archived raf.mod.uk/bob1940/) and fill July and October.
