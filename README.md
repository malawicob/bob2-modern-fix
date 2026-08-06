# BOB2 2.13 Modern Fix

A companion app for **Battle of Britain II: Wings of Victory** — gets the 2005 game running properly on Windows 10 and 11, and replaces the options screens it shipped with.

> **Not** the community "BOB2 Windows 10 Patch". That is a separate project built on the **2.01** executable which replaces textures, sounds and aircraft models, and by its own author's account does not include patch 2.13's AI improvements, ground objects or MultiSkin. This is for **patch 2.13**, keeps all of it, and replaces no game content at all.

---

## What it does

**Gets the game running.** BOB2 predates several things Windows now takes for granted:

- Renames the imported `DebugBreak` to `GetVersion`. The game calls `DebugBreak()` somewhere; Windows XP usually survived that, Windows 10/11 treats it as fatal with no debugger attached.
- Ships a `dinput8.dll` guard that catches the same crash in a vectored handler, as a backstop.
- Removes the `HIGHDPIAWARE` compatibility shim — which the Program Compatibility Assistant silently re-applies, so it is checked and removed on every launch.
- Sets up **dgVoodoo2** so the game's Direct3D 9 calls reach a modern card.

**Makes the game usable.** The in-game briefing and options screens were drawn for a 1024-pixel-wide monitor and are unreadable on anything modern. The mod rescales them by patching all **154 dialog templates** inside `Bob.exe` — verified byte-for-byte neutral at 1.0×.

**Replaces the options screens.** A configuration window that edits `bdg.txt`, `keys.txt`, `settings.cfg` and `Weather.cfg` directly, so it does not depend on the game's own UI working. Every file is backed up before it changes, and nothing is written until you press Save.

**Looks after your joystick.** BOB2 rebuilds its axis configuration from factory defaults whenever the set of connected devices changes — unplug a stick for a day and your deadzones are silently gone. The mod keeps a reference copy and tells you when that has happened.

**Measures instead of guessing.** A frame-rate capture that never requires Alt-Tab, because BOB2 loses its D3D9 device and crashes if it does.

---

## What you need

1. **A licensed copy of Battle of Britain II: Wings of Victory** — <https://a2asimulations.com/store/>
2. **Patch 2.13**, if your game is not already at it — <https://www.a2asimulations.com/bob/downloads/BDG%20v2.13.7z>

This mod ships **no game content and no patches**. It applies the installers you supply. The setup wizard checks both on its first screen and says which, if any, are missing.

**Windows:** Windows 11, any version. Windows 10 version 1809 (build 17763) and later.

> The check uses the build number, never `ProductName`. On a Windows 11 25H2 machine the registry still reports `ProductName = "Windows 10 Home Single Language"` — Microsoft never updated that value.

---

## Installing

1. Download the ZIP from [Releases](../../releases).
2. Right-click it → **Properties** → tick **Unblock**, if the option is there. Windows marks downloaded files and PowerShell may otherwise refuse to run them.
3. Extract so that the `BOB2-Win11-Fix` folder sits **beside `Bob.exe`** in your Battle of Britain II folder.
4. Run **`BOB2.bat`**.

First launch offers to walk you through setup — six questions, about three minutes, with the right answer already selected at every step.

---

## Screens

| | |
|---|---|
| **Play** | Launches the game pinned to the P-cores |
| **Setup wizard** | Six steps: find the game, install the fix, graphics, menu size, joystick, frame rate |
| **Settings** | Graphics, view, weather, realism, key bindings, joystick axes, and every `bdg.txt` value |
| **Frame rate test** | Arm it, fly, press `ALT+SHIFT+F11`. Needs [PresentMon](https://github.com/GameTechDev/PresentMon/releases) in `tools\` |
| **Graphics translator** | dgVoodoo2, native D3D9, or DXVK |
| **In-game menu size** | 102% / 110% / 125% / 140%, patched into `Bob.exe` |
| **Joystick setup** | What is plugged in, which axis drives what, deadzones, drift detection |
| **Install and repair** | One row per thing with its real state, and a button only where something is wrong |

---

## Building a release

`Build-Release.ps1` produces the distributable ZIP. It exists because the working folder is a *live install* and accumulates machine-specific state — game folder path, text-size preference, joystick calibration, logs — none of which belongs in a release.

```powershell
.\Build-Release.ps1                 # ~2.4 MB, DXVK excluded
.\Build-Release.ps1 -IncludeDxvk    # includes DXVK
```

DXVK is excluded by default: 7.5 MB, two thirds of the package, for a wrapper this mod tells you not to use because it crashes the game on entering 3D.

---

## Third-party components

| | |
|---|---|
| **dgVoodoo2 2.8.7.3** | © Dege — <https://dege.freeweb.hu>. Shipped under the redistribution rights in the dgVoodoo readme: *"You can freely ship your game or game mod with individual dgVoodoo files included."* |
| **Lucide icons** | ISC licence — <https://lucide.dev> |
| **Photographs** | Imperial War Museums, public domain. IWM HU 54418 (32 Squadron at Hawkinge, 29 July 1940) and IWM CL186 (RAF Repair and Salvage Unit, Normandy, 19 June 1944) |
| **PresentMon** | Intel, not shipped — a separate download |

---

## Disclaimer

Unofficial community mod. Not affiliated with, endorsed by, sponsored by or connected to **A2A Simulations**, Shockwave Productions, Rowan Software, or any current or former rights holder in Battle of Britain II: Wings of Victory. All trademarks and copyrights belong to their respective owners.

Provided as is, without warranty of any kind. It modifies files inside your game installation. Every file it changes is backed up first and every change can be undone from the launcher — even so, a full copy of the game folder before you start is the only backup nobody regrets.

Distributed free of charge. Never to be sold.
