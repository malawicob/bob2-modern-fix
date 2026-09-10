# Populating the German airfields — a scope, not a plan

Patrick asked whether the German-held airfields are dressed the way the British
ones are. They are not, and this is what it would take to change that. **Nothing
here has been built.** It is a study so the decision can be made on figures.

## The gap, measured

Two mechanisms place scenery, and the German fields are empty in both.

**The game's own battlefield data**, `BFIELDS/`:

| | files | carrying objects |
|---|---|---|
| `RAFAF` | 145 | 109 |
| `LUFAF` | 62 | **0** |

Every one of the 62 Luftwaffe files is 33 bytes: the header `BATTLEFIELD Jul 18
2001` and nothing after it. The Rowan-era sources tell the same story — 
`SRC/BFIELDS/LUFAF/GFABBEVI.BFI` is an 84-byte stub with an empty `Title {}` and
`Comment {}`. **The German fields were never authored, in data or in source.**

**The BDG's `ObjectAdds/`**, 295 files and 87,272 objects. Counted by real
distance to each field's own reference point rather than by filename:

| field | objects within 2 km |
|---|---|
| Wissant | 906 |
| Le Havre | 116 |
| Abbeville | 78 |
| Coquelles | 61 |
| Peuplingues | 57 |
| St Omer | 21 |
| Marck | 3 (Calais town landmarks, not the field) |
| **the other 49** | **0** |

Against a British median of **203** objects per dressed field, and 31 of 44 RAF
fields dressed at all.

## The format, which is simple

The exe's own format strings settle it:

```
read   "%lu,%lu,%f,%lu"       write  "OBJECT_ADD %lu,%lu,%f,%lu %s"
```

So: **X, Z, heading, shape id**, plus an optional trailing tag. `#` comments,
blank lines free. The game **globs `ObjectAdds\*.txt`** — there is no manifest,
which is why the release notes tell users to delete files to save frame rate.

Coordinates are the game's absolute world grid, the same one the battlefield
files use. Roughly **90 units per metre**; the engine treats 100 units as a metre
against a map stretched about 1.1x, which the source calls out itself:
`DOSDEFS.H` carries `//cludge for fact that Paul encoded yards instead of metres`
and `#define MAPSCALE 1.1`.

**Coordinates do not need deriving.** `SRC/BFIELDS/MAINWLD.BFI` already holds a
`SetUID UID_AF_<name>` reference point for **all 56** Luftwaffe fields on that
same grid, plus runway and taxi markers. Abbeville is X 41,389,568 Z 21,546,496,
and the existing `FRANCE_Abbeville.txt` sits at a median of 41,389,713 /
21,598,422 — the same place. An empirical fit from England degrades by 2-4 km
when extrapolated into France, so use MAINWLD.BFI and not a projection.

## The parts already exist and are unused

`Docs/List_From_Bin_catalog.txt` is a full 1,003-line object catalogue, and
`SRC/H/SHAPENUM.G` is the machine-readable enum behind it. The numbering agrees
where they overlap. The **German airfield kit is entirely modelled**:

> 411-414 Blitz truck, fire tender, ambulance · 415-416 Horch command · 417-418
> Kübelwagen · 419-421 Flak 18, Flak 38, Flakvierling · 422-424 Mercedes staff
> car and fuel truck · 425 Renault tankette · 426-427 SdKfz 7 · 429-430 flak
> revetments · 433-435 Dutch and French barns · **436-437 French hangars** ·
> **438 lwhut · 439 lwrevet · 440 lwtent** · 441 omhq · 442-443 Luftwaffe ground
> crew figures · 503 tent hangar

Every matching `.bin` is on disk. None of it is placed at a German field.

## What one field looks like

Distilled from Abbeville, Le Havre, Peuplingues and Coquelles: **60-115 objects**
over 1-3 km, of which **half to two-thirds is trees** (ids 62, 63, 1192), and the
rest a small kit — 8-12 `lwtent` or 7 `lwrevet`, a few barns for the
requisitioned-farm look, a hangar where there was one, one or two flak pieces
with revetments, a handful of vehicles, ground crew, bomb trolleys, drums.

The author worked cluster by cluster: consecutive lines 7-50 m apart in runs
(a dispersal, then the MT lines, then a farm group), separated by 200-600 m
jumps.

## There is a tool, and it is already shipped

`bdg.txt` carries `OBJECT_PLACEMENT_MODE=OFF` and
`ENABLE_MOUSE_PLACEMENT_MODE=ON`, both documented in the v2.13 manual. With it on
you place objects with the mouse in-game, and on exit the session is written back
as `new_<original>.txt` for merging by hand:

```
Your edited object list was written to files starting with 'new_'
The old files are still there as well.
```

**The key bindings are not documented in this install.** The manual defers to a
"3D Modeler's Pack" which is not present. That is the one real unknown standing
between here and a first field.

## Effort, honestly

| | |
|---|---|
| Fields with nothing | 42 of 46 in the order of battle |
| Objects per field | 60-115, British median 203 |
| Total to place | roughly 3,000-5,000 objects |
| Coordinates | already known, from MAINWLD.BFI |
| Models | already exist, all of them |
| Format | trivial, four numbers a line |
| Tool | shipped, undocumented keys |

The work is **not** technical. It is placement judgement — where the dispersals
were, where the tents went, which farm the Gruppe took over — done 42 times. A
first field is an afternoon once the placement keys are found; forty-two is a
project, and a better one if it is split between people who know the fields.

A cheaper middle course exists: a **template**. One good Kanalfront field built
by hand, then stamped at the other 41 reference points with the layout rotated to
each runway heading from MAINWLD.BFI. Less true, far quicker, and much better
than an empty field. Note that the BDG started something similar and abandoned
it: `frenchvillages.txt` and `frenchvillagetemplate.txt` are both blanked stubs
marked "Was an experimental file".

## Unknowns

- The heading convention. Values in the shipped files run from -111,813 to
  +252,404, so the data proves nothing; the engine evidently reduces mod 360.
- The cap behind the exe's `Too many object add files!!` warning. 295 load today.
- Whether ObjectAdds objects can be damaged, or only collided with. They do have
  collision: the manual credits `FIX_OBJECTADDS` with fixing "collisions and
  explosion problems on take-off and landing at certain airfields".
