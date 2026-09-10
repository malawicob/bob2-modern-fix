Markings for the Bf 109, cut from Patrick's skin-preview tiles by
dev/build_lw_markings.py. This file is written by that script; edit the
script, not this.

  numbers/   1 to 15 in white, red, yellow and black
  gruppe/    the II. and III. Gruppe symbols, bar and wavy, in each colour
  stab/      the staff chevrons: Kommandeur, adjutant, technical officer
  emblems/   Geschwader and Gruppe badges
  bands/     JG 53's red fuselage band

Only the NUMBER was ever the pilot's own. The Gruppe symbol follows the
unit, the emblem follows the unit, and a chevron follows the appointment,
so the Room asks about the number and works the rest out.

The colour is the STAFFEL's, not the Gruppe's: white for the 1st, 4th and
7th Staffel, red for the 2nd, 5th and 8th, yellow for the 3rd, 6th and
9th. That is why 1., 4. and 7. all come out white although they sit in
three different Gruppen.

Numbers 1 to 15 exist in the Staffel colours and 0 and 16 in black only, so
0 and 16 are not offered: a number a man cannot have in his own Staffel's
colour is not a number he can have.

THE CANVAS IS KEPT. MultiSkin places the whole tile and sizes it as a
fraction of the 2048 skin sheet, and the glyph sits wherever it sits
inside it. Trim the padding and every digit lands somewhere different,
because a 1 is narrow and a 7 is not.

WHERE THEY GO IS NOT DECIDED HERE. ../marking-positions.json carries it,
read out of the game's own MultiSkin rules by dev/measure_markings.py,
and that includes WHICH symbol each unit wears. A table in this script
once said JG 3, JG 52 and JG 53 wore the wavy line; the rules give
III./JG 3, III./JG 51 and III./JG 53 the vertical bar and name III./JG 2
as the only wavy unit, and each symbol sits at its own position.

WHERE THE EMBLEMS DO AND DO NOT APPEAR

Every Gruppe with a profile painted in its own markings already wears its
badge in the artwork. II./JG 26's aeroplane has the Schlageter S on it
before the Room draws anything, and drawing ours on top gives it two. So
the emblem is drawn ONLY on the plain factory scheme, which is what a
Gruppe with no profile of its own falls back to.

JG 53's red band is cut but NOT DRAWN. It has no MultiSkin rule: the game
swaps the whole skin for it, so there is no position to read, and a guess
put it on top of the Gruppe's own symbol.

PROVENANCE, NOW SETTLED

These are BOB2's OWN textures. The skin-previews folder is a PNG
conversion of MultiSkin\MultiSkinTextures in the game install: 1,080 of
its 1,081 filenames match that folder exactly, with one extra. MultiSkin
is not a stray third-party pack either; it is a feature of the official
BDG patch from 2.08 onward, documented in the game's own
Docs\Multiskin\README - 2.08 Multiskin feature summary.txt, dated 2008.

So the question is not "where did these come from", it is "may a mod
redistribute 97 small crops of the game's own art". The mod is useless to
anyone who does not own BOB2, which is the ordinary footing for this, but
it is still somebody else's work and the BDG is a real and contactable
group. Credit them in the release notes, and ask if in any doubt.
