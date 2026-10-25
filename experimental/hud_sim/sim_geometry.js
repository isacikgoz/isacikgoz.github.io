// Shared cartoon geometry and materials for the world and articulated figures.
import * as THREE from "./vendor/three.module.min.js";
const OUTLINE = 0.014;

// ---------------------------------------------------------------- cartoon materials and parts
// Three bands of light; a dark edge round every part (a copy of it behind, a little larger, its faces turned in).
const BANDS = (() => {
  const t = new THREE.DataTexture(new Uint8Array([95, 175, 255]), 3, 1, THREE.RedFormat);
  t.minFilter = t.magFilter = THREE.NearestFilter;
  t.needsUpdate = true;
  return t;
})();
const toons = new Map();
function toon(color) {
  if (!toons.has(color)) toons.set(color, new THREE.MeshToonMaterial({ color, gradientMap: BANDS }));
  return toons.get(color);
}
const INK = new THREE.MeshBasicMaterial({ color: 0x1c140e, side: THREE.BackSide });
const glow = color => new THREE.MeshBasicMaterial({ color });

// A part: a geometry centred on its origin, its colour (or material), its edge sized to stay `outline` thick.
function part(geometry, color, outline = OUTLINE) {
  const mesh = new THREE.Mesh(geometry, typeof color === "number" ? toon(color) : color);
  if (outline) {
    geometry.computeBoundingBox();
    const size = geometry.boundingBox.getSize(new THREE.Vector3());
    const centre = geometry.boundingBox.getCenter(new THREE.Vector3());
    const hull = new THREE.Mesh(geometry, INK);
    hull.scale.set(1 + 2 * outline / Math.max(size.x, 0.01), 1 + 2 * outline / Math.max(size.y, 0.01),
      1 + 2 * outline / Math.max(size.z, 0.01));
    hull.position.set(centre.x * (1 - hull.scale.x), centre.y * (1 - hull.scale.y), centre.z * (1 - hull.scale.z));
    mesh.add(hull);
  }
  return mesh;
}
function put(parent, child, x = 0, y = 0, z = 0) {
  child.position.set(x, y, z);
  parent.add(child);
  return child;
}
const group = () => new THREE.Group();
function ball(r, color, sx = 1, sy = 1, sz = 1, outline = OUTLINE) {
  const m = part(new THREE.SphereGeometry(r, 18, 14), color, outline);
  m.scale.set(sx, sy, sz);
  return m;
}
const capsule = (r, length, color, outline = OUTLINE) => part(new THREE.CapsuleGeometry(r, length, 5, 12), color, outline);
const cone = (r, h, color, sides = 10) => part(new THREE.ConeGeometry(r, h, sides), color);
const cylinder = (r0, r1, h, color, sides = 12, outline = OUTLINE) => part(new THREE.CylinderGeometry(r0, r1, h, sides), color, outline);
function leaf(length, color) { // a flat four-sided cone, pointing up
  const m = cone(length * 0.28, length, color, 4);
  m.scale.z = 0.3;
  return m;
}
function ring(r, tube, color, outline = OUTLINE) { return part(new THREE.TorusGeometry(r, tube, 8, 28), color, outline); }
// a pivot turned by `x` round its own x axis (after its parent's turn): for parts that tilt out from a ring
function tilted(parent, x, y, z, turnY, tiltX) {
  const holder = put(parent, group(), x, y, z);
  holder.rotation.y = turnY;
  const tilt = put(holder, group());
  tilt.rotation.x = tiltX;
  return tilt;
}

// An arc from its root out sideways (side 1: to the right), curling up, tapering to its tip: a horn, a crescent.
function horn(radius, thick, arc, color, side, taper = 0.75) {
  const g = new THREE.TorusGeometry(radius, thick, 8, 16, arc);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), y = p.getY(i), u = Math.atan2(y, x), cx = radius * Math.cos(u), cy = radius * Math.sin(u);
    const k = 1 - taper * Math.max(0, Math.min(1, u / arc));
    p.setXYZ(i, cx + (x - cx) * k, cy + (y - cy) * k, p.getZ(i) * k);
  }
  g.computeVertexNormals();
  const holder = group();
  const m = put(holder, part(g, color, OUTLINE * 0.8), 0, radius, 0); // its root at the holder's origin
  m.rotation.z = -Math.PI / 2;
  holder.scale.x = side;
  return holder;
}
// a sash round a barrel: a loop from one shoulder across to the other hip
function sash(r, tube, color, tilt, depth) {
  const holder = group();
  put(holder, ring(r, tube, color)).rotation.y = Math.PI / 2;
  holder.rotation.z = tilt;
  holder.scale.z = depth;
  return holder;
}

// One prop's parts merged into one mesh a material (their dark edges into one too): a prop is a few draw
// calls, not dozens, for the laptops a public page meets. Its glows (sprites) stay as they are.
const joined = arrays => {
  const out = new Float32Array(arrays.reduce((n, a) => n + a.length, 0));
  let at = 0;
  for (const a of arrays) { out.set(a, at); at += a.length; }
  return out;
};
function bake(g) {
  g.updateMatrixWorld(true);
  const inv = g.matrixWorld.clone().invert(), m = new THREE.Matrix4(), byMaterial = new Map(), glows = [];
  g.traverse(o => {
    if (o.isMesh) {
      if (!byMaterial.has(o.material)) byMaterial.set(o.material, []);
      byMaterial.get(o.material).push(o);
    } else if (o.isSprite) glows.push(o);
  });
  const out = group();
  Object.assign(out.userData, g.userData);
  for (const [material, meshes] of byMaterial) {
    const pos = [], nrm = [];
    for (const o of meshes) {
      m.multiplyMatrices(inv, o.matrixWorld);
      const geo = (o.geometry.index ? o.geometry.toNonIndexed() : o.geometry.clone()).applyMatrix4(m);
      const p = geo.attributes.position.array, n = geo.attributes.normal.array;
      if (m.determinant() < 0) { // a mirrored part: each triangle turned back round, so its front still faces out
        for (let i = 0; i < p.length; i += 9) for (let k = 0; k < 3; k++) {
          [p[i + 3 + k], p[i + 6 + k]] = [p[i + 6 + k], p[i + 3 + k]];
          [n[i + 3 + k], n[i + 6 + k]] = [n[i + 6 + k], n[i + 3 + k]];
        }
      }
      pos.push(p);
      nrm.push(n);
    }
    const merged = new THREE.BufferGeometry();
    merged.setAttribute("position", new THREE.BufferAttribute(joined(pos), 3));
    merged.setAttribute("normal", new THREE.BufferAttribute(joined(nrm), 3));
    out.add(new THREE.Mesh(merged, material));
  }
  for (const glowSprite of glows) {
    m.multiplyMatrices(inv, glowSprite.matrixWorld).decompose(glowSprite.position, glowSprite.quaternion, glowSprite.scale);
    out.add(glowSprite);
  }
  return out;
}

export { OUTLINE, BANDS, INK, toon, glow, part, put, group, ball, capsule, cone, cylinder, leaf, ring, tilted, horn, sash, bake };
