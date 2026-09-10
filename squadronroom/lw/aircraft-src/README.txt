THE BARE Bf 109E, and what it still needs.

bf109e_bare.png is the drawing Patrick supplied on 10 September 2026,
cut out of its black ground by dev/build_lw_aircraft.py at the settings
that already work, and scaled to 1000px wide like every other plate. The
JPEG beside it is the source as it arrived.

It is NOT in aircraft\ yet, on purpose. It cannot be used until the
problem below is solved, and a plate that cannot be measured would draw
a bare aeroplane with no markings on it at all.

WHY IT IS THE RIGHT DRAWING

It is an E. The tailplane carries its bracing strut, which an F does not
have, and the cowl and spinner are the E's flatter, more angular shape.
Every plate in aircraft\ is an F, which 33lima spotted.

It is also bare: no Balkenkreuz, no number, no Gruppe symbol, no
Geschwader emblem. That is what makes one drawing able to replace all
fifty four, the way spitfire.png and hurricane.png already do on the RAF
side, where the Room paints the code, the letter and the serial on.

WHY IT CANNOT BE USED YET

The Balkenkreuz IS THE RULER. dev/measure_markings.py converts the
MultiSkin coordinates onto a plate by finding the national marking in
the texture and in the drawing and scaling x and y between them, and
squadronroom/marking-positions.json therefore measures every plate
separately, "because there are forty of them and they do not all put the
cross in the same place".

This drawing has no cross, so there is nothing to measure against, and
the Room's own fallback is deliberate: an unmeasured profile "gets a bare
aeroplane and the note says so".

Two ways out, and the first is much the better:

  1. The same drawing again WITH the Balkenkreuz on it. Measure the cross
     on that, use the offsets on this one. Exact, and it needs no new
     method.

  2. Measure against the airframe instead: nose tip, tail tip and the
     fuselage top and bottom give a longer baseline than the cross does,
     so in principle it is more accurate, not less. But it assumes the
     texture maps to the side view linearly over that whole span, which
     the cross method never had to assume over its 150px.

ONE MORE THING TO SETTLE

The rudder is already yellow. If the recognition markings are going to be
painted on by campaign date, which is the point of going bare, then the
rudder wants to be grey here and the yellow wants to be one of the things
the Room adds after the date it was actually applied.
