import random, math, pathlib

root = pathlib.Path('/Users/purvarajsinhgohil/Developer/Wffl')
scratch = pathlib.Path('/private/tmp/claude-501/-Users-purvarajsinhgohil-Developer-Wffl/fe5a83fa-591c-448d-bfba-81c035a91d24/scratchpad')
css = (scratch / 'mock.css').read_text()
random.seed(7)

MARK = '<svg aria-hidden="true"><use href="#mark"/></svg>'
LIGHTS = '<div class="lights" aria-hidden="true"><i></i><i></i><i></i></div>'

def side(active, listing=None):
    items = [('Home', None), ('Dashboard', None), ('Meetings', '38'), ('Audio Files', '3' if active == 'Audio Files' else None)]
    nav = ''.join(f'<div class="nv{" on" if n == active else ""}">{n}' + (f' <span class="n">{c}</span>' if c else '') + '</div>' for n, c in items)
    settings = f'<div class="nv{" on" if active == "Settings" else ""}">Settings</div>'
    priv = '<div class="privacy"><b>On-device only</b>Audio stays on this Mac.</div>'
    if listing:
        return f'<aside class="side"><div class="brand">{MARK}Wffl</div>{nav}{listing}{settings}</aside>'
    return f'<aside class="side"><div class="brand">{MARK}Wffl</div>{nav}<div class="sp"></div>{settings}{priv}</aside>'

def win(inner, solo=False):
    return f'<div class="stage"><div class="win{" solo" if solo else ""}">{LIGHTS}{inner}</div></div>'

def shot(id_, title, blurb, body, sample=True):
    s = '<p class="sample">Sample data: every meeting, name and figure on this screen is invented.</p>' if sample else ''
    return f'''
      <section class="shot" id="{id_}">
        <div class="shot-head"><h2>{title}</h2><p>{blurb}</p></div>
        {body}
        {s}
      </section>
'''

def meeting_list(sel=0):
    data = [('Today', [('Design review: model download', '10:30', '47:12'), ('1:1 with Marcus', '09:00', '24:08')]),
            ('Yesterday', [('Roadmap review', '15:30', '58:41'), ('Customer call: Northwind', '11:00', '31:20')]),
            ('19 Oct 2026', [('Weekly sync', '16:00', '42:05')])]
    out = '<div class="list">'; i = 0
    for g, ms in data:
        out += f'<p class="gh">{g}</p>'
        for t, a, b in ms:
            out += f'<div class="li{" on" if i == sel else ""}"><div class="t">{t}</div><div class="m"><span>{a}</span><span>{b}</span></div></div>'; i += 1
    return out + '</div>'

AUDIO_LIST = '''<div class="list"><p class="gh">Imported</p>
      <div class="li on"><div class="t">Interview-Rao-raw.m4a</div><div class="m"><span>1:12:44</span><span>Transcribing</span></div></div>
      <div class="li"><div class="t">Voice memo 14 Oct.m4a</div><div class="m"><span>6:02</span><span>Summarized</span></div></div>
      <div class="li"><div class="t">Kirtan-practice.wav</div><div class="m"><span>28:19</span><span>Transcript</span></div></div></div>'''

def glow(style):
    return f'<div class="glow" aria-hidden="true" style="{style}"></div>'

# ---------------- main fragments ----------------
def ready_rows(system_ok=False):
    ready = [('', 'Speech engine', 'BAPS Whisper', 'Ready'), ('', 'Local summaries', 'Ollama, gemma4:12b-mlx', 'Connected'), ('', 'Microphone', 'MacBook Pro Microphone', 'Ready')]
    ready.append(('', 'System audio', 'Captures what Zoom plays', 'Ready') if system_ok else ('hollow', 'System audio', 'Screen &amp; System Audio Recording is off. Mic-only until you allow it.', '<a>Open Settings</a>'))
    return ''.join(f'<div class="r"><span class="lamp {c}"></span><span><b>{a}</b><small>{b}</small></span><span>{d}</span></div>' for c, a, b, d in ready)

def home_main(nudge=False, proto=False, system_ok=False):
    n = '<div class="nudge"><span class="lamp live"></span><span>Zoom call detected. Start recording?</span><span class="btn primary sm">Start</span><button class="x" type="button" aria-label="Dismiss">Dismiss</button></div>' if nudge else ''
    start = '<button class="btn primary lg" type="button" data-go="rec">Start Recording <kbd>⌘N</kbd></button>' if proto else '<span class="btn primary lg">Start Recording <kbd>⌘N</kbd></span>'
    return f'''<div class="main{" scr on" if proto else ""}" data-s="home">{glow('width:60%;height:90%;right:-14%;top:-20%')}
            <div class="crumb">Home</div>{n}
            <div class="body"><div class="home">
              <div>
                <p class="big">Ready when<br><span>you are.</span></p>
                <p class="lede">Record a meeting and Wffl transcribes and summarizes it, entirely on this Mac.</p>
                <div class="acts">{start}<span class="btn lg" style="font-weight:500">Import audio</span></div>
              </div>
              <div class="ready card"><h3>Ready check</h3>{ready_rows(system_ok)}</div>
            </div></div>
          </div>'''

def bars(n=96, seed=3):
    r = random.Random(seed); out = []
    for i in range(n):
        env = 0.35 + 0.65 * abs(math.sin(i * 0.19)) * (0.6 + 0.4 * math.sin(i * 0.05 + 1))
        out.append(max(4, int(80 * env * r.uniform(0.55, 1.0))))
    return out

def wave_html():
    b = ''.join(f'<i style="height:{h}px"></i>' for h in bars())
    return f'<div class="wave" aria-hidden="true"><div class="bars" id="wbars">{b}<span class="tail"></span><span class="head"></span></div><span class="rest"></span></div>'

def dots(on, n=24):
    return '<div class="dots" aria-hidden="true">' + ''.join(f'<i class="{"on" if i < on else ""}"></i>' for i in range(n)) + '</div>'

def rec_main(proto=False):
    rows = [('16:52', 'Them', 'Before that, did everyone get the build notes I sent around yesterday evening?'),
            ('17:10', 'Me', 'I did. The only open question is whether Parakeet should be the default engine for new installs.'),
            ('17:29', 'Them', 'It is faster for plain English, but BAPS Whisper keeps the Gujarati terms intact, so I would keep it recommended.'),
            ('17:48', 'Me', "Agreed. Let's keep BAPS Whisper recommended and show the model size before the Download button.")]
    tx = ''.join(f'<div class="tr"><span class="t">{t}</span><span class="w">{w}</span><span>{x}</span></div>' for t, w, x in rows)
    tx += '<div class="tr live-row"><span class="t">18:24</span><span class="w">Them</span><span>Then I can write the settings copy this afternoon<span class="caret"></span></span></div>'
    stop = '<button class="b stop" type="button" data-go="meet" data-after="summarize"><span class="d"></span>Stop &amp; save</button>' if proto else '<div class="b stop"><span class="d"></span>Stop &amp; save</div>'
    mute = '<div class="b">Mute mic</div><div class="b">Pause</div>'
    return f'''<div class="main{" scr" if proto else ""}" data-s="rec">{glow('width:46%;height:60%;right:6%;top:-24%')}
            <div class="rec">
              <div class="rec-main">
                <div class="live-state"><span class="lamp live"></span><span class="cap">Recording</span></div>
                <div class="time" id="rtime">00:18:24</div>
                {wave_html()}
                <div class="tx card" id="rtx">{tx}</div>
              </div>
              <aside class="rail">
                <div class="ctl">{mute}{stop}</div>
                <div class="inp card"><h3>Microphone</h3><small>MacBook Pro Microphone</small>{dots(11)}<div class="kv"><span>Gain</span><b>0 dB</b></div></div>
                <div class="inp card"><h3>System audio</h3><small>Zoom, Meet, everything the Mac plays</small>{dots(16)}<div class="kv"><span>Gain</span><b>+3 dB</b></div></div>
                <p class="note2">Transcribing on this Mac with BAPS Whisper. Other voices get their names after you stop.</p>
              </aside>
            </div>
          </div>'''

def calendar():
    cells = '<i class="x"></i>' * 3
    levels = {1: 'b', 2: 'c', 5: 'a', 6: 'c', 7: 'c', 8: 'b', 9: 'a', 12: 'c', 13: 'b', 14: 'c', 15: 'a', 16: 'b', 19: 'c', 20: 'c'}
    for d in range(1, 32):
        if d == 21: cells += '<i class="today"></i>'
        elif d > 21: cells += '<i class="f"></i>'
        else: cells += f'<i class="{levels.get(d, "")}"></i>'
    return cells

def dash_main(proto=False):
    rows = [('Design review: model download', 'Today, 10:30', '47:12', '', 'Summarized'), ('1:1 with Marcus', 'Today, 09:00', '24:08', '', 'Summarized'),
            ('Roadmap review', 'Yesterday', '58:41', '', 'Summarized'), ('Customer call: Northwind', 'Yesterday', '31:20', 'hollow', 'Transcript ready'),
            ('Interview-Rao-raw.m4a', '19 Oct 2026', '1:12:44', 'hollow', 'Ready to transcribe')]
    rr = ''.join(f'<div class="row"><span class="a">{a}</span><span class="m">{b}</span><span class="l">{c}</span><span class="st"><span class="lamp {d}"></span>{e}</span></div>' for a, b, c, d, e in rows)
    start = '<button class="btn primary sm" type="button" data-go="rec">Start Recording</button>' if proto else '<span class="btn primary sm">Start Recording</span>'
    return f'''<div class="main{" scr" if proto else ""}" data-s="dash">
            <div class="crumb">Dashboard<span class="grow"></span>{start}</div>
            <div class="body"><div class="dash">
              <div class="lead"><p class="k">This week</p><p class="num">12</p><p>meetings recorded, all on this Mac.</p>
                <div class="tally"><span><b>9h 41m</b>of audio captured</span><span><b>11</b>summaries written</span></div></div>
              <div class="cal card"><div class="top"><h3>October 2026</h3><span class="cap">minutes per day</span></div>
                <div class="wk"><span>M</span><span>T</span><span>W</span><span>T</span><span>F</span><span>S</span><span>S</span></div>
                <div class="g">{calendar()}</div><div class="leg"><span>Light</span><span>Heavy</span></div></div>
              <div class="recent"><h3>Recent activity</h3>{rr}</div>
            </div></div>
          </div>'''

TODOS = [('Add size and recommendation text to the model picker', 'Me', 'Fri 23 Oct'), ('Tag and publish 1.9', 'Me', 'Today'), ('Write release notes for the Core ML engine', 'Priya', 'Thu 22 Oct')]
def summary_doc():
    tl = ''.join(f'<div class="todo"><span class="box"></span><span>{a}</span><span class="o">{b}</span><span class="d">{c}</span></div>' for a, b, c in TODOS)
    return f'''<div class="doc card">
              <h3>Overview</h3>
              <p>The team agreed to show model sizes and a recommended choice before a first-time download, and to ship version 1.9 today.</p>
              <h3>Decisions</h3>
              <ul>
                <li>Settings recommends BAPS Whisper for English and shows its size, about 1.6 GB, before the Download button.</li>
                <li>Version 1.9 ships today. The notarized build is ready.</li>
                <li>Cloud summary providers stay off by default.</li>
              </ul>
              <h3>Action items</h3>
              <div>{tl}</div>
              <div class="foot"><span class="btn sm">Regenerate</span><span class="btn sm">Copy</span><span>Written on this Mac with gemma4:12b-mlx</span></div>
            </div>'''

TRANSCRIPT_TB = '<div class="toolbar"><div class="seg"><span class="on">Cleaned</span><span>Raw</span></div><span class="grow"></span><span>Speakers named after the meeting</span><span class="btn sm">Copy</span></div>'
def transcript_doc():
    return '''<div class="doc card" style="margin-top:18px">
              <p class="topic">Model download flow</p>
              <div class="para"><span class="t">10:31</span><span class="w">Me</span><span>The download flow works, but a first-time user cannot tell which model to pick. I'd like Settings to recommend one and show the size next to it.</span></div>
              <div class="para"><span class="t">10:33</span><span class="w">Priya</span><span>BAPS Whisper is about 1.6 gigabytes and Parakeet about 600 megabytes. We should say that before the button, not after.</span></div>
              <p class="topic">Release timing</p>
              <div class="para"><span class="t">10:38</span><span class="w">Marcus</span><span>Notarization finished this morning, so the DMG can go out today if nothing else blocks it.</span></div>
              <div class="para"><span class="t">10:40</span><span class="w">Me</span><span>Nothing blocks it. I'll tag 1.9 after this call.</span></div>
            </div>'''

def notes_doc():
    return '''<div class="notes card">
              <p>Ask Priya whether the Core ML engine needs its own release note or can share the 1.9 post.</p>
              <p>Idea: show a one-line "why this model" under each engine in Settings.</p>
              <p class="cap" style="margin-top:22px">Saved<span class="caret"></span></p>
            </div>'''

def meet_head(tab, proto=False):
    names = ('Summary', 'Transcript', 'Notes')
    if proto:
        tabs = ''.join(f'<button type="button" data-tab="{t.lower()}" class="{"on" if t == tab else ""}">{t}</button>' for t in names)
    else:
        tabs = ''.join(f'<span class="{"on" if t == tab else ""}">{t}</span>' for t in names)
    return f'''<div class="search">Search meetings</div>
            <div class="mh">
              <h2>Design review: model download</h2>
              <div class="meta"><span>Wednesday 21 October at 10:30</span><span>47 min</span><span>3 speakers</span></div>
              <div class="tabs"><div class="seg">{tabs}</div><span class="grow"></span><span class="more">More</span></div>
            </div>'''

def meet_main_static(tab, content, toolbar=''):
    return f'<div class="main">{meet_head(tab)}{toolbar}<div class="body">{content}</div></div>'

def meet_main_proto():
    return f'''<div class="main scr" data-s="meet">{meet_head('Summary', True)}
            <div class="body">
              <div class="pane busy-pane"><div class="busy card"><h3>Writing the summary</h3><p>Reading the transcript with gemma4:12b-mlx on this Mac.</p><div class="track"><i id="busyfill"></i></div></div></div>
              <div class="pane on" data-pane="summary">{summary_doc()}</div>
              <div class="pane" data-pane="transcript">{TRANSCRIPT_TB}{transcript_doc()}</div>
              <div class="pane" data-pane="notes">{notes_doc()}</div>
            </div>
          </div>'''

def audio_main(proto=False):
    return f'''<div class="main{" scr" if proto else ""}" data-s="audio">
            <div class="crumb">Audio Files</div>
            <div class="drop"><div><h3>Drop audio to transcribe</h3><p>On-device, never uploaded. m4a, wav, mp3, mp4 and mov.</p></div><span class="btn primary">Choose file</span></div>
            <div class="job">
              <h2>Interview-Rao-raw.m4a</h2>
              <div class="meta"><span>Imported today at 11:52</span><span>1 h 12 min</span><span>Whisper large-v3-turbo</span></div>
              <div class="prog card"><div class="top"><b>Transcribing locally</b><span class="mono">62%</span></div><div class="track"><i></i></div>
                <div style="margin-top:14px;display:flex;justify-content:space-between;align-items:center;font-size:13px;color:var(--dim)"><span>You can keep using Wffl. Closing the window pauses nothing.</span><span class="btn sm">Cancel</span></div></div>
            </div>
          </div>'''

def settings_main(proto=False):
    return f'''<div class="main{" scr" if proto else ""}" data-s="settings">
            <div class="crumb">Settings</div>
            <div class="body"><div class="set">
              <div class="banner card">{glow('')}<div><h2>Your audio stays on this Mac</h2><p>Recording, transcription and summaries run here. There is no account. The network is used only to download models and, if you opt in, cloud summaries.</p></div><span class="net">Network: model downloads only</span></div>
              <h3>Transcription engine</h3>
              <div class="grp card">
                <div class="opt"><span class="radio on"></span><span><b>BAPS Whisper</b><small>English with Gujarati and Sanskrit words kept intact. Recommended.</small></span><span class="s">1.6 GB · Ready</span></div>
                <div class="opt"><span class="radio"></span><span><b>Parakeet</b><small>Fastest plain English.</small></span><span class="s">600 MB · Ready</span></div>
                <div class="opt"><span class="radio"></span><span><b>Whisper</b><small>99 languages, translate-to-English. large-v3-turbo.</small></span><span class="s go">Download 1.5 GB</span></div>
              </div>
              <h3>Summaries</h3>
              <div class="grp card">
                <div class="opt two"><span><b>Ollama model</b><small>Local open-source model for summaries and clean-up.</small></span><span class="field">gemma4:12b-mlx</span></div>
                <div class="opt two"><span><b>Clean up transcripts after recording</b><small>Remove filler and false starts. Raw stays one toggle away.</small></span><span class="switch on"></span></div>
                <div class="opt two"><span><b>When a call is detected</b><small>Zoom, Teams, Webex, Discord, Slack, FaceTime, or a browser tab.</small></span><span class="seg"><span>Off</span><span class="on">Nudge</span><span>Auto-start</span></span></div>
              </div>
            </div></div>
          </div>'''

def collapsed():
    return '<div class="stage"><div class="desk" aria-label="Floating recording bar over the desktop"><div class="menubar"></div><div class="pill"><span class="lamp live"></span><span class="clock">00:18:24</span><span class="tiny">Mic and system</span><span class="btn sm">Stop &amp; save</span></div></div></div>'

def states():
    return '''<div class="stage"><div class="states">
          <div class="state"><h3>Select a meeting</h3><p>Pick a meeting from the sidebar to see its summary, transcript and notes.</p></div>
          <div class="state"><div class="glow" aria-hidden="true"></div><h3>No summary yet</h3><p>Generate meeting notes from the transcript. Everything is processed on this Mac.</p><div class="row2"><span class="btn primary">Generate summary</span></div></div>
          <div class="state"><h3>Writing the summary</h3><p>Reading the transcript with gemma4:12b-mlx on this Mac.</p><div class="row2"><div class="track"><i></i></div><span class="btn sm">Cancel</span></div></div>
          <div class="state"><h3>Clean-up failed</h3><p>Ollama is not running, so the transcript was left as recorded. Start Ollama, then try again.</p><div class="row2"><span class="btn">Try again</span><span class="btn sm">Show raw</span></div></div>
        </div></div>'''

# ---------------- prototype ----------------
def proto():
    nav = ''.join(f'<button class="nv{" on" if s == "home" else ""}" type="button" data-go="{s}">{n}' + (f' <span class="n">{c}</span>' if c else '') + '</button>'
                  for s, n, c in (('home', 'Home', None), ('dash', 'Dashboard', None), ('meet', 'Meetings', '38'), ('audio', 'Audio Files', '3')))
    sidebar = f'''<aside class="side"><div class="brand">{MARK}Wffl</div>{nav}
            <div class="plist" data-for="meet">{meeting_list()}</div>
            <div class="plist" data-for="audio">{AUDIO_LIST}</div>
            <div class="sp"></div><button class="nv" type="button" data-go="settings">Settings</button>
            <div class="privacy" id="pprivacy"><b>On-device only</b>Audio stays on this Mac.</div></aside>'''
    mains = home_main(proto=True, system_ok=True) + rec_main(True) + dash_main(True) + meet_main_proto() + audio_main(True) + settings_main(True)
    return f'<div class="stage"><div class="win proto" id="proto">{LIGHTS}{sidebar}{mains}<div class="toast" id="toast" role="status"></div></div></div>'

PROTO_JS = r'''
      (() => {
        const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
        const p = document.getElementById("proto"); if (!p) return;
        const scr = [...p.querySelectorAll(".scr")], navs = [...p.querySelectorAll("button.nv")];
        const lists = [...p.querySelectorAll(".plist")], priv = document.getElementById("pprivacy"), toast = document.getElementById("toast");
        let cur = "home", timers = [];
        const say = (t) => { toast.textContent = t; toast.classList.add("on"); setTimeout(() => toast.classList.remove("on"), 3200); };
        const go = (s) => {
          cur = s;
          scr.forEach((m) => m.classList.toggle("on", m.dataset.s === s));
          navs.forEach((n) => n.classList.toggle("on", n.dataset.go === s));
          lists.forEach((l) => l.classList.toggle("on", l.dataset.for === s));
          priv.classList.toggle("hide", s === "meet" || s === "audio");
          p.classList.toggle("solo", s === "rec"); p.classList.toggle("haslist", s === "meet" || s === "audio");
          if (s === "rec") startRec(); else stopRec();
        };
        const tab = (t) => {
          p.querySelectorAll("[data-tab]").forEach((b) => b.classList.toggle("on", b.dataset.tab === t));
          p.querySelectorAll("[data-pane]").forEach((x) => x.classList.toggle("on", x.dataset.pane === t));
          p.querySelector(".busy-pane").classList.remove("on");
        };
        p.addEventListener("click", (e) => {
          const g = e.target.closest("[data-go]");
          if (g) {
            const after = g.dataset.after; go(g.dataset.go);
            if (after === "summarize") {
              say("Saved. Writing the summary on this Mac.");
              p.querySelectorAll("[data-pane]").forEach((x) => x.classList.remove("on"));
              const bp = p.querySelector(".busy-pane"), fill = document.getElementById("busyfill");
              bp.classList.add("on"); fill.style.width = "8%"; void fill.offsetWidth; fill.style.width = "100%";
              setTimeout(() => { if (cur === "meet") { tab("summary"); say("Summary ready."); } }, reduce ? 300 : 2300);
            }
            return;
          }
          const t = e.target.closest("[data-tab]"); if (t) tab(t.dataset.tab);
        });

        /* Recording: clock, scrolling waveform and live transcript */
        const rtime = document.getElementById("rtime"), wbars = document.getElementById("wbars"), rtx = document.getElementById("rtx");
        const fmt = (s) => `${String(s / 3600 | 0).padStart(2, "0")}:${String(s / 60 % 60 | 0).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
        const live = [["Me", "Then please put the recommended model first in the list."], ["Them", "Will do. I will also add the download size under each engine."], ["Me", "Perfect. That should cover the first-run questions."], ["Them", "Stopping here, then. I will send the summary around."]];
        const type = (el, text) => { let i = 0; const id = setInterval(() => { el.firstChild.nodeValue = text.slice(0, ++i); if (i >= text.length) clearInterval(id); }, 28); timers.push(id); };
        function startRec() {
          stopRec();
          let secs = 18 * 60 + 24, n = 0;
          rtime.textContent = fmt(secs);
          if (reduce) return;
          timers.push(setInterval(() => { secs++; rtime.textContent = fmt(secs); }, 1000));
          timers.push(setInterval(() => {
            const first = wbars.firstElementChild; if (!first || !first.matches("i")) return;
            const i = document.createElement("i"); i.style.height = Math.max(4, 14 + Math.random() * 62 | 0) + "px";
            wbars.insertBefore(i, wbars.querySelector(".tail")); wbars.removeChild(first);
          }, 140));
          timers.push(setInterval(() => {
            if (n >= live.length) return;
            const [w, t] = live[n++];
            rtx.querySelectorAll(".caret").forEach((c) => c.remove());
            const row = document.createElement("div"); row.className = "tr";
            row.innerHTML = `<span class="t">${fmt(secs).slice(3)}</span><span class="w">${w}</span><span><span class="txt"></span><span class="caret"></span></span>`;
            row.querySelector(".txt").appendChild(document.createTextNode(""));
            rtx.appendChild(row); while (rtx.children.length > 6) rtx.removeChild(rtx.firstChild);
            type(row.querySelector(".txt"), t);
          }, 3600));
        }
        function stopRec() { timers.forEach((t) => clearInterval(t)); timers = []; }
      })();
'''

body = ''
body += shot('prototype', 'Try it: a clickable walkthrough', 'Click through the real flow. Start Recording on Home, watch the waveform and transcript run, Stop &amp; save to land in the meeting and see the summary being written. Sidebar, tabs and the appearance switch all work.', proto())
body += '<p class="hint">Below: every screen laid out flat, in light and dark, for review.</p>'
body += shot('home', 'Home', 'One dominant action, left-aligned, with the soft light behind the greeting. Readiness chips become a calm check list that says what is missing and links to the fix.', win(side('Home') + home_main()))
body += shot('nudge', 'Call detected', 'The auto-detect nudge is a black pill with one primary action and a plain Dismiss. It never covers the Start button.', win(side('Home') + home_main(nudge=True, system_ok=True)))
body += shot('recording', 'Recording', 'The window becomes the instrument: a large light timer, a waveform whose ember playhead sits at the live edge, the transcript as timecoded rows, and three big transport buttons. Live rows say Me and Them; names arrive after you stop.', win(rec_main(), solo=True))
body += shot('collapsed', 'Recording, collapsed', 'The floating focus bar over other apps: the same lamp, clock and stop control in one line.', collapsed(), sample=False)
body += shot('dashboard', 'Dashboard', 'One big number instead of three stat cards, and a dot calendar of the month: bigger, darker dots are longer days, today is ember.', win(side('Dashboard') + dash_main()))
body += shot('summary', 'Meeting summary', 'The library lives in the sidebar, the selected meeting is a white card. The summary reads like minutes: overview, decisions, and action items with owner and date.', win(side('Meetings', meeting_list()) + meet_main_static('Summary', summary_doc())))
body += shot('transcript', 'Meeting transcript', 'Cleaned view with topic headings. Time, speaker and paragraph sit on fixed columns so the eye can scan down the timecodes.', win(side('Meetings', meeting_list()) + meet_main_static('Transcript', transcript_doc(), TRANSCRIPT_TB)))
body += shot('notes', 'Meeting notes', 'A plain writing surface in the same card as the summary. Autosave is stated, not hidden.', win(side('Meetings', meeting_list()) + meet_main_static('Notes', notes_doc())))
body += shot('audio', 'Audio files', 'The drop zone states its promise. A running job shows its stage and a pill progress track, with Cancel always in reach.', win(side('Audio Files', AUDIO_LIST) + audio_main()))
body += shot('settings', 'Settings', 'The privacy statement leads, honestly worded. Engines are a radio list that shows size and state before you commit. Toggles are pills; on is black.', win(side('Settings') + settings_main()))
body += shot('states', 'Empty and busy states', 'The moments between: nothing selected, no summary yet, a summary being written, and a failed clean-up. Each says what happened and offers one next action.', states())

idx = [('prototype', 'Try it'), ('home', 'Home'), ('nudge', 'Call detected'), ('recording', 'Recording'), ('collapsed', 'Recording, collapsed'), ('dashboard', 'Dashboard'), ('summary', 'Meeting summary'), ('transcript', 'Meeting transcript'), ('notes', 'Meeting notes'), ('audio', 'Audio files'), ('settings', 'Settings'), ('states', 'Empty and busy states')]
index = ''.join(f'<li><a href="#{i}">{t}</a></li>' for i, t in idx)

FIT_JS = r'''
      (() => {
        const fit = () => document.querySelectorAll(".stage").forEach((st) => {
          const el = st.firstElementChild; if (!el) return;
          const w = el.offsetWidth || 1240, s = Math.min(1, st.clientWidth / w);
          el.style.transform = s < 1 ? `scale(${s})` : "";
          st.style.height = Math.round(el.offsetHeight * s) + "px";
        });
        addEventListener("resize", fit); fit(); addEventListener("load", fit);
        if (document.fonts) document.fonts.ready.then(fit);
      })();
'''

html = f'''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Wffl app UI mockups</title>
    <meta name="color-scheme" content="light dark" />
    <style>
{css}
    </style>
  </head>
  <body>
    <svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">
      <symbol id="mark" viewBox="0 0 100 100"><g fill="currentColor">
        <ellipse cx="14" cy="50" rx="3.4" ry="30"/><ellipse cx="24" cy="50" rx="3.4" ry="20"/><ellipse cx="34" cy="50" rx="3.4" ry="10"/>
        <ellipse cx="44" cy="50" rx="3.4" ry="20"/><ellipse cx="54" cy="50" rx="3.4" ry="26"/><ellipse cx="64" cy="50" rx="3.4" ry="20"/>
        <ellipse cx="74" cy="50" rx="3.4" ry="10"/><ellipse cx="84" cy="50" rx="3.4" ry="30"/></g></symbol>
    </svg>
    <div class="gal">
      <header class="gal-head">
        <div>
          <h1>Wffl app UI mockups</h1>
          <p>Every screen of the macOS app in the new monochrome system, plus a clickable walkthrough. Mockups only: the app's source is unchanged. All meetings, names and figures are invented sample data.</p>
        </div>
        <div class="theme" role="group" aria-label="Appearance">
          <button type="button" data-t="system" aria-pressed="true">System</button>
          <button type="button" data-t="light" aria-pressed="false">Light</button>
          <button type="button" data-t="dark" aria-pressed="false">Dark</button>
        </div>
      </header>
      <ul class="index">{index}</ul>
{body}
    </div>
    <script>
      (() => {{
        const root = document.documentElement;
        const btns = document.querySelectorAll(".theme button");
        const apply = (t) => {{
          if (t === "system") root.removeAttribute("data-theme"); else root.setAttribute("data-theme", t);
          btns.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.t === t)));
        }};
        btns.forEach((b) => b.addEventListener("click", () => apply(b.dataset.t)));
      }})();
{FIT_JS}
{PROTO_JS}
    </script>
  </body>
</html>
'''
(root / 'design/app-mockups/index.html').write_text(html)
print(len(html))
