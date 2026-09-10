RAF code letters, taken from the game's own skin tiles by
dev/build_raf_markings.py on 10 September 2026.

  letters/   A to Z, 128 x 128
  codes/     the 51 squadron codes the Room uses, 256 x 128

These are BOB2's own tiles: RAF Sky grey, the right typeface, and the
right proportions. The Room used to paint the codes as text in whatever
condensed font the machine happened to have.

THE CANVAS IS KEPT. MultiSkin places the whole tile and sizes it as a
fraction of the 2048 skin sheet, and the glyph sits wherever it sits
inside the tile. Trim the padding away and every letter lands somewhere
slightly different.

Where they go is in ../marking-positions.json, measured off the game's
own rules by dev/measure_markings.py:

    Spit_Squadron_Code.ms    0.11  x 0.055 at (1100, 768)
    Spit_PlaneID_Letter.ms   0.055 x 0.055 at (1445, 753)
    Hurri_Squadron_Code.ms   0.12  x 0.060 at (1218, 515)
    Hurri_PlaneID_Letter.ms  0.06  x 0.060 at (1583, 517)

The serial is NOT here. There is no tile for it: the game paints it into
the skin rather than placing it as a decal, so it stays drawn text.

NOT YET SEEN ON SCREEN. Every code resolves to a real file and all four
positions land on the aeroplane, but nobody has looked at a rendered
Spitfire wearing them: the dispersal only draws an aeroplane once the
pilot has a sortie in the campaign save, and the dev career has none.
New-Aircraft falls back to the old drawn text whenever a tile is missing,
so the worst case is the previous behaviour rather than a blank
aeroplane, but the first person to fly the dev install should look.
