// clawd 身上的衣服：在 3D 里是一层贴着身子的膜，不做体积。
// 衣服图跟身体用同一套 36 格图纸（rig：身子在第 left..right 列、第 top..legTop 行）：
// - 落在身子里的那块：做成一层贴膜包在身子上（衬衫、外套、围巾前后都包；眼镜、领结只贴正面；背包只贴背面）
// - 袖子那块（身子两边）：两只小手染成袖子的颜色
// - 裤腿、鞋（腿那几行）：腿染成那个颜色
// - 帽子（身子上面那几行）：一层贴在头顶的膜，颜色和花纹从帽子图里取
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

function load(src) {
  return new Promise((ok) => { const im = new Image(); im.onload = () => ok(im); im.onerror = () => ok(null); im.src = src; });
}
// 缩成 grid 格（衣服图是 36 格放大 8 倍画的）
function pixels(im, grid) {
  const c = document.createElement('canvas'); c.width = grid; c.height = grid;
  const x = c.getContext('2d'); x.imageSmoothingEnabled = false; x.drawImage(im, 0, 0, grid, grid);
  return { w: grid, h: grid, d: x.getImageData(0, 0, grid, grid).data };
}
const at = (px, x, y) => { const i = (y * px.w + x) * 4; return [px.d[i], px.d[i + 1], px.d[i + 2], px.d[i + 3]]; };
// 一块里最多的那个颜色
function dominant(px, x0, y0, x1, y1) {
  const tally = new Map();
  for (let y = Math.max(0, y0); y <= Math.min(px.h - 1, y1); y++) for (let x = Math.max(0, x0); x <= Math.min(px.w - 1, x1); x++) {
    const [r, g, b, a] = at(px, x, y); if (a < 100) continue;
    const k = (r >> 4) + ',' + (g >> 4) + ',' + (b >> 4); const e = tally.get(k) || [0, 0, 0, 0];
    tally.set(k, [e[0] + 1, e[1] + r, e[2] + g, e[3] + b]);
  }
  let best = null; for (const v of tally.values()) if (!best || v[0] > best[0]) best = v;
  return best ? new THREE.Color().setRGB(best[1] / best[0] / 255, best[2] / best[0] / 255, best[3] / best[0] / 255, THREE.SRGBColorSpace) : null;
}
// 把图纸上一块（x0..x1, y0..y1）画成贴图，四周留一圈透明（贴膜外面就是透明的）
function regionTex(px, x0, y0, x1, y1) {
  const w = x1 - x0 + 1, h = y1 - y0 + 1, c = document.createElement('canvas'); c.width = w + 2; c.height = h + 2;
  const g = c.getContext('2d'), id = g.createImageData(w + 2, h + 2);
  let any = false;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const p = at(px, x0 + x, y0 + y); if (p[3] < 100) continue; any = true;
    const di = ((y + 1) * (w + 2) + x + 1) * 4; id.data[di] = p[0]; id.data[di + 1] = p[1]; id.data[di + 2] = p[2]; id.data[di + 3] = 255;
  }
  if (!any) return null;
  g.putImageData(id, 0, 0);
  const t = new THREE.CanvasTexture(c); t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter; t.colorSpace = THREE.SRGBColorSpace;
  return { tex: t, w: w + 2, h: h + 2 };
}
// 一层膜：比身子大一丝的圆角盒子，贴图从正面投过去（侧面顺着边上那一格延伸，像布包过去）
function film(size, center, region, { front = true, back = false } = {}) {
  const [W, H, D] = size;
  const geo = new RoundedBoxGeometry(W * 1.012, H * 1.012, D * 1.02, 6, Math.min(.15, H * .33));
  const pa = geo.attributes.position, na = geo.attributes.normal, uv = geo.attributes.uv;
  const pxU = 1 / region.w, pxV = 1 / region.h;
  for (let i = 0; i < pa.count; i++) {
    const x = pa.getX(i), y = pa.getY(i), nz = na.getZ(i);
    let u = .5 + x / W * (1 - 2 * pxU), v = .5 + y / H * (1 - 2 * pxV);
    u = Math.min(1 - pxU * 1.01, Math.max(pxU * 1.01, u)); v = Math.min(1 - pxV * 1.01, Math.max(pxV * 1.01, v));
    if (nz < -.35) { if (!back) { u = pxU * .5; v = pxV * .5; } else u = 1 - u; }   // 背面：要包就镜像过去，不包就落在透明的那一圈
    else if (nz > .35 && !front) { u = pxU * .5; v = pxV * .5; }
    uv.setXY(i, u, v);
  }
  const m = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: region.tex, transparent: true, alphaTest: .5, roughness: .55 }));
  m.position.set(...center);
  return m;
}

export async function dressClawd(him, wear, rig) {
  const u = him.userData, body = u.body, grid = rig.grid || 36;
  const L = rig.left, R = rig.right, T = rig.top, B = rig.legTop - 1;
  for (const w of wear) {
    const im = await load(w.png); if (!im) continue;
    const px = pixels(im, grid);
    if (w.slot === 'eyes') u.eyes.forEach((e) => (e.visible = false));
    // 身子那块：一层贴膜
    const reg = regionTex(px, L, T, R, B);
    if (reg) {
      const wrap = w.slot === 'body' || w.slot === 'outer' || w.slot === 'scarf';
      body.add(film([.62, .46, .44], [0, .23, 0], reg, { front: w.slot !== 'back', back: wrap || w.slot === 'back' }));
    }
    // 袖子：两只小手染色
    const left = dominant(px, 0, T, L - 1, B), right = dominant(px, R + 1, T, grid - 1, B);
    if (left && u.arms[0]) u.arms[0].material = new THREE.MeshStandardMaterial({ color: left, roughness: .55 });
    if (right && u.arms[1]) u.arms[1].material = new THREE.MeshStandardMaterial({ color: right, roughness: .55 });
    // 裤腿、鞋：腿染色
    const feet = dominant(px, 0, rig.legTop, grid - 1, grid - 1);
    if (feet) for (const l of u.legs) l.material = new THREE.MeshStandardMaterial({ color: feet, roughness: .55 });
    // 帽子：头顶一层膜（花纹从帽子图里取，压在头顶和正面上沿）
    const hat = regionTex(px, L - 2, 0, R + 2, T - 1);
    if (hat) {
      const cap = film([.62, .16, .44], [0, .4, 0], hat, { front: true, back: true });
      body.add(cap);
    }
  }
}
