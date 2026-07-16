// Icon prep. Two jobs:
//  1) WHITEN — Figma's source glyphs are black-RGB + alpha. Roblox's ImageColor3
//     MULTIPLIES, so black * anything = black: they can never be tinted, they just
//     render as dark smudges. Rewriting RGB to white (keeping alpha) makes
//     ImageColor3 work, so one PNG serves grey/white/accent states.
//  2) GLOW — generate a radial falloff PNG so selection glow is a real bloom
//     instead of a scaled tinted copy of the icon.
//
// Zero deps: hand-rolled PNG decode/encode (RGBA8, non-interlaced).

const fs = require("fs");
const zlib = require("zlib");
const path = require("path");

const CRC = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return (buf) => {
    let c = -1;
    for (let i = 0; i < buf.length; i++) c = t[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ -1) >>> 0;
  };
})();

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(CRC(td));
  return Buffer.concat([len, td, crc]);
}

function decode(file) {
  const b = fs.readFileSync(file);
  const w = b.readUInt32BE(16), h = b.readUInt32BE(20);
  const bitDepth = b[24], ct = b[25], interlace = b[28];
  if (bitDepth !== 8) throw new Error("bitDepth " + bitDepth + " unsupported");
  if (interlace !== 0) throw new Error("interlaced unsupported");
  const ch = ct === 6 ? 4 : ct === 2 ? 3 : ct === 4 ? 2 : 1;
  let idat = [], p = 8;
  while (p < b.length) {
    const len = b.readUInt32BE(p), type = b.toString("ascii", p + 4, p + 8);
    if (type === "IDAT") idat.push(b.slice(p + 8, p + 8 + len));
    p += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * ch;
  const out = Buffer.alloc(w * h * ch);
  let pos = 0, prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const ft = raw[pos++];
    const line = raw.slice(pos, pos + stride); pos += stride;
    const cur = Buffer.alloc(stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= ch ? cur[i - ch] : 0, b2 = prev[i], c = i >= ch ? prev[i - ch] : 0;
      let v = line[i];
      if (ft === 1) v += a;
      else if (ft === 2) v += b2;
      else if (ft === 3) v += Math.floor((a + b2) / 2);
      else if (ft === 4) {
        const pa = Math.abs(b2 - c), pb = Math.abs(a - c), pc = Math.abs(a + b2 - 2 * c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b2 : c;
      }
      cur[i] = v & 255;
    }
    cur.copy(out, y * stride);
    prev = cur;
  }
  return { w, h, ch, data: out };
}

function encodeRGBA(w, h, rgba) {
  const stride = w * 4;
  const raw = Buffer.alloc((stride + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0; // filter: none
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function toRGBA(dec) {
  const { w, h, ch, data } = dec;
  if (ch === 4) return data;
  const out = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    if (ch === 3) { out[i * 4] = data[i * 3]; out[i * 4 + 1] = data[i * 3 + 1]; out[i * 4 + 2] = data[i * 3 + 2]; out[i * 4 + 3] = 255; }
    else if (ch === 2) { out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = data[i * 2]; out[i * 4 + 3] = data[i * 2 + 1]; }
    else { out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = data[i]; out[i * 4 + 3] = 255; }
  }
  return out;
}

// Crop fully-transparent margins so every icon is edge-to-edge and can be laid out
// by its real size rather than whatever padding Figma's effect bounds added.
function trim(w, h, rgba) {
  let minX = w, minY = h, maxX = -1, maxY = -1;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (rgba[(y * w + x) * 4 + 3] > 8) {
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return { w, h, rgba };
  const nw = maxX - minX + 1, nh = maxY - minY + 1;
  const out = Buffer.alloc(nw * nh * 4);
  for (let y = 0; y < nh; y++)
    rgba.copy(out, y * nw * 4, ((y + minY) * w + minX) * 4, ((y + minY) * w + minX) * 4 + nw * 4);
  return { w: nw, h: nh, rgba: out };
}

const dir = path.join(__dirname, "..", "icons");
const names = ["logo", "star", "wifi", "globe", "eye", "pistol", "car", "grid", "keybind", "gear"];

for (const n of names) {
  const f = path.join(dir, n + ".png");
  if (!fs.existsSync(f)) { console.log("skip (missing):", n); continue; }
  const dec = decode(f);
  let rgba = toRGBA(dec);
  let { w, h } = dec;
  ({ w, h, rgba } = trim(w, h, rgba));
  // whiten: keep alpha, force RGB to white so ImageColor3 can tint it
  for (let i = 0; i < w * h; i++) {
    if (rgba[i * 4 + 3] > 0) { rgba[i * 4] = 255; rgba[i * 4 + 1] = 255; rgba[i * 4 + 2] = 255; }
  }
  fs.writeFileSync(f, encodeRGBA(w, h, rgba));
  console.log("whitened", (n + ".png").padEnd(13), w + "x" + h);
}

// radial glow: white centre -> transparent edge, smooth falloff
{
  const S = 256, r = S / 2;
  const g = Buffer.alloc(S * S * 4);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const d = Math.sqrt((x - r) ** 2 + (y - r) ** 2) / r;
    let a = 1 - Math.min(d, 1);
    a = Math.pow(a, 2.2); // tighter core, soft tail
    const i = (y * S + x) * 4;
    g[i] = g[i + 1] = g[i + 2] = 255;
    g[i + 3] = Math.round(a * 255);
  }
  fs.writeFileSync(path.join(dir, "glow.png"), encodeRGBA(S, S, g));
  console.log("generated    glow.png     256x256");
}
