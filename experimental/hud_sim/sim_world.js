// The liquid simulator's 3D world (slosh_sim.html, Background "A 3D world"): a cartoon Teldrassil at twilight
// with you in it, a female Night Elf druid, seen from behind and above as the game's camera sees you; your pet
// beside you and your target ahead when you have them. You stay where you are: the world turns round you and
// slides past as you move (the page's facing and position: the same the slosh and the minimap use), while you
// run, back up, strafe and jump as you do, in any of your forms (caster, bear, cat, travel, moonkin), each
// feeding the spheres its own power. Trees, rocks, moonwells, lanterns and mushrooms are solid (collide: the
// page moves you by it), and the camera pulls in front of them as the game's does. The page draws this
// module's canvas under the HUD's. All in the browser: three.js is vendored (vendor/).
//
// The figures walk as bodies do: each foot is placed (planted on the ground while it bears the weight, the
// ground sliding under it at your speed, then swung forward to its next step) and each leg bent to reach it
// (two-bone inverse kinematics); the stride's length and its cadence follow the speed so no foot slides.
import * as THREE from "./vendor/three.module.min.js";
import { BANDS, INK, glow, part, put, group, ball, cone, cylinder, leaf, ring, tilted, horn, sash, bake } from "./sim_geometry.js";
import { SENTINEL, nightElf, moonkin, furbolg, bear, cat, cheetah, wolf, nightsaber, voidwalker, mover, act, step, lieDown } from "./sim_figures.js";

const TILE = 160;      // yards: trees, rocks, tents and totems repeat this far apart round wherever you are
const TUFT_TILE = 36;  // yards: the grass tufts' tile (denser: they show the ground sliding past)
const LAND_SPAN = 1800; // yards: one terrain tile spans the same square as the minimap
const LAND_SEGMENTS = 192;
const FEATURE_SIZE = 512;
const SPAWN_AT = { x: -28, z: -84 };
const TEST_HOUSE = { x: -42, z: -103, halfWidth: 12, halfDepth: 10, wall: 0.6, doorHalf: 3.5 };
const INTERIOR_MAP_SPAN = 40;
let mapFeatures = null;
let interiorFloor = 0;
let insideBuilding = false;
const JUMP = 0.72;     // a jump's time in the air (the page's) and its height in yards
const JUMP_H = 1.2;
const CAMERA_BACK = 9.8; // yards behind you, as the game's camera at its usual distance
const CAMERA_UP = 2.8;    // yards over what it looks at (1.5 over your feet): 15.9 degrees down
const CAMERA_FAR = Math.hypot(CAMERA_BACK, CAMERA_UP), CAMERA_TILT = Math.atan2(CAMERA_UP, CAMERA_BACK);
// the wheel's zoom, the camera's distance in yards: close behind you (still seen whole) to far out
const ZOOM = { min: 2.2, max: 22, rest: CAMERA_FAR };
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const ease = (current, target, dt, tau) => current + (target - current) * (1 - Math.exp(-dt / tau));
const turnOf = a => Math.atan2(Math.sin(a), Math.cos(a)); // an angle into -pi..pi

// ---------------------------------------------------------------- death: your ghost, the spirit healer, a graveyard
// A night elf's ghost is a wisp (the race's Wisp Spirit): a bright core in its glow, motes circling it; the world
// draws its trail.
function wispFigure() {
  const root = group();
  const core = put(root, new THREE.Mesh(new THREE.SphereGeometry(0.14, 16, 12), new THREE.MeshBasicMaterial({ color: 0xf4ffff })), 0, 1.35, 0);
  core.add(halo(0xbff2ff, 1.4, 0.95));
  core.add(halo(0x78c4ff, 3.4, 0.32));
  const motes = [];
  for (let i = 0; i < 6; i++) motes.push(put(core, halo(i % 2 ? 0xe2fcff : 0x9fdcff, 0.32, 0.9)));
  return { root, core, motes };
}
// The spirit healer (the game's, at every graveyard, seen only by the dead): a hooded spirit in robes of pale
// light, its face a glow, great wings fanned behind it, floating; it lifts its arms when it brings you back.
const SPIRIT = { robe: 0xd6ecff, fold: 0x9cc2ec, wing: 0xf2f9ff, feather: 0xbcdaf6 };
function spiritHealer() {
  const root = group(), body = put(root, group(), 0, 0.35, 0);
  // the robe, a bell from the shoulders to its hem, hanging over the ground
  const robe = [[0.04, 0], [0.66, 0.02], [0.6, 0.45], [0.42, 1.15], [0.31, 1.7], [0.35, 1.93], [0.14, 2.08], [0, 2.09]]
    .map(([r, y]) => new THREE.Vector2(r, y));
  put(body, part(new THREE.LatheGeometry(robe, 28), SPIRIT.robe));
  put(body, ring(0.34, 0.035, SPIRIT.fold), 0, 1.22, 0).rotation.x = Math.PI / 2; // its sash
  put(body, ball(0.37, SPIRIT.robe, 1, 0.5, 0.86), 0, 1.93, 0);                    // the mantle over its shoulders
  const head = put(body, group(), 0, 2.24, 0);
  put(head, ball(0.21, SPIRIT.fold, 1, 1.12, 1));                                     // the hood
  put(head, cone(0.17, 0.3, SPIRIT.robe, 12), 0, 0.2, 0.07).rotation.x = -0.55;      // its peak, falling back
  const face = put(head, new THREE.Mesh(new THREE.SphereGeometry(0.12, 14, 10), new THREE.MeshBasicMaterial({ color: 0xffffff })), 0, -0.03, -0.1);
  face.add(halo(0xe6f6ff, 0.95, 0.95));
  const arms = [];
  for (const side of [-1, 1]) { // sleeves from the shoulders, hands of light
    const shoulder = put(body, group(), side * 0.33, 1.9, -0.02);
    put(shoulder, cylinder(0.065, 0.15, 0.72, SPIRIT.robe), 0, -0.36, 0);
    const hand = put(shoulder, new THREE.Mesh(new THREE.SphereGeometry(0.06, 10, 8), new THREE.MeshBasicMaterial({ color: 0xffffff })), 0, -0.76, 0);
    hand.add(halo(0xd2efff, 0.55, 0.85));
    arms.push({ shoulder, side });
  }
  const wings = [];
  const feather = (len, color) => ball(0.5, color, 0.24, len, 0.07); // rounded, long and flat
  for (const side of [-1, 1]) { // long flight feathers spread out and up to the side, shorter coverts over their roots
    const wing = put(body, group(), side * 0.2, 1.84, 0.26);
    for (let i = 0; i < 8; i++) {
      const len = 0.75 + 0.3 * Math.sin((i + 1) / 9 * Math.PI) + i * 0.07, pivot = put(wing, group());
      pivot.rotation.z = -side * (0.55 + i * 0.16);
      put(pivot, feather(len, i % 2 ? SPIRIT.feather : SPIRIT.wing), 0, len / 2, 0.02 * i);
    }
    for (let i = 0; i < 5; i++) {
      const len = 0.45 + i * 0.05, pivot = put(wing, group());
      pivot.rotation.z = -side * (0.6 + i * 0.22);
      put(pivot, feather(len, SPIRIT.wing), 0, len / 2, -0.04);
    }
    wing.rotation.y = side * 0.32;
    wings.push({ wing, side });
  }
  body.add(put(group(), halo(0xcfeaff, 4.2, 0.18), 0, 1.6, 0.3)); // its light, behind it
  const pool = new THREE.Mesh(new THREE.PlaneGeometry(4.2, 4.2), new THREE.MeshBasicMaterial({ map: HALO, color: 0x9fd2ff,
    transparent: true, opacity: 0.16, depthWrite: false, blending: THREE.AdditiveBlending }));
  pool.rotation.x = -Math.PI / 2;
  pool.position.y = 0.03;
  root.add(pool);
  return { root, body, arms, wings, raise: 0 };
}
// a graveyard's stone: a slab, its top rounded, leaning a little
function headstone(rnd) {
  const g = group(), w = 0.5 + rnd() * 0.2, h = 0.7 + rnd() * 0.35, c = rnd() < 0.5 ? STONE : 0xa9a6c4;
  put(g, part(new THREE.BoxGeometry(w, h, 0.14), c), 0, h / 2, 0);
  put(g, part(new THREE.CylinderGeometry(w / 2, w / 2, 0.14, 16, 1, false, 0, Math.PI), c), 0, h, 0).rotation.set(Math.PI / 2, Math.PI / 2, 0);
  g.rotation.set((rnd() - 0.5) * 0.18, rnd() * Math.PI * 2, (rnd() - 0.5) * 0.14);
  return g;
}
// Motes of light rising and fading (a wisp's trail, the light of coming back to life)
function motes(parent, n = 60) {
  const pool = [];
  for (let i = 0; i < n; i++) {
    const m = halo(0xffffff, 0.3, 1);
    m.visible = false;
    parent.add(m);
    pool.push({ m, v: new THREE.Vector3(), life: 0, max: 1, size: 0.3 });
  }
  let next = 0;
  return {
    emit(x, y, z, color, { spread = 0.15, rise = 0.6, life = 1, size = 0.3 } = {}) {
      const p = pool[next++ % pool.length];
      p.m.position.set(x + (Math.random() - 0.5) * spread, y + (Math.random() - 0.5) * spread, z + (Math.random() - 0.5) * spread);
      p.v.set((Math.random() - 0.5) * 0.3, rise * (0.6 + Math.random() * 0.8), (Math.random() - 0.5) * 0.3);
      p.m.material.color.setHex(color);
      p.life = p.max = life * (0.7 + Math.random() * 0.6);
      p.size = size;
      p.m.visible = true;
    },
    step(dt) {
      for (const p of pool) {
        if (!p.m.visible) continue;
        p.life -= dt;
        if (p.life <= 0) { p.m.visible = false; continue; }
        p.m.position.addScaledVector(p.v, dt);
        const u = p.life / p.max;
        p.m.material.opacity = Math.min(1, u * 2.5);
        p.m.scale.setScalar(p.size * (0.4 + 0.6 * u));
      }
    },
  };
}

// ---------------------------------------------------------------- the land: Teldrassil at twilight, cartoon
const BARK = 0x5d4b5e, BARK_DARK = 0x463849, STONE = 0xc8c6dc, MOSS = 0x4f7d4c;
const CANOPY = [0x7a4f9a, 0x8c62b2, 0x3d8c83, 0x2f6b58, 0xa868ae];
function grassTexture() {
  const n = 256, cv = document.createElement("canvas");
  cv.width = cv.height = n;
  const g = cv.getContext("2d");
  g.fillStyle = "#46724f";
  g.fillRect(0, 0, n, n);
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  for (let i = 0; i < 700; i++) { // moss and shadow, a little violet, wrapping round the tile
    g.fillStyle = ["rgba(96,146,92,0.18)", "rgba(28,58,48,0.2)", "rgba(112,92,150,0.13)"][i % 3];
    const r = 5 + rnd() * 20, x = rnd() * n, y = rnd() * n;
    for (const dx of [-n, 0, n]) for (const dy of [-n, 0, n]) { g.beginPath(); g.arc(x + dx, y + dy, r, 0, Math.PI * 2); g.fill(); }
  }
  for (let i = 0; i < 140; i++) { g.fillStyle = ["#9ff3ff", "#d6b8ff", "#fff3c0"][i % 3]; g.fillRect(rnd() * n, rnd() * n, 2, 2); }
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}
const TAU = Math.PI * 2;
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const periodicDelta = (a, b) => a - b - LAND_SPAN * Math.round((a - b) / LAND_SPAN);
const heightNoise = [8, 16, 32, 64].map((n, layer) => {
  const values = new Float32Array(n * n);
  let seed = 9173 + layer * 1031;
  for (let i = 0; i < values.length; i++) { seed = (seed * 16807) % 2147483647; values[i] = seed / 1073741823.5 - 1; }
  return { n, values };
});
function periodicNoise(x, z, grid) {
  const qx = x / LAND_SPAN * grid.n, qz = z / LAND_SPAN * grid.n, ix = Math.floor(qx), iz = Math.floor(qz);
  const fx = qx - ix, fz = qz - iz, sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz);
  const at = (i, j) => grid.values[((j % grid.n + grid.n) % grid.n) * grid.n + ((i % grid.n + grid.n) % grid.n)];
  const a = at(ix, iz) + (at(ix + 1, iz) - at(ix, iz)) * sx;
  const b = at(ix, iz + 1) + (at(ix + 1, iz + 1) - at(ix, iz + 1)) * sx;
  return a + (b - a) * sz;
}
function landHeight(x, z) {
  return periodicNoise(x, z, heightNoise[0]) * 4.8 + periodicNoise(x, z, heightNoise[1]) * 2.4
    + periodicNoise(x, z, heightNoise[2]) * 0.8 + periodicNoise(x, z, heightNoise[3]) * 0.25;
}
function wrappedDistanceField(mask, n) {
  const d = new Float32Array(mask.length);
  for (let i = 0; i < mask.length; i++) d[i] = mask[i] ? 0 : 1e4;
  const relax = (x, y, ox, oy, cost) => {
    const xx = (x + ox + n) % n, yy = (y + oy + n) % n, i = y * n + x;
    d[i] = Math.min(d[i], d[yy * n + xx] + cost);
  };
  // Two wrapped chamfer sweeps settle distances across the full tile, including its edges.
  for (let pass = 0; pass < 2; pass++) {
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      relax(x, y, -1, 0, 1); relax(x, y, 0, -1, 1);
      relax(x, y, -1, -1, Math.SQRT2); relax(x, y, 1, -1, Math.SQRT2);
    }
    for (let y = n - 1; y >= 0; y--) for (let x = n - 1; x >= 0; x--) {
      relax(x, y, 1, 0, 1); relax(x, y, 0, 1, 1);
      relax(x, y, 1, 1, Math.SQRT2); relax(x, y, -1, 1, Math.SQRT2);
    }
  }
  return d;
}
function sampleFeatureDistance(field, x, z) {
  if (!mapFeatures) return null;
  const n = FEATURE_SIZE, qx = ((x / LAND_SPAN + 0.5) % 1 + 1) % 1 * n, qy = ((z / LAND_SPAN + 0.5) % 1 + 1) % 1 * n;
  const ix = Math.floor(qx), iy = Math.floor(qy), fx = qx - ix, fy = qy - iy;
  const at = (px, py) => field[((py % n + n) % n) * n + ((px % n + n) % n)];
  const a = at(ix, iy) * (1 - fx) + at(ix + 1, iy) * fx;
  const b = at(ix, iy + 1) * (1 - fx) + at(ix + 1, iy + 1) * fx;
  return (a * (1 - fy) + b * fy) * LAND_SPAN / n;
}
function readMapFeatures(image) {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = FEATURE_SIZE;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(image, 0, 0, FEATURE_SIZE, FEATURE_SIZE);
  const pixels = ctx.getImageData(0, 0, FEATURE_SIZE, FEATURE_SIZE).data, count = FEATURE_SIZE * FEATURE_SIZE;
  const water = new Uint8Array(count), roughRoad = new Uint8Array(count);
  for (let i = 0; i < count; i++) {
    const r = pixels[i * 4], g = pixels[i * 4 + 1], b = pixels[i * 4 + 2];
    water[i] = b > g * 1.18 && g > r * 1.15 && b < 145 ? 1 : 0;
    roughRoad[i] = r > g * 1.12 && g > b * 1.06 && r > 75 && g > 60 && b > 35 ? 1 : 0;
  }
  const roads = new Uint8Array(count);
  for (let y = 0; y < FEATURE_SIZE; y++) for (let x = 0; x < FEATURE_SIZE; x++) {
    const i = y * FEATURE_SIZE + x;
    if (!roughRoad[i]) continue;
    let neighbors = 0;
    for (let oy = -1; oy <= 1; oy++) for (let ox = -1; ox <= 1; ox++) {
      if ((!ox && !oy) || !roughRoad[((y + oy + FEATURE_SIZE) % FEATURE_SIZE) * FEATURE_SIZE + ((x + ox + FEATURE_SIZE) % FEATURE_SIZE)]) continue;
      neighbors++;
    }
    roads[i] = neighbors >= 2 ? 1 : 0;
  }
  return { water, roads, waterDistance: wrappedDistanceField(water, FEATURE_SIZE), roadDistance: wrappedDistanceField(roads, FEATURE_SIZE) };
}
// A stream meanders north to south; two old tracks wind across the low ground. Their curves repeat exactly
// at the land tile's edge, so the view can follow them indefinitely without a hard edge.
function riverX(z) {
  const a = TAU * z / LAND_SPAN;
  return -16 + 68 * Math.sin(a) + 18 * Math.sin(2 * a + 0.12);
}
function tributaryZ(x) {
  const a = TAU * x / LAND_SPAN;
  return -155 + 110 * Math.sin(a + 0.5) + 18 * Math.sin(2 * a);
}
function trailZ(x) {
  const a = TAU * x / LAND_SPAN;
  return -11 + 52 * Math.sin(a) + 14 * Math.sin(2 * a);
}
function trailX(z) {
  const a = TAU * z / LAND_SPAN;
  return 175 + 72 * Math.sin(a + 0.5) + 20 * Math.sin(2 * a + 0.8);
}
function riverDistance(x, z) {
  const imageDistance = sampleFeatureDistance(mapFeatures?.waterDistance, x, z);
  if (imageDistance !== null) return imageDistance;
  const mainSlope = riverX(z + 0.5) - riverX(z - 0.5), branchSlope = tributaryZ(x + 0.5) - tributaryZ(x - 0.5);
  return Math.min(Math.abs(periodicDelta(x, riverX(z))) / Math.sqrt(1 + mainSlope * mainSlope),
    Math.abs(periodicDelta(z, tributaryZ(x))) / Math.sqrt(1 + branchSlope * branchSlope));
}
function trailDistance(x, z) {
  const imageDistance = sampleFeatureDistance(mapFeatures?.roadDistance, x, z);
  if (imageDistance !== null) return imageDistance;
  const sx = (trailZ(x + 0.5) - trailZ(x - 0.5));
  const sz = (trailX(z + 0.5) - trailX(z - 0.5));
  return Math.min(Math.abs(periodicDelta(z, trailZ(x))) / Math.sqrt(1 + sx * sx),
    Math.abs(periodicDelta(x, trailX(z))) / Math.sqrt(1 + sz * sz));
}
function groundHeight(x, z) {
  const base = landHeight(x, z), water = riverDistance(x, z), path = trailDistance(x, z);
  const channel = 1 - smooth(0, 9, water), compact = 1 - smooth(2.2, 6.5, path);
  return base - 0.65 * channel + 0.26 * Math.exp(-(((water - 12) / 6) ** 2)) - 0.05 * compact;
}
function inHouse(x, z, margin = 0) {
  return Math.abs(x - TEST_HOUSE.x) < TEST_HOUSE.halfWidth - TEST_HOUSE.wall + margin
    && Math.abs(z - TEST_HOUSE.z) < TEST_HOUSE.halfDepth - TEST_HOUSE.wall + margin;
}
function featureTexture(mask, rgb) {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = FEATURE_SIZE;
  const ctx = canvas.getContext("2d"), pixels = ctx.createImageData(FEATURE_SIZE, FEATURE_SIZE);
  for (let i = 0; i < mask.length; i++) {
    const j = i * 4;
    pixels.data[j] = rgb[0]; pixels.data[j + 1] = rgb[1]; pixels.data[j + 2] = rgb[2]; pixels.data[j + 3] = mask[i] ? 255 : 0;
  }
  ctx.putImageData(pixels, 0, 0);
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;
  return texture;
}
function updateTerrainGeometry(geometry, lift = 0) {
  const positions = geometry.attributes.position;
  for (let i = 0; i < positions.count; i++) {
    const x = positions.getX(i), z = positions.getZ(i);
    positions.setY(i, groundHeight(x, z) + lift);
  }
  positions.needsUpdate = true;
  geometry.computeVertexNormals();
  geometry.computeBoundingSphere();
}
function groundGeometry() {
  const side = LAND_SEGMENTS + 1, positions = new Float32Array(side * side * 3), uvs = new Float32Array(side * side * 2), indices = [];
  let p = 0, uv = 0;
  for (let z = 0; z <= LAND_SEGMENTS; z++) for (let x = 0; x <= LAND_SEGMENTS; x++) {
    const wx = x / LAND_SEGMENTS * LAND_SPAN - LAND_SPAN / 2, wz = z / LAND_SEGMENTS * LAND_SPAN - LAND_SPAN / 2;
    positions[p++] = wx; positions[p++] = groundHeight(wx, wz); positions[p++] = wz;
    uvs[uv++] = x / LAND_SEGMENTS; uvs[uv++] = 1 - z / LAND_SEGMENTS;
    if (x < LAND_SEGMENTS && z < LAND_SEGMENTS) {
      const a = z * side + x, b = a + 1, c = a + side, d = c + 1;
      indices.push(a, c, b, b, c, d);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  g.setAttribute("uv", new THREE.BufferAttribute(uvs, 2));
  g.setIndex(indices);
  g.computeVertexNormals();
  return g;
}
function detailTexture(base, marks) {
  const n = 256, cv = document.createElement("canvas");
  cv.width = cv.height = n;
  const g = cv.getContext("2d");
  g.fillStyle = base; g.fillRect(0, 0, n, n);
  let seed = 3391;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  for (let i = 0; i < 1100; i++) {
    g.globalAlpha = 0.08 + rnd() * 0.18;
    g.fillStyle = marks[i % marks.length];
    const r = 1 + rnd() * 6;
    g.beginPath(); g.ellipse(rnd() * n, rnd() * n, r * 1.8, r, rnd() * TAU, 0, TAU); g.fill();
  }
  g.globalAlpha = 1;
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}
const SOIL = detailTexture("#75684f", ["#443f36", "#c0a77a", "#8e795a"]);
const WATER = detailTexture("#245363", ["#75b4bd", "#3e8798", "#172f48"]);
WATER.repeat.set(1, 1);
function ribbon(pointAt, start, end, segments, halfWidth, material, across = 1) {
  const positions = new Float32Array((segments + 1) * 6), uvs = new Float32Array((segments + 1) * 4), indices = [];
  for (let i = 0; i <= segments; i++) {
    const t = start + (end - start) * i / segments, p = pointAt(t), before = pointAt(t - 0.2), after = pointAt(t + 0.2);
    const dx = after.x - before.x, dz = after.z - before.z, len = Math.hypot(dx, dz) || 1, nx = dz / len, nz = -dx / len;
    const width = typeof halfWidth === "function" ? halfWidth(t) : halfWidth;
    const y = groundHeight(p.x, p.z) + (material === WATER_MAT ? 0.56 : 0.035);
    const j = i * 6;
    positions[j] = p.x - nx * width; positions[j + 1] = y; positions[j + 2] = p.z - nz * width;
    positions[j + 3] = p.x + nx * width; positions[j + 4] = y; positions[j + 5] = p.z + nz * width;
    const dist = i / segments * (end - start), k = i * 4;
    uvs[k] = 0; uvs[k + 1] = dist / 14; uvs[k + 2] = across; uvs[k + 3] = dist / 14;
    if (i < segments) { const a = i * 2, b = a + 1, c = a + 2, d = a + 3; indices.push(a, c, b, b, c, d); }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  g.setAttribute("uv", new THREE.BufferAttribute(uvs, 2));
  g.setIndex(indices);
  g.computeVertexNormals();
  const mesh = new THREE.Mesh(g, material);
  mesh.frustumCulled = false;
  return mesh;
}
const WATER_MAT = new THREE.MeshToonMaterial({ map: WATER, color: 0xa6d8dc, gradientMap: BANDS, side: THREE.DoubleSide });
const ROAD_MAT = new THREE.MeshLambertMaterial({ map: SOIL, color: 0xd7c8a6, side: THREE.DoubleSide });
function footbridge() {
  const g = group(), wood = 0x715337, plank = 0x927149, rail = 0x58432f;
  put(g, part(new THREE.BoxGeometry(24, 0.22, 6), wood), 0, 0, 0);
  for (let i = -6; i <= 6; i++) put(g, part(new THREE.BoxGeometry(1.62, 0.13, 5.7), i % 2 ? plank : 0x806342), i * 1.8, 0.17, 0);
  for (const side of [-1, 1]) {
    for (const x of [-10.5, 0, 10.5]) put(g, part(new THREE.BoxGeometry(0.2, 1, 0.2), rail), x, 0.62, side * 2.75);
    put(g, part(new THREE.BoxGeometry(23, 0.18, 0.18), rail), 0, 1.02, side * 2.75);
  }
  return bake(g);
}
function crossingPoint() {
  let best = { x: 0, z: 0, distance: Infinity };
  for (let x = -140; x <= 140; x += 0.5) {
    const z = trailZ(x), distance = Math.abs(x - riverX(z));
    if (distance < best.distance) best = { x, z, distance };
  }
  return best;
}
const CROSSING = crossingPoint();
const BRIDGE_SLOPE = trailZ(CROSSING.x + 0.5) - trailZ(CROSSING.x - 0.5);
const BRIDGE_ANGLE = -Math.atan2(BRIDGE_SLOPE, 1);
function surfaceHeight(x, z) {
  if (inHouse(x, z)) return interiorFloor;
  if (mapFeatures) {
    const ground = groundHeight(x, z), water = riverDistance(x, z), path = trailDistance(x, z);
    const roadCrossing = (1 - smooth(3.5, 9, path)) * (1 - smooth(7, 17, water));
    return ground + Math.max(0, landHeight(x, z) - ground) * roadCrossing;
  }
  const ground = groundHeight(x, z), dx = periodicDelta(x, CROSSING.x), dz = periodicDelta(z, CROSSING.z);
  const along = Math.cos(BRIDGE_ANGLE) * dx - Math.sin(BRIDGE_ANGLE) * dz;
  const across = Math.sin(BRIDGE_ANGLE) * dx + Math.cos(BRIDGE_ANGLE) * dz;
  const deck = landHeight(CROSSING.x, CROSSING.z) - 0.015;
  const onBridge = (1 - smooth(10.8, 12.3, Math.abs(along))) * (1 - smooth(2.5, 3.3, Math.abs(across)));
  return ground + Math.max(0, deck - ground) * onBridge;
}
function tuftGeometry() { // five blades leaning out from a point, lit from above
  const pos = [], nrm = [];
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2 + 0.3, w = 0.05, out = 0.12 + (i % 2) * 0.1, h = 0.3 + (i % 3) * 0.09;
    const cx = Math.cos(a), cz = Math.sin(a);
    pos.push(-cz * w, 0, cx * w, cz * w, 0, -cx * w, cx * out, h, cz * out);
    nrm.push(0, 1, 0, 0, 1, 0, 0, 1, 0);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  return g;
}
// a soft round glow (lanterns, the moonwell's water, mushrooms, wisps), white: tinted where it's used
const HALO = (() => {
  const n = 64, cv = document.createElement("canvas");
  cv.width = cv.height = n;
  const g = cv.getContext("2d"), grad = g.createRadialGradient(n / 2, n / 2, 0, n / 2, n / 2, n / 2);
  grad.addColorStop(0, "rgba(255,255,255,1)");
  grad.addColorStop(0.35, "rgba(255,255,255,0.45)");
  grad.addColorStop(1, "rgba(255,255,255,0)");
  g.fillStyle = grad;
  g.fillRect(0, 0, n, n);
  return new THREE.CanvasTexture(cv);
})();
function halo(color, size, opacity) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: HALO, color, transparent: true, opacity, depthWrite: false,
    blending: THREE.AdditiveBlending }));
  s.scale.set(size, size, 1);
  return s;
}
const glowings = new Map();
function glowing(color, strength = 0.7) { // a part giving light of its own: a mushroom's cap, a lantern
  const key = color + ":" + strength;
  if (!glowings.has(key)) glowings.set(key, new THREE.MeshToonMaterial({ color, gradientMap: BANDS, emissive: color, emissiveIntensity: strength }));
  return glowings.get(key);
}
// Each prop: block (its solid footprint's radius: you walk under a crown, not through a trunk; 0, through it)
// and height (how high its solid part stands: the camera pulls in front of what's under it).
function canopy(g, rnd, y, spread, size, n) {
  for (let i = 0; i < n; i++) {
    const r = size * (0.7 + rnd() * 0.5), a = rnd() * Math.PI * 2, d = rnd() * spread;
    put(g, part(new THREE.IcosahedronGeometry(r, 1), CANOPY[Math.floor(rnd() * CANOPY.length)]),
      Math.cos(a) * d, y + (rnd() - 0.3) * size * 0.8, Math.sin(a) * d);
  }
}
function giantTree(rnd) { // one of Teldrassil's: a thick twisting trunk on splayed roots, a crown of violet and teal
  const g = group(), r = 1.0 + rnd() * 0.6, h = 7 + rnd() * 4;
  Object.assign(g.userData, { block: r * 1.2, height: h });
  let x = 0, z = 0;
  for (let i = 0; i < 4; i++) {
    const seg = h / 4, r0 = r * (1 - i * 0.16), r1 = r * (1 - (i + 1) * 0.16);
    const c = put(g, cylinder(r1, r0, seg * 1.08, i % 2 ? BARK : BARK_DARK, 9), x, seg * (i + 0.5), z);
    c.rotation.set((rnd() - 0.5) * 0.12, i * 0.6, (rnd() - 0.5) * 0.12);
    x += (rnd() - 0.5) * 0.35;
    z += (rnd() - 0.5) * 0.35;
  }
  for (let i = 0; i < 5; i++) { // roots, out and down into the ground
    const a = (i / 5) * Math.PI * 2 + rnd() * 0.5, root = put(g, group(), Math.cos(a) * r * 0.75, 0.3, Math.sin(a) * r * 0.75);
    root.rotation.y = -a;
    put(root, cone(r * 0.38, r * 1.9, BARK_DARK, 6), r * 0.6, -0.05, 0).rotation.z = -(Math.PI / 2 - 0.3);
  }
  canopy(g, rnd, h + 1.5, 3.2, 3.4, 6);
  return g;
}
function forestTree(rnd) {
  const g = group(), h = 2.8 + rnd() * 2.2;
  Object.assign(g.userData, { block: 0.36, height: h });
  put(g, cylinder(0.22, 0.32, h, BARK, 8), 0, h / 2, 0);
  canopy(g, rnd, h + 0.8, 1.0, 1.4, 3 + Math.floor(rnd() * 2));
  return g;
}
function moonwell() { // a ring of pale stone round still, glowing water, two crescent pillars
  const g = group();
  Object.assign(g.userData, { block: 2.4, height: 1.2 });
  put(g, ring(2.0, 0.32, STONE), 0, 0.3, 0).rotation.x = Math.PI / 2;
  const water = put(g, new THREE.Mesh(new THREE.CircleGeometry(1.8, 32), glow(0x86e4ff)), 0, 0.42, 0);
  water.rotation.x = -Math.PI / 2;
  put(g, halo(0x7fdcff, 6, 0.35), 0, 0.9, 0);
  for (const side of [-1, 1]) {
    put(g, cylinder(0.14, 0.18, 1.4, STONE, 8), side * 2.0, 0.7, 0);
    put(g, horn(0.3, 0.06, Math.PI * 1.1, STONE, side, 0.7), side * 2.0, 1.45, 0);
  }
  return g;
}
function lantern() { // a night elf lamp: a curved wooden post, a violet light hanging from it
  const g = group();
  Object.assign(g.userData, { block: 0.25, height: 3 });
  put(g, cylinder(0.06, 0.09, 2.6, BARK_DARK, 8), 0, 1.3, 0);
  put(g, horn(0.4, 0.05, Math.PI * 0.75, BARK_DARK, 1, 0.5), 0, 2.55, 0);
  put(g, ball(0.14, glowing(0xc9b8ff, 1.0), 1, 1.2, 1), 0.42, 2.45, 0);
  put(g, ring(0.13, 0.015, 0xd8d0f0, 0), 0.42, 2.45, 0);
  put(g, halo(0xb9a3ff, 2.2, 0.55), 0.42, 2.45, 0);
  return g;
}
function mushrooms(rnd) { // a cluster of tall glowing mushrooms
  const g = group(), color = rnd() < 0.5 ? 0x58d6c6 : 0xb07cf0, n = 1 + Math.floor(rnd() * 3);
  Object.assign(g.userData, { block: 0.3, height: 1.5 });
  for (let i = 0; i < n; i++) {
    const h = 0.6 + rnd() * 1.2, r = 0.3 + rnd() * 0.35, a = rnd() * Math.PI * 2, d = i ? 0.45 : 0;
    const x = Math.cos(a) * d, z = Math.sin(a) * d;
    put(g, cylinder(0.07, 0.1, h, 0xe8e2d0, 8), x, h / 2, z);
    put(g, part(new THREE.SphereGeometry(r, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), glowing(color, 0.55)), x, h - 0.04, z);
    if (!i) put(g, halo(color, r * 5, 0.3), x, h + 0.15, z);
  }
  return g;
}
function mossRock(rnd) {
  const g = group(), size = 0.5 + rnd() * 1.0;
  Object.assign(g.userData, { block: size * 0.85, height: size });
  const stone = put(g, part(new THREE.DodecahedronGeometry(size, 0), [0x7a7f96, 0x6c7088, 0x8a8ea4][Math.floor(rnd() * 3)]), 0, size * 0.35, 0);
  stone.scale.y = 0.65;
  stone.rotation.set(rnd() * 3, 0, rnd() * 3);
  put(g, ball(size * 0.7, MOSS, 1.1, 0.35, 1.0), 0, size * 0.72, 0);
  return g;
}
function fern(rnd) { // low fronds you walk through
  const g = group();
  Object.assign(g.userData, { block: 0, height: 0 });
  for (let i = 0, n = 6 + Math.floor(rnd() * 3); i < n; i++) {
    put(tilted(g, 0, 0.05, 0, (i / n) * Math.PI * 2 + rnd() * 0.3, 1.0 + rnd() * 0.3), leaf(0.6 + rnd() * 0.4, i % 2 ? 0x3f7a55 : 0x4f8a5f), 0, 0.3, 0);
  }
  return g;
}
const HAZE = new THREE.Color(0x8a93bd);
function hazy(color, k) { // far away: a colour part way to the sky's haze, unlit by fog
  const m = new THREE.MeshToonMaterial({ color: new THREE.Color(color).lerp(HAZE, k), gradientMap: BANDS });
  m.fog = false;
  return m;
}
function farTree(rnd) { // one of the colossal trees on the horizon
  const g = group(), r = 4 + rnd() * 3, h = 34 + rnd() * 22;
  put(g, part(new THREE.CylinderGeometry(r * 0.65, r, h, 10), hazy(BARK, 0.42), 0), 0, h / 2, 0);
  for (let i = 0; i < 5; i++) {
    const a = rnd() * Math.PI * 2, d = rnd() * r * 2.5;
    put(g, part(new THREE.IcosahedronGeometry(15 + rnd() * 11, 1), hazy(CANOPY[Math.floor(rnd() * CANOPY.length)], 0.42), 0),
      Math.cos(a) * d, h + rnd() * 12, Math.sin(a) * d);
  }
  return g;
}
function moonTexture() {
  const n = 128, cv = document.createElement("canvas");
  cv.width = cv.height = n;
  const g = cv.getContext("2d"), grad = g.createRadialGradient(n / 2, n / 2, 0, n / 2, n / 2, n / 2);
  grad.addColorStop(0, "rgba(245,246,255,1)");
  grad.addColorStop(0.42, "rgba(232,236,255,1)");
  grad.addColorStop(0.47, "rgba(200,210,255,0.35)");
  grad.addColorStop(1, "rgba(160,170,255,0)");
  g.fillStyle = grad;
  g.fillRect(0, 0, n, n);
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// A burst of leaves and sparks (a shapeshift, a demon arriving): small bits flying out, falling, fading.
function bursts(parent) {
  const pool = [];
  for (let i = 0; i < 40; i++) {
    const m = new THREE.Mesh(new THREE.OctahedronGeometry(0.09, 0), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true }));
    m.visible = false;
    parent.add(m);
    pool.push({ m, v: new THREE.Vector3(), life: 0 });
  }
  let next = 0;
  return {
    burst(x, y, z, colors, n = 20) {
      for (let i = 0; i < n; i++) {
        const p = pool[next++ % pool.length], a = Math.random() * Math.PI * 2, out = 1.5 + Math.random() * 2.5;
        p.m.position.set(x + Math.cos(a) * 0.3, y + Math.random() * 1.4, z + Math.sin(a) * 0.3);
        p.v.set(Math.cos(a) * out, 1 + Math.random() * 3, Math.sin(a) * out);
        p.m.material.color.setHex(colors[i % colors.length]);
        p.m.scale.setScalar(0.6 + Math.random() * 0.9);
        p.life = 0.55 + Math.random() * 0.3;
        p.m.visible = true;
      }
    },
    step(dt) {
      for (const p of pool) {
        if (!p.m.visible) continue;
        p.life -= dt;
        if (p.life <= 0) { p.m.visible = false; continue; }
        p.v.y -= 6 * dt;
        p.m.position.addScaledVector(p.v, dt);
        p.m.rotation.x += dt * 6;
        p.m.rotation.y += dt * 4;
        p.m.material.opacity = Math.min(1, p.life * 3);
      }
    },
  };
}

// The target's marks, as the game's: a soft ring on the ground in its reaction's colour, its name over it.
function ringTexture() {
  const n = 256, cv = document.createElement("canvas");
  cv.width = cv.height = n;
  const g = cv.getContext("2d"), grad = g.createRadialGradient(n / 2, n / 2, n * 0.3, n / 2, n / 2, n / 2);
  grad.addColorStop(0, "rgba(255,255,255,0)");
  grad.addColorStop(0.55, "rgba(255,255,255,0.15)");
  grad.addColorStop(0.8, "rgba(255,255,255,1)");
  grad.addColorStop(0.9, "rgba(255,255,255,0.9)");
  grad.addColorStop(1, "rgba(255,255,255,0)");
  g.fillStyle = grad;
  g.fillRect(0, 0, n, n);
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
function nameplate() {
  const cv = document.createElement("canvas");
  cv.width = 1024;
  cv.height = 128;
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true }));
  sprite.renderOrder = 10;
  sprite.scale.set(4.8, 0.6, 1);
  sprite.userData.write = (text, color) => {
    const g = cv.getContext("2d");
    g.clearRect(0, 0, cv.width, cv.height);
    let px = 64;
    do g.font = `bold ${px}px Georgia, "Times New Roman", serif`; while (g.measureText(text).width > cv.width - 40 && (px -= 4) > 20);
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.lineJoin = "round";
    g.lineWidth = 9;
    g.strokeStyle = "rgba(0,0,0,0.85)";
    g.strokeText(text, cv.width / 2, cv.height / 2);
    g.fillStyle = color;
    g.fillText(text, cv.width / 2, cv.height / 2);
    tex.needsUpdate = true;
  };
  return sprite;
}

// ---------------------------------------------------------------- the world
const FORMS = { // the druid's forms: their figure, run speed (yards a second), size on the ground
  caster: { make: nightElf, run: 7, shadow: 0.85, radius: 0.35 },
  bear: { make: bear, run: 7, shadow: 1.5, radius: 0.75 },
  cat: { make: cat, run: 7, shadow: 1.15, radius: 0.45 },
  travel: { make: cheetah, run: 9.8, shadow: 1.2, radius: 0.45 }, // 40% faster
  moonkin: { make: moonkin, run: 7, shadow: 1.1, radius: 0.6 },
};
const PETS = { beast: { make: wolf, run: 7, shadow: 0.55, radius: 0.4 }, demon: { make: voidwalker, run: 7, shadow: 0.6, radius: 0.45 } };
const KINDS = { furbolg: { make: furbolg, ring: 1.05, label: 2.55 }, nightsaber: { make: nightsaber, ring: 1.35, label: 1.95 },
  sentinel: { make: () => nightElf(SENTINEL), ring: 0.9, label: 2.75 } };
export const TARGETS = { // what the Target choice puts ahead of you, and its marks' colour (the game's reaction colours)
  hostile: { kind: "furbolg", name: "Gnarlpine Warrior", color: "#ff3a2a" },
  tapped: { kind: "furbolg", name: "Gnarlpine Warrior", color: "#9a9a9a" },
  neutral: { kind: "nightsaber", name: "Nightsaber", color: "#ffd42a" },
  friendly: { kind: "sentinel", name: "Darnassian Sentinel", color: "#3ce04a" },
};
const SHIFT = [0x8fe05a, 0xd6ff9a, 0x4fae3a, 0xfff2a8]; // a shapeshift's leaves and light
// A ghost's world: the picture's own light in a pale blue (the veil over it: its hue on the world's brightness), a
// little brighter and flatter; eased in and out by opacity (a filter's hue turning between would pass through red)
const GHOST_SIGHT = "brightness(1.12) contrast(0.92)";
const SUMMON = [0x8d7bff, 0x4b3fbf, 0xc9b8ff];         // a demon's arrival

export function createWorld() {
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setPixelRatio(1);
  renderer.domElement.style.transition = "filter 1.4s ease"; // into a ghost's world and out of it
  const veil = document.createElement("div"); // laid over the world's canvas by the page, under the HUD's
  veil.className = "ghostveil";
  Object.assign(veil.style, { position: "absolute", inset: "0", pointerEvents: "none", background: "#93b4ea", mixBlendMode: "color",
    opacity: "0", transition: "opacity 1.4s ease" });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const scene = new THREE.Scene();
  // the sky at twilight: indigo overhead to a violet haze at the horizon, the fog the same haze; moonlight
  const sky = document.createElement("canvas");
  sky.width = 2;
  sky.height = 256;
  const sg = sky.getContext("2d"), grad = sg.createLinearGradient(0, 0, 0, 256);
  grad.addColorStop(0, "#221a52");
  grad.addColorStop(0.5, "#4f4290");
  grad.addColorStop(0.85, "#7f7fb6");
  grad.addColorStop(1, "#8a93bd");
  sg.fillStyle = grad;
  sg.fillRect(0, 0, 2, 256);
  scene.background = new THREE.CanvasTexture(sky);
  scene.background.colorSpace = THREE.SRGBColorSpace;
  scene.fog = new THREE.Fog(0x8a93bd, 35, 270);
  scene.add(new THREE.HemisphereLight(0xc8d0ff, 0x34442f, 1.3));
  const moonlight = new THREE.DirectionalLight(0xe2e6ff, 1.6); // from the upper left, as the HUD's glass is lit
  moonlight.position.set(-40, 70, 25);
  scene.add(moonlight);

  // the world, turned and moved round you
  const world = group();
  scene.add(world);
  const land = group();
  world.add(land);
  const ground = new THREE.Mesh(groundGeometry(), new THREE.MeshLambertMaterial({ map: grassTexture(), vertexColors: false }));
  ground.material.map.repeat.set(LAND_SPAN / 10, LAND_SPAN / 10); // 10 yards a repeat
  land.add(ground);
  const fallbackFeatures = [];
  const mainRiver = ribbon(t => ({ x: riverX(t), z: t }), -LAND_SPAN / 2, LAND_SPAN / 2, 420,
    t => 6.6 + 0.7 * Math.sin(TAU * t / LAND_SPAN * 4 + 0.6), WATER_MAT, 1);
  fallbackFeatures.push(mainRiver, ribbon(t => ({ x: t, z: tributaryZ(t) }), -LAND_SPAN / 2, LAND_SPAN / 2, 300, 6, WATER_MAT, 1));
  fallbackFeatures.push(ribbon(t => ({ x: t, z: trailZ(t) }), -LAND_SPAN / 2, CROSSING.x - 12, 300, 2.6, ROAD_MAT, 1));
  fallbackFeatures.push(ribbon(t => ({ x: t, z: trailZ(t) }), CROSSING.x + 12, LAND_SPAN / 2, 300, 2.6, ROAD_MAT, 1));
  fallbackFeatures.push(ribbon(t => ({ x: trailX(t), z: t }), -LAND_SPAN / 2, LAND_SPAN / 2, 300, 2.1, ROAD_MAT, 1));
  fallbackFeatures.forEach(mesh => land.add(mesh));
  const bridge = footbridge();
  bridge.position.set(CROSSING.x, landHeight(CROSSING.x, CROSSING.z) - 0.25, CROSSING.z);
  bridge.rotation.y = BRIDGE_ANGLE;
  land.add(bridge);
  interiorFloor = groundHeight(TEST_HOUSE.x, TEST_HOUSE.z);
  const house = group(), roof = group();
  house.position.set(TEST_HOUSE.x, interiorFloor, TEST_HOUSE.z);
  world.add(house);
  const wallColor = 0x765865, beamColor = 0x463447, trimColor = 0xd1ae6b, stoneColor = 0xaaa08e, floorColor = 0x505943;
  put(house, part(new THREE.BoxGeometry(TEST_HOUSE.halfWidth * 2 - 1.2, 0.35, TEST_HOUSE.halfDepth * 2 - 1.2), floorColor), 0, -0.14, 0);
  const wall = (w, h, d, x, y, z, color = wallColor) => put(house, part(new THREE.BoxGeometry(w, h, d), color), x, y, z);
  const wallHeight = 6.7, wallCenter = wallHeight / 2, doorWidth = TEST_HOUSE.doorHalf * 2;
  wall(0.6, wallHeight, TEST_HOUSE.halfDepth * 2, -TEST_HOUSE.halfWidth + 0.3, wallCenter, 0, beamColor);
  wall(0.6, wallHeight, TEST_HOUSE.halfDepth * 2, TEST_HOUSE.halfWidth - 0.3, wallCenter, 0, beamColor);
  wall(TEST_HOUSE.halfWidth * 2, wallHeight, 0.6, 0, wallCenter, -TEST_HOUSE.halfDepth + 0.3);
  const frontSide = (TEST_HOUSE.halfWidth * 2 - doorWidth) / 2;
  wall(frontSide, wallHeight, 0.6, -(doorWidth + frontSide) / 2, wallCenter, TEST_HOUSE.halfDepth - 0.3);
  wall(frontSide, wallHeight, 0.6, (doorWidth + frontSide) / 2, wallCenter, TEST_HOUSE.halfDepth - 0.3);
  wall(doorWidth, 1.5, 0.6, 0, wallHeight - 0.75, TEST_HOUSE.halfDepth - 0.3, beamColor);
  // Night Elf inn details: pale cut-stone plinths, rose plaster, carved timber and gilt leafwork.
  for (const x of [-10.8, -6.1, 6.1, 10.8]) {
    put(house, part(new THREE.BoxGeometry(1.25, 0.55, 1.25), stoneColor), x, 0.25, TEST_HOUSE.halfDepth - 0.8);
    put(house, cylinder(0.43, 0.35, 5.85, stoneColor, 8), x, 3.2, TEST_HOUSE.halfDepth - 0.8);
    put(house, cylinder(0.55, 0.45, 0.38, trimColor, 8), x, 0.85, TEST_HOUSE.halfDepth - 0.8);
    put(house, cylinder(0.55, 0.45, 0.38, trimColor, 8), x, 5.95, TEST_HOUSE.halfDepth - 0.8);
  }
  for (const x of [-9.2, 9.2]) {
    wall(3.1, 3.5, 0.12, x, 3.05, TEST_HOUSE.halfDepth + 0.035, 0x463b51);
    wall(2.6, 2.95, 0.08, x, 3.05, TEST_HOUSE.halfDepth + 0.12, 0xb47b8b);
    wall(3.4, 0.24, 0.24, x, 4.95, TEST_HOUSE.halfDepth + 0.16, trimColor);
    wall(3.4, 0.24, 0.24, x, 1.18, TEST_HOUSE.halfDepth + 0.16, trimColor);
    for (const dx of [-1.3, 1.3]) wall(0.18, 3.6, 0.2, x + dx, 3.05, TEST_HOUSE.halfDepth + 0.18, trimColor);
  }
  // A broad, carved entry porch and a raised central gable make the silhouette read like a Teldrassil inn.
  const entryArch = new THREE.Mesh(new THREE.TorusGeometry(3.65, 0.24, 9, 40, Math.PI),
    new THREE.MeshToonMaterial({ color: trimColor, gradientMap: BANDS }));
  entryArch.position.set(0, 4.15, TEST_HOUSE.halfDepth + 0.18);
  house.add(entryArch);
  const doorCap = new THREE.Mesh(new THREE.TorusGeometry(4.05, 0.33, 9, 40, Math.PI),
    new THREE.MeshToonMaterial({ color: beamColor, gradientMap: BANDS }));
  doorCap.position.set(0, 4.05, TEST_HOUSE.halfDepth + 0.05);
  house.add(doorCap);
  for (const x of [-3.55, 3.55]) {
    put(house, cylinder(0.42, 0.62, 6.3, beamColor, 9), x, 3.15, TEST_HOUSE.halfDepth + 0.1);
    put(house, cylinder(0.56, 0.8, 0.4, trimColor, 9), x, 0.35, TEST_HOUSE.halfDepth + 0.1);
    put(house, cylinder(0.65, 0.55, 0.4, trimColor, 9), x, 6.2, TEST_HOUSE.halfDepth + 0.1);
    put(house, ball(0.35, glowing(0x8ce6d5, 0.75), 0.75, 0.9, 0.3), x, 6.85, TEST_HOUSE.halfDepth + 0.12);
  }
  for (const side of [-1, 1]) {
    const leaf = new THREE.Shape();
    leaf.moveTo(0, 0); leaf.quadraticCurveTo(side * 0.8, 0.8, side * 1.6, 2.3);
    leaf.quadraticCurveTo(side * 0.1, 1.8, 0, 0);
    const ornament = new THREE.Mesh(new THREE.ShapeGeometry(leaf), new THREE.MeshToonMaterial({ color: trimColor, gradientMap: BANDS, side: THREE.DoubleSide }));
    ornament.position.set(side < 0 ? -2.9 : 1.3, 2.05, TEST_HOUSE.halfDepth + 0.22);
    house.add(ornament);
  }
  // Timber gables and steep purple tiled roofs. The broad roof stays in the scene indoors too.
  const up = new THREE.Vector3(0, 1, 0);
  function brace(parent, x0, y0, z0, x1, y1, z1, radius, color) {
    const a = new THREE.Vector3(x0, y0, z0), b = new THREE.Vector3(x1, y1, z1), axis = b.clone().sub(a);
    const brace = part(new THREE.CylinderGeometry(radius * 0.72, radius, axis.length(), 8), color);
    brace.position.copy(a).add(b).multiplyScalar(0.5);
    brace.quaternion.setFromUnitVectors(up, axis.normalize());
    parent.add(brace);
  }
  function gable(z, half, baseY, peakY, color) {
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute([-half, baseY, z, half, baseY, z, 0, peakY, z], 3));
    geometry.setIndex([0, 1, 2]); geometry.computeVertexNormals();
    house.add(new THREE.Mesh(geometry, new THREE.MeshToonMaterial({ color, gradientMap: BANDS, side: THREE.DoubleSide })));
    brace(house, -half, baseY, z, 0, peakY, z, 0.24, beamColor);
    brace(house, 0, peakY, z, half, baseY, z, 0.24, beamColor);
    brace(house, -half + 0.5, baseY + 0.5, z, half - 0.5, baseY + 0.5, z, 0.14, trimColor);
  }
  gable(TEST_HOUSE.halfDepth + 0.32, 5.3, 6.55, 15.3, 0x8b687d);
  gable(-TEST_HOUSE.halfDepth - 0.32, 5.3, 6.55, 15.3, 0x76566f);
  const roofCanvas = document.createElement("canvas");
  roofCanvas.width = roofCanvas.height = 256;
  const tilePaint = roofCanvas.getContext("2d");
  tilePaint.fillStyle = "#73518c";
  tilePaint.fillRect(0, 0, 256, 256);
  for (let row = 0; row < 9; row++) for (let col = -1; col < 7; col++) {
    const x = col * 38 + (row % 2) * 19, y = row * 30;
    tilePaint.beginPath();
    tilePaint.moveTo(x, y + 1); tilePaint.lineTo(x + 38, y + 1); tilePaint.lineTo(x + 38, y + 14);
    tilePaint.quadraticCurveTo(x + 19, y + 34, x, y + 14); tilePaint.closePath();
    tilePaint.fillStyle = (row + col + 16) % 3 === 0 ? "#8d6ba2" : (row + col + 16) % 3 === 1 ? "#795792" : "#68477f";
    tilePaint.fill(); tilePaint.strokeStyle = "#b29aaf"; tilePaint.lineWidth = 1.2; tilePaint.stroke();
    tilePaint.beginPath(); tilePaint.moveTo(x + 4, y + 5); tilePaint.lineTo(x + 33, y + 5);
    tilePaint.strokeStyle = "rgba(222,194,222,.25)"; tilePaint.stroke();
  }
  const roofTiles = new THREE.CanvasTexture(roofCanvas);
  roofTiles.colorSpace = THREE.SRGBColorSpace;
  roofTiles.wrapS = roofTiles.wrapT = THREE.RepeatWrapping;
  const tileMaterial = new THREE.MeshToonMaterial({ map: roofTiles, color: 0xffffff, gradientMap: BANDS, side: THREE.DoubleSide });
  const panel = (parent, length, depth, x, y, z, rz, rx) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(length, 0.42, depth), tileMaterial);
    mesh.position.set(x, y, z); mesh.rotation.set(rx, 0, rz); parent.add(mesh);
    return mesh;
  };
  const mainSlope = Math.hypot(5.55, 8.5);
  panel(roof, mainSlope, 22.2, -2.775, 10.8, 0, 0.99, 0);
  panel(roof, mainSlope, 22.2, 2.775, 10.8, 0, -0.99, 0);
  for (const side of [-1, 1]) {
    brace(roof, side * 5.45, 7.2, -10.6, side * 5.45, 7.2, 10.6, 0.42, beamColor);
    brace(roof, side * 5.45, 7.28, 10.6, 0, 15.45, 10.6, 0.3, trimColor);
    brace(roof, side * 5.45, 7.28, -10.6, 0, 15.45, -10.6, 0.3, trimColor);
  }
  const wingSlope = Math.hypot(5.5, 2.7), wingAngle = Math.atan2(2.7, 5.5);
  for (const side of [-1, 1]) {
    for (const depthSide of [-1, 1]) {
      const z = depthSide * 2.75, y = 7.75;
      panel(roof, 7.8, wingSlope, side * 8.55, y, depthSide * 1.38, 0, depthSide * wingAngle);
    }
    brace(roof, side * 5.1, 7.85, -5.7, side * 12.1, 7.85, -5.7, 0.34, trimColor);
    brace(roof, side * 5.1, 7.85, 5.7, side * 12.1, 7.85, 5.7, 0.34, trimColor);
  }
  const ridge = part(new THREE.BoxGeometry(0.8, 0.7, 22.6), trimColor);
  ridge.position.set(0, 15.05, 0); roof.add(ridge);
  for (const z of [-8, -4, 0, 4, 8]) for (const side of [-1, 1]) {
    brace(roof, side * 5.1, 7.25, z, 0, 14.95, z, 0.16, beamColor);
  }
  house.add(roof);
  const innerGlow = new THREE.PointLight(0xffc982, 11, 28, 1.8);
  innerGlow.position.set(0, 6.1, 0);
  house.add(innerGlow);
  for (const z of [-6, 3]) {
    const lamp = put(house, ball(0.22, glowing(0xffcf7e, 0.9), 0.75, 0.75, 0.75), 0, 5.9, z);
    const glow = new THREE.PointLight(0xffc982, 5, 13, 2);
    glow.position.copy(lamp.position); house.add(glow);
  }
  // A bed and a small table make the top-down plan read as a lived-in interior.
  put(house, part(new THREE.BoxGeometry(5.2, 0.5, 3.4), 0x6f4d57), -7.5, 0.5, -5.8);
  put(house, part(new THREE.BoxGeometry(4.8, 1.1, 3.2), 0x6b5945), 5.8, 0.55, -1.8);
  put(house, part(new THREE.BoxGeometry(1.1, 0.65, 1.1), 0x493d38), 0, 0.33, -8.4);
  let seed = 11;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const props = []; // each at its place in the tile, drawn in the tile's copy nearest you
  const nearestTilePoint = (x, z, point) => [x + TILE * Math.round((point.x - x) / TILE), z + TILE * Math.round((point.z - z) / TILE)];
  function blockedPropSpot(x, z, clear) {
    const [sx, sz] = nearestTilePoint(x, z, SPAWN_AT), [hx, hz] = nearestTilePoint(x, z, TEST_HOUSE);
    return Math.hypot(sx - SPAWN_AT.x, sz - SPAWN_AT.z) < clear + 5 || inHouse(hx, hz, clear + 1)
      || riverDistance(sx, sz) < 18 || trailDistance(sx, sz) < 5;
  }
  function place(obj, clear = 9) {
    let x, z;
    do {
      x = (rnd() - 0.5) * TILE; z = (rnd() - 0.5) * TILE;
    } while (blockedPropSpot(x, z, clear)); // leave the spawn and room clear, and keep props off the paths
    obj.userData.base = [x, z];
    obj.rotation.y = rnd() * Math.PI * 2;
    world.add(obj);
    props.push(obj);
  }
  for (let i = 0; i < 18; i++) place(bake(giantTree(rnd)), 15);
  for (let i = 0; i < 40; i++) place(bake(forestTree(rnd)));
  for (let i = 0; i < 2; i++) place(bake(moonwell()), 14);
  for (let i = 0; i < 10; i++) place(bake(lantern()));
  for (let i = 0; i < 24; i++) place(bake(mushrooms(rnd)));
  for (let i = 0; i < 22; i++) place(bake(mossRock(rnd)));
  for (let i = 0; i < 34; i++) place(bake(fern(rnd)), 4);
  const minimapTerrain = new Image();
  minimapTerrain.onload = () => {
    mapFeatures = readMapFeatures(minimapTerrain);
    interiorFloor = groundHeight(TEST_HOUSE.x, TEST_HOUSE.z);
    house.position.y = interiorFloor;
    updateTerrainGeometry(ground.geometry);
    for (const mesh of fallbackFeatures) {
      land.remove(mesh);
      mesh.geometry.dispose();
    }
    land.remove(bridge);
    bridge.traverse(o => {
      if (o.geometry) o.geometry.dispose();
    });
    const waterMap = featureTexture(mapFeatures.water, [57, 137, 151]);
    const roadMap = featureTexture(mapFeatures.roads, [166, 135, 91]);
    const waterMesh = new THREE.Mesh(ground.geometry.clone(), new THREE.MeshLambertMaterial({
      map: waterMap, transparent: true, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -1,
    }));
    const roadMesh = new THREE.Mesh(ground.geometry.clone(), new THREE.MeshLambertMaterial({
      map: roadMap, transparent: true, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -2,
    }));
    updateTerrainGeometry(waterMesh.geometry, 0.56);
    updateTerrainGeometry(roadMesh.geometry, 0.04);
    waterMesh.renderOrder = 1;
    roadMesh.renderOrder = 2;
    land.add(waterMesh, roadMesh);
    // The props were placed before the image finished loading. Recheck the opening, room and map features now.
    for (const prop of props) {
      let [x, z] = prop.userData.base, tries = 0;
      while (blockedPropSpot(x, z, 9) && tries++ < 400) {
        x = (rnd() - 0.5) * TILE; z = (rnd() - 0.5) * TILE;
      }
      prop.userData.base = [x, z];
    }
    const settled = [];
    for (const c of ambient) {
      let x = c.homeX, z = c.homeZ, tries = 0;
      while ((riverDistance(x, z) < 12 || trailDistance(x, z) < 5 || inHouse(x, z, 2)
        || settled.some(p => Math.hypot(x - p.x, z - p.z) < 5)) && tries++ < 300) {
        const a = rnd() * TAU, d = 10 + rnd() * 18;
        x = SPAWN_AT.x + Math.cos(a) * d; z = SPAWN_AT.z + Math.sin(a) * d;
      }
      [c.x, c.z] = pushOut(x, z, c.kind === "nightsaber" ? 0.8 : 0.6);
      [c.homeX, c.homeZ] = [c.x, c.z];
      [c.targetX, c.targetZ] = [c.x, c.z];
      settled.push({ x: c.x, z: c.z });
    }
  };
  minimapTerrain.src = "./minimap_forest.webp";
  // the solid props: a body of `radius` at (x, z) pushed out of any it stands in, so it slides along them
  const hx0 = TEST_HOUSE.x - TEST_HOUSE.halfWidth, hx1 = TEST_HOUSE.x + TEST_HOUSE.halfWidth;
  const hz0 = TEST_HOUSE.z - TEST_HOUSE.halfDepth, hz1 = TEST_HOUSE.z + TEST_HOUSE.halfDepth;
  const door0 = TEST_HOUSE.x - TEST_HOUSE.doorHalf, door1 = TEST_HOUSE.x + TEST_HOUSE.doorHalf, wallThickness = TEST_HOUSE.wall;
  const houseWalls = [
    [hx0, hx0 + wallThickness, hz0, hz1], [hx1 - wallThickness, hx1, hz0, hz1],
    [hx0, hx1, hz0, hz0 + wallThickness], [hx0, door0, hz1 - wallThickness, hz1], [door1, hx1, hz1 - wallThickness, hz1],
  ];
  function pushFromWall(x, z, radius, box) {
    const [x0, x1, z0, z1] = box, qx = clamp(x, x0, x1), qz = clamp(z, z0, z1);
    let dx = x - qx, dz = z - qz, d = Math.hypot(dx, dz);
    if (d >= radius) return [x, z];
    if (d > 1e-6) return [x + dx / d * (radius - d), z + dz / d * (radius - d)];
    const edges = [[x - x0, -1, 0], [x1 - x, 1, 0], [z - z0, 0, -1], [z1 - z, 0, 1]].sort((a, b) => a[0] - b[0]);
    const [dist, nx, nz] = edges[0];
    return [x + nx * (dist + radius), z + nz * (dist + radius)];
  }
  function pushOut(x, z, radius) {
    for (let pass = 0; pass < 3; pass++) {
      let moved = false;
      for (const p of props) {
        if (!p.userData.block) continue;
        const [bx, bz] = p.userData.base, R = p.userData.block + radius;
        const px = bx + TILE * Math.round((x - bx) / TILE), pz = bz + TILE * Math.round((z - bz) / TILE);
        const dx = x - px, dz = z - pz, d = Math.hypot(dx, dz);
        if (d >= R) continue;
        if (d > 1e-6) { x = px + dx / d * R; z = pz + dz / d * R; } else x = px + R;
        moved = true;
      }
      for (const box of houseWalls) {
        const p = pushFromWall(x, z, radius, box);
        if (p[0] !== x || p[1] !== z) { x = p[0]; z = p[1]; moved = true; }
      }
      if (!moved) break;
    }
    return [x, z];
  }
  // grass tufts: one mesh drawn many times, each wrapped into the tuft tile's copy nearest you
  const TUFTS = 520, tufts = new THREE.InstancedMesh(tuftGeometry(),
    new THREE.MeshToonMaterial({ gradientMap: BANDS, side: THREE.DoubleSide }), TUFTS);
  const tuftBase = [], tuftTurn = [], tuftSize = [], m4 = new THREE.Matrix4(), v3 = new THREE.Vector3(), sc = new THREE.Vector3(),
    Y = new THREE.Vector3(0, 1, 0), tint = new THREE.Color();
  for (let i = 0; i < TUFTS; i++) {
    tuftBase.push([(rnd() - 0.5) * TUFT_TILE, (rnd() - 0.5) * TUFT_TILE]);
    tuftTurn.push(new THREE.Quaternion().setFromAxisAngle(Y, rnd() * Math.PI * 2));
    tuftSize.push(0.55 + rnd() * 0.55);
    tufts.setColorAt(i, tint.setHex([0x4f8a5a, 0x5f9a63, 0x3f7553, 0x6a5f8f][i % 4]));
  }
  tufts.frustumCulled = false;
  world.add(tufts);
  // wisps: small lights drifting in the air round you (a tile of them wrapped round wherever you are)
  const WISPS = 90, WISP_TILE = 40, wispBase = [], wispGeo = new THREE.BufferGeometry(), wispPos = new Float32Array(WISPS * 3);
  const wispColors = new Float32Array(WISPS * 3);
  for (let i = 0; i < WISPS; i++) {
    wispBase.push([(rnd() - 0.5) * WISP_TILE, (rnd() - 0.5) * WISP_TILE, 0.6 + rnd() * 3, rnd() * 10]);
    tint.setHex([0x8ff0ff, 0xc9a8ff, 0xfff1b0][i % 3]).toArray(wispColors, i * 3);
  }
  wispGeo.setAttribute("position", new THREE.BufferAttribute(wispPos, 3));
  wispGeo.setAttribute("color", new THREE.BufferAttribute(wispColors, 3));
  const wisps = new THREE.Points(wispGeo, new THREE.PointsMaterial({ size: 0.3, map: HALO, vertexColors: true, transparent: true,
    depthWrite: false, blending: THREE.AdditiveBlending }));
  wisps.frustumCulled = false;
  world.add(wisps);
  // far off: colossal trees and hills, stars and the moon; always as far, turning with the world
  const far = group();
  world.add(far);
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2 + rnd() * 0.4, r = 220 + rnd() * 80;
    put(far, farTree(rnd), Math.cos(a) * r, -2, Math.sin(a) * r);
  }
  for (let i = 0; i < 18; i++) {
    const a = rnd() * Math.PI * 2, r = 200 + rnd() * 60;
    const hill = put(far, part(new THREE.SphereGeometry(30 + rnd() * 30, 16, 10), hazy(rnd() < 0.5 ? 0x3f5f55 : 0x4a4f6e, 0.3), 0),
      Math.cos(a) * r, -14, Math.sin(a) * r);
    hill.scale.y = 0.45;
  }
  const starPos = [];
  for (let i = 0; i < 520; i++) {
    const a = rnd() * Math.PI * 2, up = 0.18 + rnd() * 0.82, flat = Math.sqrt(1 - up * up);
    starPos.push(Math.cos(a) * flat * 800, up * 800, Math.sin(a) * flat * 800);
  }
  const starGeo = new THREE.BufferGeometry();
  starGeo.setAttribute("position", new THREE.Float32BufferAttribute(starPos, 3));
  far.add(new THREE.Points(starGeo, new THREE.PointsMaterial({ size: 1.6, sizeAttenuation: false, color: 0xe8ecff,
    transparent: true, opacity: 0.75, fog: false, depthWrite: false })));
  const moon = put(far, new THREE.Sprite(new THREE.SpriteMaterial({ map: moonTexture(), fog: false, depthWrite: false })),
    -480, 380, -420);
  moon.scale.set(110, 110, 1);

  // you: a figure a form, the one shown in the middle; your pet and your target in the world
  function blob(r) {
    const b = new THREE.Mesh(new THREE.CircleGeometry(r, 24),
      new THREE.MeshBasicMaterial({ color: 0, transparent: true, opacity: 0.25, depthWrite: false }));
    b.rotation.x = -Math.PI / 2;
    b.position.y = 0.02;
    return b;
  }
  const you = group();
  scene.add(you);
  const forms = {};
  for (const [name, f] of Object.entries(FORMS)) {
    forms[name] = mover(f.make());
    forms[name].rig.root.visible = false;
    you.add(forms[name].rig.root);
  }
  const shadow = blob(0.75);
  scene.add(shadow);
  // when the camera is pulled right up to you (your back to a tree), you fade, as in the game: your figures'
  // materials are their own, so fading you fades nothing else
  const fading = [];
  for (const f of Object.values(forms)) {
    const own = new Map();
    f.rig.root.traverse(o => {
      if (!o.isMesh) return;
      if (!own.has(o.material)) {
        const m = o.material.clone();
        m.userData.edge = o.material === INK;
        own.set(o.material, m);
        fading.push(m);
      }
      o.material = own.get(o.material);
    });
  }
  let shown = 1;
  function holder(m, shadowSize) { // a figure standing in the world, its shadow under it
    m.holder = group();
    m.holder.add(m.rig.root, blob(shadowSize));
    m.holder.visible = false;
    world.add(m.holder);
    return m;
  }
  const pets = {};
  for (const [name, p] of Object.entries(PETS)) pets[name] = holder(mover(p.make()), p.shadow);
  const ringMap = ringTexture(), targets = {};
  for (const [name, k] of Object.entries(KINDS)) {
    const t = targets[name] = holder(mover(k.make()), 0.7);
    t.ring = new THREE.Mesh(new THREE.PlaneGeometry(k.ring * 2, k.ring * 2),
      new THREE.MeshBasicMaterial({ map: ringMap, transparent: true, depthWrite: false }));
    t.ring.rotation.x = -Math.PI / 2;
    t.ring.position.y = 0.04;
    t.label = put(t.holder, nameplate(), 0, k.label, 0);
    t.holder.add(t.ring);
  }
  const ambient = [], ambientKinds = ["nightsaber", "sentinel", "nightsaber", "sentinel", "nightsaber"];
  for (let i = ambientKinds.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [ambientKinds[i], ambientKinds[j]] = [ambientKinds[j], ambientKinds[i]];
  }
  for (let i = 0; i < ambientKinds.length; i++) {
    const angle = TAU * i / ambientKinds.length + (rnd() - 0.5) * 0.55, distance = 10 + rnd() * 15;
    let x = SPAWN_AT.x + Math.cos(angle) * distance, z = SPAWN_AT.z + Math.sin(angle) * distance;
    const kind = ambientKinds[i], creature = holder(mover(KINDS[kind].make()), kind === "nightsaber" ? 1 : 0.75);
    const npc = { id: `npc-${i + 1}`, kind, name: kind === "sentinel" ? "Darnassian Sentinel" : "Nightsaber", reaction: kind === "sentinel" ? "friendly" : "neutral" };
    creature.ring = new THREE.Mesh(new THREE.PlaneGeometry(KINDS[kind].ring * 2, KINDS[kind].ring * 2),
      new THREE.MeshBasicMaterial({ map: ringMap, transparent: true, depthWrite: false, color: TARGETS[npc.reaction].color }));
    creature.ring.rotation.x = -Math.PI / 2;
    creature.ring.position.y = 0.04;
    creature.ring.visible = false;
    creature.holder.add(creature.ring);
    creature.label = put(creature.holder, nameplate(), 0, KINDS[kind].label, 0);
    creature.label.userData.write(npc.name, TARGETS[npc.reaction].color);
    creature.label.visible = false;
    [x, z] = pushOut(x, z, kind === "nightsaber" ? 0.8 : 0.6);
    creature.holder.visible = true;
    creature.yaw = rnd() * TAU;
    ambient.push({ ...npc, creature, kind, x, z, homeX: x, homeZ: z, targetX: x, targetZ: z, think: rnd() * 2 });
  }
  // death: your corpse (your own figure, lying where you fell), your ghost (a wisp, in the middle as you are), the
  // spirit healer and its graveyard's stones (where the page puts them), the light of coming back
  const corpse = holder(mover(nightElf()), 0.85);
  const corpseShadow = corpse.holder.children[1];
  const ghost = wispFigure();
  ghost.root.visible = false;
  you.add(ghost.root);
  const healer = spiritHealer();
  healer.root.visible = false;
  put(healer.root, nameplate(), 0, 3.3, 0).userData.write("Spirit Healer", "#3ce04a");
  world.add(healer.root);
  const graves = group();
  for (let i = 0; i < 6; i++) {
    const a = Math.PI * (0.35 + i * 0.26) + (rnd() - 0.5) * 0.2, r = 3.6 + rnd() * 1.6;
    put(graves, headstone(rnd), Math.cos(a) * r, 0, Math.sin(a) * r);
  }
  graves.visible = false;
  world.add(graves);
  const trail = motes(world), rising = motes(scene, 80), raycaster = new THREE.Raycaster(), cameraRay = new THREE.Raycaster(),
    cameraOrigin = new THREE.Vector3(), cameraDirection = new THREE.Vector3(), pointer = new THREE.Vector2();
  const plateV = new THREE.Vector3(), plateC = new THREE.Vector3(); // plateAt's
  let life = "alive", standUp = 0, trailAt = 0, selected = true; // selected: the target targeted (a cleared corpse: not)
  const sparks = bursts(scene), petSparks = bursts(world), fxSparks = bursts(world);
  // spells and blows: effects in the world, each played over its time, then gone
  const fxs = [], ballGeo = new THREE.SphereGeometry(1, 14, 10), beamGeo = new THREE.CylinderGeometry(1, 1, 1, 18, 1, true);
  const rise = (() => { // light fading upward: a resurrection's column
    const cv = document.createElement("canvas");
    cv.width = 2;
    cv.height = 128;
    const g = cv.getContext("2d"), grad = g.createLinearGradient(0, 0, 0, 128);
    grad.addColorStop(0, "rgba(255,255,255,0)");
    grad.addColorStop(0.55, "rgba(255,255,255,0.35)");
    grad.addColorStop(1, "rgba(255,255,255,1)");
    g.fillStyle = grad;
    g.fillRect(0, 0, 2, 128);
    return new THREE.CanvasTexture(cv);
  })();
  const slashGeo = new THREE.PlaneGeometry(1, 0.07), ringGeo = new THREE.RingGeometry(0.7, 1, 40);
  const additive = (color, opacity = 1) => new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false,
    blending: THREE.AdditiveBlending, side: THREE.DoubleSide });
  function play(obj, dur, tick, parent = world) {
    parent.add(obj);
    fxs.push({ obj, t: 0, dur, tick, parent });
  }
  // floating combat text: numbers rising over the target and over you
  const floats = Array.from({ length: 16 }, () => {
    const cv = document.createElement("canvas");
    cv.width = 256;
    cv.height = 64;
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace;
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: false }));
    sp.renderOrder = 11;
    sp.visible = false;
    return { sp, cv, tex, t: 0, base: new THREE.Vector3(), drift: 0, big: false };
  });
  let nextFloat = 0, shake = 0;
  let form = "", pet = "none", look = "none", activeNpc = null, targetHealth = 1, pop = 1, faceYaw = 0, lastFacing = null, clock = 0, camPull = 1, camFar = ZOOM.rest;
  let respawnAt = null; // a fight picked: where its mob stands (yards ahead), placed on the next frame
  let size = [1, 1], raised = 0; // the canvas; how far the picture is raised (device px) to keep you above the HUD
  const petAt = new THREE.Vector2(), petVel = new THREE.Vector2(), targetAt = new THREE.Vector2();

  const events = [];
  function showFloat({ who, text, color, big }) {
    const fl = floats[nextFloat++ % floats.length], g = fl.cv.getContext("2d");
    g.clearRect(0, 0, 256, 64);
    g.font = `bold ${big ? 52 : 44}px Georgia, "Times New Roman", serif`;
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.lineJoin = "round";
    g.lineWidth = 8;
    g.strokeStyle = "rgba(0,0,0,0.85)";
    g.strokeText(text, 128, 32);
    g.fillStyle = color;
    g.fillText(text, 128, 32);
    fl.tex.needsUpdate = true;
    fl.t = 0;
    fl.big = !!big;
    fl.drift = (Math.random() - 0.5) * 0.8;
    if (who === "you") { fl.base.set(-0.9, surfaceHeight(at.x, at.z) + 2.1, 0.2); scene.add(fl.sp); } // at your left: the target's over its own head
    else {
      if (look === "none") return;
      fl.base.set(targetAt.x, surfaceHeight(targetAt.x, targetAt.y) + KINDS[TARGETS[look].kind].label - 0.4, targetAt.y);
      world.add(fl.sp);
    }
    fl.sp.visible = true;
  }
  const camera = new THREE.PerspectiveCamera(52, 1.6, 0.1, 1500);
  const at = new THREE.Vector3();
  return {
    canvas: renderer.domElement,
    veil, // a ghost's colour over the world: the page lays it between the world's canvas and the HUD's
    zoom: ZOOM,
    resize(w, h) {
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      size = [w, h];
    },
    // Your target as the fight needs it: here (one is in the world), distance (yards), angle (radians off your
    // facing, + to the right)
    target() {
      if ((!activeNpc && look === "none") || !selected) return { here: false, distance: 99, angle: 0 };
      const target = activeNpc || { x: targetAt.x, z: targetAt.y };
      const dx = target.x - at.x, dz = target.z - at.z;
      v3.set(dx, 0, dz).applyAxisAngle(Y, -(lastFacing || 0));
      return { here: !activeNpc, distance: Math.hypot(dx, dz), angle: activeNpc ? 0 : Math.atan2(v3.x, -v3.z) };
    },
    // the next target stands this far ahead (a fight picked: it comes for you from there)
    respawn(distance) { respawnAt = distance; },
    // The nearby living units share one selection path for mouse clicks and Tab targeting.
    targetCandidates() {
      const candidates = ambient.filter(npc => npc.creature.holder.visible).map(npc => ({
        type: "npc", id: npc.id, name: npc.name, reaction: npc.reaction, kind: npc.kind, health: 1,
        distance: Math.hypot(npc.x - at.x, npc.z - at.z),
      }));
      if (look !== "none" && targetHealth > 0.001) candidates.push({
        type: "target", id: "target", name: TARGETS[look].name, reaction: look, kind: TARGETS[look].kind,
        health: targetHealth, distance: Math.hypot(targetAt.x - at.x, targetAt.y - at.z),
      });
      return candidates.filter(unit => unit.distance <= 60)
        .sort((a, b) => a.distance - b.distance || a.id.localeCompare(b.id));
    },
    // where the target's nameplate would be (over its head), as the last frame drew it: x, y in the picture (0 to 1
    // from its top left), ahead (in front of the camera), distance (yards), dead; null without a target
    plateAt(height) { // height: yards over the ground to project instead (the body: about 0.4)
      if (!activeNpc && look === "none") return null;
      const kind = activeNpc?.kind || TARGETS[look].kind, t = targets[kind], target = activeNpc || { x: targetAt.x, z: targetAt.y };
      plateV.set(target.x, surfaceHeight(target.x, target.z) + (height ?? KINDS[activeNpc?.kind || kind].label + 0.35), target.z).applyMatrix4(world.matrixWorld);
      plateC.copy(plateV).applyMatrix4(camera.matrixWorldInverse);
      plateV.project(camera);
      return { x: (plateV.x + 1) / 2, y: (1 - plateV.y) / 2, ahead: plateC.z < 0, distance: Math.hypot(target.x - at.x, target.z - at.z),
        dead: activeNpc ? false : (t.fall || 0) > 0.5 };
    },
    // what's under a point of the picture (x, y from -1 to 1, up +)
    pick(x, y) { // healer, selected target, or an ambient NPC
      raycaster.setFromCamera(pointer.set(x, y), camera);
      if (healer.root.visible && raycaster.intersectObject(healer.root, true).length) return "healer";
      for (const npc of ambient) {
        if (npc.creature.holder.visible && raycaster.intersectObject(npc.creature.rig.root, true).length) {
          return { type: "npc", id: npc.id, name: npc.name, reaction: npc.reaction, kind: npc.kind, health: 1 };
        }
      }
      const t = look !== "none" && targets[TARGETS[look].kind];
      if (t && t.holder.visible && raycaster.intersectObject(t.rig.root, true).length) return "target";
      return null;
    },
    // what the fight did, drawn: a spell's effect, a blow, a cast begun or ended, floating combat text
    event(kind, data = {}) { events.push([kind, data]); },
    // Where you can be: (north, west) moved out of anything solid, for a body the size of your form
    collide(north, west, formName) {
      const [x, z] = pushOut(-west, -north, (FORMS[formName] || FORMS.caster).radius);
      return [-z, -x];
    },
    // s: facing (radians, as GetPlayerFacing: from north toward west), north and west (yards), fwd and lat (yards
    // a second, + forward and right), air (in the air), jump (seconds since a jump began, -1: none), form, pet,
    // target (none, hostile, neutral, friendly, tapped) and thp (its health, 0-1), orbit and tilt (the camera:
    // the view turned right of your facing, tilted down past its rest; radians), zoom (its distance, yards), raise
    // (device px to lift the picture by: on a short screen, you stand above the HUD), selected (false: the target there but
    // not targeted, a cleared corpse: no ring, no name), plates (the target's name label
    // hidden: the page's nameplate card stands there), life (alive, dead: lying where
    // you fell, ghost: released, a wisp), healer ([north, west]: a graveyard's spirit healer, or none), dt
    render(s) {
      const dt = Math.min(0.1, s.dt);
      // the camera: orbiting you, tilted
      const orbit = s.orbit || 0, tilt = clamp(CAMERA_TILT + (s.tilt || 0), -0.4, 1.3);
      camFar = ease(camFar, clamp(s.zoom || ZOOM.rest, ZOOM.min, ZOOM.max), dt, 0.12); // the wheel's zoom, eased
      const camBack = Math.cos(tilt) * camFar, camUp = Math.sin(tilt) * camFar;
      // where you are: east is +x, north is -z; the world turned so you face -z and moved so you're at its middle
      at.set(-s.west, 0, -s.north);
      insideBuilding = inHouse(at.x, at.z);
      roof.visible = true;
      const playerGround = surfaceHeight(at.x, at.z);
      world.rotation.y = -s.facing;
      world.position.copy(at).negate().applyAxisAngle(Y, -s.facing);
      const landX = LAND_SPAN * Math.floor((at.x + LAND_SPAN / 2) / LAND_SPAN), landZ = LAND_SPAN * Math.floor((at.z + LAND_SPAN / 2) / LAND_SPAN);
      land.position.set(landX, 0, landZ);
      ground.material.map.offset.set(landX / 10, -landZ / 10);
      WATER.offset.y = (WATER.offset.y - dt * 0.012) % 1;
      far.position.set(at.x, 0, at.z);
      // the camera, as the game's, pulled in front of anything solid between it and you (at once), easing back out
      const pivotY = 1.5 + (s.jump >= 0 && s.jump < JUMP ? 4 * JUMP_H * (s.jump / JUMP) * (1 - s.jump / JUMP) : 0) * 0.5;
      const camX = -Math.sin(orbit) * camBack, camZ = Math.cos(orbit) * camBack, camY = 1.5 + camUp + (pivotY - 1.5);
      let clear = 1; // the share of the way to the camera that's clear
      for (const p of props) {
        const [bx, bz] = p.userData.base;
        const px = bx + TILE * Math.round((at.x - bx) / TILE), pz = bz + TILE * Math.round((at.z - bz) / TILE);
        p.position.set(px, groundHeight(px, pz), pz);
        if (!p.userData.block) continue;
        v3.copy(p.position).sub(at).applyAxisAngle(Y, -s.facing); // where it stands round you, as the camera's set
        // its solid part, a little wider (less than any of you is wide: you can't stand inside the margin)
        const R = p.userData.block + 0.2, A = camX * camX + camZ * camZ, B = -2 * (camX * v3.x + camZ * v3.z);
        const C = v3.x * v3.x + v3.z * v3.z - R * R, disc = B * B - 4 * A * C;
        if (C <= 0) { clear = 0; continue; }
        if (disc < 0) continue;
        const t = (-B - Math.sqrt(disc)) / (2 * A);
        if (t > 0 && t < clear && playerGround + pivotY + t * (camY - pivotY) < p.position.y + p.userData.height) clear = t;
      }
      // Pull the orbit camera in before the lodge's walls and permanent roof, just as it is
      // pulled in before trees and boulders. The doorway remains open to both walking and viewing.
      const cameraOffset = v3.set(camX, 0, camZ).applyAxisAngle(Y, s.facing);
      const rayX = cameraOffset.x, rayZ = cameraOffset.z;
      for (const [x0, x1, z0, z1] of houseWalls) {
        const minX = TEST_HOUSE.x + x0 - 0.28, maxX = TEST_HOUSE.x + x1 + 0.28;
        const minZ = TEST_HOUSE.z + z0 - 0.28, maxZ = TEST_HOUSE.z + z1 + 0.28;
        let enter = 0, leave = 1, blocked = true;
        for (const [origin, direction, min, max] of [[at.x, rayX, minX, maxX], [at.z, rayZ, minZ, maxZ]]) {
          if (Math.abs(direction) < 1e-6) { if (origin < min || origin > max) blocked = false; continue; }
          const a = (min - origin) / direction, b = (max - origin) / direction;
          enter = Math.max(enter, Math.min(a, b));
          leave = Math.min(leave, Math.max(a, b));
          if (enter > leave) blocked = false;
        }
        const hit = enter >= 0 ? enter : leave;
        if (blocked && hit > 0 && hit < clear && playerGround + pivotY + hit * (camY - pivotY) < interiorFloor + wallHeight) clear = hit;
      }
      world.updateMatrixWorld(true);
      cameraRay.set(cameraOrigin.set(0, playerGround + pivotY, 0), cameraDirection.set(camX, camY - pivotY, camZ).normalize());
      cameraRay.far = camFar * clear;
      const roofHit = cameraRay.intersectObject(roof, true)[0];
      if (roofHit) clear = Math.min(clear, roofHit.distance / camFar);
      clear = Math.max(clear, 0.3 / camFar); // at the closest, just behind your eyes (you faded: the game's first person)
      camPull = clear < camPull ? clear : ease(camPull, clear, dt, 0.35);
      const seen = clamp((camPull * camFar - 0.8) / 1.2, 0, 1); // fully seen from 2 yards out
      if (seen !== shown) {
        for (const m of fading) { // the dark edges go first: seen through a fading body they'd darken it
          m.transparent = seen < 1;
          m.opacity = seen;
          m.depthWrite = seen >= 1;
          if (m.userData.edge) m.visible = seen >= 1;
        }
        shown = seen;
      }
      you.visible = shadow.visible = seen > 0.02;
      shadow.position.set(0, playerGround + 0.025, 0);
      // the wisps drift
      clock += dt;
      for (const c of ambient) {
        const dx = c.targetX - c.x, dz = c.targetZ - c.z, distance = Math.hypot(dx, dz);
        c.think -= dt;
        if (c.think <= 0 || distance < 0.45) {
          c.think = 2 + rnd() * 3.5;
          c.targetX = c.homeX; c.targetZ = c.homeZ;
          if (rnd() < 0.72) {
            for (let attempt = 0; attempt < 12; attempt++) {
              const a = rnd() * TAU, d = rnd() * 6;
              const x = c.homeX + Math.cos(a) * d, z = c.homeZ + Math.sin(a) * d;
              if (!inHouse(x, z, 1) && riverDistance(x, z) > 9 && trailDistance(x, z) > 3) {
                c.targetX = x; c.targetZ = z; break;
              }
            }
          }
        }
        const d = Math.hypot(c.targetX - c.x, c.targetZ - c.z), speed = d > 0.4 ? Math.min(1.55, d * 1.3) : 0;
        const x0 = c.x, z0 = c.z;
        if (speed) [c.x, c.z] = pushOut(c.x + (c.targetX - c.x) / d * speed * dt,
          c.z + (c.targetZ - c.z) / d * speed * dt, c.kind === "nightsaber" ? 0.8 : 0.6);
        const moved = Math.hypot(c.x - x0, c.z - z0) / Math.max(dt, 1e-3), yaw0 = c.creature.yaw;
        if (moved > 0.1) {
          const yaw = Math.atan2(-(c.x - x0), -(c.z - z0));
          c.creature.yaw += turnOf(yaw - c.creature.yaw) * (1 - Math.exp(-dt / 0.28));
        }
        c.creature.holder.position.set(c.x, surfaceHeight(c.x, c.z), c.z);
        c.creature.rig.root.rotation.y = c.creature.yaw;
        step(c.creature, dt, { speed: moved, back: false, inAir: false, jump: -1,
          turn: turnOf(c.creature.yaw - yaw0) / Math.max(dt, 1e-3) });
        const isTarget = c.id === s.targetNpc && selected;
        c.creature.ring.visible = isTarget;
        c.creature.label.visible = isTarget && !s.plates;
      }
      activeNpc = ambient.find(c => c.id === s.targetNpc) || null;
      for (let i = 0; i < WISPS; i++) {
        const [bx, bz, by, ph] = wispBase[i];
        wispPos[i * 3] = bx + WISP_TILE * Math.round((at.x - bx) / WISP_TILE) + Math.sin(clock * 0.3 + ph) * 0.8;
        const wx = wispPos[i * 3], wz = bz + WISP_TILE * Math.round((at.z - bz) / WISP_TILE) + Math.cos(clock * 0.25 + ph) * 0.8;
        wispPos[i * 3 + 1] = groundHeight(wx, wz) + by + Math.sin(clock * 0.7 + ph * 2) * 0.35;
        wispPos[i * 3 + 2] = wz;
      }
      wispGeo.attributes.position.needsUpdate = true;
      for (let i = 0; i < TUFTS; i++) {
        const [bx, bz] = tuftBase[i];
        const tx = bx + TUFT_TILE * Math.round((at.x - bx) / TUFT_TILE), tz = bz + TUFT_TILE * Math.round((at.z - bz) / TUFT_TILE);
        v3.set(tx, groundHeight(tx, tz), tz);
        const inClearance = riverDistance(tx, tz) < 14 || trailDistance(tx, tz) < 3.8;
        tufts.setMatrixAt(i, m4.compose(v3, tuftTurn[i], sc.setScalar(inClearance ? 0 : tuftSize[i])));
      }
      tufts.instanceMatrix.needsUpdate = true;

      // dying, released, back: you fall where you stand (your own figure: a form falls away), lying there as you go
      // on a ghost; you rise where your ghost stands; the world goes grey for a ghost
      selected = s.selected !== false;
      const lifeNow = s.life === "dead" || s.life === "ghost" ? s.life : "alive";
      if (lifeNow !== life) {
        if (lifeNow === "dead") {
          corpse.holder.position.set(at.x, playerGround, at.z);
          corpse.rig.root.rotation.y = s.facing + faceYaw;
          corpse.fall = 0;
          corpse.holder.visible = true;
          if (form && form !== "caster") sparks.burst(0, playerGround + 0.4, 0, SHIFT, 18);
        } else if (lifeNow === "alive") {
          corpse.holder.visible = false;
          standUp = 1;
        }
        renderer.domElement.style.filter = lifeNow === "ghost" ? GHOST_SIGHT : "none";
        veil.style.opacity = lifeNow === "ghost" ? "0.92" : "0";
        life = lifeNow;
      }
      if (corpse.holder.visible) {
        step(corpse, dt, { speed: 0, back: false, inAir: false, jump: -1, turn: 0 });
        lieDown(corpse, dt, true);
        const yaw = corpse.rig.root.rotation.y; // the body falls toward its left: its shadow goes under it
        corpseShadow.position.set(-Math.cos(yaw) * 0.95 * corpse.fall, 0.02, Math.sin(yaw) * 0.95 * corpse.fall);
        corpseShadow.scale.setScalar(1 + 0.35 * corpse.fall);
      }

      // your form: a shapeshift swaps the figure in a burst of leaves, the new one popping up to its size
      const want = FORMS[s.form] ? s.form : "caster";
      if (want !== form) {
        if (form) {
          forms[form].rig.root.visible = false;
          forms[form].casting = false;
          forms[form].castK = 0;
          forms[form].act = null;
          forms[form].hit = null;
          forms[form].support = 0;
          sparks.burst(0, playerGround + 0.2, 0, SHIFT, 26);
          pop = 0;
        }
        form = want;
        forms[form].rig.root.visible = true;
      }
      pop = Math.min(1, pop + dt / 0.3);
      you.scale.setScalar(pop < 1 ? 0.35 + 0.65 * pop + Math.sin(pop * Math.PI) * 0.18 : 1);
      // the body faces the way you move (backing up: away from it); the camera stays behind your facing
      const speed = Math.hypot(s.fwd, s.lat), back = s.fwd < -0.1;
      const turnTo = speed < 0.1 ? 0 : back ? Math.atan2(s.lat, -s.fwd) : -Math.atan2(s.lat, Math.max(s.fwd, 0));
      const yaw0 = faceYaw;
      faceYaw = ease(faceYaw, turnTo, dt, 0.1);
      you.rotation.y = faceYaw;
      const turned = lastFacing === null ? 0 : turnOf(s.facing - lastFacing);
      lastFacing = s.facing;
      const active = forms[form];
      if (active.rig.druid && !active.rig.castGlow) {
        active.rig.castGlow = halo(0xa9e878, 0.48, 0.6);
        active.rig.arms[0].hand.add(active.rig.castGlow);
      }
      step(forms[form], dt, { speed, back, inAir: s.air, jump: s.jump, combat: !!s.fight?.aggro, turn: (turned + faceYaw - yaw0) / Math.max(dt, 1e-3) });
      if (active.rig.castGlow) {
        const charge = Math.max(active.castK, active.act?.kind === "release" ? 1 - active.act.t / active.act.dur : 0);
        active.rig.castGlow.visible = charge > 0.03;
        active.rig.castGlow.material.opacity = 0.65 * charge;
        active.rig.castGlow.scale.setScalar(0.35 + 0.3 * charge + 0.025 * Math.sin(clock * 12));
      }
      const lift = s.jump >= 0 && s.jump < JUMP ? 4 * JUMP_H * (s.jump / JUMP) * (1 - s.jump / JUMP) : 0;
      you.position.y = playerGround + lift;
      shadow.scale.setScalar(FORMS[form].shadow * (1 - Math.min(0.5, lift / JUMP_H * 0.5)));
      sparks.step(dt);
      forms[form].rig.root.visible = life === "alive";
      ghost.root.visible = life === "ghost";
      if (life !== "alive") shadow.visible = false;
      if (standUp > 0) { // back to life: getting up from the ground
        forms[form].fall = standUp;
        lieDown(forms[form], dt, false);
        standUp = forms[form].fall > 0.005 ? forms[form].fall : 0;
        if (!standUp) { forms[form].rig.root.rotation.z = 0; forms[form].rig.root.position.y = 0; }
      }
      if (life === "ghost") { // the wisp bobs, its motes circle it; it leaves a trail of light
        const bob = Math.sin(clock * 2.1) * 0.12;
        ghost.core.position.y = 1.35 + bob;
        ghost.motes.forEach((m, i) => {
          const a = clock * (1.6 + i * 0.35) + i * 1.05, r = 0.3 + 0.12 * Math.sin(clock * 1.3 + i);
          m.position.set(Math.cos(a) * r, Math.sin(clock * 2.4 + i * 2) * 0.18, Math.sin(a) * r);
        });
        trailAt -= dt;
        if (trailAt <= 0) {
          trailAt = speed > 0.5 ? 0.025 : 0.09;
          trail.emit(at.x, playerGround + 1.35 + bob, at.z, Math.random() < 0.5 ? 0xbff2ff : 0x8fd0ff, { rise: 0.25, life: 0.9, size: 0.28 });
        }
      }
      trail.step(dt);
      rising.step(dt);

      // your pet: it keeps its place at your left, a little behind (your speed, and the way back to its place),
      // going round what's solid, facing where it goes, then where you face
      const fx = -Math.sin(s.facing), fz = -Math.cos(s.facing); // your forward in the world; your right is (-fz, fx)
      const goX = at.x - fx * 0.6 + fz * 2.4, goZ = at.z - fz * 0.6 - fx * 2.4;
      const wantPet = PETS[s.pet] ? s.pet : "none";
      if (wantPet !== pet) {
        if (pet !== "none") pets[pet].holder.visible = false;
        pet = wantPet;
        if (pet !== "none") {
          pets[pet].holder.visible = true;
          petAt.set(...pushOut(goX, goZ, PETS[pet].radius));
          petVel.set(0, 0);
          pets[pet].yaw = s.facing;
          if (pet === "demon") petSparks.burst(petAt.x, 0.4, petAt.y, SUMMON, 24);
        }
      }
      petSparks.step(dt);
      if (pet !== "none") {
        const p = pets[pet], dx = goX - petAt.x, dz = goZ - petAt.y, dist = Math.hypot(dx, dz);
        if (dist > 40) petAt.set(...pushOut(goX, goZ, PETS[pet].radius)); // left far behind: there again
        const close = dist < 0.15 ? 0 : 4; // yards a second per yard off its place
        let wx = fx * s.fwd - fz * s.lat + dx * close, wz = fz * s.fwd + fx * s.lat + dz * close;
        const top = Math.max(PETS[pet].run * 1.6, speed * 1.3), want2 = Math.hypot(wx, wz);
        if (want2 > top) { wx *= top / want2; wz *= top / want2; }
        petVel.x = ease(petVel.x, wx, dt, 0.15);
        petVel.y = ease(petVel.y, wz, dt, 0.15);
        const x0 = petAt.x, z0 = petAt.y;
        petAt.set(...pushOut(petAt.x + petVel.x * dt, petAt.y + petVel.y * dt, PETS[pet].radius));
        const moved = Math.hypot(petAt.x - x0, petAt.y - z0) / Math.max(dt, 1e-3);
        const yawTo = moved > 0.6 ? Math.atan2(-(petAt.x - x0), -(petAt.y - z0)) : s.facing, yaw0p = p.yaw;
        p.yaw += turnOf(yawTo - p.yaw) * (1 - Math.exp(-dt / 0.12));
        p.holder.position.set(petAt.x, surfaceHeight(petAt.x, petAt.y), petAt.y);
        p.rig.root.rotation.y = p.yaw;
        step(p, dt, { speed: moved, back: false, inAir: false, jump: -1, turn: turnOf(p.yaw - yaw0p) / Math.max(dt, 1e-3) });
        p.holder.visible = life === "alive"; // gone while you're dead
      }

      // the graveyard where the page put it: its stones; its spirit healer for a ghost, floating, turning to you, its
      // arms lifting when it raises you
      const hw = Array.isArray(s.healer) ? s.healer : null;
      graves.visible = !!hw;
      healer.root.visible = !!hw && life === "ghost";
      if (hw) {
        const hx = -hw[1], hz = -hw[0], toYou = Math.atan2(-(at.x - hx), -(at.z - hz));
        const healerGround = surfaceHeight(hx, hz);
        graves.position.set(hx, healerGround, hz);
        healer.root.position.set(hx, healerGround, hz);
        healer.yaw = healer.yaw === undefined ? toYou : healer.yaw + turnOf(toYou - healer.yaw) * (1 - Math.exp(-dt / 0.8));
        healer.root.rotation.y = healer.yaw;
        healer.body.position.y = 0.35 + Math.sin(clock * 1.3) * 0.08;
        healer.raise = Math.max(0, healer.raise - dt);
        const up = healer.raise > 0 ? Math.min(1, (2.2 - healer.raise) / 0.4, healer.raise / 0.6) : 0;
        for (const a of healer.arms) { a.shoulder.rotation.z = a.side * (0.3 + 1.9 * up); a.shoulder.rotation.x = -0.25 - 0.35 * up; }
        for (const w of healer.wings) w.wing.rotation.z = w.side * (Math.sin(clock * 1.1) * 0.06 - 0.22 * up);
      }

      // your target: ahead of you when picked, its ring and name in its reaction's colour; it turns to face you
      // and lies down at 0 health
      const wantLook = activeNpc ? look : TARGETS[s.target] ? s.target : "none";
      if (wantLook !== look) {
        const was = TARGETS[look], next = TARGETS[wantLook];
        if (was && (!next || next.kind !== was.kind)) targets[was.kind].holder.visible = false;
        if (next) {
          const t = targets[next.kind];
          if (!was || was.kind !== next.kind || respawnAt !== null) { // placed ahead (9 yards), a little to your right
            const d = respawnAt ?? 9;
            targetAt.set(...pushOut(at.x + fx * d - fz * 1.5, at.z + fz * d + fx * 1.5, 0.6));
            t.yaw = Math.atan2(-(at.x - targetAt.x), -(at.z - targetAt.y));
            t.fall = 0;
            respawnAt = null;
          }
          t.holder.visible = true;
          t.ring.material.color.set(next.color);
          t.label.userData.write(next.name, next.color);
        }
        look = wantLook;
      }
      if (look !== "none" && respawnAt !== null) { // a new fight with the same kind of mob: placed again
        const t = targets[TARGETS[look].kind];
        targetAt.set(...pushOut(at.x + fx * respawnAt - fz * 1.5, at.z + fz * respawnAt + fx * 1.5, 0.6));
        t.yaw = Math.atan2(-(at.x - targetAt.x), -(at.z - targetAt.y));
        t.fall = 0;
        respawnAt = null;
      }
      let targetSpeed = 0;
      if (!activeNpc) targetHealth = s.thp;
      else if (s.fight?.kind === look || look === "tapped" && s.fight?.kind === "hostile") targetHealth = s.fight.health;
      if (look !== "none" && s.fight && s.fight.aggro && targetHealth > 0.001) { // it comes for you, to arm's length
        const dx = at.x - targetAt.x, dz = at.z - targetAt.y, d = Math.hypot(dx, dz), go = Math.min(Math.max(0, d - 2.3), 6.5 * dt);
        if (go > 0) {
          const x0 = targetAt.x, z0 = targetAt.y;
          targetAt.set(...pushOut(targetAt.x + dx / d * go, targetAt.y + dz / d * go, 0.6));
          targetSpeed = Math.hypot(targetAt.x - x0, targetAt.y - z0) / Math.max(dt, 1e-3);
        }
      }
      if (look !== "none") {
        const t = targets[TARGETS[look].kind], dead = targetHealth <= 0.001;
        if (dead) { t.act = null; t.hit = null; t.casting = false; }
        const toYou = Math.atan2(-(at.x - targetAt.x), -(at.z - targetAt.y)), yaw0t = t.yaw;
        if (!dead && Math.hypot(at.x - targetAt.x, at.z - targetAt.y) < 30) t.yaw += turnOf(toYou - t.yaw) * (1 - Math.exp(-dt / 0.5));
        t.holder.position.set(targetAt.x, surfaceHeight(targetAt.x, targetAt.y), targetAt.y);
        t.rig.root.rotation.y = t.yaw;
        step(t, dt, { speed: targetSpeed, back: false, inAir: false, jump: -1, combat: !!s.fight?.aggro, turn: turnOf(t.yaw - yaw0t) / Math.max(dt, 1e-3) });
        lieDown(t, dt, dead);
        t.label.position.y = KINDS[TARGETS[look].kind].label * (1 - t.fall * 0.6);
        t.label.visible = !activeNpc && !s.plates && s.selected !== false; // only the selected unit owns the target label
        t.ring.visible = !activeNpc && s.selected !== false;
      }

      // the fight's events: effects begun, actions played
      const me = forms[form], tgt = look !== "none" ? targets[TARGETS[look].kind] : null;
      const chest = (out, up = 0.5) => out.set(targetAt.x,
        surfaceHeight(targetAt.x, targetAt.y) + KINDS[TARGETS[look]?.kind || "furbolg"].label * up, targetAt.y);
      const castOrigin = out => { // the free palm, or the moonkin's raised wing
        const top = me.rig.druid ? me.rig.arms[0].hand : me.rig.staffTop;
        if (top && top.visible !== false) { top.getWorldPosition(out); return world.worldToLocal(out); }
        return out.set(at.x - fz * 0.32 + fx * 0.4, playerGround + 2.1 + lift, at.z + fx * 0.32 + fz * 0.4);
      };
      while (events.length) {
        const [kind, d] = events.shift();
        if (kind === "casting") { me.casting = !!d.id; me.castKind = d.id; }
        else if (kind === "windup") {
          const actor = d.who === "you" ? me : tgt;
          if (actor) act(actor, actor.rig.kind === "quad" || d.who === "you" ? "melee" : "swing");
        } else if (kind === "cancelWindup") {
          const actor = d.who === "you" ? me : tgt;
          if (actor?.act && ["swing", "melee"].includes(actor.act.kind)) actor.act = null;
        } else if (kind === "swing" && tgt) {
          const kind = tgt.rig.kind === "quad" ? "melee" : "swing", contact = kind === "melee" ? 0.31 : 0.43;
          if (tgt.act?.kind === kind) tgt.act.t = Math.max(tgt.act.t, contact);
          else act(tgt, kind, contact);
        } else if (kind === "melee") {
          if (me.act?.kind === "melee") me.act.t = Math.max(me.act.t, 0.31);
          else act(me, "melee", 0.31);
        }
        else if (kind === "targetHit" && tgt) act(tgt, "flinch");
        else if (kind === "hit") {
          act(me, "flinch");
          sparks.burst(0, playerGround + 0.8, 0, d.crushing ? [0xff5a3a, 0xffd0a0, 0xff2a1a] : [0xff5a3a, 0xffb080], d.crushing ? 22 : 8);
          if (d.crushing) shake = 0.3;
        } else if (kind === "text") showFloat(d);
        else if (kind === "resurrect") { // a column of light where you rise, motes going up with it; the healer's arms lift
          const column = new THREE.Mesh(beamGeo, additive(0xffe9b8, 0));
          column.material.map = rise;
          column.position.set(0, playerGround + 3.5, 0);
          column.scale.set(0.8, 7, 0.8);
          play(column, 1.8, u => {
            column.material.opacity = 0.55 * Math.sin(Math.min(1, u * 1.25) * Math.PI);
            column.scale.x = column.scale.z = 0.2 + 0.6 * Math.min(1, u * 3) - 0.3 * u;
          }, scene);
          const ring = new THREE.Mesh(ringGeo, additive(0xffe39a, 0.8));
          ring.rotation.x = -Math.PI / 2;
          ring.position.set(0, playerGround + 0.06, 0);
          play(ring, 1.1, u => { ring.scale.setScalar(0.4 + u * 2.8); ring.material.opacity = 0.8 * (1 - u); }, scene);
          for (let i = 0; i < 44; i++) {
            rising.emit((Math.random() - 0.5) * 1.3, playerGround + Math.random() * 1.6, (Math.random() - 0.5) * 1.3, [0xfff3c4, 0xffdf86, 0xffffff][i % 3],
              { rise: 1.7, life: 1.6, size: 0.26, spread: 0.2 });
          }
          if (d.at === "healer") healer.raise = 2.2;
        }
        else if ((kind === "wrath" || kind === "starfire") && tgt) { // a bolt flying to it
          act(me, "release");
          const from = new THREE.Vector3(), to = new THREE.Vector3(), gold = kind === "starfire";
          if (gold) chest(from, 0.5).add(new THREE.Vector3(1.5, 12, 0)); else castOrigin(from);
          const ball = new THREE.Mesh(ballGeo, additive(gold ? 0xffd36b : 0xc8ff6a));
          ball.scale.setScalar(gold ? 0.32 : 0.2);
          ball.add(halo(gold ? 0xffc040 : 0xa8ff40, gold ? 6 : 4, 0.8));
          play(ball, gold ? 0.45 : 0.32, u => {
            chest(to);
            ball.position.lerpVectors(from, to, u * u);
            if (u >= 1) fxSparks.burst(to.x, to.y - 0.6, to.z, gold ? [0xffd36b, 0xfff0b0, 0xff9a3a] : [0xc8ff6a, 0xf4ffb0, 0x7ad04a], gold ? 26 : 16);
          });
        } else if (kind === "moonfire" && tgt) { // a column of moonlight on it
          act(me, "release");
          const beam = new THREE.Mesh(beamGeo, additive(0xa8d8ff, 0.8));
          chest(beam.position, 0);
          beam.position.y = surfaceHeight(targetAt.x, targetAt.y) + 5;
          beam.scale.set(0.6, 10, 0.6);
          play(beam, 0.7, u => { beam.material.opacity = 0.8 * (1 - u); beam.scale.x = beam.scale.z = 0.6 * (1 - u * 0.6); });
          fxSparks.burst(targetAt.x, surfaceHeight(targetAt.x, targetAt.y) + 0.3, targetAt.y, [0xa8d8ff, 0xffffff, 0x7fb0ff], 14);
        } else if (kind === "heal" || kind === "rejuvenation" || kind === "enrage") { // round you: light, leaves, rage
          const colors = kind === "enrage" ? [0xff5a3a, 0xff9a4a, 0xffd0a0] : kind === "heal" ? [0x7dff8a, 0xe8ffd8, 0xb8ff9a] : [0x6cc84a, 0x9be86e, 0xd6ff9a];
          sparks.burst(0, playerGround + 0.3, 0, colors, kind === "heal" ? 26 : 18);
          const ring = new THREE.Mesh(ringGeo, additive(colors[0], 0.7));
          ring.rotation.x = -Math.PI / 2;
          ring.position.set(0, playerGround + 0.06, 0);
          play(ring, 0.6, u => { ring.scale.setScalar(0.8 + u * 1.6); ring.material.opacity = 0.7 * (1 - u); }, scene);
          if (kind === "heal" || kind === "rejuvenation") act(me, "release");
        } else if (["maul", "swipe", "claw", "rake", "bite"].includes(kind) && tgt) { // claw marks across it
          act(me, "melee", 0, kind);
          const red = kind === "rake" || kind === "bite", marks = new THREE.Group();
          chest(marks.position);
          for (let i = 0; i < 3; i++) {
            const m = new THREE.Mesh(slashGeo, additive(red ? 0xff5a4a : 0xfff0d8));
            m.position.set((i - 1) * 0.16, 0, 0);
            m.rotation.z = -0.9;
            marks.add(m);
          }
          play(marks, 0.28, u => {
            marks.lookAt(camera.position.clone().applyMatrix4(world.matrixWorld.clone().invert()));
            marks.scale.set(0.4 + u * 1.2, 1, 1);
            marks.children.forEach(m => { m.material.opacity = 1 - u; });
          });
          fxSparks.burst(targetAt.x, 0.6, targetAt.y, red ? [0xff4a3a, 0xffa080] : [0xfff0d8, 0xffd0a0], 10);
        }
      }
      for (let i = fxs.length - 1; i >= 0; i--) {
        const f = fxs[i];
        f.t += dt;
        const u = Math.min(1, f.t / f.dur);
        f.tick(u);
        if (u >= 1) {
          f.parent.remove(f.obj);
          f.obj.traverse(o => { if (o.material) o.material.dispose(); });
          fxs.splice(i, 1);
        }
      }
      fxSparks.step(dt);
      for (const fl of floats) { // floating text rises and fades
        if (!fl.sp.visible) continue;
        fl.t += dt;
        const u = fl.t / 1.3;
        if (u >= 1) { fl.sp.visible = false; fl.sp.parent.remove(fl.sp); continue; }
        fl.sp.position.set(fl.base.x + fl.drift * u, fl.base.y + 1.5 * (1 - (1 - u) * (1 - u)), fl.base.z);
        fl.sp.material.opacity = u < 0.65 ? 1 : (1 - u) / 0.35;
        const pop = fl.big && u < 0.15 ? 1 + (0.15 - u) * 4 : 1;
        fl.sp.scale.set((fl.big ? 2.4 : 1.6) * pop, (fl.big ? 0.6 : 0.4) * pop, 1);
      }
      // the camera behind and above you, as the game's: you a little under the middle, rising with a jump; never
      // under the ground; shaken a moment by a crushing blow
      shake = Math.max(0, shake - dt);
      const jolt = shake > 0 ? shake * 0.25 : 0;
      camera.position.set(camX * camPull + Math.sin(clock * 90) * jolt,
        playerGround + Math.max(0.4, pivotY + (camY - pivotY) * camPull) + Math.cos(clock * 73) * jolt, camZ * camPull);
      camera.lookAt(0, playerGround + pivotY, 0);
      const raise = Math.round(s.raise || 0); // the picture lifted: the projection's middle that far up
      if (raise !== raised) {
        raised = raise;
        if (raise > 0) camera.setViewOffset(size[0], size[1] + 2 * raise, 0, 2 * raise, size[0], size[1]);
        else camera.clearViewOffset();
      }
      renderer.render(scene, camera);
    },
    inside() { return insideBuilding; },
    interiorMapPosition() { return { x: at.x - TEST_HOUSE.x, z: at.z - TEST_HOUSE.z, span: INTERIOR_MAP_SPAN }; },
  };
}
