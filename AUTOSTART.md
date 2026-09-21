# AUTOSTART: how PLAY CAMPAIGN opens the game on the campaign map

The game offers no door: `Bob.exe` parses eight switches (`BORDER`, `DIAGS`,
`USE16`, `NOMEM`, `WINDOWED`, `SAVETILES`, `HOST`, `GUEST`) and `-0<n>`, which
is a timed autosave interval; `bdg.txt` has no start page key; `lastsavegame`
only preselects a row. So the crash guard, `dinput8.dll`, which already lives
inside the process, steers the front end from the inside.

## How the front end works (from the 2.12 PDB)

One MFC class, `RFullPanelDial`, 55 static `FullScreen` page structs in
`.data` (652 bytes each). Every button and list row goes through
`RFullPanelDial::OnSelectRlistbox(row, row)`:

```
next    = m_currentscreen->textlists[row].nextscreen
handler = m_currentscreen->textlists[row].onselect      (thiscall, may veto or rewrite next)
if (handler && !handler(&next)) return
if (next) LaunchScreen(next)                              (sets m_currentscreen, calls the page's InitProc)
```

`FullScreen` layout: `textlists` at +364, 24 bytes a row (`text` id, `nextscreen`,
`onselect` function pointer, this-delta, 8 spare); `InitProc` at +604. `text`
and `nextscreen` are static file data; `onselect` and `InitProc` are filled in
by the CRT dynamic initializers at start-up.

The intro page `introsmack` has exactly one row: `text 0`, `nextscreen title`,
`onselect CheckLobby`. With `SKIP_VIDEOS=ON`, `IntroSmackInit` posts `0x406`
and the row fires at once. `IntroSmackInit` is where `InitPreferences`,
`ReadBDGValues` (bdg.txt) and `Replay::DeleteTempFiles` run, so the intro page
must still be launched; only its exit is redirected.

The normal path is title, singleplayer (RAF or Luftwaffe: `gameside`),
campaignselect (phase: `whichcamp`), campaignentername (name, role: `gamestate`),
BEGIN. BEGIN is row 1 of campaignentername, whose handler is
`RFullPanelDial::LaunchMapFirstTime`: copies `campaigntable[whichcamp]` into
`Miss_Man.camp`, builds the target table, `StartUpMapWorld`, `SkipToDate`,
`LaunchMap`. `CampaignEnterNameInit` (the page's `InitProc`) loads the clean
node tree and the target table, so that page is launched for real rather
than skipped.

The unit IS a start-up choice in pilot mode, made on the Begin page's
ControlFly panel (see "His own unit" below); `playersquadron` in the save
records the unit of the last sortie flown.

## What the DLL does

Only when `SquadronRoom\autostart.txt` exists beside it. The file is renamed
to `autostart.done` on reading, so it is one shot; status lines are appended.

1. Verify the exe: base `0x00400000`, PE timestamp `0x5623a8e8`, the first
   24 bytes of `OnSelectRlistbox` and 16 of `LaunchScreen`, and the static row
   halves of `introsmack`, `campaignentername` and `campaignselect`. Any
   difference: log, `status=mismatch`, touch nothing.
2. A thread waits for `introsmack.InitProc` to become non-zero (initializers
   done), checks row 0's this-delta is 0 and its handler is in `.text`, then
   writes one pointer: `introsmack.textlists[0].onselect = AutostartHook`.
3. `AutostartHook`, on the UI thread inside the dispatcher: calls the original
   `CheckLobby`; sets `gameside`, `gamestate`, `whichcamp` (+0x1A9 on the
   dialog), the player name (`Save_Data+0xE3`, 20 chars), `SkipVideos`;
   rewrites `next` to `campaignentername`.
4. A thread timer (`SetTimer(NULL, ..)`, dispatched by the game's message
   loop after the handler has returned) waits for `m_currentscreen` to be
   `campaignentername`, then calls `OnSelectRlistbox(1, 1)`: BEGIN.

Status lines: `armed`, `name-page` (mode=name), `begin`, `ok`; or `off`,
`unsupported` (mode=load, not built), `bad-request`, `mismatch`, `no-init`,
`lobby-veto`, `fallback` (Begin page never became current; the player is
left there).

## Request file

```
mode=begin      begin | name (stop at the Begin page) | load (not built yet)
side=0          0 RAF, 1 Luftwaffe
role=4          4 pilot, 5 commander
phase=0         0 Convoys, 1 Eagle Attack, 2 Critical Period, 3 Blitz
unit=163        his unit as the game numbers it (SquadNum): Luftwaffe from
                oob.json sqidx (I./JG 3 = 160), RAF from the NODEBOB.H order
                with No. 32 = 64. 0 leaves the game's default.
name=Millin     up to 20 characters
```

### His own unit

In pilot mode the Begin page also carries the ControlFly panel: three combos
(group/Luftflotte, sector/Geschwader, squadron/Gruppe, plus an aircraft type
filter) whose handlers write `Miss_Man.camp.fav` (`CampaignZero::Fav`, 46 bytes
at `0x04efb050` in 2.13, `Campaign + 11384`, file offset 11412 in the save):
`squadron` (+18, RAF SquadNum), `geschwader` (+34, index into
`Node_Data.geschwader`, three Gruppen each, -1 any), `gruppe` (+38, **1..3,
0 any**: `ChangeAccelOn` tests `gruppe - 1`), `flotte` (+26, 0 any), `geschwadertype` (+30, 4 any), `group` (+6),
`ac` (+10, an aircraft TYPE filter on the RAF side), `sector` (+14).
`PackageList::IsPlayerUsedInDirectives` resolves those to a SquadNum, and the
campaign works from that unit. The panel's default is the first unit in the
list, which is how a Luftwaffe pilot who never touched it flew I./JG 3.
`LaunchMapFirstTime` saves and restores the block around its copy of the
campaign table in pilot mode, so the guard writes it in the BEGIN timer,
after the panel exists and before the press. Luftwaffe: `geschwader =
(unit-160)/3`, `gruppe = (unit-160)%3 + 1`. Settled by flight on 20 September
2026: a II./JG 26 pilot (unit 164) written as geschwader 1, gruppe 1 flew as
I./JG 26 (`playersquadron` 163), so the Geschwader index is zero based and in
SquadNum order, and the Gruppe field is one based with 0 meaning any, which
is what `NodeData::ChangeAccelOn` tests (`fav.gruppe == 0 || unit's gruppe ==
fav.gruppe - 1`). `IsPlayerUsedInDirectives` reads the same field zero based;
the game is inconsistent with itself and `ChangeAccelOn` is the one that
decides what the player flies.

The aircraft number or letter is not a start-up choice on either side:
`playeracnum` (file 11346) is the position taken in the flight on each sortie.

## Addresses, Bob.exe 2.13 (18 Oct 2015, 4,460,544 bytes, .text md5 d73ebbc2…)

| what | 2.13 | how it was pinned |
|---|---|---|
| `introsmack` | `0x00788e50` | one-row page whose row 0 next is `title` |
| `title` | `0x0078ce60` | rows `0xa34`, `0xa1f` (same string ids as 2.12) |
| `campaignselect` | `0x0078ddc0` | rows `0x47e`→title, `0x327`→campaignentername |
| `campaignentername` | `0x00788180` | rows `0x47e`→title, `0x327`→NULL, row 2→campaignselect |
| `singleplayer` / `gametype` | `0x00789b20` / `0x00787740` | three rows, third to title |
| `OnSelectRlistbox` | `0x00412fe8` | body bytes of 2.12 `0x004130f4` with the `LaunchScreen` rel32 wildcarded; member offsets identical (`0x17d`, `0x170`, `0x174`, `0x178`) |
| `LaunchScreen` | `0x00412f2e` | `profiling/names213.json` |
| `gamestate` | `0x04f4b358` | `SetUpPilot`/`SetUpCommander` bodies (`mov dword [..],4/5`) at `0x0059efbd`/`0x0059efcd` |
| `gameside` | `0x04f4b32c` | `SetUpLW` body at `0x0059efdd` |
| `Save_Data+0xE3` | `0x04f1e753` | `CampaignEnterName::OnTextChangedName` tail (`push imm; call strcpy; ret 4`) at `0x005a2ee0` |
| `BDG_Values.SkipVideos` | `0x06158a03` | the push after `"SKIP_VIDEOS"` in `ReadBDGValues` at `0x00686339` |
| `whichcamp` | `+0x1a9` | `ChangeCamp` region `0x0059ee40..` uses `[reg+0x1A9]` |
| `CheckLobby`, `LaunchMapFirstTime` | read at run time | `introsmack+0x174`, `campaignentername+0x18c` after initializers |

2.12 equivalents (for re-pinning): pages `0x00789f50`, `0x0078df60`,
`0x0078eec0`, `0x00789280`; `OnSelectRlistbox 0x004130f4`; `LaunchScreen
0x0041303a`; `gamestate 0x04f4c448`; `gameside 0x04f4c41c`; `Save_Data
0x04f1f760`; `BDG_Values 0x06159480`; `LaunchMapFirstTime 0x0059efa6`;
`CheckLobby 0x005ae463`; `ChangeCamp 0x0059ecd3`.

Tools: `~/bob2/ghidra/bobq` (2.12 symbols; `BOBQ_PROG=Bob213.exe` for 2.13),
`~/bob2/profiling/names213.json`, and the static row scan in this file's
history (python over the `.data` section, `.data` vma `0x766000` at file
`0x366000` in 2.13).

## Load (mode=load), built 21 September 2026

For a pilot with a campaign of his own (his `savePath`, chosen when he first
comes back from the game). The Room writes that file's name into the last-save
slot of `SAVEGAME\settings.cfg` (from byte 1766: last save, `Bob.cam`,
`Bob.prf`, each NUL-terminated) with the game closed, and a request:

```
mode=load
side=0          0 RAF, 1 Luftwaffe
save=Bob.bsR    for the log only; the game takes the name from settings.cfg
```

The game reads the name into `Save_Data.lastsavegame` at start-up. The hook
sends the intro exit to the Load Game page instead of the Begin page. Its
InitProc (`SetUpLoadGame`) builds the RAF list with that file selected; for
the Luftwaffe the timer presses row 1 (`SetUpLWLoadGame`, same name). Then
row 3, LOAD: `DoLoadGame` loads `selectedfile` and launches the map. Nothing
is written in the game's memory; two of its own buttons are pressed.

| what | 2.13 | how it was pinned |
|---|---|---|
| `loadgame` | `0x0078d0f0` | its dynamic initializer (2.12 `0x006bc78e`, 2.13 `0x006bc5de`) copies `SetUpRafLoadGame` into row 0; the page's static rows are RAF `0xa38`, LW `0xa39`, back `0x47e` to `title`; row 3 LOAD `0x494` / `DoLoadGame` is filled at run time and checked before it is pressed |

Status lines: `load`, then `ok`, or `fallback` if the page never came up or
LOAD left it on the page (the file would not load); the player is then on
the Load Game page with the Room's card.

## Back to the Squadron Room (both modes), built 21 September 2026

Leaving a campaign puts the game on its title menu and it keeps running, so
the Room (which returns when the game closes) stayed hidden. After a
successful begin or load the guard arms a 500 ms watch. The front-end panel
it steered is destroyed when the map opens (`CMIGView::LaunchMap`), so every
tick it finds the live one afresh: `RDialog::m_pView` (2.13 `0x0079e8f4`, 2.12
`0x0079f9f4`, read from `RFullPanelDial::LaunchMap`) then the view's
`m_pfullpane` at `+0x108`, NULL while the map or 3D is up. Once it has seen
NULL, and the panel's current screen is `title` again, it presses the title
row whose text is `0xf` (onselect `ConfirmExit`: saves preferences, restores
the display mode, closes the main window, no dialog).
