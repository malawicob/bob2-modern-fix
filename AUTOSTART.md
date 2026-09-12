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

Squadron is not a start-up choice: the game picks it per sortie, and
`playersquadron` in the save records the last one.

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
name=Millin     up to 20 characters
```

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

## Not built yet

`mode=load`: a pilot with a campaign save. Needs `SetUpLoadGame`,
`SetUpRafLoadGame` / `SetUpLWLoadGame`, `DoLoadGame`, `CFiling::LoadGame` and
how the load page picks its file. Until then the Room writes no request for
such a pilot and the guided card stands.
