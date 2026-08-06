========================================================================
  Battle of Britain II - Windows 10/11 Compatibility Fix
  Fix package v1.5.0  (2026-08-05)
  Works with both v2.12 and v2.13 (Win10 Patch) executables
========================================================================

  This version number refers to THIS FIX, not the game. The game shows
  its own version (e.g. v2.13) on the main menu. To see which fix
  version is installed in your game folder, open the file
  BOB2-Win11-Fix.version there, or run the setup tool and choose
  "Check Installation Status".


QUICK START
-----------
  You only need TWO downloads. The v2.13 patch replaces the whole
  older patch chain - see "Why only one patch?" below.

  1. Download these and place them in THIS folder (BOB2-Win11-Fix):
       - BDG v2.13.exe    (or BDG v2.13.7z - the community patch)
       - dgVoodoo2 zip    (from http://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/)

     DO NOT unzip or run them manually. The setup tool runs everything
     in the correct order and points the installer at your game folder.

  2. >>> Double-click BOB2_Setup.bat and select "Full Install" <<<

  That's it. The setup tool handles the rest: patching, dgVoodoo2,
  the crash fix, configuration, and a desktop shortcut.

  3. From then on, start the game from the "Battle of Britain II"
     shortcut on your desktop (or BOB2.bat in this folder). That is the
     launcher, and it is the only file you need to run - see below.


THE LAUNCHER - AND WHY THE ORDER MATTERS
----------------------------------------
BOB2.bat opens a small window with six things on it:

  PLAY                 launches the game pinned to your CPU's fast cores
  SETTINGS             graphics, view, gameplay, key bindings and joystick
  MEASURE FRAME RATE   60-second PresentMon capture while you fly
  GRAPHICS WRAPPER     dgVoodoo2 or native Direct3D 9
  MENU SIZE            how large the in-game menus are drawn
  SETUP AND REPAIR     the setup tool you used to install

It is not just a menu over the .bat files. It exists because the order
you do things in matters, and nothing used to tell you that.

  >>> Bob.exe REWRITES bdg.txt and settings.cfg when it exits. <<<

So if you change settings while the game is running, the game overwrites
them on quit and your changes are gone with no error and no warning.
bdg.txt even documents a case of this against itself:

    ENABLE_AUTO_TEXTURE_RES=ON  # Change to 'OFF' will affect one session
                                # only, IOW BoB will write 'ON' back over it.

The launcher checks every two seconds whether Bob.exe is running and
disables whatever is unsafe right now, with a line under each button
saying why:

  game running       Settings, Play, Graphics Wrapper and Setup are
                     greyed out.
  game not running   Everything is available.

Measure Frame Rate is always available, because the capture is armed
before or during play and then triggered by a hotkey from inside the
cockpit - see "Measuring frame rate without Alt-Tab" below.

So the normal session is: open the launcher, change anything you want
under Settings, press Play. You never touch the in-game options screens,
which clip off the right-hand edge of the window on modern displays.

The bar along the bottom shows what is actually installed: game version,
fix version (amber if your install is older than this package), and which
d3d9.dll is really in place with its version number - in red if it is not
dgVoodoo2.

The old .bat files still work on their own if you prefer them. The
launcher just calls them.


MENU SIZE
---------
The menus are 154 Windows dialogs laid out at a fixed size against an 8pt
font, so on a large screen they end up small and marooned in the middle.
MENU SIZE in the launcher rescales every one of them, and the font with
them. Four sizes:

    1.02x  font 8pt    needs 1171 px across   1280 wide or less
    1.10x  font 9pt    needs 1264 px across   1366 and up
    1.25x  font 10pt   needs 1437 px across   1600 and up
    1.40x  font 11pt   needs 1608 px across   1920 and up  [default]

Pick the largest that does not clip off the right of your screen, and
"Original size" to undo. Bob.exe is patched in place and the untouched
original is kept beside it as Bob.exe.unscaled.

  >>> IF THE MENUS DO NOT LOOK ANY BIGGER, CHECK THIS FIRST. <<<

A compatibility flag called HIGHDPIAWARE tells Windows the program
handles DPI itself and must not be scaled. BOB2 is from 2005 and does no
such thing, so with that flag set its menus are drawn at true pixel size -
on a 2560-wide display at 150% scaling that is about a third smaller than
intended, and it cancels this rescale exactly. The dialogs really are
bigger; Windows has simply stopped magnifying them.

It is easy to acquire by accident, because Properties > Compatibility >
"Change high DPI settings" > "Override high DPI scaling behaviour" sets
precisely this flag. The Win11 tweaks step removes it.

Re-applying BDG v2.13, or anything else that replaces Bob.exe, wipes the
rescale. Run MENU SIZE again afterwards.


JOYSTICK AND HOTAS
------------------
Settings > CONTROLS has two pages. Key bindings covers buttons and keys.
Joystick and axes covers everything else, and includes a live test: move
the stick and the bars move, press a button and it lights up. The button
numbers there are the same numbers the Key bindings page uses.

WHY THE GAME'S OWN CONTROLS SCREEN IS NO HELP
  Axis assignment lives in DeviceDefaults.txt, a plain-text file keyed by
  DirectInput device GUID. The shipped copy dates from 2005 and lists a
  Saitek X36, a Saitek X45, a Logitech WingMan and a Thrustmaster Top Gun.
  Any stick made since is simply unknown to the game.

  "Set up my stick" detects what is actually plugged in, works out the
  DirectInput GUID from its VID and PID, writes a correct entry, and
  applies a button preset. It adapts to what is present: a twist-grip
  stick on its own keeps throttle on its slider, but plug a separate
  throttle in and re-run and throttle moves to the real lever with rudder
  on the rocker.

  It is a first-time setup. Once your stick works there is no reason to
  press it again.

DEADZONE - AND WHY RUDDER IS SET SEPARATELY
  The game ships 7.5% everywhere. That is a 2005 default sized for
  potentiometer sticks that wandered at rest; a Hall-effect stick does not
  drift and does not need it, and that dead patch sits exactly where
  gunnery happens.

  Rudder is different. A twist grip shares a limb with roll: pushing the
  stick sideways rotates your wrist a little whether you mean it to or
  not, so a twist axis picks up unintended yaw on every roll input. Give
  it the same 1% as pitch and roll and the aeroplane hunts and jerks
  through every turn. 5% absorbs it. Real rudder pedals do not have this
  problem and can be as tight as the others.

      Fighters   pitch/roll 1%   rudder 5%   Spitfire, Hurricane, Bf109
      Heavy      pitch/roll 3%   rudder 6%   Bf110, Ju88, He111
      Pedals     pitch/roll 1%   rudder 1%
      Stock      7.5% everywhere

  The two sliders on that page set any value you like, with the deadzone
  drawn as a red band on the live bars so you can size it against what
  your stick actually does.

CURVES - THE GAME HAS NONE
  BOB2's entire input path is a deadzone followed by a multiply and an
  offset. There is no exponent and no curve table anywhere on a joystick
  axis. (The Curve class inside the game is flight-model data - engine and
  aerodynamic curves - and nothing to do with your stick.)

  Curves therefore have to be applied before the game sees the axis, by
  Thrustmaster TARGET or by Joystick Gremlin with vJoy. Both present a
  virtual stick that BOB2 then reads as linear. A ready-made TARGET script
  for the T.16000M, with separate curves for the Spitfire, the Bf109 and
  the heavies, is in the TARGET folder.

  If you enable one of those, two things follow: the virtual stick is a
  DIFFERENT device with a different GUID, so run "Set up my stick" again;
  and set the in-game deadzone to 0 so the two do not stack.

IF YOU PLAY WITHOUT THE STICK PLUGGED IN
  The game will say "Could not load joystick-settings, attempting default
  mapping". That is normal and means what it says. It then rewrites its
  input file with the stick removed, so your mapping is lost when you next
  plug in. Save it first from the Joystick page, or with
      BOB2_Sensitivity.ps1 save -Name mystick
  and load it back the same way.


THE PHOTOGRAPH ON THE LAUNCHER
------------------------------
IWM HU 54418. Pilots of 'B' Flight, No. 32 Squadron RAF relax on the
grass at Hawkinge in front of Hawker Hurricane Mk I P3522, coded GZ-V,
on 29 July 1940. The squadron was based at Biggin Hill and flew daily
from Hawkinge as a forward airfield during the opening weeks of the
Battle of Britain.

From left to right: Pilot Officer R F Smythe; Pilot Officer K R Gillman;
Pilot Officer J E Proctor; Flight Lieutenant P M Brothers; Pilot Officer
D H Grice; Pilot Officer P M Gardner; Pilot Officer A F Eckford.

All seven survived the war except Keith Gillman, who was posted missing
on 25 August 1940, aged 19.

Ministry of Information Second World War Press Agency Print Collection,
Imperial War Museums. Public domain: a United Kingdom Government work
published before 1 June 1957, so Crown copyright has expired.

  https://commons.wikimedia.org/wiki/File:The_Battle_of_Britain_HU54418.jpg
  https://www.iwm.org.uk/collections/item/object/205059622
  https://en.wikipedia.org/wiki/Battle_of_Britain

The same credit is in the launcher itself under "about this photograph".


WHY ONLY ONE PATCH?
-------------------
BDG's own v2.13 installation notes state:

    "This update will bring *any* previous version up to 2.13.
     You do not need any previous patches at all."

MultiSkin (the historically accurate squadron markings) is included
in v2.13 as well. So you do NOT need bob2_update_v2.12.EXE or
multiskin_v212.EXE - installing them first is simply wasted time and
about 500 MB of downloads.

If you already have those files, the setup tool will still use them
(choose "Individual Steps"), but it is not the recommended route.

  Base game (any version, 2.00 onwards)
        |
        v
  BDG v2.13.exe          <- the only patch you need
        |
        v
  BOB2-Win11-Fix         <- this package

TWO THINGS TO DO BEFORE PATCHING
--------------------------------
Both come from BDG's own release notes and are easy to miss:

  * OLD CAMPAIGNS DO NOT SURVIVE THE UPGRADE. If you are partway
    through a campaign, finish it first. After patching, everything in
    the SAVEGAME folder must be deleted EXCEPT these three files:
        DIR.DIR      inputcfg.dat      settings.cfg

  * WINDOWS TEXT SCALING. BDG's notes say to use 100% (96 DPI), because
    the game predates display scaling. Be aware of the trade-off on a
    high-resolution monitor, which we measured on a 2560x1600 display:
      - At 100%, the options screens render correctly but appear TINY,
        marooned in the middle of the screen.
      - At 150%, they are a usable size but the tab bar is clipped on
        the right.
    Neither is ideal. The options screens are native Windows dialogs
    drawn at a fixed pixel size, so they do not scale with your monitor
    resolution the way the 3D view does. 125% may be the best
    compromise. This affects the menus only, never the flying.


PREREQUISITES
-------------
You need Battle of Britain II: Wings of Victory installed.

The game is available for purchase from A2A Simulations:
  https://a2asimulations.com/product-category/standalone/

The base game installs as version 2.06; the v2.13 patch takes it
straight to current from there.

You also need the DirectX 9.0c End-User Runtime (June 2010). The game
links against d3dx9_35.dll, which Windows does not ship - newer
DirectX versions do NOT include it. Without it you will get a missing
DLL error. Download from Microsoft:
  https://www.microsoft.com/en-us/download/details.aspx?id=8109

Both v2.12 and v2.13 run with this fix, but v2.13 is recommended - it
fixes widescreen menu rendering that is visibly broken in v2.12.


WHAT THE SETUP TOOL DOES
-------------------------
The setup tool (BOB2_Setup.bat) has six options:

  1. Full Install (recommended)
     - Detects your game folder
     - Checks your current game version
     - Applies BDG v2.13 (the only patch needed - includes MultiSkin)
     - Installs dgVoodoo2 DirectX wrapper (REQUIRED - see below)
     - Applies the Windows 10/11 crash fix
     - Applies Win11 tweaks (compatibility mode, gauges, exit key remap)
     - Configures GPU assignment (for laptops with dual graphics)
     - Puts a "Battle of Britain II" launcher shortcut on your desktop
     - Validates the installation

     The older v2.12 and MultiSkin steps are still available under
     "Individual Steps" for anyone who needs them, but Full Install
     no longer requires those downloads.

  2. Check Installation Status
     - Shows current game version and component status

  3. Individual Steps
     - Run any single step on its own (patches, dgVoodoo2,
       crash fix, Win11 tweaks, validation, launcher shortcut)

  4. Settings Tweaker
     - Adjust dgVoodoo2 settings (FPS limit, resolution, scaling,
       VSync, filtering, antialiasing)
     - Adjust game settings (object density, particle density,
       UI refresh rate, vision range, FOV, frame smoothing)
     - Quick presets: Performance (density 1, max FPS),
       Balanced (density 2 - recommended), Quality (density 4,
       best visuals but roughly half the frame rate)

  5. Uninstall Modifications
     - Cleanly removes all modifications and restores backups

  6. Exit


WHAT'S INCLUDED IN THIS PACKAGE
--------------------------------
  BOB2_Setup.bat        - >>> DOUBLE-CLICK THIS FIRST, TO INSTALL <<<
  BOB2_Setup.ps1        - Setup tool (launched by the .bat file)
  BOB2.bat              - >>> DOUBLE-CLICK THIS AFTERWARDS, TO PLAY <<<
                          The launcher. Full Install also puts a "Battle
                          of Britain II" shortcut to it on your desktop.
  BOB2_Launcher.ps1     - The launcher itself (launched by BOB2.bat)
  assets\hu54418.jpg    - Launcher background. IWM HU 54418, public
                          domain - see "The photograph on the launcher"
  dinput8.dll           - Crash guard DLL (installed by the setup tool)
  README.txt            - This file
  CHANGELOG.txt         - What changed in each fix version

  The launcher calls the tools below. They still work on their own, but
  the launcher is what stops you running them in an order that loses
  your settings.

  BOB2_Launch.bat       - Recommended way to start the game. Pins it to
                          your CPU's performance cores. BOB2's engine is
                          effectively single-threaded, and on Intel hybrid
                          CPUs (12th gen and later) Windows may otherwise
                          schedule it onto a slow efficiency core.
  BOB2_Launch_1core.bat - Same, but pinned to a single core. Gives a higher
                          average frame rate but noticeably more stutter -
                          measured, and NOT recommended. Kept for testing.
  BOB2_MeasureFPS.bat   - Records 60 seconds of real frame data to a CSV
                          using Intel PresentMon, so you can compare
                          settings objectively instead of guessing.
                          YOU NEVER ALT-TAB - see below.
  BOB2_Config.bat       - Configurator. Use this INSTEAD of the game's own
                          options screens, which clip off the right-hand
                          side of the screen on modern displays. Ten pages
                          covering bdg.txt (350 assignments), all 236 key
                          bindings with search and rebinding, the GFX
                          screen settings from settings.cfg, and weather.
                          Backs up before saving.


MEASURING FRAME RATE WITHOUT ALT-TAB
------------------------------------
This game runs in exclusive fullscreen through dgVoodoo2. When it loses
focus it loses its Direct3D device, and it does not survive the reset -
it crashes to desktop. So Alt-Tab is not an option, and any instruction
telling you to Alt-Tab out to start a capture is wrong.

Instead the capture is ARMED from the launcher and TRIGGERED FROM INSIDE
THE COCKPIT. There are two ways:

  HOTKEY (recommended)
    Arm it, then play. When you are flying and the scene looks
    representative, press ALT+SHIFT+F11. Scroll Lock lights up while it
    records 60 seconds and goes out when it finishes, so you get
    confirmation without looking away from the game.

    Windows delivers a registered hotkey before the application sees it,
    which is why this works through exclusive fullscreen - and also why
    the combination matters. F11 alone is IMPACTTOG, SHIFT+F11 is
    FOV_LARGE and CTRL+F11 is WINAMP_STOP in this install, so any of
    those would have silently stolen a game function. ALT+SHIFT+F11 is
    unbound.

  AUTOMATIC
    Arm it with a countdown (120 seconds by default). Get airborne
    before it expires and it records 60 seconds on its own, no keypress
    needed. Use this if the hotkey is awkward on your keyboard.

Either way the CSV lands next to the tools, timestamped and labelled, so
runs never overwrite each other.
  BOB2_MenuScale.bat    - Menu size, on its own rather than from the
                          launcher. Four scales plus Original.
  BOB2_MenuScale_Restore.bat
                        - Puts the original Bob.exe back in one step.
  BOB2_Controls.ps1     - Detects your stick and writes the axis mapping
                          and button preset. Reports only unless given
                          -Apply. Backs up to _ControlsBackup\<timestamp>\.
  BOB2_Sensitivity.ps1  - Deadzone presets and named profiles. Decodes
                          SAVEGAME\inputcfg.dat directly.
  TARGET\               - Response curves for Thrustmaster TARGET, since
                          the game itself has none.
  menuscale\            - The menu rescale patches. Each carries the value
                          every edit expects to find, so it cannot be
                          applied to the wrong build or twice over itself.
  BOB2_SetWrapper.bat   - Switches the graphics wrapper:
                             dgvoodoo  - the working setup (use this)
                             native    - no wrapper; CRASHES, see below
                             dxvk      - D3D9-to-Vulkan; CRASHES, see below


AFTER INSTALLATION: SCREEN RESOLUTION
--------------------------------------
The setup tool installs dgVoodoo2 with Resolution set to "max",
which uses your desktop resolution. If you want a different in-game
resolution:

  OPTION A - Edit dgVoodoo.conf in your game folder:
    Find the [DirectX] section and change:
      Resolution = max
    To a specific resolution, e.g.:
      Resolution = 1920x1080

  OPTION B - Use the dgVoodoo2 GUI:
    Run dgVoodooCpl.exe in your game folder, go to the DirectX tab,
    and select your preferred resolution from the dropdown.

You can also adjust in-game display settings from the BOB2 options
menu. If the game looks stretched or has wrong proportions, try
changing ScalingMode in dgVoodoo.conf:
  ScalingMode = stretched      (fills the screen, may stretch)
  ScalingMode = stretched_ar   (fills the screen, keeps aspect ratio)
  ScalingMode = centered       (native resolution, black borders)


CONFIGURE WINDOWS GPU ASSIGNMENT (LAPTOPS)
------------------------------------------
If you have a laptop with both integrated and dedicated graphics
(e.g. Intel + NVIDIA), Windows may route BOB2 through the weak
integrated GPU by default.

  a) Open Windows Settings > System > Display > Graphics
  b) Click "Browse" and navigate to your Bob.exe
  c) Click "Options" and select "High performance"
  d) Click Save


LAUNCH AND TEST
---------------
  a) Launch Bob.exe (or use your normal shortcut)
  b) The intro video will be skipped (this is normal - it's the fix)
  c) Start an Instant Action mission to verify everything works
  d) Check your game folder for bob2guard.log - it confirms the
     crash guard DLL is active

Your game folder should now contain these key files:
  Bob.exe            - Game executable (2.12 or 2.13)
  bdg.txt            - Game configuration
  dgVoodoo.conf      - dgVoodoo2 configuration
  dgVoodooCpl.exe    - dgVoodoo2 settings GUI
  DDraw.dll          - dgVoodoo2 wrapper
  D3DImm.dll         - dgVoodoo2 wrapper
  D3D8.dll           - dgVoodoo2 wrapper
  D3D9.dll           - dgVoodoo2 wrapper
  dinput8.dll        - Crash guard DLL (from this fix)


PROBLEM EXPLAINED
-----------------
There are two separate problems, and both are fixed.

1. THE VIDEO CRASH
The 30 videos in the Avi\ folder are encoded with Indeo Video 5, a
codec Microsoft removed from Windows years ago. With no decoder
present, DirectShow fails while building its filter graph and the
game crashes to desktop. Disabling video playback in bdg.txt avoids
it entirely. (Older versions of this README blamed a null-pointer bug
in mpg2splt.ax - that was wrong; the real cause is the missing codec.)

2. THE DISPLAY-MODE CRASH - why dgVoodoo2 is REQUIRED
BOB2 is a Direct3D 9 game (Bob.exe imports d3d9.dll and d3dx9_35.dll;
it has no DirectDraw or D3D7 imports at all). On modern high-resolution
displays its display-mode selection fails: it asks for a fullscreen
buffer of 0 x 0 pixels with an unknown pixel format, which is invalid.
The graphics device is then never created, and the game crashes reading
a null pointer. The engine reports this itself as:

    D3DERR_INVALIDCALL in .\RenderD3D9.cpp at line 1702

This happens with Windows' own Direct3D 9 AND with DXVK - both were
tested and both crash identically. dgVoodoo2 is the only wrapper that
works, because it presents the legacy display-mode list this 2005 engine
expects. It is not optional and it is not just a compatibility layer -
without it the game does not start.

So the fix works by:
  1. Disabling video playback in bdg.txt (prevents the codec crash)
  2. Installing dgVoodoo2 (fixes display-mode selection - REQUIRED)
  3. Installing a crash guard DLL that catches breakpoint and SxS
     exceptions, and the null dereference behind the "More GFX" tab


PERFORMANCE TIPS
----------------
BOB2 is a 2000-era game but can still be demanding due to its large
campaign battles. The setup tool applies these recommended settings
automatically, but you can tweak them further:

BOB2 is CPU-bound: on a modern machine the CPU spends far longer per
frame than the GPU, and ground-object count is the dominant CPU cost.
So DENSITY settings - not resolution or antialiasing - decide your frame
rate. Resolution is close to free; run it at your monitor's native res.

In bdg.txt:
  OBJECT_DENSITY = 2              (1-4; 4 roughly halves frame rate)
  PARTICLE_DENSITY = 2            (1-4; smoke/fire effects)
  ENABLE_AUTO_GEN = OFF           (generated scenery - costs frame rate)
  ADD_SHEEP_COWS_AND_HAYSTACKS = OFF
  SMOOTHEN_FRAMERATE_MODE=NONE    (let dgVoodoo2 handle frame pacing)
  UI_REFRESH = 120.000000         (match your target FPS)
  PERIPHERAL_VISION_RANGE = 6000  (better situational awareness)

In dgVoodoo.conf (defaults are already optimized):
  FPSLimit = 60                   (stable frame pacing)
  Filtering = appdriven           (let the game control filtering)
  Antialiasing = appdriven        (let the game control AA)

NOTE: Forcing Antialiasing to 2x/4x/8x in dgVoodoo.conf can break
the game's options menu display. Leave it as "appdriven" for best
compatibility.


UNINSTALL
---------
Run BOB2_Setup.bat and select option 5 (Uninstall Modifications).

Or manually:
  1. Delete dinput8.dll from your game folder
  2. Restore bdg.txt from the backup (bdg.txt.backup)
     Or change the three settings back:
       SKIP_VIDEOS=OFF
       SKIP_QUICKVIDEOS=OFF
       INTRO_VIDEO=ON
  3. To remove dgVoodoo2, delete: DDraw.dll, D3DImm.dll, D3D8.dll,
     D3D9.dll, dgVoodoo.conf, dgVoodooCpl.exe from the game folder


TROUBLESHOOTING
---------------
Q: Game crashes immediately on launch
A: Make sure you copied the x86 (32-bit) dgVoodoo2 DLLs, not x64.
   Also check that SKIP_VIDEOS=ON in bdg.txt.

Q: Game still crashes after applying the fix
A: Check that bdg.txt actually has SKIP_VIDEOS=ON (the game may
   overwrite it on exit). Also check that you don't have a file
   called Bob.exe.local in your game folder - delete it if present.

Q: No intro video plays
A: Correct - that's the fix. The intro video triggers the Windows
   bug. You can still play the game normally.

Q: Screen is black but I can hear sound
A: dgVoodoo2 may not be configured correctly. Try running
   dgVoodooCpl.exe and setting Output API to Direct3D 11 Feature
   Level 11.0, or check that the correct DLLs are in the game folder.

Q: Game resolution is wrong or image looks stretched
A: Run dgVoodooCpl.exe in your game folder to change the resolution.
   Or edit dgVoodoo.conf and set Resolution to your preferred value
   (e.g. 1920x1080). See "AFTER INSTALLATION: SCREEN RESOLUTION"
   section above.

Q: dgVoodoo2 watermark appears in the corner
A: Run dgVoodooCpl.exe, go to the DirectX tab, and uncheck
   "dgVoodoo Watermark". Or set dgVoodooWatermark = false in
   dgVoodoo.conf under [DirectX].

Q: Poor frame rate on a powerful PC
A: Make sure Windows is using your dedicated GPU, not integrated
   graphics (see GPU Assignment section above). Also try reducing
   Antialiasing from 4x/8x to 2x in dgVoodoo.conf.

Q: bob2guard.log appears in my game folder
A: This is a diagnostic log from the crash guard DLL. It shows
   how many exceptions were intercepted. You can safely delete it.

Q: I want to verify the DLL is working
A: After running the game, check bob2guard.log. It should show
   "Crash guard ACTIVE" and "Unloading (skipped N breakpoints)".

Q: Is dinput8.dll safe?
A: Yes. It's a transparent proxy that forwards all DirectInput8
   calls to the real Windows dinput8.dll. It only adds a Vectored
   Exception Handler that catches INT 3 breakpoint instructions.
   Source code is available (dinput8_guard.c).

Q: The options menu tabs are cut off on the right side
A: This is cosmetic - the menu bar was designed for 4:3 monitors.
   The "Continue" tab is partially hidden on widescreen but still
   clickable. All settings are fully accessible.

Q: Clicking "More GFX" in the options menu crashes the game
A: This is a genuine bug in RCombo.ocx, a control the game uses for
   that screen - it dereferences a null pointer. Fix versions up to
   1.2.0 tried to patch around it at runtime and made things WORSE
   (see CHANGELOG for the detail). From 1.2.1 the crash guard only
   logs it and lets the game's own error handling take over.

   If "More GFX" still crashes for you, avoid it: every setting on
   that screen can be changed directly in bdg.txt, which is fully
   documented in the manual in your Docs\ folder.

Q: Can I use the 2.12 exe instead of 2.13?
A: Yes. Both work. The 2.12 exe may have slightly better ground
   object rendering (less pop-in). The 2.13 exe has improved
   renderer code. Either way, apply this fix to prevent the
   video crash.


TECHNICAL DETAILS
-----------------
VIDEO CRASH
The files in Avi\ are Indeo Video 5 (FourCC "IV50") AVIs. Microsoft
removed the Indeo codecs from Windows on security grounds, so no
decoder is present on Windows 10/11. DirectShow fails while building
the filter graph - the failure surfaces inside mpg2splt.ax as it
probes candidate filters, which is why that DLL was long blamed, but
the underlying cause is the absent codec. Disabling video in bdg.txt
avoids the graph being built at all. Installing a modern decoder such
as LAV/ffdshow would be an alternative way to restore the videos.

DISPLAY-MODE CRASH
Entering 3D, the game requests a fullscreen swap chain of
Width=0, Height=0, Format=Unknown - invalid parameters in Direct3D 9.
The device is therefore never created, the renderer's device pointer
stays NULL, and Renderer::SetGamma dereferences it:

    EXCEPTION_ACCESS_VIOLATION in Bob.exe at 0023:00528E94
    Read from location 00000000

Confirmed from three independent directions: DXVK's own log showing
the 0 x 0 request, the faulting address above, and the engine's assert
"D3DERR_INVALIDCALL in .\RenderD3D9.cpp at line 1702".

Windows' native Direct3D 9 and DXVK both fail this way. dgVoodoo2
succeeds because DefaultEnumeratedResolutions = all and
EnumeratedResolutionBitdepths = all give the game the legacy display
modes it expects to choose from.

PERFORMANCE
BOB2's simulation runs on a Windows multimedia timer, independent of
the render loop, so a high frame rate does NOT speed the game up.
The engine is CPU-bound: on modern hardware the CPU takes several
times longer per frame than the GPU. That means ground-object density
governs your frame rate, while resolution and antialiasing are close
to free.

CRASH GUARD
dinput8.dll is a transparent proxy that forwards all DirectInput8
calls to the real Windows DLL. It adds a Vectored Exception Handler
that skips EXCEPTION_BREAKPOINT (0x80000003), SxS activation-context
errors, and the null dereference inside RCombo.ocx behind the
"More GFX" options tab. It writes its version into bob2guard.log on
every run, so you can always tell which build is deployed.


CREDITS
-------
Fix developed March 2026; substantially revised August 2026.
Tested on Windows 11 with dgVoodoo2 v2.86.5, on an i9-13900HX /
RTX 4080 at 2560x1600.

418 Squadron RCAF - "Piyautailili" (We who are hunters)

========================================================================
  DISCLAIMER
========================================================================

  WHAT YOU NEED

    1. A licensed copy of Battle of Britain II: Wings of Victory.
       Available from A2A Simulations:  https://a2asimulations.com/store/

    2. Patch 2.13, if the game is not already at it.
       This mod does NOT include the patches. It applies the ones you
       supply. Put the installers in this folder and they are found
       automatically:
         bob2_update_v2.12.EXE       patch 2.12
         multiskin_v212.EXE          MultiSkin pack
         BDG*v2.13*.exe or .7z       patch 2.13
           Patch 2.13 is hosted by A2A:
           https://www.a2asimulations.com/bob/downloads/BDG%20v2.13.7z
       If the game already reports 2.13, none of these are needed.

    The wizard checks both for you on its first screen and says which, if
    any, are missing.

  SUPPORTED WINDOWS
    Windows 11 - every version.
    Windows 10 - version 1809 (build 17763) and later.

    Do not install this on Windows 8.1 or earlier. The graphics translator
    needs Direct3D 11 and the compatibility flags this mod removes do not
    exist on those versions.

    The mod checks for you. Install and repair shows the version it found
    on the first row, and refuses to install if it is not supported.

    A warning if you check by hand: the registry lies. On Windows 11 25H2
    the value at
      HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProductName
    still reads "Windows 10" - Microsoft never updated it. Use CurrentBuild
    instead: 22000 or higher is Windows 11.

  This is an UNOFFICIAL COMMUNITY MOD.

  NOT TO BE CONFUSED WITH THE COMMUNITY "BOB2 WINDOWS 10 PATCH".
  That is a separate project, built on the 2.01 executable, which replaces
  textures, sounds and aircraft models and - by its own author's account -
  does not include patch 2.13's AI improvements, ground objects or
  MultiSkin. This mod is for patch 2.13, keeps all of it, and replaces no
  game content whatsoever.

  It is not affiliated with, endorsed by, sponsored by or connected to
  A2A Simulations, Shockwave Productions, Rowan Software, or any current
  or former rights holder in Battle of Britain II: Wings of Victory.
  All trademarks and copyrights belong to their respective owners.

  USE AT YOUR OWN RISK. This software is provided as is, without warranty
  of any kind, express or implied. The authors accept no liability for any
  damage, data loss or lost progress arising from its use.

  It modifies files inside your Battle of Britain II installation,
  including the game executable, configuration files and control bindings.
  Every file it changes is backed up first, and every change can be undone
  from the launcher. Even so, a full copy of the game folder before you
  start is the only backup nobody regrets.

  This mod contains no game content. It patches a copy of the game that
  you already own. It is distributed free of charge and must never be sold.

  CREDITS
    Battle of Britain II: Wings of Victory
      Rowan Software / Shockwave Productions
    Patch 2.13
      the BOB2 Development Group (BDG)
    dgVoodoo2
      Dege - http://dege.freeweb.hu
    Icons
      Lucide v1.28.0, ISC licence - https://lucide.dev
    Photograph
      IWM HU 54418, public domain

