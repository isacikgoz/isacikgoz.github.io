// Cartoon figures and their physical poses, shared by the world and the model checks.
import * as THREE from "./vendor/three.module.min.js";

import { OUTLINE, glow, part, put, group, ball, capsule, cone, cylinder, leaf, ring, tilted, horn, bake } from "./sim_geometry.js";
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const ease = (current, target, dt, tau) => current + (target - current) * (1 - Math.exp(-dt / tau));

// ---------------------------------------------------------------- the figures
// A biped: root (at the feet) > body (bobs) > pelvis > legs (hip > knee), chest > arms (shoulder > elbow),
// neck > head. A quadruped: root > body > torso, legs, neck > head, tail. Each faces -z.
// A leg: its hip and knee pivots, thigh and shin lengths (a, b: the foot point is b under the knee), the foot
// point's height when planted (footH), the hip's height at rest (base), its joint (1: the knee bends forward,
// a person's or a front leg; -1: back, a hind leg's hock, a bird's) and its place in the stride (offset).
// A walker's gait: its stance share of the stride, walking to running (duty), its cadence range in strides a
// second (cad) and how high a running foot lifts (lift).
function biped() {
  const r = { kind: "biped", root: group(), body: group(), pelvis: group(), chest: group(), neck: group(), arms: [], legs: [] };
  r.root.add(r.body);
  r.body.add(r.pelvis);
  r.pelvis.add(r.chest);
  r.chest.add(r.neck);
  return r;
}
const STAND = 0.985;  // a standing leg's hip-to-foot share of its full length: knees all but straight
const CROUCH = 0.06; // a running body's lowering, of its hip's height (a runner's knees bend)
// the hip's height at rest for these leg lengths, foot point footH over the ground
const hipHeight = (a, b, footH) => footH + STAND * (a + b);
// the longest stride that keeps a planted foot in reach while running
function strideMax(leg) {
  const reach = STAND * (leg.a + leg.b), drop = leg.base * (1 - CROUCH) - leg.footH;
  return 2 * Math.sqrt(Math.max(0.01, reach * reach - drop * drop));
}
function walker(r, gait) {
  Object.assign(r, gait);
  r.strideMax = r.legs.length ? strideMax(r.legs[0]) : 1;
  return r;
}

// A female Night Elf: tall and slender, lavender skin, long ears swept up and back, glowing eyes, long brows,
// a ponytail. The druid (you, in caster form): a tunic and a skirt of leaves, a staff crowned with a crescent
// moon in her right hand. A Sentinel (a friendly target): dark violet armour, silver at the shoulders, white
// hair, a glaive.
const DRUID = { skin: 0xa891d8, hair: 0x3cb6a2, tunic: 0x3f6e3c, trim: 0x5b8c48, legging: 0x34503a, leather: 0x6a4a2c,
  boot: 0x4a3424 };
const STAFF_HOLD = -0.64 + 1.64 * 2 / 3; // grip two-thirds of the shaft up from its butt
const STAFF_PITCH = 15 * Math.PI / 180;
const SENTINEL = { skin: 0x9c86d0, hair: 0xe6e4f2, tunic: 0x3a2d5c, trim: 0x55468a, legging: 0x2c2440, leather: 0x4b3b2c,
  boot: 0x2f2638, metal: 0xc9d3e6 };
// Elliptical rings give the torso and face a continuous silhouette instead of stacked spheres.
function contour(profile, color, segments = 16) {
  const positions = [], indices = [];
  profile.forEach(([y, width, depth, z = 0]) => {
    for (let i = 0; i < segments; i++) {
      const a = i / segments * Math.PI * 2;
      positions.push(Math.cos(a) * width, y, z + Math.sin(a) * depth);
    }
  });
  for (let j = 0; j < profile.length - 1; j++) for (let i = 0; i < segments; i++) {
    const a = j * segments + i, b = j * segments + (i + 1) % segments, c = a + segments, d = b + segments;
    indices.push(a, c, b, b, c, d);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return part(geometry, color, 0.009);
}
function elfHand(side, skin, leather) {
  const hand = group();
  const palm = hand.palm = put(hand, group());
  put(palm, ball(0.043, skin, 0.92, 1.1, 0.8, 0.006), 0, 0, 0.026);
  const closed = hand.closed = put(hand, group());
  const fingers = hand.fingers = put(closed, group());
  put(fingers, capsule(0.012, 0.05, skin, 0.001), 0, -0.005, -0.024).rotation.z = Math.PI / 2;
  const thumb = hand.thumb = put(closed, group());
  put(thumb, capsule(0.011, 0.038, skin, 0.001), side * 0.032, 0.014, -0.018).rotation.set(0.22, 0, side * 1.05);
  const relaxed = hand.relaxed = put(hand, group());
  for (let i = 0; i < 4; i++) {
    const finger = put(relaxed, capsule(0.0085, 0.052 - Math.abs(i - 1.5) * 0.004, skin, 0.001), (i - 1.5) * 0.016, -0.043, -0.012);
    finger.rotation.set(0.22, 0, (i - 1.5) * 0.035);
  }
  hand.relaxedThumb = put(relaxed, capsule(0.01, 0.036, skin, 0.001), side * 0.033, -0.012, -0.008);
  hand.relaxedThumb.rotation.z = side * 0.72;
  const open = hand.open = put(hand, group());
  open.visible = false;
  relaxed.visible = false;
  for (let i = 0; i < 4; i++) {
    const finger = put(open, capsule(0.01, 0.053 - Math.abs(i - 1) * 0.009, skin, 0.001), (i - 1.5) * 0.019, -0.063, -0.018);
    finger.rotation.z = (i - 1.5) * 0.11;
  }
  put(open, capsule(0.01, 0.045, skin, 0.001), 0.04 * side, -0.016, -0.014).rotation.z = side * 0.75;
  return hand;
}
function nightElf(o = DRUID) {
  const LEAF = 0x658d53, EDGE = 0x91ad69, GOLD = 0xbca574, MOON = 0xd8e8ff, WOOD = 0x584332, armoured = !!o.metal;
  const r = biped(), base = hipHeight(0.55, 0.53, 0.065);
  r.druid = !armoured;
  r.pelvis.position.y = base + 0.04;
  r.legs = [-1, 1].map((side, i) => {
    const hip = put(r.pelvis, group(), 0.115 * side, -0.04, 0);
    put(hip, cylinder(0.086, 0.061, 0.49, o.legging), 0, -0.265, 0);
    put(hip, ball(0.063, o.legging, 1, 1, 1, 0.008), 0, -0.52, 0);
    const knee = put(hip, group(), 0, -0.55, 0);
    put(knee, cylinder(0.06, 0.047, 0.4, o.legging), 0, -0.22, 0);
    put(knee, cylinder(0.064, 0.055, 0.29, o.boot), 0, -0.34, 0);
    put(knee, ring(0.061, 0.008, GOLD, 0.004), 0, -0.215, 0).rotation.x = Math.PI / 2;
    put(knee, ball(0.064, o.boot, 0.95, 0.8, 1.8, 0.008), 0, -0.53, -0.04);
    return { hip, knee, a: 0.55, b: 0.53, footH: 0.065, base, joint: 1, offset: i * 0.5 };
  });
  put(r.pelvis, ball(0.16, o.legging, 1.15, 0.8, 0.86, 0.009), 0, -0.015, 0);
  put(r.pelvis, cylinder(0.18, 0.18, 0.095, o.leather), 0, 0.045, 0);
  put(r.pelvis, ball(0.035, GOLD, 1.3, 1, 0.4, 0.005), 0, 0.045, -0.18);
  r.petals = [];
  for (let i = 0; i < 8; i++) {
    const a = i * Math.PI / 4 + Math.PI / 8, x = Math.sin(a), z = Math.cos(a);
    const tilt = tilted(r.pelvis, x * 0.16, -0.005, z * 0.13, a, -0.14);
    put(tilt, ball(0.09, i % 2 ? o.trim : o.tunic, 1, 2.5, 0.25, 0.007), 0, -0.23, 0.02);
    put(tilt, leaf(0.13, GOLD), 0, -0.32, 0.045).rotation.z = Math.PI;
    r.petals.push({ tilt, leg: x > 0 ? 1 : 0, front: Math.max(0, -z), back: Math.max(0, z) });
  }
  r.chest.position.y = 0.06;
  put(r.chest, contour([[0, 0.13, 0.095], [0.12, 0.12, 0.085], [0.27, 0.165, 0.12],
    [0.4, 0.2, 0.13], [0.49, 0.18, 0.105], [0.56, 0.07, 0.065]], o.tunic));
  put(r.chest, contour([[0.025, 0.136, 0.1], [0.12, 0.126, 0.092], [0.22, 0.148, 0.112]], o.leather));
  for (const side of [-1, 1]) {
    const strap = put(r.chest, capsule(0.014, 0.34, GOLD), 0.11 * side, 0.33, -0.116);
    strap.rotation.z = side * 0.24;
  }
  put(r.chest, ball(0.045, GOLD, 0.85, 1, 0.4, 0.005), 0, 0.43, -0.137);
  put(r.chest, ball(0.026, glow(0x93bdc2), 0.75, 1, 0.4, 0), 0, 0.43, -0.154);
  r.arms = [-1, 1].map(side => {
    const shoulder = put(r.chest, group(), 0.245 * side, 0.48, 0);
    put(shoulder, ball(0.069, o.skin, 1, 1.05, 1, 0.008));
    put(shoulder, cylinder(0.058, 0.043, 0.28, o.skin), 0, -0.17, 0);
    // Fitted leather pauldrons and overlapping leaves follow the shoulder, rather than hiding it.
    put(shoulder, ball(0.09, armoured ? o.metal : o.leather, 1.23, 0.7, 1.2, 0.009), 0.015 * side, 0.005, 0);
    if (!armoured) for (let j = 0; j < 3; j++) {
      const pad = put(shoulder, ball(0.056, j === 1 ? EDGE : LEAF, 1, 1.75, 0.35, 0.005), 0.06 * side, -0.06, (j - 1) * 0.055);
      pad.rotation.set(0.18 * (j - 1), 0, side * 0.45);
    }
    const elbow = put(shoulder, group(), 0, -0.34, 0);
    put(elbow, ball(0.045, o.skin, 1, 1, 1, 0.006));
    put(elbow, cylinder(0.044, 0.033, 0.28, o.skin), 0, -0.15, 0);
    put(elbow, cylinder(0.05, 0.039, 0.16, armoured ? o.metal : o.leather), 0, -0.21, 0);
    for (const y of [-0.15, -0.255]) put(elbow, ring(y === -0.15 ? 0.048 : 0.04, 0.007, GOLD, 0.003), 0, y, 0).rotation.x = Math.PI / 2;
    const hand = put(elbow, elfHand(side, o.skin, o.leather), 0, -0.32, 0);
    return { shoulder, elbow, hand, a: 0.34, b: 0.32, side };
  });
  r.neck.position.set(0, 0.56, 0);
  put(r.neck, cylinder(0.045, 0.048, 0.105, o.skin), 0, 0.045, 0);
  const head = r.head = put(r.neck, group(), 0, 0.205, -0.005);
  put(head, contour([[-0.16, 0.025, 0.045, -0.015], [-0.115, 0.07, 0.075, -0.01],
    [-0.04, 0.103, 0.095], [0.04, 0.11, 0.103], [0.12, 0.09, 0.09], [0.16, 0.03, 0.04]], o.skin));
  const nose = new THREE.BufferGeometry();
  nose.setAttribute("position", new THREE.Float32BufferAttribute([0, 0.025, -0.098, -0.013, -0.05, -0.095,
    0.013, -0.05, -0.095, 0, -0.037, -0.13], 3));
  nose.setIndex([0, 1, 3, 0, 3, 2, 1, 2, 3]); nose.computeVertexNormals();
  put(head, part(nose, o.skin, 0));
  put(head, ball(0.019, 0x675078, 1.6, 0.18, 0.35, 0), 0, -0.09, -0.088);
  for (const side of [-1, 1]) {
    put(head, ball(0.019, glow(0xeaf6ff), 1.45, 0.5, 0.42, 0), 0.047 * side, 0.008, -0.098).rotation.z = side * 0.12;
    const marking = put(head, capsule(0.004, 0.038, 0x365e63), 0.073 * side, -0.032, -0.082);
    marking.rotation.z = side * 0.32;
    const brow = put(head, capsule(0.008, 0.06, o.hair), 0.052 * side, 0.046, -0.099);
    brow.rotation.z = side * 1.3;
    // Swept ears have an inner surface, and taper back instead of jutting straight sideways.
    const ear = put(head, group(), 0.099 * side, 0.012, 0.015);
    put(ear, ball(0.065, o.skin, 2.4, 0.42, 0.35, 0.005), 0.09 * side, 0.036, 0.035).rotation.z = side * 0.3;
    put(ear, ball(0.05, 0x826797, 2.2, 0.2, 0.25, 0), 0.09 * side, 0.038, 0.018).rotation.z = side * 0.3;
    put(head, capsule(0.027, 0.19, o.hair), 0.096 * side, -0.05, 0.04).rotation.z = side * 0.14;
  }
  put(head, contour([[0.065, 0.113, 0.11, 0.015], [0.12, 0.11, 0.1, 0.015],
    [0.17, 0.065, 0.065, 0.015], [0.18, 0.001, 0.001, 0.015]], o.hair));
  const fringe = put(head, ball(0.08, o.hair, 1.2, 0.5, 0.45, 0.006), -0.03, 0.095, -0.071);
  fringe.rotation.z = -0.28;
  put(head, horn(0.019, 0.005, Math.PI * 1.4, GOLD, 1, 0), 0, 0.055, -0.104).rotation.z = 0.3;
  const tie = put(head, group(), 0, 0.065, 0.105);
  put(tie, ring(0.038, 0.008, GOLD, 0.003)).rotation.x = Math.PI / 2;
  r.hair = [];
  let link = tie;
  for (let i = 0; i < 4; i++) {
    const seg = put(link, group());
    seg.userData.rest = i ? 0.12 : -0.28;
    put(seg, capsule(0.039 - i * 0.006, 0.11, o.hair), 0, -0.078, 0);
    r.hair.push(seg);
    link = put(seg, group(), 0, -0.15, 0);
  }
  // The weapon has its own pose in chest space. Hands reach its grips; the weapon never inherits a hand's scale.
  const staff = r.staff = put(r.druid ? r.chest : r.arms[1].hand, group());
  if (armoured) {
    put(staff, cylinder(0.022, 0.026, 1.8, 0x3e2f2a, 8), 0, 0.3, 0);
    put(staff, horn(0.2, 0.04, Math.PI * 0.85, o.metal, 1, 0.9), 0, 1.18, 0).rotation.z = Math.PI * 0.45;
  } else {
    put(staff, cylinder(0.018, 0.024, 1.64, WOOD, 10), 0, 0.18, 0);
    for (let i = 0; i < 12; i++) put(staff, cylinder(0.026, 0.026, 0.018, i % 2 ? o.leather : GOLD, 10, 0.003), 0, STAFF_HOLD - 0.26 + i * 0.033, 0);
    put(staff, cylinder(0.024, 0.025, 0.1, GOLD, 10, 0.004), 0, -0.61, 0);
    const moon = put(staff, horn(0.125, 0.023, Math.PI * 1.35, MOON, 1, 0.25), 0, 1.0, 0);
    moon.rotation.z = Math.PI * 0.32;
    r.staffTop = put(staff, ball(0.043, glow(0xc4ecff), 1, 1, 1, 0), 0, 1.13, 0);
    for (const side of [-1, 1]) put(tilted(staff, 0, 0.91, 0, side * 1.4, 0.8), leaf(0.12, LEAF), 0, 0.07, 0);
    for (const piece of staff.children) piece.position.y -= STAFF_HOLD;
  }
  return walker(r, { duty: [0.62, 0.3], cad: [1.0, 2.05], lift: 0.22 });
}

// Moonkin: a round owlbear in dusky feathers, antlers, wings for arms, short legs, a fan of tail feathers.
function moonkin() {
  const FEATHER = 0x6c5b80, DARK = 0x4a3d5c, CHEST = 0xe2d6bf, BONE = 0xe6dac0, BEAK = 0xf0b13c, EYE = 0xfff1a0;
  const r = biped();
  r.pelvis.position.y = 0.62;
  r.legs = [-1, 1].map((side, i) => {
    const hip = put(r.pelvis, group(), 0.32 * side, 0, 0);
    put(hip, ball(0.24, FEATHER, 1, 1.2, 1), 0, -0.18, 0);
    const knee = put(hip, group(), 0, -0.36, 0);
    put(knee, capsule(0.08, 0.18, BEAK), 0, -0.12, 0);
    for (let t = -1; t <= 1; t++) put(knee, cone(0.05, 0.22, BEAK, 6), t * 0.08, -0.3, -0.08).rotation.set(-Math.PI / 2, 0, t * 0.35);
    return { hip, knee, a: 0.36, b: 0.3, footH: 0.03, base: 0.62, joint: 1, offset: i * 0.5 };
  });
  r.chest.position.y = 0.05;
  put(r.chest, ball(0.78, FEATHER, 1, 1.05, 0.95), 0, 0.62, 0);
  put(r.chest, ball(0.6, CHEST, 0.95, 1, 0.55, 0), 0, 0.55, -0.46);
  for (let i = 0; i < 5; i++) {
    const f = put(r.chest, leaf(0.36, i % 2 ? DARK : FEATHER), (i - 2) * 0.22, 0.25 + Math.abs(i - 2) * 0.05, 0.7);
    f.rotation.set(Math.PI - 0.5, 0, (i - 2) * 0.2);
  }
  r.arms = [-1, 1].map(side => {
    const shoulder = put(r.chest, group(), 0.72 * side, 0.85, 0.05);
    put(shoulder, ball(0.24, DARK, 0.55, 1.6, 0.9), 0.04 * side, -0.32, 0).rotation.z = side * 0.12;
    for (let j = 0; j < 3; j++) put(shoulder, leaf(0.21, j % 2 ? FEATHER : DARK), 0.13 * side, -0.18 - j * 0.13, -0.07).rotation.z = side * 1.8;
    const elbow = put(shoulder, group(), 0.05 * side, -0.62, 0);
    for (let i = 0; i < 3; i++) put(elbow, leaf(0.34, i === 1 ? FEATHER : DARK), 0, -0.1, -0.12 + i * 0.12).rotation.set(Math.PI, 0, side * 0.1 * (i - 1));
    return { shoulder, elbow };
  });
  r.neck.position.set(0, 1.28, -0.05);
  const head = r.head = put(r.neck, group(), 0, 0.12, 0);
  put(head, ball(0.44, FEATHER, 1.05, 0.92, 1));
  put(head, ball(0.32, CHEST, 1.15, 0.95, 0.5, 0), 0, -0.02, -0.28);
  put(head, cone(0.08, 0.2, BEAK, 8), 0, -0.1, -0.45).rotation.x = -Math.PI / 2 - 0.5;
  for (const side of [-1, 1]) {
    put(head, ball(0.085, glow(EYE), 1, 1, 0.6, OUTLINE * 0.6), 0.15 * side, 0.06, -0.41);
    const beam = put(head, group(), 0.24 * side, 0.3, 0.05); // antlers: a beam out and up, two tines
    beam.rotation.z = -side * 0.6;
    put(beam, cylinder(0.035, 0.05, 0.5, BONE, 8), 0, 0.25, 0);
    const tine1 = put(beam, group(), 0, 0.3, 0);
    tine1.rotation.z = side * 0.9;
    put(tine1, cone(0.035, 0.28, BONE, 8), 0, 0.14, 0);
    const tine2 = put(beam, group(), 0, 0.5, 0);
    tine2.rotation.z = side * 0.25;
    put(tine2, cone(0.035, 0.3, BONE, 8), 0, 0.15, 0);
  }
  r.tail = put(r.pelvis, group(), 0, 0.1, 0.62);
  r.tailRest = 0;
  for (let i = -1; i <= 1; i++) put(r.tail, leaf(0.5, i ? DARK : FEATHER), i * 0.16, -0.1, 0.1).rotation.set(Math.PI + 1.0, 0, i * 0.35);
  return walker(r, { duty: [0.55, 0.22], cad: [1.4, 2.9], lift: 0.16 });
}

// A Gnarlpine furbolg (a hostile target): a hunched bear-man in grey-brown fur, red feathers at its belt, a club.
function furbolg() {
  const FUR = 0x6e5f55, DARK = 0x4a3e37, MUZZLE = 0xb49d84, LEATHER = 0x5e4129, WOOD = 0x6b4a2b, FEATHER = 0xc8483a,
    BONE = 0xe9e0c8;
  const r = biped(), base = hipHeight(0.44, 0.42, 0.06);
  r.pelvis.position.y = base + 0.04;
  r.legs = [-1, 1].map((side, i) => {
    const hip = put(r.pelvis, group(), 0.2 * side, -0.04, 0);
    put(hip, capsule(0.13, 0.26, FUR), 0, -0.22, 0);
    const knee = put(hip, group(), 0, -0.44, 0);
    put(knee, capsule(0.11, 0.24, FUR), 0, -0.2, 0);
    put(knee, ball(0.12, DARK, 1.1, 0.6, 1.4), 0, -0.42, -0.04);
    return { hip, knee, a: 0.44, b: 0.42, footH: 0.06, base, joint: 1, offset: i * 0.5 };
  });
  for (const z of [-1, 1]) put(r.pelvis, part(new THREE.BoxGeometry(0.36, 0.38, 0.04), LEATHER), 0, -0.16, z * 0.27);
  put(r.pelvis, ring(0.3, 0.04, LEATHER), 0, 0.06, 0).rotation.x = Math.PI / 2;
  for (let i = -1; i <= 1; i++) put(tilted(r.pelvis, i * 0.14, 0.02, -0.3, 0, Math.PI - 0.15), leaf(0.2, i ? FEATHER : BONE), 0, 0.1, 0);
  r.chest.position.y = 0.05;
  r.chestRest = 0.32;
  put(r.chest, ball(0.44, FUR, 1.1, 1, 0.95), 0, 0.38, 0);
  put(r.chest, ball(0.3, MUZZLE, 1, 0.9, 0.55, 0), 0, 0.36, -0.28);
  put(r.chest, ball(0.36, DARK, 1.15, 0.8, 1), 0, 0.62, 0.12);
  r.arms = [-1, 1].map(side => {
    const shoulder = put(r.chest, group(), 0.46 * side, 0.62, 0);
    put(shoulder, capsule(0.11, 0.24, FUR), 0, -0.2, 0);
    const elbow = put(shoulder, group(), 0, -0.38, 0);
    put(elbow, capsule(0.1, 0.22, FUR), 0, -0.16, 0);
    const hand = put(elbow, group(), 0, -0.34, 0);
    put(hand, ball(0.09, DARK, 1.05, 1, 0.8, 0.009), 0, 0, 0.025);
    for (let f = 0; f < 3; f++) put(hand, capsule(0.024, 0.055, DARK), (f - 1) * 0.047, -0.04, -0.055);
    return { shoulder, elbow, hand };
  });
  r.neck.position.set(0, 0.74, -0.2);
  const head = r.head = put(r.neck, group(), 0, 0.14, -0.06);
  put(head, ball(0.27, FUR, 1, 0.92, 1.05));
  put(head, ball(0.15, MUZZLE, 1, 0.8, 1.1), 0, -0.06, -0.24);
  put(head, ball(0.05, 0x120c08, 1.2, 0.9, 1, 0), 0, -0.03, -0.4);
  for (const side of [-1, 1]) {
    put(head, ball(0.08, FUR, 1, 1, 0.5), side * 0.19, 0.2, 0);
    put(head, ball(0.028, glow(0xff6a3d), 1, 1, 0.6, 0), side * 0.1, 0.05, -0.22);
  }
  const club = r.staff = put(r.arms[1].hand, group(), 0, 0.04, 0);
  put(club, cylinder(0.035, 0.045, 0.9, WOOD, 8), 0, 0.25, 0);
  put(club, ball(0.13, WOOD, 1, 1.5, 1), 0, 0.75, 0);
  for (let i = 0; i < 4; i++) put(tilted(club, 0, 0.8, 0, i * Math.PI / 2, 1.3), cone(0.025, 0.12, BONE, 6), 0, 0.15, 0);
  return walker(r, { duty: [0.6, 0.28], cad: [0.9, 2.2], lift: 0.18 });
}

// A quadruped from its proportions: bear, cat, travel form's cheetah, the hunter's wolf.
function quadruped(o) {
  const r = { kind: "quad", root: group(), body: group() };
  r.root.add(r.body);
  const L = o.legLength, g = o.girth, half = o.length / 2;
  r.restY = r.body.position.y = L;
  const torso = r.torso = put(r.body, group());
  put(torso, ball(g, o.fur, o.width, o.depth, half / g * 0.62), 0, g * 0.3, -half * 0.36); // the chest
  put(torso, ball(g * (o.haunch || 0.9), o.fur, o.width, o.depth, half / g * 0.6), 0, g * 0.22, half * 0.38); // the haunch
  if (o.hump) put(torso, ball(g * 0.7, o.hump, 1.15, 0.75, 1.2), 0, g * 0.85, -half * 0.3);
  if (o.belly) put(torso, ball(g * 0.8, o.belly, o.width * 0.85, 0.7, half / g * 0.8, 0), 0, -g * 0.2, 0);
  for (const [x, y, z, s] of o.spots || []) { // dark spots: caps of balls just under the coat
    const d = new THREE.Vector3(x, y, z).normalize(), sr = g * s;
    const n = new THREE.Vector3(d.x / (g * o.width), d.y / (g * o.depth), d.z / half).normalize(); // the coat's normal
    const at = new THREE.Vector3(d.x * g * o.width, g * 0.25 + d.y * g * o.depth, d.z * half).addScaledVector(n, -sr * 0.6);
    put(torso, ball(sr, o.spotColor || 0x2a1d12, 1, 1, 1, 0), at.x, at.y, at.z);
  }
  // legs (front left, front right, hind left, hind right): the hind pair pushes off, then the front pair
  const footH = o.legThick * 0.55, a = 0.51 * (L - footH) / STAND, b = 0.49 * (L - footH) / STAND;
  r.legs = [[-1, true, 0.55], [1, true, 0.65], [-1, false, 0], [1, false, 0.1]].map(([side, front, offset]) => {
    const hip = put(r.body, group(), side * g * o.width * 0.55, 0, (front ? -1 : 1) * o.length * 0.32);
    put(hip, capsule(o.legThick, a * 0.7, o.fur), 0, -a / 2, 0);
    const knee = put(hip, group(), 0, -a, 0);
    put(knee, capsule(o.legThick * 0.8, b * 0.7, o.fur), 0, -b / 2, 0);
    put(knee, ball(o.legThick * 1.15, o.paw || o.fur, 1, 0.6, 1.3), 0, -b, -o.legThick * 0.3);
    for (let toe = -1; toe <= 1; toe++) {
      put(knee, ball(o.legThick * 0.40, o.paw || o.fur, 0.8, 0.7, 1.4, 0.004), toe * o.legThick * 0.62, -b, -o.legThick * 1.03);
      put(knee, cone(o.legThick * 0.12, o.legThick * 0.65, 0xd0c5a3, 6), toe * o.legThick * 0.62, -b, -o.legThick * 1.45).rotation.x = -Math.PI / 2;
    }
    return { hip, knee, a, b, footH, base: L, joint: front ? 1 : -1, offset, front };
  });
  // neck and head: the head over the line of the back, so the camera behind you sees it and its ears
  const h = o.head;
  const neck = r.neck = put(r.body, group(), 0, g * 0.6, -half * 0.8);
  put(neck, capsule(h * 0.62, o.headUp * 0.8, o.fur), 0, o.headUp * 0.45, -h * 0.25).rotation.x = -0.5;
  const head = r.head = put(neck, group(), 0, o.headUp, -h * 0.55);
  put(head, ball(h, o.fur, 1, 0.92, 1.05));
  const [sw, sh, sl] = o.snout;
  put(head, ball(h * 0.6, o.muzzle || o.fur, sw, sh, sl), 0, -h * 0.25, -h * 0.85);
  put(head, ball(h * 0.16, 0x120c08, 1.3, 1, 1, 0), 0, -h * 0.15, -h * (0.85 + 0.6 * sl));
  for (const side of [-1, 1]) {
    put(head, ball(h * 0.12, o.eye ? glow(o.eye) : 0x120c08, 1, 1, 0.7, 0), h * 0.42 * side, h * 0.2, -h * 0.88);
    if (o.ears === "round") put(head, ball(h * 0.3, o.fur, 1, 1, 0.5), h * 0.62 * side, h * 0.72, 0);
    else {
      const ear = put(head, cone(h * 0.26, h * (o.ears === "tall" ? 0.8 : 0.55), o.fur, 6), h * 0.5 * side, h * 0.82, 0.05);
      ear.rotation.z = -side * 0.3;
      ear.scale.z = 0.5;
    }
  }
  const jaw = r.jaw = put(head, group(), 0, -h * 0.35, -h * 0.48);
  put(jaw, ball(h * 0.39, o.muzzle || o.fur, sw, 0.4, sl, 0.006), 0, -h * 0.15, -h * 0.43);
  for (const side of [-1, 1]) put(jaw, cone(h * 0.065, h * 0.27, 0xede6cf, 6), h * 0.28 * side, h * 0.04, -h * (0.44 + sl * 0.3));
  if (o.mane) put(head, ball(h * 1.1, o.mane, 1.15, 1, 0.8), 0, -h * 0.1, h * 0.45);
  // the tail
  const tail = r.tail = put(r.body, group(), 0, g * 0.45, half);
  const [tl, tr, tuft] = o.tail;
  r.tailLinks = [];
  let link = tail;
  const count = tl > 0.5 ? 4 : 1;
  for (let i = 0; i < count; i++) {
    const length = tl / count, radius = tr * (1 - i / count * 0.6);
    const joint = put(link, group(), 0, 0, i ? length : 0);
    put(joint, capsule(o.bushy ? radius * 1.15 : radius, length, o.fur), 0, 0, length / 2).rotation.x = Math.PI / 2;
    r.tailLinks.push(joint);
    link = joint;
  }
  if (tuft) put(link, ball(tr * 1.8, tuft, 1, 1, 1.6), 0, 0, tl / count + tr);
  r.tailRest = tail.rotation.x = o.tailDroop || 0.6;
  return walker(r, { duty: [0.55, o.duty || 0.25], cad: [1.2, 2.8], lift: o.lift || 0.16 });
}
const bear = () => quadruped({ fur: 0x4e3a2c, hump: 0x5e4535, muzzle: 0xa88a64, belly: 0x3f2e22, paw: 0x2f2219,
  legLength: 0.85, girth: 0.72, width: 1.12, depth: 1, length: 2.2, haunch: 0.84, legThick: 0.2, head: 0.42, headUp: 0.62,
  snout: [0.9, 0.75, 1.1], ears: "round", tail: [0.15, 0.08], duty: 0.28, lift: 0.2 });
const cat = () => quadruped({ fur: 0x54407c, muzzle: 0x7a64a8, belly: 0x6a5694, paw: 0x3b2d5a, eye: 0xf5d35a,
  legLength: 0.72, girth: 0.36, width: 1, depth: 1, length: 1.7, legThick: 0.1, head: 0.28, headUp: 0.42,
  snout: [0.85, 0.6, 0.8], ears: "point", tail: [1.1, 0.055], tailDroop: 0.55 });
const cheetah = () => quadruped({ fur: 0xd9a650, belly: 0xf2dfb0, muzzle: 0xf2dfb0, paw: 0xc9944a,
  legLength: 0.85, girth: 0.33, width: 0.95, depth: 1, length: 1.75, legThick: 0.085, head: 0.25, headUp: 0.48,
  snout: [0.8, 0.6, 0.7], ears: "point", tail: [1.0, 0.05, 0x2a1d12], tailDroop: 0.8, duty: 0.22,
  spots: [[0.5, 0.6, 0.3, 0.13], [-0.5, 0.65, 0.1, 0.12], [0.2, 0.9, -0.3, 0.12], [-0.3, 0.85, 0.5, 0.11], [0.75, 0.2, -0.5, 0.1],
    [-0.75, 0.25, -0.45, 0.11], [0.7, 0.3, 0.65, 0.1], [-0.7, 0.35, 0.7, 0.1], [0, 1, 0.2, 0.12], [0.45, 0.75, -0.75, 0.1]] });
const wolf = () => quadruped({ fur: 0x7a7c84, belly: 0xc9c6bf, muzzle: 0xb9b6ae, paw: 0x55575d,
  legLength: 0.62, girth: 0.33, width: 1, depth: 1.05, length: 1.45, legThick: 0.09, head: 0.25, headUp: 0.4,
  snout: [0.75, 0.6, 1.1], ears: "tall", tail: [0.75, 0.13], bushy: true, tailDroop: 1.35, mane: 0x6a6c74 });
// a nightsaber (a neutral target): a big silver cat with dark marks down its back, pale glowing eyes
const nightsaber = () => quadruped({ fur: 0xaeb4cf, muzzle: 0xe4e7f2, belly: 0xd9dcea, paw: 0x7f86a2, eye: 0x9fe8ff,
  legLength: 0.85, girth: 0.42, width: 1, depth: 1, length: 2.0, legThick: 0.11, head: 0.31, headUp: 0.46,
  snout: [0.85, 0.6, 0.8], ears: "point", tail: [1.2, 0.06], tailDroop: 0.6, spotColor: 0x4a4f6a,
  spots: [[0.3, 0.95, -0.6, 0.12], [-0.3, 0.95, -0.2, 0.12], [0.3, 0.95, 0.2, 0.12], [-0.3, 0.95, 0.6, 0.11],
    [0.75, 0.5, -0.3, 0.1], [-0.75, 0.5, 0.1, 0.1], [0.75, 0.5, 0.5, 0.1], [-0.75, 0.5, -0.6, 0.1]] });

// A voidwalker: floating, a broad dark violet chest, glowing eyes, huge arms in gold bands, a smoky tail.
function voidwalker() {
  const BODY = 0x3d3a8c, DEEP = 0x2a2766, LIGHT = 0x7d86e6, GOLD = 0xe2b24c;
  const r = biped();
  r.float = true;
  r.root.scale.setScalar(0.78);
  r.pelvis.position.y = 1.0;
  r.tail = put(r.pelvis, group(), 0, -0.05, 0);
  put(r.tail, ball(0.42, DEEP, 1, 0.7, 1), 0, -0.12, 0);
  put(r.tail, cone(0.36, 0.7, DEEP, 12), 0, -0.48, 0.06).rotation.x = Math.PI - 0.35;
  put(r.tail, ball(0.1, DEEP), 0, -0.84, 0.2);
  put(r.pelvis, ring(0.4, 0.06, GOLD), 0, 0.05, 0).rotation.x = Math.PI / 2;
  r.chest.position.y = 0.1;
  put(r.chest, ball(0.62, BODY, 1.2, 1.05, 0.85), 0, 0.55, 0);
  put(r.chest, ball(0.35, LIGHT, 1, 0.8, 0.5, 0), 0, 0.55, -0.38);
  r.arms = [-1, 1].map(side => {
    const shoulder = put(r.chest, group(), 0.74 * side, 0.85, 0);
    put(shoulder, ball(0.26, BODY));
    put(shoulder, capsule(0.16, 0.3, BODY), 0.05 * side, -0.3, 0);
    const elbow = put(shoulder, group(), 0.06 * side, -0.58, 0);
    put(elbow, capsule(0.2, 0.3, BODY), 0, -0.22, 0);
    put(elbow, cylinder(0.23, 0.23, 0.22, GOLD), 0, -0.2, 0);
    put(elbow, ball(0.22, DEEP), 0, -0.55, 0);
    return { shoulder, elbow };
  });
  r.neck.position.set(0, 1.12, -0.12);
  const head = r.head = put(r.neck, group(), 0, 0.1, 0);
  put(head, ball(0.26, BODY, 1, 1, 1.05));
  for (const side of [-1, 1]) put(head, ball(0.06, glow(0xe8f0ff), 1.3, 0.8, 0.6, 0), 0.1 * side, 0.03, -0.23);
  return r;
}

// ---------------------------------------------------------------- moving them
// A leg reaches for its foot point `fwd` ahead of its hip and `down` under it: the two bones' angles from the
// triangle they make (law of cosines), the knee forward or back by the leg's joint.
function reach(leg, fwd, down) {
  const { a, b } = leg, d = clamp(Math.hypot(fwd, down), 0.01, (a + b) * 0.999);
  const atHip = Math.acos(clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1));
  const atKnee = Math.acos(clamp((a * a + b * b - d * d) / (2 * a * b), -1, 1));
  leg.hip.rotation.x = Math.atan2(fwd, down) + leg.joint * atHip;
  leg.knee.rotation.x = -leg.joint * (Math.PI - atKnee);
}

// One mover: its figure and what eases between frames: speed, the stride's phase, the air, a landing, its
// turning, and two springs (fore and aft, side to side) that swing hair, tails and skirts after the body.
// Rigid decoration can share a draw call while shoulders, wrists, jaws and hair retain their pivots.
function batchFigure(rig) {
  if (rig.batched) return;
  const pivots = [];
  rig.root.traverse(node => { if (node.isGroup) pivots.push(node); });
  for (const pivot of pivots) {
    const meshes = pivot.children.filter(node => node.isMesh && node !== rig.staffTop);
    if (meshes.length < 2) continue;
    const rigid = group();
    for (const mesh of meshes) rigid.add(mesh);
    pivot.add(bake(rigid));
  }
  rig.batched = true;
}
function mover(rig) {
  batchFigure(rig);
  return { rig, phase: 0, v: 0, accel: 0, turn: 0, air: 0, airTime: 0, landT: 9, landK: 0, time: 0,
    yaw: 0, sway: { x: 0, vx: 0, z: 0, vz: 0 }, hairSway: { x: 0, vx: 0, z: 0, vz: 0 }, fall: 0, act: null, casting: false, castK: 0,
    combat: 0, support: 0, hit: null, attackSide: 0 };
}
// an action played over the pose: "swing" (a weapon brought down from overhead), "melee" (a forepaw's strike),
// "flinch" (struck), "release" (a spell let go)
const ACT_TIME = { swing: 0.86, melee: 0.62, flinch: 0.38, release: 0.48 };
function act(m, kind, phase = 0, style = "") {
  if (kind === "flinch") { m.hit = { t: 0 }; return; }
  if (kind === "melee" || kind === "swing") m.attackSide = 1 - m.attackSide;
  m.act = { kind, t: phase, dur: ACT_TIME[kind], style };
}
const smooth = u => u * u * (3 - 2 * u);
// Exact damped spring integration stays stable when a busy browser misses frames.
function spring(s, key, target, dt, hz = 1.8, damping = 0.55) {
  const w = 2 * Math.PI * hz, v = "v" + key, x = s[key] - target, velocity = s[v];
  const wd = w * Math.sqrt(1 - damping * damping), decay = Math.exp(-damping * w * dt);
  const c = Math.cos(wd * dt), sn = Math.sin(wd * dt), b = (velocity + damping * w * x) / wd;
  s[key] = target + decay * (x * c + b * sn);
  s[v] = decay * (velocity * c - (damping * w * b + wd * x) * sn);
}

// o: speed (yards a second along the ground), back (backing up), inAir, jump (seconds since a jump began, or
// -1), turn (radians a second, + left)
function step(m, dt, o) {
  const r = m.rig;
  m.time += dt;
  const v0 = m.v;
  m.v = ease(m.v, o.speed, dt, 0.1);
  m.accel = ease(m.accel, (m.v - v0) / Math.max(dt, 1e-3), dt, 0.15);
  m.turn = ease(m.turn, o.turn || 0, dt, 0.12);
  if (o.inAir) m.airTime += dt;
  else if (m.airTime > 0) { // landed: harder after a longer fall
    m.landK = clamp(0.35 + m.airTime * 0.5, 0, 1);
    m.landT = 0;
    m.airTime = 0;
  }
  m.landT += dt;
  m.air = ease(m.air, o.inAir ? 1 : 0, dt, 0.06);
  const dip = m.landT < 0.32 ? m.landK * (1 - m.landT / 0.32) ** 2 : 0;
  spring(m.sway, "x", clamp(-m.accel * 0.05, -0.6, 0.6), dt);
  spring(m.sway, "z", clamp(-m.turn * 0.12, -0.6, 0.6), dt);
  spring(m.hairSway, "x", m.sway.x, dt, 1.0, 0.72);
  spring(m.hairSway, "z", m.sway.z, dt, 1.0, 0.72);
  m.castK = ease(m.castK, m.casting ? 1 : 0, dt, m.casting ? 0.16 : 0.12);
  m.combat = ease(m.combat, o.combat ? 1 : 0, dt, 0.22);
  let hit = 0;
  if (m.hit) { m.hit.t += dt; hit = Math.sin(Math.PI * Math.min(1, m.hit.t / 0.38)) * Math.exp(-m.hit.t * 4); if (m.hit.t >= 0.38) m.hit = null; }
  let actU = -1;
  if (m.act) { m.act.t += dt; actU = m.act.t / m.act.dur; if (actU >= 1) { m.act = null; actU = -1; } }
  const doing = kind => actU >= 0 && m.act.kind === kind, pulse = actU >= 0 ? Math.sin(Math.PI * actU) : 0;
  const attack = { active: doing("melee") || doing("swing"), bite: m.act?.style === "bite", maul: m.act?.style === "maul", wind: 0, strike: 0, recoil: 0 };
  if (attack.active) for (const key of ["wind", "strike", "recoil"]) attack[key] = sample(actU, ATTACK[key]);
  const release = doing("release") ? Math.sin(Math.PI * actU) : 0;
  if (r.float) return float(m, dt, attack, hit);
  // the stride: its stance share, length and cadence for this speed (a planted foot moves at the ground's speed)
  const k = Math.min(1, m.v / 3);
  const D = r.duty[0] + (r.duty[1] - r.duty[0]) * Math.min(1, m.v / 6);
  const requiredCadence = m.v * D / r.strideMax;
  const f = Math.max(clamp(requiredCadence, r.cad[0], r.cad[1]), requiredCadence);
  const S = m.v * D / f;
  const shuffle = clamp((Math.abs(m.turn) - 0.4) / 1.5, 0, 1) * (1 - k); // turning on the spot: stepping round
  if (m.v > 0.05) m.phase += f * dt;
  else if (shuffle > 0) m.phase += 1.7 * dt;
  const dir = o.back ? -1 : 1, quad = r.kind === "quad", air = m.air;
  // the body bounces once a step (twice a stride on two legs, once a bound on four) and dips on landing
  const bob = quad ? 0.05 * k * Math.sin(2 * Math.PI * (m.phase - 0.15))
    : -0.045 * k * Math.cos(4 * Math.PI * (m.phase - D / 2));
  const drop = bob - 0.035 * m.combat * (1 - k) - 0.04 * attack.wind - CROUCH * r.legs[0].base * k - dip * 0.22 * r.legs[0].base + (1 - k) * Math.sin(m.time * 2.2) * 0.008;
  r.body.position.y = (quad ? r.restY : 0) + drop;
  r.legs.forEach((leg, i) => {
    const q = (m.phase + leg.offset) % 1;
    let fwd, lift;
    if (q < D) { fwd = S / 2 - S * q / D; lift = 0; } // planted
    else { // swinging forward to its next step
      const t = (q - D) / (1 - D);
      fwd = -S / 2 + S * (0.5 - 0.5 * Math.cos(Math.PI * t));
      lift = r.lift * Math.min(1, m.v / 2.5) * Math.sin(Math.PI * t);
    }
    fwd *= dir;
    lift += 0.07 * leg.base * shuffle * Math.max(0, Math.sin(2 * Math.PI * q));
    let down = leg.base + drop - leg.footH - lift;
    if (air > 0) { // in the air: tucked in a jump, hanging in a fall
      const reachAll = leg.a + leg.b;
      let af, ad;
      if (quad) { af = (leg.front ? 0.12 : -0.12) * reachAll; ad = 0.62 * reachAll; }
      else if (o.jump >= 0 && o.jump < 0.08) { af = -0.12 * reachAll; ad = 0.99 * reachAll; } // pushing off
      else if (o.jump >= 0) { af = (i ? -0.15 : 0.22) * reachAll; ad = (i ? 0.74 : 0.6) * reachAll; }
      else { af = (i ? -0.06 : 0.06) * reachAll + Math.sin(m.time * 9 + i * 2) * 0.05 * Math.min(1, m.airTime); ad = 0.88 * reachAll; }
      fwd += (af - fwd) * air;
      down += (ad - down) * air;
    }
    if (!quad) fwd += (i ? -1 : 1) * 0.09 * m.combat * (1 - k);
    reach(leg, fwd, down);
  });
  const sw = Math.cos(2 * Math.PI * m.phase); // 1: the left foot ahead
  if (quad) {
    r.torso.rotation.x = 0.08 * k * Math.sin(2 * Math.PI * (m.phase - 0.1)) - dip * 0.1
      + 0.10 * attack.wind - 0.20 * attack.strike + 0.12 * hit;
    r.body.position.z = 0.09 * attack.wind - 0.16 * attack.strike + 0.08 * hit;
    r.body.position.y -= 0.06 * attack.wind;
    for (const leg of r.legs) leg.hip.rotation.z = 0;
    if (attack.active && !attack.bite) for (const index of attack.maul ? [0, 1] : [m.attackSide]) {
      const paw = r.legs[index];
      reach(paw, (paw.a + paw.b) * (0.22 * attack.wind + 0.65 * attack.strike),
        paw.base + drop - paw.footH - paw.base * (0.28 * attack.wind + 0.18 * attack.strike));
      paw.hip.rotation.z = (index ? 1 : -1) * 0.20 * attack.strike;
    }
    r.neck.rotation.x = -0.10 * k * Math.sin(2 * Math.PI * m.phase) - dip * 0.15
      + 0.12 * attack.wind - 0.30 * attack.strike;
    r.head.rotation.y = clamp(m.turn * 0.15, -0.4, 0.4) + (1 - k) * Math.sin(m.time * 0.5) * 0.08;
    if (r.jaw) r.jaw.rotation.x = (attack.bite ? 0.65 : 0.24) * attack.wind + 0.15 * attack.strike;
    r.body.rotation.z = clamp(m.turn * 0.01 * k, -0.025, 0.025) + (m.attackSide ? -1 : 1) * 0.05 * attack.strike;
  } else {
    // the upper body: leaning a little into speed and into a start, twisting against the hips, barely banking
    // (a lean forward turns the top toward -z, the way it faces: a negative turn round x)
    const lean = (o.back ? -0.04 : 0.08) * k + clamp(m.accel * 0.015, -0.06, 0.08) + dip * 0.25;
    const hunch = (r.chestRest || 0) + lean;
    r.pelvis.rotation.set(-lean * 0.3, -0.1 * k * sw, 0);
    r.chest.rotation.set(-hunch, 0.18 * k * sw, 0);
    r.body.rotation.z = clamp(m.turn * 0.01 * k, -0.025, 0.025); // banking: a degree or so
    r.neck.rotation.x = hunch * 0.6; // the head held up
    if (r.head) r.head.rotation.y = clamp(m.turn * 0.12, -0.45, 0.45) - 0.08 * k * sw;
    r.arms.forEach((arm, i) => {
      arm.shoulder.rotation.set(0, 0, 0);
      arm.elbow.rotation.set(0, 0, 0);
      const hold = r.staff && i === 1 ? 0.4 : 1; // the hand on the staff swings less
      arm.shoulder.rotation.x = Math.cos(2 * Math.PI * (m.phase + (i ? 0 : 0.5))) * 0.7 * k * hold * dir
        + air * (o.jump >= 0 ? 0.5 : 0.2) + dip * 0.5;
      arm.shoulder.rotation.z = (i ? 1 : -1) * (0.08 + 0.45 * air + 0.15 * dip);
      arm.elbow.rotation.x = 0.25 + 1.0 * k + 0.4 * air;
      if (m.castK > 0.01) { // casting: both hands raised toward the target
        arm.shoulder.rotation.x += (1.15 - arm.shoulder.rotation.x) * m.castK;
        arm.elbow.rotation.x += (0.45 - arm.elbow.rotation.x) * m.castK;
      }
      if (doing("release")) arm.shoulder.rotation.x += 0.45 * pulse;
    });
    if (!r.druid) {
      r.chest.rotation.y += 0.26 * attack.wind - 0.46 * attack.strike;
      r.chest.rotation.x += 0.10 * attack.wind - 0.25 * attack.strike;
      r.body.position.z = 0.07 * attack.wind - 0.15 * attack.strike + 0.07 * hit;
      if (attack.active && r.arms[1]) {
        r.arms[1].shoulder.rotation.x += -1.8 * attack.wind + 1.35 * attack.strike;
        r.arms[1].elbow.rotation.x += 0.75 * attack.wind - 0.25 * attack.strike;
        r.arms[1].shoulder.rotation.z += 0.25 * attack.wind;
      }
    }
    r.chest.rotation.x += 0.18 * hit;
    if (r.druid) poseDruid(m, k, air, dip, attack, release, hit, dt);
    else if (r.staff) { // its angle kept through the arm's swing and the body's lean, tipped a little forward running
      const a = r.arms[1], pitch = a.shoulder.rotation.x + a.elbow.rotation.x + r.chest.rotation.x + r.pelvis.rotation.x;
      r.staff.rotation.x = -0.08 * k + 0.2 * attack.wind - 1.4 * attack.strike - pitch;
    }
    for (const p of r.petals || []) { // the skirt: pushed out by the thigh before it, swinging after the body
      const hipX = r.legs[p.leg].hip.rotation.x;
      p.tilt.rotation.x = (r.druid ? -0.14 : -0.3) - p.front * Math.max(0, hipX) * 0.8 - p.back * Math.max(0, -hipX) * 0.5 + m.sway.x * 0.3 * p.back;
    }
    (r.hair || []).forEach((seg, i) => { // a ponytail streams back with speed, swings with every push and turn
      seg.rotation.x = seg.userData.rest - (i ? 0.04 : 0.2) * k + m.hairSway.x * (i ? 0.16 : 0.34) - bob * 1.4;
      seg.rotation.z = m.hairSway.z * (i ? 0.18 : 0.36);
    });
  }
  if (r.tail) {
    const wag = Math.sin(m.time * (quad ? 5 : 3)) * (0.12 + 0.18 * (1 - k));
    r.tail.rotation.x = r.tailRest - 0.35 * k + m.sway.x * 0.5;
    r.tail.rotation.y = wag + m.sway.z;
    (r.tailLinks || []).forEach((joint, i) => {
      joint.rotation.y = Math.sin(m.time * (quad ? 4.5 : 3) - i * 0.6) * (0.08 + 0.08 * k) + m.sway.z * 0.18;
      joint.rotation.x = 0.04 * Math.sin(m.time * 3 - i * 0.7) + 0.05 * attack.recoil;
    });
  }
}
// Solve both bones in chest space with an explicit elbow direction. Euler angle guesses used to put
// the supporting elbow inside the ribs. The pole points out from the body in every weapon pose.
const DOWN = new THREE.Vector3(0, -1, 0), ARM_UP = new THREE.Vector3(), ARM_FORE = new THREE.Vector3();
const ARM_DIR = new THREE.Vector3(), ARM_BEND = new THREE.Vector3(), ARM_JOINT = new THREE.Vector3();
const ARM_Q = new THREE.Quaternion(), ARM_PARENT = new THREE.Quaternion();
function solveArm(arm, target, pole, handRotation) {
  const origin = arm.shoulder.position;
  ARM_DIR.subVectors(target, origin);
  const distance = Math.max(0.001, ARM_DIR.length()), length = clamp(distance, 0.04, arm.a + arm.b - 0.0005);
  ARM_DIR.divideScalar(distance);
  ARM_BEND.subVectors(pole, origin).addScaledVector(ARM_DIR, -ARM_BEND.dot(ARM_DIR)).normalize();
  const along = (arm.a * arm.a + length * length - arm.b * arm.b) / (2 * length);
  const out = Math.sqrt(Math.max(0, arm.a * arm.a - along * along));
  ARM_JOINT.copy(origin).addScaledVector(ARM_DIR, along).addScaledVector(ARM_BEND, out);
  ARM_UP.subVectors(ARM_JOINT, origin).normalize();
  ARM_FORE.copy(origin).addScaledVector(ARM_DIR, length).sub(ARM_JOINT).normalize();
  arm.shoulder.quaternion.setFromUnitVectors(DOWN, ARM_UP);
  ARM_Q.setFromUnitVectors(DOWN, ARM_FORE);
  ARM_PARENT.copy(arm.shoulder.quaternion).invert();
  arm.elbow.quaternion.copy(ARM_PARENT).multiply(ARM_Q);
  arm.hand.quaternion.copy(ARM_Q).invert().multiply(handRotation);
  // Retained for the numerical joint checks, without allocating objects every frame.
  (arm.target ||= new THREE.Vector3()).copy(target);
  (arm.joint ||= new THREE.Vector3()).copy(ARM_JOINT);
}
const STAFF_CARRY = new THREE.Vector3(0.265, -0.1691, -0.115), STAFF_READY = new THREE.Vector3(0.04, 0.02, -0.29);
const STAFF_AXIS = new THREE.Vector3(0, 1, 0), RUN_YAW = 80 * Math.PI / 180;
const STAFF_CARRY_ROT = new THREE.Quaternion().setFromUnitVectors(STAFF_AXIS,
  new THREE.Vector3(0, Math.sin(STAFF_PITCH), -Math.cos(STAFF_PITCH)));
// Equal sideways and upward components make the rear projection a 45-degree diagonal.
const STAFF_RUN_ROT = new THREE.Quaternion().setFromUnitVectors(STAFF_AXIS,
  new THREE.Vector3(-Math.sin(RUN_YAW), Math.sin(RUN_YAW), -Math.cos(RUN_YAW)).normalize());
const LEFT_REST = new THREE.Vector3(-0.26, -0.1766, -0.06), LEFT_CAST = new THREE.Vector3(-0.32, 0.39, -0.46);
const RIGHT_CAST = new THREE.Vector3(0.28, 0.35, -0.43);
const RIGHT_POLE = new THREE.Vector3(0.42, 0.07, -0.14), LEFT_POLE = new THREE.Vector3(-0.33, 0.045, -0.08);
const RIGHT_HAND_ROT = new THREE.Quaternion();
const STAFF_PARENT_ROT = new THREE.Quaternion();
const STAFF_TURN = new THREE.Quaternion(), STAFF_TURN_EULER = new THREE.Euler();
const HAND_AT = new THREE.Vector3(), HAND_ROT = new THREE.Quaternion(), HAND_EULER = new THREE.Euler();
const ATTACK = { wind: [[0,0],[0.32,1],[0.5,0],[1,0]], strike: [[0,0],[0.32,0],[0.5,1],[1,0]],
  recoil: [[0,0],[0.5,0],[0.66,1],[1,0]] };
function sample(u, keys) {
  for (let i = 1; i < keys.length; i++) if (u <= keys[i][0]) {
    const [a, x] = keys[i - 1], [b, y] = keys[i];
    return x + (y - x) * smooth(clamp((u - a) / (b - a), 0, 1));
  }
  return keys[keys.length - 1][1];
}
function poseDruid(m, k, air, dip, attack, release, hit, dt) {
  const r = m.rig, cast = m.castK, ready = m.combat * (1 - cast);
  const castingPose = m.casting || cast > 0.03 || m.act?.kind === "release";
  const spell = castingPose ? Math.max(cast, release) : 0;
  const carrying = m.v > 0.15 || attack.active;
  m.support = ease(m.support, carrying && !m.casting ? 1 : 0, dt, carrying ? 0.055 : 0.16);
  const support = m.support * (1 - spell);
  r.staff.visible = !castingPose;
  // Breathing and the legs lead. The chest follows the hips and the staff has a small inertial lag.
  r.chest.rotation.y += 0.12 * ready + 0.30 * attack.wind - 0.48 * attack.strike;
  r.chest.rotation.x += 0.08 * attack.wind - 0.17 * attack.strike + 0.12 * hit;
  r.body.position.z = 0.06 * attack.wind - 0.11 * attack.strike + 0.045 * hit;
  r.staff.position.copy(STAFF_CARRY).lerp(STAFF_READY, support);
  // Bring the shaft in front of the tunic before moving the grip across the waist.
  r.staff.position.z = STAFF_CARRY.z + (STAFF_READY.z - STAFF_CARRY.z) * smooth(Math.min(1, support * 3));
  r.staff.position.y += 0.025 * Math.sin(m.phase * Math.PI * 2) * k + 0.055 * air;
  r.staff.position.y += 0.13 * (attack.wind + attack.strike);
  r.staff.position.z -= 0.05 * attack.strike;
  r.staff.quaternion.copy(STAFF_CARRY_ROT).slerp(STAFF_RUN_ROT, support);
  STAFF_TURN_EULER.set(0.12 * attack.wind - 0.2 * attack.strike,
    -0.15 * attack.wind - 0.5 * attack.strike, 0.5 * attack.wind - 0.5 * attack.strike);
  STAFF_TURN.setFromEuler(STAFF_TURN_EULER);
  r.staff.quaternion.premultiply(STAFF_TURN);
  // The two carry angles are relative to the character's facing, independent of torso lean and twist.
  STAFF_PARENT_ROT.copy(r.body.quaternion).multiply(r.pelvis.quaternion).multiply(r.chest.quaternion).invert();
  r.staff.quaternion.premultiply(STAFF_PARENT_ROT);
  r.staff.position.applyQuaternion(STAFF_PARENT_ROT);
  const rightReach = r.arms[1].a + r.arms[1].b - 0.0005;
  const gripDistance = ARM_DIR.subVectors(r.staff.position, r.arms[1].shoulder.position).length();
  if (gripDistance > rightReach) r.staff.position.addScaledVector(ARM_DIR, (rightReach - gripDistance) / gripDistance);
  if (support > 0.001) {
    ARM_UP.set(0, 0.20, 0).applyQuaternion(r.staff.quaternion).add(r.staff.position);
    if (ARM_UP.x > -0.23) r.staff.position.z -= Math.max(0, ARM_UP.z + 0.27);
  }
  // Idle: forward with a 15-degree rise. Running: an 80-degree cross-body turn and a 45-degree rear diagonal.
  HAND_AT.copy(r.staff.position).lerp(RIGHT_CAST, spell);
  HAND_EULER.set(-1.4 - 0.3 * release, 0, 0.12);
  HAND_ROT.setFromEuler(HAND_EULER);
  RIGHT_HAND_ROT.copy(r.staff.quaternion).slerp(HAND_ROT, spell);
  solveArm(r.arms[1], HAND_AT, RIGHT_POLE, RIGHT_HAND_ROT);
  r.arms[1].hand.open.visible = spell > 0.15;
  r.arms[1].hand.closed.visible = !r.arms[1].hand.open.visible;
  r.arms[1].hand.relaxed.visible = false;
  const left = r.arms[0];
  HAND_AT.copy(LEFT_REST);
  HAND_AT.z -= Math.sin(m.phase * Math.PI * 2) * 0.12 * k;
  HAND_AT.y += 0.03 * k + 0.11 * air;
  HAND_AT.lerp(LEFT_CAST, Math.max(cast, release * 0.9));
  HAND_AT.x -= ready * 0.015;
  HAND_AT.z -= ready * 0.055;
  // Gather a spell toward the palm, then extend it on release, instead of waving both arms overhead.
  HAND_AT.x -= Math.sin(m.time * 3.6) * 0.025 * cast;
  HAND_AT.y += Math.cos(m.time * 3.6) * 0.025 * cast;
  HAND_AT.z -= 0.12 * release;
  HAND_EULER.set(-0.25 - 1.3 * cast - 0.45 * release, 0, -0.12);
  HAND_ROT.setFromEuler(HAND_EULER);
  if (support > 0.001) {
    ARM_UP.set(0, 0.20, 0).applyQuaternion(r.staff.quaternion).add(r.staff.position);
    HAND_AT.lerp(ARM_UP, support);
    HAND_ROT.slerp(r.staff.quaternion, support);
  }
  // Crossing the centre line is only allowed in front of the tunic, never through it.
  const reaching = support > 0.001 ? smooth(clamp((HAND_AT.x + 0.30) / 0.10, 0, 1)) : 0;
  HAND_AT.y = Math.max(HAND_AT.y, LEFT_REST.y + 0.065 * reaching);
  if (HAND_AT.x > -0.23) HAND_AT.z = Math.min(HAND_AT.z, -0.25);
  if (support < 0.001) {
    ARM_DIR.subVectors(HAND_AT, left.shoulder.position);
    const reach = left.a + left.b - 0.0005;
    if (ARM_DIR.length() > reach) HAND_AT.copy(left.shoulder.position).addScaledVector(ARM_DIR, reach / ARM_DIR.length());
  }
  solveArm(left, HAND_AT, LEFT_POLE, HAND_ROT);
  left.hand.open.visible = cast + release > 0.15 && support < 0.25;
  left.hand.relaxed.visible = !left.hand.open.visible && support < 0.25;
  left.hand.closed.visible = !left.hand.open.visible && !left.hand.relaxed.visible;
  r.neck.rotation.x -= 0.08 * cast;
}

// a voidwalker hovers: a slow bob, leaning into the way it goes, its tail streaming back
function float(m, dt, attack, hit) {
  const r = m.rig, lean = Math.min(1, m.v / 5) * 1;
  r.body.position.y = 0.45 + Math.sin(m.time * 2.4) * 0.08;
  r.chest.rotation.x = -(0.06 + 0.22 * lean); // leaning into the way it goes
  r.tail.rotation.x = -0.6 * lean + Math.sin(m.time * 3) * 0.08 + m.sway.x * 0.4;
  r.tail.rotation.z = Math.sin(m.time * 2.1) * 0.1 + m.sway.z;
  r.arms.forEach((a, i) => {
    a.shoulder.rotation.x = Math.sin(m.time * 2.4 + i) * 0.08 + 0.3 * lean - 0.5 * attack.wind + 1.1 * attack.strike + 0.2 * hit;
    a.elbow.rotation.x = 0.3;
  });
}
// a target at 0 health lies down on its side
function lieDown(m, dt, dead) {
  m.fall = ease(m.fall, dead ? 1 : 0, dt, dead ? 0.18 : 0.12);
  m.rig.root.rotation.z = m.fall * Math.PI * 0.48;
  m.rig.root.position.y = m.fall * 0.35;
}


export { SENTINEL, nightElf, moonkin, furbolg, bear, cat, cheetah, wolf, nightsaber, voidwalker, mover, act, step, lieDown, solveArm, spring };
