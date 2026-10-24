// 拼模型的工具：每一块都烘成世界坐标、带顶点色，最后合成一个网格（整座岛一次绘制）。
//
// 描边、三阶卡通光的做法参考、改写自 StarFold146/Nyx（town/shop/look.js，MIT License，Copyright (c) 2026 StarFold146）。
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';

export const grad = (() => {   // 三阶卡通光（暗、中、亮）
  const d = new Uint8Array([150, 196, 236, 255]);
  const t = new THREE.DataTexture(d, 4, 1, THREE.RedFormat);
  t.minFilter = t.magFilter = THREE.NearestFilter; t.needsUpdate = true;
  return t;
})();

// 水彩晕：白底上叠一团团深浅，乘在颜色上；按世界坐标贴，整座岛一张图
export const washTex = (() => {
  const n = 512, c = document.createElement('canvas'); c.width = c.height = n;
  const g = c.getContext('2d');
  g.fillStyle = '#ffffff'; g.fillRect(0, 0, n, n);
  let s = 31; const r = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  for (let i = 0; i < 90; i++) {
    const x = r() * n, y = r() * n, rad = 20 + r() * 80, k = .86 + r() * .1;
    for (const [ox, oy] of [[0, 0], [n, 0], [-n, 0], [0, n], [0, -n]]) {   // 四边接得上
      const gr = g.createRadialGradient(x + ox, y + oy, 0, x + ox, y + oy, rad);
      const v = Math.round(255 * k);
      gr.addColorStop(0, `rgba(${v},${v},${Math.round(v * .985)},.5)`); gr.addColorStop(1, `rgba(${v},${v},${v},0)`);
      g.fillStyle = gr; g.fillRect(x + ox - rad, y + oy - rad, rad * 2, rad * 2);
    }
  }
  for (let i = 0; i < 1400; i++) {   // 纸里的细纤维
    g.strokeStyle = `rgba(120,110,95,${.03 + r() * .04})`; g.lineWidth = .6;
    const x = r() * n, y = r() * n, a = r() * 6.28, l = 3 + r() * 9;
    g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 4;
  return t;
})();

export const toon = new THREE.MeshToonMaterial({ vertexColors: true, gradientMap: grad, map: washTex });
export const hullMat = new THREE.MeshBasicMaterial({ color: new THREE.Color('#5a4436'), side: THREE.BackSide });

let SEED = 7;
export const R = () => ((SEED = (SEED * 9301 + 49297) % 233280) / 233280);
export const jit = (hex, k = .05) => { const c = new THREE.Color(hex); const f = 1 + (R() - .5) * 2 * k; return c.multiplyScalar(f); };

// 按材质分开合：石头和木头（哑光）、金（会反光）、玻璃（彩绘玻璃，透亮）、水
export const store = { groups: { base: [], gold: [], glass: [], water: [], roof: [], slate: [], siding: [], darkstone: [], ashlar: [], plinth: [], glow: [], iron: [] }, hulls: [] };
store.parts = store.groups.base;
// 描边：华丽版不要（那是可爱版的画法）
export const OPT = { outline: false };
const GOLDS = new Set(['#c8a96c', '#c9a96a', '#d4af6a', '#b8944f', '#e3c06a', '#e8c46a']);
const tmpM = new THREE.Matrix4(), tmpQ = new THREE.Quaternion(), tmpE = new THREE.Euler(), tmpS = new THREE.Vector3(), tmpP = new THREE.Vector3();

// 一块：geo 按 p / r / s 摆好，涂成 color。
// line：描边多粗（0 = 不描）；ao：地面高度——越贴地越暗一点（假的环境光遮蔽）
export function bake(geo, color, { p = [0, 0, 0], r = [0, 0, 0], s = [1, 1, 1], line = .014, ao = null, matrix = null, mat = null } = {}) {
  let g = geo.index ? geo.toNonIndexed() : geo.clone();
  for (const k of Object.keys(g.attributes)) if (k !== 'position' && k !== 'normal') g.deleteAttribute(k);
  if (!g.attributes.normal) g.computeVertexNormals();
  tmpE.set(r[0], r[1], r[2]); tmpQ.setFromEuler(tmpE); tmpP.set(p[0], p[1], p[2]); tmpS.set(s[0], s[1], s[2]);
  tmpM.compose(tmpP, tmpQ, tmpS);
  if (matrix) tmpM.premultiply(matrix);
  g.applyMatrix4(tmpM);
  const col = color instanceof THREE.Color ? color : new THREE.Color(color);
  const pa = g.attributes.position, n = pa.count, ca = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    let k = 1;
    if (ao != null) { const h = pa.getY(i) - ao; const t = Math.max(0, Math.min(1, h / .45)); k = .74 + .26 * t * t * (3 - 2 * t); }
    ca[i * 3] = col.r * k; ca[i * 3 + 1] = col.g * k; ca[i * 3 + 2] = col.b * k;
  }
  g.setAttribute('color', new THREE.BufferAttribute(ca, 3));
  const group = mat || (typeof color === 'string' && GOLDS.has(color.toLowerCase()) ? 'gold' : 'base');
  store.groups[group].push(g);
  if (OPT.outline && line > .0055) {   // 描边壳（太细的小零件不描：远看看不见，还多一倍三角形）：法线合并成平滑的再往外撑，转角才不会断线
    let h = new THREE.BufferGeometry(); h.setAttribute('position', pa.clone());
    h = mergeVertices(h, 1e-3); h.computeVertexNormals();
    const hp = h.attributes.position, hn = h.attributes.normal;
    for (let i = 0; i < hp.count; i++) hp.setXYZ(i, hp.getX(i) + hn.getX(i) * line, hp.getY(i) + hn.getY(i) * line, hp.getZ(i) + hn.getZ(i) * line);
    h = h.toNonIndexed(); h.deleteAttribute('normal');
    store.hulls.push(h);
  }
  return g;
}

// 按世界坐标给每块贴图坐标（朝上的面用 x/z，侧面用水平方向和高度）
export function worldUV(g) {
  const pa = g.attributes.position, na = g.attributes.normal, n = pa.count, uv = new Float32Array(n * 2), S = .16;
  for (let i = 0; i < n; i++) {
    const x = pa.getX(i), y = pa.getY(i), z = pa.getZ(i), nx = Math.abs(na.getX(i)), ny = Math.abs(na.getY(i)), nz = Math.abs(na.getZ(i));
    if (ny > .6) { uv[i * 2] = x * S; uv[i * 2 + 1] = z * S; }
    else if (nx > nz) { uv[i * 2] = z * S + .37; uv[i * 2 + 1] = y * S; }
    else { uv[i * 2] = x * S + .71; uv[i * 2 + 1] = y * S; }
  }
  g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
}

export const box = (w, h, d, r = 0, seg = 2) => r > 0 ? new RoundedBoxGeometry(w, h, d, seg, Math.min(r, w / 2 - .001, h / 2 - .001, d / 2 - .001)) : new THREE.BoxGeometry(w, h, d);
export const cyl = (rt, rb, h, seg = 12, open = false) => new THREE.CylinderGeometry(rt, rb, h, seg, 1, open);
export const cone = (r, h, seg = 12) => new THREE.ConeGeometry(r, h, seg);
export const ball = (r, ws = 12, hs = 9, ...rest) => new THREE.SphereGeometry(r, ws, hs, ...rest);
export const torus = (r, t, rs = 6, ts = 16, arc = Math.PI * 2) => new THREE.TorusGeometry(r, t, rs, ts, arc);
export const disc = (r, seg = 16, a0 = 0, al = Math.PI * 2) => { const g = new THREE.CircleGeometry(r, seg, a0, al); g.rotateX(-Math.PI / 2); return g; };
// 一团叶子：二十面体轻轻揉一下，法线是平滑的（卡通光下是一团软软的，不是一面一面的）
export const blob = (r, detail = 1, squash = 1, rough = .14) => {
  const g = new THREE.IcosahedronGeometry(r, detail);
  let m = new THREE.BufferGeometry(); m.setAttribute('position', g.attributes.position.clone()); m = mergeVertices(m, 1e-4);
  const mp = m.attributes.position;
  for (let i = 0; i < mp.count; i++) { const k = 1 + (R() - .5) * rough; mp.setXYZ(i, mp.getX(i) * k, mp.getY(i) * k * squash, mp.getZ(i) * k); }
  m.computeVertexNormals(); return m;
};
// 锯齿边的松树层：底边一圈一长一短
export const jag = (r, h, seg = 12) => {
  const g = new THREE.ConeGeometry(r, h, seg, 1);
  const pa = g.attributes.position;
  for (let i = 0; i < pa.count; i++) {
    if (pa.getY(i) < -h / 2 + 1e-4) {
      const a = Math.atan2(pa.getZ(i), pa.getX(i)), k = Math.round(a / (Math.PI * 2 / seg)) % 2 ? .82 : 1.04;
      pa.setX(i, pa.getX(i) * k); pa.setZ(i, pa.getZ(i) * k); pa.setY(i, pa.getY(i) + (k < 1 ? .05 : -.02));
    }
  }
  g.computeVertexNormals(); return g;
};
// 车削：给一串 [半径, 高] 转一圈（郁金香的杯子、瓶子）
export const lathe = (pts, seg = 12) => new THREE.LatheGeometry(pts.map(([x, y]) => new THREE.Vector2(x, y)), seg);
// 一个三角面片（山墙）
export function tri3(a, b, c) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute([...a, ...b, ...c], 3)); g.computeVertexNormals(); return g;
}
