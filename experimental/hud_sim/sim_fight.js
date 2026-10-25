// The simulator's fights (slosh_sim.html, "Fight"): a druid's spells in each form, what they cost and do, a mob
// that fights back, and a player that fights for you. Health, mana, rage, energy and the mob's health are
// shares of their maximum (0-100), as the sliders the HUD is fed. No page here: the page shows it (sim_bar.js,
// its sliders) and the world draws it (sim_world.js); `hooks` tell them what happened.

export const GCD = 1.5;          // seconds: the global cooldown after a spell (a cat's 1)
const SHIFT_COST = 5;            // a shapeshift's mana
const MELEE = 4;                 // yards: in reach of a melee blow
const AGGRO = 12;                // yards: a hostile mob comes for you inside this
export const REVIVE = 50;        // health and mana back at your corpse or a spirit healer (shares)

// Each spell: its forms, power and cost, cast time (none: instant), range (yards; 0: needs no target), what
// it does (hit: a range of damage; dot / hot: ticks over time; heal; gain: power), its cooldown, the world's
// effect and the tooltip's line.
export const SPELLS = {
  wrath: { name: "Wrath", forms: ["caster", "moonkin"], cost: ["mana", 6], cast: 1.5, range: 30, hit: [15, 20],
    fx: "wrath", text: "Hurls a bolt of nature at the enemy." },
  moonfire: { name: "Moonfire", forms: ["caster", "moonkin"], cost: ["mana", 8], range: 30, hit: [7, 9],
    dot: { ticks: 4, every: 3, amount: 3 }, fx: "moonfire", text: "Burns the enemy in moonlight, and again every 3 sec for 12 sec." },
  starfire: { name: "Starfire", forms: ["caster", "moonkin"], cost: ["mana", 10], cast: 3, range: 30, hit: [28, 34], fx: "starfire",
    text: "Calls down a star's fire on the enemy." },
  rejuvenation: { name: "Rejuvenation", forms: ["caster"], cost: ["mana", 9], range: 0, hot: { ticks: 4, every: 3, amount: 5 },
    fx: "rejuvenation", text: "Heals you every 3 sec for 12 sec." },
  healingTouch: { name: "Healing Touch", forms: ["caster"], cost: ["mana", 20], cast: 3, range: 0, heal: [36, 44],
    fx: "heal", text: "Heals you for a large amount." },
  maul: { name: "Maul", forms: ["bear"], cost: ["rage", 10], range: MELEE, hit: [11, 14], fx: "maul",
    text: "A mighty blow with both paws." },
  swipe: { name: "Swipe", forms: ["bear"], cost: ["rage", 15], range: MELEE, hit: [8, 10], fx: "swipe",
    text: "Swipes at the enemy in front of you." },
  enrage: { name: "Enrage", forms: ["bear"], range: 0, gain: ["rage", 20], cooldown: 30, fx: "enrage",
    text: "Fills you with rage." },
  claw: { name: "Claw", forms: ["cat"], cost: ["energy", 40], range: MELEE, hit: [11, 14], combo: 1, fx: "claw",
    text: "Claws the enemy. Awards 1 combo point." },
  rake: { name: "Rake", forms: ["cat"], cost: ["energy", 35], range: MELEE, hit: [4, 6], combo: 1,
    dot: { ticks: 3, every: 3, amount: 3 }, fx: "rake", text: "Rakes the enemy, and it bleeds for 9 sec. Awards 1 combo point." },
  bite: { name: "Ferocious Bite", forms: ["cat"], cost: ["energy", 35], range: MELEE, finisher: [5, 6], fx: "bite",
    text: "A finishing move: more damage with every combo point." },
};
// What each form's row of buttons holds (the game's Bar 1 pages to the form's bar)
export const BARS = { caster: ["wrath", "moonfire", "rejuvenation", "healingTouch", "starfire"], bear: ["maul", "swipe", "enrage"],
  cat: ["claw", "rake", "bite"], moonkin: ["wrath", "moonfire", "starfire"], travel: [] };
export const FORMS = ["caster", "bear", "cat", "travel", "moonkin"];
// the level a druid learns each spell and form at (the game's, Classic; moonkin a talent at 40)
export const LEVELS = { wrath: 1, healingTouch: 1, moonfire: 4, rejuvenation: 4, maul: 10, enrage: 12, swipe: 16, claw: 20,
  starfire: 20, rake: 24, bite: 32, caster: 1, bear: 10, cat: 20, travel: 30, moonkin: 40 };
export const MAX_LEVEL = 60;
// what a bag's items do when used (right-click or click in the bag): potions share a cooldown, as the game's
export const ITEMS = {
  healingPotion: { name: "Healing Potion", quality: "common", use: "Restores 30% health.", heal: 30, cooldown: 60 },
  manaPotion: { name: "Mana Potion", quality: "common", use: "Restores 35% mana.", mana: 35, cooldown: 60 },
  hearthstone: { name: "Hearthstone", quality: "common", use: "Returns you to your inn." },
  linenCloth: { name: "Linen Cloth", quality: "common" },
  peacebloom: { name: "Peacebloom", quality: "common" },
  silverleaf: { name: "Silverleaf", quality: "common" },
  brokenFang: { name: "Broken Fang", quality: "poor" },
  moonberry: { name: "Moonberry Juice", quality: "common", use: "Drink: restores mana out of combat (not in the simulator)." },
  owlbearFeather: { name: "Pristine Owl Feather", quality: "uncommon" },
};
export const POWER = { caster: "mana", moonkin: "mana", travel: "mana", bear: "rage", cat: "energy" };
export const FOES = { // the mobs a fight picks: the world's target kind (TARGETS in sim_world.js), its blows
  hostile: { name: "Gnarlpine Warrior", swing: 2.0, hit: [3, 6], crush: [28, 42], aggressive: true },
  neutral: { name: "Nightsaber", swing: 1.5, hit: [2, 5], crush: [24, 32], aggressive: false },
};
const rand = ([lo, hi]) => lo + Math.random() * (hi - lo);
const round = v => Math.round(v);

// hooks: say(text, kind: "error" | "log"), fx(kind, data) (the world: "wrath", "moonfire", "heal", "swing",
// "text" ...), wound(size) (a blow: the add-on's S.Wound, through the HUD), shift(form) (the page changes
// form), xp(share), despawn() (the dead mob's gone), spawn(kind) (a fight picked: the page shows its target),
// died() (your health ran out: the page plays your death, the release and coming back: revive())
export function createFight(hooks) {
  const me = { hp: 70, mana: 55, rage: 0, energy: 100, combo: 0, form: "caster", gcd: 0, cast: null, cds: {}, hots: [],
    spent: -99, swing: 0, winding: false, tick: 0, dead: false };
  const mob = { kind: "", alive: false, hp: 100, dots: [], aggro: false, swing: 0.43, winding: false, crushes: 0, diedAt: 0 };
  let time = 0, auto = false, fights = 0, nextPick = 0, plan = "caster", wentBear = false, level = 30;
  const knows = id => (LEVELS[id] || 1) <= level;
  const foe = () => FOES[mob.kind];
  const powerOf = form => POWER[form];
  const fighting = () => mob.alive && mob.aggro;

  function say(text, kind = "log") { hooks.say(text, kind); }
  function float(who, text, color, big) { hooks.fx("text", { who, text, color, big }); }
  function hurtMob(amount, what, crit) {
    if (!mob.alive) return;
    amount = Math.max(1, round(amount));
    mob.hp = Math.max(0, mob.hp - amount);
    mob.aggro = true;
    hooks.fx("targetHit", { amount, crit });
    float("target", (crit ? amount + "!" : String(amount)), crit ? "#ffe066" : "#ffffff", crit);
    say(`Your ${what} ${crit ? "crits" : "hits"} ${foe().name} for ${amount}%.`);
    if (mob.hp <= 0) die();
  }
  function die() {
    mob.alive = false;
    mob.aggro = false;
    mob.dots = [];
    mob.diedAt = time;
    me.cast = null;
    say(`${foe().name} dies. You gain experience.`);
    hooks.xp(4);
    if (auto) nextPick = time + 9;
  }
  function healMe(amount, what) {
    const before = me.hp;
    me.hp = Math.min(100, me.hp + round(amount));
    float("you", "+" + round(me.hp - before), "#5dff6a", false);
    say(`Your ${what} heals you for ${round(me.hp - before)}%.`);
  }
  function hurtMe(amount, crushing) {
    amount = round(amount);
    me.hp = Math.max(0, me.hp - amount);
    if (me.form === "bear") me.rage = Math.min(100, me.rage + 6); // a bear's rage from the blows it takes
    if (me.cast && !crushing) me.cast.end += 0.4; // pushed back, as a hit delays a cast
    float("you", "-" + amount, "#ff5a4a", crushing);
    say(`${foe().name} ${crushing ? "crushes" : "hits"} you for ${amount}%.`);
    hooks.wound(amount / 100);
    hooks.fx("hit", { crushing });
    if (me.hp <= 0) dieMe();
  }
  // your health ran out: the fight is over (the mob goes back to full, as the game's evade), nothing works but
  // the page's release and coming back (revive)
  function dieMe() {
    Object.assign(me, { hp: 0, dead: true, cast: null, hots: [], combo: 0, swing: 0, winding: false });
    hooks.fx("casting", { id: null });
    Object.assign(mob, { aggro: false, dots: [], hp: mob.alive ? 100 : mob.hp });
    auto = false;
    say("You die.");
    hooks.died();
  }
  // back to life (at your corpse or a spirit healer): REVIVE of your health and mana, in your own form
  function revive() {
    Object.assign(me, { dead: false, hp: REVIVE, mana: REVIVE, rage: 0, energy: 100, form: "caster", gcd: time + GCD, spent: time, winding: false });
  }

  // Whether a spell can be cast now, and if not why (the bar shows it; cast() says it)
  function check(id, ctx) {
    const s = SPELLS[id];
    if (!s) return { ok: false, why: "unknown" };
    if (me.dead) return { ok: false, why: "dead", say: "You are dead." };
    if (!knows(id)) return { ok: false, why: "level", say: "You haven't learned that yet." };
    if (!s.forms.includes(me.form)) return { ok: false, why: "form", say: "You can't do that in this form." };
    if (me.cds[id] > time) return { ok: false, why: "cooldown", say: "Spell is not ready yet." };
    if (s.cost && me[s.cost[0]] < s.cost[1]) {
      return { ok: false, why: "power", say: `Not enough ${s.cost[0]}.` };
    }
    if (s.range) {
      if (!mob.alive || !ctx.here) return { ok: false, why: "target", say: "You have no target." };
      if (ctx.distance > s.range) return { ok: false, why: "range", say: "Out of range." };
      if (Math.abs(ctx.angle) > Math.PI / 3) return { ok: false, why: "facing", say: "You must be facing your target." };
    }
    if (s.cast && ctx.moving) return { ok: false, why: "moving", say: "Can't do that while moving." };
    return { ok: true };
  }
  function cast(id, ctx) {
    if (me.cast) { say("Another action is in progress.", "error"); return false; }
    if (time < me.gcd) return false; // the global cooldown: as the game, the press is lost
    const c = check(id, ctx), s = SPELLS[id];
    if (!c.ok) { say(c.say, "error"); return false; }
    me.gcd = time + (me.form === "cat" ? 1 : GCD);
    if (s.range && !mob.aggro) mob.aggro = true; // attacking it: it fights back
    if (s.cast) { me.cast = { id, start: time, end: time + s.cast }; hooks.fx("casting", { id }); return true; }
    release(id);
    return true;
  }
  // a spell takes effect: its cost, then what it does
  function release(id) {
    const s = SPELLS[id];
    if (s.cost) {
      me[s.cost[0]] -= s.cost[1];
      if (s.cost[0] === "mana") me.spent = time;
    }
    if (s.cooldown) me.cds[id] = time + s.cooldown;
    hooks.fx(s.fx, { id });
    const crit = Math.random() < 0.12;
    if (s.hit) hurtMob(rand(s.hit) * (crit ? 1.5 : 1), s.name, crit);
    if (s.finisher) {
      hurtMob((s.finisher[0] + s.finisher[1] * me.combo) * (crit ? 1.5 : 1), s.name, crit);
      me.combo = 0;
    }
    if (s.combo) me.combo = Math.min(5, me.combo + s.combo);
    if (s.dot && mob.alive) {
      mob.dots = mob.dots.filter(d => d.id !== id);
      mob.dots.push({ id, name: s.name, left: s.dot.ticks, every: s.dot.every, amount: s.dot.amount, next: time + s.dot.every });
    }
    if (s.heal) healMe(rand(s.heal), s.name);
    if (s.hot) {
      me.hots = me.hots.filter(h => h.id !== id);
      me.hots.push({ id, name: s.name, left: s.hot.ticks, every: s.hot.every, amount: s.hot.amount, next: time + s.hot.every });
    }
    if (s.gain) me[s.gain[0]] = Math.min(100, me[s.gain[0]] + s.gain[1]);
  }
  // A shapeshift: mana, and a fresh rage (none) or energy (some), as the game's
  function shift(form) {
    if (form === me.form) return true;
    if (me.dead) { say("You are dead.", "error"); return false; }
    if (!knows(form)) { say("You haven't learned that yet.", "error"); return false; }
    if (me.cast) { me.cast = null; hooks.fx("casting", { id: null }); }
    if (me.winding) { me.winding = false; hooks.fx("cancelWindup", { who: "you" }); }
    if (form !== "caster" && me.mana < SHIFT_COST) { say("Not enough mana.", "error"); return false; }
    if (form !== "caster") { me.mana -= SHIFT_COST; me.spent = time; }
    if (form === "bear") me.rage = 10;
    if (form === "cat") me.energy = 40;
    me.combo = 0;
    me.form = form;
    me.gcd = time + GCD;
    return true;
  }
  function pick(kind = "hostile") {
    mob.kind = FOES[kind] ? kind : "hostile";
    mob.alive = true;
    mob.hp = 100;
    mob.dots = [];
    mob.aggro = false;
    mob.swing = 0.43;
    mob.winding = false;
    mob.crushes = 0;
    wentBear = false;
    const plans = ["caster", ...(knows("cat") ? ["cat"] : []), ...(knows("moonkin") ? ["moonkin"] : [])];
    plan = plans[fights % plans.length];
    fights++;
    hooks.spawn(mob.kind);
    say(`${foe().name} is near. ${foe().aggressive ? "It will come for you." : "It leaves you be unless you strike it."}`);
  }

  // The automatic player: a plan a fight (a caster who turns bear when pressed, a cat, a moonkin)
  function think(ctx) {
    const can = id => check(id, ctx).ok;
    const go = id => can(id) && cast(id, ctx);
    if (!mob.alive) { // between fights: back to caster, healed up, then the next
      if (me.form !== "caster") { shift("caster"); hooks.shift("caster"); return; }
      if (me.hp < 70 && go("healingTouch")) return;
      if (time > nextPick && !ctx.moving && me.mana > 70 && me.hp > 85) pick("hostile"); // rested first
      return;
    }
    const to = form => { if (knows(form) && (form === "caster" || me.mana >= SHIFT_COST) && shift(form)) hooks.shift(form); };
    if (!mob.aggro) { // pull it with a spell from afar: it comes to you
      if (me.form !== "caster" && me.form !== "moonkin") { to("caster"); return; }
      if (go("moonfire") || go("wrath")) return;
      return;
    }
    const hurt = me.hp < 38;
    if (me.form !== "caster" && hurt && me.mana >= 25) { to("caster"); return; }
    if (me.form === "caster") {
      if (hurt && go("healingTouch")) return;
      if (me.hp < 65 && !me.hots.length && go("rejuvenation")) return;
      if (plan === "cat" && !hurt && ctx.distance < 9) { to("cat"); return; }
      if (plan === "moonkin" && !hurt) { to("moonkin"); return; }
      if (plan === "caster" && knows("bear") && !wentBear && ctx.distance < MELEE && me.hp < 70 && me.mana > 30) { wentBear = true; to("bear"); return; }
      if (!mob.dots.some(d => d.id === "moonfire") && go("moonfire")) return;
      if (ctx.distance > 14 && go("starfire")) return;
      if (go("wrath")) return;
      if (me.mana < 10 && knows("bear")) to("bear");
      return;
    }
    if (me.form === "bear") {
      if (me.hp < 45 && me.mana >= 28) { to("caster"); return; }
      if (me.rage < 10 && go("enrage")) return;
      if (me.rage >= 15 && Math.random() < 0.4 && go("swipe")) return;
      go("maul");
      return;
    }
    if (me.form === "cat") {
      if (me.combo >= 4 && go("bite")) return;
      if (!mob.dots.some(d => d.id === "rake") && go("rake")) return;
      go("claw");
      return;
    }
    if (me.form === "moonkin") {
      if (!mob.dots.some(d => d.id === "moonfire") && go("moonfire")) return;
      if (ctx.distance > 12 && go("starfire")) return;
      go("wrath");
      return;
    }
    to("caster"); // travel form: nothing to fight with
  }

  // ctx: here (a target in the world), distance (yards), angle (radians off your facing, + right), moving
  function update(dt, ctx) {
    time += dt;
    if (me.dead) return; // dead or a ghost: no fight, no power, no healing
    // a cast: done, or broken by moving
    if (me.cast) {
      if (ctx.moving) { say("Interrupted.", "error"); me.cast = null; hooks.fx("casting", { id: null }); }
      else if (time >= me.cast.end) {
        const id = me.cast.id;
        me.cast = null;
        hooks.fx("casting", { id: null });
        if (SPELLS[id].range && (!mob.alive || ctx.distance > SPELLS[id].range)) say("Your target is gone.", "error");
        else release(id);
      }
    }
    // the mob: comes for you when hostile and near, strikes when in reach, now and then crushingly
    if (mob.alive && !mob.aggro && foe().aggressive && ctx.here && ctx.distance < AGGRO) {
      mob.aggro = true;
      say(`${foe().name} attacks!`);
    }
    if (fighting() && ctx.here && ctx.distance <= MELEE) {
      mob.swing -= dt;
      const windup = mob.kind === "neutral" ? 0.31 : 0.43;
      if (mob.swing <= windup && !mob.winding) { mob.winding = true; hooks.fx("windup", { who: "target" }); }
      if (mob.swing <= 0) {
        mob.swing = foe().swing;
        mob.winding = false;
        hooks.fx("swing", {});
        // a crushing blow once a fight (when it's hurt), now and then a second
        const crush = (!mob.crushes && mob.hp < 65) || (mob.crushes < 2 && Math.random() < 0.03);
        if (crush) mob.crushes++;
        hurtMe(rand(crush ? foe().crush : foe().hit) * (!crush && Math.random() < 0.12 ? 1.6 : 1), crush);
      }
      // your auto attack in bear and cat form (a bear's builds rage)
      if (me.form === "bear" || me.form === "cat") {
        me.swing -= dt;
        if (me.swing <= 0.31 && !me.winding) { me.winding = true; hooks.fx("windup", { who: "you" }); }
        if (me.swing <= 0) {
          me.swing = me.form === "bear" ? 2.5 : 1.0;
          me.winding = false;
          hooks.fx("melee", {});
          if (me.form === "bear") me.rage = Math.min(100, me.rage + 5);
          hurtMob(me.form === "bear" ? rand([3, 5]) : rand([2.5, 3.5]), "attack", false);
        }
      }
    } else {
      mob.swing = Math.min(mob.swing, 0.6);
      if (mob.winding) { hooks.fx("cancelWindup", { who: "target" }); mob.winding = false; mob.swing = 0.43; }
      if (me.winding) { hooks.fx("cancelWindup", { who: "you" }); me.winding = false; me.swing = 0.31; }
    }
    // damage and healing over time
    for (const d of mob.dots) while (d.left > 0 && time >= d.next && mob.alive) {
      d.left--;
      d.next += d.every;
      hurtMob(d.amount, d.name, false);
    }
    mob.dots = mob.dots.filter(d => d.left > 0);
    for (const h of me.hots) while (h.left > 0 && time >= h.next) { h.left--; h.next += h.every; healMe(h.amount, h.name); }
    me.hots = me.hots.filter(h => h.left > 0);
    // power: energy ticks every 2 sec; mana comes back 5 sec after you last spent it, faster out of combat;
    // rage ebbs out of combat; health returns out of combat
    me.tick += dt;
    while (me.tick >= 2) { me.tick -= 2; me.energy = Math.min(100, me.energy + 20); }
    const calm = !fighting();
    if (time - me.spent > 5) me.mana = Math.min(100, me.mana + dt * (calm ? 4 : 0.4));
    if (calm) {
      me.rage = Math.max(0, me.rage - dt * 3);
      if (time - mob.diedAt > 2) me.hp = Math.min(100, me.hp + dt * 2);
      if (time - mob.diedAt > 10) me.combo = 0;
    }
    if (!mob.alive && mob.kind && time - mob.diedAt > 7) { mob.kind = ""; hooks.despawn(); }
    if (auto && !me.cast && time >= me.gcd) think(ctx);
  }

  // an item used from a bag: a potion (health or mana; they share a minute's cooldown); others say what they'd do
  function use(kind) {
    const item = ITEMS[kind];
    if (!item) return false;
    if (!item.heal && !item.mana) { say(kind === "hearthstone" ? "There's no inn in the simulator." : item.use || "You can't use that.", "error"); return false; }
    if ((me.cds.potion || 0) > time) { say("Item is not ready yet.", "error"); return false; }
    me.cds.potion = time + item.cooldown;
    if (item.heal) { healMe(item.heal, item.name); hooks.fx("heal", {}); }
    if (item.mana) {
      me.mana = Math.min(100, me.mana + item.mana);
      say(`Your ${item.name} restores ${item.mana}% mana.`);
      hooks.fx("rejuvenation", {});
    }
    return true;
  }

  // the page's Target choice put one there by hand: a mob to fight (it fights back once struck, or comes for you
  // when hostile), or none
  function adopt(kind, hp) {
    if (!FOES[kind]) { mob.kind = ""; mob.alive = false; mob.aggro = false; mob.dots = []; return; }
    if (mob.kind === kind && mob.alive) return;
    Object.assign(mob, { kind, alive: hp > 0, hp, aggro: false, dots: [], crushes: 0, swing: 0.43, winding: false });
  }

  return {
    me, mob, check, cast, shift, pick, adopt, update, knows, use, revive,
    kill() { if (!me.dead) dieMe(); }, // the page's Die
    get level() { return level; },
    set level(v) { level = Math.max(1, Math.min(MAX_LEVEL, Math.round(v) || 1)); },
    get auto() { return auto; },
    set auto(on) { auto = on; if (on && !mob.alive) nextPick = time + 0.5; },
    get time() { return time; },
    power: () => me[powerOf(me.form)],
    setPower(v) { me[powerOf(me.form)] = v; },
  };
}
