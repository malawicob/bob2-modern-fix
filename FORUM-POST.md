# BOB2 2.13 Modern Fix — gets Wings of Victory running properly on Windows 10 and 11

Battle of Britain II is twenty years old and still the best campaign in any Battle of
Britain sim. Getting it to run on a current machine is the problem, and most of the
advice about it online is either out of date, contradictory, or right for the wrong
reason.

This is a free companion app that installs alongside the game, gets it starting and
staying started, and replaces the options screens that no longer fit on a modern
monitor. It ships **no game content and no patches** — you supply patch 2.13 and it
applies it for you. Nothing in the game is replaced: the 2.13 AI, ground objects and
MultiSkin all stay exactly as the BDG left them.

Windows 11 any version; Windows 10 1809 and later.

---

## What it is not

It is **not** the community "BOB2 Windows 10 Patch". That is a separate and older
project built on the **2.01** executable, which replaces textures, sounds and aircraft
models, and by its own author's account does not carry patch 2.13's AI improvements,
ground objects or MultiSkin.

This is for **2.13**, keeps all of it, and changes no game content at all. It touches
the executable in two places only — both reversible, both explained below.

---

## What it does

**Gets the game running.** BOB2 predates several things Windows now takes for granted:

- Renames the imported `DebugBreak` to `GetVersion`. The game calls `DebugBreak()`
  somewhere. Windows XP usually shrugged that off; Windows 10/11 treats it as fatal
  when no debugger is attached. Both names are ten characters, take no arguments and
  return something the caller ignores, so pointing the import at `GetVersion` makes the
  call harmless. Nine bytes.
- Ships a `dinput8.dll` guard as a backstop — a transparent DirectInput proxy with a
  vectored exception handler that catches the same breakpoint exception, the SxS
  activation-context errors, and the null dereference behind the "More GFX" tab.
- Removes the `HIGHDPIAWARE` compatibility shim. This is checked and removed on
  **every** launch, because the Program Compatibility Assistant keeps a record for
  `Bob.exe` and silently puts the flag back after a crash or an odd exit — which is why
  one-off removals appear to "stop working" a few hours later.
- Sets up **dgVoodoo2**, without which the game does not enter 3D at all. See below.
- Turns off video playback, which is what the intro crash actually is.

**Makes the game usable.** The briefing and options screens were drawn for a
1024-pixel-wide monitor and are unreadable on anything current. The mod rescales them
by patching all **154 Win32 dialog templates** held as resources inside `Bob.exe` —
102%, 110%, 125% or 140%. The patcher is verified neutral: a 1.0× pass reproduces
`Bob.exe` byte-for-byte, and all 154 templates round-trip exactly. The original is kept
and restorable in one step.

**Replaces the options screens.** A configuration window that edits `bdg.txt`,
`keys.txt`, `settings.cfg` and `Weather.cfg` directly, so it does not depend on the
game's own UI rendering correctly: ~350 `bdg.txt` assignments, all 236 key bindings
with search and rebinding, the GFX settings, weather, joystick axes and deadzones.
Every file is backed up before it is touched and nothing is written until you press
Save.

**Looks after your joystick.** BOB2 rewrites `SAVEGAME\inputcfg.dat` when it exits, and
rebuilds the axis records from **factory defaults** whenever the set of DirectInput
devices changes — a stick unplugged, moved to another USB port, or simply enumerated in
a different order. Tuned deadzones silently become 7.5% and you find out in the air.
The launcher keeps a reference copy, compares against it on startup and again
immediately before Play, and offers to put your settings back.

There is also a device story worth knowing: axis assignment lives in
`DeviceDefaults.txt`, keyed by DirectInput GUID, and the shipped copy dates from 2005 —
a Saitek X36, an X45, a Logitech WingMan and a Thrustmaster Top Gun. Any stick made
since is unknown to the game, which is the real reason its controls screen is so
unhelpful. The mod detects what is plugged in and writes the entry. Thrustmaster TARGET
response curves are included for those who use it.

**Measures instead of guessing.** A frame-rate capture using Intel PresentMon that
**never requires Alt-Tab** — because BOB2 runs exclusive fullscreen through dgVoodoo2,
loses its D3D9 device when it loses focus, and does not survive the reset. Any guide
that tells you to Alt-Tab out to start a capture is wrong. Instead you arm it in the
launcher and trigger it from the cockpit with `ALT+SHIFT+F11` (Scroll Lock lights while
it records), or set a countdown and just get airborne. The CSV lands timestamped and
labelled so runs never overwrite each other.

**Setup wizard.** Six steps, about three minutes, with the right answer already
selected at each one — find the game, install the fix, graphics translator, menu size,
joystick, frame rate. Pressing Next six times produces a good result. No step is a dead
end and it can be re-run at any time.

---

## Why it works — the two crashes, explained properly

### 1. The display-mode crash, and why dgVoodoo2 is mandatory

First, the fact that most of the existing advice gets wrong: **BOB2 2.x is a Direct3D 9
game.** `Bob.exe` imports `d3d9.dll` and `d3dx9_35.dll` and has *no* DirectDraw or D3D7
imports at all. The 2005 retail release was D3D7; the 2.x patch series rewrote the
renderer. So every explanation built on "D3DImm.dll wraps D3D7, that's the fix" is
describing a code path that is never loaded.

Entering 3D on a modern display, the engine's mode selection fails and it requests a
fullscreen swap chain of **Width=0, Height=0, Format=Unknown** — invalid in Direct3D 9.
The device is therefore never created, the renderer's device pointer stays NULL, and
`Renderer::SetGamma` dereferences it:

```
EXCEPTION_ACCESS_VIOLATION in Bob.exe at 0023:00528E94
Read from location 00000000
```

Confirmed from three independent directions: DXVK's own log showing the 0 × 0 request,
the faulting address above, and the engine's own assert —
`D3DERR_INVALIDCALL in .\RenderD3D9.cpp at line 1702`.

All three wrappers were tested on the same machine:

| Wrapper | Result |
|---|---|
| **dgVoodoo2** | **The only one that works** |
| Windows' native Direct3D 9 | CTD — identical crash |
| DXVK | CTD — identical crash |

dgVoodoo2 succeeds because `DefaultEnumeratedResolutions = all` and
`EnumeratedResolutionBitdepths = all` hand the 2005 engine the legacy display-mode list
it expects to choose from. It is not a performance tweak and not an optional
compatibility layer — without it the game does not start.

This also puts a long-standing community story to bed. The failure happens **at device
creation, before flight** — so "the 2.02+ executables crash in flight" was never the
right description of it.

### 2. The intro video crash

The 30 files in `Avi\` are Indeo Video 5 (`IV50`). Microsoft removed the Indeo codecs
from Windows on security grounds, so no decoder is present on 10 or 11. DirectShow
fails while building its filter graph and the game goes to desktop. The failure
surfaces inside `mpg2splt.ax` as it probes candidate filters, which is why that DLL was
blamed for years — but the cause is the missing codec, not a bug in the splitter.
Disabling video in `bdg.txt` means the graph is never built. (Installing LAV or ffdshow
is a perfectly good alternative if you want the videos back.)

---

## Performance — density, not resolution

BOB2's simulation runs on a Windows multimedia timer independent of the render loop, so
a higher frame rate does **not** speed the game up. And the engine is heavily CPU-bound:
on a current machine the CPU takes several times longer per frame than the GPU.

Two consequences, both measured rather than assumed:

- **Ground-object density governs your frame rate. Resolution is close to free.** Run
  the game at your monitor's native resolution and spend the budget on
  `OBJECT_DENSITY` instead — 4 roughly halves the frame rate against 2.
- **Pin it to the P-cores.** BOB2's engine is effectively single-threaded, and on Intel
  hybrid CPUs (12th gen and later) Windows will happily schedule it onto an efficiency
  core. The launcher's Play button starts it pinned. (Single-core pinning gives a
  higher average but noticeably more stutter — measured, and not recommended. It is
  still there for testing.)

On the development machine — i9-13900HX / RTX 4080 at 2560×1600 — power plan, P-core
pinning and object density together took it from **28 to 95 FPS median**. Your numbers
will differ, which is exactly why the frame-rate test is in the package: measure your
own, don't inherit mine.

One trap worth repeating: forcing antialiasing to 2×/4×/8× in `dgVoodoo.conf` can break
the game's options-screen display. Leave it `appdriven`.

---

## What you need

1. A licensed copy of **Battle of Britain II: Wings of Victory** —
   <https://a2asimulations.com/store/>
2. **Patch 2.13**, if you are not already on it —
   <https://www.a2asimulations.com/bob/downloads/BDG%20v2.13.7z>

That is the whole prerequisite list. 2.13 replaces the older patch chain; you do not
need to walk 2.01 → 2.02 → … first. The setup wizard checks both on its first screen
and tells you which, if any, is missing.

Intel **PresentMon** is a separate optional download, needed only for the frame-rate
test.

## Installing

1. Download the ZIP from the Releases page.
2. Right-click it → Properties → tick **Unblock** if the option is there. Windows marks
   downloaded files and PowerShell may otherwise refuse to run them.
3. Extract so the `BOB2-Win11-Fix` folder sits **beside `Bob.exe`** in your Battle of
   Britain II folder.
4. Run **`BOB2.bat`** and take the setup wizard.

Everything it changes is backed up first, and every change can be undone from the
launcher. Even so — take a full copy of the game folder before you start. It is the
only backup nobody ever regrets.

---

## Credits and small print

dgVoodoo2 © Dege (<https://dege.freeweb.hu>), shipped under the redistribution
permission in its own readme. Icons from Lucide (ISC). Launcher photographs from the
Imperial War Museums, public domain — IWM HU 54418 (32 Squadron at Hawkinge, 29 July
1940) and IWM CL186. PresentMon is Intel's and is not redistributed here.

Thanks to the BDG for 2.13, without which none of this would be worth doing.

Unofficial community mod. Not affiliated with, endorsed by, sponsored by or connected
to A2A Simulations, Shockwave Productions, Rowan Software, or any current or former
rights holder in Battle of Britain II: Wings of Victory. All trademarks and copyrights
belong to their respective owners. Provided as is, without warranty of any kind.
Distributed free of charge — never to be sold.

Bug reports, corrections and "that's wrong on my machine" reports all welcome. Several
things in the technical section above were themselves corrections of earlier confident
guesses, so I would rather be told.
