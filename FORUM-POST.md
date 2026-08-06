# BOB2 2.13 Modern Fix — gets Wings of Victory running properly on Windows 10 and 11

*Draft forum post. Copy the body below.*

---

## BOB2 2.13 Modern Fix — a launcher and configuration tool for Wings of Victory

Battle of Britain II still has the best campaign of any Battle of Britain sim, and it is twenty years old. Getting it running on a modern machine means a crash on the way into a mission, options screens drawn for a 1024-pixel monitor, and a frame rate that collapses for reasons nobody can see.

This is a companion app that deals with all of that. It is **not** a new patch and it replaces no game content — it sits alongside patch 2.13 and makes the game work.

**Download:** https://github.com/malawicob/bob2-modern-fix/releases

---

### What it does

**Gets the game started and keeps it started.**

The startup crash, the DPI shim Windows keeps putting back, and Direct3D. Details on why further down, because the "why" matters more than the list.

**Makes the menus readable.**

The briefing and options screens were laid out for a 1024-pixel-wide monitor. On a 1440p or 4K display they are unreadable. The mod rescales them to 102%, 110%, 125% or 140%, and it does it by editing the dialog layout inside `Bob.exe` itself — not by DPI scaling, which just makes everything blurry.

**Replaces the options screens.**

A settings window that edits `bdg.txt`, `keys.txt`, `settings.cfg` and `Weather.cfg` directly, so it does not depend on the game's own UI working at all. Graphics, view, weather, realism, key bindings, joystick axes, and every single `bdg.txt` value with the game's own inline comments beside it. Nothing is written until you press Save, and every file is copied to a timestamped backup first.

**Looks after your joystick.**

BOB2 rebuilds its axis configuration from factory defaults whenever the set of connected devices changes. Unplug your stick for a day, plug it back in, and your deadzones are silently back to 7.5% — which on a modern Hall-effect stick is a large dead patch right where gunnery happens. The mod keeps a reference copy of your settings and tells you the moment that has happened, with one button to put them back.

There is also a live axis test, per-axis deadzones (rudder wants a different value from pitch and roll if you fly with a twist grip), and Thrustmaster TARGET curves for the T.16000M.

**Measures the frame rate instead of guessing.**

A capture that never requires Alt-Tab — because BOB2 loses its Direct3D device and crashes if you do. You arm it, fly, and press a hotkey in the cockpit. Scroll Lock lights while it records.

**A setup wizard for people who just want to fly.**

Six questions, about three minutes, with the correct answer already selected at every step. Pressing Next six times produces a good result. No step is a dead end, nothing is irreversible, and it can be re-run any time to change an answer.

---

### What makes it different

**This is not the "BOB2 Windows 10 Patch".**

That is a separate and well-known package, and it is a good piece of work for what it is — but it is built on the **2.01** executable. By its own author's account it does not include patch 2.13's AI improvements, new ground objects or the MultiSkin feature. It also replaces textures, sounds and aircraft models with its own.

This mod is the opposite approach:

| | Windows 10 Patch | This |
|---|---|---|
| Built on | 2.01 executable | **2.13 executable** |
| 2.13 AI, ground objects, MultiSkin | not included | **kept** |
| Game content | replaces textures, sounds, models | **replaces none** |
| What it is | a repackaged game | a launcher and configuration tool |

If you are happy on 2.01, that package is fine. If you want 2.13 — and 2.13 is the better game — this is for you.

**It tells you what it is doing.**

Every screen states what it will change before it changes it. Install and repair shows one row per thing with its real state, and offers a button only where something is actually wrong. If everything passes it says so, plainly.

**It measures rather than assumes.**

The frame-rate advice in this mod is not folklore. It comes from CPU sampling of an actual flight, which showed the game is rendering-bound on the CPU rather than simulation-bound, and named the two functions that dominate — one of which is cloud lighting. That is why the wizard offers the specific settings it does.

---

### Why it works

Worth explaining, because these are the things that catch people out.

**The startup crash.** The game calls `DebugBreak()` somewhere in its startup path. On Windows XP that was usually survivable. On Windows 10 and 11, with no debugger attached, it kills the process. The mod renames the imported `DebugBreak` to `GetVersion` — both are ten characters, both take no arguments, and both return something the caller ignores, so the call becomes harmless. There is also a `dinput8.dll` guard that catches the same exception in a vectored handler, as a backstop.

**The menus that keep going small again.** Windows applies a `HIGHDPIAWARE` compatibility shim to `Bob.exe`, which cancels the menu rescale. Removing it once is not enough: the Program Compatibility Assistant silently puts it back. The launcher checks and removes it **every single time you press Play**.

**Direct3D.** BOB2 asks for Direct3D 9 in a way modern drivers do not answer well. dgVoodoo2 translates it to Direct3D 11. This is not optional on most modern cards — without it the game often will not start at all. DXVK is offered for completeness but crashes this game on entering 3D, and the mod says so where you choose.

**The menu rescale.** The game's screens are 154 Windows dialog templates inside `Bob.exe`, laid out in dialog units against an 8pt font. Every coordinate is a fixed-width 16-bit field, which means they can be patched in place. The tool rescales all 1,535 controls and their font sizes together. It was verified by generating a 1.0× patch and confirming the result is byte-for-byte identical to the original `Bob.exe` — if the maths were wrong anywhere, that test would fail.

**Frame rate.** Four settings cost more than everything else in the game put together — ground object density above 2 being the worst. The wizard offers to set them sensibly and tells you exactly what it is changing, with `bdg.txt` backed up first.

---

### What you need

1. **A licensed copy of Battle of Britain II: Wings of Victory** — https://a2asimulations.com/store/
2. **Patch 2.13**, if you are not already on it — https://www.a2asimulations.com/bob/downloads/BDG%20v2.13.7z

The mod ships neither. It applies the patch installers you supply, and the wizard checks for both and tells you what is missing.

**Windows 11**, any version, or **Windows 10** version 1809 and later. The mod checks and refuses to install on anything older, rather than half-working.

---

### Installing

1. Download the ZIP from the releases page.
2. Right-click it, Properties, tick **Unblock** if that option is there. Windows marks downloaded files and PowerShell may otherwise refuse to run them.
3. Extract so the `BOB2-Win11-Fix` folder sits **beside `Bob.exe`**.
4. Run **`BOB2.bat`**.

It offers to walk you through setup on first launch. Everything it changes is backed up first and can be undone from the launcher — but a copy of your game folder before you start is the only backup nobody regrets.

---

### The usual caveats

Unofficial community mod. Not affiliated with, endorsed by or connected to A2A Simulations, Shockwave Productions or Rowan Software. Provided as is, without warranty. Free, and never to be sold.

Source is on GitHub, so you can read exactly what it does to your install before you run it.

Bug reports and suggestions welcome — this has been tested on one machine, and one machine is not a sample.
