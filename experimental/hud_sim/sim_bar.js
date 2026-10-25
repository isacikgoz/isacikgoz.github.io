// The simulator's action bar (slosh_sim.html): the druid's spells on the HUD's upper row (keys 1-6, as the
// game's Bar 1, paged by form), placed where Bars.lua stands it on the frame. Shapeshifts live in Ring.lua's
// Forms fan. This draws the browser buttons, cooldowns, cast bar, errors and tooltips; the fight is sim_fight.js.
import { SPELLS, BARS, POWER } from "./sim_fight.js";

// Bars.lua's rows, in HUD units: 31.36 wide, 3 apart, 13 a row, the rows 3.5 apart, the lower 7.5 over the HUD's
// bottom (flush with the screen's); Sphere.lua's frame top (one slot) and Bars.lua's CAST_UP; the
// spheres (Sphere.lua ORB_X, ORB_Y, BALL) for the touch row's place
const SIZE = 31.36, GAP = 3, ROW_GAP = 3.5, BOTTOM = 7.5, COLUMNS = 13, SINK = 0, FRAME_TOP = 120.9, CAST_UP = 40;
const ORB_X = 320, ORB_Y = 92, BALL = 182;
const TOUCH = 46, TOUCH_LEAST = 38, TOUCH_GAP = 6; // CSS px: the touch row's buttons, down to 38 to fit between the spheres
const EXTRAS = { // the simulator's own buttons: name, what they do
  spawn: ["A random fight", "A Gnarlpine warrior or a nightsaber comes out ahead of you (the simulator's own, not the game's)."],
  auto: ["Fight for me", "Plays one fight after another for you; click again to stop (the simulator's own, not the game's)."],
};

// ---------------------------------------------------------------- icons: a dark square, a light, a sign
function iconCanvas(draw, from, to) {
  const n = 64, c = document.createElement("canvas");
  c.width = c.height = n;
  const g = c.getContext("2d"), bg = g.createRadialGradient(n * 0.4, n * 0.35, 4, n / 2, n / 2, n * 0.75);
  bg.addColorStop(0, from);
  bg.addColorStop(1, to);
  g.fillStyle = bg;
  g.fillRect(0, 0, n, n);
  g.lineCap = g.lineJoin = "round";
  draw(g, n);
  return c;
}
const glowOn = (g, color, blur) => { g.shadowColor = color; g.shadowBlur = blur; };
function star(g, x, y, r1, r2, points) {
  g.beginPath();
  for (let i = 0; i < points * 2; i++) {
    const r = i % 2 ? r2 : r1, a = (i / (points * 2)) * Math.PI * 2 - Math.PI / 2;
    g.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r);
  }
  g.closePath();
}
function crescent(g, x, y, r, color) {
  g.fillStyle = color;
  g.beginPath();
  g.arc(x, y, r, 0, Math.PI * 2);
  g.arc(x + r * 0.45, y - r * 0.2, r * 0.85, 0, Math.PI * 2, true);
  g.fill("evenodd");
}
function leafShape(g, x, y, len, angle, color) {
  g.save();
  g.translate(x, y);
  g.rotate(angle);
  g.fillStyle = color;
  g.beginPath();
  g.moveTo(0, 0);
  g.quadraticCurveTo(len * 0.45, -len * 0.35, len, 0);
  g.quadraticCurveTo(len * 0.45, len * 0.35, 0, 0);
  g.fill();
  g.restore();
}
function slashes(g, n, color, count = 3) {
  glowOn(g, color, 6);
  g.strokeStyle = color;
  g.lineWidth = 4;
  for (let i = 0; i < count; i++) {
    g.beginPath();
    g.moveTo(n * (0.22 + i * 0.16), n * 0.2);
    g.quadraticCurveTo(n * (0.42 + i * 0.16), n * 0.5, n * (0.3 + i * 0.16), n * 0.82);
    g.stroke();
  }
}
function paw(g, n, color) {
  g.fillStyle = color;
  g.beginPath();
  g.ellipse(n / 2, n * 0.62, n * 0.17, n * 0.14, 0, 0, Math.PI * 2);
  g.fill();
  for (const [x, y] of [[0.3, 0.42], [0.43, 0.32], [0.57, 0.32], [0.7, 0.42]]) {
    g.beginPath();
    g.ellipse(n * x, n * y, n * 0.065, n * 0.08, 0, 0, Math.PI * 2);
    g.fill();
  }
}
// the simulator's own two (not the game's): crossed blades in a turning arrow (Fight for me), a red mark with a
// question in it (a random foe)
function blades(g, n) {
  for (const side of [-1, 1]) {
    g.save();
    g.translate(n / 2, n / 2);
    g.rotate(side * Math.PI / 4);
    g.fillStyle = "#e6e9f0";
    g.beginPath(); g.moveTo(-2.5, -24); g.lineTo(2.5, -24); g.lineTo(2.5, 10); g.lineTo(0, 14); g.lineTo(-2.5, 10); g.fill();
    g.fillStyle = "#d8a93c";
    g.fillRect(-8, 10, 16, 3.5); // the guard
    g.fillRect(-2, 13, 4, 9);    // the grip
    g.restore();
  }
}
const ICONS = {
  auto: () => iconCanvas((g, n) => {
    blades(g, n);
    glowOn(g, "#ffd36b", 4);
    g.strokeStyle = "#ffd36b";
    g.lineWidth = 3;
    g.beginPath(); g.arc(n / 2, n / 2, 26, -0.3, Math.PI * 1.55); g.stroke();
    g.fillStyle = "#ffd36b";
    g.beginPath(); g.moveTo(n / 2 + 26 * Math.cos(-0.3) + 6, n / 2 + 26 * Math.sin(-0.3) - 2); g.lineTo(n / 2 + 26 * Math.cos(-0.3) - 6, n / 2 + 26 * Math.sin(-0.3) - 4);
    g.lineTo(n / 2 + 26 * Math.cos(-0.3) + 1, n / 2 + 26 * Math.sin(-0.3) + 6); g.fill();
  }, "#6a2a1e", "#1c0a06"),
  spawn: () => iconCanvas((g, n) => {
    glowOn(g, "#ff4a3a", 6);
    g.strokeStyle = "#ff5a48";
    g.lineWidth = 3.5;
    g.beginPath(); g.arc(n / 2, n / 2, 19, 0, Math.PI * 2); g.stroke();
    for (let i = 0; i < 4; i++) {
      const a = i * Math.PI / 2;
      g.beginPath(); g.moveTo(n / 2 + Math.cos(a) * 13, n / 2 + Math.sin(a) * 13); g.lineTo(n / 2 + Math.cos(a) * 27, n / 2 + Math.sin(a) * 27); g.stroke();
    }
    g.shadowBlur = 0;
    g.fillStyle = "#ffe6d8";
    g.font = "bold 22px Georgia, serif";
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillText("?", n / 2, n / 2 + 1);
  }, "#3a3438", "#100c10"),
  wrath: () => iconCanvas((g, n) => {
    glowOn(g, "#f4ff8a", 14);
    g.fillStyle = "#eaff7a";
    star(g, n / 2, n / 2, n * 0.38, n * 0.13, 7);
    g.fill();
    g.fillStyle = "#ffffff";
    g.beginPath(); g.arc(n / 2, n / 2, n * 0.1, 0, Math.PI * 2); g.fill();
  }, "#5d8a2a", "#16260c"),
  moonfire: () => iconCanvas((g, n) => {
    glowOn(g, "#9fd8ff", 10);
    g.fillStyle = "rgba(170,220,255,0.55)";
    g.fillRect(n * 0.42, 0, n * 0.16, n);
    crescent(g, n * 0.45, n * 0.45, n * 0.24, "#eaf4ff");
  }, "#2b3d86", "#0b1030"),
  starfire: () => iconCanvas((g, n) => {
    glowOn(g, "#ffd36b", 16);
    g.fillStyle = "#ffe08a";
    star(g, n / 2, n * 0.48, n * 0.34, n * 0.15, 5);
    g.fill();
  }, "#5b2f86", "#170a26"),
  rejuvenation: () => iconCanvas((g, n) => {
    glowOn(g, "#b8ff9a", 8);
    leafShape(g, n * 0.5, n * 0.52, n * 0.34, -2.4, "#9be86e");
    leafShape(g, n * 0.5, n * 0.52, n * 0.34, -0.7, "#6cc84a");
    leafShape(g, n * 0.5, n * 0.52, n * 0.3, 1.0, "#c4ff9a");
  }, "#2f6a35", "#0c1f10"),
  healingTouch: () => iconCanvas((g, n) => {
    glowOn(g, "#d6ffb8", 14);
    g.fillStyle = "#e8ffd2";
    g.fillRect(n * 0.42, n * 0.2, n * 0.16, n * 0.6);
    g.fillRect(n * 0.2, n * 0.42, n * 0.6, n * 0.16);
  }, "#3d8a3c", "#0f2610"),
  maul: () => iconCanvas((g, n) => slashes(g, n, "#ffe2c4"), "#7a3b22", "#200c06"),
  swipe: () => iconCanvas((g, n) => {
    glowOn(g, "#ffe2c4", 8);
    g.strokeStyle = "#ffe2c4";
    g.lineWidth = 5;
    g.beginPath(); g.arc(n * 0.5, n * 0.95, n * 0.55, -2.6, -0.55); g.stroke();
    g.lineWidth = 3;
    g.beginPath(); g.arc(n * 0.5, n * 0.95, n * 0.4, -2.5, -0.65); g.stroke();
  }, "#6b4a2a", "#1d1208"),
  enrage: () => iconCanvas((g, n) => {
    glowOn(g, "#ff6a3a", 14);
    g.fillStyle = "#ff8a4a";
    star(g, n / 2, n / 2, n * 0.36, n * 0.18, 9);
    g.fill();
    paw(g, n, "#3a0c06");
  }, "#a02a16", "#2a0604"),
  claw: () => iconCanvas((g, n) => slashes(g, n, "#f2e8ff"), "#5a3f8a", "#170d28"),
  rake: () => iconCanvas((g, n) => slashes(g, n, "#ff6a6a", 2), "#4a2a3a", "#14060c"),
  bite: () => iconCanvas((g, n) => {
    g.fillStyle = "#fff6ea";
    for (const [x, flip] of [[0.32, 1], [0.68, 1], [0.32, -1], [0.68, -1]]) {
      g.beginPath();
      const y = flip > 0 ? n * 0.25 : n * 0.75;
      g.moveTo(n * (x - 0.1), y); g.lineTo(n * (x + 0.1), y); g.lineTo(n * x, y + flip * n * 0.26);
      g.fill();
    }
  }, "#8a1f22", "#24060a"),
  caster: () => iconCanvas((g, n) => {
    crescent(g, n * 0.5, n * 0.42, n * 0.22, "#e6dcff");
    leafShape(g, n * 0.28, n * 0.8, n * 0.28, -0.5, "#7fd06a");
    leafShape(g, n * 0.72, n * 0.8, n * 0.28, -2.6, "#5fb04c");
  }, "#5a3f8a", "#170d28"),
  bear: () => iconCanvas((g, n) => paw(g, n, "#3a2416"), "#9a6a42", "#2a1a0e"),
  cat: () => iconCanvas((g, n) => {
    g.fillStyle = "#f5d35a";
    glowOn(g, "#f5d35a", 8);
    for (const x of [0.33, 0.67]) {
      g.beginPath(); g.ellipse(n * x, n * 0.5, n * 0.12, n * 0.07, 0, 0, Math.PI * 2); g.fill();
    }
    g.shadowBlur = 0;
    g.fillStyle = "#1a1026";
    for (const x of [0.33, 0.67]) g.fillRect(n * x - 1.5, n * 0.43, 3, n * 0.14);
  }, "#54407c", "#120a20"),
  travel: () => iconCanvas((g, n) => {
    g.strokeStyle = "#fff0c8";
    g.lineWidth = 3;
    for (let i = 0; i < 3; i++) { g.beginPath(); g.moveTo(n * 0.15, n * (0.35 + i * 0.15)); g.lineTo(n * (0.55 + i * 0.08), n * (0.35 + i * 0.15)); g.stroke(); }
    g.fillStyle = "#3a2410";
    for (const [x, y] of [[0.7, 0.3], [0.8, 0.55], [0.62, 0.7]]) { g.beginPath(); g.arc(n * x, n * y, n * 0.06, 0, Math.PI * 2); g.fill(); }
  }, "#d9a650", "#4a3010"),
  moonkin: () => iconCanvas((g, n) => {
    crescent(g, n * 0.42, n * 0.42, n * 0.24, "#fff1a0");
    g.fillStyle = "#c9b8ff";
    leafShape(g, n * 0.55, n * 0.82, n * 0.3, -1.2, "#b9a6ff");
  }, "#3b2f6a", "#0e0a22"),
};

// an icon as an image URL, made once (sim_rings.js's spellbook shows them too)
const iconURLs = {};
export const iconURL = id => (iconURLs[id] ||= ICONS[id]().toDataURL());
export { iconCanvas, glowOn, star, crescent, leafShape, paw };

// ---------------------------------------------------------------- the bar
// view: the scene's element; frame: the brass bevel (Media/SlotFrame) as an image URL; act: { cast(id),
// shift(form), jump() } the page's; touch: a touch screen (the touch row too)
export function createBar(view, frame, act, touch = false) {
  const root = document.createElement("div");
  root.className = "hudbar";
  view.appendChild(root);
  const iconFor = iconURL;
  function slot(row, column, keyText) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "slot";
    b.innerHTML = `<img class="icon" alt=""><img class="edge" alt="" src="${frame}"><span class="cd"></span><span class="key">${keyText}</span>`;
    b.hidden = true;
    root.appendChild(b);
    return { b, row, column, icon: b.querySelector(".icon"), cd: b.querySelector(".cd"), key: b.querySelector(".key"), id: null };
  }
  const spells = Array.from({ length: 6 }, (_, i) => slot(1, i, String(i + 1)));
  spells.forEach(s => s.b.addEventListener("click", () => { if (s.id) act.cast(s.id); }));
  // the simulator's own, at the lower row's end under the Bag hub (the player's: "add a "spell" under the bag icon to
  // auto fight toggle, and left to it, spawn random enemy"): a random fight, then Fight for me
  const extras = [["spawn", 11], ["auto", 12]].map(([id, column]) => {
    const s = slot(2, column, "");
    s.id = id;
    s.b.dataset.id = id;
    s.icon.src = iconFor(id);
    s.b.hidden = false;
    s.b.addEventListener("click", () => { if (act[id]) act[id](); });
    return s;
  });
  // Touch screens: the HUD's spells again in big buttons and a jump; forms stay in their ring.
  const row = document.createElement("div");
  row.className = "touchrow";
  row.hidden = !touch;
  root.appendChild(row);
  const big = (cls, label) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "big " + cls;
    b.setAttribute("aria-label", label);
    b.innerHTML = '<img class="icon" alt=""><span class="cd"></span>';
    row.appendChild(b);
    return b;
  };
  const bigSpells = Array.from({ length: 6 }, () => { const b = big("spell", ""); b.hidden = true; return b; });
  bigSpells.forEach(b => b.addEventListener("click", () => { if (b.dataset.id) act.cast(b.dataset.id); }));
  const jumpButton = big("jump", "Jump");
  jumpButton.innerHTML = "<span>Jump</span>";
  jumpButton.addEventListener("click", () => act.jump());
  // the cast bar, the error line, the combo points, the tooltip
  const castBar = document.createElement("div");
  castBar.className = "castbar";
  castBar.innerHTML = '<div class="fill"></div><span class="name"></span><span class="time"></span>';
  castBar.hidden = true;
  root.appendChild(castBar);
  const errors = document.createElement("div");
  errors.className = "errors";
  errors.setAttribute("role", "status");
  root.appendChild(errors);
  const combo = document.createElement("div");
  combo.className = "combo";
  combo.innerHTML = "<i></i>".repeat(5);
  combo.hidden = true;
  root.appendChild(combo);
  const tip = document.createElement("div");
  tip.className = "tip";
  tip.hidden = true;
  root.appendChild(tip);
  function tooltip(s) {
    if (!s.id) return;
    let html;
    if (SPELLS[s.id]) {
      const sp = SPELLS[s.id];
      const cost = sp.cost ? `${sp.cost[1]}% ${sp.cost[0]}` : sp.gain ? `Gives ${sp.gain[1]}% ${sp.gain[0]}` : "";
      const range = sp.range > 4 ? `${sp.range} yd range` : sp.range ? "Melee range" : "";
      html = `<b>${sp.name}</b><div class="row"><span>${cost}</span><span>${range}</span></div>` +
        `<div class="row"><span>${sp.cast ? sp.cast + " sec cast" : "Instant"}</span><span>${sp.cooldown ? sp.cooldown + " sec cooldown" : ""}</span></div>` +
        `<p>${sp.text}</p>`;
    } else if (EXTRAS[s.id]) html = `<b>${EXTRAS[s.id][0]}</b><p>${EXTRAS[s.id][1]}</p>`;
    else html = `<b>${s.id}</b>`;
    tip.innerHTML = html;
    tip.hidden = false;
    const box = s.b.getBoundingClientRect(), into = view.getBoundingClientRect();
    tip.style.left = Math.min(into.width - tip.offsetWidth - 8, Math.max(8, box.left - into.left)) + "px";
    tip.style.bottom = (into.bottom - box.top + 8) + "px";
  }
  for (const s of [...spells, ...extras]) { // tooltips for a mouse (a finger's tap would cast under it)
    s.b.addEventListener("pointerenter", e => { if (e.pointerType !== "touch") tooltip(s); });
    s.b.addEventListener("pointerleave", () => { tip.hidden = true; });
  }
  let errorTimer = 0, placed = null, rowTop = 0, rowCount = -1;
  // the touch row: over the frame between the spheres where it fits, else over the spheres (laid out again when
  // its buttons come and go)
  function placeRow() {
    if (!touch || !placed) return;
    const [origin, ppu, dpr] = placed, css = u => u * ppu / dpr;
    const count = [...row.children].filter(b => !b.hidden).length, between = 2 * css(ORB_X - BALL / 2) - 12;
    const widthAt = size => count * (size + TOUCH_GAP) - TOUCH_GAP + 0.26 * size + 2; // the jump a quarter wider
    const biggest = room => { let size = TOUCH; while (widthAt(size) > room && size > TOUCH_LEAST) size -= 2; return size; };
    // between the spheres at the biggest size that fits there (a short screen's are close together), else over them
    // as big as the scene's width takes
    let size = biggest(between);
    const fits = widthAt(size) <= between;
    if (!fits) size = biggest(view.clientWidth - 16);
    const width = widthAt(size);
    const bottom = origin[1] / dpr + (fits ? css(FRAME_TOP - SINK) + 8 : css(ORB_Y - SINK + BALL / 2) + 8);
    row.style.setProperty("--touch", size + "px");
    Object.assign(row.style, { left: (origin[0] / dpr - width / 2) + "px", bottom: bottom + "px" });
    rowTop = bottom + size;
    rowCount = count;
  }
  let gameState = null;
  return {
    // where the HUD stands: origin (device px of HUD (0, 0): its middle on the screen's bottom edge), ppu (device
    // px a unit), dpr
    layout(origin, ppu, dpr) {
      const css = u => u * ppu / dpr, left0 = -(COLUMNS * SIZE + (COLUMNS - 1) * GAP) / 2;
      root.style.setProperty("--u", css(1) + "px"); // a HUD unit in CSS px: what scales with the buttons
      for (const s of [...spells, ...extras]) {
        const frame = gameState && gameState.rows && gameState.rows[s.row - 1] && gameState.rows[s.row - 1][s.column + 1];
        const left = s.row === 1 ? (frame && frame.w || SIZE) + GAP : 0;
        const x = frame ? frame.x - 960 - left : left0 + s.column * (SIZE + GAP) - left;
        const y = frame ? frame.y : BOTTOM - SINK + (s.row === 1 ? SIZE + ROW_GAP : 0);
        const w = frame && frame.w || SIZE, h = frame && frame.h || SIZE;
        Object.assign(s.b.style, { left: (origin[0] / dpr + css(x)) + "px", bottom: (origin[1] / dpr + css(y)) + "px",
          width: css(w) + "px", height: css(h) + "px", fontSize: Math.max(9, css(11)) + "px" });
      }
      const cast = gameState && gameState.cast;
      const castW = cast && cast.w || 200, castH = cast && cast.h || 13, castX = cast ? cast.x - 960 : -castW / 2;
      const castY = cast ? cast.y : FRAME_TOP + CAST_UP - SINK;
      Object.assign(castBar.style, { left: (origin[0] / dpr + css(castX)) + "px", bottom: (origin[1] / dpr + css(castY)) + "px",
        width: css(castW) + "px", height: Math.max(14, css(castH)) + "px", fontSize: Math.max(10, css(10)) + "px" });
      Object.assign(combo.style, { left: (origin[0] / dpr + css(left0)) + "px", bottom: (origin[1] / dpr + css(BOTTOM - SINK + 2 * SIZE + ROW_GAP + 3)) + "px" });
      root.classList.toggle("tiny", css(SIZE) < 22); // a phone's HUD: its buttons too small for their key labels
      placed = [origin, ppu, dpr];
      placeRow();
    },
    // the touch row's top, CSS px over the scene's bottom (none: 0): the world keeps you standing above it
    rowTop() { return touch && !row.hidden ? rowTop : 0; },
    // each frame: what the buttons show (the fight's state for the place you're in: ctx, as sim_fight.js check)
    update(fight, ctx, actual = gameState) {
      gameState = actual || gameState;
      const me = fight.me, form = me.form, bar = BARS[form] || [];
      spells.forEach((s, i) => {
        const actualSlot = gameState && gameState.rows && gameState.rows[0] && gameState.rows[0][i];
        const actualId = actualSlot && actualSlot.shown && actualSlot.name || "";
        const id = gameState ? (actualId && fight.knows(actualId) ? actualId : null)
          : (bar[i] && fight.knows(bar[i]) ? bar[i] : null); // the harness's real Bars.lua decides the action slot
        if (id !== s.id) { s.id = id; s.b.hidden = !id; s.b.dataset.id = id || ""; if (id) s.icon.src = iconFor(id); }
        if (!id) return;
        const c = fight.check(id, ctx), sp = SPELLS[id];
        s.b.classList.toggle("nopower", c.why === "power");
        s.b.classList.toggle("unusable", c.why === "form" || c.why === "target" || c.why === "dead");
        s.key.classList.toggle("far", c.why === "range" || c.why === "facing");
        s.b.classList.toggle("active", !!me.cast && me.cast.id === id);
        const cdLeft = Math.max(0, (me.cds[id] || 0) - fight.time), gcdLeft = Math.max(0, me.gcd - fight.time);
        const left = Math.max(cdLeft, gcdLeft), whole = cdLeft >= gcdLeft ? sp.cooldown || 1 : (form === "cat" ? 1 : 1.5);
        s.cd.style.setProperty("--p", left > 0 ? (left / whole * 100).toFixed(1) + "%" : "0%");
        s.cd.textContent = cdLeft > 1.5 ? Math.ceil(cdLeft) : "";
      });
      extras[1].b.classList.toggle("checked", !!fight.auto); // Fight for me, on
      for (const s of extras) s.b.classList.toggle("unusable", me.dead);
      if (touch) { // the touch row follows the HUD's: the same spells, states and cooldowns
        bigSpells.forEach((b, i) => {
          const s = spells[i];
          if (b.dataset.id !== (s.id || "")) { b.dataset.id = s.id || ""; b.hidden = !s.id; if (s.id) { b.querySelector(".icon").src = iconURL(s.id); b.setAttribute("aria-label", SPELLS[s.id].name); } }
          if (!s.id) return;
          for (const c of ["nopower", "unusable", "active"]) b.classList.toggle(c, s.b.classList.contains(c));
          b.classList.toggle("far", s.key.classList.contains("far"));
          b.querySelector(".cd").style.setProperty("--p", s.cd.style.getPropertyValue("--p"));
        });
        if ([...row.children].filter(b => !b.hidden).length !== rowCount) placeRow();
      }
      // the cast bar: filling while you cast, its name and time left
      if (me.cast) {
        const sp = SPELLS[me.cast.id], done = (fight.time - me.cast.start) / (me.cast.end - me.cast.start);
        castBar.hidden = false;
        castBar.querySelector(".fill").style.width = Math.min(100, done * 100).toFixed(1) + "%";
        castBar.querySelector(".name").textContent = sp.name;
        castBar.querySelector(".time").textContent = Math.max(0, me.cast.end - fight.time).toFixed(1);
      } else castBar.hidden = true;
      combo.hidden = form !== "cat";
      [...combo.children].forEach((p, i) => p.classList.toggle("on", i < me.combo));
    },
    // the game's red line at the top: one at a time, fading
    error(text) {
      errors.textContent = text;
      errors.classList.remove("fade");
      void errors.offsetWidth;
      errors.classList.add("fade");
      clearTimeout(errorTimer);
      errorTimer = setTimeout(() => { errors.textContent = ""; }, 2400);
    },
    power: form => POWER[form],
  };
}
