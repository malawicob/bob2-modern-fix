#requires -version 5.1
# =============================================================================
#  BATTLE OF BRITAIN II - CONFIGURATION
#  Part of the BOB2 Windows 10/11 fix v1.5.0.  Single file, no dependencies.
# =============================================================================
#  The game's own options screens render at a fixed ~1024px width and clip on
#  modern displays, and several settings are not exposed in them at all.  This
#  edits the underlying files directly.
#
#  FILES EDITED
#    bdg.txt                 350 assignments (318 without the DITHER_LOOK_UP
#                            array), Windows-1252, CRLF.  139 carry an inline
#                            comment, which is the best documentation there is.
#    KEYBOARD\keys.txt       236 actions (190 bound, 46 unbound on this install)
#    KEYBOARD\default.txt    269 actions - read-only, used for "reset"
#    SAVEGAME\settings.cfg   1786-byte binary, four known offsets
#    Weather\Weather.cfg     3 plain-text lines
#
#  RULES OBSERVED WHEN WRITING
#    * Only the VALUE on a matched line is replaced.  Leading indentation, the
#      spacing around '=', trailing spacing, inline comments, line order, blank
#      lines, the Windows-1252 encoding and the CRLF endings all survive intact.
#    * Text is rebuilt by concatenating captured groups, never by regex
#      substitution, so a '$' in a value cannot corrupt the line.
#    * Unknown bytes in settings.cfg are never touched.
#    * Joystick / POV codes on a keys.txt line are preserved verbatim when the
#      keyboard part of that binding is changed.
#    * Every file that is about to change is copied into a timestamped backup
#      folder first.  Nothing at all is written until Save is pressed.
#
#  IMPLEMENTATION NOTES
#    * WPF via XAML.  The XAML is a literal single-quoted here-string, declares
#      no custom types and no custom converters, so it needs no Add-Type and
#      cannot fail on assembly resolution.  Rows are built in code rather than
#      data-bound, which avoids the PowerShell/WPF binding-notification traps.
#    * The source is deliberately pure ASCII.  PowerShell 5.1 decodes a BOM-less
#      .ps1 as the system ANSI codepage, so a stray non-ASCII character would
#      render differently on a machine with another codepage.  Anything that
#      wants to look typographic is drawn as a shape instead of a glyph.
#    * $PSScriptRoot is captured at top level; it is not valid inside functions.
#    * Loop variables are never captured by event handlers - per-control state
#      always travels on the control's .Tag.
#
#  NOT TESTED (no way to verify from here)
#    * Gamma levels 0, 1 and 3 in settings.cfg.  Only 2 (Medium) and 4 (Maximum)
#      were confirmed by differential analysis; the 0-4 scale is inferred.
#    * Item Shading value 1.  Only 0 (Off) and 2 (Reflections) were confirmed.
#    * Whether the game accepts a keys.txt line for an action that was
#      previously unbound.  It is written in exactly the shipped format, but
#      that path has not been exercised in game.
#    * Numeric-keypad Enter cannot be told apart from main Enter by WPF, so the
#      key capture records both as Enter (DIK 28), not 156.
# =============================================================================

param(
    # Render the window to a PNG and exit, for checking layout without
    # clicking through. param() must be the FIRST executable statement in a
    # PowerShell file - only comments may precede it.
    [string]$RenderTo,
    [double]$RenderScale = 1.0,
    # Open straight onto a page, so the launcher can link into Joystick and
    # axes without the user hunting for it.
    [string]$Page
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# Hide our own console window (never when rendering).
#
# This used to assume the .bat launched us detached so no console was ever
# visible.  That was wrong twice over: the launcher starts this with
# Start-Process powershell.exe -File, which always creates one, and when
# Windows Terminal is the default terminal application it ignores
# -WindowStyle Hidden entirely.  Either way a black console sat behind the
# window for the whole session.  BOB2_Config.vbs now starts us hidden; this
# is the fallback for anyone running the .ps1 directly.
if (-not $RenderTo) {
  try {
    Add-Type -Namespace BOB2C -Name Win -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
    $h = [BOB2C.Win]::GetConsoleWindow()
    if ($h -ne [IntPtr]::Zero) { [void][BOB2C.Win]::ShowWindow($h, 0) }   # SW_HIDE
  } catch { }
}

# Any error that escapes has to be shown in a dialog or it disappears
# silently - there is no console left to print to.
trap {
    # PositionMessage alone reports the OUTERMOST statement, which for
    # anything raised inside a WPF event handler is always the final
    # ShowDialog() line - true, and useless. ScriptStackTrace names the
    # function and line the error actually came from.
    $msg = $_.Exception.Message
    $where = ''
    try { $where = $_.ScriptStackTrace } catch { }
    if (-not $where) { $where = $_.InvocationInfo.PositionMessage }
    $full = "$msg`n`n$where"
    try { Set-Content -Path (Join-Path $script:ScriptDir 'BOB2_Config_error.log') -Value $full -Encoding UTF8 } catch { }
    [void][System.Windows.MessageBox]::Show(
        $full,
        'Battle of Britain II - Configuration',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error)
    break
}

# $PSScriptRoot / $PSCommandPath are only valid at top level.
$script:ScriptDir = $PSScriptRoot
if (-not $script:ScriptDir -and $PSCommandPath) { $script:ScriptDir = Split-Path -Parent $PSCommandPath }
if (-not $script:ScriptDir) { $script:ScriptDir = (Get-Location).Path }

$script:Enc1252 = [System.Text.Encoding]::GetEncoding(1252)

# -----------------------------------------------------------------------------
#  DirectInput scancodes.  keys.txt stores DIK_* codes, not virtual keys.
#  Spot-checked against the shipped file:
#    GEARUPDOWN 34 = G      GOTOMAPKEY 50 = M     SHOOT 57 = Space
#    DROPBOMB 48 = B        LEFTWHEELBRAKE 51 = , RIGHTWHEELBRAKE 52 = .
#    SCREENSHOT 183 29+25 = PrtScn and Ctrl+P     AILTRIMUP 29+201 = Ctrl+PgUp
#    LOOKUPNW 29+71 = Ctrl+Numpad7 (up and to the left - consistent)
#  Anything >= 256 is a joystick button or POV code, not a keyboard code.
# -----------------------------------------------------------------------------
$script:DikName = @{
    1='Escape'; 2='1'; 3='2'; 4='3'; 5='4'; 6='5'; 7='6'; 8='7'; 9='8'; 10='9'; 11='0'
    12='Minus'; 13='Equals'; 14='Backspace'; 15='Tab'
    16='Q'; 17='W'; 18='E'; 19='R'; 20='T'; 21='Y'; 22='U'; 23='I'; 24='O'; 25='P'
    26='Left Bracket'; 27='Right Bracket'; 28='Enter'; 29='Left Ctrl'
    30='A'; 31='S'; 32='D'; 33='F'; 34='G'; 35='H'; 36='J'; 37='K'; 38='L'
    39='Semicolon'; 40='Apostrophe'; 41='Grave'; 42='Left Shift'; 43='Backslash'
    44='Z'; 45='X'; 46='C'; 47='V'; 48='B'; 49='N'; 50='M'
    51='Comma'; 52='Period'; 53='Slash'; 54='Right Shift'; 55='Numpad *'
    56='Left Alt'; 57='Space'; 58='Caps Lock'
    59='F1'; 60='F2'; 61='F3'; 62='F4'; 63='F5'; 64='F6'; 65='F7'; 66='F8'; 67='F9'; 68='F10'
    69='Num Lock'; 70='Scroll Lock'
    71='Numpad 7'; 72='Numpad 8'; 73='Numpad 9'; 74='Numpad -'
    75='Numpad 4'; 76='Numpad 5'; 77='Numpad 6'; 78='Numpad +'
    79='Numpad 1'; 80='Numpad 2'; 81='Numpad 3'; 82='Numpad 0'; 83='Numpad .'
    87='F11'; 88='F12'
    156='Numpad Enter'; 157='Right Ctrl'; 181='Numpad /'; 183='Print Screen'
    184='Right Alt'; 197='Pause'
    199='Home'; 200='Up'; 201='Page Up'; 203='Left'; 205='Right'
    207='End'; 208='Down'; 209='Page Down'; 210='Insert'; 211='Delete'
}
# Short forms used on the key caps.
$script:DikCap = @{
    12='-'; 13='='; 26='['; 27=']'; 39=';'; 40="'"; 41='`'; 43='\'
    51=','; 52='.'; 53='/'; 55='Num *'; 58='Caps'; 69='NumLk'; 70='ScrLk'
    71='Num 7'; 72='Num 8'; 73='Num 9'; 74='Num -'; 75='Num 4'; 76='Num 5'
    77='Num 6'; 78='Num +'; 79='Num 1'; 80='Num 2'; 81='Num 3'; 82='Num 0'
    83='Num .'; 156='Num Enter'; 181='Num /'; 183='PrtScn'
    199='Home'; 201='PgUp'; 209='PgDn'; 210='Ins'; 211='Del'
    29='Ctrl'; 42='Shift'; 56='Alt'; 54='R Shift'; 157='R Ctrl'; 184='R Alt'
    14='Bksp'; 1='Esc'
}
# Codes the game accepts in the modifier position, in preference order.
$script:ModOrder = @(29, 42, 56, 157, 54, 184)
$script:ModName  = @{ 29='Ctrl'; 42='Shift'; 56='Alt'; 157='Right Ctrl'; 54='Right Shift'; 184='Right Alt' }

function Get-DikCap {
    param([int]$Code)
    if ($script:DikCap.ContainsKey($Code)) { return $script:DikCap[$Code] }
    if ($script:DikName.ContainsKey($Code)) { return $script:DikName[$Code] }
    return "DIK $Code"
}

# WPF Key name -> DIK.  Several WPF Key members share a value and ToString()
# does not always return the friendly alias, so both spellings are listed.
$script:WpfToDik = @{
    'Escape'=1
    'D1'=2;'D2'=3;'D3'=4;'D4'=5;'D5'=6;'D6'=7;'D7'=8;'D8'=9;'D9'=10;'D0'=11
    'OemMinus'=12;'Subtract'=74;'OemPlus'=13;'Add'=78
    'Back'=14;'Tab'=15
    'Q'=16;'W'=17;'E'=18;'R'=19;'T'=20;'Y'=21;'U'=22;'I'=23;'O'=24;'P'=25
    'OemOpenBrackets'=26;'Oem4'=26;'OemCloseBrackets'=27;'Oem6'=27
    'Return'=28;'Enter'=28
    'LeftCtrl'=29;'RightCtrl'=157
    'A'=30;'S'=31;'D'=32;'F'=33;'G'=34;'H'=35;'J'=36;'K'=37;'L'=38
    'OemSemicolon'=39;'Oem1'=39;'OemQuotes'=40;'Oem7'=40;'OemTilde'=41;'Oem3'=41
    'LeftShift'=42;'RightShift'=54
    'OemBackslash'=43;'Oem5'=43;'OemPipe'=43
    'Z'=44;'X'=45;'C'=46;'V'=47;'B'=48;'N'=49;'M'=50
    'OemComma'=51;'OemPeriod'=52;'OemQuestion'=53;'Oem2'=53
    'Multiply'=55;'Divide'=181
    'LeftAlt'=56;'RightAlt'=184
    'Space'=57;'Capital'=58;'CapsLock'=58
    'F1'=59;'F2'=60;'F3'=61;'F4'=62;'F5'=63;'F6'=64;'F7'=65;'F8'=66;'F9'=67;'F10'=68
    'F11'=87;'F12'=88
    'NumLock'=69;'Scroll'=70
    'NumPad7'=71;'NumPad8'=72;'NumPad9'=73;'NumPad4'=75;'NumPad5'=76;'NumPad6'=77
    'NumPad1'=79;'NumPad2'=80;'NumPad3'=81;'NumPad0'=82;'Decimal'=83
    'Snapshot'=183;'PrintScreen'=183;'Pause'=197
    'Home'=199;'Up'=200;'Prior'=201;'PageUp'=201;'Left'=203;'Right'=205
    'End'=207;'Down'=208;'Next'=209;'PageDown'=209;'Insert'=210;'Delete'=211
}

# -----------------------------------------------------------------------------
#  Key-binding taxonomy.  Derived from the action names; first rule wins.
#  Verified against all 269 actions in default.txt - nothing falls through to
#  "Other", but the fallback is kept in case a mod adds actions.
# -----------------------------------------------------------------------------
$script:KeyCategories = @(
    @{ N='Flight controls';           R='^(AILERON_|ELEVATOR_|RUDDER_)|^(AILTRIM|ELEVTRIM|RUDTRIM|RESETALLTRIM)|^FLAPS|^GEARUPDOWN$|^EMERGENCYGEAR$|^FK_(EMERGENCYUC|LANDING|ELEVATORTRIM|RUDDERTRIM)$|WHEELBRAKE$|^SPEEDBRAKE$|^BREAK$' }
    @{ N='Engine and systems';        R='^RPM_|PROPPITCH|^CYCLEENGINES$|^RESTARTENGINE$|^FK_(ENGINESTARTER|PRIMER|MAG|FUELCOCK|THROTTLE|BOOSTCUTOUT|PROPPITCH)|^FUELGUAGESELECTOR$|^CANOPYEJECT$|^EJECTPILOT$' }
    @{ N='Weapons and gunnery';       R='^SHOOT$|^DROPBOMB$|WEAPON|^BOXTARGET$|GUNNER$|^FK_(ARMED|GUNCAM)$|^GUNSIGHTVIEW$' }
    @{ N='Cockpit and head position'; R='^HEAD|^INOUTTOG$|^INSIDETOG$|^OUTSIDETOG$|^NOPITTOG$|^FLOORVIEW$|^INSTVIEW$|^VIEWMODETOG$' }
    @{ N='Look direction';            R='^A?LOOK' }
    @{ N='Target views and padlock';  R='PADLOCK|^(ENEMY|FRND|GRNDT|WAYPT|OTHERAC|ESCORTEE|AIUNFRIENDLY)VIEW$|^PREV(ENEMY|FRND|GRNDT|WAYPT)VIEW$|^RESET(ENEMY|FRND|GRNDT|WAYPT)VIEW$|^RESETVIEW$|^PCENEMY$|^ANYBANDITS$|^SEEMIGS$' }
    @{ N='External camera';           R='^(A|BIG)?ROT|^A?PAN(LEFT|RIGHT)$|^RCAM|^CHASETOG$|^FLANKERVIEWTOGGLE$|^OUTREVLOCKTOG$|^TOGGLEWOBBLEVIEW$' }
    @{ N='Zoom and field of view';    R='ZOOM|^FOV_' }
    @{ N='Map and navigation';        R='^GOTOMAPKEY$|^SATELLITOG$|^F3SATOGGLE$' }
    @{ N='Radio and messages';        R='MSG$|^MSGVIEW$|^RADIOCOMMS$|^TOGGLEMESSAGES$|^VOICETOGGLE$' }
    @{ N='Simulation and assists';    R='^ACCELKEY|^TOGGLE_DECEL$|^PAUSEKEY$|^AUTOPILOTTOGGLE$|^AUTOKEY$|^SPINRECOVERY$|^RESURRECTKEY$|^SUICIDE$' }
    @{ N='Interface and menus';       R='^MENU|^KEY_|^EXITKEY$|^CLEAR$|^MOUSE|^SENS_|^HUDTOGGLE$|^INFOPANEL$|^DISPLAY_FPS$|^IMPACTTOG$' }
    @{ N='Graphics detail';           R='^DETAIL|^NEXTSHAPE|^SHAPECHEATTOG$' }
    @{ N='Recording and capture';     R='^RECORD|^RESETRECORD$|^SCREENSHOT$' }
    @{ N='Music player';              R='^WINAMP_' }
    @{ N='Debug and testing';         R='^CHEAT|^PROF_|^TOGGLEPROFILER|^PCMODETOGGLE$' }
    @{ N='Other';                     R='.' }
)

# Explicit labels for the actions whose meaning is unambiguous.  Everything
# else is prettified mechanically.  The raw action name is always shown beneath
# the label, so a mechanical guess can never mislead.
$script:KeyLabel = @{
    'AILERON_LEFT'='Roll left';                 'AILERON_RIGHT'='Roll right'
    'ELEVATOR_BACK'='Pitch up';                 'ELEVATOR_FORWARD'='Pitch down'
    'RUDDER_LEFT'='Rudder left';                'RUDDER_RIGHT'='Rudder right'
    'AILTRIMUP'='Aileron trim up';              'AILTRIMDOWN'='Aileron trim down'
    'ELEVTRIMUP'='Elevator trim up';            'ELEVTRIMDOWN'='Elevator trim down'
    'RUDTRIMUP'='Rudder trim up';               'RUDTRIMDOWN'='Rudder trim down'
    'RESETALLTRIM'='Reset all trim'
    'FLAPSUP'='Flaps up';                       'FLAPSDOWN'='Flaps down'
    'GEARUPDOWN'='Undercarriage up / down';     'EMERGENCYGEAR'='Emergency undercarriage'
    'LEFTWHEELBRAKE'='Left wheel brake';        'RIGHTWHEELBRAKE'='Right wheel brake'
    'SPEEDBRAKE'='Air brake';                   'BREAK'='Break (evade)'
    'CYCLEENGINES'='Select next engine';        'RESTARTENGINE'='Restart engine'
    'PROPPITCHUP'='Propeller pitch up';         'PROPPITCHDOWN'='Propeller pitch down'
    'MAXPROPPITCH'='Propeller pitch to maximum';'MINPROPPITCH'='Propeller pitch to minimum'
    'RPM_UP'='Throttle up';                     'RPM_DOWN'='Throttle down'
    'RPM_ZERO'='Throttle closed';               'RPM_00'='Throttle 0 per cent'
    'RPM_BIG_UP'='Throttle up (coarse)';        'RPM_BIG_DOWN'='Throttle down (coarse)'
    'FUELGUAGESELECTOR'='Fuel gauge selector'
    'CANOPYEJECT'='Jettison canopy';            'EJECTPILOT'='Bale out'
    'SHOOT'='Fire guns';                        'DROPBOMB'='Release bombs'
    'NEXTWEAPON'='Next weapon';                 'LASTWEAPON'='Previous weapon'
    'CYCLETHROUGHWEAPONS'='Cycle weapons';      'DUMPWEAPONS'='Jettison weapons'
    'RELOADWEAPON'='Reload';                    'BOXTARGET'='Box the current target'
    'GUNSIGHTVIEW'='Gunsight view';             'NOSEGUNNER'='Nose gunner position'
    'DORSALGUNNER'='Dorsal gunner position';    'VENTRALGUNNER'='Ventral gunner position'
    'INOUTTOG'='Inside / outside view';         'INSIDETOG'='Cockpit view'
    'OUTSIDETOG'='External view';               'NOPITTOG'='Hide cockpit'
    'FLOORVIEW'='Look at the floor';            'INSTVIEW'='Instrument panel view'
    'VIEWMODETOG'='Cycle view mode'
    'HEADUP'='Move head up';                    'HEADDOWN'='Move head down'
    'HEADLEFT'='Move head left';                'HEADRIGHT'='Move head right'
    'HEADFORWARD'='Move head forward';          'HEADBACKWARD'='Move head back'
    'HEADOUTVIEWL'='Lean out to the left';      'HEADOUTVIEWR'='Lean out to the right'
    'LOOKN'='Look forward';   'LOOKNE'='Look forward-right'; 'LOOKE'='Look right'
    'LOOKSE'='Look back-right'; 'LOOKS'='Look back'; 'LOOKSW'='Look back-left'
    'LOOKW'='Look left';      'LOOKNW'='Look forward-left'
    'LOOKUPN'='Look up and forward';   'LOOKUPNE'='Look up and forward-right'
    'LOOKUPE'='Look up and right';     'LOOKUPSE'='Look up and back-right'
    'LOOKUPS'='Look up and back';      'LOOKUPSW'='Look up and back-left'
    'LOOKUPW'='Look up and left';      'LOOKUPNW'='Look up and forward-left'
    'LOOKUPTOG'='Look up toggle'
    'PADLOCKTOG'='Padlock target';     'PADLOCKOVERRIDE'='Padlock override'
    'ENEMYVIEW'='View next enemy';     'PREVENEMYVIEW'='View previous enemy'
    'RESETENEMYVIEW'='Reset enemy view'
    'FRNDVIEW'='View next friendly';   'PREVFRNDVIEW'='View previous friendly'
    'RESETFRNDVIEW'='Reset friendly view'
    'GRNDTVIEW'='View next ground target'; 'PREVGRNDTVIEW'='View previous ground target'
    'RESETGRNDTVIEW'='Reset ground target view'
    'WAYPTVIEW'='View next waypoint';  'PREVWAYPTVIEW'='View previous waypoint'
    'RESETWAYPTVIEW'='Reset waypoint view'
    'OTHERACVIEW'='View another aircraft'; 'ESCORTEEVIEW'='View the aircraft being escorted'
    'AIUNFRIENDLYVIEW'='View an unfriendly AI aircraft'
    'RESETVIEW'='Reset view';          'ANYBANDITS'='Call out bandits'
    'PCENEMY'='Nearest enemy';         'SEEMIGS'='Reveal all aircraft'
    'CHASETOG'='Chase camera';         'FLANKERVIEWTOGGLE'='Flanking camera'
    'OUTREVLOCKTOG'='Lock external view rotation'; 'TOGGLEWOBBLEVIEW'='Camera wobble'
    'RCAMTOGGLE'='Roving camera';      'RCAMRESET'='Reset roving camera'
    'RCAMFASTER'='Roving camera faster'; 'RCAMSLOWER'='Roving camera slower'
    'ROTRESET'='Reset external rotation'; 'ROTRESET2'='Reset external rotation (alternate)'
    'AROTRESET'='Reset alternate rotation'
    'ZOOMIN'='Zoom in';                'ZOOMOUT'='Zoom out'
    'BIGZOOMIN'='Zoom in (coarse)';    'BIGZOOMOUT'='Zoom out (coarse)'
    'AZOOMOUT'='Alternate zoom out'
    'FOV_SMALL'='Field of view - narrow';  'FOV_MEDIUM'='Field of view - medium'
    'FOV_LARGE'='Field of view - wide';    'FOV_TOGGLE'='Toggle field of view'
    'FOV_JIB01'='Field of view - preset'
    'GOTOMAPKEY'='Open the map';       'SATELLITOG'='Satellite view'
    'F3SATOGGLE'='F3 satellite toggle'
    'RADIOCOMMS'='Radio menu';         'TOGGLEMESSAGES'='Show / hide messages'
    'MSGVIEW'='Message view';          'VOICETOGGLE'='Voice on / off'
    'COMBATMSG'='Radio - combat';      'PRECOMBATMSG'='Radio - before combat'
    'POSTCOMBATMSG'='Radio - after combat'; 'TOWERMSG'='Radio - tower'
    'FACMSG'='Radio - forward air controller'; 'GROUPINFOMSG'='Radio - group information'
    'ACCELKEY'='Accelerate time';      'ACCELKEY2'='Accelerate time (alternate)'
    'TOGGLE_DECEL'='Toggle deceleration'; 'PAUSEKEY'='Pause'
    'AUTOPILOTTOGGLE'='Autopilot';     'AUTOKEY'='Auto key'
    'SPINRECOVERY'='Spin recovery assist'; 'RESURRECTKEY'='Resurrect'
    'SUICIDE'='End flight'
    'EXITKEY'='Exit to menu';          'CLEAR'='Clear'
    'HUDTOGGLE'='Show / hide HUD';     'INFOPANEL'='Information panel'
    'DISPLAY_FPS'='Show frame rate';   'IMPACTTOG'='Impact markers'
    'KEY_CONFIGMENU'='Open the configuration menu'
    'KEY_JOYSTICKCONFIG'='Open joystick configuration'
    'KEY_TOGGLE_DESC_TEXT'='Show / hide descriptive text'
    'MENUSELECT'='Menu - select';      'MENUBACK'='Menu - back'
    'MENUPLUS'='Menu - increase';      'MENUMINUS'='Menu - decrease'
    'MOUSEMODETOGGLE'='Mouse look on / off'
    'MOUSE_SENS_UP'='Mouse sensitivity up'; 'MOUSE_SENS_DOWN'='Mouse sensitivity down'
    'MOUSE_SENS_DEFAULT'='Mouse sensitivity default'
    'MOUSEWHEEL_SENS_UP'='Mouse wheel sensitivity up'
    'MOUSEWHEEL_SENS_DOWN'='Mouse wheel sensitivity down'
    'SENS_UP'='Control sensitivity up'; 'SENS_DOWN'='Control sensitivity down'
    'DETAILUP'='Increase detail';      'DETAILDN'='Reduce detail'
    'DETAILCANOPY'='Toggle canopy detail'; 'DETAILDIALS'='Toggle dial detail'
    'DETAILPANEL'='Toggle panel detail';   'DETAILSIDES'='Toggle cockpit sides'
    'DETAILSIGHT'='Toggle gunsight detail'
    'RECORDTOGGLE'='Start / stop recording'; 'RESETRECORD'='Reset recording'
    'SCREENSHOT'='Screenshot'
    'WINAMP_START'='Music - play';     'WINAMP_STOP'='Music - stop'
    'WINAMP_NEXT'='Music - next track';'WINAMP_PREV'='Music - previous track'
    'WINAMP_VOLUP'='Music - volume up';'WINAMP_VOLDOWN'='Music - volume down'
}

# Token expansions for the mechanical prettifier.
$script:KeyWords = [ordered]@{
    'TOGGLE'='toggle'; 'TOG'='toggle'; 'PREV'='previous'; 'FRND'='friendly'
    'GRNDT'='ground target'; 'WAYPT'='waypoint'; 'MSG'='message'; 'DN'='down'
    'PROPPITCH'='propeller pitch'; 'RPM'='throttle'; 'FOV'='field of view'
    'AC'='aircraft'; 'CPT'='cockpit'; 'RCAM'='roving camera'; 'ROT'='rotate'
    'FK'='function'; 'PROF'='profiler'; 'SPC'='single-player campaign'
    'AI'='AI'; 'UC'='undercarriage'; 'MAG'='magneto'; 'SENS'='sensitivity'
}

function ConvertTo-KeyLabel {
    param([string]$Action)
    if ($script:KeyLabel.ContainsKey($Action)) { return $script:KeyLabel[$Action] }
    $t = $Action -replace '_', ' '
    $t = $t -replace '(?<=[a-z])(?=[A-Z])', ' '
    foreach ($w in $script:KeyWords.Keys) {
        $t = [regex]::Replace($t, "(?i)\b$w\b", $script:KeyWords[$w])
    }
    $t = $t.ToLower() -replace '\s+', ' '
    $t = $t.Trim()
    if ($t.Length -gt 0) { $t = $t.Substring(0,1).ToUpper() + $t.Substring(1) }
    return $t
}

function Get-KeyCategory {
    param([string]$Action)
    foreach ($c in $script:KeyCategories) {
        if ($Action -match $c.R) { return $c.N }
    }
    return 'Other'
}

# -----------------------------------------------------------------------------
#  Curated bdg.txt metadata.
#  Every setting listed here gets a human label and an explanation.  Anything
#  not listed still appears on the "All settings" page with its own inline
#  comment as the description, so nothing is hidden.
#
#  -Rec sets a recommended value.  A row whose value differs from -Rec shows an
#  inline note, and the same rule drives the health checks on the Overview page,
#  so the two can never disagree.
# -----------------------------------------------------------------------------
function S {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Label,
        [string]$Hint = '',
        [string[]]$Choices = $null,   # each entry is 'rawvalue|display text'
        [string]$Rec = $null,
        [ValidateSet('critical','perf','info')][string]$Level = 'info',
        [string]$RecMsg = ''
    )
    @{ Key=$Key; Label=$Label; Hint=$Hint; Choices=$Choices; Rec=$Rec; Level=$Level; RecMsg=$RecMsg }
}

$D4 = @('1|1  -  Sparse (fastest)', '2|2  -  Balanced (recommended)', '3|3  -  Dense', '4|4  -  Maximum (very expensive)')

$script:Pages = [ordered]@{

 'Performance' = @{
  Sub = 'The handful of settings that actually decide your frame rate, and the ones that only look as if they do.'
  Sections = @(
   @{ T='Scene density'
      N='Ground detail is where this engine spends its time. If the frame rate is poor, start here and nowhere else.'
      I=@(
      (S 'OBJECT_DENSITY' 'Ground object density' 'How much is drawn on the ground. This is the single biggest frame-rate cost in the game - setting 4 roughly halves the frame rate compared with 2, for detail you will almost never look at.' -Choices $D4 -Rec '2' -Level perf -RecMsg 'Density above 2 is the most expensive setting in the game. Drop it to 2 before touching anything else.')
      (S 'PARTICLE_DENSITY' 'Particle density' 'Smoke, fire, dust and debris. The cost lands during heavy combat, which is exactly when you can least afford it.' -Choices $D4)
      (S 'LANDSCAPE_TEXTURE_SIZE' 'Terrain texture size' 'The larger set looks better. 1024 is the BDG team''s own documented remedy for a low frame rate and halves terrain texture memory.' -Choices @('2048|2048  -  Full detail','1024|1024  -  Half (the documented fix for low FPS)'))
      (S 'ENABLE_AUTO_GEN' 'Auto-generated scenery' 'Procedural ground clutter scattered over the landscape. Costs frame rate and adds nothing you will notice at combat speed.')
      (S 'ADD_SHEEP_COWS_AND_HAYSTACKS' 'Sheep, cows and haystacks' 'Charming, and pure cost. Only ever visible at very low level.')
      (S 'Render_Sheep_View_Radius' 'Livestock draw radius' 'How far out the animals above are drawn. Irrelevant if they are switched off.')
      (S 'ENABLE_FOREST_RIM_TREES' 'Trees along forest edges' 'Individual tree models placed around the edge of each wood.')
      (S 'RIM_TREE_DIST_TO_NEXT_TREE' 'Spacing between rim trees' 'Larger spacing means fewer trees and a higher frame rate. The comment in bdg.txt suggests 4300 for appearance.')
      (S 'SHAPE_NUM_OF_FOREST_RIM_TREES' 'Rim tree model number' 'Which 3D model is used for the edge trees.')
      (S 'ENABLE_TOWN_AND_FOREST_RAISES' 'Raised towns and forests' 'Session-only. The game rewrites this on exit, so it will not stick.')
      (S 'OPTIMISE_OBJECTS_DURING_RUNTIME' 'Optimise objects at runtime' 'Rebuilds object data while flying. Can trade a stutter now for a smoother average later.')
   )}
   @{ T='Frame pacing'
      N='On period hardware these smoothed the picture. On a modern machine running through a wrapper they mostly add latency.'
      I=@(
      (S 'SMOOTHEN_FRAMERATE_MODE' 'Frame smoothing' 'NONE lets frames arrive as fast as they are drawn. The other modes hold frames back, which adds input lag and on modern hardware often makes stutter worse rather than better.' -Choices @('NONE|NONE  -  no smoothing (recommended)','LIMITED|LIMITED  -  cap only','SMOOTHEN|SMOOTHEN  -  pace only','LIMIT_AND_SMOOTHEN|LIMIT_AND_SMOOTHEN  -  both') -Rec 'NONE' -Level perf -RecMsg 'NONE is recommended. Frame smoothing adds latency and rarely helps on modern hardware.')
      (S 'UI_REFRESH' 'Menu refresh rate' 'How often the 2D menus redraw, in hertz. Has no effect in flight.')
      (S 'DEBUG_STUTTER' 'Stutter debugging' 'Diagnostic output only. Leave at 0 unless you are chasing a hitch.')
   )}
   @{ T='Draw distance'
      N='Cheap to raise on a modern CPU, and the main thing that decides whether you see the aircraft that is about to shoot you.'
      I=@(
      (S 'PERIPHERAL_VISION_RANGE' 'Peripheral vision range' 'How far out other aircraft are tracked and drawn. Higher costs CPU but is the difference between spotting a bounce and being hit by one.')
      (S 'TRACKVIEWRANGE' 'Track view range' 'Range used by the tracking views.')
      (S 'TEMP_AG_DIST' 'Ground object distance' 'Distance at which ground objects stop being drawn. Undocumented in bdg.txt.')
      (S 'TEMP_AGTL_DIST' 'Ground object detail distance' 'Distance at which ground objects drop to a simpler model. Undocumented in bdg.txt.')
      (S 'NEAR_CLIP_NON_COCKPIT' 'Near clip plane (external)' 'How close geometry can get to the external camera before it is clipped away.')
   )}
  )
 }

 'Graphics' = @{
  Sub = 'Texture, lighting and display options. Most of this is GPU work, which a 2005 engine has no trouble finding on a modern card.'
  Sections = @(
   @{ T='Terrain and textures'; N=''
      I=@(
      (S 'USE_HIRES_LANDSCAPE_TILES' 'High-resolution landscape tiles' 'Sharper ground. Almost free on any modern graphics card.')
      (S 'HIRES_LANDSCAPE_OFFSET' 'High-resolution tile blend' 'Where the high-resolution tiles blend into the lower-resolution ones.')
      (S 'ENABLE_AUTO_TEXTURE_RES' 'Automatic texture resolution' 'Session-only: the comment in bdg.txt states the game writes ON back on exit, so a change here lasts one session.')
      (S 'USE_PCX_OR_DDS' 'Use PCX or DDS textures' 'Session-only, same as above. DDS is the faster path.')
      (S 'WK_LANDSCAPE_TEXTURES' 'Landscape texture set' 'Selects which set of ground textures is loaded.')
      (S 'EVERYTHING_OBSCURES_TERRAIN' 'Everything obscures terrain' 'Changes the depth ordering so all objects hide terrain behind them.')
      (S 'CHECK_TEXTURES_ARE_AS_EXPECTED' 'Verify textures on load' 'Diagnostic. Slows loading.')
      (S 'USE_DUMMY_IF_TEXTURE_MISSES' 'Substitute missing textures' 'Draws a placeholder instead of failing when a texture is absent. Useful with skin packs.')
   )}
   @{ T='Lighting and effects'; N=''
      I=@(
      (S 'DIFFUSE_FACTOR' 'Diffuse lighting strength' 'Overall brightness of surfaces lit directly by the sun.')
      (S 'SPEC_FACTOR' 'Specular highlight strength' 'How hard the highlights are on metal and glass.')
      (S 'DITHER_FACTOR' 'Dithering' 'Legacy dithering for low colour depths. Rarely worth changing.')
      (S 'BOB_DITHER_ALPHA' 'Dither alpha' 'Alpha threshold used by the dithering above.')
      (S 'RAIN_FACTOR' 'Rain density' 'How heavy rain looks when it falls.')
      (S 'Rain_Switch' 'Rain enabled' 'Master switch for rain.')
      (S 'IN_CLOUD_EFFECT_POLY_COUNT' 'In-cloud effect polygons' 'How many polygons make the whiteout when you fly into cloud.')
      (S 'IN_CLOUD_EFFECT_POLY_SIZE' 'In-cloud polygon size' '')
      (S 'IN_CLOUD_EFFECT_POLY_DOMAIN' 'In-cloud polygon spread' '')
   )}
   @{ T='Display'; N=''
      I=@(
      (S 'USE_DESKTOP_RESOLUTION' 'Use the desktop resolution' 'Takes the resolution from Windows instead of the value stored in settings.cfg.')
      (S 'FORCE_WINDOWED_MODE' 'Force windowed mode' 'Runs in a window. Often the quickest way out of a black screen on Windows 11.')
      (S 'DRAW_MENU_ON_3D_SCREEN' 'Draw menus on the 3D screen' 'Renders the menus through the 3D path rather than the 2D one.')
      (S 'BOB_SCREENSHOT_MODE' 'Screenshot mode' '0 is normal. Higher values capture at higher resolution by tiling.')
      (S 'NO_OF_HIRES_SCREENIE_TILES' 'High-resolution screenshot tiles' 'Tiles per row. 4 gives 16 tiles, so 16 times the pixels.')
   )}
   @{ T='Water colour'
      N='Six raw channel values. The defaults produce the dark North Sea; raising the light channels gives a Mediterranean look that is not remotely historical.'
      I=@(
      (S 'WATER_COLOUR_DARK_R' 'Deep water - red' ''); (S 'WATER_COLOUR_DARK_G' 'Deep water - green' ''); (S 'WATER_COLOUR_DARK_B' 'Deep water - blue' '')
      (S 'WATER_COLOUR_LIGHT_R' 'Shallow water - red' ''); (S 'WATER_COLOUR_LIGHT_G' 'Shallow water - green' ''); (S 'WATER_COLOUR_LIGHT_B' 'Shallow water - blue' '')
   )}
   @{ T='Aircraft markings'; N=''
      I=@(
      (S 'MULTI_SKIN_MODE' 'MultiSkin mode' 'Enables per-aircraft skins so squadrons carry their own codes. Only has any effect if MultiSkin is installed.' -Choices @('ENABLE|ENABLE','DISABLE|DISABLE','FX_FILES_ONLY|FX_FILES_ONLY','MS_FILES_ONLY|MS_FILES_ONLY'))
      (S 'SKINNERS_MODE' 'Skinner''s mode' 'Reloads textures on the fly. For people painting aircraft, not for flying.')
      (S 'AUTO_TEXTURE_CHANGE' 'Automatic texture change' '')
   )}
  )
 }

 'View and camera' = @{
  Sub = 'Field of view, head position, external cameras and padlock. Worth setting up properly - this game is largely about seeing things first.'
  Sections = @(
   @{ T='Field of view'
      N='Degrees. The game clamps the maximum to 110 unless ultra-high values are allowed.'
      I=@(
      (S 'FOV_INITIAL' 'Field of view on spawning' 'What you get when the mission starts.')
      (S 'FOV_MINIMAL' 'Narrowest field of view' 'The zoomed-in limit.')
      (S 'FOV_MAXIMAL' 'Widest field of view' 'The zoomed-out limit.')
      (S 'ALLOW_ULTRA_HIGH_FOVS' 'Allow ultra-high fields of view' 'Lifts the 110 degree cap. For ultrawide or multi-monitor setups.')
      (S 'NO_FOV_RESET' 'Keep field of view between views' 'Stops the field of view snapping back when you change view.')
      (S 'FOV_SMALL' 'Preset - narrow' ''); (S 'FOV_MEDIUM' 'Preset - medium' ''); (S 'FOV_LARGE' 'Preset - wide' '')
      (S 'FOV_TOGGLE_SMALL' 'Toggle preset - narrow' ''); (S 'FOV_TOGGLE_LARGE' 'Toggle preset - wide' '')
   )}
   @{ T='Head and cockpit'; N=''
      I=@(
      (S 'HEAD_BOBBING' 'Head movement' 'Head shifts with acceleration. Adds life; some find it tiring.')
      (S 'NO_HEAD_BOBBING_WHILE_PADLOCK' 'No head movement while padlocked' 'Steadies the picture when you are tracking a target.')
      (S 'CUSTOM_HEAD_POSITION' 'Custom head position' 'Enables the three eye offsets below.')
      (S 'EYE_X_POS' 'Eye position - sideways' ''); (S 'EYE_Y_POS' 'Eye position - vertical' ''); (S 'EYE_Z_POS' 'Eye position - fore and aft' '')
      (S 'CPTVIEWPOINTTRAVELRATE' 'Head movement speed' 'How quickly the viewpoint slides when you move your head.')
      (S 'CPTVIEWPOINTTRAVELINC' 'Head movement step' 'How far each press moves the viewpoint.')
      (S 'ALWAYS_BEHIND_GUNSIGHT' 'Always sit behind the gunsight' 'Keeps the eye aligned with the sight whatever else you do.')
      (S 'LOCK_GUNNER_VIEW_TO_GUN' 'Lock gunner view to the gun' 'In bomber gunner positions, the view follows the gun.')
      (S 'Your_2dGauges_Work_In_Autopilot' '2D gauges during autopilot' 'Keeps the pop-up gauges live while the autopilot flies.')
      (S '2DGAUGES_IN_PADLOCK_MODE' '2D gauges while padlocked' 'What the gauge overlay shows when a target is padlocked.' -Choices @('DISPLAY_SELF_ALWAYS|Always show your own aircraft','DISPLAY_PADLOCKED_PLANE_DAMAGE_DATA|Show the padlocked aircraft''s damage','DISPLAY_PADLOCKED_PLANE_ALL_DATA|Show all of the padlocked aircraft''s data'))
      (S 'HEAD_BOBBING' 'Head movement' '')
   )}
   @{ T='External views'; N=''
      I=@(
      (S 'External_View_Starting_Distance' 'Starting distance' 'How far the external camera sits from the aircraft. 1.3 restores the closer view from earlier builds.')
      (S 'External_View_Zoom_Distance' 'Maximum zoom distance' 'How far the external camera can be pulled back.')
      (S 'INVERT_EXTERNAL_PAN' 'Invert external panning' '')
      (S 'PAN_SPEED_FACTOR' 'Panning speed' 'How fast the view swings when you pan.')
      (S 'NO_PILOT_IN_ROVING_CAM' 'Hide the pilot in the roving camera' '')
   )}
   @{ T='Padlock'; N=''
      I=@(
      (S 'DRAW_PADLOCK_CENTER_BOX' 'Draw the padlock box' 'The box drawn around the padlocked aircraft.')
      (S 'DEATH_BREAKS_PADLOCK' 'Break padlock when the target dies' '')
      (S 'BOB_PADLOCKFIX' 'Padlock fix' 'A community correction to padlock behaviour.')
      (S 'PADLOCK_OVERRIDES_TRACKIR' 'Padlock overrides TrackIR' 'Padlock takes control of the view away from head tracking.')
   )}
   @{ T='Head tracking'; N='TrackIR and compatible head trackers.'
      I=@(
      (S 'TRACKIR' 'TrackIR enabled' '')
      (S 'TRACKIR6DOF' 'Six degrees of freedom' 'Allows translation as well as rotation.')
      (S 'TRACKIR_Z_AXIS_MODE' 'Z axis mode' 'How forward and back movement of your head is interpreted.')
      (S 'NO_OUTSIDE_TRACKIR' 'Disable TrackIR outside the cockpit' '')
   )}
  )
 }

 'Weather and sky' = @{
  Sub = 'The sky model, the cloud layers, and the three-line Weather.cfg that the GFX screen writes to but never fully shows you.'
  Sections = @(
   @{ T='Weather.cfg'
      N='A separate 53-byte file. SkyDetail is what the GFX screen labels Weather Detail. HorizonDistance is not exposed anywhere in the game.'
      I=@() }
   @{ T='Daylight'; N=''
      I=@(
      (S 'Weather_Dawn_Time_Sec' 'Dawn' 'Seconds after midnight. 17100 is 04:45.')
      (S 'Weather_Dusk_Time_Sec' 'Dusk' 'Seconds after midnight. 71700 is 19:55.')
   )}
   @{ T='Sky model'
      N='A Preetham-style analytic sky. These are the model coefficients; small changes have large effects.'
      I=@(
      (S 'Weather_Turbidity' 'Turbidity' 'Haze in the atmosphere. Low is a clear day, high is a summer murk.')
      (S 'Weather_SkyExposure' 'Sky exposure' ''); (S 'Weather_SkyGamma' 'Sky gamma' '')
      (S 'Weather_SunIntensity' 'Sun intensity' ''); (S 'Weather_SunColor' 'Sun colour' '')
      (S 'Weather_SunGlow' 'Sun glow' ''); (S 'Weather_SunFlare' 'Sun flare' '')
      (S 'Weather_CloudAlbedo' 'Cloud albedo' 'How much light clouds reflect.')
      (S 'Weather_MieG' 'Mie scattering g' ''); (S 'Weather_MMult' 'Mie multiplier' ''); (S 'Weather_RMult' 'Rayleigh multiplier' '')
      (S 'Weather_SkyLambda1' 'Sky wavelength 1' ''); (S 'Weather_SkyLambda2' 'Sky wavelength 2' ''); (S 'Weather_SkyLambda3' 'Sky wavelength 3' '')
      (S 'Weather_SunLambda1' 'Sun wavelength 1' ''); (S 'Weather_SunLambda2' 'Sun wavelength 2' ''); (S 'Weather_SunLambda3' 'Sun wavelength 3' '')
   )}
   @{ T='Fair weather clouds'; N=''
      I=@(
      (S 'Cloud_Fair_CloudCover' 'Cover' 'Set to zero by default to remove the flat cloud layer.')
      (S 'Cloud_Fair_CloudDensity' 'Density' '')
      (S 'Cloud_Fair_CloudSliceHeight' 'Base height' 'Feet. 3048 is 10,000 ft.')
   )}
   @{ T='Poor weather clouds'; N=''
      I=@(
      (S 'Cloud_Poor_CloudCover' 'Cover' ''); (S 'Cloud_Poor_CloudDensity' 'Density' '')
      (S 'Cloud_Poor_NimbusCover' 'Nimbus cover' ''); (S 'Cloud_Poor_CloudSliceHeight' 'Base height' '')
   )}
   @{ T='Inclement weather'; N=''
      I=@(
      (S 'Cloud_Inclement_CloudCover' 'Cover' ''); (S 'Cloud_Inclement_CloudDensity' 'Density' '')
      (S 'Cloud_Inclement_NimbusCover' 'Nimbus cover' ''); (S 'Cloud_Inclement_CloudSliceHeight' 'Base height' '')
      (S 'Cloud_Inclement_RainStrength' 'Rain strength' '')
      (S 'Cloud_Inclement_FogDensity' 'Fog density' ''); (S 'Cloud_Inclement_FogEndMult' 'Fog end multiplier' '')
   )}
  )
 }

 'Realism and AI' = @{
  Sub = 'Gunnery, flight model corrections, enemy behaviour and anti-aircraft fire.'
  Sections = @(
   @{ T='Gunnery'; N=''
      I=@(
      (S 'CONVERGENCE' 'Gun convergence' 'The range at which the wing guns cross. Historically 250 to 400 yards; the RAF shortened it during the battle.')
      (S 'BULLET_LIFESPAN' 'Bullet lifespan' 'Seconds before a round is removed. Effectively the maximum range.')
      (S 'Bullet_Dispersion' 'Bullet dispersion' 'The master switch for gun scatter. ON is realistic.')
      (S 'Bullet_DragGravity' 'Bullet drag and gravity' 'Rounds slow and drop. bdg.txt records that the BDG team recommend this ON.' -Rec 'ON' -Level info -RecMsg 'bdg.txt notes that Stickman recommends this setting be ON.')
      (S 'Player_Stronger_Bullets' 'Player bullets do more damage' 'Only the player benefits. Off is historical.')
      (S 'HIDE_AMMO_COUNTER' 'Hide the ammunition counter' 'Historical - the pilot had no round counter.')
      (S 'Do_You_Want_Increase_Firing_Rate_Of_Hand_Held_Gunners' 'Historic hand-held gun rate of fire' '')
   )}
   @{ T='Flight model'; N=''
      I=@(
      (S 'PLAYER_REDUCE_SURFACE_DEFLECTION' 'Realistic control deflection - player' 'Control surfaces stiffen with speed, as they did.')
      (S 'AI_REDUCE_SURFACE_DEFLECTION' 'Realistic control deflection - AI' '')
      (S 'FIX_KEYBOARD_RUDDER' 'Keyboard rudder fix' '')
      (S 'BOB_SMOOTHER_DEADZONE' 'Smoothed joystick deadzone' 'Softens the transition out of the centre of the stick.')
      (S 'Wind_Effects_Fraction' 'Wind strength' 'A fraction of full wind. 0.25 is a quarter strength.')
      (S 'ENGINE_ALWAYS_RUNNING' 'Engine always running' 'Skips the starting drill.')
      (S 'BOB_DISABLE_ENGINE_CUTOUT' 'Disable negative-g engine cutout' 'The Merlin''s float carburettor cut under negative g. The DB601 did not - that is why the 109 could bunt away.')
      (S 'BOB_DISABLE_STALL_HORN' 'Disable the stall warning' 'No aircraft in 1940 had one.')
      (S 'No_Spinning_Death' 'No spinning death' 'OFF gives the original Rowan spinning death effect.')
      (S 'Do_You_Want_AI_AC_To_Spin' 'Allow AI aircraft to spin' 'Global switch for AI departures.')
      (S 'Use_The_Spinout_Maneuver' 'AI spin-out manoeuvre' '')
      (S 'AutoPilot_Kludge' 'Autopilot kludge' 'For flight-model work only. Leave OFF.')
   )}
   @{ T='Damage and collisions'; N=''
      I=@(
      (S 'Friendly_Fire' 'Friendly fire' 'ON is historical - people did shoot their own side.')
      (S 'NO_FRIENDLY_COLLISIONS' 'No collisions with friendlies' 'Stops your own formation destroying you on take-off.')
      (S 'Collision_Detection_And_Avoidance' 'AI collision avoidance' 'Must be ON for the AI to avoid each other at all.')
      (S 'Air_To_Air_Collision_Bubble_Size' 'Collision bubble size' 'Smaller means fewer collisions.')
      (S 'Collision_Avoidance_Rear_End' 'Avoidance look-ahead - astern' 'Seconds.')
      (S 'Collision_Avoidance_Head_On' 'Avoidance look-ahead - head on' 'Seconds.')
   )}
   @{ T='Enemy and wingman AI'; N=''
      I=@(
      (S 'SPC_Skill_RAF' 'Forced RAF skill level' 'Overrides the skill of every RAF pilot in a single-player campaign. NONE leaves the campaign to decide.' -Choices @('NONE|NONE  -  let the campaign decide','HERO|HERO','ACE|ACE','VETERAN|VETERAN','REGULAR|REGULAR','POOR|POOR','NOVICE|NOVICE'))
      (S 'SPC_Skill_LUF' 'Forced Luftwaffe skill level' 'As above, for the Luftwaffe.' -Choices @('NONE|NONE  -  let the campaign decide','HERO|HERO','ACE|ACE','VETERAN|VETERAN','REGULAR|REGULAR','POOR|POOR','NOVICE|NOVICE'))
      (S 'Do_You_Want_Random_Mixed_Squad_skills' 'Mixed skill within a squadron' 'Squadrons contain a spread of ability rather than one uniform level.')
      (S 'Max_Number_AI_Targeting_Player' 'Maximum AI attacking you' 'How many enemy aircraft may engage you at once.')
      (S 'Max_Number_AI_Targeting_AI' 'Maximum AI attacking one AI' '')
      (S 'AI_Always_Sees_Enemy' 'AI always sees the enemy' 'Removes AI spotting limits. Not historical.')
      (S 'Wingmen_Always_Sees_Enemy' 'Wingmen always see the enemy' '')
      (S 'Novice_AI' 'Novice AI' 'Instant Action only.')
      (S 'Novice_AI_Airspeed_Fraction' 'Novice AI speed' 'A fraction of normal speed.')
      (S 'Novice_Target_Size' 'Oversized targets' 'Larger hit boxes for practice.')
      (S 'Novice_Gunnery_Predictor' 'Gunnery predictor' 'Shows where to aim. You must padlock the target to see it.')
      (S 'Do_You_Want_To_Fight_The_Terminator_AI' 'Terminator AI' 'Instant Action only.')
      (S 'Do_You_Want_The_JU87_To_DogFight' 'Ju 87 will dogfight' 'ON makes the Stuka turn and fight after evading.')
      (S 'RAF_Breaksoff_Before_France' 'RAF turns back before France' 'Fighter Command policy - they were not to cross the Channel.')
      (S 'Testing_Do_Not_Shoot' 'AI will not shoot' 'Testing only.')
   )}
   @{ T='Flak and anti-aircraft fire'; N=''
      I=@(
      (S 'Do_You_Want_Flak_And_AAA_Fire' 'Flak and AAA enabled' '')
      (S 'Do_You_Want_Flak_Over_France' 'Flak over France' '')
      (S 'Do_You_Want_Flak_And_AAA_Fire_if_Friendly_within_1000_Meters' 'Fire with friendlies within 1000 m' '')
      (S 'Increase_Flak_and_AAA_Rate_Of_Fire' 'Increased rate of fire' '')
      (S 'Flak_Size_In_Meters' 'Flak burst radius' 'Metres. A burst this close forces major damage.')
      (S 'Reload_LT_BRIT_3_7IN_Gun' 'British 3.7 in reload' 'Centiseconds. 2400 is 24 seconds.')
      (S 'Reload_LT_BRIT_4_5IN_Gun' 'British 4.5 in reload' 'Centiseconds.')
      (S 'LT_BRIT_BOFORS_Reloadtime' 'Bofors reload' 'Centiseconds.')
   )}
   @{ T='Campaign'; N=''
      I=@(
      (S 'Allow_Commander_Campaign_Sack' 'You can be sacked' 'Perform badly enough as commander and you lose the job.')
      (S 'Campaign_Break_Off_Code' 'Campaign break-off logic' '')
      (S 'SELECT_QS_SQUADRONS' 'Choose squadron in Quick Start' '')
      (S 'Time_In_IA_Missions_Until_LUF_Returns_Home' 'Instant Action time limit' 'Minutes before the Luftwaffe goes home. 0 means no limit.')
      (S 'Remove_SPC_Warning_Message' 'Suppress the waypoint warning' 'Hides the recursive-waypoint message.')
      (S 'Permit_Annoying_Radio_chatter' 'Radio chatter' 'The bdg.txt author''s own choice of adjective.')
   )}
  )
 }

 'Interface' = @{
  Sub = 'Videos, labels, on-screen information and dialogs. The video settings at the top are the ones that stop the game crashing on Windows 10 and 11.'
  Sections = @(
   @{ T='Videos - required on modern Windows'
      N='The full-motion video is Indeo 5, a codec Microsoft removed from Windows for security reasons. There is no supported way to put it back, and attempting playback takes the game down.'
      I=@(
      (S 'SKIP_VIDEOS' 'Skip full-motion video' 'Must be ON. The Indeo codec these clips need is absent from modern Windows and playback crashes the game.' -Rec 'ON' -Level critical -RecMsg 'Must be ON. The Indeo codec is absent from Windows 10 and 11 and playback crashes the game.')
      (S 'SKIP_QUICKVIDEOS' 'Skip short video clips' 'Must be ON, for the same reason.' -Rec 'ON' -Level critical -RecMsg 'Must be ON. Same Indeo codec problem as the full-motion video.')
      (S 'INTRO_VIDEO' 'Play the intro video' 'Must be OFF, for the same reason.' -Rec 'OFF' -Level critical -RecMsg 'Must be OFF. The intro clip uses the missing Indeo codec and will crash the game on startup.')
   )}
   @{ T='On-screen information'; N=''
      I=@(
      (S 'TEXT_REMINDERS' 'Text reminders' 'Prompts such as undercarriage and flap warnings.')
      (S 'HIDE_POWER_INFO' 'Hide the power readout' '')
      (S 'SHOW_INFOLINE_BACKGROUND' 'Info line background' 'A panel behind the info line so it stays readable over cloud.')
      (S 'INFOLINE_COLOUR' 'Info line colour' 'Eight hex digits, alpha first.')
      (S 'DISABLE_ALL_2D_ELEMENTS' 'Disable all 2D elements' 'A clean screen for screenshots and film. bdg.txt notes it is not fully implemented.')
      (S 'USE_NATIONAL_UNITS' 'National units' 'Feet and miles per hour for the RAF, metres and kilometres per hour for the Luftwaffe.')
      (S 'ENEMY_POSITION_INDICATOR' 'Enemy position indicator' 'An arrow towards the nearest enemy. Not historical.')
      (S 'EPI_RADIUS' 'Indicator radius' ''); (S 'EPI_Y_RADIUS' 'Indicator vertical radius' '')
      (S 'ART_HORIZON_SIZE' 'Artificial horizon size' '')
      (S 'RETICLE_SIZE_BIAS' 'Gunsight reticle size' '')
   )}
   @{ T='Aircraft labels'; N='Labels are the single largest concession to playability in the game.'
      I=@(
      (S 'FADING_LABELS' 'Fade labels with distance' 'Labels dim as the aircraft gets further away.')
      (S 'SHORTENED_LABELS' 'Short labels' 'ME109 rather than the full type name.')
      (S 'Single_Chararacter_Labels' 'Single-character labels' 'One letter per aircraft. The misspelling is in the game file, not here.')
      (S 'Single_Character_Label_Friendly' 'Friendly label character' 'A single character. Blank uses the default.')
      (S 'Single_Character_Label_Enemy' 'Enemy label character' 'A single character. Blank uses the default.')
      (S 'LABELCOLOUR_FRIENDLY' 'Friendly label colour' 'Six hex digits, red green blue.')
      (S 'LABELCOLOUR_ENEMY' 'Enemy label colour' 'Six hex digits, red green blue.')
      (S 'LABEL_FULL_ALPHA' 'Fully opaque out to' 'Range in game units.')
      (S 'LABEL_HALF_ALPHA' 'Half faded at' ''); (S 'LABEL_ZERO_ALPHA' 'Invisible beyond' '')
   )}
   @{ T='Dialogs and pausing'; N=''
      I=@(
      (S 'CONTINUE_QUIT_BOX_CAMPAIGN' 'Confirm on quitting a campaign' '')
      (S 'CONTINUE_QUIT_BOX_QUICK' 'Confirm on quitting a quick mission' '')
      (S 'GAME_PAUSE' 'Pause on mission start' 'Starts every mission paused so you can set up before anything happens.')
      (S 'ENABLE_MOUSE_PLACEMENT_MODE' 'Mouse placement mode' '')
      (S 'WINAMP_FADES_OUT' 'Fade music out' 'For the in-game Winamp control.')
   )}
  )
 }
}

# =============================================================================
#  FILE MODEL
#  Every file is held as an array of lines (or bytes) plus an index of parsed
#  entries that remember which line they came from.  Writing rebuilds the line
#  from captured groups, so nothing outside the value is ever disturbed.
# =============================================================================

$script:GameFolder = $null
$script:BdgLines   = @()
$script:Bdg        = @{}    # KEY -> @{ Key Value Original Comment Line G1 G2 G4 G5 }
$script:BdgOrder   = @()
$script:KeyLines   = @()
$script:Keys       = @{}    # ACTION -> @{ Action Line Gap Trail Kb Dev OrigKb }
$script:KeyOrder   = @()
$script:Defaults   = @{}    # ACTION -> array of keyboard chords
$script:CfgBytes   = $null
$script:CfgOrig    = $null
$script:WxLines    = @()
$script:Wx         = @{}    # KEY -> @{ Value Original Line G1 G2 G4 G5 }
$script:Paths      = @{}

# KEY = VALUE  [# comment]
#   g1 'KEY ='   g2 spaces   g3 value   g4 spaces   g5 comment
# The key charset includes [ and ] because bdg.txt contains the 32-element
# BOB_DITHER_LOOK_UP[n] array.  Excluding them is what makes the file look like
# 318 settings rather than the 350 assignments it actually holds.
$script:BdgRx = [regex]'^(\s*[A-Za-z_0-9\[\]]+\s*=)([ \t]*)([^#]*?)([ \t]*)(#.*)?$'

function Read-TextFile {
    param([string]$Path)
    ,($script:Enc1252.GetString([System.IO.File]::ReadAllBytes($Path)) -split "`r`n", 0)
}

function Write-TextFile {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllBytes($Path, $script:Enc1252.GetBytes(($Lines -join "`r`n")))
}

function Read-Bdg {
    param([string]$Path)
    $script:BdgLines = Read-TextFile $Path
    $script:Bdg = @{}
    $script:BdgOrder = @()
    for ($i = 0; $i -lt $script:BdgLines.Count; $i++) {
        $m = $script:BdgRx.Match($script:BdgLines[$i])
        if (-not $m.Success) { continue }
        $name = ($m.Groups[1].Value -replace '=\s*$','').Trim()
        if ($script:Bdg.ContainsKey($name)) { continue }   # first occurrence wins
        $script:Bdg[$name] = @{
            Key      = $name
            Value    = $m.Groups[3].Value
            Original = $m.Groups[3].Value
            Comment  = ($m.Groups[5].Value -replace '^#\s*','').Trim()
            Line     = $i
            G1 = $m.Groups[1].Value; G2 = $m.Groups[2].Value
            G4 = $m.Groups[4].Value; G5 = $m.Groups[5].Value
        }
        $script:BdgOrder += $name
    }
}

function Set-BdgValue {
    param([string]$Key, [string]$Value)
    if (-not $script:Bdg.ContainsKey($Key)) { return }
    $script:Bdg[$Key].Value = $Value
}

function Build-BdgLine {
    param($E)
    $gap4 = $E.G4
    # Three lines in bdg.txt put a value straight against its comment, e.g.
    #   Cloud_Fair_CloudCover = 0.000000#Changed Default to zero per Stickman
    # so an absent gap is NOT on its own a reason to add one - doing that
    # rewrites lines nobody touched.  Padding is inserted only where the
    # shipped value was blank and we are filling it in, which would otherwise
    # glue the new value onto the '#'.
    if ($E.Original -eq '' -and $E.Value -ne '' -and $gap4 -eq '' -and $E.G5 -ne '') { $gap4 = '    ' }
    $E.G1 + $E.G2 + $E.Value + $gap4 + $E.G5
}

# =============================================================================
#  JOYSTICK AND POV CODES
#  keys.txt encodes non-keyboard input as codes >= 256.  Decoded from the
#  shipped keys.txt and default.txt, which agree exactly:
#
#      buttons   260 + 40*device + button      device 0-3
#      POV hats  580 +  8*hat    + direction   hat 0-7, direction 0=up clockwise
#
#  Evidence for the 40-per-device stride: SHOOT is 260 300 340 380 and
#  ROTRESET2 is 261 301 341 381 - the same physical button on four devices.
#  Evidence for the POV block: the eight ROT* actions each carry eight codes
#  spaced 8 apart, together filling 580..643 exactly with no gaps.
#
#  256-259 and 420-579 are used by no shipped binding and are NOT decoded here;
#  most likely axes.  Anything unrecognised is displayed as its raw number and
#  written back untouched, so an unknown code can never be corrupted.
# =============================================================================
$script:JoyBtnBase   = 260
$script:JoyBtnStride = 40
$script:JoyMaxDev    = 4
$script:PovBase      = 580
$script:PovStride    = 8
$script:PovMaxHat    = 8
$script:PovNames     = @('Up', 'Up-Right', 'Right', 'Down-Right', 'Down', 'Down-Left', 'Left', 'Up-Left')

function Format-DevCode {
    param([string]$Code)
    if ($Code -notmatch '^\d+$') { return $Code }
    $n = [int]$Code
    $btnTop = $script:JoyBtnBase + ($script:JoyBtnStride * $script:JoyMaxDev)
    if ($n -ge $script:JoyBtnBase -and $n -lt $btnTop) {
        $d = [math]::Floor(($n - $script:JoyBtnBase) / $script:JoyBtnStride)
        $b = ($n - $script:JoyBtnBase) % $script:JoyBtnStride
        return ('Joy ' + ($d + 1) + '  Button ' + ($b + 1))
    }
    $povTop = $script:PovBase + ($script:PovStride * $script:PovMaxHat)
    if ($n -ge $script:PovBase -and $n -lt $povTop) {
        $h = [math]::Floor(($n - $script:PovBase) / $script:PovStride)
        $r = ($n - $script:PovBase) % $script:PovStride
        return ('Hat ' + ($h + 1) + '  ' + $script:PovNames[$r])
    }
    return ('Code ' + $n)
}

function ConvertTo-JoyButtonCode { param([int]$Device, [int]$Button)
    $script:JoyBtnBase + ($script:JoyBtnStride * $Device) + $Button }
function ConvertTo-PovCode { param([int]$Hat, [int]$Direction)
    $script:PovBase + ($script:PovStride * $Hat) + $Direction }

# winmm rather than DirectInput: joyGetPosEx is a two-function interop that
# needs no extra runtime, and covers buttons plus the primary hat, which is
# what the game's own bindings use.  It exposes only ONE hat per device, so
# capture can produce hat 1 codes; hats 2-8 can still be typed by hand and are
# displayed and preserved correctly.
$script:JoyReady = $false
function Initialize-Joystick {
    if ($script:JoyReady) { return $true }
    try {
        if (-not ('BOB2Joy' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BOB2Joy {
    [StructLayout(LayoutKind.Sequential)]
    public struct JOYINFOEX {
        public int dwSize, dwFlags, dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos;
        public int dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2;
    }
    [DllImport("winmm.dll")] public static extern int joyGetPosEx(int id, ref JOYINFOEX pji);
    public static bool Poll(int id, out int buttons, out int pov) {
        JOYINFOEX j = new JOYINFOEX();
        j.dwSize  = Marshal.SizeOf(typeof(JOYINFOEX));
        j.dwFlags = 0xFF;                       // JOY_RETURNALL
        int r = joyGetPosEx(id, ref j);
        buttons = j.dwButtons;
        pov     = j.dwPOV;
        return r == 0;                          // JOYERR_NOERROR
    }
}
'@
        }
        $script:JoyReady = $true
    } catch {
        $script:JoyReady = $false
    }
    $script:JoyReady
}

# Returns @{ Device Buttons Pov } for every device that responds, or an empty
# array when nothing is plugged in.
function Get-JoystickState {
    if (-not (Initialize-Joystick)) { return @() }
    $out = @()
    for ($i = 0; $i -lt $script:JoyMaxDev; $i++) {
        $b = 0; $p = 0
        try { $ok = [BOB2Joy]::Poll($i, [ref]$b, [ref]$p) } catch { $ok = $false }
        if ($ok) { $out += @{ Device = $i; Buttons = $b; Pov = $p } }
    }
    ,$out
}

# ACTION codes...      codes are DIK chords (<256) or joystick/POV codes (>=256)
$script:KeyRx = [regex]'^(\S+)([ \t]*)(.*?)([ \t]*)$'

function Parse-KeyLine {
    param([string]$Line)
    $m = $script:KeyRx.Match($Line)
    if (-not $m.Success) { return $null }
    $body = $m.Groups[3].Value
    $kb = @(); $dev = @()
    foreach ($tok in ($body -split '\s+')) {
        if ($tok -eq '') { continue }
        if ($tok -notmatch '^\d+(\+\d+)?$') { $dev += $tok; continue }
        $parts = $tok -split '\+'
        if (($parts | ForEach-Object { [int]$_ } | Where-Object { $_ -ge 256 }).Count -gt 0) { $dev += $tok }
        else { $kb += $tok }
    }
    @{ Action = $m.Groups[1].Value; Gap = $m.Groups[2].Value; Trail = $m.Groups[4].Value
       Kb = @($kb); Dev = @($dev) }
}

function Read-Keys {
    param([string]$Path)
    $script:KeyLines = Read-TextFile $Path
    $script:Keys = @{}
    $script:KeyOrder = @()
    for ($i = 0; $i -lt $script:KeyLines.Count; $i++) {
        if ($script:KeyLines[$i].Trim() -eq '') { continue }
        $p = Parse-KeyLine $script:KeyLines[$i]
        if (-not $p) { continue }
        if ($script:Keys.ContainsKey($p.Action)) { continue }
        $p.Line = $i
        $p.OrigKb = @($p.Kb)
        $p.OrigDev = @($p.Dev)
        $script:Keys[$p.Action] = $p
        $script:KeyOrder += $p.Action
    }
}

function Read-Defaults {
    param([string]$Path)
    $script:Defaults = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($line in (Read-TextFile $Path)) {
        if ($line.Trim() -eq '') { continue }
        $p = Parse-KeyLine $line
        if ($p) { $script:Defaults[$p.Action] = @($p.Kb) }
    }
}

function Build-KeyLine {
    param($E)
    $body = (@($E.Kb) + @($E.Dev)) -join ' '
    if ($body -eq '') { return $E.Action + $E.Gap }   # unbound: 'ACTION ' exactly as shipped
    $E.Action + $E.Gap + $body + $E.Trail
}

function Test-KeyChanged {
    param($E)
    ((($E.Kb -join ' ') -ne ($E.OrigKb -join ' ')) -or
     (($E.Dev -join ' ') -ne (@($E.OrigDev) -join ' ')))
}

# Weather.cfg uses the same shape as bdg.txt, so it reuses the same regex.
function Read-Weather {
    param([string]$Path)
    $script:WxLines = Read-TextFile $Path
    $script:Wx = @{}
    for ($i = 0; $i -lt $script:WxLines.Count; $i++) {
        $m = $script:BdgRx.Match($script:WxLines[$i])
        if (-not $m.Success) { continue }
        $name = ($m.Groups[1].Value -replace '=\s*$','').Trim()
        $script:Wx[$name] = @{
            Key = $name; Value = $m.Groups[3].Value; Original = $m.Groups[3].Value; Line = $i
            G1 = $m.Groups[1].Value; G2 = $m.Groups[2].Value
            G4 = $m.Groups[4].Value; G5 = $m.Groups[5].Value
        }
    }
}

# -----------------------------------------------------------------------------
#  settings.cfg - 1786 bytes, banner "Rowan Savegame: V 002".
#  Offsets established by differential analysis (change one option in game,
#  quit cleanly, diff the file).  Recorded in mod92/tools/SETTINGS_CFG_MAP.md.
#  Everything not listed here is copied through untouched.
# -----------------------------------------------------------------------------
$script:CfgOffsets = @{ GroundShadingByte = 1676; GroundShadingBit = 0x20
                        Gamma = 1684; ItemShading = 1688; Mirror = 1754
                        ResW = 1416; ResH = 1480; ResHz = 1544; ResBpp = 1608 }

function Get-CfgBit  { param([int]$Off,[int]$Mask) [bool]($script:CfgBytes[$Off] -band $Mask) }
function Set-CfgBit  {
    param([int]$Off,[int]$Mask,[bool]$On)
    if ($On) { $script:CfgBytes[$Off] = [byte](($script:CfgBytes[$Off] -bor $Mask) -band 0xFF) }
    else     { $script:CfgBytes[$Off] = [byte](($script:CfgBytes[$Off] -band (-bnot $Mask)) -band 0xFF) }
}
function Test-CfgChanged {
    if (-not $script:CfgBytes -or -not $script:CfgOrig) { return $false }
    for ($i = 0; $i -lt $script:CfgBytes.Length; $i++) {
        if ($script:CfgBytes[$i] -ne $script:CfgOrig[$i]) { return $true }
    }
    $false
}

# -----------------------------------------------------------------------------
#  Locating the installation.
# -----------------------------------------------------------------------------
function Test-GameFolder {
    param([string]$Folder)
    $Folder -and (Test-Path -LiteralPath (Join-Path $Folder 'bdg.txt'))
}

function Find-GameFolder {
    $remembered = Join-Path $script:ScriptDir 'BOB2_Config.path'
    $candidates = @()
    if (Test-Path -LiteralPath $remembered) {
        $candidates += (Get-Content -LiteralPath $remembered -TotalCount 1 -ErrorAction SilentlyContinue)
    }
    $candidates += $script:ScriptDir
    $candidates += (Split-Path -Parent $script:ScriptDir)
    foreach ($root in @('C:','D:','E:','F:')) {
        $candidates += "$root\Battle of Britain II"
        $candidates += "$root\Games\Battle of Britain II"
        $candidates += "$root\Program Files (x86)\Battle of Britain II"
        $candidates += "$root\Program Files (x86)\Shockwave\Battle of Britain II"
    }
    foreach ($c in $candidates) { if (Test-GameFolder $c) { return $c } }
    return $null
}

function Save-GameFolder {
    param([string]$Folder)
    try { Set-Content -LiteralPath (Join-Path $script:ScriptDir 'BOB2_Config.path') -Value $Folder -Encoding ASCII } catch { }
}

function Request-GameFolder {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title  = 'Locate bdg.txt in your Battle of Britain II folder'
    $dlg.Filter = 'bdg.txt|bdg.txt|All files|*.*'
    $dlg.CheckFileExists = $true
    if ($dlg.ShowDialog() -eq $true) { return (Split-Path -Parent $dlg.FileName) }
    return $null
}

function Load-AllFiles {
    param([string]$Folder)
    $script:Paths = @{
        Bdg     = Join-Path $Folder 'bdg.txt'
        Keys    = Join-Path $Folder 'KEYBOARD\keys.txt'
        Default = Join-Path $Folder 'KEYBOARD\default.txt'
        Cfg     = Join-Path $Folder 'SAVEGAME\settings.cfg'
        Wx      = Join-Path $Folder 'Weather\Weather.cfg'
    }
    Read-Bdg $script:Paths.Bdg
    if (Test-Path -LiteralPath $script:Paths.Keys) { Read-Keys $script:Paths.Keys } else { $script:KeyLines=@(); $script:Keys=@{}; $script:KeyOrder=@() }
    Read-Defaults $script:Paths.Default
    if (Test-Path -LiteralPath $script:Paths.Cfg) {
        $script:CfgBytes = [System.IO.File]::ReadAllBytes($script:Paths.Cfg)
        $script:CfgOrig  = [System.IO.File]::ReadAllBytes($script:Paths.Cfg)
    } else { $script:CfgBytes = $null; $script:CfgOrig = $null }
    if (Test-Path -LiteralPath $script:Paths.Wx) { Read-Weather $script:Paths.Wx } else { $script:WxLines=@(); $script:Wx=@{} }
}

# -----------------------------------------------------------------------------
#  Change accounting
# -----------------------------------------------------------------------------
function Get-ChangedBdg   { @($script:BdgOrder | Where-Object { $script:Bdg[$_].Value -ne $script:Bdg[$_].Original }) }
function Get-ChangedKeys  { @($script:KeyOrder | Where-Object { Test-KeyChanged $script:Keys[$_] }) }
function Get-ChangedWx    { @($script:Wx.Keys  | Where-Object { $script:Wx[$_].Value -ne $script:Wx[$_].Original }) }
function Get-ChangeCount  { (Get-ChangedBdg).Count + (Get-ChangedKeys).Count + (Get-ChangedWx).Count + $(if (Test-CfgChanged) { 1 } else { 0 }) }

function Save-All {
    $stamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $backup  = Join-Path $script:GameFolder ('_ConfigBackups\' + $stamp)
    $report  = New-Object System.Collections.ArrayList
    $wrote   = $false

    function Backup-One {
        param([string]$Path, [string]$Leaf)
        $dest = Join-Path $backup $Leaf
        $dir  = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $Path -Destination $dest -Force
    }

    $bdgChanged = Get-ChangedBdg
    if ($bdgChanged.Count) {
        Backup-One $script:Paths.Bdg 'bdg.txt'
        foreach ($k in $bdgChanged) {
            $e = $script:Bdg[$k]
            $script:BdgLines[$e.Line] = Build-BdgLine $e
        }
        Write-TextFile $script:Paths.Bdg $script:BdgLines
        foreach ($k in $bdgChanged) { $script:Bdg[$k].Original = $script:Bdg[$k].Value }
        [void]$report.Add(@{ File='bdg.txt'; N=$bdgChanged.Count; What='setting' }); $wrote = $true
    }

    $keyChanged = Get-ChangedKeys
    if ($keyChanged.Count) {
        Backup-One $script:Paths.Keys 'KEYBOARD\keys.txt'
        foreach ($a in $keyChanged) {
            $e = $script:Keys[$a]
            $script:KeyLines[$e.Line] = Build-KeyLine $e
        }
        Write-TextFile $script:Paths.Keys $script:KeyLines
        foreach ($a in $keyChanged) {
            $script:Keys[$a].OrigKb  = @($script:Keys[$a].Kb)
            $script:Keys[$a].OrigDev = @($script:Keys[$a].Dev)
        }
        [void]$report.Add(@{ File='KEYBOARD\keys.txt'; N=$keyChanged.Count; What='binding' }); $wrote = $true
    }

    $wxChanged = Get-ChangedWx
    if ($wxChanged.Count) {
        Backup-One $script:Paths.Wx 'Weather\Weather.cfg'
        foreach ($k in $wxChanged) {
            $e = $script:Wx[$k]
            $script:WxLines[$e.Line] = Build-BdgLine $e
        }
        Write-TextFile $script:Paths.Wx $script:WxLines
        foreach ($k in $wxChanged) { $script:Wx[$k].Original = $script:Wx[$k].Value }
        [void]$report.Add(@{ File='Weather\Weather.cfg'; N=$wxChanged.Count; What='setting' }); $wrote = $true
    }

    if (Test-CfgChanged) {
        $n = 0
        for ($i = 0; $i -lt $script:CfgBytes.Length; $i++) { if ($script:CfgBytes[$i] -ne $script:CfgOrig[$i]) { $n++ } }
        Backup-One $script:Paths.Cfg 'SAVEGAME\settings.cfg'
        [System.IO.File]::WriteAllBytes($script:Paths.Cfg, $script:CfgBytes)
        $script:CfgOrig = [byte[]]$script:CfgBytes.Clone()
        [void]$report.Add(@{ File='SAVEGAME\settings.cfg'; N=$n; What='byte' }); $wrote = $true
    }

    @{ Wrote = $wrote; Report = $report; Backup = $backup }
}

# =============================================================================
#  INTERFACE
#  The XAML below is a literal single-quoted here-string: PowerShell performs no
#  expansion inside it, so no escaping of $ or ` is needed.  It declares no
#  custom types and no custom converters, so XamlReader never has to resolve an
#  assembly and the whole thing loads without Add-Type.
#
#  Palette: instrument-panel colours.  Near-black blue-greys for the chrome,
#  a bone/parchment text colour rather than pure white, and a single brass
#  accent taken from dial lighting.  Red and amber are reserved strictly for
#  conflicts and warnings so they still mean something when they appear.
# =============================================================================
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battle of Britain II - Configuration"
        Width="1360" Height="900" MinWidth="1100" MinHeight="720"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        Background="#0E1116"
        UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Ideal"
        TextOptions.TextRenderingMode="ClearType"
        TextElement.Foreground="#E4DFD4"
        FontFamily="Segoe UI Variable Text, Segoe UI, Tahoma" FontSize="13">
  <Window.Resources>

    <SolidColorBrush x:Key="Rail"      Color="#0B0E12"/>
    <SolidColorBrush x:Key="Surface"   Color="#12161C"/>
    <SolidColorBrush x:Key="Card"      Color="#171C24"/>
    <SolidColorBrush x:Key="CardHi"    Color="#1E242E"/>
    <SolidColorBrush x:Key="Field"     Color="#0D1116"/>
    <SolidColorBrush x:Key="Popup"     Color="#1A202A"/>
    <SolidColorBrush x:Key="Line"      Color="#232A34"/>   <!-- decorative hairlines ONLY -->
    <SolidColorBrush x:Key="Edge"      Color="#626A77"/>   <!-- borders of anything clickable: 3.33:1, WCAG needs 3:1 -->
    <SolidColorBrush x:Key="LineSoft"  Color="#1C222B"/>
    <SolidColorBrush x:Key="Text"      Color="#E4DFD4"/>
    <SolidColorBrush x:Key="Muted"     Color="#AEB6C2"/>   <!-- 8.34:1 (was #98A0AC) -->
    <SolidColorBrush x:Key="Dim"       Color="#949DAC"/>   <!-- 6.25:1 (was #697280 = 3.52:1, FAILED AA) -->
    <SolidColorBrush x:Key="Accent"    Color="#C8973F"/>
    <SolidColorBrush x:Key="AccentSoft" Color="#8A6B2E"/>
    <SolidColorBrush x:Key="AccentWash" Color="#2A2114"/>
    <SolidColorBrush x:Key="Danger"    Color="#E2685A"/>   <!-- 5.18:1 (was #C9564A = 4.00:1, FAILED AA) -->
    <SolidColorBrush x:Key="DangerWash" Color="#2C1614"/>
    <SolidColorBrush x:Key="Warn"      Color="#D9A441"/>
    <SolidColorBrush x:Key="Good"      Color="#8FB56A"/>   <!-- 7.32:1 -->
    <SolidColorBrush x:Key="Info"      Color="#7FA6CE"/>   <!-- 6.72:1 -->

    <!-- Lucide icons, ISC licence - https://lucide.dev -->
    <PathGeometry x:Key="IcoClipboardCheck" Figures="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2 M9,14 l2 2 4-4 M9.0,2.0 H15.0 A1.0,1.0 0 0 1 16.0,3.0 V5.0 A1.0,1.0 0 0 1 15.0,6.0 H9.0 A1.0,1.0 0 0 1 8.0,5.0 V3.0 A1.0,1.0 0 0 1 9.0,2.0 Z"/>
    <PathGeometry x:Key="IcoCloudSun" Figures="M12 2v2 M4.93,4.93 l1.41 1.41 M20 12h2 M19.07,4.93 l-1.41 1.41 M15.947 12.65a4 4 0 0 0-5.925-4.128 M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6Z"/>
    <PathGeometry x:Key="IcoCrosshair" Figures="M2.0,12.0 A10.0,10.0 0 1 0 22.0,12.0 A10.0,10.0 0 1 0 2.0,12.0 Z M22.0,12.0 L18.0,12.0 M6.0,12.0 L2.0,12.0 M12.0,6.0 L12.0,2.0 M12.0,22.0 L12.0,18.0"/>
    <PathGeometry x:Key="IcoEye" Figures="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0 M9.0,12.0 A3.0,3.0 0 1 0 15.0,12.0 A3.0,3.0 0 1 0 9.0,12.0 Z"/>
    <PathGeometry x:Key="IcoFileCog" Figures="M15 8a1 1 0 0 1-1-1V2a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8z M20 8v12a2 2 0 0 1-2 2h-4.182 M3.305,19.53 l.923-.382 M4 10.592V4a2 2 0 0 1 2-2h8 M4.228,16.852 l-.924-.383 M5.852,15.228 l-.383-.923 M5.852,20.772 l-.383.924 M8.148,15.228 l.383-.923 M8.53,21.696 l-.382-.924 M9.773,16.852 l.922-.383 M9.773,19.148 l.922.383 M4.0,18.0 A3.0,3.0 0 1 0 10.0,18.0 A3.0,3.0 0 1 0 4.0,18.0 Z"/>
    <PathGeometry x:Key="IcoFileText" Figures="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z M14 2v5a1 1 0 0 0 1 1h5 M10 9H8 M16 13H8 M16 17H8"/>
    <PathGeometry x:Key="IcoGauge" Figures="M12,14 l4-4 M3.34 19a10 10 0 1 1 17.32 0"/>
    <PathGeometry x:Key="IcoJoystick" Figures="M21 17a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-2Z M6 15v-2 M12 15V9 M9.0,6.0 A3.0,3.0 0 1 0 15.0,6.0 A3.0,3.0 0 1 0 9.0,6.0 Z"/>
    <PathGeometry x:Key="IcoKeyboard" Figures="M10 8h.01 M12 12h.01 M14 8h.01 M16 12h.01 M18 8h.01 M6 8h.01 M7 16h10 M8 12h.01 M4.0,4.0 H20.0 A2.0,2.0 0 0 1 22.0,6.0 V18.0 A2.0,2.0 0 0 1 20.0,20.0 H4.0 A2.0,2.0 0 0 1 2.0,18.0 V6.0 A2.0,2.0 0 0 1 4.0,4.0 Z"/>
    <PathGeometry x:Key="IcoLayoutDashboard" Figures="M4.0,3.0 H9.0 A1.0,1.0 0 0 1 10.0,4.0 V11.0 A1.0,1.0 0 0 1 9.0,12.0 H4.0 A1.0,1.0 0 0 1 3.0,11.0 V4.0 A1.0,1.0 0 0 1 4.0,3.0 Z M15.0,3.0 H20.0 A1.0,1.0 0 0 1 21.0,4.0 V7.0 A1.0,1.0 0 0 1 20.0,8.0 H15.0 A1.0,1.0 0 0 1 14.0,7.0 V4.0 A1.0,1.0 0 0 1 15.0,3.0 Z M15.0,12.0 H20.0 A1.0,1.0 0 0 1 21.0,13.0 V20.0 A1.0,1.0 0 0 1 20.0,21.0 H15.0 A1.0,1.0 0 0 1 14.0,20.0 V13.0 A1.0,1.0 0 0 1 15.0,12.0 Z M4.0,16.0 H9.0 A1.0,1.0 0 0 1 10.0,17.0 V20.0 A1.0,1.0 0 0 1 9.0,21.0 H4.0 A1.0,1.0 0 0 1 3.0,20.0 V17.0 A1.0,1.0 0 0 1 4.0,16.0 Z"/>
    <PathGeometry x:Key="IcoMonitor" Figures="M8.0,21.0 L16.0,21.0 M12.0,17.0 L12.0,21.0 M4.0,3.0 H20.0 A2.0,2.0 0 0 1 22.0,5.0 V15.0 A2.0,2.0 0 0 1 20.0,17.0 H4.0 A2.0,2.0 0 0 1 2.0,15.0 V5.0 A2.0,2.0 0 0 1 4.0,3.0 Z"/>

    <PathGeometry x:Key="IcoInfo" Figures="M12 16v-4 M12 8h.01 M2.0,12.0 A10.0,10.0 0 1 0 22.0,12.0 A10.0,10.0 0 1 0 2.0,12.0 Z"/>
    <PathGeometry x:Key="IcoSettings" Figures="M10 5H3 M12 19H3 M14 3v4 M16 17v4 M21 12h-9 M21 19h-5 M21 5h-7 M8 10v4 M8 12H3"/>

    <!-- Typography -->
    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="26"/><Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/><Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="MaxWidth" Value="760"/>
      <Setter Property="LineHeight" Value="22"/>
    </Style>
    <Style x:Key="Eyebrow" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    </Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="17"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource Accent}"/>
    </Style>
    <Style x:Key="RowLabel" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="RowHint" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13.5"/><Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="LineHeight" Value="20"/>
      <Setter Property="Margin" Value="0,4,0,0"/>
    </Style>
    <Style x:Key="Mono" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Cascadia Mono, Consolas"/><Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
    </Style>

    <!-- Scrollbars: the stock ones are light grey and ruin a dark window -->
    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="11"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="T" Background="#333B48" CornerRadius="4" Margin="3"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="T" Property="Background" Value="#4A5464"/>
                          </Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False" Background="Transparent" BorderThickness="0"/>
                </Track.IncreaseRepeatButton>
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False" Background="Transparent" BorderThickness="0"/>
                </Track.DecreaseRepeatButton>
              </Track>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="Orientation" Value="Horizontal">
                <Setter Property="Width" Value="Auto"/>
                <Setter Property="Height" Value="11"/>
                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToolTip">
            <Border Background="#1E242E" BorderBrush="#333B48" BorderThickness="1" CornerRadius="4" Padding="10,7">
              <ContentPresenter TextBlock.Foreground="#D8D3C8" TextBlock.FontSize="12"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Setter Property="MaxWidth" Value="380"/>
    </Style>

    <!-- Navigation rail -->
    <Style x:Key="NavItem" TargetType="RadioButton">
      <Setter Property="Height" Value="34"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Grid>
              <Border x:Name="Bg" Background="Transparent"/>
              <Rectangle x:Name="Bar" Width="3" HorizontalAlignment="Left" Fill="Transparent"/>
              <ContentPresenter Margin="22,0,14,0" VerticalAlignment="Center"
                                TextBlock.Foreground="{TemplateBinding Foreground}"
                                TextBlock.FontSize="{TemplateBinding FontSize}"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bg" Property="Background" Value="#141922"/>
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bg" Property="Background" Value="#181E27"/>
                <Setter TargetName="Bar" Property="Fill" Value="{StaticResource Accent}"/>
                <Setter Property="Foreground" Value="{StaticResource Text}"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Buttons -->
    <Style x:Key="BtnBase" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                Margin="{TemplateBinding Padding}"
                                TextBlock.Foreground="{TemplateBinding Foreground}"
                                TextBlock.FontSize="{TemplateBinding FontSize}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.65"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
      <Setter Property="Foreground" Value="#1A1206"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="BtnGhost" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="{StaticResource Edge}"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
    </Style>
    <Style x:Key="BtnQuiet" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="8,0"/>
      <Setter Property="FontSize" Value="11.5"/>
    </Style>

    <!-- Text input -->
    <Style x:Key="FieldBox" TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource Field}"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="CaretBrush" Value="{StaticResource Accent}"/>
      <Setter Property="SelectionBrush" Value="{StaticResource AccentSoft}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Edge}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Padding" Value="9,0"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="4">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="#8A93A1"/></Trigger>
              <Trigger Property="IsFocused" Value="True"><Setter TargetName="B" Property="BorderBrush" Value="{StaticResource AccentSoft}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SearchBox" TargetType="TextBox" BasedOn="{StaticResource FieldBox}">
      <Setter Property="Height" Value="34"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="12,0"/>
    </Style>

    <!-- ComboBox -->
    <Style TargetType="ComboBoxItem">
      <Setter Property="Padding" Value="11,7"/>
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="B" Background="Transparent" Padding="{TemplateBinding Padding}">
              <ContentPresenter TextBlock.Foreground="{TemplateBinding Foreground}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="B" Property="Background" Value="{StaticResource AccentWash}"/>
                <Setter Property="Foreground" Value="{StaticResource Accent}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Combo" TargetType="ComboBox">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="MaxDropDownHeight" Value="340"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="B" Background="{StaticResource Field}" BorderBrush="{StaticResource Edge}"
                            BorderThickness="1" CornerRadius="4">
                      <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,11,0"
                            Data="M 0 0 L 4.5 4.5 L 9 0" Stroke="#8A929E" StrokeThickness="1.4"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="B" Property="BorderBrush" Value="{StaticResource AccentSoft}"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Margin="11,0,28,0" VerticalAlignment="Center" IsHitTestVisible="False"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                TextBlock.Foreground="{TemplateBinding Foreground}"
                                TextBlock.FontSize="{TemplateBinding FontSize}"/>
              <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False"
                     IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Fade">
                <Border Background="{StaticResource Popup}" BorderBrush="{StaticResource Line}" BorderThickness="1"
                        CornerRadius="4" Margin="0,3,0,0"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <ScrollViewer><ItemsPresenter/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ON / OFF switch -->
    <Style x:Key="Switch" TargetType="ToggleButton">
      <Setter Property="Width" Value="44"/><Setter Property="Height" Value="24"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid Background="Transparent">
              <Border x:Name="Track" CornerRadius="12" Background="#1A1F27" BorderBrush="#333B48" BorderThickness="1"/>
              <Border x:Name="Knob" Width="16" Height="16" CornerRadius="8" Background="#6C7583"
                      HorizontalAlignment="Left" Margin="4,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#3A2C13"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Knob" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Track" Property="BorderBrush" Value="{StaticResource AccentSoft}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- A key binding row is one big button: click the caps to rebind -->
    <Style x:Key="ChipButton" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Right"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="Transparent" BorderBrush="Transparent" BorderThickness="1"
                    CornerRadius="5" Padding="8,5">
              <ContentPresenter HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="B" Property="Background" Value="#1B212B"/>
                <Setter TargetName="B" Property="BorderBrush" Value="{StaticResource AccentSoft}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

  </Window.Resources>

  <Border BorderBrush="#2A2F38" BorderThickness="1">
  <DockPanel LastChildFill="True">
    <!-- Custom title bar. Default WPF chrome shows the powershell.exe icon
         and a Windows title bar, which looks nothing like the rest of the
         app and announces that you are running a script. -->
    <Grid x:Name="ChromeBar" DockPanel.Dock="Top" Background="#1A1E25" Height="34">
      <TextBlock Text="BATTLE OF BRITAIN II  -  SETTINGS" Foreground="#AEB6C2" FontSize="12" FontWeight="SemiBold"
                 VerticalAlignment="Center" Margin="16,0,0,0"
                 FontFamily="Bahnschrift SemiCondensed, Segoe UI"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <!-- Options. In the title bar rather than on a settings page,
             because someone who cannot read the app cannot navigate to a
             page to fix that. Visible from every page. -->
        <Border x:Name="ChromeCog" Width="40" Height="34" Background="Transparent" Cursor="Hand"
                ToolTip="Text size and options">
          <Viewbox Width="17" Height="17">
            <Canvas Width="24" Height="24">
              <Path Data="{StaticResource IcoSettings}" Fill="{x:Null}" Stroke="#AEB6C2"
                    StrokeThickness="1.9" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                    StrokeLineJoin="Round"/>
            </Canvas>
          </Viewbox>
        </Border>
        <Border x:Name="ChromeMin" Width="40" Height="34" Background="Transparent" Cursor="Hand">
          <TextBlock Text="&#x2013;" Foreground="#AEB6C2" FontSize="14"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="ChromeMax" Width="40" Height="34" Background="Transparent" Cursor="Hand"
                ToolTip="Maximise">
          <TextBlock Text="&#x25A1;" Foreground="#AEB6C2" FontSize="13"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="ChromeClose" Width="40" Height="34" Background="Transparent" Cursor="Hand">
          <TextBlock Text="&#x2715;" Foreground="#AEB6C2" FontSize="13"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </StackPanel>

      <!-- Options popup. Anchored to the cog, closes when you click away. -->
      <Popup x:Name="CogPopup" PlacementTarget="{Binding ElementName=ChromeCog}"
             Placement="Bottom" StaysOpen="False" AllowsTransparency="True"
             HorizontalOffset="-236" VerticalOffset="4">
        <Border Background="{StaticResource Popup}" BorderBrush="{StaticResource Edge}"
                BorderThickness="1" CornerRadius="6" Padding="18">
          <StackPanel Width="280">
            <TextBlock Text="TEXT SIZE" Style="{StaticResource Eyebrow}"/>
            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
              <Button x:Name="BtnSize100" Content="A" Style="{StaticResource BtnGhost}"
                      FontSize="13" MinWidth="52" Padding="6,6"/>
              <Button x:Name="BtnSize115" Content="A" Style="{StaticResource BtnGhost}"
                      FontSize="16" MinWidth="52" Padding="6,6" Margin="8,0,0,0"/>
              <Button x:Name="BtnSize130" Content="A" Style="{StaticResource BtnGhost}"
                      FontSize="19" MinWidth="52" Padding="6,6" Margin="8,0,0,0"/>
            </StackPanel>
            <TextBlock Style="{StaticResource RowHint}" Margin="0,10,0,0"
                       Text="Makes everything in this window bigger. The window grows with it, up to the size of your screen."/>

            <Rectangle Height="1" Fill="{StaticResource Line}" Margin="0,16,0,14"/>
            <TextBlock Text="THIS WINDOW" Style="{StaticResource Eyebrow}"/>
            <TextBlock x:Name="CogInfoGame"  Style="{StaticResource RowHint}" Margin="0,8,0,0"/>
            <TextBlock x:Name="CogInfoFiles" Style="{StaticResource RowHint}" Margin="0,4,0,0"/>
            <TextBlock x:Name="CogInfoVer"   Style="{StaticResource RowHint}" Margin="0,4,0,0"/>
            <Button x:Name="BtnCogFolder" Content="Open the game folder" Style="{StaticResource BtnGhost}"
                    HorizontalAlignment="Left" Margin="0,14,0,0"/>
          </StackPanel>
        </Border>
      </Popup>
    </Grid>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <!-- Photograph band. The same device as the launcher - full-bleed
         photograph, dark scrim on the left, condensed caps over it - so the
         two windows read as one application. It sits ABOVE the rail and the
         page rather than behind them: no body text is ever laid over a
         photograph, which is what would undo the contrast work. -->
    <Grid Grid.Row="0" Height="128" ClipToBounds="True">
      <Image x:Name="BandBg" Stretch="UniformToFill"
             HorizontalAlignment="Center" VerticalAlignment="Center"/>
      <Rectangle HorizontalAlignment="Left" Width="620">
        <Rectangle.Fill>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#F5080B10" Offset="0.0"/>
            <GradientStop Color="#E6080B10" Offset="0.55"/>
            <GradientStop Color="#00080B10" Offset="1.0"/>
          </LinearGradientBrush>
        </Rectangle.Fill>
      </Rectangle>
      <Rectangle VerticalAlignment="Bottom" Height="46">
        <Rectangle.Fill>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#00080B10" Offset="0.0"/>
            <GradientStop Color="#FF0E1116" Offset="1.0"/>
          </LinearGradientBrush>
        </Rectangle.Fill>
      </Rectangle>
      <StackPanel VerticalAlignment="Center" Margin="34,0,0,10">
        <TextBlock Text="BATTLE OF BRITAIN II" FontSize="27" FontWeight="Bold"
                   Foreground="#F4F1EB"
                   FontFamily="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
        <TextBlock Text="SETTINGS" FontSize="15" FontWeight="Bold" Foreground="#C8102E"
                   Margin="1,2,0,0"
                   FontFamily="Bahnschrift SemiCondensed, Bahnschrift, Segoe UI"/>
      </StackPanel>
      <TextBlock VerticalAlignment="Bottom" HorizontalAlignment="Right"
                 Margin="0,0,16,6" FontSize="11" Foreground="#8E8880"
                 Text="IWM CL186 - Normandy, June 1944"/>
    </Grid>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="238"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Navigation rail -->
      <Border Grid.Column="0" Background="{StaticResource Rail}" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <StackPanel Grid.Row="0" Margin="22,26,20,22">
            <Grid Width="34" Height="34" HorizontalAlignment="Left">
              <Ellipse Fill="#2E4A72"/>
              <Ellipse Fill="#CFC8B8" Width="21" Height="21"/>
              <Ellipse Fill="#A34438" Width="9" Height="9"/>
            </Grid>
            <!-- The band above already says which game and which screen this
                 is. Repeating it here was just noise beside the roundel. -->
          </StackPanel>

          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel x:Name="NavPanel" Margin="0,0,0,20"/>
          </ScrollViewer>

          <Border Grid.Row="2" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Padding="22,14">
            <StackPanel>
              <TextBlock Text="INSTALLATION" Style="{StaticResource Eyebrow}"/>
              <TextBlock x:Name="FolderText" Style="{StaticResource Mono}" TextWrapping="Wrap" Margin="0,5,0,0"/>
              <Button x:Name="BtnChangeFolder" Content="Change folder" Style="{StaticResource BtnQuiet}"
                      HorizontalAlignment="Left" Margin="-8,4,0,0"/>
            </StackPanel>
          </Border>
        </Grid>
      </Border>

      <!-- Content -->
      <Grid Grid.Column="1" Background="{StaticResource Surface}">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Padding="34,26,34,20" BorderBrush="{StaticResource Line}" BorderThickness="0,0,0,1">
          <StackPanel>
            <TextBlock x:Name="HeadTitle" Style="{StaticResource H1}"/>
            <TextBlock x:Name="HeadSub" Style="{StaticResource Sub}" Margin="0,6,0,0"/>
          </StackPanel>
        </Border>

        <Grid x:Name="PageHost" Grid.Row="1"/>

        <Border Grid.Row="2" Background="{StaticResource Rail}" BorderBrush="{StaticResource Line}"
                BorderThickness="0,1,0,0" Padding="34,0">
          <Grid Height="60">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="{StaticResource Dim}" VerticalAlignment="Center"/>
              <TextBlock x:Name="StatusText" Margin="10,0,0,0" VerticalAlignment="Center"
                         FontSize="12.5" Foreground="{StaticResource Muted}"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <Button x:Name="BtnLauncher" Content="Back to launcher" Style="{StaticResource BtnGhost}"
                      Margin="0,0,10,0"/>
              <Button x:Name="BtnRevert" Content="Discard changes" Style="{StaticResource BtnGhost}" IsEnabled="False"/>
              <Button x:Name="BtnSave" Content="Save to disk" Style="{StaticResource BtnPrimary}"
                      Margin="10,0,0,0" IsEnabled="False"/>
            </StackPanel>
          </Grid>
        </Border>
      </Grid>
    </Grid>

    <!-- Modal layer: key capture and save results -->
    <Grid x:Name="Overlay" Background="#D6070A0E" Visibility="Collapsed">
      <Border x:Name="OverlayCard" Background="{StaticResource Card}" BorderBrush="{StaticResource Line}"
              BorderThickness="1" CornerRadius="8" Padding="30" MaxWidth="560"
              HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel x:Name="OverlayHost"/>
      </Border>
    </Grid>
  </Grid>
  </DockPanel>
  </Border>
</Window>

'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$Win = [Windows.Markup.XamlReader]::Load($reader)

$NavPanel        = $Win.FindName('NavPanel')
# Custom title bar: dragging a WindowStyle="None" window is manual, and the
# buttons are Borders so they cannot inherit a dialog's Button style.
$bar = $Win.FindName('ChromeBar')
if ($bar) { $bar.Add_MouseLeftButtonDown({ $Win.DragMove() }) }
$cx = $Win.FindName('ChromeClose')
if ($cx) {
    $cx.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled = $true; $Win.Close() })
    $cx.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#C8102E') })
    $cx.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
}
$cmax = $Win.FindName('ChromeMax')
if ($cmax) {
    $cmax.Add_MouseLeftButtonDown({
        param($s,$e); $e.Handled = $true
        $Win.WindowState = $(if ($Win.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' })
    })
    $cmax.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#2C313A') })
    $cmax.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
}
$cog = $Win.FindName('ChromeCog')
if ($cog) {
    # Mouse UP, not DOWN. A Popup with StaysOpen="False" opened on mouse-down
    # is dismissed by the very click that opened it, so the panel appeared
    # never to work at all. Handled stops the title bar starting a drag.
    $cog.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled = $true })
    $cog.Add_MouseLeftButtonUp({
        param($s,$e)
        $e.Handled = $true
        $pop = $Win.FindName('CogPopup')
        if ($pop) { $pop.IsOpen = -not $pop.IsOpen }
    })
    $cog.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#2C313A') })
    $cog.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
}

$cm = $Win.FindName('ChromeMin')
if ($cm) {
    $cm.Add_MouseLeftButtonDown({ param($s,$e) $e.Handled = $true; $Win.WindowState = 'Minimized' })
    $cm.Add_MouseEnter({ param($s,$e) $s.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#2C313A') })
    $cm.Add_MouseLeave({ param($s,$e) $s.Background = [Windows.Media.Brushes]::Transparent })
}

$PageHost        = $Win.FindName('PageHost')
$HeadTitle       = $Win.FindName('HeadTitle')
$HeadSub         = $Win.FindName('HeadSub')
$StatusDot       = $Win.FindName('StatusDot')
$StatusText      = $Win.FindName('StatusText')
$BtnSave         = $Win.FindName('BtnSave')
$BtnRevert       = $Win.FindName('BtnRevert')
$BtnLauncher     = $Win.FindName('BtnLauncher')
$FolderText      = $Win.FindName('FolderText')
$BtnChangeFolder = $Win.FindName('BtnChangeFolder')
$Overlay         = $Win.FindName('Overlay')
$OverlayHost     = $Win.FindName('OverlayHost')

# Named Res, not R: PowerShell ships R as an alias for Invoke-History and
# aliases beat functions during command resolution, so 'R' would never run.
function Res { param([string]$Key) $Win.FindResource($Key) }

# =============================================================================
#  SMALL ELEMENT FACTORIES
#  Rows are built in code rather than data-bound.  PowerShell's WPF binding
#  needs INotifyPropertyChanged to push updates back to the screen, which means
#  Add-Type and a C# compile at startup; building controls directly avoids both
#  and keeps every update explicit.
# =============================================================================
function New-TB {
    param([string]$Text = '', [string]$Style = $null, [string]$Brush = $null,
          [double]$Size = 0, [string]$Weight = $null, [switch]$Wrap, $Margin = $null)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    if ($Style)  { $t.Style = Res $Style }
    if ($Brush)  { $t.Foreground = Res $Brush }
    if ($Size)   { $t.FontSize = $Size }
    if ($Weight) { $t.FontWeight = $Weight }
    if ($Wrap)   { $t.TextWrapping = 'Wrap' }
    if ($Margin -ne $null) { $t.Margin = $Margin }
    $t
}

function New-Stack {
    param([string]$Orientation = 'Vertical', $Margin = $null, [string]$HAlign = $null, [string]$VAlign = $null)
    $s = New-Object System.Windows.Controls.StackPanel
    $s.Orientation = $Orientation
    if ($Margin -ne $null) { $s.Margin = $Margin }
    if ($HAlign) { $s.HorizontalAlignment = $HAlign }
    if ($VAlign) { $s.VerticalAlignment = $VAlign }
    $s
}

function New-Bd {
    param($Child = $null, [string]$Bg = $null, [string]$Border = $null, $Thickness = $null,
          $Padding = $null, $Margin = $null, [double]$Radius = 0)
    $b = New-Object System.Windows.Controls.Border
    if ($Child)   { $b.Child = $Child }
    if ($Bg)      { $b.Background = Res $Bg }
    if ($Border)  { $b.BorderBrush = Res $Border }
    if ($Thickness -ne $null) { $b.BorderThickness = $Thickness }
    if ($Padding -ne $null)   { $b.Padding = $Padding }
    if ($Margin -ne $null)    { $b.Margin = $Margin }
    if ($Radius)  { $b.CornerRadius = $Radius }
    $b
}

function New-Btn {
    param([string]$Text, [string]$Style = 'BtnGhost', $Tag = $null, [scriptblock]$OnClick = $null, $Margin = $null)
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Text
    $b.Style = Res $Style
    if ($Tag -ne $null)    { $b.Tag = $Tag }
    if ($Margin -ne $null) { $b.Margin = $Margin }
    if ($OnClick)          { $b.Add_Click($OnClick) }
    $b
}

$script:GlConv = New-Object System.Windows.GridLengthConverter
function New-Grid {
    param([string[]]$Cols = @(), [string[]]$Rows = @())
    $g = New-Object System.Windows.Controls.Grid
    foreach ($c in $Cols) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $script:GlConv.ConvertFromString($c)
        $g.ColumnDefinitions.Add($cd)
    }
    foreach ($r in $Rows) {
        $rd = New-Object System.Windows.Controls.RowDefinition
        $rd.Height = $script:GlConv.ConvertFromString($r)
        $g.RowDefinitions.Add($rd)
    }
    $g
}

function Add-Cell {
    param($Grid, $Child, [int]$Col = 0, [int]$Row = 0, [int]$ColSpan = 1)
    [System.Windows.Controls.Grid]::SetColumn($Child, $Col)
    [System.Windows.Controls.Grid]::SetRow($Child, $Row)
    if ($ColSpan -gt 1) { [System.Windows.Controls.Grid]::SetColumnSpan($Child, $ColSpan) }
    [void]$Grid.Children.Add($Child)
    $Child
}

function New-Scroll {
    param($Child)
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'
    $sv.HorizontalScrollBarVisibility = 'Disabled'
    $sv.Content = $Child
    $sv
}

# A key cap.  Tone: 'key' normal, 'mod' modifier, 'dev' joystick, 'bad' conflict.
function New-Cap {
    param([string]$Text, [string]$Tone = 'key')
    $t = New-TB $Text -Size 11.5
    $t.FontFamily = 'Consolas'
    $b = New-Bd $t -Thickness ([System.Windows.Thickness]::new(1)) `
                   -Padding ([System.Windows.Thickness]::new(8,3,8,3)) `
                   -Margin ([System.Windows.Thickness]::new(4,2,0,2)) -Radius 4
    switch ($Tone) {
        'mod' { $b.Background = Res 'Field';      $b.BorderBrush = Res 'Line';       $t.Foreground = Res 'Muted' }
        'dev' { $b.Background = 'Transparent';  $b.BorderBrush = Res 'LineSoft';   $t.Foreground = Res 'Dim' }
        'bad' { $b.Background = Res 'DangerWash'; $b.BorderBrush = Res 'Danger';     $t.Foreground = Res 'Danger' }
        default { $b.Background = Res 'CardHi';   $b.BorderBrush = Res 'Line';       $t.Foreground = Res 'Text' }
    }
    $b
}

function New-Note {
    param([string]$Text, [string]$Level = 'info')
    $brush = switch ($Level) { 'critical' { 'Danger' } 'perf' { 'Warn' } default { 'Info' } }
    $t = New-TB $Text -Size 12 -Wrap
    $t.Foreground = Res $brush
    $t.LineHeight = 17
    $bar = New-Object System.Windows.Shapes.Rectangle
    $bar.Width = 2; $bar.Fill = Res $brush; $bar.VerticalAlignment = 'Stretch'
    $g = New-Grid @('2','12','*')
    Add-Cell $g $bar 0 | Out-Null
    Add-Cell $g $t 2 | Out-Null
    New-Bd $g -Margin ([System.Windows.Thickness]::new(0,8,0,0))
}

# =============================================================================
#  SETTINGS ROWS
# =============================================================================
$script:Rows = @{}          # bdg key -> @{ Dot NoteHost Def Editor }
$script:OnChange = $null    # set once the status bar exists

function Get-SettingKind {
    param($Def, $Entry)
    if ($Def -and $Def.Choices) { return 'choice' }
    $v = $Entry.Value.Trim().ToUpper()
    if ($v -eq 'ON' -or $v -eq 'OFF')          { return 'bool' }
    if ($v -eq 'ENABLE' -or $v -eq 'DISABLE')  { return 'bool' }
    return 'text'
}

function Test-Numeric { param([string]$V) $V.Trim() -match '^-?\d+(\.\d+)?$' }

function Update-RowState {
    param([string]$Key)
    if (-not $script:Rows.ContainsKey($Key)) { return }
    $r = $script:Rows[$Key]
    $e = $script:Bdg[$Key]
    $changed = ($e.Value -ne $e.Original)
    $r.Dot.Visibility = $(if ($changed) { 'Visible' } else { 'Hidden' })
    $r.NoteHost.Children.Clear()
    $d = $r.Def
    if ($d -and $d.Rec -and ($e.Value.Trim() -ne $d.Rec)) {
        [void]$r.NoteHost.Children.Add((New-Note $d.RecMsg $d.Level))
    }
    if ($r.Numeric -and -not (Test-Numeric $e.Value)) {
        [void]$r.NoteHost.Children.Add((New-Note 'This setting expects a number. Saving is blocked until it is valid.' 'critical'))
    }
}

function Set-Setting {
    param([string]$Key, [string]$Value)
    Set-BdgValue $Key $Value
    Update-RowState $Key
    if ($script:OnChange) { & $script:OnChange }
}

function New-SettingRow {
    param($Def, [string]$Key = $null)
    if (-not $Key) { $Key = $Def.Key }
    if (-not $script:Bdg.ContainsKey($Key)) { return $null }
    $entry = $script:Bdg[$Key]

    $grid = New-Grid @('*','16','228','14','10')
    $grid.Margin = [System.Windows.Thickness]::new(0,13,0,13)

    # --- description column ---------------------------------------------
    $left = New-Stack
    $label = if ($Def -and $Def.Label) { $Def.Label } else { $Key }
    [void]$left.Children.Add((New-TB $label -Style 'RowLabel'))
    [void]$left.Children.Add((New-TB $Key -Style 'Mono' -Margin ([System.Windows.Thickness]::new(0,2,0,0))))
    $hint = if ($Def -and $Def.Hint) { $Def.Hint } else { $entry.Comment }
    if ($hint) { [void]$left.Children.Add((New-TB $hint -Style 'RowHint')) }
    # If a curated hint was written, still surface the game's own comment.
    if ($Def -and $Def.Hint -and $entry.Comment -and $Def.Hint -ne $entry.Comment) {
        $c = New-TB ('bdg.txt: ' + $entry.Comment) -Style 'Mono' -Wrap
        $c.Margin = [System.Windows.Thickness]::new(0,5,0,0)
        [void]$left.Children.Add($c)
    }
    $noteHost = New-Stack
    [void]$left.Children.Add($noteHost)
    Add-Cell $grid $left 0 | Out-Null

    # --- editor column ---------------------------------------------------
    $kind = Get-SettingKind $Def $entry
    $editorHost = New-Stack -VAlign 'Top'
    $numeric = $false

    switch ($kind) {
        'bool' {
            $on  = if ($entry.Value.Trim().ToUpper() -eq 'ENABLE' -or $entry.Value.Trim().ToUpper() -eq 'DISABLE') { 'ENABLE' } else { 'ON' }
            $off = if ($on -eq 'ENABLE') { 'DISABLE' } else { 'OFF' }
            $row = New-Stack -Orientation 'Horizontal'
            $sw = New-Object System.Windows.Controls.Primitives.ToggleButton
            $sw.Style = Res 'Switch'
            $sw.IsChecked = ($entry.Value.Trim().ToUpper() -eq $on)
            $cap = New-TB $(if ($sw.IsChecked) { $on } else { $off }) -Size 12 -Brush 'Muted' `
                          -Margin ([System.Windows.Thickness]::new(11,0,0,0))
            $cap.VerticalAlignment = 'Center'
            $sw.Tag = @{ Key = $Key; On = $on; Off = $off; Cap = $cap }
            $sw.Add_Click({
                param($s, $e)
                $t = $s.Tag
                $v = if ($s.IsChecked) { $t.On } else { $t.Off }
                $t.Cap.Text = $v
                Set-Setting $t.Key $v
            })
            [void]$row.Children.Add($sw)
            [void]$row.Children.Add($cap)
            [void]$editorHost.Children.Add($row)
        }
        'choice' {
            $cb = New-Object System.Windows.Controls.ComboBox
            $cb.Style = Res 'Combo'
            $map = @{}
            $sel = $null
            foreach ($c in $Def.Choices) {
                $parts  = $c -split '\|', 2
                $raw    = $parts[0]
                $disp   = if ($parts.Count -gt 1) { $parts[1] } else { $raw }
                $map[$disp] = $raw
                [void]$cb.Items.Add($disp)
                if ($raw -eq $entry.Value.Trim()) { $sel = $disp }
            }
            if (-not $sel) {
                # The file holds something outside the documented set - show it
                # rather than silently rewriting it.
                $extra = $entry.Value.Trim() + '   (current value, not a documented option)'
                $map[$extra] = $entry.Value.Trim()
                [void]$cb.Items.Insert(0, $extra)
                $sel = $extra
            }
            $cb.SelectedItem = $sel
            $cb.Tag = @{ Key = $Key; Map = $map }
            $cb.Add_SelectionChanged({
                param($s, $e)
                if ($s.SelectedItem -eq $null) { return }
                Set-Setting $s.Tag.Key $s.Tag.Map[[string]$s.SelectedItem]
            })
            [void]$editorHost.Children.Add($cb)
        }
        default {
            $numeric = Test-Numeric $entry.Original
            $tb = New-Object System.Windows.Controls.TextBox
            $tb.Style = Res 'FieldBox'
            $tb.Text = $entry.Value
            $tb.Tag = @{ Key = $Key }
            $tb.Add_TextChanged({ param($s, $e) Set-Setting $s.Tag.Key $s.Text })
            [void]$editorHost.Children.Add($tb)
            # colour swatch for the hex colour settings
            if ($Key -match 'COLOUR') {
                $sw = New-Object System.Windows.Shapes.Rectangle
                $sw.Height = 6; $sw.RadiusX = 3; $sw.RadiusY = 3
                $sw.Margin = [System.Windows.Thickness]::new(0,6,0,0)
                $sw.Fill = Res 'Line'
                $tb.Tag['Swatch'] = $sw
                [void]$editorHost.Children.Add($sw)
                $tb.Add_TextChanged({
                    param($s, $e)
                    $hex = ($s.Text.Trim() -replace '[^0-9A-Fa-f]','')
                    if ($hex.Length -ge 8) { $hex = $hex.Substring($hex.Length - 6) }
                    if ($hex.Length -eq 6) {
                        try { $s.Tag.Swatch.Fill = New-Object System.Windows.Media.SolidColorBrush (
                            [System.Windows.Media.ColorConverter]::ConvertFromString('#' + $hex)) } catch { }
                    }
                })
                $hex0 = ($entry.Value.Trim() -replace '[^0-9A-Fa-f]','')
                if ($hex0.Length -ge 8) { $hex0 = $hex0.Substring($hex0.Length - 6) }
                if ($hex0.Length -eq 6) {
                    try { $sw.Fill = New-Object System.Windows.Media.SolidColorBrush (
                        [System.Windows.Media.ColorConverter]::ConvertFromString('#' + $hex0)) } catch { }
                }
            }
        }
    }
    Add-Cell $grid $editorHost 2 | Out-Null

    # --- changed marker ---------------------------------------------------
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 7; $dot.Height = 7; $dot.Fill = Res 'Accent'
    $dot.VerticalAlignment = 'Top'; $dot.Margin = [System.Windows.Thickness]::new(0,9,0,0)
    $dot.ToolTip = 'Changed but not yet saved'
    $dot.Visibility = 'Hidden'
    Add-Cell $grid $dot 4 | Out-Null

    $script:Rows[$Key] = @{ Dot = $dot; NoteHost = $noteHost; Def = $Def; Numeric = $numeric; Grid = $grid }
    Update-RowState $Key

    New-Bd $grid -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))
}

# =============================================================================
#  KEY BINDINGS
# =============================================================================
$script:KeyUi      = @{}    # action -> @{ Row Chips Dot Conflict Cat }
$script:KeyGroups  = @()    # @{ Name Header Actions }
$script:Conflicts  = @{}    # chord -> @(actions)
$script:KeyFilter  = ''
$script:KeyMode    = 'All'
$script:ConflictBar = $null
$script:KeyCountText = $null

function Split-Chord {
    param([string]$Chord)
    $p = $Chord -split '\+'
    if ($p.Count -ge 2) { return @{ Mod = [int]$p[0]; Key = [int]$p[1] } }
    @{ Mod = 0; Key = [int]$p[0] }
}

function Format-Chord {
    param([string]$Chord)
    $c = Split-Chord $Chord
    $parts = @()
    if ($c.Mod -gt 0) { $parts += (Get-DikCap $c.Mod) }
    $parts += (Get-DikCap $c.Key)
    ,$parts
}

function Get-ChordSearchText {
    param($Entry)
    $s = @()
    foreach ($ch in $Entry.Kb) { $s += ((Format-Chord $ch) -join ' ') }
    # Device codes go in as BOTH the decoded label and the raw number, so
    # "joy 1", "hat", "button 8" and "267" all find the same row. Searching
    # only the action name meant a stick binding was unfindable by what it
    # actually says on screen.
    foreach ($d in $Entry.Dev) { $s += (Format-DevCode $d); $s += $d }
    ($s -join ' ')
}

function Update-Conflicts {
    $script:Conflicts = @{}
    foreach ($a in $script:KeyOrder) {
        foreach ($ch in $script:Keys[$a].Kb) {
            if (-not $script:Conflicts.ContainsKey($ch)) { $script:Conflicts[$ch] = @() }
            $script:Conflicts[$ch] += $a
        }
    }
    $n = 0
    foreach ($ch in $script:Conflicts.Keys) { if ($script:Conflicts[$ch].Count -gt 1) { $n++ } }
    $n
}

function Get-ConflictPartners {
    param([string]$Action)
    $out = @()
    foreach ($ch in $script:Keys[$Action].Kb) {
        if ($script:Conflicts.ContainsKey($ch) -and $script:Conflicts[$ch].Count -gt 1) {
            $out += ($script:Conflicts[$ch] | Where-Object { $_ -ne $Action })
        }
    }
    ,(@($out | Select-Object -Unique))
}

function Update-KeyRow {
    param([string]$Action)
    if (-not $script:KeyUi.ContainsKey($Action)) { return }
    $ui = $script:KeyUi[$Action]
    $e  = $script:Keys[$Action]
    $partners = Get-ConflictPartners $Action
    $bad = ($partners.Count -gt 0)

    $ui.Chips.Children.Clear()
    if ($e.Kb.Count -eq 0 -and $e.Dev.Count -eq 0) {
        $t = New-TB 'Not assigned' -Size 12 -Brush 'Dim'
        $t.FontStyle = 'Italic'; $t.VerticalAlignment = 'Center'
        [void]$ui.Chips.Children.Add($t)
    } else {
        $first = $true
        foreach ($ch in $e.Kb) {
            if (-not $first) {
                $orT = New-TB 'or' -Size 11 -Brush 'Dim' -Margin ([System.Windows.Thickness]::new(8,0,2,0))
                $orT.VerticalAlignment = 'Center'
                [void]$ui.Chips.Children.Add($orT)
            }
            $c = Split-Chord $ch
            if ($c.Mod -gt 0) { [void]$ui.Chips.Children.Add((New-Cap (Get-DikCap $c.Mod) 'mod')) }
            [void]$ui.Chips.Children.Add((New-Cap (Get-DikCap $c.Key) $(if ($bad) { 'bad' } else { 'key' })))
            $first = $false
        }
        foreach ($d in $e.Dev) {
            $cap = New-Cap (Format-DevCode $d) 'dev'
            $cap.ToolTip = "Device code $d. Click the row to reassign it."
            [void]$ui.Chips.Children.Add($cap)
        }
    }

    if ($bad) {
        $ui.Conflict.Text = 'Shared with ' + (($partners | Select-Object -First 3) -join ', ') +
                            $(if ($partners.Count -gt 3) { ' and ' + ($partners.Count - 3) + ' more' } else { '' })
        $ui.Conflict.Visibility = 'Visible'
        $ui.Row.BorderBrush = Res 'Danger'
        $ui.Row.BorderThickness = [System.Windows.Thickness]::new(2,0,0,1)
    } else {
        $ui.Conflict.Visibility = 'Collapsed'
        $ui.Row.BorderBrush = Res 'LineSoft'
        $ui.Row.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
    }
    $ui.Dot.Visibility = $(if (Test-KeyChanged $e) { 'Visible' } else { 'Hidden' })
}

function Refresh-AllKeyRows {
    $n = Update-Conflicts
    foreach ($a in $script:KeyOrder) { Update-KeyRow $a }
    if ($script:ConflictBar) {
        if ($n -gt 0) {
            $script:ConflictBar.Tag.Text = "$n key combination$(if ($n -ne 1) { 's' } else { '' }) assigned to more than one action"
            $script:ConflictBar.Visibility = 'Visible'
        } else {
            $script:ConflictBar.Visibility = 'Collapsed'
        }
    }
    if ($script:OnChange) { & $script:OnChange }
}

function Set-Binding {
    param([string]$Action, [string]$Chord)
    $e = $script:Keys[$Action]
    if ($e.Kb.Count -eq 0) { $e.Kb = @($Chord) }
    else { $k = @($e.Kb); $k[0] = $Chord; $e.Kb = $k }
    Refresh-AllKeyRows
    Apply-KeyFilter
}

function Set-DevBinding {
    param([string]$Action, [string]$Code)
    $e = $script:Keys[$Action]
    # Replace the FIRST device code and leave any others alone, mirroring how
    # the keyboard side behaves. Actions bound on four sticks keep the other
    # three.
    if ($e.Dev.Count -eq 0) { $e.Dev = @($Code) }
    else { $d = @($e.Dev); $d[0] = $Code; $e.Dev = $d }
    Refresh-AllKeyRows
    Apply-KeyFilter
}

function Clear-DevBinding {
    param([string]$Action)
    $script:Keys[$Action].Dev = @()
    Refresh-AllKeyRows
    Apply-KeyFilter
}

function Clear-Binding {
    param([string]$Action)
    $script:Keys[$Action].Kb = @()
    Refresh-AllKeyRows
    Apply-KeyFilter
}

function Reset-Binding {
    param([string]$Action)
    if (-not $script:Defaults.ContainsKey($Action)) { return }
    $script:Keys[$Action].Kb = @($script:Defaults[$Action])
    Refresh-AllKeyRows
    Apply-KeyFilter
}

# -----------------------------------------------------------------------------
#  Press-a-key capture
# -----------------------------------------------------------------------------
$script:Capture = @{ Active = $false; Action = $null; Chord = $null; Dev = $null
                     Caps = $null; Assign = $null; Hint = $null; Timer = $null; Base = $null }

# Renders whatever has just been captured into the preview box and says who
# else already owns it. One function for both keyboard and joystick so the two
# can never present differently.
function Show-CapturePreview {
    param([string]$Text, $Caps)
    $script:Capture.Caps.Children.Clear()
    foreach ($c in $Caps) { [void]$script:Capture.Caps.Children.Add($c) }
    $script:Capture.Assign.IsEnabled = $true
    $owner = @()
    foreach ($a in $script:KeyOrder) {
        if ($a -eq $script:Capture.Action) { continue }
        $e2 = $script:Keys[$a]
        if ((@($e2.Kb) + @($e2.Dev)) -contains $Text) { $owner += (ConvertTo-KeyLabel $a) }
    }
    if ($owner.Count -gt 0) {
        $script:Capture.Hint.Text = 'Already used by ' + (($owner | Select-Object -First 2) -join ', ') +
            $(if ($owner.Count -gt 2) { ' and ' + ($owner.Count - 2) + ' more' } else { '' })
    } else {
        $script:Capture.Hint.Text = 'Press Assign to use this'
    }
}

function Stop-JoyPoll {
    if ($script:Capture.Timer) { $script:Capture.Timer.Stop(); $script:Capture.Timer = $null }
}

# Polls the sticks while the capture overlay is open. Only a fresh press
# counts: the state at the moment the overlay opened is the baseline, so a
# button already held down does not immediately assign itself.
function Start-JoyPoll {
    Stop-JoyPoll
    if (-not (Initialize-Joystick)) { return }
    $base = @{}
    foreach ($st in (Get-JoystickState)) { $base[$st.Device] = $st }
    if ($base.Count -eq 0) { return }
    $script:Capture.Base = $base

    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(60)
    $t.Add_Tick({
        if (-not $script:Capture.Active) { Stop-JoyPoll; return }
        foreach ($st in (Get-JoystickState)) {
            $b0 = 0; $p0 = 65535
            if ($script:Capture.Base.ContainsKey($st.Device)) {
                $b0 = $script:Capture.Base[$st.Device].Buttons
                $p0 = $script:Capture.Base[$st.Device].Pov
            }
            # buttons: bit set now that was clear at baseline
            $fresh = $st.Buttons -band (-bnot $b0)
            if ($fresh -ne 0) {
                for ($i = 0; $i -lt 32; $i++) {
                    if ($fresh -band (1 -shl $i)) {
                        if ($st.Device -ge $script:JoyMaxDev) { break }
                        $code = ConvertTo-JoyButtonCode $st.Device $i
                        $script:Capture.Dev = "$code"; $script:Capture.Chord = $null
                        Show-CapturePreview "$code" @((New-Cap (Format-DevCode "$code") 'dev'))
                        return
                    }
                }
            }
            # POV: 0 = up, increasing clockwise in hundredths of a degree,
            # 65535 (or -1) = centred. Only the primary hat is reachable here.
            $pov = $st.Pov
            if ($pov -ge 0 -and $pov -le 31500 -and $pov -ne $p0) {
                $dir = [int][math]::Round($pov / 4500.0) % 8
                $code = ConvertTo-PovCode 0 $dir
                $script:Capture.Dev = "$code"; $script:Capture.Chord = $null
                Show-CapturePreview "$code" @((New-Cap (Format-DevCode "$code") 'dev'))
                return
            }
            # re-baseline released buttons so the same button can be pressed twice
            if ($script:Capture.Base.ContainsKey($st.Device)) {
                $script:Capture.Base[$st.Device] = @{ Device = $st.Device
                    Buttons = ($script:Capture.Base[$st.Device].Buttons -band $st.Buttons)
                    Pov = $st.Pov }
            }
        }
    })
    $t.Start()
    $script:Capture.Timer = $t
}

function Get-PressedModifier {
    $kb = [System.Windows.Input.Keyboard]
    foreach ($code in $script:ModOrder) {
        $wpf = switch ($code) {
            29  { 'LeftCtrl' }  42 { 'LeftShift' }  56 { 'LeftAlt' }
            157 { 'RightCtrl' } 54 { 'RightShift' } 184 { 'RightAlt' }
        }
        if ($kb::IsKeyDown([System.Windows.Input.Key]$wpf)) { return $code }
    }
    0
}

function Show-Overlay { param($Content) $OverlayHost.Children.Clear(); [void]$OverlayHost.Children.Add($Content); $Overlay.Visibility = 'Visible' }
function Hide-Overlay {
    $Overlay.Visibility = 'Collapsed'
    $OverlayHost.Children.Clear()
    $script:Capture.Active = $false
    Stop-JoyPoll
}

function Show-Capture {
    param([string]$Action)
    $e = $script:Keys[$Action]
    $panel = New-Stack

    [void]$panel.Children.Add((New-TB 'ASSIGN A KEY OR JOYSTICK BUTTON' -Style 'Eyebrow'))
    [void]$panel.Children.Add((New-TB (ConvertTo-KeyLabel $Action) -Style 'H1' -Margin ([System.Windows.Thickness]::new(0,6,0,0))))
    [void]$panel.Children.Add((New-TB $Action -Style 'Mono' -Margin ([System.Windows.Thickness]::new(0,3,0,0))))

    $caps = New-Object System.Windows.Controls.WrapPanel
    $caps.Margin = [System.Windows.Thickness]::new(0,4,0,0)
    $caps.HorizontalAlignment = 'Center'
    $joys = Get-JoystickState
    $prompt = New-TB $(if ($joys.Count) { 'Press a key, or a button or hat on your joystick' }
                       else { 'Press the key combination you want' }) -Size 13 -Brush 'Muted'
    $prompt.HorizontalAlignment = 'Center'
    $inner = New-Stack
    [void]$inner.Children.Add($prompt)
    [void]$inner.Children.Add($caps)
    $box = New-Bd $inner -Bg 'Field' -Border 'AccentSoft' -Thickness ([System.Windows.Thickness]::new(1)) `
                         -Padding ([System.Windows.Thickness]::new(20,22,20,22)) `
                         -Margin ([System.Windows.Thickness]::new(0,20,0,0)) -Radius 6
    [void]$panel.Children.Add($box)

    $hintText = 'One modifier plus one key. Press Escape to cancel without changing anything.'
    if ($joys.Count) {
        $hintText = 'One modifier plus one key, or a joystick button or hat. ' +
                    $joys.Count + ' device' + $(if ($joys.Count -ne 1) { 's' } else { '' }) +
                    ' detected. Press Escape to cancel without changing anything.'
    }
    $hint = New-TB $hintText -Size 11.5 -Brush 'Dim' -Wrap
    $hint.Margin = [System.Windows.Thickness]::new(0,10,0,0)
    $hint.TextAlignment = 'Center'
    [void]$panel.Children.Add($hint)

    if ($e.Kb.Count -gt 1) {
        [void]$panel.Children.Add((New-Note ('This action has ' + $e.Kb.Count +
            ' keyboard combinations. Assigning here replaces the first one; the rest are left alone.') 'info'))
    }
    if ($e.Dev.Count -gt 1) {
        [void]$panel.Children.Add((New-Note ('This action has ' + $e.Dev.Count +
            ' device assignments (' + (($e.Dev | ForEach-Object { Format-DevCode $_ }) -join ', ') +
            '). Assigning a joystick input here replaces the first; the rest are left alone.') 'info'))
    }
    if (-not $joys.Count) {
        [void]$panel.Children.Add((New-Note ('No joystick detected, so only keyboard assignment is available. ' +
            'Any joystick codes already on this action are preserved exactly as found.') 'info'))
    }

    $bar = New-Stack -Orientation 'Horizontal' -HAlign 'Right' -Margin ([System.Windows.Thickness]::new(0,22,0,0))
    $btnReset = New-Btn 'Reset to default' 'BtnGhost' $Action { param($s,$e2) Reset-Binding $s.Tag; Hide-Overlay }
    $btnReset.IsEnabled = $script:Defaults.ContainsKey($Action)
    $btnClear = New-Btn 'Clear binding' 'BtnGhost' $Action {
        param($s,$e2)
        Clear-Binding $s.Tag
        Clear-DevBinding $s.Tag
        Hide-Overlay
    }
    $btnClear.Margin = [System.Windows.Thickness]::new(8,0,0,0)
    $btnCancel = New-Btn 'Cancel' 'BtnGhost' $null { Hide-Overlay }
    $btnCancel.Margin = [System.Windows.Thickness]::new(8,0,0,0)
    $btnAssign = New-Btn 'Assign' 'BtnPrimary' $Action {
        param($s,$e2)
        if ($script:Capture.Dev)        { Set-DevBinding $s.Tag $script:Capture.Dev }
        elseif ($script:Capture.Chord)  { Set-Binding    $s.Tag $script:Capture.Chord }
        Hide-Overlay
    }
    $btnAssign.Margin = [System.Windows.Thickness]::new(8,0,0,0)
    $btnAssign.IsEnabled = $false
    foreach ($b in @($btnReset, $btnClear, $btnCancel, $btnAssign)) { [void]$bar.Children.Add($b) }
    [void]$panel.Children.Add($bar)

    $script:Capture = @{ Active = $true; Action = $Action; Chord = $null; Dev = $null
                         Caps = $caps; Assign = $btnAssign; Hint = $prompt; Timer = $null; Base = $null }
    Show-Overlay $panel
    $Win.Focus() | Out-Null
    Start-JoyPoll
}

$Win.Add_PreviewKeyDown({
    param($s, $e)
    if (-not $script:Capture.Active) { return }
    $e.Handled = $true

    $k = $e.Key
    if ($k -eq [System.Windows.Input.Key]::System) { $k = $e.SystemKey }
    $name = $k.ToString()

    if ($name -eq 'Escape') { Hide-Overlay; return }
    # A modifier on its own is not a binding - wait for the real key.
    if ($name -match '^(Left|Right)(Ctrl|Shift|Alt)$' -or $name -eq 'LWin' -or $name -eq 'RWin') { return }
    if (-not $script:WpfToDik.ContainsKey($name)) {
        $script:Capture.Hint.Text = "That key ($name) has no DirectInput code the game understands"
        return
    }

    $dik = $script:WpfToDik[$name]
    $mod = Get-PressedModifier
    if ($mod -eq $dik) { $mod = 0 }
    $chord = if ($mod -gt 0) { "$mod+$dik" } else { "$dik" }
    $script:Capture.Chord = $chord
    $script:Capture.Dev = $null

    $script:Capture.Caps.Children.Clear()
    $c = Split-Chord $chord
    if ($c.Mod -gt 0) { [void]$script:Capture.Caps.Children.Add((New-Cap (Get-DikCap $c.Mod) 'mod')) }
    [void]$script:Capture.Caps.Children.Add((New-Cap (Get-DikCap $c.Key) 'key'))

    $owner = @()
    if ($script:Conflicts.ContainsKey($chord)) {
        $owner = @($script:Conflicts[$chord] | Where-Object { $_ -ne $script:Capture.Action })
    }
    if ($owner.Count -gt 0) {
        $script:Capture.Hint.Text = 'Already used by ' + (($owner | Select-Object -First 2) -join ', ')
        $script:Capture.Hint.Foreground = Res 'Danger'
    } else {
        $script:Capture.Hint.Text = 'Ready to assign'
        $script:Capture.Hint.Foreground = Res 'Good'
    }
    $script:Capture.Assign.IsEnabled = $true
})

# -----------------------------------------------------------------------------
#  Filtering
# -----------------------------------------------------------------------------
function Apply-KeyFilter {
    $f = $script:KeyFilter.Trim()
    $shown = 0
    foreach ($g in $script:KeyGroups) {
        $visibleInGroup = 0
        foreach ($a in $g.Actions) {
            $e  = $script:Keys[$a]
            $ui = $script:KeyUi[$a]
            $ok = $true
            switch ($script:KeyMode) {
                # A stick-only binding is still a binding. Counting only the
                # keyboard half listed 17 joystick-bound actions as unassigned.
                'Assigned'   { $ok = (($e.Kb.Count + $e.Dev.Count) -gt 0) }
                'Unassigned' { $ok = (($e.Kb.Count + $e.Dev.Count) -eq 0) }
                'Conflicts'  { $ok = ((Get-ConflictPartners $a).Count -gt 0) }
                'Changed'    { $ok = (Test-KeyChanged $e) }
            }
            if ($ok -and $f) {
                $hay = $a + ' ' + (ConvertTo-KeyLabel $a) + ' ' + (Get-ChordSearchText $e) + ' ' + $g.Name
                $ok = $hay -like ('*' + $f + '*')
            }
            $ui.Row.Visibility = $(if ($ok) { 'Visible' } else { 'Collapsed' })
            if ($ok) { $visibleInGroup++; $shown++ }
        }
        $g.Header.Visibility = $(if ($visibleInGroup -gt 0) { 'Visible' } else { 'Collapsed' })
    }
    if ($script:KeyCountText) {
        $script:KeyCountText.Text = "$shown of $($script:KeyOrder.Count) actions"
    }
}

function Build-KeysPage {
    $root = New-Grid @('*') @('Auto','Auto','*')

    # toolbar
    $tb = New-Grid @('*','12','200','12','Auto') @('Auto','Auto')
    $tb.Margin = [System.Windows.Thickness]::new(34,20,34,14)
    $search = New-Object System.Windows.Controls.TextBox
    $search.Style = Res 'SearchBox'
    $search.ToolTip = 'Search by action name, by the plain-English label, or by the key it is assigned to (try "Ctrl" or "Num 7")'
    $search.Add_TextChanged({ param($s,$e) $script:KeyFilter = $s.Text; Apply-KeyFilter })
    Add-Cell $tb $search 0 | Out-Null

    $mode = New-Object System.Windows.Controls.ComboBox
    $mode.Style = Res 'Combo'; $mode.Height = 34
    foreach ($m in @('All actions','Assigned only','Unassigned only','Conflicts only','Changed only')) { [void]$mode.Items.Add($m) }
    $mode.SelectedIndex = 0
    $mode.Add_SelectionChanged({
        param($s,$e)
        $script:KeyMode = switch ([string]$s.SelectedItem) {
            'Assigned only'   { 'Assigned' }   'Unassigned only' { 'Unassigned' }
            'Conflicts only'  { 'Conflicts' }  'Changed only'    { 'Changed' }
            default { 'All' }
        }
        Apply-KeyFilter
    })
    Add-Cell $tb $mode 2 | Out-Null

    $resetAll = New-Btn 'Restore all defaults' 'BtnGhost' $null {
        foreach ($a in $script:KeyOrder) { if ($script:Defaults.ContainsKey($a)) { $script:Keys[$a].Kb = @($script:Defaults[$a]) } }
        Refresh-AllKeyRows; Apply-KeyFilter
    }
    $resetAll.Height = 34
    $resetAll.ToolTip = 'Copies every binding from KEYBOARD\default.txt. Still not written until you press Save.'
    Add-Cell $tb $resetAll 4 | Out-Null
    $script:KeyCountText = New-TB '' -Size 12 -Brush 'Dim' -Margin ([System.Windows.Thickness]::new(2,8,0,0))
    Add-Cell $tb $script:KeyCountText 0 1 | Out-Null
    Add-Cell $root $tb 0 0 | Out-Null

    # conflict banner
    $cbText = New-TB '' -Size 12.5 -Brush 'Danger'
    $cbText.VerticalAlignment = 'Center'
    $cbInner = New-Stack -Orientation 'Horizontal'
    $dotc = New-Object System.Windows.Shapes.Ellipse
    $dotc.Width = 7; $dotc.Height = 7; $dotc.Fill = Res 'Danger'; $dotc.VerticalAlignment = 'Center'
    $dotc.Margin = [System.Windows.Thickness]::new(0,0,10,0)
    [void]$cbInner.Children.Add($dotc); [void]$cbInner.Children.Add($cbText)
    $cb = New-Bd $cbInner -Bg 'DangerWash' -Border 'Danger' -Thickness ([System.Windows.Thickness]::new(1)) `
                          -Padding ([System.Windows.Thickness]::new(14,9,14,9)) `
                          -Margin ([System.Windows.Thickness]::new(34,0,34,14)) -Radius 5
    $cb.Tag = $cbText
    $cb.Visibility = 'Collapsed'
    $script:ConflictBar = $cb
    Add-Cell $root $cb 0 1 | Out-Null

    # list
    $list = New-Stack -Margin ([System.Windows.Thickness]::new(34,0,26,40))
    $script:KeyGroups = @()
    $grouped = @{}
    foreach ($a in $script:KeyOrder) {
        $cat = Get-KeyCategory $a
        if (-not $grouped.ContainsKey($cat)) { $grouped[$cat] = @() }
        $grouped[$cat] += $a
    }
    foreach ($cdef in $script:KeyCategories) {
        $cat = $cdef.N
        if (-not $grouped.ContainsKey($cat)) { continue }

        $hdrStack = New-Stack
        [void]$hdrStack.Children.Add((New-TB $cat.ToUpper() -Style 'SectionTitle'))
        [void]$hdrStack.Children.Add((New-TB ("$($grouped[$cat].Count) actions") -Size 11.5 -Brush 'Dim' `
                                       -Margin ([System.Windows.Thickness]::new(0,3,0,0))))
        $hdr = New-Bd $hdrStack -Margin ([System.Windows.Thickness]::new(0,26,0,8)) `
                                -Padding ([System.Windows.Thickness]::new(0,0,0,10)) `
                                -Border 'Line' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))
        [void]$list.Children.Add($hdr)
        $script:KeyGroups += @{ Name = $cat; Header = $hdr; Actions = @($grouped[$cat] | Sort-Object) }

        foreach ($a in ($grouped[$cat] | Sort-Object)) {
            $g = New-Grid @('*','16','Auto','10','10')
            $g.Margin = [System.Windows.Thickness]::new(10,0,0,0)

            $left = New-Stack -VAlign 'Center' -Margin ([System.Windows.Thickness]::new(0,11,0,11))
            [void]$left.Children.Add((New-TB (ConvertTo-KeyLabel $a) -Style 'RowLabel'))
            [void]$left.Children.Add((New-TB $a -Style 'Mono' -Margin ([System.Windows.Thickness]::new(0,2,0,0))))
            $conf = New-TB '' -Size 11.5 -Brush 'Danger' -Wrap -Margin ([System.Windows.Thickness]::new(0,4,0,0))
            $conf.Visibility = 'Collapsed'
            [void]$left.Children.Add($conf)
            Add-Cell $g $left 0 | Out-Null

            $chips = New-Object System.Windows.Controls.WrapPanel
            $chips.HorizontalAlignment = 'Right'
            $btn = New-Btn '' 'ChipButton' $a { param($s,$e2) Show-Capture $s.Tag }
            $btn.Content = $chips
            $btn.VerticalAlignment = 'Center'
            $btn.ToolTip = 'Click to assign a new key'
            Add-Cell $g $btn 2 | Out-Null

            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 7; $dot.Height = 7; $dot.Fill = Res 'Accent'; $dot.VerticalAlignment = 'Center'
            $dot.ToolTip = 'Changed but not yet saved'; $dot.Visibility = 'Hidden'
            Add-Cell $g $dot 4 | Out-Null

            $row = New-Bd $g -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))
            [void]$list.Children.Add($row)
            $script:KeyUi[$a] = @{ Row = $row; Chips = $chips; Dot = $dot; Conflict = $conf }
        }
    }

    $sv = New-Scroll $list
    Add-Cell $root $sv 0 2 | Out-Null

    Refresh-AllKeyRows
    Apply-KeyFilter
    $root
}

# =============================================================================
#  CURATED SETTINGS PAGES
# =============================================================================
function New-SectionHeader {
    param([string]$Title, [string]$Note)
    $st = New-Stack
    [void]$st.Children.Add((New-TB $Title.ToUpper() -Style 'SectionTitle'))
    if ($Note) {
        $n = New-TB $Note -Size 12 -Brush 'Muted' -Wrap -Margin ([System.Windows.Thickness]::new(0,5,0,0))
        $n.MaxWidth = 720; $n.LineHeight = 17
        [void]$st.Children.Add($n)
    }
    New-Bd $st -Margin ([System.Windows.Thickness]::new(0,30,0,6)) `
               -Padding ([System.Windows.Thickness]::new(0,0,0,12)) `
               -Border 'Line' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))
}

function New-WxRow {
    param([string]$Key, [string]$Label, [string]$Hint, [string[]]$Choices)
    if (-not $script:Wx.ContainsKey($Key)) { return $null }
    $e = $script:Wx[$Key]
    $grid = New-Grid @('*','16','228','14','10')
    $grid.Margin = [System.Windows.Thickness]::new(0,13,0,13)

    $left = New-Stack
    [void]$left.Children.Add((New-TB $Label -Style 'RowLabel'))
    [void]$left.Children.Add((New-TB ('Weather.cfg  ' + $Key) -Style 'Mono' -Margin ([System.Windows.Thickness]::new(0,2,0,0))))
    if ($Hint) { [void]$left.Children.Add((New-TB $Hint -Style 'RowHint')) }
    Add-Cell $grid $left 0 | Out-Null

    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 7; $dot.Height = 7; $dot.Fill = Res 'Accent'
    $dot.VerticalAlignment = 'Top'; $dot.Margin = [System.Windows.Thickness]::new(0,9,0,0)
    $dot.Visibility = $(if ($e.Value -ne $e.Original) { 'Visible' } else { 'Hidden' })
    Add-Cell $grid $dot 4 | Out-Null

    $cb = New-Object System.Windows.Controls.ComboBox
    $cb.Style = Res 'Combo'
    $map = @{}; $sel = $null
    foreach ($c in $Choices) {
        $p = $c -split '\|', 2
        $map[$p[1]] = $p[0]
        [void]$cb.Items.Add($p[1])
        if ($p[0] -eq $e.Value.Trim()) { $sel = $p[1] }
    }
    if ($sel) { $cb.SelectedItem = $sel }
    $cb.Tag = @{ Key = $Key; Map = $map; Dot = $dot }
    $cb.Add_SelectionChanged({
        param($s, $e2)
        if ($s.SelectedItem -eq $null) { return }
        $t = $s.Tag
        $script:Wx[$t.Key].Value = $t.Map[[string]$s.SelectedItem]
        $t.Dot.Visibility = $(if ($script:Wx[$t.Key].Value -ne $script:Wx[$t.Key].Original) { 'Visible' } else { 'Hidden' })
        if ($script:OnChange) { & $script:OnChange }
    })
    Add-Cell $grid $cb 2 | Out-Null
    New-Bd $grid -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))
}

$script:WeatherChoices = @('0|0  -  Low', '1|1  -  Medium', '2|2  -  High')

function Build-SettingsPage {
    param([string]$Name, $Def)
    $list = New-Stack -Margin ([System.Windows.Thickness]::new(34,0,34,50))
    foreach ($sec in $Def.Sections) {
        [void]$list.Children.Add((New-SectionHeader $sec.T $sec.N))
        if ($sec.T -eq 'Weather.cfg') {
            foreach ($w in @(
                @('WaterDetail','Water detail','The GFX screen calls this Water Detail.'),
                @('SkyDetail','Weather detail','The GFX screen calls this Weather Detail, not Sky Detail.'),
                @('HorizonDistance','Horizon distance','Not exposed anywhere in the game. Higher pushes the visible horizon further out.'))) {
                $r = New-WxRow $w[0] $w[1] $w[2] $script:WeatherChoices
                if ($r) { [void]$list.Children.Add($r) }
            }
            continue
        }
        foreach ($item in $sec.I) {
            $r = New-SettingRow $item
            if ($r) { [void]$list.Children.Add($r) }
        }
    }
    New-Scroll $list
}

# =============================================================================
#  GFX SCREEN  (SAVEGAME\settings.cfg)
# =============================================================================
function New-CfgRow {
    param([string]$Label, [string]$Where, [string]$Hint, $Editor, $Dot)
    $grid = New-Grid @('*','16','228','14','10')
    $grid.Margin = [System.Windows.Thickness]::new(0,13,0,13)
    $left = New-Stack
    [void]$left.Children.Add((New-TB $Label -Style 'RowLabel'))
    [void]$left.Children.Add((New-TB $Where -Style 'Mono' -Margin ([System.Windows.Thickness]::new(0,2,0,0))))
    if ($Hint) { [void]$left.Children.Add((New-TB $Hint -Style 'RowHint')) }
    Add-Cell $grid $left 0 | Out-Null
    Add-Cell $grid $Editor 2 | Out-Null
    if ($Dot) { Add-Cell $grid $Dot 4 | Out-Null }
    New-Bd $grid -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))
}

function New-CfgDot {
    $d = New-Object System.Windows.Shapes.Ellipse
    $d.Width = 7; $d.Height = 7; $d.Fill = Res 'Accent'
    $d.VerticalAlignment = 'Top'; $d.Margin = [System.Windows.Thickness]::new(0,9,0,0)
    $d.Visibility = 'Hidden'
    $d
}

function New-CfgCombo {
    param([int]$Offset, [string[]]$Choices, $Dot)
    $cb = New-Object System.Windows.Controls.ComboBox
    $cb.Style = Res 'Combo'
    $map = @{}; $sel = $null
    foreach ($c in $Choices) {
        $p = $c -split '\|', 2
        $map[$p[1]] = [int]$p[0]
        [void]$cb.Items.Add($p[1])
        if ([int]$p[0] -eq $script:CfgBytes[$Offset]) { $sel = $p[1] }
    }
    if (-not $sel) {
        $extra = 'Raw value ' + $script:CfgBytes[$Offset] + '   (not a known option)'
        $map[$extra] = [int]$script:CfgBytes[$Offset]
        [void]$cb.Items.Insert(0, $extra); $sel = $extra
    }
    $cb.SelectedItem = $sel
    $cb.Tag = @{ Off = $Offset; Map = $map; Dot = $Dot }
    $cb.Add_SelectionChanged({
        param($s, $e)
        if ($s.SelectedItem -eq $null) { return }
        $t = $s.Tag
        $script:CfgBytes[$t.Off] = [byte]$t.Map[[string]$s.SelectedItem]
        $t.Dot.Visibility = $(if ($script:CfgBytes[$t.Off] -ne $script:CfgOrig[$t.Off]) { 'Visible' } else { 'Hidden' })
        if ($script:OnChange) { & $script:OnChange }
    })
    $cb
}

function New-CfgSwitch {
    param([int]$Offset, [int]$Mask, $Dot)
    $row = New-Stack -Orientation 'Horizontal'
    $sw = New-Object System.Windows.Controls.Primitives.ToggleButton
    $sw.Style = Res 'Switch'
    $sw.IsChecked = $(if ($Mask) { (Get-CfgBit $Offset $Mask) } else { $script:CfgBytes[$Offset] -ne 0 })
    $cap = New-TB $(if ($sw.IsChecked) { 'On' } else { 'Off' }) -Size 12 -Brush 'Muted' -Margin ([System.Windows.Thickness]::new(11,0,0,0))
    $cap.VerticalAlignment = 'Center'
    $sw.Tag = @{ Off = $Offset; Mask = $Mask; Cap = $cap; Dot = $Dot }
    $sw.Add_Click({
        param($s, $e)
        $t = $s.Tag
        if ($t.Mask) { Set-CfgBit $t.Off $t.Mask ([bool]$s.IsChecked) }
        else { $script:CfgBytes[$t.Off] = [byte]$(if ($s.IsChecked) { 1 } else { 0 }) }
        $t.Cap.Text = $(if ($s.IsChecked) { 'On' } else { 'Off' })
        $t.Dot.Visibility = $(if ($script:CfgBytes[$t.Off] -ne $script:CfgOrig[$t.Off]) { 'Visible' } else { 'Hidden' })
        if ($script:OnChange) { & $script:OnChange }
    })
    [void]$row.Children.Add($sw); [void]$row.Children.Add($cap)
    $row
}

function Build-GfxPage {
    $list = New-Stack -Margin ([System.Windows.Thickness]::new(34,0,34,50))
    if (-not $script:CfgBytes) {
        [void]$list.Children.Add((New-Note 'SAVEGAME\settings.cfg was not found, so the GFX options cannot be read.' 'critical'))
        return (New-Scroll $list)
    }

    [void]$list.Children.Add((New-SectionHeader 'Decoded GFX options' (
        'settings.cfg is a 1786-byte binary with no field names in it. These four offsets were established by ' +
        'differential analysis: change one option in game, quit cleanly, then compare the file byte for byte. ' +
        'Every other byte is written back exactly as found.')))

    $d1 = New-CfgDot
    [void]$list.Children.Add((New-CfgRow 'Ground shading' 'settings.cfg offset 1676, bit 0x20' `
        'Shading across the terrain. Stored as a single bit inside a byte that also carries settings nobody has identified yet, so only that bit is touched.' `
        (New-CfgSwitch $script:CfgOffsets.GroundShadingByte $script:CfgOffsets.GroundShadingBit $d1) $d1))

    $d2 = New-CfgDot
    [void]$list.Children.Add((New-CfgRow 'Gamma level' 'settings.cfg offset 1684' `
        'Only Medium (2) and Maximum (4) were confirmed in game. The five-step scale is inferred from those two samples and has not been verified.' `
        (New-CfgCombo $script:CfgOffsets.Gamma @('0|0  -  Minimum (inferred)','1|1  -  Low (inferred)','2|2  -  Medium (confirmed)','3|3  -  High (inferred)','4|4  -  Maximum (confirmed)') $d2) $d2))

    $d3 = New-CfgDot
    [void]$list.Children.Add((New-CfgRow 'Item shading' 'settings.cfg offset 1688' `
        'Off (0) and Reflections (2) were confirmed. The middle value has never been observed and is a guess.' `
        (New-CfgCombo $script:CfgOffsets.ItemShading @('0|0  -  Off (confirmed)','1|1  -  Middle (unconfirmed)','2|2  -  Reflections (confirmed)') $d3) $d3))

    $d4 = New-CfgDot
    [void]$list.Children.Add((New-CfgRow 'Mirror' 'settings.cfg offset 1754' `
        'The rear-view mirror. Costs a second render pass, so it is not free.' `
        (New-CfgSwitch $script:CfgOffsets.Mirror 0 $d4) $d4))

    [void]$list.Children.Add((New-SectionHeader 'Campaign resolution' (
        'Four 32-bit integers at a 64-byte stride. The dropdown below writes them - it offers only modes ' +
        'your display actually reports, so an unusable mode cannot be selected. The 3D view is separate: ' +
        'set USE_DESKTOP_RESOLUTION on the Graphics page for that.')))

    # PLAUSIBILITY GATE. These offsets were mapped by differential
    # analysis of ONE machine's settings.cfg. A tester's file reads
    # "67,110,784 pixels wide" at the same offset - a different layout,
    # not a resolution. If the values are structurally implausible we
    # say so and offer NO editor, because writing into a file we cannot
    # read would corrupt it. Same gate as Install and repair.
    $gW  = [BitConverter]::ToInt32($script:CfgBytes, $script:CfgOffsets.ResW)
    $gH  = [BitConverter]::ToInt32($script:CfgBytes, $script:CfgOffsets.ResH)
    $gHz = [BitConverter]::ToInt32($script:CfgBytes, $script:CfgOffsets.ResHz)
    $resPlausible = ($gW -ge 320 -and $gW -le 7680 -and $gH -ge 200 -and $gH -le 4320 -and $gHz -ge 0 -and $gHz -le 500)
    if (-not $resPlausible) {
        [void]$list.Children.Add((New-Note ("This settings.cfg does not match the layout these offsets were mapped on " +
            "(raw read: $gW x $gH @ $gHz). The values are left strictly alone and no editor is offered - " +
            "change the campaign resolution from the game's own GFX screen instead.") 'critical'))
    } else {

    $res = New-Stack -Orientation 'Horizontal'
    foreach ($f in @(
        @('Width',   $script:CfgOffsets.ResW),
        @('Height',  $script:CfgOffsets.ResH),
        @('Refresh', $script:CfgOffsets.ResHz),
        @('Depth',   $script:CfgOffsets.ResBpp))) {
        $v = [BitConverter]::ToInt32($script:CfgBytes, $f[1])
        $st = New-Stack
        [void]$st.Children.Add((New-TB $f[0].ToUpper() -Style 'Eyebrow'))
        $val = New-TB ([string]$v) -Size 22 -Weight 'SemiBold' -Margin ([System.Windows.Thickness]::new(0,6,0,0))
        [void]$st.Children.Add($val)
        [void]$st.Children.Add((New-TB ('offset ' + $f[1]) -Style 'Mono' -Margin ([System.Windows.Thickness]::new(0,4,0,0))))
        [void]$res.Children.Add((New-Bd $st -Bg 'Card' -Border 'Line' -Thickness ([System.Windows.Thickness]::new(1)) `
            -Padding ([System.Windows.Thickness]::new(20,14,28,14)) -Margin ([System.Windows.Thickness]::new(0,14,12,0)) -Radius 6))
    }
    [void]$list.Children.Add($res)

    # ------------------------------------------------------------------
    #  CAMPAIGN RESOLUTION - now editable, but only to modes the display
    #  itself enumerates. The old fear here was writing a mode the
    #  hardware refuses, which leaves the game unable to start; offering
    #  nothing but enumerated modes removes that failure, so the
    #  read-only rule can go.
    # ------------------------------------------------------------------
    $dR = New-CfgDot
    $cbRes = New-Object System.Windows.Controls.ComboBox
    $cbRes.Style = Res 'Combo'
    $cbRes.MinWidth = 260
    $modes = @{}
    try {
        Get-CimInstance CIM_VideoControllerResolution -ErrorAction Stop |
            Where-Object { $_.NumberOfColors -ge 4294967296 -or $_.BitsPerPixel -ge 32 -or $true } |
            ForEach-Object {
                if ($_.HorizontalResolution -ge 800 -and $_.RefreshRate -ge 50) {
                    $k = '{0} x {1} @ {2} Hz' -f $_.HorizontalResolution, $_.VerticalResolution, $_.RefreshRate
                    $modes[$k] = @([int]$_.HorizontalResolution, [int]$_.VerticalResolution, [int]$_.RefreshRate)
                }
            }
    } catch { }
    $ordered = $modes.Keys | Sort-Object { $m = $modes[$_]; $m[0]*100000 + $m[1]*10 + $m[2]/1000 }
    foreach ($k in $ordered) { [void]$cbRes.Items.Add($k) }
    $curW  = [BitConverter]::ToInt32($script:CfgBytes, $script:CfgOffsets.ResW)
    $curH  = [BitConverter]::ToInt32($script:CfgBytes, $script:CfgOffsets.ResH)
    $curHz = [BitConverter]::ToInt32($script:CfgBytes, $script:CfgOffsets.ResHz)
    $curKey = '{0} x {1} @ {2} Hz' -f $curW, $curH, $curHz
    if (-not $modes.ContainsKey($curKey)) {
        $modes[$curKey] = @($curW, $curH, $curHz)
        [void]$cbRes.Items.Insert(0, $curKey)
    }
    $cbRes.SelectedItem = $curKey
    $cbRes.Tag = @{ Modes = $modes; Dot = $dR }
    $cbRes.Add_SelectionChanged({
        param($sndr, $e)
        if ($sndr.SelectedItem -eq $null) { return }
        $m = $sndr.Tag.Modes[[string]$sndr.SelectedItem]
        if (-not $m) { return }
        [Array]::Copy([BitConverter]::GetBytes([int]$m[0]), 0, $script:CfgBytes, $script:CfgOffsets.ResW,  4)
        [Array]::Copy([BitConverter]::GetBytes([int]$m[1]), 0, $script:CfgBytes, $script:CfgOffsets.ResH,  4)
        [Array]::Copy([BitConverter]::GetBytes([int]$m[2]), 0, $script:CfgBytes, $script:CfgOffsets.ResHz, 4)
        $changed = $false
        foreach ($o in @($script:CfgOffsets.ResW, $script:CfgOffsets.ResH, $script:CfgOffsets.ResHz)) {
            for ($i = 0; $i -lt 4; $i++) { if ($script:CfgBytes[$o+$i] -ne $script:CfgOrig[$o+$i]) { $changed = $true } }
        }
        $sndr.Tag.Dot.Visibility = $(if ($changed) { 'Visible' } else { 'Hidden' })
        if ($script:OnChange) { & $script:OnChange }
    })
    [void]$list.Children.Add((New-CfgRow 'Set campaign resolution' 'settings.cfg offsets 1416 / 1480 / 1544' `
        'Writes width, height and refresh together. Colour depth is left as it is. Remember to press Save to disk.' `
        $cbRes $dR))

    }

    # ------------------------------------------------------------------
    #  GUNSIGHTS - stock reticles or the enhanced redrawn set.
    #
    #  Three DXT5 textures drive the reflector sights: RAFsight.dds in
    #  COCKMASK and COCKPM16 (Spitfire/Hurricane) and SIGHT2.dds in
    #  COCKPM16 (the Bf109 Revi). The enhanced set redraws them at
    #  1024x1024 with thin sharp lines at the stock ring geometry, so
    #  aiming references do not move. Stock files are backed up as
    #  .stock-backup on first switch and restored from there.
    # ------------------------------------------------------------------
    [void]$list.Children.Add((New-SectionHeader 'Gunsights' (
        'The reflector-sight reticles. Enhanced replaces the thick glowing stock reticles with thin sharp ' +
        'ones redrawn at four times the resolution, at the same ring size, so deflection aiming is unchanged. ' +
        'Switching is safe: the stock textures are backed up first and Restore puts them back exactly.')))

    $sightTargets = @(
        @{ Src = 'RAFsight.dds'; Dst = 'COCKMASK\RAFsight.dds' },
        @{ Src = 'RAFsight.dds'; Dst = 'COCKPM16\RAFsight.dds' },
        @{ Src = 'SIGHT2.dds';   Dst = 'COCKPM16\SIGHT2.dds' }
    )
    $sightAssets = Join-Path $script:ScriptDir 'assets\gunsights'
    # GetNewClosure() binds LOCAL variables only - $script: scoped ones
    # resolve against the closure's own module and come back null, which
    # made both buttons fail with "Cannot bind argument to parameter
    # 'Path'". Capture the folder into a local first.
    $sightGameDir = $script:GameFolder

    $curSight = 'unknown'
    $probe = Join-Path $script:GameFolder 'COCKPM16\SIGHT2.dds'
    if (Test-Path -LiteralPath $probe) {
        $len = (Get-Item -LiteralPath $probe).Length
        if ($len -ge 1000000) { $curSight = 'enhanced' } elseif ($len -eq 262272) { $curSight = 'stock' }
    }
    $sightState = New-TB ("Currently installed: " + $curSight) -Style 'Eyebrow' -Margin ([System.Windows.Thickness]::new(0,14,0,0))
    [void]$list.Children.Add($sightState)

    $sightRow = New-Stack -Orientation 'Horizontal' -Margin ([System.Windows.Thickness]::new(0,10,0,0))
    $btnEnh = New-Btn 'Use enhanced gunsights' 'BtnPrimary' $null {
        try {
            if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) {
                [System.Windows.MessageBox]::Show('Close the game first - it has these textures open.','Gunsights') | Out-Null; return
            }
            $done = 0
            foreach ($t in $sightTargets) {
                $src = Join-Path $sightAssets $t.Src
                $dst = Join-Path $sightGameDir $t.Dst
                if (-not (Test-Path -LiteralPath $src)) { continue }
                if (-not (Test-Path -LiteralPath $dst)) { continue }
                if (-not (Test-Path -LiteralPath ($dst + '.stock-backup'))) { Copy-Item -LiteralPath $dst ($dst + '.stock-backup') }
                Copy-Item -LiteralPath $src $dst -Force
                $done++
            }
            $sightState.Text = 'Currently installed: enhanced  (' + $done + ' textures replaced, stock backed up)'
        } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Gunsights') | Out-Null }
    }.GetNewClosure()
    $btnStock = New-Btn 'Restore stock' 'BtnGhost' $null {
        try {
            if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) {
                [System.Windows.MessageBox]::Show('Close the game first - it has these textures open.','Gunsights') | Out-Null; return
            }
            $done = 0
            foreach ($t in $sightTargets) {
                $dst = Join-Path $sightGameDir $t.Dst
                if (Test-Path -LiteralPath ($dst + '.stock-backup')) { Copy-Item -LiteralPath ($dst + '.stock-backup') $dst -Force; $done++ }
            }
            $sightState.Text = 'Currently installed: stock  (' + $done + ' textures restored from backup)'
        } catch { [System.Windows.MessageBox]::Show($_.Exception.Message,'Gunsights') | Out-Null }
    }.GetNewClosure()
    $btnStock.Margin = [System.Windows.Thickness]::new(12,0,0,0)
    [void]$sightRow.Children.Add($btnEnh)
    [void]$sightRow.Children.Add($btnStock)
    [void]$list.Children.Add($sightRow)

    New-Scroll $list
}

# =============================================================================
#  ALL SETTINGS
# =============================================================================
$script:AllRows = @()
$script:AllGroups = @()
$script:AllFilter = ''
$script:AllCount = $null

$script:BdgFamilies = @(
    @{ N='Video and startup';        R='^SKIP_|^INTRO_VIDEO$|^CONTINUE_QUIT|^GAME_PAUSE$|^PRELOAD|^AUTOMATIC_PRELOAD$|^START_FROM_PEN$' }
    @{ N='Scene density and performance'; R='DENSITY$|^LANDSCAPE_TEXTURE_SIZE$|^ENABLE_AUTO_GEN$|^ADD_SHEEP|^Render_Sheep|RIM_TREE|FOREST_RIM|^OPTIMISE_|^SMOOTHEN_|^UI_REFRESH$|^PERIPHERAL_|^TRACKVIEWRANGE$|^TEMP_AG' }
    @{ N='Field of view';            R='^FOV_|^ALLOW_ULTRA_HIGH_FOVS$|^NO_FOV_RESET$' }
    @{ N='Head position and cockpit';R='^EYE_|^CPTVIEW|^HEAD_BOBBING$|^NO_HEAD_BOBBING|^CUSTOM_HEAD|^ALWAYS_BEHIND|^LOCK_GUNNER|2DGAUGES|^Your_2dGauges' }
    @{ N='External views and padlock'; R='^External_View|^INVERT_EXTERNAL|^PAN_SPEED|^NO_PILOT_IN_ROVING|PADLOCK|^NEAR_CLIP' }
    @{ N='Head tracking';            R='^TRACKIR' }
    @{ N='Labels';                   R='^LABEL|^Single_Char|^SHORTENED_LABELS$|^FADING_LABELS$|^EPI_|^ENEMY_POSITION' }
    @{ N='Water colour';             R='^WATER_COLOUR' }
    @{ N='Sky model';                R='^Weather_' }
    @{ N='Cloud layers';             R='^Cloud_|^IN_CLOUD' }
    @{ N='Bullet dispersion';        R='^Dispersion_|^Bullet_|^BULLET_|^CONVERGENCE$' }
    @{ N='Spin behaviour';           R='_Spin_|^Spin_AISkill|^No_Spinning_Death$|^Use_The_Spinout|^SPINRECOVERY$' }
    @{ N='Flight model deltas';      R='_Boost_Delta$|_Trim_Delta$|REDUCE_SURFACE_DEFLECTION$' }
    @{ N='Flak and anti-aircraft';   R='^Flak_|Flak|^Reload_LT_BRIT|^LT_BRIT' }
    @{ N='Collisions';               R='^Collision_|^Air_To_Air|^NO_FRIENDLY_COLLISIONS$|^GEAR_' }
    @{ N='AI behaviour';             R='^AI_|^Novice_|^Max_Number_AI|^Wingmen_|^RAF_Breaksoff|^SPC_Skill|^Do_You_Want|^Permit_|^Allow_|^Campaign_|^Time_In_IA|^Remove_SPC|^Friendly_Fire$|^Testing_Do_Not_Shoot$|^Player_Stronger' }
    @{ N='Damage modelling';         R='^BOB_(WING|ENG|CAN)' }
    @{ N='Dither lookup table';      R='^BOB_DITHER|^DITHER_FACTOR$' }
    @{ N='Textures and terrain';     R='TEXTURE|^USE_HIRES|^HIRES_|^WK_LANDSCAPE|^EVERYTHING_OBSCURES|^USE_PCX_OR_DDS$|^ENABLE_TOWN' }
    @{ N='Community fixes';          R='^BOB_|^FIX_' }
    @{ N='Debug and testing';        R='^DEBUG|^Maneuvre_Testing|^PERFORMANCE_TEST|^UDET_|^Show_MoveCodes$|^Scott_PS_Log$|^Do_All_SAG|^MINIDUMPLOG|^Jump_Test|^SKINNERS_MODE$|^3D_MODELLER_MODE$|^VIDEO_MAKING_MODE$|^OBJECT_PLACEMENT_MODE$|^SHADER2TWEAK$|^DELETE_MODELS' }
    @{ N='Everything else';          R='.' }
)

function Get-BdgFamily {
    param([string]$Key)
    foreach ($f in $script:BdgFamilies) { if ($Key -match $f.R) { return $f.N } }
    'Everything else'
}

function Apply-AllFilter {
    $f = $script:AllFilter.Trim()
    $shown = 0
    foreach ($g in $script:AllGroups) {
        $vis = 0
        foreach ($r in $g.Rows) {
            $ok = $true
            if ($f) {
                $e = $script:Bdg[$r.Key]
                $hay = $r.Key + ' ' + $e.Value + ' ' + $e.Comment + ' ' + $r.Label + ' ' + $g.Name
                $ok = $hay -like ('*' + $f + '*')
            }
            $r.Row.Visibility = $(if ($ok) { 'Visible' } else { 'Collapsed' })
            if ($ok) { $vis++; $shown++ }
        }
        $g.Header.Visibility = $(if ($vis -gt 0) { 'Visible' } else { 'Collapsed' })
    }
    if ($script:AllCount) { $script:AllCount.Text = "$shown of $($script:BdgOrder.Count) assignments" }
}

function Build-AllPage {
    $root = New-Grid @('*') @('Auto','*')

    $tb = New-Grid @('*','16','Auto')
    $tb.Margin = [System.Windows.Thickness]::new(34,20,34,10)
    $search = New-Object System.Windows.Controls.TextBox
    $search.Style = Res 'SearchBox'
    $search.ToolTip = 'Search the key name, the current value, or the inline comment from bdg.txt'
    $search.Add_TextChanged({ param($s,$e) $script:AllFilter = $s.Text; Apply-AllFilter })
    Add-Cell $tb $search 0 | Out-Null
    $script:AllCount = New-TB '' -Size 12 -Brush 'Dim'
    $script:AllCount.VerticalAlignment = 'Center'
    Add-Cell $tb $script:AllCount 2 | Out-Null
    Add-Cell $root $tb 0 0 | Out-Null

    # Curated pages own their rows already; a key can only have one editor, so
    # anything already placed is listed here as a cross-reference instead.
    $claimed = @{}
    foreach ($pn in $script:Pages.Keys) {
        foreach ($sec in $script:Pages[$pn].Sections) {
            foreach ($i in $sec.I) { $claimed[$i.Key] = $pn }
        }
    }

    $list = New-Stack -Margin ([System.Windows.Thickness]::new(34,0,26,50))
    $grouped = @{}
    foreach ($k in $script:BdgOrder) {
        $fam = Get-BdgFamily $k
        if (-not $grouped.ContainsKey($fam)) { $grouped[$fam] = @() }
        $grouped[$fam] += $k
    }
    $script:AllGroups = @()
    foreach ($fdef in $script:BdgFamilies) {
        $fam = $fdef.N
        if (-not $grouped.ContainsKey($fam)) { continue }
        $hdr = New-SectionHeader $fam ''
        [void]$list.Children.Add($hdr)
        $rows = @()
        foreach ($k in $grouped[$fam]) {
            if ($claimed.ContainsKey($k)) {
                # Editing lives on the curated page; show a compact pointer.
                $g = New-Grid @('*','16','228','14','10')
                $g.Margin = [System.Windows.Thickness]::new(0,11,0,11)
                $left = New-Stack
                [void]$left.Children.Add((New-TB $k -Style 'RowLabel'))
                [void]$left.Children.Add((New-TB ('Edited on the ' + $claimed[$k] + ' page') -Style 'Mono' `
                                          -Margin ([System.Windows.Thickness]::new(0,2,0,0))))
                Add-Cell $g $left 0 | Out-Null
                $v = New-TB $script:Bdg[$k].Value -Size 12.5 -Brush 'Muted'
                $v.FontFamily = 'Consolas'; $v.VerticalAlignment = 'Center'
                Add-Cell $g $v 2 | Out-Null
                $row = New-Bd $g -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))
                $row.Opacity = 0.7
            } else {
                $row = New-SettingRow $null $k
            }
            if ($row) {
                [void]$list.Children.Add($row)
                $rows += @{ Key = $k; Row = $row; Label = $k }
            }
        }
        $script:AllGroups += @{ Name = $fam; Header = $hdr; Rows = $rows }
    }
    Add-Cell $root (New-Scroll $list) 0 1 | Out-Null
    Apply-AllFilter
    $root
}

# =============================================================================
#  OVERVIEW
# =============================================================================
$script:HealthHost = $null
$script:FileHost   = $null

function Get-HealthIssues {
    $out = @()
    foreach ($pn in $script:Pages.Keys) {
        foreach ($sec in $script:Pages[$pn].Sections) {
            foreach ($i in $sec.I) {
                if (-not $i.Rec) { continue }
                if (-not $script:Bdg.ContainsKey($i.Key)) { continue }
                if ($script:Bdg[$i.Key].Value.Trim() -eq $i.Rec) { continue }
                $out += @{ Key = $i.Key; Label = $i.Label; Want = $i.Rec; Level = $i.Level
                           Msg = $i.RecMsg; Page = $pn; Now = $script:Bdg[$i.Key].Value.Trim() }
            }
        }
    }
    ,$out
}

function Invalidate-Pages {
    foreach ($n in @($script:PageCache.Keys)) {
        if ($n -eq 'Overview' -or $n -eq 'Key bindings' -or $n -eq 'GFX screen' -or
            $n -eq 'All settings' -or $n -eq 'Joystick and axes') { continue }
        [void]$PageHost.Children.Remove($script:PageCache[$n])
        $script:PageCache.Remove($n)
    }
}

function Refresh-Health {
    if (-not $script:HealthHost) { return }
    $script:HealthHost.Children.Clear()
    $issues = Get-HealthIssues
    if ($issues.Count -eq 0) {
        $ok = New-Stack -Orientation 'Horizontal'
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 8; $dot.Height = 8; $dot.Fill = Res 'Good'; $dot.VerticalAlignment = 'Center'
        $dot.Margin = [System.Windows.Thickness]::new(0,0,12,0)
        [void]$ok.Children.Add($dot)
        [void]$ok.Children.Add((New-TB 'Every recommended setting is already correct.' -Size 13 -Brush 'Muted'))
        [void]$script:HealthHost.Children.Add((New-Bd $ok -Padding ([System.Windows.Thickness]::new(0,12,0,12))))
        return
    }

    foreach ($i in $issues) {
        $g = New-Grid @('*','16','Auto')
        $g.Margin = [System.Windows.Thickness]::new(0,12,0,12)
        $left = New-Stack
        $head = New-Stack -Orientation 'Horizontal'
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 8; $dot.Height = 8; $dot.VerticalAlignment = 'Center'
        $dot.Fill = Res $(if ($i.Level -eq 'critical') { 'Danger' } elseif ($i.Level -eq 'perf') { 'Warn' } else { 'Info' })
        $dot.Margin = [System.Windows.Thickness]::new(0,0,10,0)
        [void]$head.Children.Add($dot)
        [void]$head.Children.Add((New-TB $i.Label -Style 'RowLabel'))
        [void]$left.Children.Add($head)
        [void]$left.Children.Add((New-TB $i.Msg -Style 'RowHint'))
        $now = New-TB ($i.Key + ' is ' + $i.Now + ', recommended ' + $i.Want) -Style 'Mono'
        $now.Margin = [System.Windows.Thickness]::new(18,5,0,0)
        [void]$left.Children.Add($now)
        Add-Cell $g $left 0 | Out-Null

        $fix = New-Btn ('Set to ' + $i.Want) 'BtnGhost' $i {
            param($s, $e)
            Set-Setting $s.Tag.Key $s.Tag.Want
            Invalidate-Pages
            Refresh-Health
        }
        $fix.VerticalAlignment = 'Top'
        Add-Cell $g $fix 2 | Out-Null
        [void]$script:HealthHost.Children.Add((New-Bd $g -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))))
    }

    if ($issues.Count -gt 1) {
        $all = New-Btn ('Apply all ' + $issues.Count + ' recommendations') 'BtnPrimary' $null {
            foreach ($i in (Get-HealthIssues)) { Set-Setting $i.Key $i.Want }
            Invalidate-Pages
            Refresh-Health
        }
        $all.HorizontalAlignment = 'Left'
        $all.Margin = [System.Windows.Thickness]::new(0,18,0,0)
        [void]$script:HealthHost.Children.Add($all)
    }
}

function Build-OverviewPage {
    $list = New-Stack -Margin ([System.Windows.Thickness]::new(34,0,34,50))

    # The single most important thing to say.
    $warnStack = New-Stack
    [void]$warnStack.Children.Add((New-TB 'CLOSE THE GAME BEFORE SAVING' -Style 'Eyebrow' -Brush 'Warn'))
    $wt = New-TB ('Battle of Britain II rewrites bdg.txt, keys.txt, settings.cfg and Weather.cfg when it exits. ' +
                  'If the game is running when you save, it will overwrite everything this tool wrote the moment ' +
                  'you quit. Edit with the game closed, save, then start it.') -Size 13 -Wrap
    $wt.Foreground = Res 'Text'; $wt.LineHeight = 19; $wt.MaxWidth = 720
    $wt.Margin = [System.Windows.Thickness]::new(0,8,0,0)
    [void]$warnStack.Children.Add($wt)
    [void]$list.Children.Add((New-Bd $warnStack -Bg 'Card' -Border 'Warn' -Thickness ([System.Windows.Thickness]::new(1,1,1,1)) `
        -Padding ([System.Windows.Thickness]::new(22,18,22,20)) -Margin ([System.Windows.Thickness]::new(0,6,0,0)) -Radius 6))

    [void]$list.Children.Add((New-SectionHeader 'Checks' (
        'These are the settings where a wrong value causes a crash or costs a large amount of frame rate. ' +
        'Applying a fix only stages it; nothing reaches disk until you press Save.')))
    $script:HealthHost = New-Stack
    [void]$list.Children.Add($script:HealthHost)
    Refresh-Health

    [void]$list.Children.Add((New-SectionHeader 'Files' 'What was found, and what this tool will write to.'))
    $script:FileHost = New-Stack
    foreach ($f in @(
        @('bdg.txt',              $script:Paths.Bdg,     'Game settings.  Windows-1252, CRLF.'),
        @('KEYBOARD\keys.txt',    $script:Paths.Keys,    'Your key bindings.'),
        @('KEYBOARD\default.txt', $script:Paths.Default, 'Stock bindings.  Read only - used for Reset.'),
        @('SAVEGAME\settings.cfg',$script:Paths.Cfg,     'Binary. Holds the GFX options screen.'),
        @('Weather\Weather.cfg',  $script:Paths.Wx,      'Water, weather and horizon detail.'))) {
        $g = New-Grid @('300','*','Auto')
        $g.Margin = [System.Windows.Thickness]::new(0,11,0,11)
        $nm = New-TB $f[0] -Size 12.5
        $nm.FontFamily = 'Consolas'
        Add-Cell $g $nm 0 | Out-Null
        Add-Cell $g (New-TB $f[2] -Size 12 -Brush 'Muted' -Wrap) 1 | Out-Null
        $exists = Test-Path -LiteralPath $f[1]
        $st = if ($exists) {
            $fi = Get-Item -LiteralPath $f[1]
            New-TB (('{0:n0} bytes    {1:yyyy-MM-dd HH:mm}' -f $fi.Length, $fi.LastWriteTime)) -Size 11.5 -Brush 'Dim'
        } else {
            New-TB 'not found' -Size 11.5 -Brush 'Danger'
        }
        $st.FontFamily = 'Consolas'
        $st.Margin = [System.Windows.Thickness]::new(20,0,0,0)
        Add-Cell $g $st 2 | Out-Null
        [void]$script:FileHost.Children.Add((New-Bd $g -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))))
    }
    [void]$list.Children.Add($script:FileHost)

    [void]$list.Children.Add((New-SectionHeader 'How this tool treats your files' ''))
    foreach ($p in @(
        'Only the value on a line is replaced. Indentation, the spacing around the equals sign, inline comments, line order, blank lines, the Windows-1252 encoding and the CRLF line endings are all preserved exactly.',
        'Joystick and POV codes on a key binding line are never altered. When you change the keyboard part of a binding, those codes are written back untouched.',
        'In settings.cfg, only the four decoded bytes are ever modified, and ground shading changes a single bit inside a byte that carries other, unidentified settings.',
        'Every file that is about to change is copied into a timestamped folder under _ConfigBackups before anything is written.')) {
        $t = New-TB $p -Size 12.5 -Brush 'Muted' -Wrap
        $t.LineHeight = 19; $t.MaxWidth = 760
        $t.Margin = [System.Windows.Thickness]::new(0,10,0,0)
        [void]$list.Children.Add($t)
    }
    New-Scroll $list
}

# =============================================================================
#  NAVIGATION
# =============================================================================
$script:PageCache = @{}
$script:NavIcons = @{
    'Overview' = 'IcoClipboardCheck'
    'Performance' = 'IcoGauge'
    'Graphics' = 'IcoMonitor'
    'View and camera' = 'IcoEye'
    'Weather and sky' = 'IcoCloudSun'
    'Realism and AI' = 'IcoCrosshair'
    'Interface' = 'IcoLayoutDashboard'
    'GFX screen' = 'IcoFileCog'
    'Key bindings' = 'IcoKeyboard'
    'Joystick and axes' = 'IcoJoystick'
    'All settings' = 'IcoFileText'
    'About' = 'IcoInfo'
}

$script:NavDefs = @(
    @{ Caption = $null;        Name = 'Overview';        Sub = 'Settings worth changing before you fly, and the five files this tool writes to.' }
    @{ Caption = 'SETTINGS';   Name = 'Performance';     Sub = $null }
    @{ Caption = $null;        Name = 'Graphics';        Sub = $null }
    @{ Caption = $null;        Name = 'View and camera'; Sub = $null }
    @{ Caption = $null;        Name = 'Weather and sky'; Sub = $null }
    @{ Caption = $null;        Name = 'Realism and AI';  Sub = $null }
    @{ Caption = $null;        Name = 'Interface';       Sub = $null }
    @{ Caption = $null;        Name = 'GFX screen';      Sub = 'The options behind the game''s own GFX screen, decoded out of a binary save file.' }
    @{ Caption = 'CONTROLS';   Name = 'Key bindings';    Sub = 'Click any binding to assign a new key. Search matches the action name, the plain-English label, or the key itself.' }
    @{ Caption = $null;        Name = 'Joystick and axes'; Sub = 'What is plugged in, which physical axis drives what, and how much dead travel sits around centre.' }
    @{ Caption = $null;        Name = 'About';           Sub = 'What this is, what it is not, and where the photographs came from.' }
    @{ Caption = 'EVERYTHING'; Name = 'All settings';    Sub = 'Every assignment in bdg.txt, grouped and searchable, with the game''s own inline comments.' }
)

# =============================================================================
#  JOYSTICK AND AXES
#  Everything about the stick that is NOT a button binding: what is plugged in,
#  which physical axis drives which control, and the deadzone around centre.
#  The heavy lifting stays in BOB2_Controls.ps1 and BOB2_Sensitivity.ps1 so
#  there is one implementation, not two that can drift apart.
# =============================================================================
# Device detection, kept deliberately small: winmm gives real axis and button
# counts, the registry gives the product name, and a DirectInput product GUID
# is just PID then VID with a fixed tail. No DirectInput interop needed.
function Get-JoystickDevices {
    if (-not ('BOB2CfgJoy' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class BOB2CfgJoy {
  [StructLayout(LayoutKind.Sequential)] public struct JOYCAPS {
    public ushort wMid, wPid;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szPname;
    public uint wXmin,wXmax,wYmin,wYmax,wZmin,wZmax,wNumButtons,wPeriodMin,wPeriodMax;
    public uint wRmin,wRmax,wUmin,wUmax,wVmin,wVmax,wCaps,wMaxAxes,wNumAxes,wMaxButtons;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szRegKey;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string szOEMVxD;
  }
  [DllImport("winmm.dll", CharSet=CharSet.Ansi)] public static extern uint joyGetDevCapsA(uint id, ref JOYCAPS c, uint size);
}
'@
    }
    $oem = @{}
    foreach ($root in @('HKLM:\SYSTEM\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM',
                        'HKCU:\System\CurrentControlSet\Control\MediaProperties\PrivateProperties\Joystick\OEM')) {
        if (-not (Test-Path $root)) { continue }
        foreach ($k in (Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $n = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).OEMName
            if ($n) { $oem[$k.PSChildName.ToUpper()] = $n }
        }
    }
    $out = @()
    for ($i = 0; $i -lt 16; $i++) {
        $c = New-Object BOB2CfgJoy+JOYCAPS
        $r = [BOB2CfgJoy]::joyGetDevCapsA($i, [ref]$c, [System.Runtime.InteropServices.Marshal]::SizeOf($c))
        if ($r -ne 0 -or -not $c.szPname) { continue }
        $v = '{0:X4}' -f $c.wMid
        $d = '{0:X4}' -f $c.wPid          # not $pid, which PowerShell owns
        $key = "VID_$v&PID_$d"
        $out += [pscustomobject]@{
            Name    = $(if ($oem.ContainsKey($key.ToUpper())) { $oem[$key.ToUpper()] } else { $c.szPname })
            Guid    = ('{{{0}{1}-0000-0000-0000-504944564944}}' -f $d, $v)
            Buttons = [int]$c.wNumButtons
            Axes    = [int]$c.wNumAxes
            HasPov  = [bool]($c.wCaps -band 1)
        }
    }
    $out
}

$script:JoyStride = 278
$script:JoyAu = @('Pitch','Roll','Yaw','Throttle','Throttle 2','Prop pitch','Prop pitch 2',
                  'Gunner X','Gunner Y','View X','View Y','View zoom','View FOV')
$script:JoyDiAxis = @('X','Y','Z','Rx','Ry','Rz','Slider','Slider 2')

function Get-JoyAxisRows {
    $cfg = Join-Path $script:GameFolder 'SAVEGAME\inputcfg.dat'
    if (-not (Test-Path -LiteralPath $cfg)) { return @() }
    $b = [System.IO.File]::ReadAllBytes($cfg)
    $out = @()
    for ($i = 0; $i -lt [math]::Floor($b.Length / $script:JoyStride); $i++) {
        $o = $i * $script:JoyStride
        $kind = [BitConverter]::ToInt32($b, $o + 8)
        $di   = [BitConverter]::ToInt32($b, $o + 20)
        if ($kind -eq 0 -and $di -lt 0) { continue }
        $nb = $b[($o+25)..($o+70)]
        $z = [Array]::IndexOf($nb, [byte]0); if ($z -lt 0) { $z = $nb.Length }
        $out += @{
            Use  = $(if ($i -lt $script:JoyAu.Count) { $script:JoyAu[$i] } else { "axis $i" })
            Kind = $kind
            Dead = [BitConverter]::ToInt32($b, $o + 12)
            Sat  = [BitConverter]::ToInt32($b, $o + 16)
            Inv  = $b[$o + 24]
            Ax   = $(if ($di -ge 0 -and $di -lt $script:JoyDiAxis.Count) { $script:JoyDiAxis[$di] } else { '' })
            Name = [System.Text.Encoding]::ASCII.GetString($nb, 0, $z)
        }
    }
    $out
}

function Invoke-JoyTool {
    param([string]$Script, [string[]]$Arguments)
    $p = Join-Path $script:ScriptDir $Script
    if (-not (Test-Path -LiteralPath $p)) {
        [void][System.Windows.MessageBox]::Show($Win, "$Script is missing from the fix folder.", 'Joystick', 'OK', 'Warning')
        return $false
    }
    if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) {
        [void][System.Windows.MessageBox]::Show($Win,
            "The game is running. It rewrites its input configuration when it exits, so anything changed now would be discarded. Close it first.",
            'Joystick', 'OK', 'Warning')
        return $false
    }
    $a = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',"`"$p`"") + $Arguments
    $r = Start-Process -FilePath 'powershell.exe' -ArgumentList $a `
            -WorkingDirectory $script:ScriptDir -WindowStyle Hidden -Wait -PassThru
    if ($r.ExitCode -ne 0) {
        [void][System.Windows.MessageBox]::Show($Win,
            "$Script exited with code $($r.ExitCode). Nothing may have been written - run it from the fix folder to see why.",
            'Joystick', 'OK', 'Warning')
        return $false
    }
    return $true
}

# Live joystick state. joyGetPosEx reports each axis as 0..65535 with centre
# at 32767, buttons as a bitmask, and the hat in hundredths of a degree with
# 65535 meaning centred.
$script:JoyLive = @{ Timer = $null; Axes = @{}; Buttons = @(); Hat = $null; DzPct = 1.0; Dev = 0 }

function Get-JoyState {
    param([int]$Device = 0)
    if (-not ('BOB2CfgJoyState' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class BOB2CfgJoyState {
  [StructLayout(LayoutKind.Sequential)] public struct JOYINFOEX {
    public int dwSize, dwFlags, dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos;
    public int dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2;
  }
  [DllImport("winmm.dll")] public static extern int joyGetPosEx(int id, ref JOYINFOEX pji);
  public static bool Poll(int id, out int x, out int y, out int z, out int r, out int u, out int v, out int btn, out int pov) {
    JOYINFOEX j = new JOYINFOEX();
    j.dwSize = Marshal.SizeOf(typeof(JOYINFOEX));
    j.dwFlags = 0xFF;
    int rc = joyGetPosEx(id, ref j);
    x=j.dwXpos; y=j.dwYpos; z=j.dwZpos; r=j.dwRpos; u=j.dwUpos; v=j.dwVpos;
    btn=j.dwButtons; pov=j.dwPOV;
    return rc == 0;
  }
}
'@
    }
    $x=0;$y=0;$z=0;$r=0;$u=0;$v=0;$b=0;$pv=0
    $ok = $false
    try { $ok = [BOB2CfgJoyState]::Poll($Device, [ref]$x, [ref]$y, [ref]$z, [ref]$r, [ref]$u, [ref]$v, [ref]$b, [ref]$pv) } catch { }
    if (-not $ok) { return $null }
    # Index by the DirectInput axis order the game uses.
    @{ Raw = @($x, $y, $z, $r, $u, $v); Buttons = $b; Pov = $pv }
}

function Stop-JoyLive {
    if ($script:JoyLive.Timer) { $script:JoyLive.Timer.Stop(); $script:JoyLive.Timer = $null }
}

# One bar per axis: a track, a shaded dead band around centre, and a marker.
function New-AxisBar {
    param([string]$Label, [int]$DiIndex)
    $g = New-Grid @('215','*')
    $g.Margin = [System.Windows.Thickness]::new(0,6,0,6)
    $lb = New-TB $Label -Size 12.5
    $lb.VerticalAlignment = 'Center'
    Add-Cell $g $lb 0 | Out-Null

    $cv = New-Object System.Windows.Controls.Canvas
    $cv.Width = 300; $cv.Height = 20; $cv.HorizontalAlignment = 'Left'

    $track = New-Object System.Windows.Shapes.Rectangle
    $track.Width = 300; $track.Height = 20; $track.Fill = Res 'Field'
    $track.Stroke = Res 'Line'; $track.StrokeThickness = 1
    [void]$cv.Children.Add($track)

    $dz = New-Object System.Windows.Shapes.Rectangle
    $dz.Height = 18; $dz.Fill = Res 'DangerWash'
    [System.Windows.Controls.Canvas]::SetTop($dz, 1)
    [void]$cv.Children.Add($dz)

    $mid = New-Object System.Windows.Shapes.Rectangle
    $mid.Width = 1; $mid.Height = 20; $mid.Fill = Res 'Line'
    [System.Windows.Controls.Canvas]::SetLeft($mid, 150)
    [void]$cv.Children.Add($mid)

    $mark = New-Object System.Windows.Shapes.Rectangle
    $mark.Width = 3; $mark.Height = 20; $mark.Fill = Res 'Accent'
    [System.Windows.Controls.Canvas]::SetLeft($mark, 148)
    [void]$cv.Children.Add($mark)

    Add-Cell $g $cv 1 | Out-Null
    $script:JoyLive.Axes[$DiIndex] = @{ Mark = $mark; Dead = $dz }
    $g
}

function Update-JoyDeadBands {
    $w = 300.0
    $half = ($script:JoyLive.DzPct / 100.0) * ($w / 2.0)
    foreach ($k in $script:JoyLive.Axes.Keys) {
        $d = $script:JoyLive.Axes[$k].Dead
        $d.Width = [math]::Max(0.0, $half * 2.0)
        [System.Windows.Controls.Canvas]::SetLeft($d, 150.0 - $half)
    }
}

function Start-JoyLive {
    Stop-JoyLive
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(50)
    $t.Add_Tick({
        $st = Get-JoyState $script:JoyLive.Dev
        if (-not $st) { return }
        foreach ($k in $script:JoyLive.Axes.Keys) {
            if ($k -lt 0 -or $k -ge $st.Raw.Count) { continue }
            $frac = $st.Raw[$k] / 65535.0
            [System.Windows.Controls.Canvas]::SetLeft($script:JoyLive.Axes[$k].Mark, ($frac * 297.0))
        }
        for ($i = 0; $i -lt $script:JoyLive.Buttons.Count; $i++) {
            $on = ($st.Buttons -band (1 -shl $i)) -ne 0
            $script:JoyLive.Buttons[$i].Background = $(if ($on) { Res 'Accent' } else { Res 'Field' })
        }
        if ($script:JoyLive.Hat) {
            $pv = $st.Pov
            $script:JoyLive.Hat.Text = $(if ($pv -lt 0 -or $pv -gt 36000) { 'centred' }
                                        else { @('up','up-right','right','down-right','down','down-left','left','up-left')[([int][math]::Round($pv/4500.0)) % 8] })
        }
    })
    $t.Start()
    $script:JoyLive.Timer = $t
}

function Build-JoystickPage {
    $p = New-Stack
    $script:JoyLive.Axes = @{}
    $script:JoyLive.Buttons = @()
    $script:JoyLive.Hat = $null

    [void]$p.Children.Add((New-Note ('Buttons live on the Key bindings page. This page is the other half: which physical ' +
        'axis drives which control, how much dead travel sits around centre, and a live test so you can see both.') 'info'))

    $devs = @()
    try { $devs = @(Get-JoystickDevices) } catch { }

    # --- detected hardware -------------------------------------------
    [void]$p.Children.Add((New-SectionHeader 'DETECTED' 'What Windows can see right now.'))
    if ($devs.Count -eq 0) {
        [void]$p.Children.Add((New-Note 'No game controller is connected. Plug your stick in and reopen this page.' 'critical'))
    } else {
        foreach ($d in $devs) {
            $st = New-Stack
            [void]$st.Children.Add((New-TB $d.Name -Size 14))
            [void]$st.Children.Add((New-TB ("{0} buttons, {1} axes{2}" -f $d.Buttons, $d.Axes,
                $(if ($d.HasPov) { ', 1 hat' } else { '' })) -Size 11.5 -Brush 'Muted'))
            $gid = New-TB $d.Guid -Size 11 -Brush 'Dim'; $gid.FontFamily = 'Consolas'
            [void]$st.Children.Add($gid)
            $st.Margin = [System.Windows.Thickness]::new(0,8,0,8)
            [void]$p.Children.Add((New-Bd $st -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))))
        }
    }

    $rows = @(Get-JoyAxisRows)
    $joy  = @($rows | Where-Object { $_.Kind -eq 2 })

    # --- live test ----------------------------------------------------
    if ($devs.Count -gt 0) {
        [void]$p.Children.Add((New-SectionHeader 'LIVE TEST' 'Move the stick and press its buttons - this updates as you do.'))

        if ($joy.Count -eq 0) {
            [void]$p.Children.Add((New-Note ('The bars below show raw hardware. Nothing is mapped in the game yet - ' +
                'press "Set up my stick" further down, then start the game once.') 'perf'))
        }

        # These are the RAW hardware axes as winmm reports them, not the
        # game's names for them. winmm's order (X Y Z R U V) is NOT
        # DirectInput's (X Y Z Rx Ry Rz Slider), and the two do not line up
        # per-device: on this stick the twist grip appears on winmm's Z or R
        # depending on the driver, while DirectInput calls it Z Rotation.
        # Rather than guess a mapping and mislabel a bar, show what the
        # hardware sends and let the stick identify itself - move a control
        # and watch which bar answers.
        $axisNames = @(
            @{ N = 'X'; H = 'left / right - roll' }
            @{ N = 'Y'; H = 'forward / back - pitch' }
            @{ N = 'Z'; H = 'third axis' }
            @{ N = 'R'; H = 'fourth axis - usually twist or slider' }
            @{ N = 'U'; H = 'fifth axis' }
            @{ N = 'V'; H = 'sixth axis' }
        )
        $nAx = $(if ($devs.Count -gt 0) { [math]::Min(6, [math]::Max(2, $devs[0].Axes)) } else { 4 })
        for ($i = 0; $i -lt $nAx; $i++) {
            [void]$p.Children.Add((New-AxisBar ("{0}   {1}" -f $axisNames[$i].N, $axisNames[$i].H) $i))
        }
        [void]$p.Children.Add((New-Note ('Move one control at a time to see which bar it drives. The names above are ' +
            'the hardware''s own, and do not always match the names the game uses in the list further down.') 'info'))

        # Hat
        $hg = New-Grid @('215','*')
        $hg.Margin = [System.Windows.Thickness]::new(0,6,0,6)
        Add-Cell $hg (New-TB 'Hat' -Size 12.5) 0 | Out-Null
        $ht = New-TB 'centred' -Size 12.5 -Brush 'Accent'
        Add-Cell $hg $ht 1 | Out-Null
        $script:JoyLive.Hat = $ht
        [void]$p.Children.Add($hg)

        # Buttons, numbered as the game numbers them.
        $bl = New-TB 'Buttons' -Size 12.5
        $bl.Margin = [System.Windows.Thickness]::new(0,14,0,6)
        [void]$p.Children.Add($bl)
        $wrap = New-Object System.Windows.Controls.WrapPanel
        $count = $(if ($devs.Count -gt 0) { [math]::Min(32, $devs[0].Buttons) } else { 16 })
        for ($i = 0; $i -lt $count; $i++) {
            $b = New-Object System.Windows.Controls.Border
            $b.Width = 30; $b.Height = 26; $b.Margin = [System.Windows.Thickness]::new(0,0,5,5)
            $b.Background = Res 'Field'; $b.BorderBrush = Res 'Line'; $b.BorderThickness = [System.Windows.Thickness]::new(1)
            $t = New-TB ([string]($i + 1)) -Size 11 -Brush 'Muted'
            $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'
            $b.Child = $t
            [void]$wrap.Children.Add($b)
            $script:JoyLive.Buttons += $b
        }
        [void]$p.Children.Add($wrap)
        [void]$p.Children.Add((New-Note ('Button numbers here match the numbers used on the Key bindings page, so if ' +
            'you press a button and it lights up as 7, that is "Joy 1 Button 7" there.') 'info'))
    }

    # --- axis assignment ---------------------------------------------
    [void]$p.Children.Add((New-SectionHeader 'AXIS ASSIGNMENT' 'Read from SAVEGAME\inputcfg.dat.'))
    if ($rows.Count -eq 0) {
        [void]$p.Children.Add((New-Note 'No input configuration found yet.' 'perf'))
    }
    foreach ($r in $rows) {
        $g = New-Grid @('130','*','90','70')
        $g.Margin = [System.Windows.Thickness]::new(0,7,0,7)
        Add-Cell $g (New-TB $r.Use -Size 13) 0 | Out-Null
        $phys = New-TB ("{0}{1}" -f $r.Name, $(if ($r.Ax) { "  [$($r.Ax)]" } else { '' })) -Size 12 -Brush 'Muted'
        $phys.FontFamily = 'Consolas'
        Add-Cell $g $phys 1 | Out-Null
        Add-Cell $g (New-TB ('{0:0.0}% dead' -f ($r.Dead / 100)) -Size 12 -Brush $(if ($r.Kind -eq 2) { 'Text' } else { 'Dim' })) 2 | Out-Null
        Add-Cell $g (New-TB $(if ($r.Inv) { 'inverted' } else { '' }) -Size 11.5 -Brush 'Dim') 3 | Out-Null
        [void]$p.Children.Add((New-Bd $g -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))))
    }

    # --- deadzone -----------------------------------------------------
    [void]$p.Children.Add((New-SectionHeader 'DEADZONE' 'Movement around centre the game ignores.'))
    [void]$p.Children.Add((New-Note ('The game ships 7.5%, a 2005 default sized for potentiometer sticks that wandered ' +
        'at rest. A Hall-effect stick does not drift and does not need it - and that dead patch sits exactly where ' +
        'gunnery happens. Drag the slider and watch the red band on the bars above: set it just wide enough to cover ' +
        'any wander when you let go of the stick, and no wider.') 'info'))

    [void]$p.Children.Add((New-Note ('Rudder is set separately, and should be larger. A twist grip shares a limb ' +
        'with roll: pushing the stick sideways rotates your wrist a little whether you mean it to or not, so a twist ' +
        'axis picks up unintended yaw on every roll. Matching it to pitch and roll makes the aeroplane hunt and jerk ' +
        'in turns. If you fly with pedals instead, set it as tight as the others.') 'perf'))

    $curMain = $(if ($joy.Count -gt 0) { $joy[0].Dead / 100.0 } else { 1.0 })
    $yawRow  = @($joy | Where-Object { $_.Use -eq 'Yaw' } | Select-Object -First 1)
    $curYaw  = $(if ($yawRow.Count -gt 0) { $yawRow[0].Dead / 100.0 } else { 5.0 })
    $script:JoyLive.DzPct = $curMain

    $mkSlider = {
        param([string]$Label, [double]$Start, [bool]$IsMain)
        $g = New-Grid @('Auto','*','Auto')
        $g.Margin = [System.Windows.Thickness]::new(0,12,0,0)
        $lb = New-TB $Label -Size 12.5; $lb.MinWidth = 110; $lb.VerticalAlignment = 'Center'
        Add-Cell $g $lb 0 | Out-Null
        $sl = New-Object System.Windows.Controls.Slider
        $sl.Minimum = 0; $sl.Maximum = 20; $sl.Value = $Start
        $sl.TickFrequency = 0.5; $sl.IsSnapToTickEnabled = $true
        $sl.Width = 300; $sl.HorizontalAlignment = 'Left'
        $sl.Margin = [System.Windows.Thickness]::new(12,0,12,0); $sl.VerticalAlignment = 'Center'
        Add-Cell $g $sl 1 | Out-Null
        $v = New-TB ('{0:0.0}%' -f $Start) -Size 13 -Brush 'Accent'
        $v.VerticalAlignment = 'Center'; $v.MinWidth = 50
        Add-Cell $g $v 2 | Out-Null
        $sl.Add_ValueChanged({
            param($s, $e)
            $v.Text = ('{0:0.0}%' -f $s.Value)
            # Only the pitch/roll slider drives the red band on the bars -
            # those bars are the raw hardware axes, and yaw is one of them.
            if ($IsMain) { $script:JoyLive.DzPct = $s.Value; Update-JoyDeadBands }
        }.GetNewClosure())
        @{ Grid = $g; Slider = $sl }
    }

    $mainS = & $mkSlider 'Pitch and roll' $curMain $true
    $yawS  = & $mkSlider 'Rudder / twist' $curYaw  $false
    [void]$p.Children.Add($mainS.Grid)
    [void]$p.Children.Add($yawS.Grid)
    Update-JoyDeadBands

    $ab = New-Stack -Orientation 'Horizontal' -Margin ([System.Windows.Thickness]::new(0,14,0,0))
    $apply = New-Btn 'Apply these deadzones' 'BtnPrimary' $null {
        $v  = [int][math]::Round($mainS.Slider.Value * 100.0)
        $vy = [int][math]::Round($yawS.Slider.Value * 100.0)
        if (Set-JoyDeadzone $v $vy) {
            Invalidate-Page 'Joystick and axes'
            Select-Nav 'Joystick and axes'
        }
    }.GetNewClosure()
    [void]$ab.Children.Add($apply)
    $note = New-TB 'Writes straight to the game''s input file, backing it up first. It does not wait for Save.' -Size 11.5 -Brush 'Muted' -Wrap
    $note.Margin = [System.Windows.Thickness]::new(12,0,0,0); $note.VerticalAlignment = 'Center'
    [void]$ab.Children.Add($note)
    [void]$p.Children.Add($ab)

    $pb = New-Stack -Orientation 'Horizontal' -Margin ([System.Windows.Thickness]::new(0,10,0,0))
    foreach ($pr in @(
        @{ K='precision'; L='Fighters 1% / 5%' }
        @{ K='standard';  L='Heavy 3% / 6%' }
        @{ K='target';    L='External curves 0%' }
        @{ K='stock';     L='Stock 7.5%' }
        @{ K='pedals';    L='Rudder pedals 1%' })) {
        $b = New-Btn $pr.L 'BtnGhost' $pr.K {
            param($s, $e)
            if (Invoke-JoyTool 'BOB2_Sensitivity.ps1' @($s.Tag)) {
                Invalidate-Page 'Joystick and axes'
                Select-Nav 'Joystick and axes'
            }
        }
        $b.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        [void]$pb.Children.Add($b)
    }
    [void]$p.Children.Add($pb)

    # --- set up -------------------------------------------------------
    [void]$p.Children.Add((New-SectionHeader 'SET UP' 'Detect the stick and write a sensible starting point.'))
    $b1 = New-Stack -Orientation 'Horizontal'
    [void]$b1.Children.Add((New-Btn 'Set up my stick' 'BtnPrimary' $null {
        if (Invoke-JoyTool 'BOB2_Controls.ps1' @('-Apply')) {
            Invalidate-Page 'Joystick and axes'
            Select-Nav 'Joystick and axes'
        }
    }))
    $t1 = New-TB 'Detects what is plugged in, writes the axis mapping, and applies the recommended button preset.' -Size 11.5 -Brush 'Muted' -Wrap
    $t1.Margin = [System.Windows.Thickness]::new(12,0,0,0); $t1.VerticalAlignment = 'Center'
    [void]$b1.Children.Add($t1)
    [void]$p.Children.Add($b1)

    # --- curves -------------------------------------------------------
    [void]$p.Children.Add((New-SectionHeader 'CURVES' 'Not something this game can do.'))
    [void]$p.Children.Add((New-Note ('BOB2 has no joystick response curves. Its entire input path is a deadzone, then a ' +
        'multiply and an offset - no exponent, no curve table anywhere on a joystick axis. Curves must be applied ' +
        'before the game sees the stick, by Thrustmaster TARGET or Joystick Gremlin with vJoy. Both present a virtual ' +
        'stick that BOB2 then reads as linear.') 'info'))
    [void]$p.Children.Add((New-Note ('A ready-made TARGET script for the T.16000M, with separate curves for the ' +
        'Spitfire, the Bf109 and the heavies, is in the TARGET folder of this fix package. If you enable it, come back ' +
        'and press "Set up my stick" - the virtual device has a different GUID - and set the deadzone here to 0.') 'info'))

    New-Scroll $p
}

# Writes one deadzone to every joystick axis. Mirrors what
# BOB2_Sensitivity.ps1 does, but for an arbitrary value from the slider.
function Set-JoyDeadzone {
    param([int]$Units, [int]$YawUnits = -1)
    if ($YawUnits -lt 0) { $YawUnits = $Units }
    if (Get-Process -Name 'Bob' -ErrorAction SilentlyContinue) {
        [void][System.Windows.MessageBox]::Show($Win,
            'The game is running. It rewrites its input configuration when it exits, so this would be discarded. Close it first.',
            'Deadzone', 'OK', 'Warning')
        return $false
    }
    $cfg = Join-Path $script:GameFolder 'SAVEGAME\inputcfg.dat'
    if (-not (Test-Path -LiteralPath $cfg)) {
        [void][System.Windows.MessageBox]::Show($Win, 'inputcfg.dat not found.', 'Deadzone', 'OK', 'Warning')
        return $false
    }
    $b = [System.IO.File]::ReadAllBytes($cfg)
    $n = 0
    for ($i = 0; $i -lt [math]::Floor($b.Length / $script:JoyStride); $i++) {
        $o = $i * $script:JoyStride
        if ([BitConverter]::ToInt32($b, $o + 8) -ne 2) { continue }   # joystick rows only
        # Record 2 is yaw. A twist grip needs more than pitch and roll do,
        # because rolling the stick rotates your wrist with it.
        $u = $(if ($i -eq 2) { $YawUnits } else { $Units })
        [Array]::Copy([BitConverter]::GetBytes([int]$u), 0, $b, $o + 12, 4)
        $n++
    }
    if ($n -eq 0) {
        [void][System.Windows.MessageBox]::Show($Win,
            'No joystick axes are configured yet. Use "Set up my stick" first, then start the game once.',
            'Deadzone', 'OK', 'Warning')
        return $false
    }
    $dir = Join-Path $script:GameFolder '_AxisProfiles'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Copy-Item $cfg (Join-Path $dir ('backup_' + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '.dat')) -Force
    [System.IO.File]::WriteAllBytes($cfg, $b)
    return $true
}


function Build-AboutPage {
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Margin = '0,0,0,40'

    [void]$sp.Children.Add((New-TB 'WHAT THIS IS' -Style 'SectionTitle'))
    [void]$sp.Children.Add((New-TB ("An unofficial community mod for Battle of Britain II: Wings of Victory. " +
        "It gets the game running properly on Windows 10 and 11, and replaces the game's own options screens, " +
        "which were drawn for a monitor 1024 pixels wide and clip on anything modern.") -Style 'RowHint'))

    [void]$sp.Children.Add((New-TB 'WHAT THIS IS NOT' -Style 'SectionTitle'))
    [void]$sp.Children.Add((New-TB ("Not affiliated with, endorsed by or connected to A2A Simulations, Shockwave " +
        "Productions or Rowan Software. Not to be confused with the community ""BOB2 Windows 10 Patch"", which is a " +
        "separate project built on the 2.01 executable that replaces textures, sounds and aircraft models. This mod " +
        "is for patch 2.13, keeps 2.13's AI, ground objects and MultiSkin, and replaces no game content at all.") -Style 'RowHint'))

    [void]$sp.Children.Add((New-TB 'CREDITS' -Style 'SectionTitle'))
    foreach ($line in @(
        'Battle of Britain II: Wings of Victory - Rowan Software / Shockwave Productions',
        'Patch 2.13 - the BOB2 Development Group',
        'dgVoodoo2 - Dege',
        'Icons - Lucide, ISC licence',
        'Launcher photograph - IWM HU 54418, public domain',
        'Settings photograph - IWM CL186, public domain')) {
        [void]$sp.Children.Add((New-TB $line -Style 'Mono'))
    }
    return (New-Scroll $sp)
}

function Build-Page {
    param([string]$Name)
    switch ($Name) {
        'Overview'     { return (Build-OverviewPage) }
        'GFX screen'   { return (Build-GfxPage) }
        'Key bindings' { return (Build-KeysPage) }
        'Joystick and axes' { return (Build-JoystickPage) }
        'All settings' { return (Build-AllPage) }
        'About'        { return (Build-AboutPage) }
        default        { return (Build-SettingsPage $Name $script:Pages[$Name]) }
    }
}

function Invalidate-Page {
    # Drop a cached page AND take it out of the visual tree. Removing it from
    # the cache alone left the old copy parented in PageHost, so every reset
    # added another dead copy underneath - each with its own controls that
    # the live joystick poll could still be holding references to.
    param([string]$Name)
    if ($script:PageCache.ContainsKey($Name)) {
        $old = $script:PageCache[$Name]
        if ($old -and $PageHost) { [void]$PageHost.Children.Remove($old) }
        [void]$script:PageCache.Remove($Name)
    }
}

function Show-Page {
    param([string]$Name)
    if (-not $script:PageCache.ContainsKey($Name)) {
        $Win.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            $p = Build-Page $Name
            $p.Visibility = 'Collapsed'
            [void]$PageHost.Children.Add($p)
            $script:PageCache[$Name] = $p
        } finally { $Win.Cursor = $null }
    }
    foreach ($c in $PageHost.Children) { $c.Visibility = 'Collapsed' }
    $script:PageCache[$Name].Visibility = 'Visible'

    # The joystick page polls the stick 20 times a second. Leaving that
    # running behind another page is pure waste, so it follows the page.
    if ($Name -eq 'Joystick and axes') { Start-JoyLive } else { Stop-JoyLive }

    $HeadTitle.Text = $Name
    $def = $script:NavDefs | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    $sub = $def.Sub
    if (-not $sub -and $script:Pages.Contains($Name)) { $sub = $script:Pages[$Name].Sub }
    $HeadSub.Text = $sub
    $HeadSub.Visibility = $(if ($sub) { 'Visible' } else { 'Collapsed' })
    if ($Name -eq 'Overview') { Refresh-Health }
}

foreach ($nd in $script:NavDefs) {
    if ($nd.Caption) {
        $cap = New-TB $nd.Caption -Style 'Eyebrow'
        $cap.Margin = [System.Windows.Thickness]::new(22,20,0,7)
        [void]$NavPanel.Children.Add($cap)
    }
    $rb = New-Object System.Windows.Controls.RadioButton
    $rb.Style = Res 'NavItem'
    # Icon column. One glyph, one meaning, across both windows: gauge is
    # frame rate everywhere, joystick is the stick everywhere.
    $icoKey = $script:NavIcons[$nd.Name]
    if ($icoKey) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        $vb = New-Object System.Windows.Controls.Viewbox
        $vb.Width = 20; $vb.Height = 20; $vb.Margin = '0,0,12,0'
        $vb.VerticalAlignment = 'Center'
        $cv = New-Object System.Windows.Controls.Canvas
        $cv.Width = 24; $cv.Height = 24
        $pt = New-Object System.Windows.Shapes.Path
        $pt.Data = Res $icoKey
        $pt.Fill = $null
        $pt.Stroke = Res 'Dim'
        $pt.StrokeThickness = 1.9
        $pt.StrokeStartLineCap = 'Round'; $pt.StrokeEndLineCap = 'Round'; $pt.StrokeLineJoin = 'Round'
        [void]$cv.Children.Add($pt)
        $vb.Child = $cv
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $nd.Name; $tb.VerticalAlignment = 'Center'
        [void]$row.Children.Add($vb); [void]$row.Children.Add($tb)
        $rb.Content = $row
    } else {
        $rb.Content = $nd.Name
    }
    $rb.GroupName = 'nav'
    $rb.Tag = $nd.Name
    $rb.Add_Checked({ param($s, $e) Show-Page $s.Tag })
    [void]$NavPanel.Children.Add($rb)
}


# =============================================================================
#  TEXT SIZE
#  A ScaleTransform on the window's root content, which WPF gives away almost
#  free and this audience needs more than any other feature here. Three stops.
#  The window has to grow with it or the content simply clips - and it is
#  clamped to the working area, because 1.30 on a 1366-wide laptop would open
#  a window wider than the screen.
# =============================================================================
$script:UiScaleFile = Join-Path $script:ScriptDir 'BOB2_Config.textsize'

function Get-SavedUiScale {
    try {
        if (Test-Path $script:UiScaleFile) {
            $v = [double]((Get-Content $script:UiScaleFile -First 1).Trim())
            if ($v -ge 1.0 -and $v -le 1.3) { return $v }
        }
    } catch { }
    return 1.0
}

function Set-UiScale {
    param([double]$Scale, [switch]$Save)
    $script:UiScale = $Scale

    # NO outer scroll viewer here, deliberately. Wrapping the whole window in
    # one hands the page's own ScrollViewer an INFINITE height: it then never
    # has anything to scroll, and a ScrollViewer swallows the mouse wheel even
    # when it cannot move - so the wheel stopped working anywhere in the
    # window. Each page already scrolls through New-Scroll; the header, rail
    # and status bar are meant to stay put.
    $root = $Win.Content
    if ($Scale -eq 1.0) {
        $root.LayoutTransform = $null
    } else {
        $root.LayoutTransform = New-Object Windows.Media.ScaleTransform($Scale, $Scale)
    }

    # Resize AND reposition. Growing a window whose top-left stays put pushes
    # its bottom and right off the screen - and with WindowStyle="None" there
    # is no resize border to drag it back with, which is what made the app
    # hard to navigate after a size change. Keep it inside the work area.
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($Win.WindowState -eq 'Maximized') { $Win.WindowState = 'Normal' }

    $newW = [Math]::Min(1360 * $Scale, $wa.Width)
    $newH = [Math]::Min(900  * $Scale, $wa.Height)

    # Minimums must never exceed the size we are about to set, or WPF will
    # quietly enlarge the window past the screen to satisfy them.
    $Win.MinWidth  = [Math]::Min(1100 * $Scale, $newW)
    $Win.MinHeight = [Math]::Min(720  * $Scale, $newH)
    $Win.Width     = $newW
    $Win.Height    = $newH

    # Keep the centre where it was, then clamp to the work area, so the
    # window grows outwards rather than off the bottom right.
    $cx = $Win.Left + ($Win.ActualWidth  / 2)
    $cy = $Win.Top  + ($Win.ActualHeight / 2)
    if ([double]::IsNaN($cx) -or $Win.ActualWidth -le 0) {
        $cx = $wa.Left + ($wa.Width / 2); $cy = $wa.Top + ($wa.Height / 2)
    }
    $Win.Left = [Math]::Max($wa.Left, [Math]::Min($cx - ($newW / 2), $wa.Right  - $newW))
    $Win.Top  = [Math]::Max($wa.Top,  [Math]::Min($cy - ($newH / 2), $wa.Bottom - $newH))

    # Mark the active stop. Brass is "the thing you are on" everywhere else
    # in this window, so it means the same here.
    foreach ($pair in @(@('BtnSize100',1.0), @('BtnSize115',1.15), @('BtnSize130',1.30))) {
        $b = $Win.FindName($pair[0])
        if ($b) { $b.Foreground = $(if ([Math]::Abs($Scale - $pair[1]) -lt 0.01) { Res 'Accent' } else { Res 'Muted' }) }
    }

    if ($Save) {
        try { Set-Content -Path $script:UiScaleFile -Value ([string]$Scale) -Encoding ASCII } catch { }
    }
}

foreach ($pair in @(@('BtnSize100',1.0), @('BtnSize115',1.15), @('BtnSize130',1.30))) {
    $b = $Win.FindName($pair[0])
    if ($b) {
        $sc = [double]$pair[1]
        $b.Add_Click({ Set-UiScale -Scale $sc -Save }.GetNewClosure())
    }
}

# Cog panel: the few facts worth having to hand without leaving the page.
$gi = $Win.FindName('CogInfoGame')
if ($gi) { $gi.Text = "Game folder: $script:GameFolder" }
$gf = $Win.FindName('CogInfoFiles')
if ($gf) { $gf.Text = 'Edits bdg.txt, keys.txt, settings.cfg and Weather.cfg directly. Every file is backed up before it changes.' }
$gv = $Win.FindName('CogInfoVer')
if ($gv) {
    $v = 'unknown'
    try {
        $vf = Join-Path $script:GameFolder 'BOB2-Win11-Fix.version'
        if (Test-Path $vf) {
            $m = Select-String -Path $vf -Pattern '^FixVersion\s*=\s*(.+)$' -ErrorAction SilentlyContinue
            if ($m) { $v = $m.Matches[0].Groups[1].Value.Trim() }
        }
    } catch { }
    $gv.Text = "Mod version $v"
}
$bf = $Win.FindName('BtnCogFolder')
if ($bf) { $bf.Add_Click({ Start-Process explorer.exe $script:GameFolder }) }

$bandPath = Join-Path $script:ScriptDir 'assets\cl186.jpg'
if (Test-Path $bandPath) {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.UriSource = New-Object System.Uri($bandPath)
    $bmp.DecodePixelWidth = 1800
    $bmp.CacheOption = 'OnLoad'
    $bmp.EndInit()
    $Win.FindName('BandBg').Source = $bmp
}

Set-UiScale -Scale (Get-SavedUiScale)

# Navigate by checking the nav radio rather than calling Show-Page directly,
# so the rail highlight always agrees with the page on screen.
function Select-Nav {
    param([string]$Name)
    foreach ($c in $NavPanel.Children) {
        if ($c -is [System.Windows.Controls.RadioButton] -and $c.Tag -eq $Name) {
            if ($c.IsChecked) { Show-Page $Name } else { $c.IsChecked = $true }
            return
        }
    }
}

# =============================================================================
#  STATUS BAR AND SAVING
# =============================================================================
function Get-InvalidSettings {
    $bad = @()
    foreach ($k in (Get-ChangedBdg)) {
        $e = $script:Bdg[$k]
        if ((Test-Numeric $e.Original) -and -not (Test-Numeric $e.Value)) { $bad += $k }
    }
    ,$bad
}

function Update-Status {
    $n   = Get-ChangeCount
    $bad = Get-InvalidSettings
    if ($bad.Count -gt 0) {
        $StatusDot.Fill = Res 'Danger'
        $StatusText.Text = "$($bad.Count) value$(if ($bad.Count -ne 1) {'s'} else {''}) not valid: " + (($bad | Select-Object -First 3) -join ', ')
        $StatusText.Foreground = Res 'Danger'
        $BtnSave.IsEnabled = $false
        $BtnRevert.IsEnabled = $true
        return
    }
    $StatusText.Foreground = Res 'Muted'
    if ($n -eq 0) {
        $StatusDot.Fill = Res 'Dim'
        $StatusText.Text = 'No unsaved changes'
        $BtnSave.IsEnabled = $false
        $BtnRevert.IsEnabled = $false
    } else {
        $StatusDot.Fill = Res 'Accent'
        $bits = @()
        $b = (Get-ChangedBdg).Count;  if ($b) { $bits += "$b setting$(if ($b -ne 1) {'s'} else {''})" }
        $k = (Get-ChangedKeys).Count; if ($k) { $bits += "$k binding$(if ($k -ne 1) {'s'} else {''})" }
        $w = (Get-ChangedWx).Count;   if ($w) { $bits += "$w weather value$(if ($w -ne 1) {'s'} else {''})" }
        if (Test-CfgChanged)          { $bits += 'GFX options' }
        $StatusText.Text = 'Unsaved: ' + ($bits -join ', ')
        $BtnSave.IsEnabled = $true
        $BtnRevert.IsEnabled = $true
    }
}
$script:OnChange = { Update-Status }

function Show-SaveResult {
    param($Result, [string]$ErrorText = $null)
    $p = New-Stack
    if ($ErrorText) {
        [void]$p.Children.Add((New-TB 'COULD NOT SAVE' -Style 'Eyebrow' -Brush 'Danger'))
        [void]$p.Children.Add((New-TB 'Nothing was written' -Style 'H1' -Margin ([System.Windows.Thickness]::new(0,6,0,0))))
        [void]$p.Children.Add((New-Note $ErrorText 'critical'))
        [void]$p.Children.Add((New-Note ('The usual cause is that the game is still running, or the folder is ' +
            'read only because it sits under Program Files.') 'info'))
    } else {
        [void]$p.Children.Add((New-TB 'SAVED' -Style 'Eyebrow' -Brush 'Good'))
        [void]$p.Children.Add((New-TB 'Written to disk' -Style 'H1' -Margin ([System.Windows.Thickness]::new(0,6,0,0))))
        foreach ($r in $Result.Report) {
            $g = New-Grid @('*','Auto')
            $g.Margin = [System.Windows.Thickness]::new(0,10,0,10)
            $nm = New-TB $r.File -Size 12.5; $nm.FontFamily = 'Consolas'
            Add-Cell $g $nm 0 | Out-Null
            Add-Cell $g (New-TB ("$($r.N) $($r.What)$(if ($r.N -ne 1) {'s'} else {''}) changed") -Size 12 -Brush 'Good') 1 | Out-Null
            [void]$p.Children.Add((New-Bd $g -Border 'LineSoft' -Thickness ([System.Windows.Thickness]::new(0,0,0,1))))
        }
        $bk = New-TB ('Backups of the previous versions: ' + $Result.Backup) -Size 11.5 -Brush 'Dim' -Wrap
        $bk.FontFamily = 'Consolas'
        $bk.Margin = [System.Windows.Thickness]::new(0,16,0,0)
        [void]$p.Children.Add($bk)
        [void]$p.Children.Add((New-Note 'Start the game now. Do not save again from this tool while the game is running.' 'info'))
    }
    $bar = New-Stack -Orientation 'Horizontal' -HAlign 'Right' -Margin ([System.Windows.Thickness]::new(0,22,0,0))
    [void]$bar.Children.Add((New-Btn 'Close' 'BtnPrimary' $null { Hide-Overlay }))
    [void]$p.Children.Add($bar)
    Show-Overlay $p
}

function Confirm-Save {
    $p = New-Stack
    [void]$p.Children.Add((New-TB 'SAVE' -Style 'Eyebrow'))
    [void]$p.Children.Add((New-TB 'Write changes to the game folder' -Style 'H1' -Margin ([System.Windows.Thickness]::new(0,6,0,0))))

    $files = @()
    if ((Get-ChangedBdg).Count)  { $files += "bdg.txt  ($((Get-ChangedBdg).Count) settings)" }
    if ((Get-ChangedKeys).Count) { $files += "KEYBOARD\keys.txt  ($((Get-ChangedKeys).Count) bindings)" }
    if ((Get-ChangedWx).Count)   { $files += "Weather\Weather.cfg  ($((Get-ChangedWx).Count) values)" }
    if (Test-CfgChanged)         { $files += 'SAVEGAME\settings.cfg  (GFX options)' }
    foreach ($f in $files) {
        $t = New-TB $f -Size 12.5
        $t.FontFamily = 'Consolas'
        $t.Margin = [System.Windows.Thickness]::new(0,10,0,0)
        [void]$p.Children.Add($t)
    }
    [void]$p.Children.Add((New-Note ('The game must not be running. It rewrites all of these files on exit and ' +
        'would discard everything written here.') 'perf'))
    [void]$p.Children.Add((New-Note 'A copy of each file is placed in _ConfigBackups first.' 'info'))

    $bar = New-Stack -Orientation 'Horizontal' -HAlign 'Right' -Margin ([System.Windows.Thickness]::new(0,22,0,0))
    [void]$bar.Children.Add((New-Btn 'Cancel' 'BtnGhost' $null { Hide-Overlay }))
    $go = New-Btn 'Write the files' 'BtnPrimary' $null {
        Hide-Overlay
        try {
            $res = Save-All
            Update-Status
            Refresh-Health
            # Land back on Overview after a successful write: it is where the
            # health checks and the file list live, so it is the page that
            # reflects what just happened. On failure stay put, so the page
            # holding the unsaved change is still in front of you.
            Select-Nav 'Overview'
            Show-SaveResult $res
        } catch {
            Show-SaveResult $null $_.Exception.Message
        }
    }
    $go.Margin = [System.Windows.Thickness]::new(10,0,0,0)
    [void]$bar.Children.Add($go)
    [void]$p.Children.Add($bar)
    Show-Overlay $p
}

$BtnSave.Add_Click({ Confirm-Save })

# Back to the launcher. Unsaved work is the only thing that makes this
# risky, so say so rather than discarding it silently. The launcher is
# only started if one is not already open - otherwise this would stack a
# second window every time.
$BtnLauncher.Add_Click({
    if ((Get-ChangeCount) -gt 0) {
        $r = [System.Windows.MessageBox]::Show($Win,
            "You have unsaved changes. Leave without saving?",
            'Back to launcher', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
    }
    $bat = $null
    foreach ($d in @($script:ScriptDir, $script:GameFolder,
                     (Join-Path $script:GameFolder 'BOB2-Win11-Fix'))) {
        if (-not $d) { continue }
        $c = Join-Path $d 'BOB2.bat'
        if (Test-Path -LiteralPath $c) { $bat = $c; break }
    }
    $open = Get-Process powershell -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -eq 'Battle of Britain II' }
    if (-not $open -and $bat) {
        Start-Process -FilePath $bat -WorkingDirectory (Split-Path -Parent $bat)
    }
    $Win.Close()
})

$BtnRevert.Add_Click({
    foreach ($k in $script:BdgOrder) { $script:Bdg[$k].Value = $script:Bdg[$k].Original }
    foreach ($a in $script:KeyOrder) { $script:Keys[$a].Kb = @($script:Keys[$a].OrigKb) }
    foreach ($k in @($script:Wx.Keys)) { $script:Wx[$k].Value = $script:Wx[$k].Original }
    if ($script:CfgOrig) { $script:CfgBytes = [byte[]]$script:CfgOrig.Clone() }
    # Rebuild every page so the controls match the reverted state.
    foreach ($n in @($script:PageCache.Keys)) {
        [void]$PageHost.Children.Remove($script:PageCache[$n])
        $script:PageCache.Remove($n)
    }
    $script:Rows = @{}; $script:KeyUi = @{}; $script:KeyGroups = @(); $script:ConflictBar = $null
    $sel = $NavPanel.Children | Where-Object { $_ -is [System.Windows.Controls.RadioButton] -and $_.IsChecked }
    Update-Status
    if ($sel) { Show-Page $sel.Tag }
})

$Overlay.Add_MouseLeftButtonDown({
    param($s, $e)
    # Click the scrim to dismiss, but not a click inside the card.
    if ($e.OriginalSource -eq $s) { Hide-Overlay }
})

$BtnChangeFolder.Add_Click({
    $f = Request-GameFolder
    if (-not $f) { return }
    if (-not (Test-GameFolder $f)) { return }
    $script:GameFolder = $f
    Save-GameFolder $f
    Load-AllFiles $f
    $FolderText.Text = $f
    foreach ($n in @($script:PageCache.Keys)) {
        [void]$PageHost.Children.Remove($script:PageCache[$n])
        $script:PageCache.Remove($n)
    }
    $script:Rows = @{}; $script:KeyUi = @{}; $script:KeyGroups = @(); $script:ConflictBar = $null
    Update-Status
    Show-Page 'Overview'
    ($NavPanel.Children | Where-Object { $_ -is [System.Windows.Controls.RadioButton] } | Select-Object -First 1).IsChecked = $true
})

$Win.Add_Closing({
    param($s, $e)
    if ((Get-ChangeCount) -le 0) { return }
    $r = [System.Windows.MessageBox]::Show(
        'There are unsaved changes. Close without writing them?',
        'Battle of Britain II - Configuration',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning)
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { $e.Cancel = $true }
})

# =============================================================================
#  START
# =============================================================================
$script:GameFolder = Find-GameFolder
if (-not $script:GameFolder) {
    [void][System.Windows.MessageBox]::Show(
        "The Battle of Britain II folder could not be found automatically.`n`nSelect bdg.txt in your installation on the next screen.",
        'Battle of Britain II - Configuration',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information)
    $script:GameFolder = Request-GameFolder
}
if (-not (Test-GameFolder $script:GameFolder)) {
    [void][System.Windows.MessageBox]::Show(
        'No bdg.txt was found, so there is nothing to configure.',
        'Battle of Britain II - Configuration',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error)
    return
}
Save-GameFolder $script:GameFolder
Load-AllFiles $script:GameFolder
$FolderText.Text = $script:GameFolder
Update-Status
($NavPanel.Children | Where-Object { $_ -is [System.Windows.Controls.RadioButton] } | Select-Object -First 1).IsChecked = $true
if ($Page) {
    $Win.Add_ContentRendered({ Select-Nav $Page }.GetNewClosure())
}

if ($RenderTo) {
    $Win.Add_ContentRendered({
        $root = $Win.Content
        $root.UpdateLayout()
        $root.Measure([Windows.Size]::new($Win.Width, $Win.Height))
        $root.Arrange([Windows.Rect]::new(0, 0, $Win.Width, $Win.Height))
        $root.UpdateLayout()
        $w = [int][Math]::Ceiling($root.ActualWidth); $h = [int][Math]::Ceiling($root.ActualHeight)
        $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, 'Pbgra32')
        $rtb.Render($root)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($RenderTo); $enc.Save($fs); $fs.Close()
        Write-Host "rendered $w x $h at scale $script:UiScale -> $RenderTo"
        $Win.Close()
    })
    if ($RenderScale -ne 1.0) { Set-UiScale -Scale $RenderScale }
}

[void]$Win.ShowDialog()
