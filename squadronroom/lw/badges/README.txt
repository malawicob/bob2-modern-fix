pilot-badge.png is the Flugzeugfuehrerabzeichen, the pilot's badge. It
carries no swastika, which is what makes it safe on a public download.

Patrick supplied it as a PNG already on a transparent ground, so it
needed nothing done to it but cropping to the badge and scaling. The
apparently black interior of the wreath is genuinely clear; the opaque
black in the file is the badge's own shading, and it belongs there.

An earlier version was a line engraving on white paper, and it took three
operations: cutting the printed caption off, making the white
transparent, and inverting the whole drawing so it read as pale metal
against a nearly black tunic instead of vanishing into it. That version
worked but looked like a drawing. This one looks like a badge, and needed
none of it.

It is shown at 62 pixels where the RAF wings are shown at 52, because
this badge is taller than it is wide and the wings are the opposite, so
at equal height it looks the smaller thing.

The six collar patches are now proper embroidered ones supplied by
Patrick, replacing the flat ones dev/make_lw_badges.py drew from the
Moritz Ruhl plate. That script is kept: it records what the references do
and do not settle, and the gull counts it worked out are the counts these
were chosen by.

Choosing them needed care. Sixteen images arrived with duplicates among
them, and two of my first picks were wrong: one I read as two gulls has
one, and one I read as three has two. Each was checked at full size
against the verified counts before it was used.

  unteroffizier   1 gull,  no wreath
  feldwebel       3 gulls, no wreath
  oberfeldwebel   4 gulls, no wreath
  leutnant        1 gull + wreath and cord
  oberleutnant    2 gulls + wreath and cord
  hauptmann       3 gulls + wreath and cord

Several of the images show a chequerboard behind the patch. That
chequerboard is PAINTED ON, not transparency: the files are RGB. The ones
used are the plain white versions, whose background could actually be
removed.

ek2.png, ek1.png, ritterkreuz.png and eichenlaub.png are the Iron Cross
ladder. None carries a swastika. White backgrounds were flooded out from
the edges rather than cleared by colour: the crosses have pale silver
beading and the ribbons have white stripes, and a colour-based clear
would have eaten through both.

WHAT IS DELIBERATELY NOT HERE, and why

Of fourteen images supplied across two batches, four are used. The rest
are out, and the reasons are worth keeping because every one of them is
a plausible-looking German medal that would have been easy to add:

  Ritterkreuz mit Schwertern      swords instituted 21 June 1941
  ... mit Brillanten / in Gold    later grades again
  Winterschlacht im Osten         instituted 26 May 1942, and for the East
  Kriegsverdienstkreuz            for merit not in direct combat, which is
                                  why the RAF ladder leaves out the AFC
  two ribbon bars with devices    not identifiable as documented awards,
                                  so not used at all

The oak leaves ARE period-correct and are in: instituted 3 June 1940,
and both Moelders and Galland had them by September that year, which is
inside this campaign. In the Room they REPLACE the plain Knight's Cross
rather than sitting beside it, because the leaves clasp onto the cross a
man already wears; drawing both would show him with two of them.

THE AIR CREW BADGE (crew-badge.png)
-----------------------------------
The Fliegerschuetzen- und Bordfunkerabzeichen, worn by the man in the
back of a Bf 110. NOT the pilot's badge: same silver wreath, but the
eagle dives steeply and sits lower in it, and carries a bundle of
lightning bolts in its claws. The pilot's has none, and giving a
Bordfunker the pilot's badge would be RAF wings on an air gunner.

Supplied by Patrick, cut from its background by dev/cut_badge.py. The
first version he sent was the pilot's badge again - the two are similar
enough at a glance that it took putting them side by side to be sure.
They now differ by 52.7 mean grey at 64x64; the duplicate scored 12.6,
which is rendering variation rather than a different design.

I drew one before that and it was not good enough to sit beside a
photographic badge - dev/make_crew_badge.py is kept with the reasoning
at the top. Nothing calls it.
