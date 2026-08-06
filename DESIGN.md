# Battle of Britain II — Wings of Victory
## Launcher and Configuration — Design Direction

Version 1.0. This document is the source of truth for colour, type, spacing, iconography and layout across `BOB2_Launcher.ps1` and `BOB2_Config.ps1`. Every value here is final and implementable: hex codes, pixel sizes, font family strings, icon names and literal UI copy. Nothing in it requires a package, a font install, or an internet connection.

**Platform reality this design is built inside:** WPF, loaded by `XamlReader` from single-quoted PowerShell here-strings. No MVVM, no converters, no custom types, no NuGet. Only fonts already present on a stock Windows 10/11. Icons only as XAML `Path` geometry.

---

## 0. What is actually wrong

Three problems, in order of how much they cost the user.

**1. The settings screen is not readable by its own audience.** Measured against WCAG 2.1 on the current palette:

| Foreground | On | Ratio | Used at | Verdict |
|---|---|---|---|---|
| `Dim #697280` | `Card #171C24` | **3.52:1** | 10.5–11.5px | **Fails** 4.5:1 |
| `Dim #697280` | `CardHi #1E242E` | **3.21:1** | 11.5px mono | **Fails** |
| `Danger #C9564A` | `Card #171C24` | **4.00:1** | 12–13.5px | **Fails** — not previously measured |
| `Muted #98A0AC` | `Card #171C24` | 6.48:1 | 12–12.5px | Passes, but far too small |
| `Text #E4DFD4` | `Card #171C24` | 12.87:1 | 13.5px | Passes, still too small |

And on the launcher:

| Foreground | On | Ratio | Used at | Verdict |
|---|---|---|---|---|
| `#C8102E` "WINGS OF VICTORY" | `#050608` | **3.45:1** | 13px SemiBold | **Fails** — 13px is not "large text" (needs ≥18.66px bold) |
| `#6B6660` photo credit | `#050608` | **3.57:1** | 10.5px | **Fails**, and it sits over a photograph |
| `#9A958C` nav subtitles | `#050608` | 6.81:1 | 11.5px | Passes, too small |

The body scale runs 10.5–13.5px. For a sixty-year-old on a 27" 4K panel that is not a style problem, it is a functional one.

**2. The settings screen has no shape.** Eleven pages of near-equal-weight rows. Nothing tells you that `OBJECT_DENSITY` is worth ten of the settings next to it, or which of your edits are still uncommitted, or whether the install underneath is even healthy.

**3. The launcher labels name the machinery, not the job.** "GRAPHICS WRAPPER" and "MEASURE FRAME RATE" describe implementation. A person who wants to fly a Hurricane does not have a mental slot for "wrapper".

Everything below serves those three, in that order.

---

## 1. Colour tokens

### 1.1 Governing idea

The palette is not invented. It is taken from two real sources already present in the product:

- **The instrument panel at night.** Sky-type P11 dial lighting in a 1940 fighter was a dim brass-yellow on near-black — that is where `Brass #C8973F` comes from, and why it stays the single accent. Everything not brass is a blue-grey cast, the colour a cockpit actually is under a red-dimmed lamp.
- **Roundel red.** `#C8102E` is the launcher's brand mark and stays exactly as it is.

There is no light theme. This app is used in a dark room before a night flight. A light theme would double the contrast work and serve nobody.

### 1.2 Core surfaces and text — 7 tokens

Replace the `Dim` token entirely. Keep the surface ramp — it was never the problem.

```
Ink        #0B0E12   nav rail, deepest chrome, window edge          (unchanged)
Panel      #12161C   window background                              (unchanged)
Card       #171C24   setting cards, group containers                (unchanged)
Rule       #232A34   decorative dividers only, no contrast duty     (was Line #242B36)
Edge       #626A77   borders of anything you can click or type in   NEW — 3.33:1 on Panel
Text       #E4DFD4   primary text                        12.87:1 on Card   (unchanged)
Secondary  #AEB6C2   help text, subtitles, section notes  8.34:1 on Card   (was Muted #98A0AC)
Tertiary   #949DAC   config keys, timestamps, captions    6.25:1 on Card   (was Dim #697280)
```

That is 8 lines but 7 *roles*: `Rule` and `Edge` are one role split by an accessibility rule that WPF cannot enforce for you. The split matters — WCAG requires **3:1** for the boundary of a control you can operate. `Rule #232A34` is 1.27:1 on Panel, which is correct for a hairline divider and **wrong** for a `TextBox` border. Today `Line #242B36` does both jobs. That is the second, quieter contrast bug in the app.

**Verified ratios, worst-case surface (`CardHi #1E242E`):**

| Token | on Card #171C24 | on CardHi #1E242E |
|---|---|---|
| `Text #E4DFD4` | 12.87:1 | 11.73:1 |
| `Secondary #AEB6C2` | 8.34:1 | 7.61:1 |
| `Tertiary #949DAC` | **6.25:1** (was 3.52) | **5.70:1** (was 3.21) |
| `Brass #C8973F` | 6.48:1 | 5.91:1 |

Every text token now clears 4.5:1 on every surface in the app, with the smallest type sitting at 6.25:1 rather than 3.52:1.

**Why `Tertiary` did not simply become lighter than `Secondary`.** The obvious fix — push `Dim` up until it passes — collapses the hierarchy, because at 7:1 it would out-shine `Muted`. The three tiers survive because they are now separated by **62 ΔL steps that are still legible**, and because tier three is additionally distinguished by *family* (monospace) and *containment* (a bordered chip), not by dimness alone. Dimness is a bad way to say "less important" when your reader is sixty.

### 1.3 Accent and state

```
Brass       #C8973F   the one accent. Active nav, section titles, primary button.   6.48:1
BrassSoft   #8A6B2E   accent borders and rules only. Never text.
BrassWash   #2A2114   fill behind an accent callout. Never text.
Danger      #E2685A   conflicts, destructive actions, failed checks.   5.18:1  (was #C9564A, 4.00:1)
Warn        #D9A441   "this will not stick", "needs attention".        7.60:1  (unchanged)
Good        #8FB56A   verified, healthy, applied.                      7.32:1  (was #7FA05F, 5.78:1)
Info        #7FA6CE   neutral note, "session only".                    6.72:1  (was #6E92B8, 5.26:1)
```

`Danger` moved for contrast. `Good` and `Info` moved a smaller amount so the four state colours read as one family at the new lightness — the old ones now looked muddy sitting next to a compliant `Danger`.

**One rule that keeps the accent meaning something:** brass is used for *the thing you are on* and *the thing to press*. It is never used for decoration, never for a border on a non-interactive box, never as a gradient. If brass appears twice on a card, one of them is wrong.

### 1.4 Launcher tokens

The launcher palette is nearly right and keeps its character. Two changes, both forced by measurement.

```
Night       #050608   window ground                                    (unchanged)
Bone        #F4F1EB   title and nav titles                             (unchanged)
Roundel     #C8102E   the red bar, the active mark, and display type
                      at 19px Bold or larger ONLY.                     3.45:1 — legal for
                                                                       UI marks (3:1) and
                                                                       large text (3:1)
RoundelLite #E8394F   red TEXT below 18.66px bold.                     4.95:1
NavSub      #9A958C   nav subtitles                                    6.81:1 (unchanged colour,
                                                                       size goes 11.5 → 13px)
Caption     #8E8880   photo credit and status bar                      5.77:1 (was #6B6660, 3.57:1)
Hairline    #33FFFFFF the divider under the title                      (unchanged)
```

`Roundel` and `RoundelLite` are one brand colour at two duties. "WINGS OF VICTORY" at 13px in `#C8102E` fails AA today; it either goes up to 19px Bold (where 3:1 applies and it passes) **or** it goes to `#E8394F`. **Take the first option** — set "WINGS OF VICTORY" at 19px Bold in `#C8102E`. It is the better typographic answer anyway, and it keeps the pure roundel red on the most visible word on the screen. `RoundelLite` then exists only for small red text elsewhere (error states in the status bar), where it is genuinely needed.

**The two reds are deliberately different colours.** Launcher `#C8102E` is a *brand mark*. Settings `#E2685A` is a *state*. If a red bar and a red error can be the same colour, the user learns nothing from red.

---

## 2. Typography

### 2.1 Three faces, three jobs

```
DISPLAY   Bahnschrift SemiCondensed, Bahnschrift, Franklin Gothic Medium Cond,
          Segoe UI Semibold, Segoe UI
          → All caps headings, nav labels, section titles, buttons, big numbers.

BODY      Segoe UI Variable Text, Segoe UI, Tahoma
          → Every sentence the user has to read. Setting labels, help text, wizard copy.

DATA      Cascadia Mono, Consolas, Courier New
          → Config key names, file paths, measured values, key bindings, versions.
```

**Bahnschrift SemiCondensed** stays as the display face because the launcher already earns its keep with it and because a condensed grotesque is the right register: it is the face of a stencilled aircraft serial, a squadron board, a fuel gauge. It ships on Windows 10 1709+ and all Windows 11.

> **Implementation warning — read this before typing a font string.** Bahnschrift is a variable font. Windows registers several GDI family names for it (`Bahnschrift Light SemiCondensed`, `Bahnschrift SemiBold SemiCondensed`, and so on) but **WPF's font resolution across these named instances is unreliable and differs between Win10 builds.** Do not chase weight by swapping family names. Set `FontFamily="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"` once, and vary weight with `FontWeight="Normal|SemiBold|Bold"`. This is the difference between working and silently falling back to Segoe UI on someone's machine.

**Segoe UI Variable Text** as the first body choice is the one genuinely new call here. It ships on Windows 11 only, it is optically tuned for the 12–18px band (larger apparent x-height, more open apertures than static Segoe UI), and it degrades to `Segoe UI` on Windows 10 with no layout shift because the metrics are compatible. For this audience that is free legibility on the majority platform.

**Faces deliberately rejected, with reasons:**
- **Corbel** and **Candara** — both default to *old-style (text) figures*. In a screen where the user compares `1024` to `2048` and reads `4300`, descending numerals that misalign in a column are a comprehension bug, not a style. Rejected on that alone.
- **Sitka Small** — genuinely the best-engineered small-text face on Windows, but a serif hairline on a `#171C24` ground thins out badly in ClearType and would undo the contrast work.
- **Cascadia Code** — has ligatures. Config keys are not code; `!=` should never become a glyph. Use Cascadia **Mono**.

> **Second implementation warning.** WPF `TextBlock` has **no letter-spacing / tracking property.** There is no supported way to track out the condensed caps without emitting per-character `Run`s. Do not design around tracking, do not add it to a spec, and do not fake it. The condensed family is doing that job already.

> **Third.** `BOB2_Config.ps1` currently sets `TextOptions.TextFormattingMode="Display"`. That was correct at 10.5–13.5px. At the new sizes it is not — `Display` snaps advance widths to whole pixels and coarsens the larger type. **Switch the settings window to `TextFormattingMode="Ideal"` with `TextRenderingMode="ClearType"`**, matching the launcher, which already does this.

### 2.2 Type scale — settings window

Base is **15px**. Nothing anywhere in the app is below **12px**. That is the single most important line in this document.

| Role | Family | Size | Weight | Line height | Colour |
|---|---|---|---|---|---|
| Window title bar | DISPLAY | 14 | SemiBold | — | `Secondary` |
| Page title (H1) | DISPLAY | 26 | Bold | 30 | `Text` |
| Page subtitle | BODY | 15 | Normal | 22 | `Secondary` |
| Rail group caption | DISPLAY | 12 | SemiBold, CAPS | — | `Tertiary` |
| Rail item | DISPLAY | 16 | Normal / SemiBold when active | — | `Secondary` / `Text` |
| Section title | DISPLAY | 17 | SemiBold | 21 | `Brass` |
| Section note | BODY | 14 | Normal | 21 | `Secondary` |
| Setting label | BODY | 15 | SemiBold | 20 | `Text` |
| Setting help | BODY | 13.5 | Normal | 20 | `Secondary` (8.34:1) |
| Config key chip | DATA | 12 | Normal | — | `Tertiary` (6.25:1) |
| Control value (combo, textbox) | BODY | 15 | Normal | — | `Text` |
| Priority mark | DISPLAY | 12 | Bold, CAPS | — | `Brass` / `Danger` |
| Button | DISPLAY | 15 | SemiBold | — | per style |
| Status bar | BODY | 13.5 | Normal | — | `Secondary` |
| Big readout (FPS, axis %) | DATA | 32 | Normal | 34 | `Text` |

Compared with today: help text 12 → 13.5, config keys 11.5 → 12, setting labels 13.5 → 15, page title 21 → 26. Roughly a 15% lift across the board, and the floor rises from 10.5 to 12.

### 2.3 Type scale — launcher

| Role | Family | Size | Weight | Colour | Was |
|---|---|---|---|---|---|
| "BATTLE OF BRITAIN II" | DISPLAY | 34 | Bold | `Bone` | 30 |
| "WINGS OF VICTORY" | DISPLAY | 19 | Bold | `Roundel` | 13 SemiBold — **failed AA** |
| Mod version line | DATA | 12 | Normal | `Caption` | 11 Bahnschrift |
| Nav title (PLAY) | DISPLAY | 21 | SemiBold | `Bone` | 19 |
| Nav title (others) | DISPLAY | 18 | SemiBold | `Bone` | 17 |
| Nav subtitle | BODY | 13 | Normal | `NavSub` | 11.5 |
| Status pill | BODY | 13 | Normal | `Caption` | 11.5 |
| Photo credit | BODY | 12 | Normal | `Caption` | 10.5 — **failed AA** |

The version line moves to `Cascadia Mono` — it is a version number, it belongs to the DATA role, and it introduces the third face on the launcher so the two screens read as one family.

### 2.4 The text-size control

WPF gives this away almost free and this audience needs it more than any feature in the app.

Wrap the settings window's root content in a `ScaleTransform` set from code:

```
$Win.Content.LayoutTransform = New-Object Windows.Media.ScaleTransform($s, $s)
$Win.Width  = 1360 * $s ; $Win.Height = 900 * $s
$Win.MinWidth = 1100 * $s ; $Win.MinHeight = 720 * $s
```

Three stops: **Normal (1.00) · Large (1.15) · Larger (1.30)**. Persist the choice.

The control lives in the **status bar, on every page** — labelled `Text size` with three `A` glyphs at 13/16/19px. Not on a settings page. A user who cannot read the app cannot navigate to a page to fix that; the escape hatch has to be where they already are.

Default window grows from 1240×840 to **1360×900**, min from 1020×660 to **1100×720**.

---

## 3. Spacing and form

**4px base unit.** Permitted steps: `4 · 8 · 12 · 16 · 24 · 32 · 48 · 64`. Nothing else.

| Element | Value |
|---|---|
| Nav rail width | 260 |
| Rail item height | 40 (was 34) |
| Rail item text inset | 56 left (icon at 20, gutter at 16, active bar at 3) |
| Rail group caption margin | 24 top, 8 bottom |
| Content padding | 32 left/right, 24 top |
| Prose max width | 880 |
| Card padding | 24 |
| Gap between cards | 16 |
| Gap between sections | 32 |
| Setting row min height | 56 |
| Setting row vertical padding | 14 / 14 |
| Setting row: label column | `*`, control column fixed 320 |
| Status bar height | 52 (was ~40) |
| Form 700 drawer width | 320 open, 48 collapsed |

**Corner radius:** `4` on controls (button, combo, textbox), `6` on cards, `0` on the active-nav bar and the priority mark. Nothing else is rounded. No shadow anywhere — a drop shadow on a `#171C24` card over a `#12161C` panel is invisible and costs render time.

**Stroke widths:** hairline dividers `1px` in `Rule`. Interactive borders `1px` in `Edge`. Active nav bar `3px` in `Brass`.

---

## 4. Icons

### 4.1 Library and licence

**Lucide** — <https://lucide.dev>. **ISC licence.** ISC is a permissive, OSI-approved licence functionally equivalent to MIT (copyright notice retained, no further conditions). Lucide is the maintained fork of Feather (MIT); either is safe, but Lucide has roughly 1,500 icons against Feather's 287, and it has `joystick`, `gauge` and `scaling` — which Feather does not, and which this app specifically needs.

Ship the ISC notice in `README.txt` alongside the IWM credit.

Take geometry from the `lucide-static` distribution: `lucide-static/icons/<name>.svg`. **Do not hand-author path data. Copy the `d` strings.**

### 4.2 Converting Lucide SVG to WPF

Lucide icons are **stroked, not filled**, on a 24×24 grid with a 2px round-capped stroke. Four rules:

1. **`Fill="{x:Null}"`, always.** A Lucide `d` string filled instead of stroked renders as a black blob.
2. **`Stroke`, `StrokeThickness`, `StrokeStartLineCap="Round"`, `StrokeEndLineCap="Round"`, `StrokeLineJoin="Round"`.**
3. **Many Lucide icons are multiple SVG elements.** `<circle>` and `<line>` have no `d` attribute and must be converted by hand:
   - `<line x1 y1 x2 y2>` → `M x1,y1 L x2,y2`
   - `<circle cx cy r>` → `M (cx-r),cy A r,r 0 1,0 (cx+r),cy A r,r 0 1,0 (cx-r),cy`
   - `<rect x y w h rx>` → build with `M / H / A / V / A / H / A / V / A / Z`, or prefer an icon without one.
   Combine the results into a single `Data` string separated by spaces — WPF's path mini-language accepts multiple figures in one `Data`, and one `Path` per icon is what you want inside a here-string.
4. **Sizing.** Render at native 24 with **no `Viewbox`** and `StrokeThickness="1.6"` wherever a 24px icon fits. Where a 20px icon is specified (settings rail), wrap in `<Viewbox Width="20" Height="20">` around a `<Canvas Width="24" Height="24">` and set `StrokeThickness="1.9"` — the Viewbox scales the stroke by 20/24, landing back at ~1.6 optical.

Set `UseLayoutRounding="True"` on the icon container. Lucide's 2px strokes sit centred on half-pixel lines at 24; at 1.6 they will be slightly soft at 100% DPI and crisp at 125%+ where this audience mostly lives. Accept it — the alternative is a pixel-hinted icon font, and there isn't one on stock Windows worth using.

### 4.3 Launcher icons — 24px, in the icon column

Icon colour follows the item state: `Caption #8E8880` at rest, `Bone #F4F1EB` on hover, `Roundel #C8102E` on the primary/active item.

| Nav item | Lucide icon | Why this one |
|---|---|---|
| PLAY | `play` | Single-path triangle. Universal. |
| GUIDED SETUP *(new)* | `compass` | Getting your bearings, and it is the only aviation-native glyph in the set. Deliberately not `wand-2` or `sparkles`. |
| SETTINGS | `sliders-horizontal` | Adjusting values, not administering a system. **Not** `settings` (the cog) — a cog says "machinery", which is exactly the register this app is trying to leave. |
| FRAME RATE TEST | `gauge` | A dial. The instrument-panel metaphor pays off once, here. |
| GRAPHICS TRANSLATOR | `layers` | The wrapper is literally a layer between game and driver. |
| IN-GAME MENU SIZE | `scaling` | Lucide's scale-a-thing glyph. **Not** `type` — this scales the whole menu, not just text. |
| JOYSTICK SETUP | `joystick` | Exists in Lucide; unambiguous. |
| INSTALL AND REPAIR | `wrench` | Plain. |

### 4.4 Settings rail icons — 20px

Icon colour: `Tertiary #949DAC` at rest, `Text #E4DFD4` on hover, `Brass #C8973F` when active.

Against the **real** nav (`$script:NavDefs`, `BOB2_Config.ps1:2915`):

| Page | Lucide icon | Why |
|---|---|---|
| Overview | `clipboard-check` | It is a servicing form. Literal, not metaphorical. |
| Performance | `gauge` | Same glyph as the launcher's frame-rate test. Deliberate — same subject, same mark. |
| Graphics | `monitor` | |
| View and camera | `eye` | |
| Weather and sky | `cloud-sun` | |
| Realism and AI | `crosshair` | Realism in a combat sim is about what the enemy can do to you. |
| Interface | `layout-dashboard` | |
| GFX screen | `file-cog` | Honest: it is settings decoded out of a binary save file. |
| Key bindings | `keyboard` | |
| Joystick and axes | `joystick` | Same glyph as the launcher. |
| All settings | `file-text` | It is `bdg.txt`. Say so. |
| About | `info` | |

Mapping for the page names used in the brief, should that naming be adopted instead:

| Brief name | Lucide icon |
|---|---|
| Graphics | `monitor` |
| View | `eye` |
| Gameplay | `gamepad-2` |
| Controls | `keyboard` |
| Joystick and axes | `joystick` |
| Weather | `cloud-sun` |
| Audio | `volume-2` |
| Difficulty | `crosshair` |
| Advanced | `terminal` |
| About | `info` |

**One glyph, one meaning, across both windows.** `gauge` is frame rate everywhere. `joystick` is the stick everywhere. `wrench` is repair everywhere. If the same idea needs two glyphs, the idea is wrong.

---

## 5. The signature element — the Form 700

**RAF Form 700 is the aircraft servicing record.** It is the document that travels with an airframe listing every defect found, every rectification made, and a signature saying the aircraft is fit to fly. No pilot in 1940 got airborne without one being signed. Every person who plays this game knows what it is.

That artifact is an exact structural match for what this app does and does not currently show: *here is what is wrong with your installation, here is what I changed, and here is you committing to it.* It answers problem 2 — the wall of settings with no shape — with a real object from the subject's own world rather than a generic "unsaved changes" bar.

It appears in three places, and nowhere else.

**A. The Overview page is the Form 700 top sheet.** Not a dashboard of stat tiles. A list, because a servicing record is a list.

```
┌─────────────────────────────────────────────────────────────────────┐
│  FORM 700 · SERVICING RECORD                                        │  Bahnschrift 12 CAPS, Tertiary
│                                                                     │
│  Ready to fly                                            ✓          │  Bahnschrift 26 Bold, Text
│  Four items need attention before this will run its best.           │  Segoe 15, Secondary
│                                                                     │
│  ── AIRFRAME ──────────────────────────────────────────────────     │  Rule 1px
│  ● Game                 Battle of Britain II 2.13, patched          │  Good dot
│  ● Multi-skin pack      Installed                                   │
│  ● Crash fix            Applied 5 Aug 2026                          │
│  ● Graphics translator  dgVoodoo2 2.86.5  ·  recommended            │
│                                                                     │
│  ── DEFECTS ───────────────────────────────────────────────────     │
│  ▲ Ground object density is 4                          [ Fix ]      │  Warn
│    Roughly halves your frame rate. 2 is recommended.                │
│  ▲ Frame smoothing is LIMITED                          [ Fix ]      │
│    Adds input lag on modern hardware.                               │
│  ▲ In-game menus are at 100%                           [ Fix ]      │
│    On a 3840-wide monitor they will be very small.                  │
│  ✕ No joystick detected                                [ Check ]    │  Danger
│                                                                     │
│  ── RECTIFICATIONS THIS SESSION ───────────────────────────────     │
│    (nothing yet)                                                    │
└─────────────────────────────────────────────────────────────────────┘
```

Three headings, in the order a fitter would work: what's fitted, what's wrong, what you did about it. Each defect carries the one-button fix — the user never has to go and find the setting.

**B. The Form 700 drawer.** A 320px panel on the right of every settings page, **collapsed to 48px by default**, showing a brass count badge when there are uncommitted changes. It lists every pending edit as `label · old → new`, each with an undo. It is the running rectification list; opening it at the end of a session and reading it back is the review step the app currently has no place for.

**C. The wizard's final screen** is a completed Form 700, and a copy is written to `BOB2_Setup_Log.txt`.

**What the Form 700 is *not*:** it is not a name the user has to know to operate the app. The heading in the panel is always plain English ("Ready to fly", "3 changes not yet saved"). "FORM 700 · SERVICING RECORD" is the eyebrow above it — flavour for those who recognise it, invisible to those who don't. The buttons stay literal: **"Save 3 changes"**, not "Sign off". A metaphor may name a place. It may never name a verb.

---

## 6. The Spitfire cutaway — how it is used

**Decision: show it whole, once, on the About page. Do not use it anywhere else on the settings screen. Do use its *method* on the Joystick page.**

### Why not as background, watermark or texture

Every instinct says take the 1940 "BRITAIN'S NEW SPITFIRE" cutaway, drop it behind the settings content at 8% opacity, and call the screen designed. Three reasons not to:

1. **It fights the only real problem on this screen.** Section 0 documents a measured contrast failure. Laying a full-colour illustration under text — at any opacity — reintroduces uncontrolled local contrast underneath the exact text I have just spent a palette fixing. It would be undoing the work in the same commit.
2. **It is the wrong register, and that is a fact about the artifact, not a taste.** The launcher's IWM photograph is monochrome, documentary, and about *people at war*. The cutaway is coloured, printed, promotional, and about *a machine's parts*. Putting the cutaway behind a settings form does not create continuity between the screens; it creates a second, competing world. Two artifacts, two screens, each used whole — that is continuity. A watermark is not.
3. **Watermarking degrades it.** This is a real 86-year-old printed artifact with a legible 37-item key. Cropped to 8% behind a combo box it becomes texture. Shown at size with its key intact, it is a thing worth looking at.

### Where it goes

**The About page, at full size, full colour, unclipped, with a caption and provenance** — treated exactly the way the launcher treats the IWM photograph. The About page is the only page in the app with no settings on it, so there is nothing for it to compete with. Give it the full content width, a `Rule` hairline above and below, and a caption in `Segoe UI 13.5 / Secondary`:

> *"Britain's New Spitfire" — a 1940 cutaway published for the British public, with a key to thirty-seven components. The aircraft in this simulation is modelled from records of the same period.*

This is also the honest place for it, because that is what the illustration *is*: a period explainer aimed at a non-technical public who wanted to understand a machine they cared about. Which is, precisely, this app's audience.

### Where its method goes — the Joystick page

The cutaway's real design idea is not "numbers on a picture". It is: **a machine has parts, the parts have names, and a key tells you which is which.** That idea is worth stealing, but only where the subject actually *is* a machine with parts.

Settings are not parts of a machine. Numbering `01 / 02 / 03` down a settings page would be decoration wearing the costume of information, and it is rejected.

**The Joystick and axes page, however, is literally about a physical object with named parts** — four axes, a twist, a slider, sixteen buttons — and the page already polls the device twenty times a second (`Start-JoyLive`, `BOB2_Config.ps1:3422`). So:

Draw a generic stick-and-throttle as flat XAML `Path` geometry in `Rule`/`Tertiary` — no shading, no photograph, a line diagram in the cutaway's own idiom. Number the callouts. **Light the callout in `Brass` when the user moves that axis or presses that button.** Beneath it, the key: number, part, what it currently controls, current value.

```
        ①                                                  KEY
        │      ┌──┐                              ─────────────────────────────────
        └──────┤  │        ┌────────┐            ① Stick, forward/back   Pitch    -12%
               │  │  ⑤─────┤▓▓▓▓░░░░│ ⑥          ② Stick, left/right     Roll     +03%
        ②──────┤  ├──③     └────────┘            ③ Twist                 Rudder    00%
               └┬─┘                              ④ Base slider           Throttle  74%
                │                                ⑤ Trigger               Fire
                ④                                ⑥ Throttle lever        —  unassigned
```

That is a diagram that does a job no paragraph can: it answers "which thing on my desk is the game calling *axis 3*". It is the one place in the app where a picture beats words, and it earns the cutaway's inheritance by being true rather than by being pretty.

---

## 7. Settings screen layout

### 7.1 Full screen, drawer collapsed (the normal state)

```
┌──────────────────────────────────────────────────────────────────────────────────────────┬──┐
│  BATTLE OF BRITAIN II · SETTINGS                                              –  □  ✕    │  │ 44
├──────────────────┬───────────────────────────────────────────────────────────────────────┤  │
│                  │                                                                       │  │
│ ▣ Overview       │  Performance                                                          │▌3│ ← collapsed
│                  │  The handful of settings that actually decide your frame rate, and    │  │   Form 700,
│ SETTINGS         │  the ones that only look as if they do.                               │  │   brass badge
│▌◔ Performance    │                                                                       │  │
│  ▭ Graphics      │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  ◉ View & camera │  │  ● IF YOU CHANGE ONLY ONE THING                                 │  │  │
│  ☁ Weather & sky │  │                                                                 │  │  │
│  ✛ Realism & AI  │  │  Ground object density                    [ 2 — Medium      ▾ ] │  │  │
│  ▦ Interface     │  │  Terrain texture size                     [ 1024            ▾ ] │  │  │
│  ⛁ GFX screen    │  │  Frame smoothing                          [ NONE            ▾ ] │  │  │
│                  │  │  Auto-generated scenery                   [ ●———     Off      ] │  │  │
│ CONTROLS         │  │                                                                 │  │  │
│  ⌨ Key bindings  │  │  These four cost more than everything else in this list added   │  │  │
│  ⟟ Joystick      │  │  together.        [ Set all four to the recommended value ]     │  │  │
│                  │  └─────────────────────────────────────────────────────────────────┘  │  │
│ EVERYTHING       │                                                                       │  │
│  ▤ All settings  │  SCENE DENSITY                                                        │  │
│  ⓘ About         │  Ground detail is where this engine spends its time. If the frame     │  │
│                  │  rate is poor, start here and nowhere else.                           │  │
│                  │                                                                       │  │
│                  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│                  │  │  Ground object density                              ● MATTERS   │  │  │
│                  │  │  How much is drawn on the ground. Setting 4 roughly halves the  │  │  │
│                  │  │  frame rate compared with 2, for detail you will never look at. │  │  │
│                  │  │  ┌──────────────────┐                    ┌───────────────────┐  │  │  │
│                  │  │  │ OBJECT_DENSITY   │                    │ 2 — Medium      ▾ │  │  │  │
│                  │  │  └──────────────────┘                    └───────────────────┘  │  │  │
│                  │  └─────────────────────────────────────────────────────────────────┘  │  │
│                  │                                                                       │  │
│                  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│                  │  │  Particle density                                               │  │  │
│                  │  │  Smoke, fire, dust and debris. The cost lands during heavy      │  │  │
│                  │  │  combat, which is when you can least afford it.                 │  │  │
│                  │  │  ┌──────────────────┐                    ┌───────────────────┐  │  │  │
│                  │  │  │ PARTICLE_DENSITY │                    │ 2 — Medium      ▾ │  │  │  │
│                  │  │  └──────────────────┘                    └───────────────────┘  │  │  │
│                  │  └─────────────────────────────────────────────────────────────────┘  │  │
│                  │                                                                       │  │
│                  │  ⌄ Show 7 more advanced settings in this section                      │  │
│                  │                                                                       │  │
├──────────────────┴───────────────────────────────────────────────────────────────────────┴──┤
│  bdg.txt   D:\Games\BOB2\BDG.txt        Text size  A A A     [ Discard ]  [ Save 3 changes ]│ 52
└─────────────────────────────────────────────────────────────────────────────────────────────┘
   260                                    *                                              320/48
```

### 7.2 Drawer open

```
│  ┌──────────────────────────────────────────┐ │ ┌─────────────────────────────┐ │
│  │  Ground object density        ● MATTERS  │ │ │ FORM 700                  ✕ │ │
│  │  ...                                     │ │ │                             │ │
│  │  ┌──────────────┐   ┌─────────────────┐  │ │ │ 3 changes not yet saved     │ │  Bahnschrift 17
│  │  │OBJECT_DENSITY│   │ 2 — Medium    ▾ │  │ │ │                             │ │
│  │  └──────────────┘   └─────────────────┘  │ │ │ PERFORMANCE                 │ │  Eyebrow 12 CAPS
│  └──────────────────────────────────────────┘ │ │ ─────────────────────────── │ │
│                                               │ │ Ground object density       │ │  Body 15
│  ┌──────────────────────────────────────────┐ │ │ 4  →  2                  ↺  │ │  Data 15, arrow Brass
│  │  Particle density                        │ │ │                             │ │
│  │  ...                                     │ │ │ Frame smoothing             │ │
│  └──────────────────────────────────────────┘ │ │ LIMITED  →  NONE         ↺  │ │
│                                               │ │                             │ │
│                                               │ │ GRAPHICS                    │ │
│                                               │ │ ─────────────────────────── │ │
│                                               │ │ Water detail                │ │
│                                               │ │ 3  →  2                  ↺  │ │
│                                               │ │                             │ │
│                                               │ │ All three go into            │ │  13.5 Secondary
│                                               │ │ BDG.txt. A backup is         │ │
│                                               │ │ written first.               │ │
│                                               │ │                             │ │
│                                               │ │ [   Save 3 changes        ] │ │  BtnPrimary, full width
│                                               │ │ [   Discard all           ] │ │  BtnGhost
│                                               │ └─────────────────────────────┘ │
```

Drawer opens by clicking the collapsed strip or the "Save N changes" count in the status bar. 120ms slide. That is the only animation in the settings window.

### 7.3 Setting row anatomy

```
┌───────────────────────────────────────────────────────────────────────────┐
│ ↑24                                                                       │
│    Ground object density                                    ● MATTERS     │  label: Segoe 15 SemiBold / Text
│  ↑8                                                          ↑ Bahnschrift 12 Bold CAPS, Brass
│    How much is drawn on the ground. Setting 4 roughly halves the frame     │  help: Segoe 13.5 / Secondary
│    rate compared with 2, for detail you will almost never look at.         │  8.34:1, LH 20, max width 640
│  ↑12                                                                      │
│    ┌────────────────────┐                    ┌──────────────────────────┐  │
│    │  OBJECT_DENSITY    │                    │  2 — Medium            ▾ │  │  key chip: Cascadia 12 / Tertiary
│    └────────────────────┘                    └──────────────────────────┘  │  6.25:1, bg Field, border Rule
│      ← the "key"                               ← control, 320 fixed         │  control: Segoe 15 / Text,
│ ↓24                                                                       │  border Edge 3.33:1, h 36
└───────────────────────────────────────────────────────────────────────────┘
```

**The config-key chip is the one structural device taken from the cutaway's key**, and it is honest: this is the name the user will see in every forum post and every README about this game. It is what actually changes in `BDG.txt`. Showing it is not nostalgia, it is traceability — and it makes the app's smallest text a monospaced ASCII string, which is the easiest kind of small text to read.

### 7.4 How the wall of settings gets a shape

Three mechanisms, all driven by data the config already carries (`-Level perf`, `-Rec`, `-RecMsg`):

1. **`● MATTERS`** — a brass mark on the small number of settings that measurably change frame rate or break the game. Roughly eight settings across the app carry it. It is not a rating system; it is a binary, and it is rare enough to be believed.
2. **"IF YOU CHANGE ONLY ONE THING"** — a card at the top of the Performance page with the four highest-cost controls inlined. These are *the same bound controls* as their home pages, not copies; changing either updates both and produces one entry in the Form 700. Plus one button that sets all four at once.
3. **Advanced disclosure per section** — everything with no recommendation and no measurable effect collapses behind `⌄ Show 7 more advanced settings in this section`, closed by default. The settings do not go away; they stop shouting at the same volume as the ones that matter.

Together these turn eleven pages of flat rows into: *this is what's wrong (Overview) → this is what matters (Performance top card) → this is what you changed (Form 700)*.

---

## 8. Launcher — refinements

Keep: the full-bleed IWM photograph bleeding off the right, the left scrim, the condensed caps, the red bar, the vertical text list, the status bar, the restraint. The photograph and the type treatment are the identity and they are not up for negotiation.

Change four things.

**1. Icons, at 24px, in a 40px column left of the label block.** Vertically centred **on the title line, not the whole block** — an icon centred on a two-line item drifts down and breaks the vertical rhythm of the list. Colour `#8E8880` at rest, `#F4F1EB` on hover, `#C8102E` on the primary item. The icon column sits *inside* the existing `-22` negative margin so the red bar remains the leftmost element.

**2. Type sizes up** per §2.3, and the photo credit fixed to 12px `#8E8880`.

**3. GUIDED SETUP as an eighth item**, placed **above PLAY** when it has never been run, and **directly below PLAY** afterwards. When never run it takes the primary treatment (red bar, 21px) and PLAY drops to secondary — because a user who has not run setup pressing PLAY is the failure case this whole app exists to prevent.

**4. Relabelling** — §9.

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                                                              –  ✕              │
│                                                                                │
│   BATTLE OF BRITAIN II                        [ IWM HU 54418 — 'B' Flight,     │  34 Bold Bone
│   WINGS OF VICTORY                              No. 32 Squadron RAF,           │  19 Bold Roundel (was 13 — failed AA)
│   BOB2 WIN11 FIX  v1.4.2                        Hawkinge, 29 July 1940 ]       │  12 Cascadia Caption
│   ────────────────────────────────                                             │
│                                                                                │
│  ▌ ▶   PLAY                                                                    │  21 SemiBold
│        Start the game with the performance fixes applied                       │  13 NavSub
│                                                                                │
│    ⊕   GUIDED SETUP                                                            │  18 SemiBold
│        Five questions and it configures everything for your PC                 │
│                                                                                │
│    ⚌   SETTINGS                                                                │
│        Graphics, view, controls and difficulty — all in one place              │
│                                                                                │
│    ◔   FRAME RATE TEST                                                         │
│        Fly for 60 seconds and get a report on how smooth it was                │
│                                                                                │
│    ▤   GRAPHICS TRANSLATOR                                                     │
│        Lets this 2005 game talk to a modern card · dgVoodoo2 2.86.5            │
│                                                                                │
│    ⤢   IN-GAME MENU SIZE                                                       │
│        The game's own briefing screens · currently 125%                        │
│                                                                                │
│    ⟟   JOYSTICK SETUP                                                          │
│        Thrustmaster T.16000M · 4 axes, 16 buttons                              │
│                                                                                │
│    ⚒   INSTALL AND REPAIR                                                      │
│        Apply the patches, check every file, put anything broken back           │
│                                                                                │
│                                                                                │
│   ● Not running  ·  Game 2.13  ·  Fix 1.4.2  ·  dgVoodoo2 2.86.5               │  13 Caption
│   IWM HU 54418 — 'B' Flight, No. 32 Squadron RAF, Hawkinge, 29 July 1940.       │  12 Caption (was 10.5 — failed AA)
│   Public domain.        [ about this photograph ]                              │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Plain-English labels

The rule applied throughout: **name the job, not the mechanism; and never lie about what the thing does.** Where the current label is already plain, it stays — relabelling something that works is churn.

| Current | Proposed | Subtitle (live state in *italic*) |
|---|---|---|
| PLAY | **PLAY** *(keep)* | Start the game with the performance fixes applied |
| — | **GUIDED SETUP** *(new)* | Five questions and it configures everything for your PC |
| SETTINGS | **SETTINGS** *(keep)* | Graphics, view, controls and difficulty — all in one place |
| MEASURE FRAME RATE | **FRAME RATE TEST** | Fly for 60 seconds and get a report on how smooth it was |
| GRAPHICS WRAPPER | **GRAPHICS TRANSLATOR** | Lets this 2005 game talk to a modern card · *dgVoodoo2 2.86.5* |
| MENU SIZE | **IN-GAME MENU SIZE** | The game's own briefing screens · *currently 125%* |
| JOYSTICK AXES | **JOYSTICK SETUP** | *Thrustmaster T.16000M · 4 axes, 16 buttons* |
| SETUP AND REPAIR | **INSTALL AND REPAIR** | Apply the patches, check every file, put anything broken back |

**Notes on the three that needed real thought.**

*"GRAPHICS TRANSLATOR"* over "GRAPHICS COMPATIBILITY". Both are honest. "Compatibility" is a category noun that tells you nothing new; "translator" tells you what the thing actually does in four syllables — it stands between two parties that can't talk to each other and passes messages. A non-technical person can hold that. Naming the specific wrapper in the subtitle keeps it truthful for the expert.

*"IN-GAME MENU SIZE"* over "MENU SIZE". "Menu size" is already plain English — the jargon complaint doesn't apply to it. What it *is* is ambiguous: this launcher has menus too. One word removes the ambiguity. Resisted "BIGGER MENUS" because the control also goes down.

*"FRAME RATE TEST"* over "MEASURE FRAME RATE" and over "CHECK PERFORMANCE". "Frame rate" is not jargon to a flight simmer — it is the single number this community talks about most. Replacing it with "performance" would be dumbing down, which the brief rightly forbids. What was wrong was the verb: "measure" sounds like an instrument, "test" sounds like something you do.

*Subtitle "launch pinned to the P-cores" → "Start the game with the performance fixes applied".* P-core affinity is real and important and belongs in a tooltip and in `README.txt`. It does not belong on the biggest button on the screen, where its job is to reassure, not to inform.

---

## 10. First-run wizard — "First Flight"

**Entry:** `GUIDED SETUP` on the launcher. Auto-offered once, on first launch after install, with a dismissible line: *"It looks like this is a fresh install. Want me to walk you through setting it up? It takes about three minutes."*

**Window:** 900 × 680, centred, same tokens as the settings screen.

**The four rules this wizard is built on:**

1. **Every step has a correct answer already chosen.** Pressing "Next" six times produces a good result. The wizard is a *review*, not an interrogation.
2. **No step is a dead end.** Every step has a secondary that leaves things exactly as they are.
3. **Nothing is irreversible and every step says so.** Backups before writes, stated in the copy.
4. **It is re-runnable and it knows it.** On re-run it says "Currently: X" on every step and the welcome screen offers a jump list.

**Progress:** `Step 3 of 6` plus six dots, top right. Numbering appears **here and nowhere else in the app**, because this is the only part of the product that is genuinely a sequence.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  FIRST FLIGHT                                        Step 3 of 6         │  eyebrow / progress
│  ● ● ◉ ○ ○ ○                                                             │  dots, active = Brass
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   How should the game talk to your graphics card?                        │  Bahnschrift 26 Bold
│                                                                          │
│   This game asks for a graphics feature that Windows removed years        │  Segoe 15 / Secondary
│   ago. A small translator sits in between and answers for it. Without     │  LH 23, max width 620
│   one, the game will not start at all.                                    │
│                                                                          │
│   ◉  dgVoodoo2                                        Recommended        │  15 SemiBold + Brass tag
│      Works on every graphics card we have tested. Use this one.          │  13.5 Secondary
│                                                                          │
│   ○  Windows' own Direct3D                                               │
│      No translator at all. In theory the fastest, but this game          │
│      fails to start on most modern cards without one.                    │
│                                                                          │
│   ○  DXVK                                                                │
│      Known to crash this game the moment you enter the cockpit.          │
│      Here for completeness.                                              │
│                                                                          │
│   Currently: dgVoodoo2 2.86.5                                            │  13.5 Tertiary (re-run only)
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│   You can change this later from GRAPHICS TRANSLATOR.   [ Back ] [ Next ]│
└──────────────────────────────────────────────────────────────────────────┘
```

### Welcome

> ### First flight
>
> This will get Battle of Britain II running properly on this PC. Six questions, about three minutes.
>
> I will make a backup of every file before I change it, and nothing here is permanent — you can run this again at any time to change your answers.
>
> `[ Start ]` `[ Not now ]`

*On re-run the title becomes* **Setup** *and the body becomes:*

> Run through all six steps again, or jump straight to the one you want to change.
>
> `[ Run all six steps ]` · Or go to: Find the game · Install the fix · Graphics · Menu size · Joystick · Frame rate

### Step 1 — Find the game

> ### Where is Battle of Britain II installed?
>
> **Found it.**
> `D:\Games\Battle of Britain II`
> Version 2.13, patched. This looks right.
>
> `[ Use this folder ]` `[ Choose a different folder ]`

*Not found:*

> I could not find Battle of Britain II on this PC. Point me at the folder that contains `BoB.exe` and I will take it from there.
>
> `[ Browse for the folder ]`

*Wrong folder chosen:*

> That folder does not contain `BoB.exe`. The game is usually somewhere like `C:\Program Files (x86)\Shockwave\Battle of Britain II` or wherever you installed it from GOG.

### Step 2 — Install the fix

> ### Get the game running on Windows 11
>
> Battle of Britain II was written for Windows XP. Four things have to change before it will run properly on a modern PC. Every file I touch gets backed up first.
>
> ☑ **Game patch 2.13** — the community's final patch. Fixes a long list of bugs the original shipped with.
> ☑ **Multi-skin pack** — lets the game load more than one aircraft skin per squadron.
> ☑ **Startup crash fix** — stops the crash that happens on the way into a mission.
> ☑ **Windows 11 compatibility flags** — tells Windows to stop applying two behaviours this game predates.
>
> `[ Install all four ]` `[ Skip — I have done this already ]`

*Already installed:*

> All four are already in place, applied 5 August 2026. Nothing to do here.
>
> `[ Next ]` · `[ Reinstall them anyway ]`

*After running:*

> Done. Four of four applied. A record went into `BOB2_Setup_Log.txt`.

### Step 3 — Graphics translator

Copy as shown in the wireframe above.

*If the user picks DXVK:*

> Are you sure? DXVK crashes this game when you enter 3D. If it does, come back here and choose dgVoodoo2.
>
> `[ Use DXVK anyway ]` `[ Go back to dgVoodoo2 ]`

### Step 4 — Menu size

> ### How big should the game's own menus be?
>
> The briefing screens and options screens inside the game were drawn for a monitor 1024 pixels wide. Your monitor is 3840 pixels wide, so they come out very small. I can enlarge them.
>
> ○ **102%** — Barely changed. For monitors 1280 wide or less.
> ○ **110%** — A small increase. For 1366 wide and up.
> ◉ **125%** — Comfortable. For 1600 wide and up. **Recommended for your monitor**
> ○ **140%** — Largest. For 1920 wide and up. Needs 1608 pixels across — anything narrower will clip.
>
> This changes the game's menus only. It does not change anything you see while flying.
>
> `[ Back ]` `[ Next ]`

*A live preview strip under the options, showing one real menu row at the chosen scale, updating as they click.*

### Step 5 — Joystick

> ### Let's check your joystick
>
> **Found: Thrustmaster T.16000M** — 4 axes, 16 buttons.
>
> Move the stick around and press a couple of buttons, so I can be sure Windows is seeing it.
>
> ```
> Pitch     ▓▓▓▓▓▓▓░░░░░░░░   -12%
> Roll      ░░░░░░░▓▓▓▓░░░░   +34%
> Rudder    ░░░░░░░▓░░░░░░░    00%
> Throttle  ▓▓▓▓▓▓▓▓▓▓▓░░░░    74%
> Buttons   ①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯
> ```
>
> Pitch, roll, rudder and throttle are all on sensible axes.
>
> `[ Looks right ]` `[ Something is on the wrong axis ]`

*Nothing detected:*

> I cannot see a joystick attached to this PC.
>
> You can fly with the keyboard and mouse — the game supports it and the key bindings are already set up. If you have a stick, plug it in and press the button below, or come back and run this again later.
>
> `[ Look again ]` `[ Carry on without one ]`

*"Something is on the wrong axis":*

> Move the control you want to use for **pitch**, and hold it at the extreme for a moment.
>
> *(repeat for roll, rudder, throttle)*

### Step 6 — Frame rate starting point

> ### A sensible starting point for frame rate
>
> Four settings in this game cost more than everything else in it added together. Setting them sensibly roughly triples the frame rate on most PCs, and costs you detail you would have to go looking for to notice.
>
> | | Now | Proposed |
> |---|---|---|
> | Ground object density | 4 | **2** |
> | Terrain texture size | 2048 | **1024** |
> | Frame smoothing | LIMITED | **NONE** |
> | Auto-generated scenery | On | **Off** |
>
> Every one of these is reversible from SETTINGS, and your original `BDG.txt` is backed up before I touch it.
>
> `[ Apply these four ]` `[ Leave my settings alone ]`

### Done

> ### You're ready to fly.
>
> **FORM 700 · SERVICING RECORD**
>
> ✓ Game found — `D:\Games\Battle of Britain II`, version 2.13
> ✓ Patch 2.13, multi-skin pack, crash fix and Windows 11 flags — all applied
> ✓ Graphics translator — dgVoodoo2 2.86.5
> ✓ In-game menus — 125%
> ✓ Joystick — Thrustmaster T.16000M, four axes confirmed
> ✓ Frame rate settings — four changed
>
> A copy of this is in `BOB2_Setup_Log.txt`, next to the game.
>
> Once you have flown, use **FRAME RATE TEST** on the main screen to see what you are actually getting.
>
> `[ Fly now ]` `[ Back to the main screen ]`
>
> *Run GUIDED SETUP again any time to change any of this.*

**Copy discipline used throughout:** first person for the tool's actions ("I will make a backup"), second person for the user's ("Move the stick"). Sentence case. Active verbs. Buttons name the outcome, and the outcome is reported back in the same words — `Install all four` → `Four of four applied`. No apologies, no exclamation marks, no "Oops". Every warning states the consequence and the remedy in the same breath.

---

## 11. Motion

Almost none, deliberately.

| Where | What | Duration |
|---|---|---|
| Form 700 drawer | Slide + fade | 120ms, `CubicEase EaseOut` |
| Nav active bar | Fill colour only, no slide | 90ms |
| Wizard step change | Cross-fade content, dots step instantly | 100ms |
| Joystick axis bars | No animation — must track the stick 1:1 | — |

Nothing else moves. No hover lift, no card scale, no page transition, no shimmer, no pulsing badge. Two reasons: WPF `Storyboard`s authored inside a PowerShell here-string are expensive to get right and cheap to get subtly wrong, and this audience is here to configure a program, not to watch it. Restraint in motion is what lets the one animated element — the drawer carrying your uncommitted changes — actually mean something.

If `SystemParameters.ClientAreaAnimation` is `False`, skip all four.

---

## 12. Quality floor

- **Keyboard.** Every control reachable by Tab in reading order. Visible focus: a 2px `Brass` outline at 2px offset, never removed. The settings rail is arrow-navigable (it is a `RadioButton` group, so this is already true — do not break it).
- **The nav rail is not the only route.** Every defect on the Overview page has a `[ Fix ]` button that navigates and scrolls to the setting. Every setting is findable by the existing search.
- **Never trap.** Closing with unsaved changes opens the Form 700 with `Save 3 changes` focused, not a modal "Are you sure?" with two identical grey buttons.
- **Every destructive action states what it backs up, before it happens, in the button's own vicinity.**
- **Nothing below 12px. Nothing below 4.5:1.** These are hard limits, not targets.
- **1100×720 must work.** At the 1.30 text scale the window is 1768×936 — that fits 1920×1080. Above that, the drawer collapses first, then the rail collapses to icons-only at 64px.

---

## 13. Self-critique — what was rejected and why

**Rejected: the warm cream / high-contrast serif / terracotta look.** The most common default in AI-generated design right now. Wrong for a product used in a dark room and wrong for a subject whose own materials are black-and-white photographs and dim instrument lighting.

**Rejected: near-black with a single acid accent.** This app already sits one bad decision away from it. The guard is provenance: `#C8973F` is dial-lighting brass, `#C8102E` is roundel red, and neither is allowed to become neon. Where I moved a state colour for contrast (`Danger`, `Good`, `Info`), I moved it the minimum distance that passes and no further.

**Rejected: the Spitfire cutaway as a background wash.** The obvious move, and the one I spent longest talking myself out of. It would have reintroduced uncontrolled contrast under the exact text the palette work exists to fix, and it would have reduced a real artifact to wallpaper. §6 is the argument in full. This is the risk I took: the settings screen has *no* illustration on it at all, and lives entirely on typography, spacing and one accent. A minimal direction has to be precise or it is just empty — that is why §3 exists at the level of detail it does.

**Rejected: `01 / 02 / 03` numbered markers on settings sections.** The cutaway's numbers are the most attractive thing about it and the most tempting to steal. But settings are not a sequence and not parts of a machine, so numbering them would be decoration wearing information's clothes. Numbering survives in exactly one place — the wizard — because the wizard genuinely is a sequence. The callout *method* survives in exactly one place — the joystick diagram — because a joystick genuinely is a machine with named parts.

**Rejected: a stat-tile dashboard for the Overview.** Four cards with big numbers and a gradient accent is the template answer, and it would have been wrong here: the user does not need aggregates, they need a list of specific things that are wrong with specific fixes. A servicing record is a list because the job is a list.

**Rejected: the cog for SETTINGS.** `settings` in every icon set is a gear. This app's entire thesis is that the user should not have to think about machinery, and a gear is a picture of machinery. `sliders-horizontal` says "adjust", which is what they came to do.

**Rejected: Corbel and Candara as body faces**, despite both being more characterful than Segoe UI and both being on every Windows install. Old-style figures. A settings screen is a numbers screen. Character is not worth a misaligned `1024`.

**Rejected: a light theme.** Doubles the contrast work, serves a use case (bright office) that does not exist for a night-flying sim launcher.

**Rejected: naming the save button "Sign off".** The Form 700 metaphor was earning its keep right up until it tried to rename a verb. A metaphor may name a place — a panel, a page, a section. The moment it names an action, the user has to translate before they can press it. The panel is FORM 700; the button says `Save 3 changes`. This is the accessory I took off before leaving the house.

**Rejected: hover-lift, card scale, page transitions, and a pulsing unsaved badge.** Four separate things I wrote into an earlier draft of §11 and cut. The drawer slide survives because it is the only animation that carries meaning — it shows you where your changes went.

**Kept deliberately, against the instinct to redesign:** the surface ramp (`#0B0E12 / #12161C / #171C24 / #1E242E`), the brass accent, the launcher photograph, the launcher's left-scrim composition, the settings nav rail structure, and the word `SETTINGS`. The measured problems were text contrast, text size, and information hierarchy. None of those are fixed by changing things that work, and every gratuitous change costs implementation time that should go into §2.4 and §7.4.

---

## 14. Implementation order

1. **Palette and type tokens** (§1, §2). One pass over both here-strings. Fixes three measured AA failures. Highest value per line changed.
2. **Text-size control** (§2.4). Roughly 20 lines. Second-highest value per line for this audience.
3. **Launcher relabelling and type sizes** (§8, §9). No new mechanics.
4. **Icons** (§4). Mechanical once the first one is converted.
5. **Priority marks and the "if you change only one thing" card** (§7.4). Drives off data the config already carries.
6. **Form 700 — Overview page and drawer** (§5). The signature. Needs `Get-ChangedBdg` surfaced as a list.
7. **First Flight wizard** (§10). Largest single piece; wraps existing `BOB2_Setup.ps1` steps rather than reimplementing them.
8. **Joystick callout diagram** (§6). Last, because it is the only item that is genuinely optional.
