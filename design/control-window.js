(() => {
  const S = {
    hu: { reh: "Próba", con: "Koncert", proj: "Projektor 1920×1080 60 Hz", pow: "Töltő", mute: "NÉMÍTVA", aon: "HANG BE → HDMI",
      last: "Utolsó gomb", live: "ÉLŐ", next: "KÖVETKEZŐ", nothing: "semmi", covRun: "TAKARVA · fut", covPause: "TAKARVA · áll",
      toPlan: "tervezett végéig", toEnd: "klip végéig", black: "Fekete", logo: "Logó", brk: "Szünet", min: "perc", cd: "visszaszámlálás",
      go: "GO", play: "Lejátszás", restart: "Elejére", mute2: "Hang", okAll: "Mind a 9 klip rendben",
      concertBanner: "KONCERT", unmuteAsk: "Nyomd meg újra az M-et a hang bekapcsolásához (3 mp)",
      modeAsk: m => `Kattints újra: váltás ${m} módra (3 mp)`, concertMute: "Koncert módban a hang mindig ki van kapcsolva",
      noArm: "Nincs semmi előkészítve", notReady: "A következő klip még töltődik", focus: "A BILLENTYŰK NEM AZ APPHOZ MENNEK. KATTINTS IDE.",
      projH: "Projektor", projP: "Itt csak videó, fekete, logó vagy a szünet képernyő jelenhet meg. A B és az L letakarja az élő klipet, de nem állítja meg." },
    en: { reh: "Rehearsal", con: "Concert", proj: "Projector 1920×1080 60 Hz", pow: "Power", mute: "MUTED", aon: "AUDIO ON → HDMI",
      last: "Last key", live: "LIVE", next: "NEXT", nothing: "nothing", covRun: "COVERED · running", covPause: "COVERED · paused",
      toPlan: "to planned end", toEnd: "to clip end", black: "Black", logo: "Logo", brk: "Intermission", min: "min", cd: "countdown",
      go: "GO", play: "Play", restart: "Restart", mute2: "Sound", okAll: "All 9 clips checked",
      concertBanner: "CONCERT", unmuteAsk: "Press M again to turn sound on (3 s)",
      modeAsk: m => `Click again to switch to ${m} (3 s)`, concertMute: "Sound is always off in concert mode",
      noArm: "Nothing armed", notReady: "Next clip is still loading", focus: "KEYS ARE NOT REACHING THE APP. CLICK HERE.",
      projH: "Projector", projP: "Only video, black, a logo or the break screen ever appears here. B and L cover the live clip without stopping it." }
  };
  const movies = ["The Greatest Showman", "Second film (example)"];
  const clip = (movie, n, title, planned, tail, hue) => ({ k: "clip", movie, n, title, planned, tail, dur: planned + tail, hue });
  const items = [
    { k: "black" },
    clip(0, 0, "Title", 45, 15, 220),
    clip(0, 1, "The Greatest Show", 212.5, 60, 28),
    clip(0, 2, "A Million Dreams", 268, 60, 205),
    clip(0, 3, "Come Alive", 223, 60, 12),
    { k: "black", movie: 0 },
    clip(0, 4, "The Other Side", 211, 60, 45),
    clip(0, 5, "Never Enough", 207, 60, 320),
    clip(0, 6, "This Is Me", 234, 60, 350),
    clip(0, 7, "Never Enough (Reprise)", 82, 60, 300),
    { k: "break", minutes: 20 },
    clip(1, 0, "Title", 40, 20, 160),
    { k: "logo", n: 1 }
  ];

  let st, speed = 1, lang = "hu", pending = null, focused = true, log = [];
  const reset = () => {
    st = { live: null, t: 0, playing: false, cover: null, armed: 1, at: 0, mode: "rehearsal", muted: true,
      lastKey: "", msg: null, simNow: 0, breakEnd: 0 };
    log = []; pending = null; note("Launch: projector black, 00 Title armed");
  };
  const $ = id => document.getElementById(id);
  const fmt = s => { s = Math.max(0, Math.round(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`; };
  const T = () => S[lang];
  const label = it => {
    const t = T();
    if (it.k === "clip") return it.title;
    if (it.k === "black") return t.black;
    if (it.k === "logo") return `${t.logo} ${it.n}`;
    return `${t.brk} ${it.minutes} ${t.min} (${t.cd})`;
  };
  const num = it => it.k === "clip" ? String(it.n).padStart(2, "0") : "";
  const note = s => { log.unshift({ at: st ? fmt(st.simNow) : "0:00", s }); log = log.slice(0, 8); };
  const say = (text, warn) => { st.msg = { text, warn }; };

  // commands mirror docs/design.md behaviour
  const cur = () => items[st.live] || null;
  const armedIt = () => items[st.armed] || null;
  const movieOf = i => (items[i] && items[i].movie !== undefined) ? items[i].movie : null;
  function go() {
    const a = armedIt();
    if (!a) return say(T().noArm, true);
    st.live = st.armed; st.t = a.k === "clip" ? st.at : 0; st.cover = null;
    st.playing = a.k === "clip";
    if (a.k === "break") st.breakEnd = st.simNow + a.minutes * 60;
    note(`GO → ${num(a)} ${label(a)}${st.at ? " @ " + fmt(st.at) : ""}`);
    st.armed = st.armed + 1 < items.length ? st.armed + 1 : null; st.at = 0;
  }
  function cover(c) {
    st.cover = st.cover === c ? null : c;
    note(st.cover ? `cover ${c}` : `uncover → ${cur() ? label(cur()) : "black"}`);
  }
  function arm(i) { if (i < 0 || i >= items.length) return; st.armed = i; st.at = 0; note(`arm ${num(items[i])} ${label(items[i])}`); }
  function armDigit(d) {
    const m = movieOf(st.armed) ?? movieOf(st.live) ?? 0;
    const i = items.findIndex(it => it.k === "clip" && it.movie === m && it.n === d);
    if (i >= 0) arm(i);
  }
  function seek(d) { const c = cur(); if (c && c.k === "clip") { st.t = Math.min(c.dur, Math.max(0, st.t + d)); note(`seek ${d > 0 ? "+" : ""}${d} s`); } }
  function park(d) { const a = armedIt(); if (a && a.k === "clip") { st.at = Math.min(a.dur - 1, Math.max(0, st.at + d)); note(`park next @ ${fmt(st.at)}`); } }
  function playPause() { const c = cur(); if (c && c.k === "clip" && st.t < c.dur) { st.playing = !st.playing; note(st.playing ? "play" : "pause"); } }
  function restart() { const c = cur(); if (c && c.k === "clip") { st.t = 0; note("restart"); } }
  function mute() {
    if (st.mode === "concert") return say(T().concertMute, true);
    if (!st.muted) { st.muted = true; note("mute"); return; }
    if (pending && pending.kind === "unmute") { st.muted = false; pending = null; note("sound on"); return; }
    pending = { kind: "unmute", until: performance.now() + 3000 };
  }
  function askMode(m) {
    if (st.mode === m) return;
    if (pending && pending.kind === "mode" && pending.m === m) {
      st.mode = m; pending = null; if (m === "concert") st.muted = true; note(`mode → ${m}`); return;
    }
    pending = { kind: "mode", m, until: performance.now() + 3000 };
  }

  const keyName = e => (e.metaKey ? "Cmd+" : "") + (e.altKey ? "Opt+" : "") + (e.shiftKey && e.key.length > 1 ? "Shift+" : "") +
    ({ " ": "Space", ArrowLeft: "←", ArrowRight: "→", ArrowUp: "↑", ArrowDown: "↓" }[e.key] || (e.key.length === 1 ? e.key.toUpperCase() : e.key));
  function onKey(e) {
    if (e.target && e.target.id === "scrub") return;
    const k = e.key, sh = e.shiftKey, alt = e.altKey;
    let done = true;
    if (k === "Enter") go();
    else if (k === " ") playPause();
    else if (k === "b" || k === "B") cover("black");
    else if (k === "l" || k === "L") cover(sh ? "logo2" : "logo1");
    else if (k === "ArrowLeft" || k === "ArrowRight") { const d = (k === "ArrowLeft" ? -1 : 1) * (sh ? 30 : 5); alt ? park(d) : seek(d); }
    else if (k === "ArrowUp" || k === "-") arm((st.armed ?? items.length) - 1);
    else if (k === "ArrowDown" || k === "+") arm((st.armed ?? -1) + 1);
    else if (k === "Home") restart();
    else if (k === "m" || k === "M") mute();
    else if (/^[0-9]$/.test(k)) armDigit(+k);
    else if (k === "Escape") note("Esc: nothing");
    else done = false;
    if (done) { e.preventDefault(); st.lastKey = keyName(e); render(); }
  }

  // screens
  function screenHTML(it, t, opts = {}) {
    if (!it || it.k === "black") return "";
    if (it.k === "logo" || opts.logo) {
      const n = opts.logo || it.n;
      return `<div class="logo">${n === 1 ? "Example Orchestra" : "Spring Gala 2026"}<span>${n === 1 ? "logo 1" : "logo 2"}</span></div>`;
    }
    if (it.k === "break") {
      const left = st.breakEnd - st.simNow, t2 = T();
      return `<div class="brk"><div class="t">${t2.brk}</div>${left > 0 ? `<div class="c">${fmt(left)}</div>` : ""}</div>`;
    }
    const fade = Math.max(0, Math.min(1, it.dur - t));
    const x = 15 + ((t * 4) % 70), h = it.hue;
    return `<div class="film" style="opacity:${fade};background:radial-gradient(circle at ${x}% 55%, hsl(${h} 80% 70% / .9), transparent 38%),
      linear-gradient(120deg, hsl(${h} 45% 22%), hsl(${(h + 40) % 360} 55% 38%) 60%, hsl(${(h + 80) % 360} 40% 18%))"></div>`;
  }
  function projectorHTML() {
    if (st.cover === "black") return "";
    if (st.cover === "logo1") return screenHTML(null, 0, { logo: 1 });
    if (st.cover === "logo2") return screenHTML(null, 0, { logo: 2 });
    return screenHTML(cur(), st.t);
  }

  const BTN = [
    ["GO", "Enter", go, "go"], ["play", "Space", playPause], ["restart", "Home", restart],
    ["−30", "⇧←", () => seek(-30)], ["−5", "←", () => seek(-5)], ["+5", "→", () => seek(5)], ["+30", "⇧→", () => seek(30)],
    ["black", "B", () => cover("black"), "blk"], ["logo1", "L", () => cover("logo1")], ["logo2", "⇧L", () => cover("logo2")],
    ["mute2", "M", mute]
  ];
  function renderButtons() {
    const t = T();
    $("btns").innerHTML = BTN.map(([l, k, , c], i) => {
      const txt = l === "logo1" ? `${t.logo.toUpperCase()} 1` : l === "logo2" ? `${t.logo.toUpperCase()} 2` : l === "black" ? t.black.toUpperCase() : t[l] || l;
      const on = (l === "black" && st.cover === "black") || (l === "logo1" && st.cover === "logo1") || (l === "logo2" && st.cover === "logo2");
      return `<button type="button" class="b ${c || ""} ${on ? "on" : ""}" data-i="${i}" tabindex="-1">${txt}<small>${k}</small></button>`;
    }).join("");
  }
  function renderList() {
    let html = "", lastMovie = -1;
    items.forEach((it, i) => {
      if (it.movie !== undefined && it.movie !== lastMovie) { lastMovie = it.movie; html += `<div class="mv">${it.movie + 1} · ${movies[it.movie]}</div>`; }
      if (it.movie === undefined) lastMovie = -1;
      const cls = i === st.live ? "live" : i === st.armed ? "armed" : "";
      const meta = it.k === "clip" ? fmt(it.dur) : "";
      html += `<div class="it ${cls}" data-i="${i}"><span class="n">${num(it)}</span><span>${label(it)}</span><span class="meta">${meta}</span></div>`;
    });
    $("list").innerHTML = html;
  }

  function render() {
    const t = T(), c = cur(), a = armedIt();
    $("mReh").textContent = t.reh; $("mCon").textContent = t.con;
    $("mReh").classList.toggle("on", st.mode === "rehearsal"); $("mCon").classList.toggle("on", st.mode === "concert");
    $("lHu").classList.toggle("on", lang === "hu"); $("lEn").classList.toggle("on", lang === "en");
    $("dProj").textContent = t.proj; $("dPow").textContent = t.pow;
    $("audio").textContent = st.muted ? t.mute : t.aon; $("audio").classList.toggle("on", !st.muted);
    $("lastkey").innerHTML = `${t.last} <b>${st.lastKey || "–"}</b>`;
    const b = $("banner");
    let bt = "", bc = "";
    if (!focused) { bt = t.focus; bc = "focus"; }
    else if (pending && pending.kind === "unmute") { bt = t.unmuteAsk; bc = "confirm"; }
    else if (pending && pending.kind === "mode") { bt = t.modeAsk(pending.m === "concert" ? t.con : t.reh); bc = "confirm"; }
    else if (st.mode === "concert") { bt = t.concertBanner; bc = "concert"; }
    b.className = "banner " + (bt ? "show " + bc : ""); b.textContent = bt;
    renderList(); renderButtons();

    const covTag = st.cover && c && c.k === "clip" ? `<span class="tag cover">${st.playing ? t.covRun : t.covPause}</span>` : "";
    $("lbLive").innerHTML = `<span class="tag live">${t.live}</span> ${c ? `${num(c)} ${label(c)}` : t.black} ${covTag}`;
    $("lbNext").innerHTML = `<span class="tag next">${t.next}</span> ${a ? `${num(a)} ${label(a)}` : t.nothing}${a && a.k === "clip" && st.at ? " @ " + fmt(st.at) : ""}`;
    $("pvLive").innerHTML = screenHTML(c, st.t);
    $("pvNext").innerHTML = a ? screenHTML(a, st.at) : "";
    const sc = $("scrub"); sc.disabled = !(a && a.k === "clip");
    if (document.activeElement !== sc) sc.value = a && a.k === "clip" ? Math.round(st.at / a.dur * 1000) : 0;

    const isClip = c && c.k === "clip";
    $("fill").style.width = isClip ? `${st.t / c.dur * 100}%` : "0";
    $("mkPlan").style.display = $("mkTail").style.display = isClip ? "block" : "none";
    if (isClip) { $("mkPlan").style.left = `${c.planned / c.dur * 100}%`; $("mkTail").style.left = `calc(${(c.dur - 1) / c.dur * 100}% - 2px)`; }
    $("tPos").textContent = isClip ? `${fmt(st.t)} / ${fmt(c.dur)}` : "";
    $("tPlanL").textContent = isClip ? t.toPlan : "";
    $("tPlan").textContent = isClip ? (st.t <= c.planned ? fmt(c.planned - st.t) : "+" + fmt(st.t - c.planned)) : "";
    $("tEnd").textContent = isClip ? `${t.toEnd} ${fmt(c.dur - st.t)}` : "";
    const m = $("msg"); const msg = st.msg || { text: t.okAll };
    m.textContent = msg.text; m.className = "msg " + (msg.warn ? "warn" : "ok");

    $("proj").innerHTML = projectorHTML();
    $("projH").textContent = t.projH; $("projP").textContent = t.projP;
    $("log").innerHTML = log.map(l => `<li><b>${l.at}</b> ${l.s}</li>`).join("");
  }

  const KEYS = [
    ["Enter", "GO: put the next item on the projector, then arm the one after"],
    ["Space", "Play or pause the live clip, also while covered"],
    ["B", "Black cover on/off. The clip keeps its state under it"],
    ["L / Shift+L", "Logo 1 / logo 2 cover on/off"],
    ["← → / Shift", "Seek the live clip 5 s / 30 s"],
    ["Opt+← → / Shift", "Park the next clip 5 s / 30 s before GO"],
    ["↑ ↓ (keypad − +)", "Arm previous / next item"],
    ["0 – 9", "Arm that clip number in the current film"],
    ["Home", "Restart the live clip"],
    ["M", "Mute instantly; sound on needs a second press. Concert: always muted"],
    ["Esc", "Does nothing, on purpose"]
  ];
  $("keys").innerHTML = KEYS.map(([k, d]) => `<tr><td><kbd>${k}</kbd></td><td>${d}</td></tr>`).join("");

  const cw = $("cw");
  cw.addEventListener("keydown", onKey);
  cw.addEventListener("focus", () => { focused = true; render(); });
  cw.addEventListener("blur", () => { focused = false; render(); });
  $("banner").addEventListener("click", () => cw.focus());
  $("btns").addEventListener("click", e => { const el = e.target.closest(".b"); if (!el) return; BTN[+el.dataset.i][2](); cw.focus(); render(); });
  $("list").addEventListener("click", e => { const el = e.target.closest(".it"); if (!el) return; arm(+el.dataset.i); cw.focus(); render(); });
  $("mReh").addEventListener("click", () => { askMode("rehearsal"); cw.focus(); render(); });
  $("mCon").addEventListener("click", () => { askMode("concert"); cw.focus(); render(); });
  $("lHu").addEventListener("click", () => { lang = "hu"; cw.focus(); render(); });
  $("lEn").addEventListener("click", () => { lang = "en"; cw.focus(); render(); });
  $("scrub").addEventListener("input", e => { const a = armedIt(); if (a && a.k === "clip") { st.at = Math.min(a.dur - 1, e.target.value / 1000 * a.dur); render(); } });
  $("scrub").addEventListener("change", () => { note(`park next @ ${fmt(st.at)}`); cw.focus(); render(); });
  document.querySelectorAll("[data-speed]").forEach(btn => btn.addEventListener("click", () => {
    speed = +btn.dataset.speed;
    document.querySelectorAll("[data-speed]").forEach(x => x.setAttribute("aria-pressed", String(x === btn)));
  }));
  $("reset").addEventListener("click", () => { reset(); render(); });

  reset(); focused = false; render();
  let prev = performance.now();
  setInterval(() => {
    const now = performance.now(), dt = (now - prev) / 1000 * speed; prev = now;
    st.simNow += dt;
    const c = cur();
    if (c && c.k === "clip" && st.playing) { st.t += dt; if (st.t >= c.dur) { st.t = c.dur; st.playing = false; note("clip ended, holding last frame"); } }
    if (pending && now > pending.until) pending = null;
    render();
  }, 100);
})();
