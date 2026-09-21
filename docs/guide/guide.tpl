<title>Modern Fix Handbook</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Zilla+Slab:wght@600;700&family=Barlow:wght@400;500;600&family=Barlow+Condensed:wght@500;600&display=swap">
<style>
:root{
  --ground:#10181E; --panel:#162129; --panel2:#1B2932; --ink:#E6E1D3; --soft:#C3CCC7; --muted:#8FA0A8;
  --brass:#C8973F; --brass-hi:#E2B45A; --rule:#27363F; --green:#8FB56A; --green-bg:#1C2917; --amber:#D08A2E;
  --display:"Zilla Slab", Rockwell, Georgia, serif; --body:"Barlow", "Segoe UI", system-ui, sans-serif;
  --label:"Barlow Condensed", "Bahnschrift SemiCondensed", "Arial Narrow", sans-serif;
  color-scheme:dark;
}
*{box-sizing:border-box}
body{background:var(--ground);color:var(--ink);font-family:var(--body);font-size:17px;line-height:1.6}
.wrap{max-width:1080px;margin:0 auto;padding-inline:20px;padding-block:0 72px}
a{color:var(--brass-hi)}
a:focus-visible,button:focus-visible{outline:2px solid var(--brass-hi);outline-offset:2px}
img{max-width:100%;height:auto;display:block}
.label{font-family:var(--label);font-weight:600;font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--brass)}
h1,h2,h3{font-family:var(--display);font-weight:700;line-height:1.15;margin:0;text-wrap:balance}
h1{font-size:clamp(34px,5.6vw,58px)}
h2{font-size:clamp(26px,3.4vw,36px)}
h3{font-size:21px}
p{margin:0}
.measure{max-width:66ch}

/* masthead */
.mast{display:grid;grid-template-columns:minmax(0,1.05fr) minmax(0,1fr);gap:40px;align-items:center;padding-block:48px 36px;border-bottom:1px solid var(--rule)}
.mast .lede{font-size:19px;color:var(--soft);margin-top:18px}
.mast .kicker{display:flex;flex-wrap:wrap;gap:6px 14px;margin-bottom:14px}
.mast figure{margin:0}
.mast figure img{border:6px solid var(--brass);border-radius:2px}
.mast figcaption{font-size:13px;color:var(--muted);margin-top:8px}
.paths{display:flex;flex-wrap:wrap;gap:12px;margin-top:26px}
.paths a{display:inline-flex;flex-direction:column;gap:2px;text-decoration:none;padding:12px 18px;border-radius:3px;background:var(--panel2);border:1px solid var(--rule);color:var(--ink)}
.paths a:hover{border-color:var(--brass)}
.paths a b{font-family:var(--label);font-weight:600;font-size:15px;letter-spacing:.1em;text-transform:uppercase;color:var(--brass-hi)}
.paths a span{font-size:14px;color:var(--muted)}

section{padding-block:56px 8px}
section > .head{display:flex;flex-direction:column;gap:8px;margin-bottom:26px}
section > .head p{color:var(--soft)}

/* what's new */
.feature{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.35fr);gap:34px;align-items:start;padding-block:30px;border-top:1px solid var(--rule)}
.feature.flip{grid-template-columns:minmax(0,1.35fr) minmax(0,1fr)}
.feature.flip .text{order:2}
.feature .text{display:flex;flex-direction:column;gap:12px}
.feature .text p{color:var(--soft)}
.feature ul{margin:0;padding-left:20px;color:var(--soft)}
.feature li{margin-block:4px}
.shot{border:1px solid var(--rule);border-radius:3px;overflow:hidden;background:var(--panel)}
.shot + .shot{margin-top:14px}
.cap{font-size:13px;color:var(--muted);margin-top:8px}
.pair{display:grid;grid-template-columns:1fr;gap:10px}
.minis{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,300px),1fr));gap:14px;padding-block:30px;border-top:1px solid var(--rule)}
.mini{background:var(--panel);border:1px solid var(--rule);border-radius:3px;padding:18px 20px;display:flex;flex-direction:column;gap:8px}
.mini p{color:var(--soft);font-size:16px}

/* steps */
ol.steps{list-style:none;counter-reset:s;margin:0;padding:0;display:flex;flex-direction:column;gap:0}
ol.steps > li{counter-increment:s;display:grid;grid-template-columns:52px minmax(0,1fr);gap:18px;padding-block:18px;border-top:1px solid var(--rule)}
ol.steps > li::before{content:counter(s);font-family:var(--display);font-weight:700;font-size:30px;color:var(--brass);line-height:1}
ol.steps h3{font-size:19px;margin-bottom:6px}
ol.steps p{color:var(--soft)}
code,.path{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace;font-size:14.5px;background:var(--panel2);border:1px solid var(--rule);border-radius:3px;padding:1px 6px;color:var(--ink);overflow-wrap:anywhere}
pre.tree{font-family:ui-monospace,"Cascadia Mono",Consolas,monospace;font-size:14px;line-height:1.5;background:var(--panel);border:1px solid var(--rule);border-radius:3px;padding:14px 16px;margin:10px 0 0;overflow-x:auto;color:var(--soft)}
pre.tree b{color:var(--brass-hi);font-weight:600}

.twocol{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:30px}
.orders{background:var(--green-bg);border:1px solid #45613A;border-radius:3px;padding:18px 20px;display:flex;flex-direction:column;gap:8px}
.orders .label{color:var(--green)}
.orders p{color:var(--soft)}

/* faq */
.faq{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr));gap:0 34px}
.faq div{padding-block:18px;border-top:1px solid var(--rule);display:flex;flex-direction:column;gap:6px}
.faq h3{font-family:var(--body);font-weight:600;font-size:17.5px}
.faq p{color:var(--soft);font-size:16px}

footer{margin-top:60px;padding-top:22px;border-top:1px solid var(--rule);font-size:14px;color:var(--muted);display:flex;flex-direction:column;gap:6px}

@media (max-width:820px){
  .mast,.feature,.feature.flip,.twocol{grid-template-columns:1fr}
  .feature.flip .text{order:0}
  .mast{padding-block:32px 28px}
}
@media (prefers-reduced-motion:reduce){*{scroll-behavior:auto}}
</style>

<div class="wrap">

<header class="mast">
  <div>
    <div class="kicker"><span class="label">Battle of Britain II</span><span class="label" style="color:var(--muted)">2.13 Modern Fix, version 1.9.2</span></div>
    <h1>The Modern Fix Handbook</h1>
    <p class="lede measure">Everything the mod does, how to install it, and how to fly a career with it: from a fresh Windows 11 install to your first sortie, and your pilot's record after it. Written for new players and for anyone coming from version 1.8.</p>
    <nav class="paths" aria-label="Where to start">
      <a href="#install"><b>New here</b><span>Install it, step by step</span></a>
      <a href="#new"><b>Coming from 1.8</b><span>See what has changed</span></a>
      <a href="#room"><b>Flying a career</b><span>The Squadron Room</span></a>
    </nav>
  </div>
  <figure>
    <img src="@@hero@@" alt="A Spitfire of No. 92 Squadron over the English coast in Battle of Britain II">
    <figcaption>No. 92 Squadron over the coast, running on Windows 11 with the mod.</figcaption>
  </figure>
</header>

<section id="new" aria-labelledby="new-h">
  <div class="head">
    <span class="label">What's new in 1.9</span>
    <h2 id="new-h">A career that starts in the game and comes back to you</h2>
    <p class="measure">Version 1.8 got the game running well. Version 1.9 is about what happens around the flying: getting into your campaign in one click, flying for either side, and a Squadron Room that keeps a proper record of the man in the cockpit.</p>
  </div>

  <article class="feature">
    <div class="text">
      <span class="label">One click into your war</span>
      <h3>PLAY CAMPAIGN opens the game on the campaign map</h3>
      <p>Create your pilot in the Squadron Room and press PLAY CAMPAIGN. The game starts, skips its menus and lands you on the campaign map with everything already set: your side, your squadron or Gruppe, the phase of the war, your role and your name.</p>
      <p>No more working through the campaign screens and preferences by hand, and no more flying with a squadron you did not choose. This works for a new pilot starting his war. For a pilot whose campaign is already under way, the Room tells you which save to load.</p>
    </div>
    <div>
      <div class="shot"><img src="@@raf@@" alt="The RAF dispersal in the Squadron Room for a new pilot of No. 610 Squadron, with his Spitfire DW-E"></div>
      <p class="cap">A new pilot of No. 610 Squadron at Biggin Hill. His Spitfire is on the board from the day he is posted.</p>
    </div>
  </article>

  <article class="feature flip">
    <div class="text">
      <span class="label">Fly for the Luftwaffe</span>
      <h3>The German side of the Squadron Room</h3>
      <p>Everything the RAF side has, the Luftwaffe side now has too, in its own form:</p>
      <ul>
        <li>The Gruppen on a map of the Channel front, changing with the date.</li>
        <li>The Bf 109 E and the Bf 110. A Zerstörer pilot has his Bordfunker beside him, with his own rank, record and photograph.</li>
        <li>The Flugbuch (log book), the Staffel roster, and the Morgenmeldung each morning.</li>
      </ul>
    </div>
    <div>
      <div class="shot"><img src="@@lw@@" alt="The Luftwaffe ready room for a Bf 110 pilot of III./ZG 26 and his Bordfunker"></div>
      <p class="cap">A Bf 110 crew of III./ZG 26: the pilot, his Bordfunker, and their aircraft with its code 3U+DR.</p>
      <div class="shot"><img src="@@gruppen@@" alt="The Gruppen map of the Channel front on 12 August 1940"></div>
      <p class="cap">The Gruppen on the Channel front, by date.</p>
    </div>
  </article>

  <article class="feature">
    <div class="text">
      <span class="label">The aeroplane the game gives you</span>
      <h3>The right letter, number and camouflage</h3>
      <p>The game decides which aircraft you fly on each sortie, and the Squadron Room now follows it. When you come back from a sortie, your code letter (RAF) or your number and its colour (Luftwaffe) are the ones you actually flew.</p>
      <p>Every German side view is painted from the game's own skin textures, so the camouflage matches what you saw in the air. That is 125 Bf 109 E skins and 12 Bf 110 skins.</p>
    </div>
    <div class="pair">
      <div class="shot"><img src="@@sv109@@" alt="A Bf 109 E side view of II./JG 26 painted from the game's own skin"></div>
      <div class="shot"><img src="@@sv110@@" alt="A Bf 110 side view painted from the game's own grey green skin"></div>
      <p class="cap">A II./JG 26 Bf 109 E and a Bf 110, both painted from the game's textures.</p>
    </div>
  </article>

  <article class="feature flip">
    <div class="text">
      <span class="label">A personal record</span>
      <h3>Click your photograph</h3>
      <p>Every pilot now has a first name and a surname, and a personal record behind his portrait. It gives when and where he was born and how he came to fly: school, the flying training schools, and the entry his commanding officer found in his file when he arrived.</p>
      <p>The training routes are the real ones men followed in 1940. The man himself is invented. Type over any of it and press SAVE, or press WRITE ANOTHER for a different past. Your Bordfunker has a record of his own.</p>
    </div>
    <div>
      <div class="shot"><img src="@@record@@" alt="The personal record window for a Bf 110 pilot, with first name, birth date, birthplace and his story"></div>
    </div>
  </article>

  <article class="feature">
    <div class="text">
      <span class="label">Two morning papers</span>
      <h3>The Morning Bulletin and the Morgenmeldung</h3>
      <p>Each paper now carries what really happened the day before in 1940:</p>
      <ul>
        <li>The raids and the weather.</li>
        <li>The figures Fighter Command claimed that night, beside the losses the records showed after the war.</li>
        <li>The other news a British or German reader would have seen that morning.</li>
      </ul>
      <p>All 114 days from 10 July to 31 October 1940 are covered. The band is clearly marked as the record of 1940, so it is never mixed up with your own campaign's figures.</p>
    </div>
    <div>
      <div class="shot"><img src="@@rafpaper@@" alt="The Morning Bulletin for 16 August 1940 with the record of 15 August"></div>
      <div class="shot"><img src="@@lwpaper@@" alt="The Morgenmeldung for 16 August 1940"></div>
    </div>
  </article>

  <div class="minis">
    <div class="mini"><span class="label">Joysticks</span><h3>New sticks set themselves up</h3><p>Plug in a different joystick or HOTAS and the launcher notices, and offers to set it up for you. No more controls that work in Windows but not in the game.</p></div>
    <div class="mini"><span class="label">The picture</span><h3>No grid lines, sharper distance</h3><p>The lines across the terrain are gone (they came from forced antialiasing), distant ground is sharper with larger terrain textures, and ReShade's Balanced preset sharpens the image.</p></div>
    <div class="mini"><span class="label">Frame rate</span><h3>Two measured patches</h3><p>Optional patches to the game's cloud lighting and line drawing. The cloud one raised the average frame rate by 16% in testing. Both stay off by default while they are tested on more machines.</p></div>
    <div class="mini"><span class="label">Fewer alarms</span><h3>No more false warnings</h3><p>The launcher no longer says the graphics settings file looks damaged. If that file ever really is broken, PLAY quietly puts a good copy back and keeps the old one beside it.</p></div>
  </div>
</section>

<section id="install" aria-labelledby="install-h">
  <div class="head">
    <span class="label">New here</span>
    <h2 id="install-h">Installing the mod</h2>
    <p class="measure">You need a licensed copy of Battle of Britain II. The mod includes everything else, including the graphics translator (dgVoodoo2), so there is nothing else to download.</p>
  </div>
  <ol class="steps">
    <li><div><h3>Unblock the download</h3><p>Right click the zip you downloaded, choose Properties, tick <b>Unblock</b> and press OK. If you skip this, Windows may stop the launcher opening.</p></div></li>
    <li><div><h3>Extract it into your game folder</h3><p>The zip holds one folder, <span class="path">BOB2-Win11-Fix</span>. Put that whole folder inside your Battle of Britain II folder, next to <span class="path">Bob.exe</span>:</p>
      <pre class="tree">D:\Battle of Britain II\
    Bob.exe
    bdg.txt
    <b>BOB2-Win11-Fix\</b>      &lt;- the folder from the zip</pre></div></li>
    <li><div><h3>Start the launcher</h3><p>Open the folder and double click <span class="path">_CLICK HERE TO START.bat</span>, the first file in it.</p></div></li>
    <li><div><h3>Run the setup wizard</h3><p>The wizard puts in the graphics translator, sets the right resolution, applies the Windows 11 fixes and sets up your joystick. It explains each step before it changes anything, and backs up every file first. If your game is not yet at version 2.13, put the 2.13 patch file in the <span class="path">BOB2-Win11-Fix</span> folder first. The wizard applies it for you, so do not run it yourself.</p></div></li>
    <li><div><h3>Press PLAY</h3><p>That's it. To fly a career, open the Squadron Room instead (see below).</p></div></li>
  </ol>

  <div class="head" style="margin-top:44px">
    <span class="label">Coming from 1.8</span>
    <h2>Updating</h2>
  </div>
  <ol class="steps">
    <li><div><h3>Delete the old BOB2-Win11-Fix folder</h3><p>It holds nothing of yours. Your pilots and their records are kept in the <span class="path">SquadronRoom</span> folder beside <span class="path">Bob.exe</span>, and your backups and joystick settings are kept elsewhere too, so none of them are touched.</p></div></li>
    <li><div><h3>Put the new folder in its place</h3><p>Unblock and extract the new zip exactly as in the steps above.</p></div></li>
    <li><div><h3>Start the launcher and click the upgrade line</h3><p>At the foot of the launcher it will say <b>Mod 1.8.4 installed, 1.9.2 available, click here to upgrade</b>. Click it, and the game folder is brought up to date. Your settings and pilots carry over.</p></div></li>
  </ol>
</section>

<section id="room" aria-labelledby="room-h">
  <div class="head">
    <span class="label">Flying a career</span>
    <h2 id="room-h">The Squadron Room, step by step</h2>
    <p class="measure">The Squadron Room is where your pilot lives between sorties. You fly in the game as usual, and the Room keeps the record: log book, rank, awards, crew, aircraft and the morning paper.</p>
  </div>
  <div class="twocol">
    <ol class="steps">
      <li><div><h3>Open the Squadron Room</h3><p>From the launcher. Choose the RAF or the Luftwaffe with the switch at the top.</p></div></li>
      <li><div><h3>Choose your unit and your date</h3><p>Pick a phase of the Battle, then a squadron on the Fighter Command board, or a Gruppe on the map of the Channel front.</p></div></li>
      <li><div><h3>Report for duty</h3><p>Give your first name and your surname (both are needed), choose whether you arrive as an NCO or with a commission, and pick your photograph. On the German side you also choose your aircraft's number, or its letter on a Bf 110.</p></div></li>
      <li><div><h3>Press PLAY CAMPAIGN</h3><p>The game opens on the campaign map with your squadron, phase and name already set. Fly the day.</p></div></li>
      <li><div><h3>Come back to the Room</h3><p>Your sortie is in the log book, your aircraft shows the letter or number you actually flew, and rank and awards follow from what you do.</p></div></li>
    </ol>
    <div style="display:flex;flex-direction:column;gap:16px">
      <div class="orders">
        <span class="label">Your orders, as the Room gives them</span>
        <p>Press PLAY CAMPAIGN (top right). In the game, start or continue the Campaign and fly the day. When you come back here your first sortie will be in the logbook.</p>
        <p>Quick missions and training are not recorded here. Your aeroplane and your logbook are for the campaign only.</p>
      </div>
      <p style="color:var(--soft)">Please do not switch away from the game with Alt+Tab while you fly. The game runs full screen, and any window that appears over it can make it lose the display or your joystick.</p>
    </div>
  </div>
</section>

<section id="faq" aria-labelledby="faq-h">
  <div class="head">
    <span class="label">Good to know</span>
    <h2 id="faq-h">Questions players have asked</h2>
  </div>
  <div class="faq">
    <div><h3>Why is my letter in the game different from the Room's?</h3><p>Before your first sortie the Room shows the letter the game gives the squadron leader's aircraft. If the game puts you further down the flight you fly a different one. After the sortie the Room shows the letter you actually flew.</p></div>
    <div><h3>Why am I leading the squadron as a Pilot Officer?</h3><p>That is the game. On your first sortie it puts you in the lead aircraft, whatever your rank.</p></div>
    <div><h3>My quick mission is not in the log book</h3><p>Only campaign sorties are recorded. Quick missions and flight training are for practice.</p></div>
    <div><h3>Are the newspaper figures from my campaign?</h3><p>The band headed "from the record of 1940" is real history for the day before, with sources kept for every date. The Morgenmeldung's lead story is your own campaign's figures, and says so underneath.</p></div>
    <div><h3>A console window flashes and the launcher never opens</h3><p>Windows or your antivirus has blocked it. Unblock the zip before extracting (step 1), or add the <span class="path">BOB2-Win11-Fix</span> folder to your antivirus exclusions. The mod is open source.</p></div>
    <div><h3>Two mouse pointers, or the joystick does nothing</h3><p>A copy of the game was still running, or a window appeared over the game. The launcher will not start a second copy. Close anything that pops up on a timer while you fly.</p></div>
    <div><h3>Can I change my pilot's past?</h3><p>Yes. Click his photograph, type over anything, and press SAVE. What you write is kept and never replaced.</p></div>
    <div><h3>Will updating lose my pilots?</h3><p>No. They live in the <span class="path">SquadronRoom</span> folder beside <span class="path">Bob.exe</span>, not in the mod's folder.</p></div>
  </div>
</section>

<footer>
  <span>An unofficial community mod for Battle of Britain II 2.13. Not affiliated with or endorsed by A2A Simulations. The full source is public at github.com/malawicob/bob2-modern-fix.</span>
  <span>Pilots, crews and their histories in the Squadron Room are invented. Squadrons, Gruppen, schools, dates and the 1940 record are historical.</span>
</footer>
</div>
