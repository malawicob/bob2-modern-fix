ONE BARE Bf 109E, and everything else painted on.

bf109e.png is the only 109 plate. It replaced forty of them on
10 September 2026, and the reason is worth keeping.

WHAT WAS WRONG WITH THE FORTY

They were Bf 109Fs. The tailplane carried no bracing struts and the cowl
and spinner were the F's rounded shape, where an E has struts and a
flatter, more angular nose. The Battle of Britain was fought on the E.
33lima spotted it.

They also carried their unit's markings and the yellow cowl already
painted on, and Get-GruppeAircraftPath picked one by unit name with no
reference to the campaign date at all, where a 110 goes through
Get-Profile110 with the date. So a Gruppe on 10 July wore recognition
markings it did not have for another month, and went on wearing them
whatever the date.

Matching the game would not have fixed that. Me109MainSkin.ms holds 126
distinct base skins chosen by unit AND individual aircraft number, and
only 5 of its 178 rules carry a date at all, against 113 of the 110's
114. There is no rule anywhere that puts the yellow on by date; it is
painted into each .DDS. Copying the 110's approach would have meant
about 126 drawings and would still have shown a yellow nose in July.

WHAT REPLACED THEM

The way the RAF side always worked. spitfire.png and hurricane.png arrive
bare and the Room paints the code, the letter and the serial on, so one
drawing serves every squadron. This does the same: the number in the
Staffel's colour, the Gruppe symbol, the Geschwader badge, and a Stab
chevron where one is due, all placed from the game's own MultiSkin rules
by dev/measure_markings.py.

The drawing carries its Balkenkreuz, and that is deliberate. The cross is
the RULER: measure_markings.py converts MultiSkin's texture coordinates
onto a plate by finding the national marking in both and scaling x and y
between them. A plate with no cross cannot be measured at all, and the
first version supplied had none, which is why there was a second.

WHAT IS STILL NOT DONE

The recognition markings. The yellow cowl and rudder came in through the
late summer of 1940 and this drawing has neither, which is right for July
and wrong from about the end of August. Painting them on by campaign date
is the remaining piece, and it has to be a historical rule of our own
because the game does not carry one.

The cut is dev/build_lw_aircraft.py at its usual settings. The aerial
wire comes out dashed where it crosses open sky, because in this drawing
it is a single antialiased pixel that is nearly black against a black
ground. At the 340px the Room draws these at, it is invisible.
