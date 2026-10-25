// The simulator's rings (slosh_sim.html): Spheres' game menu hub in the right frame well and its Bags hub at the
// upper row's last place, each opening its fan round the map sphere as Ring.lua lays them out (Ring:Orbit and
// Ring:OrbitBags, ported here: keep them in step), in the HUD's units from the add-on's own geometry (the
// bridge's init: S.Liquids). The menu's Character (C) and Spellbook (P) open windows, its others are the game's
// own (a note says so); the bags' buttons open their bags (B: all of them), whose potions work in a fight.
import { SPELLS, FORMS, LEVELS, ITEMS } from "./sim_fight.js";
import { iconURL, iconCanvas, glowOn, star, crescent, leafShape, paw } from "./sim_bar.js";

// Ring.lua R.MICRO, in its order: what each is, its key in the game, the window it opens here; the round ones
// (the minimap header's) on a disc
const MICRO = [
  ["character", "Character Info", "C", "character"], ["professions", "Professions", "K"],
  ["spellbook", "Spellbook & Abilities", "P", "spellbook"], ["talents", "Talents", "N"], ["achievements", "Achievements", "Y"],
  ["quests", "Quest Log", "L"], ["guild", "Guild & Communities", "J"], ["lfg", "Group Finder", "I"], ["collections", "Collections"],
  ["calendar", "Calendar", "", null, true], ["diel", "Night", "", null, true], ["tracking", "Tracking", "", null, true],
  ["addons", "AddOns", "", null, true], ["help", "Customer Support"], ["menu", "Game Menu", "Esc"],
];
// Ring.lua R.BAGS (no reagent bag in the Classic world): what it is, its slots, what's in it
const BAGS = [
  ["backpack", "Backpack", 16, [["healingPotion", 5], ["manaPotion", 4], ["hearthstone", 1], ["linenCloth", 12], ["peacebloom", 7],
    ["brokenFang", 3], ["moonberry", 6]]],
  ["bag1", "Small Brown Pouch", 6, [["silverleaf", 5]]], ["bag2", "Linen Bag", 8, [["linenCloth", 8], ["owlbearFeather", 1]]],
  ["bag3", "Woolen Bag", 10, []], ["bag4", "Traveler's Backpack", 14, [["peacebloom", 3]]], ["keyring", "Keyring", 4, []],
];
const SHIFTS = ["bear", "cat", "travel", "moonkin"];
const SHIFT_CHOICES = ["caster", ...SHIFTS];
const SHIFT_NAMES = { caster: "Caster Form (return to your usual form)", bear: "Bear Form", cat: "Cat Form", travel: "Travel Form", moonkin: "Moonkin Form" };
const MENU = { angle: 88, size: 46, disc: 36 };    // Ring.lua: the menu's dock (the right well), MENU_SIZE, A.MINIMAP_SIZE
const BAG_SIZE = 32;                                // the Bag hub's width (Bars.lua's row slot)
const ROW = { size: 32, gap: 3, gapRows: 4, bottom: 15, columns: 13 }; // Bars.lua's rows: the Bag hub at the upper's last
const rad = d => d * Math.PI / 180;
const QUALITY = { poor: "#9d9d9d", common: "#ffffff", uncommon: "#1eff00" };

// ---------------------------------------------------------------- icons: the menu's, the bags', the items'
const book = (g, n, cover) => {
  g.fillStyle = cover; g.fillRect(n * 0.24, n * 0.2, n * 0.52, n * 0.62);
  g.fillStyle = "#f2e6c4"; g.fillRect(n * 0.3, n * 0.24, n * 0.42, n * 0.54);
  g.fillStyle = cover; g.fillRect(n * 0.24, n * 0.2, n * 0.08, n * 0.62);
};
const flask = (g, n, liquid) => {
  glowOn(g, liquid, 8);
  g.fillStyle = liquid;
  g.beginPath(); g.arc(n * 0.5, n * 0.62, n * 0.22, 0, Math.PI * 2); g.fill();
  g.shadowBlur = 0;
  g.fillStyle = "#c9d4dc"; g.fillRect(n * 0.43, n * 0.22, n * 0.14, n * 0.2);
  g.fillStyle = "#7a5a3a"; g.fillRect(n * 0.41, n * 0.17, n * 0.18, n * 0.07);
  g.fillStyle = "rgba(255,255,255,0.45)"; g.beginPath(); g.arc(n * 0.43, n * 0.56, n * 0.06, 0, Math.PI * 2); g.fill();
};
const sack = (g, n, cloth, tie) => {
  g.fillStyle = cloth;
  g.beginPath(); g.ellipse(n * 0.5, n * 0.6, n * 0.27, n * 0.24, 0, 0, Math.PI * 2); g.fill();
  g.beginPath(); g.moveTo(n * 0.36, n * 0.4); g.lineTo(n * 0.5, n * 0.24); g.lineTo(n * 0.64, n * 0.4); g.fill();
  g.strokeStyle = tie; g.lineWidth = 3; g.beginPath(); g.moveTo(n * 0.38, n * 0.4); g.lineTo(n * 0.62, n * 0.4); g.stroke();
};
const ICONS = {
  character: () => iconCanvas((g, n) => {
    g.fillStyle = "#d8c49a";
    g.beginPath(); g.arc(n * 0.5, n * 0.36, n * 0.14, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.ellipse(n * 0.5, n * 0.86, n * 0.3, n * 0.28, 0, Math.PI, 0); g.fill();
  }, "#5a4a3a", "#16100a"),
  professions: () => iconCanvas((g, n) => {
    g.save(); g.translate(n / 2, n / 2); g.rotate(-0.7);
    g.fillStyle = "#8a6a44"; g.fillRect(-n * 0.04, -n * 0.05, n * 0.08, n * 0.4);
    g.fillStyle = "#c9ccd2"; g.fillRect(-n * 0.18, -n * 0.18, n * 0.36, n * 0.16);
    g.restore();
  }, "#4a5a6a", "#10161c"),
  spellbook: () => iconCanvas((g, n) => book(g, n, "#7a2e2e"), "#3a3a6a", "#0c0c1c"),
  talents: () => iconCanvas((g, n) => { glowOn(g, "#ffd36b", 8); g.fillStyle = "#ffd36b"; star(g, n / 2, n / 2, n * 0.3, n * 0.12, 6); g.fill(); }, "#3a5a2a", "#0c1606"),
  achievements: () => iconCanvas((g, n) => {
    g.fillStyle = "#d8b45a";
    g.beginPath(); g.moveTo(n * 0.28, n * 0.24); g.lineTo(n * 0.72, n * 0.24); g.lineTo(n * 0.68, n * 0.58); g.lineTo(n * 0.5, n * 0.78); g.lineTo(n * 0.32, n * 0.58); g.fill();
  }, "#6a4a2a", "#1c1006"),
  quests: () => iconCanvas((g, n) => {
    glowOn(g, "#ffd100", 10); g.fillStyle = "#ffd100";
    g.fillRect(n * 0.44, n * 0.2, n * 0.12, n * 0.4); g.beginPath(); g.arc(n * 0.5, n * 0.74, n * 0.07, 0, Math.PI * 2); g.fill();
  }, "#5a4a2a", "#1a1206"),
  guild: () => iconCanvas((g, n) => {
    g.fillStyle = "#8a6a44"; g.fillRect(n * 0.3, n * 0.18, n * 0.05, n * 0.64);
    g.fillStyle = "#3b6f8f"; g.beginPath(); g.moveTo(n * 0.35, n * 0.2); g.lineTo(n * 0.74, n * 0.2); g.lineTo(n * 0.74, n * 0.56);
    g.lineTo(n * 0.55, n * 0.48); g.lineTo(n * 0.35, n * 0.56); g.fill();
  }, "#2a3a4a", "#0a1016"),
  lfg: () => iconCanvas((g, n) => {
    g.fillStyle = "#e8f0ff"; g.beginPath(); g.ellipse(n / 2, n / 2, n * 0.3, n * 0.17, 0, 0, Math.PI * 2); g.fill();
    glowOn(g, "#7fd0ff", 8); g.fillStyle = "#3b8fdf"; g.beginPath(); g.arc(n / 2, n / 2, n * 0.11, 0, Math.PI * 2); g.fill();
  }, "#2a2a4a", "#0a0a18"),
  collections: () => iconCanvas((g, n) => {
    g.strokeStyle = "#d8c49a"; g.lineWidth = 6; g.beginPath(); g.arc(n / 2, n * 0.46, n * 0.2, Math.PI * 0.15, Math.PI * 1.85, true); g.stroke();
  }, "#5a3a5a", "#160a16"),
  calendar: () => iconCanvas((g, n) => {
    g.fillStyle = "#f2ead6"; g.fillRect(n * 0.24, n * 0.26, n * 0.52, n * 0.5);
    g.fillStyle = "#b8322a"; g.fillRect(n * 0.24, n * 0.22, n * 0.52, n * 0.12);
    g.fillStyle = "#2a2a2a"; g.font = `bold ${n * 0.26}px Georgia`; g.textAlign = "center"; g.fillText("23", n / 2, n * 0.68);
  }, "#4a4a4a", "#101010"),
  diel: () => iconCanvas((g, n) => crescent(g, n * 0.48, n * 0.5, n * 0.24, "#e6ecff"), "#2a3a7a", "#060a20"),
  tracking: () => iconCanvas((g, n) => {
    g.strokeStyle = "#e8e0c8"; g.lineWidth = 5; g.beginPath(); g.arc(n * 0.44, n * 0.44, n * 0.16, 0, Math.PI * 2); g.stroke();
    g.lineWidth = 7; g.beginPath(); g.moveTo(n * 0.56, n * 0.56); g.lineTo(n * 0.74, n * 0.74); g.stroke();
  }, "#4a5a3a", "#10160a"),
  addons: () => iconCanvas((g, n) => {
    g.fillStyle = "#8fd06a";
    for (const [x, y] of [[0.28, 0.28], [0.52, 0.28], [0.28, 0.52], [0.52, 0.52]]) g.fillRect(n * x, n * y, n * 0.2, n * 0.2);
  }, "#2a4a3a", "#08140e"),
  help: () => iconCanvas((g, n) => {
    g.fillStyle = "#e8f0ff"; g.font = `bold ${n * 0.56}px Georgia`; g.textAlign = "center"; g.textBaseline = "middle"; g.fillText("?", n / 2, n * 0.54);
  }, "#2a4a7a", "#081428"),
  menu: () => iconCanvas((g, n) => {
    glowOn(g, "#ffd36b", 6); g.fillStyle = "#d8b45a"; star(g, n / 2, n / 2, n * 0.32, n * 0.24, 8); g.fill();
    g.shadowBlur = 0; g.fillStyle = "#1a1408"; g.beginPath(); g.arc(n / 2, n / 2, n * 0.1, 0, Math.PI * 2); g.fill();
  }, "#3a3a3a", "#0e0e0e"),
  backpack: () => iconCanvas((g, n) => sack(g, n, "#8a5a32", "#3a2414"), "#4a3a2a", "#120c06"),
  bag1: () => iconCanvas((g, n) => sack(g, n, "#6a4a2a", "#2a1a0a"), "#3a2e22", "#100a06"),
  bag2: () => iconCanvas((g, n) => sack(g, n, "#c9b08a", "#6a5a3a"), "#4a4234", "#12100c"),
  bag3: () => iconCanvas((g, n) => sack(g, n, "#9a8ab0", "#4a3a6a"), "#3a3448", "#0e0c14"),
  bag4: () => iconCanvas((g, n) => sack(g, n, "#5a7a4a", "#2a3a1a"), "#2e3a28", "#0a1008"),
  keyring: () => iconCanvas((g, n) => {
    g.strokeStyle = "#d8b45a"; g.lineWidth = 5; g.beginPath(); g.arc(n * 0.38, n * 0.4, n * 0.14, 0, Math.PI * 2); g.stroke();
    g.beginPath(); g.moveTo(n * 0.48, n * 0.5); g.lineTo(n * 0.74, n * 0.76); g.moveTo(n * 0.66, n * 0.68); g.lineTo(n * 0.6, n * 0.74); g.stroke();
  }, "#3a3a2a", "#0e0e08"),
  healingPotion: () => iconCanvas((g, n) => flask(g, n, "#e8282a"), "#3a1a1a", "#0e0606"),
  manaPotion: () => iconCanvas((g, n) => flask(g, n, "#2a6aff"), "#1a1a3a", "#06060e"),
  moonberry: () => iconCanvas((g, n) => flask(g, n, "#a04ad8"), "#2a1a3a", "#0a060e"),
  hearthstone: () => iconCanvas((g, n) => {
    g.fillStyle = "#8a8f9a"; g.beginPath(); g.ellipse(n / 2, n / 2, n * 0.26, n * 0.3, 0, 0, Math.PI * 2); g.fill();
    glowOn(g, "#7fe0ff", 8); g.strokeStyle = "#9fefff"; g.lineWidth = 3;
    g.beginPath(); g.moveTo(n * 0.42, n * 0.36); g.lineTo(n * 0.58, n * 0.5); g.lineTo(n * 0.44, n * 0.64); g.stroke();
  }, "#2a3a4a", "#080e14"),
  linenCloth: () => iconCanvas((g, n) => {
    g.fillStyle = "#e6dcc0"; g.fillRect(n * 0.22, n * 0.34, n * 0.56, n * 0.32);
    g.fillStyle = "#c9bc9a"; g.fillRect(n * 0.22, n * 0.46, n * 0.56, n * 0.06);
  }, "#4a4434", "#12100c"),
  peacebloom: () => iconCanvas((g, n) => {
    leafShape(g, n * 0.5, n * 0.75, n * 0.3, -1.9, "#5fa04a");
    g.fillStyle = "#f2f0e8"; for (let i = 0; i < 5; i++) { const a = i * 1.257; g.beginPath(); g.arc(n * 0.5 + Math.cos(a) * n * 0.12, n * 0.4 + Math.sin(a) * n * 0.12, n * 0.08, 0, Math.PI * 2); g.fill(); }
    g.fillStyle = "#f5d35a"; g.beginPath(); g.arc(n * 0.5, n * 0.4, n * 0.06, 0, Math.PI * 2); g.fill();
  }, "#2e4a2a", "#0a120a"),
  silverleaf: () => iconCanvas((g, n) => { leafShape(g, n * 0.28, n * 0.72, n * 0.5, -0.8, "#c9d4dc"); }, "#2e3a3a", "#0a1010"),
  brokenFang: () => iconCanvas((g, n) => {
    g.fillStyle = "#e8e2d0"; g.beginPath(); g.moveTo(n * 0.38, n * 0.24); g.lineTo(n * 0.62, n * 0.24); g.lineTo(n * 0.5, n * 0.78); g.fill();
  }, "#3a3430", "#0e0c0a"),
  owlbearFeather: () => iconCanvas((g, n) => { leafShape(g, n * 0.25, n * 0.75, n * 0.6, -0.8, "#b8a6d8"); }, "#2a2a3a", "#0a0a12"),
};
const pictures = {};
const picture = id => (pictures[id] ||= ICONS[id]().toDataURL());

// ---------------------------------------------------------------- the rings' layouts, as Ring.lua's
// The slots in an arc round the hub's sphere, outside the hub, on its side and up (its angle mirrored to the top
// half, kept 30 degrees off the horizontal), turned 10 degrees at a time until every slot is on the screen and
// above the action bar frame; no turn will do: a wider arc. (Ring:Orbit; no buffs here to keep out of.)
function orbit(n, size, s) {
  const a0 = MENU.angle <= 180 ? MENU.angle : 360 - MENU.angle, start = rad(Math.max(30, Math.min(150, a0)));
  let ro = s.r + s.hub / 2 + 6 + size / 2;
  const gap = 6, angleOf = (mid, k) => mid + (k - (n + 1) / 2) * (size + gap) / ro;
  const fits = mid => {
    for (let k = 1; k <= n; k++) {
      const a = angleOf(mid, k), x = s.cx + ro * Math.cos(a), y = s.cy + ro * Math.sin(a);
      if (x < size / 2 || x > s.W - size / 2 || y > s.H - size / 2 || y - size / 2 < s.floor + 4) return false;
    }
    return true;
  };
  const turn = () => {
    for (let j = 0; j <= 18; j++) {
      const d = rad(10 * j);
      if (fits(start + d)) return start + d;
      if (fits(start - d)) return start - d;
    }
    return null;
  };
  let mid = turn();
  const reach = Math.hypot(s.W, s.H);
  while (mid === null && ro < reach) { ro += 10; mid = turn(); }
  if (mid === null) mid = start;
  return Array.from({ length: n }, (_, i) => { const a = angleOf(mid, i + 1); return [s.cx + ro * Math.cos(a), s.cy + ro * Math.sin(a)]; });
}
// The Bags hub lives in the action row, its buttons round the map sphere: an arc just outside the hubs there,
// grown or turned to clear the screen's edge and the other hubs. (Ring:OrbitBags.)
function orbitBags(count, size, s, others) {
  const gap = 12, first = Math.max(s.r + s.hub / 2 + size / 2 + 12, 150);
  const at = (mid, rr, k) => mid + ((count + 1) / 2 - k) * (size + gap) / rr;
  const fits = (mid, rr) => {
    for (let k = 1; k <= count; k++) {
      const a = at(mid, rr, k), x = s.cx + rr * Math.cos(a), y = s.cy + rr * Math.sin(a);
      if (y - size / 2 < s.floor + 4) return false;
      if (x - size / 2 < 0 || x + size / 2 > s.W || y + size / 2 > s.H) return false;
      for (const [ox, oy, ow] of others) {
        const clear = (size + ow) / 2 + 10;
        if (Math.abs(x - ox) < clear && Math.abs(y - oy) < clear) return false;
      }
    }
    return true;
  };
  let angle = null, radius = null;
  search: for (let rr = first; rr <= first + 200; rr += 8) {
    for (let offset = 0; offset <= 12; offset++) {
      const turn = rad(5 * offset);
      for (const mid of [rad(65) + turn, rad(65) - turn]) if (fits(mid, rr)) { angle = mid; radius = rr; break search; }
    }
  }
  angle ??= rad(65);
  radius ??= first;
  return Array.from({ length: count }, (_, i) => { const a = at(angle, radius, i + 1); return [s.cx + radius * Math.cos(a), s.cy + radius * Math.sin(a)]; });
}

// ---------------------------------------------------------------- the rings, their windows
// root: the bar's layer over the scene; frames: { slot, hub } (Media/SlotFrame, Media/HubFrame as image URLs);
// act: { fight() (the fight, for the spellbook and the items), cast(spell), shift(form) }
export function createRings(root, frames, act) {
  const el = (tag, cls, parent = root) => { const e = document.createElement(tag); if (cls) e.className = cls; parent.appendChild(e); return e; };
  function button(cls, icon, frame, label, key = "") {
    const b = el("button", "slot " + cls);
    b.type = "button";
    b.innerHTML = `<img class="icon" alt="" src="${icon}"><img class="edge" alt="" src="${frame}"><span class="key">${key}</span>`;
    b.setAttribute("aria-label", label);
    b.dataset.tip = label;
    return b;
  }
  const menuHub = button("hub round", picture("menu"), frames.hub, "Game Menu: open its ring");
  const bagHub = button("hub", picture("backpack"), frames.slot, "Bags: open their ring (B opens them all)", "B");
  const menuSlots = MICRO.map(([id, label, key, , round]) => {
    const b = button("fan" + (round ? " round" : " micro"), picture(id), round ? frames.hub : frames.slot, label + (key ? ` (${key})` : ""));
    b.dataset.id = id;
    b.hidden = true;
    return b;
  });
  const bagSlots = BAGS.map(([id, label, n]) => {
    const b = button("fan", picture(id), frames.slot, `${label}, ${n} slots`);
    b.dataset.id = id;
    b.hidden = true;
    return b;
  });
  const formHub = button("hub round", iconURL("caster"), frames.hub, "Druid Forms: open the stance ring");
  const formSlots = SHIFT_CHOICES.map(id => {
    const b = button("fan", iconURL(id), frames.slot, SHIFT_NAMES[id]);
    b.dataset.id = id;
    b.hidden = true;
    return b;
  });
  const fans = { menu: { hub: menuHub, slots: menuSlots, open: false }, bags: { hub: bagHub, slots: bagSlots, open: false },
    forms: { hub: formHub, slots: formSlots, open: false } };
  let gameState = null;
  const actualRing = name => gameState && gameState.rings && gameState.rings.find(r => r.id === name);
  // the tooltip, the game's note (yellow, at the top)
  const tip = el("div", "tip");
  tip.hidden = true;
  const note = el("div", "note-line");
  let noteTimer = 0;
  function say(text) {
    note.textContent = text;
    note.classList.remove("fade");
    void note.offsetWidth;
    note.classList.add("fade");
    clearTimeout(noteTimer);
    noteTimer = setTimeout(() => { note.textContent = ""; }, 3000);
  }
  function showTip(b, html) {
    tip.innerHTML = html;
    tip.hidden = false;
    const box = b.getBoundingClientRect(), into = root.getBoundingClientRect();
    tip.style.left = Math.min(into.width - tip.offsetWidth - 8, Math.max(8, box.left - into.left)) + "px";
    tip.style.bottom = (into.bottom - box.top + 8) + "px";
  }
  root.addEventListener("pointerover", e => {
    if (e.pointerType === "touch") return; // a finger's tap would use what's under it: no tooltip in the way
    const b = e.target.closest("[data-tip]");
    if (b && root.contains(b)) showTip(b, b.dataset.tipHtml || `<b>${b.dataset.tip}</b>`);
  });
  root.addEventListener("pointerout", e => { if (e.target.closest("[data-tip]")) tip.hidden = true; });

  // the windows: Character, Spellbook, a bag each
  const windows = [];
  function gameWindow(id, title, cls = "") {
    const w = el("section", "gamewin " + cls);
    w.hidden = true;
    w.dataset.id = id;
    w.setAttribute("aria-label", title);
    w.innerHTML = `<header><span>${title}</span><button type="button" class="wclose" aria-label="Close ${title}">&#215;</button></header><div class="wbody"></div>`;
    w.querySelector(".wclose").addEventListener("click", () => toggleWindow(w, false));
    windows.push(w);
    return w;
  }
  const character = gameWindow("character", "Character", "left");
  const spellbook = gameWindow("spellbook", "Spellbook & Abilities", "left");
  const bags = BAGS.map(([id, label, n, items]) => {
    const w = gameWindow(id, label, "bag");
    const grid = el("div", "bagslots", w.querySelector(".wbody"));
    const contents = items.map(([kind, count]) => ({ kind, count }));
    for (let i = 0; i < n; i++) {
      const cell = el("button", "bagslot", grid);
      cell.type = "button";
      cell.dataset.slot = i;
    }
    w.contents = contents;
    w.grid = grid;
    return w;
  });
  function drawBag(w) {
    [...w.grid.children].forEach((cell, i) => {
      const item = w.contents[i];
      cell.innerHTML = item ? `<img alt="" src="${picture(item.kind)}">${item.count > 1 ? `<span class="count">${item.count}</span>` : ""}` : "";
      const def = item && ITEMS[item.kind];
      cell.dataset.tip = def ? def.name : "";
      if (def) cell.dataset.tipHtml = `<b style="color:${QUALITY[def.quality]}">${def.name}</b>${def.use ? `<p class="use">Use: ${def.use}</p>` : ""}`;
      else { delete cell.dataset.tip; delete cell.dataset.tipHtml; }
      cell.setAttribute("aria-label", def ? `${def.name}${item.count > 1 ? `, ${item.count}` : ""}` : "Empty");
    });
  }
  bags.forEach(w => {
    drawBag(w);
    w.grid.addEventListener("click", e => { // an item used: a potion's one gone
      const cell = e.target.closest(".bagslot"), item = cell && w.contents[Number(cell.dataset.slot)];
      if (!item || !act.fight() || !act.fight().use(item.kind)) return; // used (a potion): one fewer
      item.count--;
      if (!item.count) w.contents.splice(w.contents.indexOf(item), 1);
      drawBag(w);
    });
    w.grid.addEventListener("contextmenu", e => { e.preventDefault(); e.target.closest(".bagslot")?.click(); });
  });
  function drawCharacter() {
    const f = act.fight();
    if (!f) return;
    const m = f.me;
    character.querySelector(".wbody").innerHTML = `<p class="who"><b>Lunara</b><br>Level ${f.level} Night Elf Druid</p>
      <dl><dt>Health</dt><dd>${Math.round(m.hp)}%</dd><dt>Mana</dt><dd>${Math.round(m.mana)}%</dd>
      <dt>Form</dt><dd>${m.form[0].toUpperCase() + m.form.slice(1)}</dd>
      <dt>Spells known</dt><dd>${Object.keys(SPELLS).filter(id => f.knows(id)).length} of ${Object.keys(SPELLS).length}</dd>
      <dt>Forms known</dt><dd>${FORMS.filter(id => f.knows(id)).length} of ${FORMS.length}</dd></dl>`;
  }
  function drawSpellbook() {
    const f = act.fight();
    if (!f) return;
    const entries = [...FORMS.filter(id => id !== "caster").map(id => [id, id[0].toUpperCase() + id.slice(1) + " Form"]),
      ...Object.entries(SPELLS).map(([id, s]) => [id, s.name])].sort((a, b) => LEVELS[a[0]] - LEVELS[b[0]] || a[1].localeCompare(b[1]));
    spellbook.querySelector(".wbody").innerHTML = '<div class="spells">' + entries.map(([id, name]) => {
      const known = f.knows(id), s = SPELLS[id];
      const line = s ? `${s.forms.map(x => x[0].toUpperCase() + x.slice(1)).join(", ")}${s.cast ? `, ${s.cast} sec cast` : ""}` : "Shapeshift";
      return `<button type="button" class="spell${known ? "" : " locked"}" data-id="${id}" ${known ? "" : "disabled"}>
        <img alt="" src="${iconURL(id)}"><span><b>${name}</b><small>${known ? line : `Learned at level ${LEVELS[id]}`}</small></span></button>`;
    }).join("") + "</div>";
  }
  spellbook.addEventListener("click", e => { // a known spell cast, a known form taken
    const b = e.target.closest(".spell:not(.locked)");
    if (!b) return;
    if (SPELLS[b.dataset.id]) act.cast(b.dataset.id);
    else act.shift(b.dataset.id);
  });
  function toggleWindow(w, on = w.hidden) {
    w.hidden = !on;
    if (on && w === character) drawCharacter();
    if (on && w === spellbook) drawSpellbook();
    placeWindows();
  }
  // the game's windows at the screen's left (the panels), the bags at its right above the HUD, stacked up
  let hudTopCss = 240;
  function placeWindows() {
    let left = 16;
    for (const w of [character, spellbook]) if (!w.hidden) { w.style.left = left + "px"; left += w.offsetWidth + 12; }
    let right = 16, bottom = hudTopCss + 12, column = 0;
    for (const w of bags) {
      if (w.hidden) continue;
      if (bottom + w.offsetHeight > root.clientHeight - 16 && column === 0) { column = 1; right += w.offsetWidth + 10; bottom = hudTopCss + 12; }
      Object.assign(w.style, { right: right + "px", bottom: bottom + "px" });
      bottom += w.offsetHeight + 8;
    }
  }
  function openFan(name, on) {
    const fan = fans[name];
    if (act.ring) {
      const state = act.ring(name, on);
      if (state && !state.error) gameState = state;
      const real = state && state.rings && state.rings.find(r => r.id === name);
      if (real) on = real.shown;
    }
    fan.open = on;
    fan.hub.classList.toggle("open", on);
    const ring = actualRing(name), indexes = name === "bags" ? [0, 1, 2, 3, 4, 6] : null;
    fan.slots.forEach((b, i) => {
      const actual = ring && (name === "forms" ? ring.slots.find(s => s.form === b.dataset.id) : ring.slots[indexes ? indexes[i] : i]);
      const availableForm = name === "forms" && b.dataset.id === "caster" && ring && ring.slots.some(s => s.form && s.shown);
      b.hidden = !on || (b.dataset.id === "caster" && name === "forms" ? !availableForm : !actual || !actual.shown);
    });
    if (on) for (const other of Object.keys(fans)) if (other !== name && fans[other].open) openFan(other, false);
  }
  menuHub.addEventListener("click", () => openFan("menu", !fans.menu.open));
  bagHub.addEventListener("click", () => openFan("bags", !fans.bags.open));
  formHub.addEventListener("click", () => openFan("forms", !fans.forms.open));
  formSlots.forEach(b => b.addEventListener("click", () => { openFan("forms", false); act.shift(b.dataset.id); }));
  menuSlots.forEach((b, i) => b.addEventListener("click", () => { // a slot fires, the ring folds (Ring.lua NATIVE_POST)
    const [id, label, , win] = MICRO[i];
    openFan("menu", false);
    if (win === "character") toggleWindow(character);
    else if (win === "spellbook") toggleWindow(spellbook);
    else say(`${label}: the game's own, not in the simulator.`);
  }));
  bagSlots.forEach((b, i) => b.addEventListener("click", () => { openFan("bags", false); toggleWindow(bags[i]); }));

  let geo = null, layoutArgs = null;
  let formLayoutKey = "";
  const formGeometryKey = () => {
    const ring = actualRing("forms");
    return ring ? JSON.stringify([ring.hub, ...ring.slots.filter(s => s.form).map(s => [s.form, s.shown, s.x, s.y, s.w, s.h])]) : "";
  };
  const casterFrame = ring => {
    const slots = ring && ring.slots.filter(s => s.form);
    if (!slots || !slots.length) return null;
    const first = slots[0];
    if (slots.length > 1) return { x: 2 * first.x - slots[1].x, y: 2 * first.y - slots[1].y, w: first.w, h: first.h };
    const dx = first.x - ring.hub.x, dy = first.y - ring.hub.y, length = Math.hypot(dx, dy) || 1;
    const step = first.w + 6;
    return { x: first.x + dy / length * step, y: first.y - dx / length * step, w: first.w, h: first.h };
  };
  return {
    // where the HUD stands (as the bar's layout), the screen's size in device px, the add-on's ring geometry (the
    // bridge's init) and the frame's top (units over the HUD's bottom)
    layout(origin, ppu, dpr, W, H, rings, frameTop) {
      if (!rings) return;
      geo = rings;
      layoutArgs = [origin, ppu, dpr, W, H, rings, frameTop];
      const css = u => u * ppu / dpr, sink = rings.sink, Wu = W / ppu, Hu = H / ppu;
      const place = (b, x, y, w, h = w) => Object.assign(b.style, { left: (origin[0] / dpr + css(x - w / 2)) + "px",
        bottom: (origin[1] / dpr + css(y - h / 2)) + "px", width: css(w) + "px", height: css(h) + "px", fontSize: Math.max(9, css(11)) + "px" });
      const actualPlace = (b, frame) => {
        if (!frame) return false;
        Object.assign(b.style, { left: (origin[0] / dpr + css(frame.x - 960 - frame.w / 2)) + "px",
          bottom: (origin[1] / dpr + css(frame.y - frame.h / 2)) + "px", width: css(frame.w) + "px", height: css(frame.h) + "px",
          fontSize: Math.max(9, css(11)) + "px" });
        return true;
      };
      // the hubs: the menu's in the right frame well; the Bags' at the upper row's last place
      const [sx, sy] = rings.socket;
      if (!actualPlace(menuHub, actualRing("menu") && actualRing("menu").hub)) place(menuHub, sx, sy - sink, rings.hub);
      const rowLeft = -(ROW.columns * ROW.size + (ROW.columns - 1) * ROW.gap) / 2;
      const bagX = rowLeft + 12 * (ROW.size + ROW.gap) + ROW.size / 2, bagY = ROW.bottom - sink + ROW.size + ROW.gapRows + ROW.size / 2;
      if (!actualPlace(bagHub, actualRing("bags") && actualRing("bags").hub)) place(bagHub, bagX, bagY, BAG_SIZE);
      // the fans round the map sphere (UIParent's coordinates: from the screen's bottom left)
      const s = { cx: rings.orb[0] + Wu / 2, cy: rings.orb[1] - sink, r: rings.ball / 2 + rings.hub / 2 - rings.overlap, hub: rings.hub,
        W: Wu, H: Hu, floor: frameTop - sink };
      const menuSize = Math.min(MENU.size, Wu / (MICRO.length + 11));
      orbit(MICRO.length, menuSize, s).forEach(([x, y], i) => {
        const round = MICRO[i][4];
        const real = actualRing("menu") && actualRing("menu").slots[i];
        if (!actualPlace(menuSlots[i], real)) place(menuSlots[i], x - Wu / 2, y, round ? MENU.disc : menuSize * 0.8, round ? MENU.disc : menuSize);
      });
      orbitBags(BAGS.length, BAG_SIZE, s, [[sx + Wu / 2, sy - sink, rings.hub]]).forEach(([x, y], i) => {
        const indexes = [0, 1, 2, 3, 4, 6], real = actualRing("bags") && actualRing("bags").slots[indexes[i]];
        if (!actualPlace(bagSlots[i], real)) place(bagSlots[i], x - Wu / 2, y, BAG_SIZE);
      });
      const formRing = actualRing("forms");
      if (formRing) {
        actualPlace(formHub, formRing.hub);
        for (const b of formSlots) {
          const real = b.dataset.id === "caster" ? casterFrame(formRing) : formRing.slots.find(s => s.form === b.dataset.id);
          if (real) actualPlace(b, real);
        }
        formLayoutKey = formGeometryKey();
      }
      hudTopCss = css(rings.orb[1] - sink + rings.ball / 2) + origin[1] / dpr;
      placeWindows();
    },
    // each frame: the open windows' numbers
    update(state, form = "caster") {
      if (state) gameState = state;
      formHub.querySelector(".icon").src = iconURL(form === "caster" ? "caster" : form);
      const ring = actualRing("forms");
      if (ring) {
        for (const b of formSlots) {
          const actual = ring.slots.find(s => s.form === b.dataset.id);
          const availableForm = b.dataset.id === "caster" && ring.slots.some(s => s.form && s.shown);
          b.hidden = !fans.forms.open || (b.dataset.id === "caster" ? !availableForm : !actual || !actual.shown);
          b.classList.toggle("checked", b.dataset.id === form);
        }
      }
      const nextKey = formGeometryKey();
      if (layoutArgs && nextKey !== formLayoutKey) this.layout(...layoutArgs);
      if (!character.hidden) drawCharacter();
    },
    refresh() { if (!spellbook.hidden) drawSpellbook(); }, // the level changed
    // the game's keys: C, P, B, Esc (the open fan, then the top window); true when taken
    key(e) {
      const k = e.key.toLowerCase();
      if (k === "c") { toggleWindow(character); return true; }
      if (k === "p") { toggleWindow(spellbook); return true; }
      if (k === "b") { const any = bags.some(w => !w.hidden); bags.forEach(w => toggleWindow(w, !any)); return true; }
      if (e.key === "Escape") {
        for (const name of Object.keys(fans)) if (fans[name].open) { openFan(name, false); return true; }
        const open = [...windows].reverse().find(w => !w.hidden);
        if (open) { toggleWindow(open, false); return true; }
      }
      return false;
    },
    state() {
      return { fans: Object.fromEntries(Object.entries(fans).map(([k, f]) => [k, f.open])),
        windows: windows.filter(w => !w.hidden).map(w => w.dataset.id),
        bags: Object.fromEntries(bags.map(w => [w.dataset.id, w.contents.map(i => `${i.kind}x${i.count}`)])) };
    },
    say,
    relayout() { if (layoutArgs) this.layout(...layoutArgs); },
  };
}
