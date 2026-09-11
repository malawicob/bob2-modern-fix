162 Bf 109E SKINS, AND THE GAME CHOOSES WHICH.

Every plate here is named for the MultiSkin texture it was drawn from,
with _sideview appended: M109ULF_IIIJG26_Camo_V2_sideview.png for
M109ULF_IIIJG26_Camo_V2.DDS. That is what makes the lookup buildable
from the game's own rules with nothing mapped by hand, and it is why
Patrick redrew all of them on 11 September 2026.

WHAT THEY REPLACED, AND WHY

Forty plates named per Gruppe, picked by unit name with no reference to
the campaign date at all. They were Bf 109Fs, which 33lima spotted, and
they carried their unit markings and the yellow cowl already painted on,
so a Gruppe on 10 July wore recognition markings it did not have for
another month and went on wearing them whatever the date.

There was a brief stop on the way: one bare E with the markings painted
on, which fixed the airframe and the yellow but showed every Gruppe the
same aeroplane. These are better, because they are the aeroplanes the
game will actually put him in.

HOW ONE IS CHOSEN

dev/build_lw_109_skins.py reads Me109MainSkin.ms into skins109.json:
178 rules IN FILE ORDER, and the first match wins. A rule may name a
unit, an aeroplane (planeid 1 to 36), and a date. 27 name no unit, one
names nothing at all - Replacement.DDS, the catch-all. Get-Profile109
walks them in that order.

THE GAME COMPOSITES, AND SO DOES THE ROOM

A main skin is camouflage, the Balkenkreuz and the swastika, and nothing
else. The number, the Gruppe symbol and the Geschwader badge are laid
over it from Me109_PlaneID_1.ms, Me109_PlaneID_2.ms and Me109_Emblem.ms,
and the Room does the same.

Where a skin already carries one, the game points that overlay at
blank.dds, and so the Room must draw nothing. The case you would notice
is Galland: planeid 1 of fifteen units is blanked because a Kommandeur's
chevron is part of his skin, and drawing a number or a second chevron
over it would be obvious. See Test-MarkBlank.

THE CROSS IS STILL THE RULER

measure_markings.py converts MultiSkin's coordinates onto a plate by
finding the Balkenkreuz in both and scaling x and y between them, so
every one of these is measured separately.

Across 162 paint schemes no single detector manages it. The white border
finds 150 and reads 19 of those out of square; a darkness threshold
finds all 162 but clips an arm wherever it runs into dark camouflage,
which is what RLM70_71 does - its cross sits half on dark green and half
on light blue and reads 87 x 68 instead of 86 x 86. find_cross_109 runs
both and takes the squarest plausible answer.

Nothing is compared against the other plates any more. That was right
while they were forty copies of one drawing; these genuinely differ, and
M109ULF_IIIJG26_Bartels_G really is painted with a bigger cross, 97 px
against the usual 82.
