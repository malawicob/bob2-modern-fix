bf109.png is a PLACEHOLDER, supplied by Patrick on 9 September 2026.

It arrived as a JPEG on a black ground. The black was removed by flooding
inwards from the edges rather than by clearing every black pixel, because
the Balkenkreuz outlines, the propeller blades and the exhaust stubs are
themselves black and enclosed by the aeroplane; clearing them by colour
would have punched holes through it. It was then cropped to the aircraft
and scaled to 1000px wide, which is what spitfire.png and hurricane.png
are.

One difference from the RAF plates worth knowing before anyone writes the
marking code. The Spitfire and Hurricane arrive BARE and the Room paints
the squadron code, the individual letter and the serial onto them. This
109 already carries its Balkenkreuz and its yellow nose, so nothing
should be painted over it until a bare version exists.

It also carries a swastika on the fin. That is historically correct and
it is a decision for the project, not for the drawing: see the note in
the changelog.


TWO FAULTS IN THESE PLATES, both raised by 33lima on 10 September 2026.

FIRST, THE AIRFRAME IS A Bf 109F, NOT AN E. The tailplane has no bracing
struts under it, and an E has them; the cowling and spinner are the
rounded F shape rather than the E's flatter, more angular nose. The
Battle of Britain was fought on the E, so every one of these needs
replacing with an E profile. The note above already called the drawing a
placeholder, which it is, but nobody had said out loud that it is the
wrong mark.

SECOND, AND WORSE, THE 109 PROFILE DOES NOT FOLLOW THE CAMPAIGN DATE.
Get-GruppeAircraftPath picks a 109 plate purely by unit name:

    $key = ("$($G.unit)" -replace '\.','' -replace '/','_' -replace ' ','')

while the 110 goes through Get-Profile110 with -Date, because
Me110_MainSkin.ms carries date conditions and build_lw_110_skins.py
resolves them. So a Zerstoerer changes with the campaign and a 109 never
does. These drawings carry the yellow cowl, which means a Gruppe on
10 July 1940 is shown wearing recognition markings it did not have for
another month.

The fix is not a new lookup table. It is the same shape as the 110's: the
plates want a Summer 1940 basis with the unit badge and the Gruppe
marking, and the phase markings want to come on with the date, read from
the game's own rules rather than from a date typed in here.
