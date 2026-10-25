// Spheres' textures as the game reads them: RGBA bytes, rows top first. From TGA (the add-on's own files, under
// make sim) or PNG (the public page's, make site: the same pixels in a fifteenth of the bytes). Decoded here, not
// by the browser: an <img> or an ImageBitmap may premultiply alpha or convert colour, and the glows are mostly
// alpha. Each answers { w, h, data }.

export function decodeTGA(buffer, name) {
  const b = new Uint8Array(buffer), d = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const type = b[2], w = d.getUint16(12, true), h = d.getUint16(14, true), bpp = b[16], desc = b[17];
  if (b[1] !== 0 || (type !== 2 && type !== 10) || (bpp !== 32 && bpp !== 24)) throw new Error(name + ": unsupported TGA");
  const px = bpp / 8, n = w * h, out = new Uint8Array(n * 4);
  let p = 18 + b[0], i = 0;
  const put = o => { out[i * 4] = b[o + 2]; out[i * 4 + 1] = b[o + 1]; out[i * 4 + 2] = b[o]; out[i * 4 + 3] = px === 4 ? b[o + 3] : 255; i++; };
  if (type === 2) { while (i < n) { put(p); p += px; } }
  else {
    while (i < n) {
      const head = b[p++], count = (head & 127) + 1;
      if (head & 128) { for (let k = 0; k < count && i < n; k++) put(p); p += px; }
      else for (let k = 0; k < count && i < n; k++) { put(p); p += px; }
    }
  }
  if (!(desc & 0x20)) { // bottom-left origin: rows bottom first
    const row = w * 4, tmp = new Uint8Array(row);
    for (let y = 0; y < h / 2; y++) {
      const a = y * row, z = (h - 1 - y) * row;
      tmp.set(out.subarray(a, a + row)); out.copyWithin(a, z, z + row); out.set(tmp, z);
    }
  }
  return { w, h, data: out };
}

// Only what make site writes: 8 bits a channel, RGBA, not interlaced. Its pixels come through the browser's
// own zlib (DecompressionStream), then the PNG row filters are undone.
export async function decodePNG(buffer, name) {
  const b = new Uint8Array(buffer), d = new DataView(b.buffer, b.byteOffset, b.byteLength);
  if (d.getUint32(0) !== 0x89504e47 || d.getUint32(4) !== 0x0d0a1a0a) throw new Error(name + ": not a PNG");
  let p = 8, w = 0, h = 0;
  const parts = [];
  while (p + 8 <= b.length) {
    const length = d.getUint32(p), type = d.getUint32(p + 4);
    if (type === 0x49484452) { // IHDR
      w = d.getUint32(p + 8);
      h = d.getUint32(p + 12);
      if (b[p + 16] !== 8 || b[p + 17] !== 6 || b[p + 20] !== 0) throw new Error(name + ": not an 8-bit RGBA PNG");
    } else if (type === 0x49444154) parts.push(b.subarray(p + 8, p + 8 + length)); // IDAT
    else if (type === 0x49454e44) break; // IEND
    p += 12 + length;
  }
  const stream = new Blob(parts).stream().pipeThrough(new DecompressionStream("deflate"));
  const raw = new Uint8Array(await new Response(stream).arrayBuffer());
  const row = w * 4, out = new Uint8Array(row * h);
  if (raw.length < (row + 1) * h) throw new Error(name + ": PNG cut short");
  for (let y = 0; y < h; y++) {
    const filter = raw[y * (row + 1)], s = y * (row + 1) + 1, o = y * row, up = o - row;
    for (let x = 0; x < row; x++) {
      const left = x >= 4 ? out[o + x - 4] : 0, above = y ? out[up + x] : 0, corner = x >= 4 && y ? out[up + x - 4] : 0;
      let v = raw[s + x];
      if (filter === 1) v += left;
      else if (filter === 2) v += above;
      else if (filter === 3) v += (left + above) >> 1;
      else if (filter === 4) {
        const pa = Math.abs(above - corner), pb = Math.abs(left - corner), pc = Math.abs(left + above - 2 * corner);
        v += pa <= pb && pa <= pc ? left : pb <= pc ? above : corner;
      } else if (filter !== 0) throw new Error(name + ": PNG filter " + filter);
      out[o + x] = v; // a byte: wraps as the filters mean
    }
  }
  return { w, h, data: out };
}
