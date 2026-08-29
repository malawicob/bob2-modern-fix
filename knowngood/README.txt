knowngood\settings.cfg

A complete SAVEGAME\settings.cfg captured from the proven working install
(audited 2026-08-29): campaign resolution 1920x1080 @ 60 Hz, 32-bit
(int32 at offsets 1416/1480/1544/1608), sane GFX options. 1786 bytes,
banner "Rowan Savegame: V 002".

Used by the repair action that replaces a damaged or differently laid out
settings.cfg (a tester's file read 67,110,784 at the width offset, which
is a different layout, not a resolution). The installer patches the four
resolution ints to the machine's own desktop mode before writing, backs
the old file up as settings.cfg.before-knowngood, and only ever runs when
the user asks. The game must be closed: it rewrites this file on exit.
