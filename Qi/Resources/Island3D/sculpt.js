// 捏出来的形状：不拿现成的球、方块直接拼，而是照真东西的轮廓长出来、再推拉变形。
// - noise / fbm：一片连续的起伏（同一个位置永远是同一个值，接缝不会裂）
// - lumpy：沿法线鼓一鼓、瘪一瘪（石头、树冠、果子表面不再是正圆）
// - bend / taper / twist：整体弯、一头细、拧一点
// - leaf：按叶子的轮廓（叶尖、最宽处、叶柄）铺一张面，再沿叶脉对折、往下垂、边上起波浪
// - stem：沿一条曲线长出一根管子，粗细一路变（茎、树干、树枝、藤）
// - fruit：果子——有棱（南瓜）、顶上凹（苹果、番茄）、一头尖（草莓）、表面起伏
// - rock / canopy：不规则的石头、一团团的树冠
import * as THREE from 'three';
import { mergeVertices, mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// ———— 噪声 ————
const hash = (x, y, z, s) => {
  let h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(z | 0, 1440662683) ^ Math.imul(s | 0, 2246822519);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};
const sm = (t) => t * t * (3 - 2 * t);
export function noise(x, y, z, s = 0) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z), u = sm(x - xi), v = sm(y - yi), w = sm(z - zi);
  const L = (a, b, t) => a + (b - a) * t;
  const c = (i, j, k) => hash(xi + i, yi + j, zi + k, s);
  return L(L(L(c(0, 0, 0), c(1, 0, 0), u), L(c(0, 1, 0), c(1, 1, 0), u), v), L(L(c(0, 0, 1), c(1, 0, 1), u), L(c(0, 1, 1), c(1, 1, 1), u), v), w) * 2 - 1;
}
export function fbm(x, y, z, s = 0, oct = 3) {
  let a = 0, amp = 1, f = 1, tot = 0;
  for (let i = 0; i < oct; i++) { a += noise(x * f, y * f, z * f, s + i * 17) * amp; tot += amp; amp *= .5; f *= 2.03; }
  return a / tot;
}

// ———— 变形 ————
// 法线重新算成平滑的（球的接缝处先并成一个点，不然会有一道折痕）
export function smooth(geo) {
  let g = geo;
  for (const k of Object.keys(g.attributes)) if (k !== 'position') g.deleteAttribute(k);
  g = mergeVertices(g, 1e-5);
  g.computeVertexNormals();
  return g;
}
export function deform(geo, fn) {
  const pa = geo.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < pa.count; i++) { v.fromBufferAttribute(pa, i); fn(v, i); pa.setXYZ(i, v.x, v.y, v.z); }
  pa.needsUpdate = true;
  return geo;
}
// 沿着从中心出去的方向鼓瘪（形状大致是团状的东西用）
export function lumpy(geo, amp = .1, freq = 2, seed = 0, oct = 3) {
  return deform(geo, (v) => { const n = fbm(v.x * freq, v.y * freq, v.z * freq, seed, oct); const l = v.length() || 1; v.multiplyScalar(1 + n * amp / Math.max(.2, l) * l); });
}
// 绕 z 轴往 x 方向弯（沿 y 长的东西）：k = 弯多少（顶上偏出去 k）
export function bend(geo, k, len = 1) {
  return deform(geo, (v) => { const t = v.y / len; v.x += k * t * t; });
}
// 越往上越细：top = 顶上剩几成
export function taper(geo, top = .5, y0 = 0, y1 = 1) {
  return deform(geo, (v) => { const t = Math.min(1, Math.max(0, (v.y - y0) / (y1 - y0))); const f = 1 + (top - 1) * t; v.x *= f; v.z *= f; });
}

// ———— 叶子 / 花瓣 ————
// 叶子平铺在 x 方向（叶柄在原点、叶尖在 +x），宽在 z，背面朝 -y。
// shape：叶子的轮廓（0 到 1 每一处的半宽，乘 wid）；默认是一片尖头、最宽处在三分之一的叶子
export const LEAF = (u) => Math.pow(Math.sin(Math.PI * Math.pow(u, .72)), .9) * (1 - .15 * u);
export const PETAL = (u) => Math.pow(Math.sin(Math.PI * Math.pow(u, .55)), .7);
export const BLADE = (u) => (1 - u) * Math.min(1, u * 8);   // 细长的草叶、麦叶
export function leaf({ len = 1, wid = .4, shape = LEAF, segL = 10, segW = 4, droop = .25, fold = .3, curl = 0, wave = 0, waves = 5, seed = 0, both = true } = {}) {
  const pos = [], idx = [], cols = segW * 2 + 1;
  for (let i = 0; i <= segL; i++) {
    const u = i / segL, hw = wid * .5 * shape(u);
    for (let j = 0; j < cols; j++) {
      const v = j / (cols - 1) * 2 - 1, av = Math.abs(v);
      let x = u * len, z = v * hw, y = 0;
      y += fold * av * hw;                              // 沿叶脉对折，两边往上翘
      y -= droop * len * u * u;                         // 叶尖往下垂
      y += wave * hw * av * Math.sin(u * waves * Math.PI + seed) * (.4 + .6 * u);   // 边上起伏
      y += noise(u * 3, v * 2, seed, 5) * .06 * hw;
      if (curl) { const a = curl * u * v; const yy = y * Math.cos(a) - z * Math.sin(a); z = y * Math.sin(a) + z * Math.cos(a); y = yy; }   // 边往里卷
      pos.push(x, y, z);
    }
  }
  for (let i = 0; i < segL; i++) for (let j = 0; j < cols - 1; j++) {
    const a = i * cols + j, b = a + 1, c = a + cols, d = c + 1;
    idx.push(a, c, b, b, c, d);
  }
  // 两面都要（叶子薄，从底下看也看得见）：反面再铺一层，稍微错开一点点（材质本身两面都画的就不用）
  const n = pos.length / 3;
  if (both) for (let k = 0; k < n; k++) pos.push(pos[k * 3], pos[k * 3 + 1] - .002 * wid, pos[k * 3 + 2]);
  const m = idx.length;
  if (both) for (let k = 0; k < m; k += 3) idx.push(idx[k] + n, idx[k + 2] + n, idx[k + 1] + n);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
  return g;
}

// ———— 茎、树干、树枝 ————
// pts：一串点（会连成顺滑的曲线）；r0 → r1：从根到梢的粗细；bulge：中间鼓一点
export function stem(pts, r0 = .02, r1 = .008, { seg = 16, rad = 7, bulge = 0, knots = 0, seed = 0, cap = true } = {}) {
  const curve = new THREE.CatmullRomCurve3(pts.map((p) => (p.isVector3 ? p : new THREE.Vector3(...p))));
  const fr = curve.computeFrenetFrames(seg, false), pos = [], idx = [];
  for (let i = 0; i <= seg; i++) {
    const t = i / seg, c = curve.getPointAt(t), N = fr.normals[i], B = fr.binormals[i];
    let r = r0 + (r1 - r0) * t; r *= 1 + bulge * Math.sin(Math.PI * t);
    if (knots) r *= 1 + .18 * Math.max(0, Math.sin(t * knots * Math.PI * 2)) ** 8;
    for (let j = 0; j < rad; j++) {
      const a = j / rad * Math.PI * 2, rr = r * (1 + noise(t * 6, Math.cos(a), Math.sin(a), seed) * .12);
      pos.push(c.x + (N.x * Math.cos(a) + B.x * Math.sin(a)) * rr, c.y + (N.y * Math.cos(a) + B.y * Math.sin(a)) * rr, c.z + (N.z * Math.cos(a) + B.z * Math.sin(a)) * rr);
    }
  }
  for (let i = 0; i < seg; i++) for (let j = 0; j < rad; j++) {
    const a = i * rad + j, b = i * rad + (j + 1) % rad, c = a + rad, d = b + rad;
    idx.push(a, b, c, b, d, c);
  }
  if (cap) {   // 梢上收成一个尖（不留开口）
    const tip = curve.getPointAt(1), d = curve.getTangentAt(1), k = pos.length / 3;
    pos.push(tip.x + d.x * r1, tip.y + d.y * r1, tip.z + d.z * r1);
    for (let j = 0; j < rad; j++) idx.push(seg * rad + j, seg * rad + (j + 1) % rad, k);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
  return g;
}

// ———— 果子 ————
// lobes：几道棱（南瓜 10）；dent：顶上凹多深；point：底下尖出去多少（草莓）；lump：表面起伏
export function fruit(r = .1, { sx = 1, sy = 1, sz = 1, lobes = 0, lobeAmp = .08, dent = .25, point = 0, lump = .04, seed = 0, seg = r < .01 ? 6 : r < .03 ? 10 : r < .09 ? 16 : 26 } = {}) {
  let g = new THREE.SphereGeometry(1, seg, Math.round(seg * .75));
  g = smooth(g);
  deform(g, (v) => {
    const lat = v.y, phi = Math.atan2(v.z, v.x), eq = 1 - lat * lat;
    let k = 1 + lobeAmp * Math.pow(Math.abs(Math.cos(lobes * phi / 2)), .45) * Math.sqrt(eq) * (lobes ? 1 : 0) - (lobes ? lobeAmp * .5 : 0);
    if (lat > 0) v.y -= dent * Math.pow(Math.max(0, 1 - Math.hypot(v.x, v.z) / .55), 2);   // 果蒂那儿往里凹
    if (point && lat < 0) { v.y -= point * Math.pow(-lat, 3); k *= 1 - .45 * point * Math.pow(-lat, 2); }   // 往下收尖
    k *= 1 + fbm(v.x * 2.2, v.y * 2.2, v.z * 2.2, seed) * lump * 2;
    v.x *= k * r * sx; v.z *= k * r * sz; v.y *= r * sy;
  });
  g.computeVertexNormals();
  return g;
}

// ———— 石头、树冠 ————
export function rock(r = .2, { flat = .55, seed = 0, rough = .22, detail = 3 } = {}) {
  let g = smooth(new THREE.IcosahedronGeometry(1, detail));
  deform(g, (v) => {
    const n = fbm(v.x * 1.6, v.y * 1.6, v.z * 1.6, seed, 4);
    v.multiplyScalar(1 + n * rough);
    // 几个削平的面（石头是被劈开、磨平的，不是一团泥）
    for (const [px, py, pz, d] of [[.7, .5, .2, .78], [-.5, .4, .6, .8], [.1, .9, -.3, .74]]) { const s = v.x * px + v.y * py + v.z * pz; if (s > d) v.addScaledVector(new THREE.Vector3(px, py, pz), (d - s) * .8); }
    if (v.y < 0) v.y *= .35;   // 底下压平，坐在地上
    v.y *= flat; v.multiplyScalar(r);
  });
  g.computeVertexNormals();
  return g;
}
// 树冠：几团大小不一的鼓包挤在一起，表面再起一层细的起伏（叶丛的感觉），底下收平一点
export function canopy(r = .6, { blobs = 6, seed = 0, sy = .85, rough = .18 } = {}) {
  let s = seed * 9301 + 7; const rnd = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  const parts = [];
  for (let i = 0; i < blobs; i++) {
    const a = rnd() * Math.PI * 2, d = i === 0 ? 0 : r * (.35 + rnd() * .3), y = i === 0 ? 0 : (rnd() - .35) * r * .6;
    const rr = r * (i === 0 ? .75 : .42 + rnd() * .2);
    const b = new THREE.IcosahedronGeometry(rr, 3);
    b.translate(Math.cos(a) * d, y, Math.sin(a) * d);
    parts.push(b);
  }
  let g = smooth(mergeGeometries(parts.map((p) => { p.deleteAttribute('uv'); p.deleteAttribute('normal'); return p; })));
  deform(g, (v) => {
    v.multiplyScalar(1 + fbm(v.x * 3 / r, v.y * 3 / r, v.z * 3 / r, seed, 3) * rough);
    v.multiplyScalar(1 + noise(v.x * 9 / r, v.y * 9 / r, v.z * 9 / r, seed + 3) * .05);
    v.y *= sy; if (v.y < -r * .3) v.y = -r * .3 + (v.y + r * .3) * .4;
  });
  g.computeVertexNormals();
  return g;
}

// ———— 田垄 ————
// 一道翻过的土垄：中间拱起、两头收下去，表面一块块高低不平（沿 x 长，宽在 z，底边贴地）
export function ridge(len = .96, wid = .16, h = .07, { seed = 0, nx = 22, nz = 6 } = {}) {
  const pos = [], idx = [], cols = nz + 1;
  for (let i = 0; i <= nx; i++) {
    const u = i / nx, end = Math.pow(Math.sin(Math.PI * Math.min(1, Math.max(0, u * 1.08 - .04))), .35);
    for (let j = 0; j <= nz; j++) {
      const v = j / nz * 2 - 1, prof = Math.pow(Math.max(0, 1 - v * v), .75) * end;
      const x = (u - .5) * len + noise(u * 5, v, seed, 2) * .015;
      const z = v * wid * .5 * (1 + noise(u * 6, 3, seed, 4) * .12);
      const y = h * prof * (1 + fbm(u * 9, v * 2, seed, 6, 3) * .35 + noise(u * 30, v * 5, seed, 8) * .12) - .012 * (1 - prof);
      pos.push(x, y, z);
    }
  }
  for (let i = 0; i < nx; i++) for (let j = 0; j < nz; j++) { const a = i * cols + j, b = a + 1, c = a + cols, d = c + 1; idx.push(a, b, c, b, d, c); }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setIndex(idx); g.computeVertexNormals();
  return g;
}
